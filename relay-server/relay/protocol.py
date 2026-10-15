"""Protocol v2 constants and payload validation.

Every frame is a JSON text message shaped ``{"t": <type>, "d": <payload>}``.
The relay only parses the envelope; in-match payloads are forwarded verbatim.
"""

from __future__ import annotations

import re
from typing import Any, Optional

from .name_filter import sanitize_name

PROTO_VERSION = 2
MAX_MESSAGE_BYTES = 64 * 1024

# Messages each in-match role may send; the relay forwards them to the peer.
HOST_RELAY_TYPES = frozenset({"settings", "start", "snap", "quiz", "evt", "resync", "finish", "profile"})
GUEST_RELAY_TYPES = frozenset({"cmd", "ready", "req_resync", "profile"})

# Messages the relay itself consumes.
CONTROL_TYPES = frozenset({"hello", "queue", "friend_create", "friend_join", "cancel", "leave", "ping"})

SUBJECTS = ("算数", "理科", "国語", "社会", "英語")
MODES = ("TEN_QUESTIONS", "ENDLESS")
FRIEND_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
FRIEND_CODE_LENGTH = 5

# Profile values are preset ids plus one player-chosen name. The name is the only
# free text that crosses the relay, and only after sanitize_name() accepts it.
PROFILE_LIMITS = {"nick": 63, "hat": 31, "toon": 15}
EMOTE_LIMIT = 63
# Body colours travel as an opaque lowercase hex blob (the game's PlayerSkin compact
# code). Hex only, so it cannot carry free text; the client decodes and range-checks it.
SKIN_PATTERN = re.compile(r"(?:[0-9a-f]{2}){1,256}")


def grade_band(grade: int) -> int:
    """Grades 1-2, 3-4 and 5-6 queue together."""
    return (max(1, min(6, grade)) - 1) // 2


def _int_in(value: Any, low: int, high: int) -> Optional[int]:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = int(value)
    if number < low or number > high:
        return None
    return number


def sanitize_profile(raw: Any = None) -> dict:
    profile = {"nick": 0, "name": "", "hat": 0, "toon": 0, "emotes": [1, 2, 3]}
    if not isinstance(raw, dict):
        return profile
    profile["name"] = sanitize_name(raw.get("name"))
    for key, limit in PROFILE_LIMITS.items():
        value = _int_in(raw.get(key), 0, limit)
        if value is not None:
            profile[key] = value
    emotes = raw.get("emotes")
    if isinstance(emotes, list) and len(emotes) == 3:
        cleaned = [_int_in(e, 0, EMOTE_LIMIT) for e in emotes]
        if all(e is not None for e in cleaned):
            profile["emotes"] = cleaned
    # Only present when valid, so peers without a skin keep the original profile shape.
    skin = raw.get("skin")
    if isinstance(skin, str) and SKIN_PATTERN.fullmatch(skin):
        profile["skin"] = skin
    return profile


def sanitize_queue_request(raw: Any) -> Optional[dict]:
    """Validate the settings a player queues with. Returns None when invalid."""
    if not isinstance(raw, dict):
        return None
    subject = raw.get("subject")
    mode = raw.get("mode", "TEN_QUESTIONS")
    grade = _int_in(raw.get("grade"), 1, 6)
    difficulty = _int_in(raw.get("difficulty", 1), 0, 2)
    if subject not in SUBJECTS or mode not in MODES or grade is None or difficulty is None:
        return None
    return {"subject": subject, "grade": grade, "difficulty": difficulty, "mode": mode}


def normalize_friend_code(raw: Any) -> Optional[str]:
    if not isinstance(raw, str):
        return None
    code = raw.strip().upper()
    if len(code) != FRIEND_CODE_LENGTH or any(ch not in FRIEND_CODE_CHARS for ch in code):
        return None
    return code
