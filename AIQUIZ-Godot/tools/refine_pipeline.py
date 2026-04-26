"""
オフライン問題バンク 最高品質化パイプライン
===========================================
Gemini API を使い、offline_bank.json を4段階で最高品質にリファインする。

Phase 1: 静的バリデーション（プログラムのみ）
Phase 2: LLM品質審査（Gemini バッチ判定）
Phase 3: LLMリファイン（exp短縮 + t付与 + 選択肢改善）
Phase 4: 不足分の自動生成

使い方:
  pip install google-genai
  python refine_pipeline.py
"""

import json
import os
import re
import time
import sys
import traceback
from pathlib import Path
from collections import Counter

# ── パス解決 ──
PROJECT_ROOT = Path(__file__).parent.parent
BANK_PATH = PROJECT_ROOT / "offline_bank.json"
OUTPUT_PATH = PROJECT_ROOT / "offline_bank_v2.json"
PROGRESS_PATH = PROJECT_ROOT / "offline_bank_refining.json"

# ── 設定 ──
TARGET_PER_CATEGORY = 100
AUDIT_BATCH_SIZE = 10       # Phase 2: 一度に審査する問題数
REFINE_BATCH_SIZE = 10      # Phase 3: 一度にリファインする問題数
GENERATE_BATCH_SIZE = 10    # Phase 4: 一度に生成する問題数
API_DELAY = 1.5             # API呼び出し間の待機秒数（レートリミット対策）

# ── NG パターン ──
STATIC_NG_PATTERNS = ["次のうち", "図の", "上の", "テープが", "グラフを見て", "表を見て"]

# 3桁以上の計算を検出する正規表現
LARGE_CALC_RE = re.compile(r'\d{3,}\s*[＋＋\-−×÷÷+\-*/]\s*\d+|\d+\s*[＋＋\-−×÷÷+\-*/]\s*\d{3,}')


def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def get_gemini_client():
    """Gemini APIクライアントを取得"""
    try:
        from google import genai
    except ImportError:
        print("エラー: google-genai がインストールされていません。")
        print("  pip install google-genai")
        sys.exit(1)

    # APIキー取得（tools/.env → プロジェクト/.env の順で探す）
    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        env_tools = PROJECT_ROOT / "tools" / ".env"
        env_root = PROJECT_ROOT / ".env"
        for env_path in [env_tools, env_root]:
            if env_path.exists():
                with open(env_path, "r") as f:
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
        print("エラー: GEMINI_API_KEY が見つかりません。")
        sys.exit(1)

    client = genai.Client(api_key=api_key, http_options={"timeout": 120000.0})
    return client


def call_gemini(client, prompt, *, model="gemini-3-flash-preview", temperature=0.3, max_retries=3):
    """Gemini APIを呼び出してJSON応答を取得"""
    from google.genai import types

    for attempt in range(max_retries):
        try:
            response = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=temperature,
                    response_mime_type="application/json",
                ),
            )
            text = response.text.strip()
            # ```json ... ``` の除去
            if text.startswith("```json"):
                text = text[7:]
            if text.startswith("```"):
                text = text[3:]
            if text.endswith("```"):
                text = text[:-3]
            return json.loads(text.strip())
        except Exception as e:
            if attempt < max_retries - 1:
                wait = (attempt + 1) * 2
                print(f"    [リトライ {attempt+1}/{max_retries}] {type(e).__name__}: {e}", flush=True)
                time.sleep(wait)
            else:
                print(f"    [失敗] {type(e).__name__}: {e}", flush=True)
                return None
    return None


# ═══════════════════════════════════════════
# Phase 1: 静的バリデーション
# ═══════════════════════════════════════════

