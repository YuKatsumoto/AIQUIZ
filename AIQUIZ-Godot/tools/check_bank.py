import json

with open("C:/AIQUIZ/AIQUIZ-Godot/offline_bank.json", encoding="utf-8") as f:
    d = json.load(f)

strange_qs = []
for subj, grades in d.items():
    if not isinstance(grades, dict): continue
    for grade, qs in grades.items():
        if not isinstance(qs, list): continue
        for idx, q in enumerate(qs):
            text = q.get("q", "")
            c = q.get("c", [])
            
            reasons = []
            if text.count("？") > 1 or text.count("。") > 1:
                reasons.append("Multiple sentences")
            if len(text) > 50:
                reasons.append("Too long")
            if len(c) not in [2, 4]:
                reasons.append("Wrong choice count")
            
            if reasons:
                strange_qs.append({
                    "subject": subj, "grade": grade, "index": idx, "text": text, "reasons": reasons
                })

print(f"Found {len(strange_qs)} strange questions based on heuristics.")
for sq in strange_qs[:20]:
    print(f"[{sq['subject']}{sq['grade']}] {sq['reasons']}: {sq['text']}")
