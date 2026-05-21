import os
import json
import sys
import argparse
import requests
from pathlib import Path
import time

PROJECT_ROOT = Path(__file__).parent.parent
BANK_PATH = PROJECT_ROOT / "offline_bank.json"

def get_existing_questions(bank_data, subject, grade):
    if subject not in bank_data:
        return set()
    if grade not in bank_data[subject]:
        return set()
    return {q.get("q", "") for q in bank_data[subject][grade]}

def generate_questions(subject, grade, count, difficulty, proxy_url, app_secret, api_key):
    # Adjust difficulty instruction
    diff_instruction = ""
    if difficulty == "簡単":
        diff_instruction = '5. 難易度(difficulty)は "簡単" に統一し、基礎的で易しい問題にしてください。'
    elif difficulty == "普通":
        diff_instruction = '5. 難易度(difficulty)は "普通" に統一し、標準的な問題にしてください。'
    elif difficulty == "難しい":
        diff_instruction = '5. 難易度(difficulty)は "難しい" に統一し、応用力や思考力を問う問題にしてください。'
    else:
        diff_instruction = '5. 難易度(difficulty)は "簡単", "普通", "難しい" のいずれかをバランス良く含めてください。'

    system_instruction = f"""あなたは日本の小学{grade}年生向け教育エキスパートです。
以下のJSONスキーマに従い、「{subject}」のクイズを{count}問、厳密なJSONのリスト(配列)形式のみで出力してください。

【厳守するルール】
1. 問題文(q)は40文字以内。先頭に必ず【テーマ名】を付ける。
2. 選択肢(c)は必ず4つ。各15文字以内。特殊記号は使わない。
3. 正解(a)は 0〜3 の整数。
4. 解説(e)は30文字以内で簡潔に。
{diff_instruction}
6. 問題(q)が過去に生成したものと被らないよう、多様な単元を網羅する。
7. 余計なマークダウン(```jsonなど)は一切含めず、純粋なJSON配列のみを出力すること。

例:
[
  {{
    "q": "【図形】3つの直線で囲まれた形を何という？",
    "c": ["四角形", "三角形", "円", "長方形"],
    "a": 1,
    "e": "3つの直線で囲まれた形は三角形です。",
    "difficulty": "簡単"
  }}
]
"""

    prompt = f"小学{grade}年生の{subject}の高品質なクイズを{count}問作成してください。"

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "systemInstruction": {"parts": [{"text": system_instruction}]},
        "generationConfig": {
            "temperature": 0.8,
            "responseMimeType": "application/json"
        }
    }
    
    headers = {'Content-Type': 'application/json'}
    fetch_url = ""
    
    if proxy_url:
        fetch_url = f"{proxy_url.rstrip('/')}/gemini?model=gemini-2.5-flash"
        if app_secret:
            headers['x-app-secret'] = app_secret
    elif api_key:
        fetch_url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
    else:
        raise ValueError("Either PROXY_URL + APP_SECRET or GEMINI_API_KEY must be provided.")

    for attempt in range(3):
        try:
            response = requests.post(fetch_url, json=payload, headers=headers, timeout=120)
            response.raise_for_status()
            resp_json = response.json()
            
            if proxy_url and "candidates" not in resp_json and "error" not in resp_json:
                pass
                
            text_resp = resp_json.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text", "")
            
            text_resp = text_resp.strip()
            if text_resp.startswith("```json"):
                text_resp = text_resp[7:]
            if text_resp.endswith("```"):
                text_resp = text_resp[:-3]
            
            data = json.loads(text_resp.strip())
            if isinstance(data, list):
                return data
            elif isinstance(data, dict) and "questions" in data:
                return data["questions"]
            return []
        except Exception as e:
            print(f"Attempt {attempt+1} Error generating {subject} Grade {grade}: {e}", file=sys.stderr)
            time.sleep(2)
            
    return []

def main():
    parser = argparse.ArgumentParser(description="Generate high-quality quizzes for AIQUIZ")
    parser.add_argument("--subject", required=True, help="Target subject (e.g. 算数)")
    parser.add_argument("--grade", required=True, help="Target grade (1-6)")
    parser.add_argument("--count", type=int, default=10, help="Number of questions to generate")
    parser.add_argument("--difficulty", type=str, default="すべて", help="Difficulty (すべて, 簡単, 普通, 難しい)")
    args = parser.parse_args()

    proxy_url = os.environ.get("PROXY_URL")
    app_secret = os.environ.get("APP_SECRET")
    api_key = os.environ.get("GEMINI_API_KEY")
    
    if not proxy_url and not api_key:
        print("Error: PROXY_URL or GEMINI_API_KEY environment variable is required.", file=sys.stderr)
        sys.exit(1)

    print(f"🚀 生成開始: {args.grade}年生 {args.subject} ({args.count}問) - 難易度: {args.difficulty}")
    
    if not BANK_PATH.exists():
        bank_data = {}
    else:
        try:
            with open(BANK_PATH, "r", encoding="utf-8") as f:
                bank_data = json.load(f)
        except Exception as e:
            print(f"Error loading bank data: {e}", file=sys.stderr)
            bank_data = {}

    existing_questions = get_existing_questions(bank_data, args.subject, args.grade)
    
    new_qs = generate_questions(args.subject, args.grade, args.count, args.difficulty, proxy_url, app_secret, api_key)
    
    valid_qs = []
    for q in new_qs:
        if "q" in q and "c" in q and "a" in q and "e" in q and len(q["c"]) >= 2:
            if len(q["q"]) > 50: continue
            if q["q"] in existing_questions: continue
            
            q["grade"] = int(args.grade) if args.grade.isdigit() else args.grade
            q["subject"] = args.subject
            q["src"] = "AUTO_GEN"
            q["ts"] = int(time.time())
            
            valid_qs.append(q)
            existing_questions.add(q["q"])

    if args.subject not in bank_data:
        bank_data[args.subject] = {}
    if args.grade not in bank_data[args.subject]:
        bank_data[args.subject][args.grade] = []
        
    bank_data[args.subject][args.grade].extend(valid_qs)
    
    with open(BANK_PATH, "w", encoding="utf-8") as f:
        json.dump(bank_data, f, ensure_ascii=False, indent=2)

    print(json.dumps({
        "success": True,
        "requested": args.count,
        "generated": len(new_qs),
        "added": len(valid_qs)
    }))

if __name__ == "__main__":
    main()