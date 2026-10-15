"""Relay v2 integration tests.

Starts the real relay with uvicorn (shortened timers) and drives it over real
WebSockets. Runs with plain ``python tests/test_relay.py``; pytest also collects
the ``test_*`` coroutines through ``test_all``.
"""

from __future__ import annotations

import asyncio
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import websockets

ROOT = Path(__file__).resolve().parents[1]
TIMERS = {"RELAY_GRACE_S": "2", "RELAY_WIDEN_S": "1", "RELAY_QUEUE_EXPIRE_S": "3", "RELAY_HEARTBEAT_S": "2"}
BASE_SETTINGS = {"subject": "算数", "grade": 3, "difficulty": 1, "mode": "TEN_QUESTIONS"}


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Peer:
    def __init__(self, url: str):
        self.url = url
        self.ws = None
        self.inbox: asyncio.Queue = asyncio.Queue()
        self._reader = None
        self._pinger = None

    async def connect(self, hello: bool = True, profile: dict | None = None, resume: dict | None = None, ping: bool = True):
        self.ws = await websockets.connect(self.url)
        self._reader = asyncio.create_task(self._read())
        if hello:
            payload = {"proto": 2, "build": "test", "profile": profile or {"nick": 3}}
            if resume:
                payload["resume"] = resume
            await self.send("hello", payload)
            await self.expect("welcome")
        if ping:
            self._pinger = asyncio.create_task(self._ping())
        return self

    async def _read(self):
        try:
            async for raw in self.ws:
                msg = json.loads(raw)
                if msg.get("t") != "pong":
                    await self.inbox.put(msg)
        except websockets.ConnectionClosed:
            pass
        await self.inbox.put({"t": "__closed__", "d": {"code": self.ws.close_code}})

    async def _ping(self):
        try:
            while True:
                await self.send("ping", {"ts": int(time.time() * 1000)})
                await asyncio.sleep(0.5)
        except Exception:
            pass

    def stop_ping(self):
        if self._pinger:
            self._pinger.cancel()

    async def send(self, t: str, d: dict | None = None):
        await self.ws.send(json.dumps({"t": t, "d": d or {}}))

    async def expect(self, t: str, timeout: float = 3.0) -> dict:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f"timed out waiting for {t}")
            msg = await asyncio.wait_for(self.inbox.get(), remaining)
            if msg.get("t") == t:
                return msg.get("d", {})

    async def nothing(self, t: str, wait: float = 0.6):
        deadline = time.monotonic() + wait
        while time.monotonic() < deadline:
            try:
                msg = await asyncio.wait_for(self.inbox.get(), deadline - time.monotonic())
            except asyncio.TimeoutError:
                return
            assert msg.get("t") != t, f"unexpected {t}: {msg}"

    async def close(self):
        self.stop_ping()
        if self.ws:
            await self.ws.close()


async def matched_pair(url: str, settings_a=None, settings_b=None):
    a = await Peer(url).connect(profile={"nick": 1, "hat": 2, "toon": 1, "emotes": [4, 5, 6]})
    b = await Peer(url).connect(profile={"nick": 2})
    await a.send("queue", settings_a or BASE_SETTINGS)
    await a.expect("queued")
    await b.send("queue", settings_b or BASE_SETTINGS)
    ma = await a.expect("matched")
    mb = await b.expect("matched")
    return a, b, ma, mb


# ---------------------------------------------------------------------- tests

async def test_version_gate(url):
    p = await Peer(url).connect(hello=False, ping=False)
    await p.send("hello", {"proto": 1})
    await p.expect("update_required")
    assert (await p.expect("__closed__"))["code"] == 4001
    q = await Peer(url).connect(hello=False, ping=False)
    await q.send("queue", BASE_SETTINGS)
    await q.expect("error")
    await q.expect("__closed__")