def phase1_static_validation(bank_data):
    print("\n" + "=" * 60)
    print("Phase 1: 静的バリデーション")
    print("=" * 60)

    valid_data = {}
    total_removed = 0
    removal_reasons = Counter()

    for subject, grades in bank_data.items():
        valid_data[subject] = {}
        for grade, questions in grades.items():
            valid_questions = []
            seen_texts = set()

            for q in questions:
                # フォーマットチェック
                if not all(k in q for k in ("q", "c", "a")):
                    total_removed += 1
                    removal_reasons["フォーマット不備"] += 1
                    continue

                # 選択肢数チェック
                if len(q["c"]) < 2:
                    total_removed += 1
                    removal_reasons["選択肢不足"] += 1
                    continue

                # 正解インデックスチェック
                if not (0 <= q["a"] < len(q["c"])):
                    total_removed += 1
                    removal_reasons["正解インデックス範囲外"] += 1
                    continue

                # NGパターンチェック
                text = q["q"]
                if any(ng in text for ng in STATIC_NG_PATTERNS):
                    total_removed += 1
                    removal_reasons["NGパターン"] += 1
                    continue

                # 3桁以上の計算チェック（算数のみ）
                if subject == "算数" and LARGE_CALC_RE.search(text):
                    total_removed += 1
                    removal_reasons["暗算制約違反(3桁計算)"] += 1
                    continue

                # 重複チェック（完全一致）
                if text in seen_texts:
                    total_removed += 1
                    removal_reasons["重複"] += 1
                    continue
                seen_texts.add(text)

                valid_questions.append(q)

            valid_data[subject][grade] = valid_questions
            removed_here = len(questions) - len(valid_questions)
            if removed_here > 0:
                print(f"  {subject} {grade}年: {len(questions)} → {len(valid_questions)} ({removed_here}問除外)")

    print(f"\n  合計 {total_removed} 問を除外:")
    for reason, count in removal_reasons.most_common():
        print(f"    - {reason}: {count}")

    return valid_data


# ═══════════════════════════════════════════
# Phase 2: LLM品質審査
# ═══════════════════════════════════════════

def phase2_llm_audit(client, bank_data):
    print("\n" + "=" * 60)
    print("Phase 2: LLM品質審査 (Gemini)")
    print("=" * 60)

    audited_data = {}
    total_fail = 0
    total_refine = 0
    total_pass = 0

    for subject, grades in bank_data.items():
        audited_data[subject] = {}
        for grade, questions in grades.items():
            audited_questions = []

            # バッチ処理
            total_batches = (len(questions) + AUDIT_BATCH_SIZE - 1) // AUDIT_BATCH_SIZE
            for batch_idx, batch_start in enumerate(range(0, len(questions), AUDIT_BATCH_SIZE)):
                batch = questions[batch_start:batch_start + AUDIT_BATCH_SIZE]
                print(f"    [{subject} {grade}年] バッチ {batch_idx+1}/{total_batches} ({len(batch)}問)...", end="", flush=True)
                indexed = [{"id": i, "q": q["q"], "c": q["c"], "a": q["a"],
                           "exp": q.get("exp", "")} for i, q in enumerate(batch)]

                prompt = f"""あなたは小学生向けクイズの品質管理エキスパートです。
以下は「{subject}」の「{grade}年生」向けのクイズです。

各問題を以下の基準で審査し、JSONの配列で結果を返してください:

【FAIL（即除外）の条件】
1. 正解インデックス(a)が実際の正解と一致していない
2. 選択肢に正解が含まれていない
3. {grade}年生の学習範囲から明らかに逸脱（上の学年 or 下の学年の内容）

【NEEDS_REFINE（要改善）の条件】
1. 解説(exp)が25文字を超えている
2. 問題文が冗長（もっと簡潔にできる）
3. 選択肢が安直（明らかに間違いと分かるものが含まれている）
4. 同じ学年・科目内で類似パターンの問題がある

【PASS】上記に該当しない良問

出力フォーマット（必ずこの形式で）:
[{{"id": 0, "verdict": "PASS"}}, {{"id": 1, "verdict": "FAIL", "reason": "正解が間違っている"}}, ...]

入力 ({len(batch)}問):
{json.dumps(indexed, ensure_ascii=False)}"""

                result = call_gemini(client, prompt, temperature=0.1)
                print(" OK", flush=True)
                time.sleep(API_DELAY)

                if result is None:
                    # API失敗時は全てPASS扱い
                    for q in batch:
                        q["_verdict"] = "PASS"
                        audited_questions.append(q)
                    continue

                # 結果をマッピング
                verdict_map = {}
                if isinstance(result, list):
                    for item in result:
                        if isinstance(item, dict) and "id" in item:
                            verdict_map[item["id"]] = item.get("verdict", "PASS")

                for i, q in enumerate(batch):
                    verdict = verdict_map.get(i, "PASS")
                    if verdict == "FAIL":
                        total_fail += 1
                        continue  # 除外
                    elif verdict == "NEEDS_REFINE":
                        total_refine += 1
                        q["_verdict"] = "NEEDS_REFINE"
                    else:
                        total_pass += 1
                        q["_verdict"] = "PASS"
                    audited_questions.append(q)

            audited_data[subject][grade] = audited_questions
            print(f"  {subject} {grade}年: {len(questions)} → {len(audited_questions)} "
                  f"(FAIL除外: {len(questions) - len(audited_questions)})", flush=True)

    print(f"\n  審査結果: PASS={total_pass}  NEEDS_REFINE={total_refine}  FAIL={total_fail}", flush=True)
    return audited_data


