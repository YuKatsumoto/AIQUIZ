"""Development-only network simulator.

Enabled with ``RELAY_NETSIM="lat=120,jit=40,stall_p=0.01,stall_ms=300,kill_after=0,kill_role=0"``.
``lat`` is one-way relay->client latency. ``kill_after`` drops each role's first
matched connection once (``kill_role`` 1=host, 2=guest, 0=both).
WebSocket rides on TCP, so loss is modelled as head-of-line stalls rather than
dropped frames. Delivery stays in order: each frame's due time is never earlier
than the previous frame's.
"""

from __future__ import annotations

import asyncio
import os
import random
import time
from dataclasses import dataclass
from typing import Awaitable, Callable, Optional


@dataclass(frozen=True)
class NetSimConfig:
    latency_ms: float = 0.0
    jitter_ms: float = 0.0
    stall_probability: float = 0.0
    stall_ms: float = 0.0
    kill_after_s: float = 0.0
    kill_role: str = ""

    @property
    def active(self) -> bool:
        return any((self.latency_ms, self.jitter_ms, self.stall_probability, self.kill_after_s))


def parse_netsim(spec: Optional[str]) -> NetSimConfig:
    if not spec:
        return NetSimConfig()
    values: dict[str, float] = {}
    for part in spec.split(","):
        if "=" not in part:
            continue
        key, raw = part.split("=", 1)
        try:
            values[key.strip()] = float(raw)
        except ValueError:
            continue
    return NetSimConfig(
        latency_ms=values.get("lat", 0.0),
        jitter_ms=values.get("jit", 0.0),
        stall_probability=values.get("stall_p", 0.0),
        stall_ms=values.get("stall_ms", 0.0),
        kill_after_s=values.get("kill_after", 0.0),
        kill_role={1.0: "host", 2.0: "guest"}.get(values.get("kill_role", 0.0), ""),
    )


def config_from_env() -> NetSimConfig:
    return parse_netsim(os.environ.get("RELAY_NETSIM"))


class DelayedSender:
    """Per-connection ordered outbound queue that applies simulated latency."""

    def __init__(self, config: NetSimConfig, send: Callable[[str], Awaitable[None]]):
        self._config = config
        self._send = send
        self._queue: asyncio.Queue[tuple[float, str]] = asyncio.Queue()
        self._last_due = 0.0
        self._task = asyncio.create_task(self._pump())

    def push(self, text: str) -> None:
        now = time.monotonic()
        delay = self._config.latency_ms + random.uniform(-1.0, 1.0) * self._config.jitter_ms
        if self._config.stall_probability > 0.0 and random.random() < self._config.stall_probability:
            delay += self._config.stall_ms
        due = max(now + max(0.0, delay) / 1000.0, self._last_due)
        self._last_due = due
        self._queue.put_nowait((due, text))

    async def _pump(self) -> None:
        while True:
            due, text = await self._queue.get()
            wait = due - time.monotonic()
            if wait > 0:
                await asyncio.sleep(wait)
            try:
                await self._send(text)
            except Exception:
                return

    def close(self) -> None:
        self._task.cancel()