async def test_random_match_same_subject(url):
    a, b, ma, mb = await matched_pair(url)
    assert ma["role"] == "host" and mb["role"] == "guest"
    assert ma["match_id"] == mb["match_id"]
    assert ma["token"] != mb["token"]
    assert mb["settings"] == BASE_SETTINGS
    assert mb["opponent"] == {"nick": 1, "name": "", "hat": 2, "toon": 1, "emotes": [4, 5, 6]}
    assert ma["opponent"]["nick"] == 2
    await a.close(); await b.close()


async def test_widen_subject_within_band(url):
    a = await Peer(url).connect()
    b = await Peer(url).connect()
    await a.send("queue", {**BASE_SETTINGS, "subject": "国語", "grade": 5})
    await a.expect("queued")
    await b.send("queue", {**BASE_SETTINGS, "subject": "理科", "grade": 6})
    await b.expect("queued")
    await b.nothing("matched", 0.4)
    mb = await b.expect("matched", 3.0)
    assert mb["role"] == "guest" and mb["settings"]["subject"] == "国語" and mb["settings"]["grade"] == 5
    await a.close(); await b.close()


async def test_band_mismatch_expires(url):
    a = await Peer(url).connect()
    b = await Peer(url).connect()
    await a.send("queue", {**BASE_SETTINGS, "grade": 1})
    await b.send("queue", {**BASE_SETTINGS, "grade": 6})
    await a.expect("queue_timeout", 6.0)
    await b.expect("queue_timeout", 6.0)
    await a.close(); await b.close()


async def test_bad_settings_rejected(url):
    a = await Peer(url).connect()
    await a.send("queue", {"subject": "体育", "grade": 3})
    assert (await a.expect("error"))["code"] == "bad_settings"
    await a.close()


async def test_role_allowlist_and_routing(url):
    host, guest, _, _ = await matched_pair(url)
    await guest.send("snap", {"x": 1})
    await guest.send("chat", {"text": "hi"})
    await guest.send("cmd", {"seq": 1})
    got = await host.expect("cmd")
    assert got == {"seq": 1}
    await host.nothing("snap", 0.3)
    await host.nothing("chat", 0.1)
    await host.send("snap", {"tick": 5})
    assert (await guest.expect("snap"))["tick"] == 5
    await host.nothing("snap", 0.3)  # no echo back to the sender
    await host.send("cmd", {"seq": 9})
    await guest.nothing("cmd", 0.3)
    await host.close(); await guest.close()


async def test_profile_sanitized(url):
    a = await Peer(url).connect(profile={"nick": "わるいことば", "hat": 999, "emotes": ["x"]})
    b = await Peer(url).connect()
    await a.send("queue", BASE_SETTINGS)
    await b.send("queue", BASE_SETTINGS)
    mb = await b.expect("matched")
    assert mb["opponent"] == {"nick": 0, "name": "", "hat": 0, "toon": 0, "emotes": [1, 2, 3]}
    await a.expect("matched")
    await a.send("profile", {"nick": 7, "name": "free text", "emotes": [9, 9, 9]})
    prof = await b.expect("profile")
    assert prof == {"nick": 7, "name": "", "hat": 0, "toon": 0, "emotes": [9, 9, 9]}
    await a.close(); await b.close()


SKIN_CODE = "02" + "ab" * 21  # game PlayerSkin code: version + 7 parts x RGB


def test_skin_profile_rules():
    sys.path.insert(0, str(ROOT))
    from relay.protocol import sanitize_profile
    assert sanitize_profile({"skin": SKIN_CODE})["skin"] == SKIN_CODE
    assert "skin" not in sanitize_profile({})
    for bad in ["", SKIN_CODE.upper(), SKIN_CODE + "0", "zz" + SKIN_CODE[2:], "ab" * 257, "01 02", None, 12, ["01"], {"a": 1}]:
        assert "skin" not in sanitize_profile({"skin": bad}), bad


