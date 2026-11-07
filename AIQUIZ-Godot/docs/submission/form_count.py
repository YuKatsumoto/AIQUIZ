"""form_entry.md の ```text ブロックの字数を数える。

改行も 1 字として数える（Google フォームの字数と同じ数え方）。
使い方: python docs/submission/form_count.py
"""
import pathlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

path = pathlib.Path(__file__).with_name("form_entry.md")
text = path.read_text(encoding="utf-8")

for m in re.finditer(r"^```text\n(.*?)\n```", text, flags=re.S | re.M):
    body = m.group(1)
    # このブロックの直前の見出しを探す
    before = text[: m.start()]
    heads = re.findall(r"^#+ (.+)$", before, flags=re.M)
    head = heads[-1] if heads else "?"
    newlines = body.count("\n")
    print(f"{len(body):5d} 字（うち改行 {newlines}）  {head}")
