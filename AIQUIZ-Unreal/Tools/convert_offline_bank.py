#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Convert AIQUIZ-Godot offline_bank.json into a flat JSON array for UE DataTable import.

Source shape:  { "<subject>": { "<grade>": [ {q, c[], a, exp|e, t} ] } }
Output shape:  [ { Name, Subject, Grade, Q, C[], A, E, T, NumChoices }, ... ]

The output matches the S_QuizItem Blueprint struct used by DT_QuizBank in the UE port.
One-time dev tool — NOT part of the shipped game.

Usage:  py convert_offline_bank.py
"""
import json
from pathlib import Path

SRC = Path(r"C:\AIQUIZ\AIQUIZ-Godot\offline_bank.json")
DST = Path(r"C:\AIQUIZ\AIQUIZ-Unreal\Tools\DT_QuizBank.json")

SUBJECT_EN = {"算数": "Math", "理科": "Science", "国語": "Japanese", "社会": "Social"}


def main() -> None:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    rows = []
    skipped = 0
    stats = {}
    for subject, grades in data.items():
        subj_en = SUBJECT_EN.get(subject, subject)
        for grade_str, items in grades.items():
            try:
                grade = int(grade_str)
            except (TypeError, ValueError):
                grade = 0
            kept = 0
            for it in items:
                q = (it.get("q") or "").strip()
                c = it.get("c") or []
                a = it.get("a", -1)
                e = (it.get("exp") or it.get("e") or "").strip()
                t = it.get("t", 4.0)
                # light validation (heavy normalization/dedup is deferred to runtime GetQuizzes)
                if not q:
                    skipped += 1
                    continue
                if not isinstance(c, list) or len(c) not in (2, 4):
                    skipped += 1
                    continue
                if not isinstance(a, int) or a < 0 or a >= len(c):
                    skipped += 1
                    continue
                c = [str(x).strip() for x in c]
                try:
                    t = float(t)
                except (TypeError, ValueError):
                    t = 4.0
                seq = len(rows) + 1
                rows.append({
                    "Name": f"{subj_en}_{grade}_{seq:06d}",
                    "Subject": subject,
                    "Grade": grade,
                    "Q": q,
                    "C": c,
                    "A": a,
                    "E": e,
                    "T": t,
                    "NumChoices": len(c),
                })
                kept += 1
            stats[f"{subject}/{grade}"] = kept
    DST.parent.mkdir(parents=True, exist_ok=True)
    DST.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"Wrote {len(rows)} rows -> {DST}")
    print(f"Skipped {skipped} invalid items")
    for k in sorted(stats, key=lambda s: (s.split('/')[0], int(s.split('/')[1]))):
        print(f"  {k}: {stats[k]}")


if __name__ == "__main__":
    main()