async def test_skin_reaches_peer(url):
    a = await Peer(url).connect(profile={"nick": 1, "skin": SKIN_CODE})
    b = await Peer(url).connect(profile={"nick": 2, "skin": "NOT HEX"})
    await a.send("queue", BASE_SETTINGS)
    await b.send("queue", BASE_SETTINGS)
    ma = await a.expect("matched")
    mb = await b.expect("matched")
    assert mb["opponent"]["skin"] == SKIN_CODE
    assert "skin" not in ma["opponent"]
    await b.send("profile", {"nick": 2, "skin": "02" * 22})
    assert (await a.expect("profile"))["skin"] == "02" * 22
    await a.close(); await b.close()


async def test_player_names(url):
    a = await Peer(url).connect(profile={"nick": 1, "name": "でんせつのパンダ"})
    b = await Peer(url).connect(profile={"nick": 2, "name": "シネシネ"})
    await a.send("queue", BASE_SETTINGS)
    await b.send("queue", BASE_SETTINGS)
    ma = await a.expect("matched")
    mb = await b.expect("matched")
    assert mb["opponent"]["name"] == "でんせつのパンダ"
    assert ma["opponent"]["name"] == "" and ma["opponent"]["nick"] == 2  # NG word never reaches the peer
    assert mb["you"]["name"] == ""  # the sender learns its name was replaced
    await a.send("profile", {"nick": 1, "name": "ＡＢＣ１２"})
    assert (await b.expect("profile"))["name"] == "ABC12"  # full-width normalised
    await a.send("profile", {"nick": 1, "name": "090-1234"})
    assert (await b.expect("profile"))["name"] == ""
    await a.close(); await b.close()


def test_name_filter_rules():
    sys.path.insert(0, str(ROOT))
    from relay.name_filter import sanitize_name
    assert sanitize_name("でんせつのパンダ") == "でんせつのパンダ"
    assert sanitize_name("九九マスター★") == "九九マスター★"
    assert sanitize_name("  たろう  ") == "たろう"
    for bad in ["", "a" * 13, "た ろう", "ばか", "バカ", "ば-か", "しーね", "ｼﾈ", "Fuck", "1234",
                "さくら小学校", "<script>", "たろう😀", None, 12]:
        assert sanitize_name(bad) == "", bad


def test_ng_lists_match_game():
    """The game's NetNameFilter and the relay must reject the same words."""
    import re
    sys.path.insert(0, str(ROOT))
    from relay.name_filter import NG_WORDS
    gd = ROOT.parent / "AIQUIZ-Godot" / "scripts" / "core" / "net" / "net_name_filter.gd"
    if not gd.exists():
        return
    block = gd.read_text(encoding="utf-8").split("NG_WORDS_BEGIN")[1].split("NG_WORDS_END")[0]
    assert tuple(re.findall(r'"([^"]+)"', block)) == NG_WORDS


async def test_friend_code(url):
    a = await Peer(url).connect()
    b = await Peer(url).connect()
    c = await Peer(url).connect()
    await a.send("friend_create", {**BASE_SETTINGS, "subject": "英語", "grade": 4})
    code = (await a.expect("friend_code"))["code"]
    assert len(code) == 5
    await b.send("friend_join", {"code": "ZZZZZ" if code != "ZZZZZ" else "YYYYY"})
    assert (await b.expect("error"))["code"] == "friend_not_found"
    # Friend rooms never leak into the random queue.
    await c.send("queue", {**BASE_SETTINGS, "subject": "英語", "grade": 4})
    await c.nothing("matched", 1.5)
    await b.send("friend_join", {"code": code.lower()})
    mb = await b.expect("matched")
    ma = await a.expect("matched")
    assert ma["role"] == "host" and mb["role"] == "guest" and mb["settings"]["subject"] == "英語"
    await a.close(); await b.close(); await c.close()


async def test_resume_within_grace(url):
    host, guest, _, mg = await matched_pair(url)
    await guest.close()
    paused = await host.expect("peer_paused")
    assert paused["who"] == "guest"
    bad = await Peer(url).connect(resume={"match_id": mg["match_id"], "token": "nope"})
    await bad.expect("resume_failed")
    await bad.close()
    again = await Peer(url).connect(resume={"match_id": mg["match_id"], "token": mg["token"]})
    resumed = await again.expect("resumed")
    assert resumed["role"] == "guest" and resumed["peer_present"] is True
    assert (await host.expect("peer_resumed"))["who"] == "guest"
    await again.send("cmd", {"seq": 2})
    assert (await host.expect("cmd"))["seq"] == 2
    await host.nothing("forfeit", 2.5)  # grace timer was cancelled
    await host.close(); await again.close()


