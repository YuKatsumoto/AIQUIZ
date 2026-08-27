import os
import json
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
BANK_PATH = PROJECT_ROOT / "offline_bank.json"
ENV_PATH = PROJECT_ROOT / "tools" / ".env"
MODEL = "gemini-2.5-flash"

def get_api_key():
    if not ENV_PATH.exists():
        return None
    with open(ENV_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("GEMINI_API_KEY="):
                return line.strip().split("=", 1)[1]
    return None

API_KEY = get_api_key()

SUBJECTS = ["算数", "国語", "理科", "社会"]
QUESTIONS_PER_BATCH = 60


def build_request(subject, grade):
    system_instruction = f"""あなたは日本の{grade}年生向け教育エキスパートです。
以下のJSONスキーマに従い、「{subject}」のクイズを{QUESTIONS_PER_BATCH}問、【絶対にJSONのリスト(配列)形式のみ】で出力してください。
マークダウンのコードブロック(```json ... ```)は付けないでください！[ {{...}}, {{...}} ] のみを出力してください。
問題(q)の先頭には【テーマ名】を付けてください。
選択肢(c)は4つ、正解(a)は 0〜3 のインデックス、解説(exp)も出力してください。
問題は絶対に被らないように、様々な単元を網羅してください。"""
    prompt = f"小学{grade}年生の{subject}の高品質なクイズを{QUESTIONS_PER_BATCH}問作成せよ。"
    return {
        "contents": [{"parts": [{"text": prompt}], "role": "user"}],
        "system_instruction": {"parts": [{"text": system_instruction}]},
        "config": {"temperature": 0.7, "response_mime_type": "application/json"},
    }


def parse_quiz_json(text):
    text = (text or "").strip()
    if text.startswith("```json"):
        text = text[7:]
    if text.startswith("```"):
        text = text[3:]
    if text.endswith("```"):
        text = text[:-3]
    data = json.loads(text.strip())
    return data if isinstance(data, list) else []


def _response_text(response) -> str:
    if response is None:
        return ""
    text = getattr(response, "text", None)
    if text:
        return text
    try:
        return response.candidates[0].content.parts[0].text
    except Exception:
        return ""


def generate_all_batch(jobs):
    from google import genai

    client = genai.Client(api_key=API_KEY)
    src = [build_request(subject, grade) for subject, grade in jobs]
    print(f"Batch API に {len(src)} 件を投入します（50%オフ）...")
    batch_job = client.batches.create(
        model=MODEL,
        src=src,
        config={"display_name": "aiquiz-mass-generate"},
    )
    name = batch_job.name
    started = time.time()
    while True:
        batch_job = client.batches.get(name=name)
        state = getattr(batch_job.state, "name", str(batch_job.state))
        print(f"  batch {state}")
        if state == "JOB_STATE_SUCCEEDED":
            break
        if state in ("JOB_STATE_FAILED", "JOB_STATE_CANCELLED", "JOB_STATE_EXPIRED"):
            raise RuntimeError(f"Batch failed: {state} {getattr(batch_job, 'error', None)}")
        if time.time() - started > 3600:
            raise TimeoutError("Batch timed out")
        time.sleep(10)

    dest = getattr(batch_job, "dest", None)
    inlined = getattr(dest, "inlined_responses", None) if dest is not None else None
    if not inlined:
        inlined = getattr(batch_job, "inlined_responses", []) or []
    results = []
    for item in inlined:
        response = getattr(item, "response", item)
        try:
            results.append(parse_quiz_json(_response_text(response)))
        except Exception as e:
            print(f"  parse error: {e}")
            results.append([])
    while len(results) < len(jobs):
        results.append([])
    return results


def merge_into_bank(bank_data, subject, grade, new_qs):
    valid_qs = [q for q in new_qs if "q" in q and "c" in q and "a" in q and "exp" in q and len(q["c"]) >= 2]
    if subject not in bank_data:
        bank_data[subject] = {}
    if grade not in bank_data[subject]:
        bank_data[subject][grade] = []
    existing = {q.get("q"): True for q in bank_data[subject][grade]}
    added = 0
    for q in valid_qs:
        if q["q"] not in existing:
            bank_data[subject][grade].append(q)
            existing[q["q"]] = True
            added += 1
    return added


def main():
    if not API_KEY:
        print("GEMINI_API_KEY が .env に見つかりません。")
        return

    print("[超大量クイズ生成モード開始] Gemini Batch API で各学年・各教科を一括生成します...")

    with open(BANK_PATH, "r", encoding="utf-8") as f:
        bank_data = json.load(f)

    jobs = [(subj, grade) for grade in ["1", "2", "3", "4", "5", "6"] for subj in SUBJECTS]
    results = generate_all_batch(jobs)
    total_added = 0
    for (subj, grade), new_qs in zip(jobs, results):
        added = merge_into_bank(bank_data, subj, grade, new_qs)
        total_added += added
        print(f"  {subj}(小{grade}) -> {added}問 追加")

    with open(BANK_PATH, "w", encoding="utf-8") as f:
        json.dump(bank_data, f, ensure_ascii=False, indent=2)

    print(f"\n完了。{total_added} 問が新たにオフラインバンクに注入されました。")


if __name__ == "__main__":
    main()
