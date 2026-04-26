import json
import random

filepath = 'c:/AIQUIZ/AIQUIZ-Godot/offline_bank.json'
with open(filepath, 'r', encoding='utf-8') as f:
    data = json.load(f)

# Collect all questions
all_questions = []
for subject, grades in data.items():
    for grade, questions in grades.items():
        for q in questions:
            all_questions.append((subject, grade, q))

# Sample 30 questions
random.seed(42) # For reproducibility
samples = random.sample(all_questions, 30)

for subject, grade, q in samples:
    print(f"[{subject} - Grade {grade}]")
    print(f"Q: {q['q']}")
    for i, c in enumerate(q['c']):
        prefix = "✅ " if i == q['a'] else "❌ "
        print(f"  {prefix}{c}")
    print(f"Exp: {q['exp']}")
    print("-" * 40)
