"""Connection registry, matchmaking queue and match lifecycle.

Everything runs on one asyncio loop, so state is mutated without locks. Rooms
live in memory: the Cloud Run service must run as a single instance.
"""

from __future__ import annotations

import asyncio
import json
import os
import secrets
import time
import uuid
from dataclasses import dataclass, field
from typing import Awaitable, Callable, Dict, List, Optional

from . import protocol
from .netsim import DelayedSender, NetSimConfig

def _env_seconds(name: str, default: float) -> float:
    """Timing knobs are overridable so tests can shrink them."""
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


HELLO_TIMEOUT_S = 10.0
HEARTBEAT_TIMEOUT_S = _env_seconds("RELAY_HEARTBEAT_S", 6.0)
RECONNECT_GRACE_S = _env_seconds("RELAY_GRACE_S", 30.0)
QUEUE_WIDEN_AFTER_S = _env_seconds("RELAY_WIDEN_S", 20.0)
QUEUE_EXPIRE_S = _env_seconds("RELAY_QUEUE_EXPIRE_S", 120.0)
FRIEND_CODE_EXPIRE_S = 600.0
FINISHED_MATCH_TTL_S = 60.0
MATCH_MAX_AGE_S = 45 * 60.0
MAX_CONNECTIONS_PER_IP = 64
MAX_RATE_VIOLATIONS = 200


class TokenBucket:
    def __init__(self, rate: float, burst: float):
        self.rate = rate
        self.burst = burst
        self.tokens = burst
        self.stamp = time.monotonic()

    def take(self) -> bool:
        now = time.monotonic()
        self.tokens = min(self.burst, self.tokens + (now - self.stamp) * self.rate)
        self.stamp = now
        if self.tokens < 1.0:
            return False
        self.tokens -= 1.0
        return True


@dataclass
class Client:
    id: str
    ip: str
    send_text: Callable[[str], Awaitable[None]]
    close: Callable[[int], Awaitable[None]]
    profile: dict = field(default_factory=protocol.sanitize_profile)
    greeted: bool = False
    last_seen: float = field(default_factory=time.monotonic)
    match: Optional["Match"] = None
    role: str = ""
    entry: Optional["QueueEntry"] = None
    detached: bool = False
    violations: int = 0
    general_bucket: TokenBucket = field(default_factory=lambda: TokenBucket(90.0, 120.0))
    cmd_bucket: TokenBucket = field(default_factory=lambda: TokenBucket(40.0, 60.0))
    sender: Optional[DelayedSender] = None

    async def send(self, msg_type: str, data: Optional[dict] = None) -> None:
        await self.send_raw(json.dumps({"t": msg_type, "d": data or {}}, ensure_ascii=False))

    async def send_raw(self, text: str) -> None:
        if self.sender is not None:
            self.sender.push(text)
            return
        try:
            await self.send_text(text)
        except Exception:
            pass


@dataclass
class QueueEntry:
    client: Client
    settings: dict
    friend_code: str = ""
    enqueued_at: float = field(default_factory=time.monotonic)

    def waited(self, now: float) -> float:
        return now - self.enqueued_at


@dataclass
class Match:
    id: str
    settings: dict
    tokens: Dict[str, str]
    profiles: Dict[str, dict]
    slots: Dict[str, Optional[Client]]
    status: str = "active"  # active | finished
    created_at: float = field(default_factory=time.monotonic)
    finished_at: float = 0.0
    grace_tasks: Dict[str, asyncio.Task] = field(default_factory=dict)

    @staticmethod
    def other_role(role: str) -> str:
        return "guest" if role == "host" else "host"

    def peer(self, role: str) -> Optional[Client]:
        return self.slots.get(self.other_role(role))


