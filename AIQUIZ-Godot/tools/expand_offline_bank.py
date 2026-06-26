#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""カリキュラム・厳選JSON・add_quizzesから高品質問題を offline_bank にマージ。"""
from __future__ import annotations

import ast
import json
import re
import shutil
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CURRICULUM_ROOT = PROJECT_ROOT / "assets" / "curriculum"
BANK_PATH = PROJECT_ROOT / "offline_bank.json"
ANDROID_BANK = PROJECT_ROOT.parent / "AIQUIZ-Godot-Android" / "offline_bank.json"
CURATED_JSON = Path(__file__).resolve().parent / "data" / "curated_expansion.json"
BACKUP_PATH = PROJECT_ROOT / "offline_bank.backup.expand.json"

MAX_Q = 60
MAX_C = 20
SRC_TAG = "CURRICULUM_HQ"


def validate(item: dict) -> bool:
    q = item.get("q", "")
    if not q or len(q) > MAX_Q:
        return False
    c = item.get("c", [])
    if len(c) != 4:
        return False
    seen = set()
    for ch in c:
        s = str(ch).strip()
        if not s or len(s) > MAX_C:
            return False
        k = s.lower()
        if k in seen:
            return False
        seen.add(k)
    a = item.get("a")
    if not isinstance(a, int) or a < 0 or a >= 4:
        return False
    if not str(item.get("exp", "")).strip():
        return False
    t = item.get("t", 4.0)
    try:
        t = float(t)
    except (TypeError, ValueError):
        return False
    if t <= 0 or t > 10:
        return False
    return True


def normalize_quiz(q: dict, unit: str = "", src: str = SRC_TAG) -> dict | None:
    text = (q.get("q") or "").strip()
    if not text:
        return None
    if not text.startswith("【") and unit:
        text = f"【{unit}】{text}"
    c = q.get("c", [])
    if len(c) != 4:
        return None
    exp = q.get("exp") or q.get("e") or ""
    if not exp:
        return None
    t = q.get("t", 4.0)
    try:
        t = float(t)
    except (TypeError, ValueError):
        t = 4.0
    item = {
        "q": text[:MAX_Q],
        "c": [str(x)[:MAX_C] for x in c],
        "a": int(q["a"]),
        "exp": str(exp)[:100],
        "t": max(2.0, min(8.0, t)),
        "src": src,
    }
    return item if validate(item) else None


