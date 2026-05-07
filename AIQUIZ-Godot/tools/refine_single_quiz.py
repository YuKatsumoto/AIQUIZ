import json
import os
import sys
import argparse
import time
from pathlib import Path

# パス解決
PROJECT_ROOT = Path(__file__).parent.parent
BANK_PATH = PROJECT_ROOT / "offline_bank.json"

def get_gemini_client():
    try:
        from google import genai
    except ImportError:
        print(json.dumps({"error": "google-genai is not installed."}))
        sys.exit(1)

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        # envファイルから探索
        for env_path in [PROJECT_ROOT / "tools" / ".env", PROJECT_ROOT / ".env"]:
            if env_path.exists():
                with open(env_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("GEMINI_API_KEY="):
                            api_key = line.split("=", 1)[1].strip()
                            break
                        elif line.startswith("GOOGLE_API_KEY=") and not api_key:
                            api_key = line.split("=", 1)[1].strip()
            if api_key:
                break

    if not api_key:
        print(json.dumps({"error": "API Key not found."}))
        sys.exit(1)

    return genai.Client(api_key=api_key)

def refine_single_quiz(subject, grade, original_q_text):
    if not BANK_PATH.exists():
        print(json.dumps({"error": f"{BANK_PATH.name} not found."}))
        sys.exit(1)

    with open(BANK_PATH, "r", encoding="utf-8") as f:
        bank_data = json.load(f)

    if subject not in bank_data or grade not in bank_data[subject]:
        print(json.dumps({"error": f"Category {subject}/{grade} not found in bank."}))
        sys.exit(1)

    questions = bank_data[subject][grade]
    target_idx = -1
    for i, q in enumerate(questions):
        if q.get("q", "").strip() == original_q_text.strip():
            target_idx = i
            break

    if target_idx == -1:
        print(json.dumps({"error": "Question not found in the bank data."}))
        sys.exit(1)

    target_q = questions[target_idx]

    client = get_gemini_client()

    prompt = f"""あなたは小学校{grade}年生の「{subject}」の最高品質クイズの添削者です。
以下の問題は、選択肢が少なすぎたり、正解が設定されていないなどの不備があります。
この問題を修正し、以下の条件を満たす完全で魅力的なクイズに書き換えてください。

【元の問題データ】
{json.dumps(target_q, ensure_ascii=False, indent=2)}

【品質基準】
1. 問題文は50文字以内。「【単元名】問題文」の形式にすること（例: 【図形】三角形の面積は？）。
2. 選択肢(c)は必ず4択にする。誤答はよくある間違いなど魅力的なものにする。
3. 正解インデックス(a)を0〜3の範囲で正確に指定する。
4. 解説(exp)は20文字以内の核心の一言にする。
5. 予測解答時間(t)を付与（2.0〜8.0秒の間）。
6. 暗算で解ける範囲にする。

出力フォーマット（必ず以下のJSONオブジェクト1つだけを出力してください）:
{{"q": "【単元名】問題文", "c": ["A","B","C","D"], "a": 0, "exp": "解説", "t": 3.5}}
"""

    from google.genai import types
    try:
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.2,
                response_mime_type="application/json",
            )
        )
        
        text = response.text.strip()
        if text.startswith("```json"):
            text = text[7:]
        if text.startswith("```"):
            text = text[3:]
        if text.endswith("```"):
            text = text[:-3]
            
        new_q = json.loads(text.strip())
        
        # バリデーション
        if not all(k in new_q for k in ("q", "c", "a")):
            raise ValueError("Missing required fields in generated JSON.")
        if not (0 <= new_q["a"] < len(new_q["c"])):
            new_q["a"] = 0 # フォールバック
        
        # 保存
        questions[target_idx] = new_q
        with open(BANK_PATH, "w", encoding="utf-8") as f:
            json.dump(bank_data, f, ensure_ascii=False, indent=2)

        print(json.dumps({
            "success": True,
            "message": "Question refined successfully.",
            "original": target_q,
            "refined": new_q
        }, ensure_ascii=False))

    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Refine a single quiz question.")
    parser.add_argument("--subject", required=True, help="Subject name (e.g. 算数)")
    parser.add_argument("--grade", required=True, help="Grade string (e.g. 1)")
    parser.add_argument("--text", required=True, help="Exact original question text 'q' to find the question.")
    
    args = parser.parse_args()
    refine_single_quiz(args.subject, args.grade, args.text)
