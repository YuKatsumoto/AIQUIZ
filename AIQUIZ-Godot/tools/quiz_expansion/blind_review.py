# -*- coding: utf-8 -*-
"""Blind-solve helper for the independent review pass (see REVIEW.md).

    python AIQUIZ-Godot/tools/quiz_expansion/blind_review.py show  <shard.json> [start] [end]
        Print questions and choices with the answer key and explanation hidden.

    python AIQUIZ-Godot/tools/quiz_expansion/blind_review.py check <shard.json> <answers.json>
        Compare the reviewer's answers with the shard's answer key.
        answers.json maps item index to the chosen choice index, e.g. {"0": 2, "1": 0},
        or to null when no single choice can be defended.
"""
import json
import sys


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def show(path, start=0, end=None):
    items = load(path)["items"]
    end = len(items) if end is None else min(end, len(items))
    for i in range(start, end):
        it = items[i]
        print("#%d [%s] %s" % (i, it.get("g", ""), it["q"]))
        for k, choice in enumerate(it["c"]):
            print("    %d) %s" % (k, choice))


def check(path, answers_path):
    items = load(path)["items"]
    answers = load(answers_path)
    if isinstance(answers, list):
        answers = {str(i): v for i, v in enumerate(answers)}
    missing = [i for i in range(len(items)) if str(i) not in answers]
    mismatches = 0
    for i, it in enumerate(items):
        if str(i) not in answers:
            continue
        mine = answers[str(i)]
        if mine == it["a"]:
            continue
        mismatches += 1
        print("#%d MISMATCH reviewer=%s key=%d" % (i, mine, it["a"]))
        print("    q: %s" % it["q"])
        for k, choice in enumerate(it["c"]):
            mark = "*" if k == it["a"] else ("R" if k == mine else " ")
            print("    %s %d) %s" % (mark, k, choice))
        print("    exp: %s" % it.get("exp", ""))
    print("\n%d items, %d answered, %d mismatches, %d unanswered%s"
          % (len(items), len(items) - len(missing), mismatches, len(missing),
             (" (missing: %s)" % missing[:20]) if missing else ""))
    return 1 if mismatches or missing else 0


def main(argv):
    if len(argv) >= 2 and argv[0] == "show":
        nums = [int(x) for x in argv[2:4]]
        show(argv[1], *nums)
        return 0
    if len(argv) == 3 and argv[0] == "check":
        return check(argv[1], argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
