# -*- coding: utf-8 -*-
"""Print existing questions compactly (question text and correct answer only).

    python AIQUIZ-Godot/tools/quiz_expansion/list_existing.py <教科> <学年>

Lists offline_bank.json and every shard for that subject and grade, one line
each, so authors can see what is covered without loading the full JSON
(choices, explanations and timings are omitted to save context).
"""
import glob
import json
import os
import sys

import validate


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    subject, grade = argv[0], str(int(argv[1]))
    bank = validate.load_bank()
    rows = []
    for it in bank.get(subject, {}).get(grade, []):
        c, a = it.get("c", []), it.get("a")
        ans = c[a] if isinstance(a, int) and 0 <= a < len(c) else "?"
        rows.append(("bank", it.get("g", ""), it.get("q", ""), ans))
    slug = validate.SUBJECT_SLUGS.get(subject)
    if slug:
        for path in sorted(glob.glob(os.path.join(validate.SHARD_DIR, "%s_g%s_*.json" % (slug, grade)))):
            for it in validate.load_shard(path).get("items", []):
                c, a = it.get("c", []), it.get("a")
                ans = c[a] if isinstance(a, int) and 0 <= a < len(c) else "?"
                rows.append((os.path.basename(path)[:-5], it.get("g", ""), it.get("q", ""), ans))
    for src, unit, q, ans in rows:
        print("%s\t%s\t%s\t=> %s" % (src, unit, q, ans))
    print("\n%d questions" % len(rows))
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