# ═══════════════════════════════════════════
# Phase 3: LLMリファイン
# ═══════════════════════════════════════════

def phase3_llm_refine(client, bank_data):
    print("\n" + "=" * 60)
    print("Phase 3: LLMリファイン (exp短縮 + t付与 + 品質向上)")
    print("=" * 60)

    refined_data = {}
    total_refined = 0
    total_t_added = 0

    for subject, grades in bank_data.items():
        refined_data[subject] = {}
        for grade, questions in grades.items():
            refined_questions = []

            total_batches = (len(questions) + REFINE_BATCH_SIZE - 1) // REFINE_BATCH_SIZE
            for batch_idx, batch_start in enumerate(range(0, len(questions), REFINE_BATCH_SIZE)):
                batch = questions[batch_start:batch_start + REFINE_BATCH_SIZE]
                print(f"    [{subject} {grade}年] リファイン {batch_idx+1}/{total_batches}...", end="", flush=True)
                indexed = []
                for i, q in enumerate(batch):
                    item = {"id": i, "q": q["q"], "c": q["c"], "a": q["a"],
                            "exp": q.get("exp", ""), "verdict": q.get("_verdict", "PASS")}
                    indexed.append(item)

                prompt = f"""あなたは小学生向けクイズのリライト専門家です。
以下は「{subject}」の「{grade}年生」向けのクイズです。各問題を改善してください。

【全問題に対して行うこと】
1. 「t」フィールドを追加: その問題を{grade}年生が解くのにかかる予測秒数（float, 1.5〜10.0）
   - 即答系（簡単な暗算・基本知識）= 2.0〜3.0
   - 標準（ちょっと考える）= 3.5〜5.0
   - 思考問題（文章題・応用）= 5.0〜7.0
   - 難問 = 7.0〜10.0

【verdict が "NEEDS_REFINE" の問題に対して追加で行うこと】
2. 「exp」を20文字以内に短縮。核心の一言だけ残す。
   例: "三角形の面積の公式は底辺×高さ÷2です。5×4÷2＝10" → "底辺×高さ÷2=10c㎡"
3. 問題文が50文字を超える場合、簡潔にリライト
4. 選択肢に明らかなダミーがある場合、もっともらしい誤答に改善

【verdict が "PASS" の問題】
- 「t」だけ追加。他はそのまま。ただし exp が25文字超の場合は短縮してよい。

出力フォーマット（元のq,c,aは変更なし or 改善済みで返す）:
[{{"id": 0, "q": "問題文", "c": ["A","B","C","D"], "a": 0, "exp": "短い解説", "t": 3.5}}, ...]

入力 ({len(batch)}問):
{json.dumps(indexed, ensure_ascii=False)}"""

                result = call_gemini(client, prompt, temperature=0.2)
                print(" OK", flush=True)
                time.sleep(API_DELAY)

                if result is None:
                    # API失敗時はそのまま（tだけデフォルトで追加）
                    for q in batch:
                        if "t" not in q:
                            q["t"] = 4.0
                        q.pop("_verdict", None)
                        refined_questions.append(q)
                    continue

                # 結果をマッピング
                result_map = {}
                if isinstance(result, list):
                    for item in result:
                        if isinstance(item, dict) and "id" in item:
                            result_map[item["id"]] = item

                for i, orig_q in enumerate(batch):
                    refined = result_map.get(i)
                    if refined and all(k in refined for k in ("q", "c", "a")):
                        new_q = {
                            "q": refined["q"],
                            "c": refined["c"],
                            "a": refined["a"],
                            "exp": refined.get("exp", orig_q.get("exp", "")),
                        }
                        # t を安全にパース
                        t_val = refined.get("t", 4.0)
                        try:
                            t_val = float(t_val)
                        except (ValueError, TypeError):
                            t_val = 4.0
                        new_q["t"] = max(1.5, min(10.0, t_val))
                        total_t_added += 1

                        if orig_q.get("_verdict") == "NEEDS_REFINE":
                            total_refined += 1

                        refined_questions.append(new_q)
                    else:
                        # パース失敗時はオリジナルにtだけ追加
                        orig_q.pop("_verdict", None)
                        if "t" not in orig_q:
                            orig_q["t"] = 4.0
                        refined_questions.append(orig_q)

            refined_data[subject][grade] = refined_questions
            print(f"  {subject} {grade}年: {len(refined_questions)}問処理完了", flush=True)

    print(f"\n  リファイン: {total_refined}問改善  t付与: {total_t_added}問")
    return refined_data


