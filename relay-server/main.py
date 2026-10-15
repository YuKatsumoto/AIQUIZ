"""
AIQUIZ Online Relay Server (protocol v2)
=======================================
WebSocket relay for 1v1 quiz battles. Both players connect outbound, so no
port forwarding is needed. The relay pairs players (random queue or a private
friend code), forwards in-match messages between host and guest, and keeps a
match alive for a reconnect grace window when either side drops.

Endpoints:
  GET  /health   — Health check and counters
  WS   /ws       — Protocol v2 (first frame must be ``hello``)
  WS   /ws/{id}  — Legacy v1 path; replies "update required" and closes

State is in memory: deploy as a single instance (see deploy_cloud_run.sh).
"""

from __future__ import annotations

import asyncio
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from relay import protocol
from relay.hub import Client, Hub
from relay.netsim import config_from_env

hub: Hub


@asynccontextmanager
async def lifespan(_app: FastAPI):
    global hub
    hub = Hub(config_from_env())
    if hub.netsim.active:
        print(f"[relay] NETSIM active: {hub.netsim}")
    hub.start()
    yield
    await hub.shutdown()


app = FastAPI(title="AIQUIZ Relay", version="2.0.0", lifespan=lifespan)


def _client_ip(websocket: WebSocket) -> str:
    forwarded = websocket.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return websocket.client.host if websocket.client else "unknown"


@app.get("/health")
async def health():
    return {"status": "ok", "proto": protocol.PROTO_VERSION, **hub.stats()}


@app.websocket("/ws")
async def ws_v2(websocket: WebSocket):
    ip = _client_ip(websocket)
    await websocket.accept()
    if not hub.admit(ip):
        await websocket.send_text('{"t":"error","d":{"code":"too_many_connections"}}')
        await websocket.close(code=4029)
        return

    async def close(code: int) -> None:
        try:
            await asyncio.wait_for(websocket.close(code=code), timeout=2.0)
        except Exception:
            pass

    client = Client(id=uuid.uuid4().hex[:10], ip=ip, send_text=websocket.send_text, close=close)
    hub.register(client)
    kill_task = None
    if hub.netsim.kill_after_s > 0:
        kill_task = asyncio.create_task(_netsim_kill(client, hub.netsim.kill_after_s))
    try:
        while True:
            raw = await websocket.receive_text()
            await hub.handle(client, raw)
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        print(f"[relay] connection {client.id} error: {exc!r}")
    finally:
        if kill_task is not None:
            kill_task.cancel()
        await hub.unregister(client)


_netsim_killed: set[str] = set()


async def _netsim_kill(client: Client, after_s: float) -> None:
    """Dev only: drop each role's first matched connection once, to exercise reconnect."""
    await asyncio.sleep(after_s)
    role = client.role
    wanted = hub.netsim.kill_role in ("", role)
    if client.match is not None and wanted and role not in _netsim_killed:
        _netsim_killed.add(role)
        print(f"[relay] NETSIM killing {client.role} connection {client.id}")
        await client.close(4004)


@app.websocket("/ws/{legacy_room}")
async def ws_legacy(websocket: WebSocket, legacy_room: str):
    await websocket.accept()
    await websocket.send_text('{"type":"error","msg":"ゲームを最新版にアップデートしてください"}')
    await websocket.close(code=4001)