async def test_grace_expiry_forfeits(url):
    host, guest, _, _ = await matched_pair(url)
    await host.close()
    await guest.expect("peer_paused")
    result = await guest.expect("forfeit", 4.0)
    assert result == {"winner": "guest", "reason": "timeout"}
    await guest.close()


async def test_leave_forfeits_immediately(url):
    host, guest, _, _ = await matched_pair(url)
    await guest.send("leave")
    assert (await host.expect("forfeit")) == {"winner": "host", "reason": "left"}
    await host.close(); await guest.close()


async def test_finished_match_no_pause(url):
    host, guest, _, _ = await matched_pair(url)
    await host.send("finish", {"winner": 1})
    await guest.expect("finish")
    await host.close()
    assert (await guest.expect("peer_left"))["who"] == "host"
    await guest.nothing("peer_paused", 0.3)
    await guest.close()


async def test_heartbeat_timeout(url):
    host, guest, _, _ = await matched_pair(url)
    guest.stop_ping()
    paused = await host.expect("peer_paused", 5.0)
    assert paused["who"] == "guest"
    await host.close(); await guest.close()


async def test_rate_limit(url):
    host, guest, _, _ = await matched_pair(url)
    for i in range(300):
        await guest.send("cmd", {"seq": i})
    received = 0
    deadline = time.monotonic() + 1.0
    while time.monotonic() < deadline:
        try:
            msg = await asyncio.wait_for(host.inbox.get(), 0.2)
        except asyncio.TimeoutError:
            break
        if msg.get("t") == "cmd":
            received += 1
    assert 40 <= received <= 120, received
    await host.close(); await guest.close()


async def test_legacy_path(url):
    legacy = url.replace("/ws", "/ws/ABCD")
    async with websockets.connect(legacy) as ws:
        msg = json.loads(await ws.recv())
        assert msg["type"] == "error"


TESTS = [v for k, v in sorted(globals().items()) if k.startswith("test_") and asyncio.iscoroutinefunction(v)]


SYNC_TESTS = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)
              and not asyncio.iscoroutinefunction(v) and k != "test_all"]


async def _run_all(url: str) -> list[str]:
    failures = []
    for test in SYNC_TESTS:
        try:
            test()
            print(f"PASS {test.__name__}")
        except Exception as exc:
            failures.append(test.__name__)
            print(f"FAIL {test.__name__}: {exc!r}")
    for test in TESTS:
        started = time.monotonic()
        try:
            await asyncio.wait_for(test(url), 20)
            print(f"PASS {test.__name__} ({time.monotonic() - started:.1f}s)")
        except Exception as exc:
            failures.append(test.__name__)
            print(f"FAIL {test.__name__}: {exc!r}")
    return failures


def _start_server(port: int, extra_env: dict | None = None) -> subprocess.Popen:
    env = {**os.environ, **TIMERS, **(extra_env or {})}
    proc = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", str(port), "--log-level", "warning"],
        cwd=ROOT, env=env,
    )
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1) as resp:
                if resp.status == 200:
                    return proc
        except Exception:
            time.sleep(0.2)
    proc.kill()
    raise RuntimeError("relay did not start")


def main() -> int:
    port = _free_port()
    proc = _start_server(port)
    try:
        failures = asyncio.run(_run_all(f"ws://127.0.0.1:{port}/ws"))
    finally:
        proc.terminate()
        proc.wait(10)
    total = len(TESTS) + len(SYNC_TESTS)
    print(f"{total - len(failures)}/{total} passed")
    return 1 if failures else 0


def test_all():
    assert main() == 0


if __name__ == "__main__":
    raise SystemExit(main())