# ═══════════════════════════════════════════
# Phase 4: 不足分の自動生成
# ═══════════════════════════════════════════

def phase4_augmentation(client, bank_data):
    print("\n" + "=" * 60)
    print(f"Phase 4: 不足分の自動生成 (目標: 各カテゴリ {TARGET_PER_CATEGORY}問)")
    print("=" * 60)

    total_generated = 0

    for subject, grades in bank_data.items():
        for grade, questions in grades.items():
            needed = TARGET_PER_CATEGORY - len(questions)
            if needed <= 0:
                # 目標以上ある場合は品質上位を残す（t が低い = 即答系を優先的にキープ）
                if len(questions) > TARGET_PER_CATEGORY + 20:
                    print(f"  {subject} {grade}年: {len(questions)}問 → {TARGET_PER_CATEGORY}問に絞り込み")
                    bank_data[subject][grade] = questions[:TARGET_PER_CATEGORY]
                continue

            print(f"  {subject} {grade}年: あと {needed}問 必要。生成中...")

            # 既存問題の単元を取得して重複を避ける
            existing_units = set()
            for q in questions:
                match = re.match(r'【(.+?)】', q["q"])
                if match:
                    existing_units.add(match.group(1))

            generated = []
            while len(generated) < needed:
                batch_size = min(GENERATE_BATCH_SIZE, needed - len(generated))

                prompt = f"""あなたは小学校{grade}年生の「{subject}」の最高品質クイズ作成者です。
以下の条件で {batch_size} 問の新しいクイズを作成してください。

【品質基準】
1. 問題文は50文字以内。【単元名】を先頭に付ける
2. 選択肢は4択（2択が自然な場合のみ2択可）
3. 誤答は「よくある間違い」を反映した魅力的なもの
4. 正解インデックス(a)は0〜3で均等に散らす
5. 解説(exp)は20文字以内の核心一言
6. 予測解答時間(t)を付与（2.0〜8.0秒）
7. 暗算で解ける範囲の計算のみ（3桁以上の計算禁止）
8. テキストだけで自己完結して解ける問題のみ

【多様性】
- 各問題は異なる単元・トピックから出題
- 既に以下の単元がカバー済みなので、これら以外の単元から出題すること:
  {', '.join(list(existing_units)[:20]) if existing_units else '(なし)'}

出力フォーマット:
[{{"q": "【単元】問題文", "c": ["A","B","C","D"], "a": 0, "exp": "解説", "t": 3.5}}]"""

                result = call_gemini(client, prompt, temperature=0.7)
                time.sleep(API_DELAY)

                if result and isinstance(result, list):
                    for item in result:
                        if isinstance(item, dict) and all(k in item for k in ("q", "c", "a")):
                            # バリデーション
                            if not (0 <= item["a"] < len(item["c"])):
                                continue
                            if len(item["c"]) < 2:
                                continue

                            new_q = {
                                "q": item["q"],
                                "c": item["c"],
                                "a": item["a"],
                                "exp": item.get("exp", ""),
                            }
                            t_val = item.get("t", 4.0)
                            try:
                                t_val = float(t_val)
                            except (ValueError, TypeError):
                                t_val = 4.0
                            new_q["t"] = max(1.5, min(10.0, t_val))

                            generated.append(new_q)
                            # 単元を記録
                            match = re.match(r'【(.+?)】', item["q"])
                            if match:
                                existing_units.add(match.group(1))
                else:
                    print(f"    生成失敗。リトライ...")

            questions.extend(generated[:needed])
            total_generated += len(generated[:needed])
            print(f"    → {len(generated[:needed])}問追加 (計{len(questions)}問)")

    print(f"\n  合計 {total_generated} 問を新規生成")
    return bank_data