class Hub:
    def __init__(self, netsim: NetSimConfig):
        self.netsim = netsim
        self.clients: Dict[str, Client] = {}
        self.queue: List[QueueEntry] = []
        self.friend_rooms: Dict[str, QueueEntry] = {}
        self.matches: Dict[str, Match] = {}
        self.tokens: Dict[str, tuple[str, str]] = {}
        self.ip_counts: Dict[str, int] = {}
        self._tasks: List[asyncio.Task] = []

    # ------------------------------------------------------------------ lifecycle

    def start(self) -> None:
        self._tasks.append(asyncio.create_task(self._maintenance_loop()))

    async def shutdown(self) -> None:
        for client in list(self.clients.values()):
            await client.send("server_restart")
        for task in self._tasks:
            task.cancel()

    def stats(self) -> dict:
        active = sum(1 for m in self.matches.values() if m.status == "active")
        return {
            "clients": len(self.clients),
            "queued": len(self.queue),
            "friend_rooms": len(self.friend_rooms),
            "matches": len(self.matches),
            "active_matches": active,
        }

    # ------------------------------------------------------------------ connections

    def admit(self, ip: str) -> bool:
        return self.ip_counts.get(ip, 0) < MAX_CONNECTIONS_PER_IP

    def register(self, client: Client) -> None:
        self.clients[client.id] = client
        self.ip_counts[client.ip] = self.ip_counts.get(client.ip, 0) + 1
        if self.netsim.active:
            client.sender = DelayedSender(self.netsim, client.send_text)

    async def unregister(self, client: Client) -> None:
        if self.clients.pop(client.id, None) is None:
            return
        remaining = self.ip_counts.get(client.ip, 1) - 1
        if remaining > 0:
            self.ip_counts[client.ip] = remaining
        else:
            self.ip_counts.pop(client.ip, None)
        if client.sender is not None:
            client.sender.close()
        self._leave_queue(client)
        if not client.detached and client.match is not None:
            await self._on_match_disconnect(client)

    # ------------------------------------------------------------------ messages

    async def handle(self, client: Client, raw: str) -> None:
        client.last_seen = time.monotonic()
        if len(raw.encode("utf-8")) > protocol.MAX_MESSAGE_BYTES:
            await client.send("error", {"code": "too_large"})
            await client.close(4009)
            return
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            return
        if not isinstance(msg, dict):
            return
        msg_type = msg.get("t")
        data = msg.get("d") if isinstance(msg.get("d"), dict) else {}

        if not client.greeted:
            if msg_type != "hello":
                await client.send("error", {"code": "hello_required"})
                await client.close(4002)
                return
            await self._on_hello(client, data)
            return

        if not self._rate_ok(client, msg_type):
            client.violations += 1
            if client.violations > MAX_RATE_VIOLATIONS:
                await client.send("error", {"code": "rate_limited"})
                await client.close(4008)
            return

        if msg_type == "ping":
            await client.send("pong", {"ts": data.get("ts", 0), "server_ms": int(time.time() * 1000)})
        elif msg_type == "queue":
            await self._on_queue(client, data)
        elif msg_type == "friend_create":
            await self._on_friend_create(client, data)
        elif msg_type == "friend_join":
            await self._on_friend_join(client, data)
        elif msg_type == "cancel":
            self._leave_queue(client)
            await client.send("cancelled")
        elif msg_type == "leave":
            await self._on_leave(client)
        elif client.match is not None:
            await self._relay(client, msg_type, raw)

    def _rate_ok(self, client: Client, msg_type: str) -> bool:
        if not client.general_bucket.take():
            return False
        if msg_type == "cmd" and not client.cmd_bucket.take():
            return False
        return True

    async def _on_hello(self, client: Client, data: dict) -> None:
        proto = data.get("proto")
        if proto != protocol.PROTO_VERSION:
            await client.send("update_required", {"proto": protocol.PROTO_VERSION})
            await client.close(4001)
            return
        client.greeted = True
        client.profile = protocol.sanitize_profile(data.get("profile"))
        await client.send("welcome", {"proto": protocol.PROTO_VERSION, "client_id": client.id})
        resume = data.get("resume")
        if isinstance(resume, dict):
            await self._resume(client, resume)

    # ------------------------------------------------------------------ queue

    async def _on_queue(self, client: Client, data: dict) -> None:
        if client.match is not None:
            await client.send("error", {"code": "already_in_match"})
            return
        settings = protocol.sanitize_queue_request(data)
        if settings is None:
            await client.send("error", {"code": "bad_settings"})
            return
        self._leave_queue(client)
        entry = QueueEntry(client=client, settings=settings)
        client.entry = entry
        self.queue.append(entry)
        await client.send("queued", {"widen_after_s": QUEUE_WIDEN_AFTER_S, "expire_s": QUEUE_EXPIRE_S})
        await self._try_match_queue()

    def _compatible(self, a: QueueEntry, b: QueueEntry, now: float) -> bool:
        sa, sb = a.settings, b.settings
        if sa["mode"] != sb["mode"]:
            return False
        if protocol.grade_band(sa["grade"]) != protocol.grade_band(sb["grade"]):
            return False
        if sa["subject"] == sb["subject"]:
            return True
        return max(a.waited(now), b.waited(now)) >= QUEUE_WIDEN_AFTER_S

    async def _try_match_queue(self) -> None:
        now = time.monotonic()
        matched = True
        while matched:
            matched = False
            for i, older in enumerate(self.queue):
                for newer in self.queue[i + 1:]:
                    if self._compatible(older, newer, now):
                        self.queue.remove(older)
                        self.queue.remove(newer)
                        older.client.entry = None
                        newer.client.entry = None
                        await self._create_match(older, newer)
                        matched = True
                        break
                if matched:
                    break

    async def _on_friend_create(self, client: Client, data: dict) -> None:
        if client.match is not None:
            await client.send("error", {"code": "already_in_match"})
            return
        settings = protocol.sanitize_queue_request(data)
        if settings is None:
            await client.send("error", {"code": "bad_settings"})
            return
        self._leave_queue(client)
        code = self._new_friend_code()
        entry = QueueEntry(client=client, settings=settings, friend_code=code)
        client.entry = entry
        self.friend_rooms[code] = entry
        await client.send("friend_code", {"code": code, "expire_s": FRIEND_CODE_EXPIRE_S})

    async def _on_friend_join(self, client: Client, data: dict) -> None:
        if client.match is not None:
            await client.send("error", {"code": "already_in_match"})
            return
        code = protocol.normalize_friend_code(data.get("code"))
        host_entry = self.friend_rooms.get(code or "")
        if host_entry is None or host_entry.client is client:
            await client.send("error", {"code": "friend_not_found"})
            return
        self._leave_queue(client)
        self.friend_rooms.pop(host_entry.friend_code, None)
        host_entry.client.entry = None
        guest_entry = QueueEntry(client=client, settings=host_entry.settings)
        await self._create_match(host_entry, guest_entry)

    def _new_friend_code(self) -> str:
        while True:
            code = "".join(secrets.choice(protocol.FRIEND_CODE_CHARS) for _ in range(protocol.FRIEND_CODE_LENGTH))
            if code not in self.friend_rooms:
                return code

    def _leave_queue(self, client: Client) -> None:
        entry = client.entry
        if entry is None:
            return
        client.entry = None
        if entry in self.queue:
            self.queue.remove(entry)
        if entry.friend_code and self.friend_rooms.get(entry.friend_code) is entry:
            self.friend_rooms.pop(entry.friend_code, None)

    # ------------------------------------------------------------------ matches

    async def _create_match(self, host_entry: QueueEntry, guest_entry: QueueEntry) -> None:
        host, guest = host_entry.client, guest_entry.client
        match = Match(
            id=uuid.uuid4().hex[:12],
            settings=dict(host_entry.settings),
            tokens={"host": secrets.token_urlsafe(18), "guest": secrets.token_urlsafe(18)},
            profiles={"host": host.profile, "guest": guest.profile},
            slots={"host": host, "guest": guest},
        )
        self.matches[match.id] = match
        for role, client in match.slots.items():
            self.tokens[match.tokens[role]] = (match.id, role)
            client.match = match
            client.role = role
        for role in ("host", "guest"):
            await self._send_match_info(match, role, "matched")

    async def _send_match_info(self, match: Match, role: str, msg_type: str) -> None:
        client = match.slots.get(role)
        if client is None:
            return
        await client.send(msg_type, {
            "match_id": match.id,
            "role": role,
            "token": match.tokens[role],
            "settings": match.settings,
            "you": match.profiles[role],
            "opponent": match.profiles[Match.other_role(role)],
            "peer_present": match.peer(role) is not None,
            "grace_s": RECONNECT_GRACE_S,
        })

    async def _relay(self, client: Client, msg_type: str, raw: str) -> None:
        match = client.match
        allowed = protocol.HOST_RELAY_TYPES if client.role == "host" else protocol.GUEST_RELAY_TYPES
        if match is None or msg_type not in allowed:
            return
        if msg_type == "profile":
            # Re-encode profile updates so only sanitized preset ids reach the peer.
            try:
                payload = json.loads(raw).get("d")
            except (json.JSONDecodeError, AttributeError):
                return
            match.profiles[client.role] = protocol.sanitize_profile(payload)
            peer = match.peer(client.role)
            if peer is not None:
                await peer.send("profile", match.profiles[client.role])
            return
        if msg_type == "finish" and match.status == "active":
            match.status = "finished"
            match.finished_at = time.monotonic()
        peer = match.peer(client.role)
        if peer is not None:
            await peer.send_raw(raw)

    async def _on_leave(self, client: Client) -> None:
        match = client.match
        if match is None:
            self._leave_queue(client)
            return
        role = client.role
        peer = match.peer(role)
        if match.status == "active":
            match.status = "finished"
            match.finished_at = time.monotonic()
            if peer is not None:
                await peer.send("forfeit", {"winner": Match.other_role(role), "reason": "left"})
        elif peer is not None:
            await peer.send("peer_left", {"who": role})
        self._detach(client)

    def _detach(self, client: Client) -> None:
        match = client.match
        if match is not None and match.slots.get(client.role) is client:
            match.slots[client.role] = None
        client.match = None
        client.role = ""
        if match is not None and all(slot is None for slot in match.slots.values()):
            self._drop_match(match)

    def _drop_match(self, match: Match) -> None:
        for task in match.grace_tasks.values():
            task.cancel()
        for token in match.tokens.values():
            self.tokens.pop(token, None)
        self.matches.pop(match.id, None)

    async def _on_match_disconnect(self, client: Client) -> None:
        match = client.match
        role = client.role
        if match is None:
            return
        if match.status != "active":
            peer = match.peer(role)
            if peer is not None:
                await peer.send("peer_left", {"who": role})
            self._detach(client)
            return
        match.slots[role] = None
        client.match = None
        peer = match.peer(role)
        if peer is None:
            # Both sides are gone; keep the match for the grace window in case either resumes.
            pass
        else:
            await peer.send("peer_paused", {"who": role, "grace_s": RECONNECT_GRACE_S})
        previous = match.grace_tasks.pop(role, None)
        if previous is not None:
            previous.cancel()
        match.grace_tasks[role] = asyncio.create_task(self._grace_expire(match, role))

    async def _grace_expire(self, match: Match, role: str) -> None:
        try:
            await asyncio.sleep(RECONNECT_GRACE_S)
        except asyncio.CancelledError:
            return
        match.grace_tasks.pop(role, None)
        if match.slots.get(role) is not None or match.id not in self.matches:
            return
        peer = match.peer(role)
        if match.status == "active":
            match.status = "finished"
            match.finished_at = time.monotonic()
            if peer is not None:
                await peer.send("forfeit", {"winner": Match.other_role(role), "reason": "timeout"})
        if all(slot is None for slot in match.slots.values()):
            self._drop_match(match)

    async def _resume(self, client: Client, resume: dict) -> None:
        token = resume.get("token")
        found = self.tokens.get(token) if isinstance(token, str) else None
        match = self.matches.get(found[0]) if found else None
        if match is None or found is None or found[0] != resume.get("match_id"):
            await client.send("resume_failed", {"reason": "unknown_match"})
            return
        role = found[1]
        if match.status != "active":
            await client.send("resume_failed", {"reason": "finished"})
            return
        stale = match.slots.get(role)
        if stale is not None and stale is not client:
            # Half-open socket from before the drop: retire it without pausing the match.
            stale.detached = True
            stale.match = None
            asyncio.create_task(stale.close(4003))
        grace = match.grace_tasks.pop(role, None)
        if grace is not None:
            grace.cancel()
        match.slots[role] = client
        client.match = match
        client.role = role
        client.profile = match.profiles[role]
        await self._send_match_info(match, role, "resumed")
        peer = match.peer(role)
        if peer is not None:
            await peer.send("peer_resumed", {"who": role})

    # ------------------------------------------------------------------ maintenance

    async def _maintenance_loop(self) -> None:
        while True:
            await asyncio.sleep(1.0)
            try:
                await self._maintenance_tick()
            except Exception as exc:  # keep the loop alive no matter what
                print(f"[relay] maintenance error: {exc!r}")

    async def _maintenance_tick(self) -> None:
        now = time.monotonic()
        for client in list(self.clients.values()):
            limit = HEARTBEAT_TIMEOUT_S if client.greeted else HELLO_TIMEOUT_S
            if now - client.last_seen > limit:
                asyncio.create_task(client.close(4000))
                await self.unregister(client)
        for entry in list(self.queue):
            if entry.waited(now) >= QUEUE_EXPIRE_S:
                self._leave_queue(entry.client)
                await entry.client.send("queue_timeout")
        for code, entry in list(self.friend_rooms.items()):
            if entry.waited(now) >= FRIEND_CODE_EXPIRE_S:
                self._leave_queue(entry.client)
                await entry.client.send("queue_timeout")
        # Widening is time based, so re-run matching even without new arrivals.
        await self._try_match_queue()
        for match in list(self.matches.values()):
            expired_finished = match.status == "finished" and now - match.finished_at > FINISHED_MATCH_TTL_S
            if expired_finished or now - match.created_at > MATCH_MAX_AGE_S:
                for client in list(match.slots.values()):
                    if client is not None:
                        client.match = None
                        client.role = ""
                self._drop_match(match)
