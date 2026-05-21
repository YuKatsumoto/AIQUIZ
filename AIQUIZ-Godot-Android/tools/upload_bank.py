import json
import requests
import time
import os
import uuid
from dotenv import load_dotenv

load_dotenv()
db_url = os.environ.get('FIREBASE_DB_URL', 'https://aiquiz-a12f6-default-rtdb.asia-southeast1.firebasedatabase.app')
path = os.environ.get('FIREBASE_RATINGS_PATH', 'quiz_ratings/shared')
url = f"{db_url.rstrip('/')}/{path}.json"

with open('../offline_bank.json', 'r', encoding='utf-8') as f:
    bank = json.load(f)

payload = {}
ts = int(time.time())

for subject, grades in bank.items():
    for grade, qs in grades.items():
        for q in qs:
            push_id = f"offline_{uuid.uuid4().hex}"
            payload[push_id] = {
                "q": q["q"],
                "c": q["c"],
                "a": q["a"],
                "e": q.get("exp", ""),
                "good": True,
                "subject": subject,
                "grade": grade,
                "difficulty": "普通",
                "src": "OFFLINE",
                "reason": "最高品質パイプライン審査通過 (Gemini Flash)",
                "ts": ts
            }

print(f"Uploading {len(payload)} questions to Firebase via PATCH...")
res = requests.patch(url, json=payload)
if res.status_code == 200:
    print("Success! Uploaded all questions instantly.")
else:
    print(f"Error: {res.status_code} - {res.text}")