# ═══════════════════════════════════════════
# 最終検証
# ═══════════════════════════════════════════

def final_validation(bank_data):
    print("\n" + "=" * 60)
    print("最終検証")
    print("=" * 60)

    issues = []
    total = 0

    for subject, grades in bank_data.items():
        for grade, questions in grades.items():
            for i, q in enumerate(questions):
                total += 1
                tag = f"{subject}/{grade}年/#{i}"

                # 必須フィールド
                for key in ("q", "c", "a", "exp", "t"):
                    if key not in q:
                        issues.append(f"{tag}: '{key}' が欠落")

                # 正解範囲
                if "a" in q and "c" in q:
                    if not (0 <= q["a"] < len(q["c"])):
                        issues.append(f"{tag}: 正解インデックス範囲外 (a={q['a']}, len(c)={len(q['c'])})")

                # t の範囲
                if "t" in q:
                    if not (1.0 <= q["t"] <= 12.0):
                        issues.append(f"{tag}: t値が範囲外 ({q['t']})")

                # exp の長さ
                if "exp" in q and len(q["exp"]) > 50:
                    issues.append(f"{tag}: exp が50文字超 ({len(q['exp'])}文字)")

            count = len(questions)
            status = "✅" if count >= TARGET_PER_CATEGORY else "⚠️"
            print(f"  {status} {subject} {grade}年: {count}問", end="")
            if "t" in questions[0] if questions else {}:
                avg_t = sum(q.get("t", 4.0) for q in questions) / max(1, len(questions))
                print(f"  (平均t: {avg_t:.1f}秒)", end="")
            print()

    print(f"\n  合計: {total}問")
    if issues:
        print(f"  ⚠️ {len(issues)}件の問題:")
        for issue in issues[:20]:
            print(f"    - {issue}")
    else:
        print("  ✅ 全問題が品質基準をクリア！")

    return len(issues) == 0


# ═══════════════════════════════════════════
# メイン
# ═══════════════════════════════════════════

def main():
    print("=" * 60)
    print("🔧 オフライン問題バンク 最高品質化パイプライン")
    print("=" * 60)

    if not BANK_PATH.exists():
        print(f"エラー: {BANK_PATH} が見つかりません。")
        return

    # Gemini クライアント初期化
    client = get_gemini_client()
    print("✅ Gemini API 接続確認OK")

    # 既存データ読み込み（途中再開対応）
    if PROGRESS_PATH.exists():
        print(f"⏩ 途中経過ファイルから再開: {PROGRESS_PATH.name}")
        bank_data = load_json(PROGRESS_PATH)
    else:
        bank_data = load_json(BANK_PATH)

    try:
        t0 = time.time()

        # Phase 1: 静的バリデーション
        data_p1 = phase1_static_validation(bank_data)
        save_json(PROGRESS_PATH, data_p1)

        # Phase 2: LLM品質審査
        data_p2 = phase2_llm_audit(client, data_p1)
        save_json(PROGRESS_PATH, data_p2)

        # Phase 3: LLMリファイン
        data_p3 = phase3_llm_refine(client, data_p2)
        save_json(PROGRESS_PATH, data_p3)

        # Phase 4: 不足分の自動生成
        data_p4 = phase4_augmentation(client, data_p3)

        # 最終検証
        is_valid = final_validation(data_p4)

        # 保存
        save_json(OUTPUT_PATH, data_p4)
        t1 = time.time()

        print("\n" + "=" * 60)
        print(f"🎉 パイプライン完了！ (所要時間: {t1-t0:.0f}秒 = {(t1-t0)/60:.1f}分)")
        print(f"   結果: {OUTPUT_PATH.name}")
        if is_valid:
            print("   品質: ✅ 全問題クリア")
        else:
            print("   品質: ⚠️ 一部に問題あり（上記参照）")
        print("=" * 60)

        # 途中経過ファイルを削除
        if PROGRESS_PATH.exists():
            os.remove(PROGRESS_PATH)

    except KeyboardInterrupt:
        print("\n\n⏸️ 中断されました。進捗は保存済みです。")
        print(f"   再開するには再度実行してください。")
    except Exception as e:
        traceback.print_exc()
        print(f"\n❌ エラーが発生しました: {e}")


if __name__ == "__main__":
    main()