def load_bank(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def save_bank(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def existing_qset(bank: dict) -> set[str]:
    s = set()
    for grades in bank.values():
        if not isinstance(grades, dict):
            continue
        for items in grades.values():
            if isinstance(items, list):
                for q in items:
                    if isinstance(q, dict) and q.get("q"):
                        s.add(q["q"].strip())
    return s


def merge(bank: dict, subject: str, grade: str, item: dict, seen: set[str]) -> bool:
    if item["q"].strip() in seen:
        return False
    bank.setdefault(subject, {})
    bank[subject].setdefault(str(grade), [])
    bank[subject][str(grade)].append(item)
    seen.add(item["q"].strip())
    return True


def iter_curriculum() -> list[tuple[str, str, dict]]:
    out = []
    for path in sorted(CURRICULUM_ROOT.rglob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        subject = data.get("subject") or path.parent.name
        grade = str(data.get("grade") or path.stem.replace("grade_", ""))
        for unit in data.get("units", []):
            un = unit.get("name", "")
            for sq in unit.get("sample_questions", []):
                item = normalize_quiz(sq, un)
                if item:
                    out.append((subject, grade, item))
    return out


def concept_quizzes(subject: str, grade: str, unit: str, concepts: list, mistakes: list) -> list[tuple[str, str, dict]]:
    """key_concepts から定義・知識系の4択を生成（算数の暗算系は除外）。"""
    generated = []
    skip_words = ("九九", "暗算", "筆算", "×", "÷", "＋", "－")

    templates = [
        # (pattern in concept, question template, answer from group 0, wrong pool)
    ]

    mapping = [
        ("国会", "法律を作る機関は？", ["国会", "内閣", "裁判所", "警察"], 0, "立法は国会の仕事です。", 4.0),
        ("内閣", "法律を実行する役割を担うのは？", ["国会", "内閣", "裁判所", "市役所"], 1, "行政は内閣が行います。", 4.0),
        ("裁判所", "法律に基づき裁判を行うのは？", ["国会", "内閣", "裁判所", "消防署"], 2, "司法は裁判所です。", 4.0),
        ("光合成", "日光でデンプンを作る働きは？", ["呼吸", "光合成", "蒸散", "消化"], 1, "光合成で養分を作ります。", 4.0),
        ("発芽", "種の発芽に不要なものは？", ["水", "空気", "日光", "適当な温度"], 2, "発芽に日光は不要です。", 4.0),
        ("酸素", "ものが燃えるのに必要な気体は？", ["酸素", "二酸化炭素", "窒素", "水素"], 0, "燃焼には酸素が必要です。", 3.5),
        ("浸食", "川が土をけずる働きを何という？", ["堆積", "浸食", "運搬のみ", "蒸発"], 1, "土を削る働きは浸食です。", 4.0),
        ("比例", "xが2倍でyも2倍になる関係は？", ["比例", "反比例", "平行", "垂直"], 0, "比例の関係です。", 3.5),
        ("直角", "直角は何度？", ["45度", "90度", "180度", "360度"], 1, "直角は90度です。", 3.0),
        ("太平洋ベルト", "太平洋沿いの工業地帯を？", ["太平洋ベルト", "日本海ライン", "シルクロード", "南極"], 0, "太平洋ベルトと呼びます。", 4.0),
        ("西から東", "日本の天気は一般にどちらから変わる？", ["東から西", "西から東", "南から北", "北から南"], 1, "西から東へ変わることが多いです。", 4.0),
        ("ひもの長さ", "振り子の周期を長くするには？", ["ひもを長くする", "おもりを重くする", "色を変える", "短くする"], 0, "長さで周期が決まります。", 4.5),
        ("巻き数", "電磁石を強くするには？", ["巻き数を増やす", "巻き数を減らす", "電流を止める", "鉄を抜く"], 0, "コイルの巻き数を増やします。", 4.5),
        ("国民主権", "国の政治の最終的な決定権は国民にあるという考えは？", ["国民主権", "平和主義", "三権分立", "富国強兵"], 0, "国民主権が三原則の一つです。", 4.5),
        ("平和主義", "戦争を放棄していることを憲法の何という？", ["国民主権", "平和主義", "基本的人権", "三権分立"], 1, "平和主義が三原則です。", 4.5),
        ("貝塚", "縄文時代の貝の殻が積もった遺跡は？", ["古墳", "貝塚", "城跡", "都"], 1, "貝塚から当時の生活がわかります。", 4.0),
        ("平城京", "奈良時代の都は？", ["平城京", "平安京", "江戸", "鎌倉"], 0, "平城京が奈良の都です。", 4.0),
        ("慣用句", "「猫の手も借りたい」の意味は？", ["猫が好き", "とても忙しい", "猫を飼いたい", "手が痛い"], 1, "とても忙しいという慣用句です。", 4.0),
        ("接続", "「雨が降った。（　）サッカーは中止」", ["しかし", "だから", "また", "ところで"], 1, "原因→結果は「だから」です。", 4.0),
        ("敬語", "「行く」の謙譲語は？", ["いらっしゃる", "まいる", "いく", "おいで"], 1, "自分の動作は「まいる」です。", 4.5),
    ]

    concept_blob = " ".join(concepts) + " " + unit
    for key, question, choices, ans, exp, t in mapping:
        if key in concept_blob or key in unit:
            tag = unit.split("(")[0][:8] if unit else key
            item = normalize_quiz(
                {"q": f"【{tag}】{question}", "c": choices, "a": ans, "exp": exp, "t": t},
                src="CONCEPT_HQ",
            )
            if item:
                generated.append((subject, grade, item))

    for concept in concepts:
        if any(w in concept for w in skip_words):
            continue
        if "→" in concept and len(concept) < 40:
            parts = [p.strip() for p in concept.split("→")]
            if len(parts) == 2:
                qtext = f"【{unit[:8]}】{parts[0]}の次の時代は？"
                # 歴史用
                if subject == "社会" and "時代" in unit:
                    choices = [parts[0], parts[1], "江戸", "明治"]
                    choices = list(dict.fromkeys(choices))[:4]
                    while len(choices) < 4:
                        choices.append("戦国")
                    if parts[1] in choices:
                        a = choices.index(parts[1])
                        item = normalize_quiz(
                            {"q": qtext, "c": choices[:4], "a": a, "exp": f"{parts[0]}→{parts[1]}", "t": 4.0},
                            src="CONCEPT_HQ",
                        )
                        if item:
                            generated.append((subject, grade, item))
    return generated


def iter_curriculum_concepts() -> list[tuple[str, str, dict]]:
    out = []
    for path in sorted(CURRICULUM_ROOT.rglob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        subject = data.get("subject") or path.parent.name
        grade = str(data.get("grade") or path.stem.replace("grade_", ""))
        for unit in data.get("units", []):
            un = unit.get("name", "")
            out.extend(concept_quizzes(subject, grade, un, unit.get("key_concepts", []), unit.get("typical_mistakes", [])))
    return out


def load_curated_json() -> list[tuple[str, str, dict]]:
    if not CURATED_JSON.exists():
        return []
    data = json.loads(CURATED_JSON.read_text(encoding="utf-8"))
    out = []
    for row in data:
        item = normalize_quiz(
            {
                "q": row["q"],
                "c": row["c"],
                "a": row["a"],
                "exp": row.get("exp") or row.get("e", ""),
                "t": row.get("t", 4.0),
            },
            src="CURATED_HQ",
        )
        if item:
            out.append((row["subject"], str(row["grade"]), item))
    return out


def load_add_quizzes() -> list[tuple[str, str, dict]]:
    out = []
    tools = Path(__file__).resolve().parent
    for py in tools.glob("add_quizzes_*.py"):
        text = py.read_text(encoding="utf-8")
        m = re.search(r"new_quizzes\s*=\s*(\{)", text)
        if not m:
            continue
        start = m.start(1)
        depth = 0
        for i in range(start, len(text)):
            if text[i] == "{": depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        data = ast.literal_eval(text[start : i + 1])
                    except SyntaxError:
                        break
                    for subj, grades in data.items():
                        for gr, qs in grades.items():
                            for q in qs:
                                item = normalize_quiz(q, src="ADD_QUIZZES_HQ")
                                if item:
                                    out.append((subj, str(gr), item))
                    break
    return out


def count_bank(bank: dict) -> int:
    n = 0
    for grades in bank.values():
        if isinstance(grades, dict):
            for items in grades.values():
                if isinstance(items, list):
                    n += len(items)
    return n


def main() -> int:
    bank = load_bank(BANK_PATH)
    before = count_bank(bank)
    if not BACKUP_PATH.exists():
        shutil.copy2(BANK_PATH, BACKUP_PATH)

    seen = existing_qset(bank)
    added = 0
    stats = {}

    batches = [
        ("curriculum_samples", iter_curriculum()),
        ("curriculum_concepts", iter_curriculum_concepts()),
        ("curated_json", load_curated_json()),
        ("add_quizzes", load_add_quizzes()),
    ]

    for name, candidates in batches:
        n = 0
        for subject, grade, item in candidates:
            if merge(bank, subject, grade, item, seen):
                added += 1
                n += 1
        stats[name] = n

    after = count_bank(bank)
    save_bank(BANK_PATH, bank)
    if ANDROID_BANK.parent.exists():
        save_bank(ANDROID_BANK, bank)

    print("=== offline_bank 拡充 ===")
    print(f"追加前: {before} 問")
    print(f"追加後: {after} 問 (+{added})")
    for k, v in stats.items():
        print(f"  {k}: +{v}")
    print(f"保存: {BANK_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
