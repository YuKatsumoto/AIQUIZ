"""
AIQUIZ Online Relay Server
==========================
Lightweight WebSocket relay for 1v1 quiz battles.
Both players connect outbound — no port forwarding required.
The relay forwards messages between matched players and broadcasts
snapshots simultaneously for equal latency.

Endpoints:
  GET  /health           — Health check
  GET  /rooms            — List open rooms
  WS   /ws/{room_id}     — Join / create a room via WebSocket
"""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from dataclasses import dataclass, field
from typing import Dict, Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

app = FastAPI(title="AIQUIZ Relay", version="1.0.0")

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Player:
    ws: WebSocket
    player_id: str  # "host" or "guest"
    name: str = ""
    joined_at: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)


@dataclass
class Room:
    room_id: str
    host: Optional[Player] = None
    guest: Optional[Player] = None
    created_at: float = field(default_factory=time.time)
    settings: dict = field(default_factory=dict)
    status: str = "waiting"  # waiting | full | playing | closed

    @property
    def player_count(self) -> int:
        return (1 if self.host else 0) + (1 if self.guest else 0)

    def other(self, player_id: str) -> Optional[Player]:
        if player_id == "host":
            return self.guest
        return self.host


rooms: Dict[str, Room] = {}

# ---------------------------------------------------------------------------
# Cleanup stale rooms (> 30 min idle)
# ---------------------------------------------------------------------------

ROOM_TTL = 1800  # 30 minutes


async def _cleanup_loop():
    while True:
        await asyncio.sleep(60)
        now = time.time()
        stale = [rid for rid, r in rooms.items()
                 if now - r.created_at > ROOM_TTL and r.status != "playing"]
        for rid in stale:
            rooms.pop(rid, None)


@app.on_event("startup")
async def _startup():
    asyncio.create_task(_cleanup_loop())


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok", "rooms": len(rooms)}


@app.get("/rooms")
async def list_rooms():
    """Return rooms that are waiting for a guest."""
    result = []
    for r in rooms.values():
        if r.status == "waiting":
            result.append({
                "room_id": r.room_id,
                "host_name": r.host.name if r.host else "",
                "settings": r.settings,
                "created_at": r.created_at,
            })
    return JSONResponse(result)


# ---------------------------------------------------------------------------
# WebSocket relay
# ---------------------------------------------------------------------------

@app.websocket("/ws/{room_id}")
async def ws_relay(websocket: WebSocket, room_id: str):
    await websocket.accept()

    room = rooms.get(room_id)
    player_id: str

    # --- Join or create room ---
    if room is None:
        # First connection: become host, create room
        room = Room(room_id=room_id)
        player_id = "host"
        player = Player(ws=websocket, player_id=player_id)
        room.host = player
        rooms[room_id] = room
        await _send(websocket, {"type": "room_created", "room_id": room_id,
                                "role": "host"})
    elif room.guest is None and room.status == "waiting":
        # Second connection: become guest
        player_id = "guest"
        player = Player(ws=websocket, player_id=player_id)
        room.guest = player
        room.status = "full"
        await _send(websocket, {"type": "room_joined", "room_id": room_id,
                                "role": "guest"})
        # Notify host that guest arrived
        if room.host:
            await _send(room.host.ws, {"type": "guest_joined"})
    else:
        await _send(websocket, {"type": "error", "msg": "Room is full"})
        await websocket.close()
        return

    # --- Message loop ---
    try:
        while True:
            raw = await websocket.receive_text()
            player_obj = room.host if player_id == "host" else room.guest
            if player_obj:
                player_obj.last_seen = time.time()

            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get("type", "")

            if msg_type == "settings":
                # Host broadcasts game settings
                room.settings = msg.get("data", {})
                if player_id == "host" and room.guest:
                    await _send(room.guest.ws, msg)

            elif msg_type == "start":
                # Host starts the game
                room.status = "playing"
                await _broadcast(room, msg)

            elif msg_type == "snapshot":
                # Host sends game state snapshot → broadcast to BOTH
                await _broadcast(room, msg)

            elif msg_type == "input":
                # Guest sends input → forward to host only
                if player_id == "guest" and room.host:
                    await _send(room.host.ws, msg)

            elif msg_type == "quiz":
                # Host sends quiz data → broadcast to both
                await _broadcast(room, msg)

            elif msg_type == "event":
                # Game events (correct, wrong, game_over, clear) → broadcast
                await _broadcast(room, msg)

            elif msg_type == "player_info":
                # Exchange player info (name, hat, emotes)
                if player_obj:
                    player_obj.name = msg.get("name", "")
                other = room.other(player_id)
                if other:
                    await _send(other.ws, msg)

            elif msg_type == "chat":
                # Simple text chat relay
                other = room.other(player_id)
                if other:
                    await _send(other.ws, msg)

            elif msg_type == "ping":
                await _send(websocket, {"type": "pong",
                                        "ts": msg.get("ts", 0)})

            else:
                # Unknown: relay to other player
                other = room.other(player_id)
                if other:
                    await _send(other.ws, msg)

    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        # --- Cleanup on disconnect ---
        other = room.other(player_id)
        if other:
            try:
                await _send(other.ws, {"type": "peer_disconnected"})
            except Exception:
                pass

        if player_id == "host":
            room.host = None
        else:
            room.guest = None

        if room.player_count == 0:
            rooms.pop(room_id, None)
        else:
            room.status = "waiting"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _send(ws: WebSocket, data: dict):
    try:
        await ws.send_text(json.dumps(data, ensure_ascii=False))
    except Exception:
        pass


async def _broadcast(room: Room, data: dict):
    """Send to both players simultaneously for equal latency."""
    text = json.dumps(data, ensure_ascii=False)
    tasks = []
    if room.host:
        tasks.append(room.host.ws.send_text(text))
    if room.guest:
        tasks.append(room.guest.ws.send_text(text))
    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)
