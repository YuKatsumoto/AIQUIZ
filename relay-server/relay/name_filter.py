"""Player-chosen names, validated before any other child can see them.

Mirrors AIQUIZ-Godot/scripts/core/net/net_name_filter.gd. The game checks first so
the child gets an immediate reason; the relay checks again because a modified
client could skip that. tests/test_relay.py asserts both NG lists are identical.
"""

from __future__ import annotations

import unicodedata

MAX_LENGTH = 12
MAX_DIGITS = 3

# NG_WORDS_BEGIN (hiragana / lowercase ascii; names are folded the same way first)
NG_WORDS = (
    "しね", "しんで", "ころす", "ころせ", "ころして", "きえろ", "きもい", "きしょい", "うざ",
    "ばか", "あほ", "くず", "ごみ", "ぶす", "でぶ", "ぶさいく", "のろま", "ざこ", "くそ",
    "うんこ", "うんち", "ちんこ", "ちんちん", "まんこ", "おっぱい", "せっくす", "えっち", "えろ",
    "ぱんつ", "へんたい", "ちかん", "ばばあ", "じじい", "きちがい", "がいじ",
    "死", "殺", "糞", "馬鹿", "阿呆", "屑", "変態", "痴漢", "乳",
    "がっこう", "学校", "しょうがく", "小学", "ちゅうがく", "中学",
    "fuck", "shit", "sex", "porn", "kill", "bitch", "dick", "pussy", "penis", "nazi", "hitler",
    "idiot", "stupid", "baka", "aho", "unko", "chinko", "manko", "oppai", "ecchi", "kimoi", "kuso",
)
# NG_WORDS_END

_SYMBOLS = "ー・★☆♪"
_SMALL = "ぁぃぅぇぉっゃゅょゎ"
_LARGE = "あいうえおつやゆよわ"


def _allowed(ch: str) -> bool:
    code = ord(ch)
    return (
        0x3041 <= code <= 0x3096
        or 0x30A1 <= code <= 0x30FA
        or 0x4E00 <= code <= 0x9FFF
        or code == 0x3005
        or ch.isascii() and ch.isalnum()
        or ch in _SYMBOLS
    )


def _fold(name: str) -> str:
    out = []
    for ch in name:
        code = ord(ch)
        if 0x30A1 <= code <= 0x30F6:
            ch = chr(code - 0x60)
        ch = ch.lower()
        index = _SMALL.find(ch)
        if index >= 0:
            ch = _LARGE[index]
        if ch in _SYMBOLS:
            continue
        out.append(ch)
    return "".join(out)


def sanitize_name(raw: object) -> str:
    """Returns the cleaned name, or "" when it must not be shown to anyone."""
    if not isinstance(raw, str):
        return ""
    name = unicodedata.normalize("NFKC", raw).strip()
    if not name or len(name) > MAX_LENGTH:
        return ""
    if not all(_allowed(ch) for ch in name):
        return ""
    if sum(1 for ch in name if ch.isascii() and ch.isdigit()) > MAX_DIGITS:
        return ""
    folded = _fold(name)
    if any(word in folded for word in NG_WORDS):
        return ""
    return name
