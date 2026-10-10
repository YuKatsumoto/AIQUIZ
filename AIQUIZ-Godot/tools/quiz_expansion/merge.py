# -*- coding: utf-8 -*-
"""Merge validated shard files into offline_bank.json.

Usage:
    python AIQUIZ-Godot/tools/quiz_expansion/merge.py [--dry-run] [shard.json ...]

Refuses to merge when validate.py reports any error. Items whose question text
already exists in the bank are skipped, so re-running is safe.
"""
import json
import sys

import validate


def main(argv):
    dry = "--dry-run" in argv
    paths = validate.shard_paths([a for a in argv if a != "--dry-run"])
    if not paths:
        print("no shard files found")
        return 1
    bank = validate.load_bank()
    errors, loaded = validate.validate(paths, bank, quiet=True)
    if errors:
        print("%d validation error(s); nothing merged" % errors)
        return 1
    present = {validate.norm(it.get("q", "")) for g in bank.values() for lst in g.values() for it in lst}
    added = {}
    for p in paths:
        shard = loaded[p]
        subj, grade = shard["subject"], str(shard["grade"])
        target = bank.setdefault(subj, {}).setdefault(grade, [])
        for it in shard["items"]:
            key = validate.norm(it["q"])
            if key in present:
                continue
            present.add(key)
            target.append({k: it[k] for k in ("q", "c", "a", "exp", "t", "g")})
            added[(subj, grade)] = added.get((subj, grade), 0) + 1
    for (subj, grade), n in sorted(added.items()):
        print("%s %s年: +%d (now %d)" % (subj, grade, n, len(bank[subj][grade])))
    print("total added: %d" % sum(added.values()))
    if not dry:
        with open(validate.BANK_PATH, "w", encoding="utf-8") as f:
            f.write(json.dumps(bank, ensure_ascii=False, indent=2) + "\n")
        print("wrote %s" % validate.BANK_PATH)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
