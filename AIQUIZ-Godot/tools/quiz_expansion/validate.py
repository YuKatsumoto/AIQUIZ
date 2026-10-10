# -*- coding: utf-8 -*-
"""Validate quiz-expansion shard files against SPEC.md.

Usage:
    python AIQUIZ-Godot/tools/quiz_expansion/validate.py [shard.json ...]

With no arguments every file in shards/ is checked. Exact duplicates (against
offline_bank.json and other shards) and schema violations are errors; near
duplicates and distribution skews are warnings. Exit code 1 when any error.
"""
import difflib
import glob
import json
import os
import re
import sys
import unicodedata
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
BANK_PATH = os.path.normpath(os.path.join(HERE, "..", "..", "offline_bank.json"))
SHARD_DIR = os.path.join(HERE, "shards")

SUBJECT_SLUGS = {"算数": "math", "理科": "science", "国語": "japanese", "社会": "social", "英語": "english"}
MAX_Q, MAX_C, MAX_EXP, MAX_G = 90, 30, 120, 12
NEAR_DUP = 0.85
_STRIP = re.compile(r"[\s　【】「」『』（）()［］\[\]、。，．,.？?！!・：:〜~ー－\-]")
_FIGURE = re.compile(r"(図|表|写真|グラフ|イラスト)(のように|を見て|で示|の中|から読み)|下の(図|表)|右の(図|表)|左の(図|表)")


_DECIMAL = re.compile(r"(?<=\d)\.(?=\d)")
_TAG = re.compile(r"^【[^】]*】")
_QUOTED = re.compile(r"「[^」]*」|（[^）]*）|\([^)]*\)")
_DIGITS = re.compile(r"[0-9０-９.．]+")


def _skeleton(q):
    """Question with quoted parts and numbers blanked, to spot copy-paste templates."""
    s = _TAG.sub("", unicodedata.normalize("NFKC", q).strip())
    s = _DIGITS.sub("0", _QUOTED.sub("X", s))
    return s


def norm(text):
    # Keep decimal points so "1.5秒" and "15秒" stay distinct choices.
    text = _DECIMAL.sub("p", unicodedata.normalize("NFKC", str(text)))
    return _STRIP.sub("", text).lower()


def load_bank():
    with open(BANK_PATH, encoding="utf-8") as f:
        return json.load(f)


def load_shard(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def shard_paths(args):
    found = args if args else glob.glob(os.path.join(SHARD_DIR, "*.json"))
    return sorted(os.path.normcase(os.path.abspath(p)) for p in found)


def check_item(it, idx):
    errs = []
    if not isinstance(it, dict):
        return ["#%d: item is not an object" % idx]
    q = it.get("q")
    c = it.get("c")
    a = it.get("a")
    if not isinstance(q, str) or not q.strip():
        errs.append("#%d: q is empty" % idx)
    elif len(q) > MAX_Q:
        errs.append("#%d: q is %d chars (max %d)" % (idx, len(q), MAX_Q))
    if not isinstance(c, list) or len(c) != 4:
        errs.append("#%d: c must be a list of exactly 4 choices" % idx)
    else:
        if any(not isinstance(x, str) or not x.strip() for x in c):
            errs.append("#%d: empty choice" % idx)
        elif len({norm(x) for x in c}) != 4:
            errs.append("#%d: duplicate choices %s" % (idx, c))
        for x in c:
            if isinstance(x, str) and len(x) > MAX_C:
                errs.append("#%d: choice '%s' is %d chars (max %d)" % (idx, x, len(x), MAX_C))
        banned = ("すべて", "全部正しい", "どれでもない", "上のどれ")
        if any(isinstance(x, str) and any(b in x for b in banned) for x in c):
            errs.append("#%d: banned catch-all choice %s" % (idx, c))
    if not isinstance(a, int) or isinstance(a, bool) or not 0 <= a <= 3:
        errs.append("#%d: a must be an int 0-3" % idx)
    exp = it.get("exp")
    if not isinstance(exp, str) or not exp.strip():
        errs.append("#%d: exp is empty" % idx)
    elif len(exp) > MAX_EXP:
        errs.append("#%d: exp is %d chars (max %d)" % (idx, len(exp), MAX_EXP))
    t = it.get("t")
    if not isinstance(t, (int, float)) or isinstance(t, bool) or not 1.5 <= t <= 10.0:
        errs.append("#%d: t must be a number 1.5-10.0" % idx)
    g = it.get("g")
    if not isinstance(g, str) or not g.strip():
        errs.append("#%d: g (unit) is empty" % idx)
    elif len(g) > MAX_G:
        errs.append("#%d: g '%s' is %d chars (max %d)" % (idx, g, len(g), MAX_G))
    extra = set(it) - {"q", "c", "a", "exp", "t", "g"}
    if extra:
        errs.append("#%d: unexpected keys %s" % (idx, sorted(extra)))
    return errs


def validate(paths, bank=None, quiet=False):
    """Return (error_count, {path: shard}) for the given shard paths."""
    bank = bank if bank is not None else load_bank()
    # Exact-dup index over the whole bank and every shard on disk.
    seen = {}
    for subj, grades in bank.items():
        for gr, lst in grades.items():
            for i, it in enumerate(lst):
                seen.setdefault(norm(it.get("q", "")), "bank %s/%s #%d" % (subj, gr, i))
    all_shards = sorted(set(shard_paths([])) | set(paths))
    loaded = {}
    total_errors = 0
    for p in all_shards:
        try:
            loaded[p] = load_shard(p)
        except (OSError, ValueError) as e:
            if p in paths:
                print("ERROR %s: cannot read (%s)" % (p, e))
                total_errors += 1
    for p in all_shards:
        if p in paths or p not in loaded:
            continue
        for i, it in enumerate(loaded[p].get("items", [])):
            if isinstance(it, dict):
                seen.setdefault(norm(it.get("q", "")), "%s #%d" % (os.path.basename(p), i))

    for p in paths:
        if p not in loaded:
            continue
        shard = loaded[p]
        name = os.path.basename(p)
        errs, warns = [], []
        subj, grade = shard.get("subject"), shard.get("grade")
        if subj not in SUBJECT_SLUGS:
            errs.append("subject '%s' is not one of %s" % (subj, list(SUBJECT_SLUGS)))
        if not isinstance(grade, int) or not 1 <= grade <= 6:
            errs.append("grade must be an int 1-6")
        items = shard.get("items")
        if not isinstance(items, list) or not items:
            errs.append("items is empty")
            items = []
        if subj in SUBJECT_SLUGS and isinstance(grade, int):
            expect = "%s_g%d_" % (SUBJECT_SLUGS[subj], grade)
            if not name.startswith(expect):
                errs.append("file name should start with '%s'" % expect)

        existing = []
        if subj in bank:
            for gr, lst in bank[subj].items():
                existing.extend((norm(it.get("q", "")), "bank %s/%s" % (subj, gr), it.get("q", "")) for it in lst)
        local = {}
        skeletons = defaultdict(list)
        longest_correct = 0
        for i, it in enumerate(items):
            errs.extend(check_item(it, i))
            if not isinstance(it, dict) or not isinstance(it.get("q"), str):
                continue
            key = norm(it["q"])
            if key in local:
                errs.append("#%d: duplicate of #%d in this shard" % (i, local[key]))
            elif key in seen:
                errs.append("#%d: exact duplicate of %s: %s" % (i, seen[key], it["q"]))
            local.setdefault(key, i)
            if _FIGURE.search(it["q"]):
                warns.append("#%d: looks like it needs a figure/table: %s" % (i, it["q"]))
            c, a = it.get("c"), it.get("a")
            if isinstance(c, list) and isinstance(a, int) and 0 <= a < len(c) and isinstance(c[a], str):
                ans = norm(c[a])
                if len(ans) >= 2 and not ans.isdigit() and ans in norm(it["q"]):
                    warns.append("#%d: answer '%s' appears in the question" % (i, c[a]))
                if len(c) == 4 and all(isinstance(x, str) for x in c):
                    others = sorted((len(x) for k, x in enumerate(c) if k != a), reverse=True)
                    # Only sentence-like choices; short names/words differ in length naturally.
                    if len(c[a]) >= 12 and len(c[a]) >= 1.4 * others[0]:
                        warns.append("#%d: correct choice is much longer than the others (length gives it away): %s" % (i, c))
                    if len(c[a]) > others[0]:
                        longest_correct += 1
                exp = it.get("exp")
                if isinstance(exp, str) and (len(exp) < 15 or norm(exp) == ans):
                    warns.append("#%d: exp is too thin to teach anything: '%s'" % (i, exp))
            skeletons[_skeleton(it["q"])].append(i)
            # seq2 is the cached side; compare this item against each earlier text.
            sm = difflib.SequenceMatcher(None, autojunk=False)
            sm.set_seq2(key)
            for other_key, where, other_q in existing:
                if other_key == key:
                    continue
                sm.set_seq1(other_key)
                if sm.real_quick_ratio() >= NEAR_DUP and sm.quick_ratio() >= NEAR_DUP and sm.ratio() >= NEAR_DUP:
                    warns.append("#%d: near duplicate of %s: '%s' vs '%s'" % (i, where, it["q"], other_q))
                    break
            existing.append((key, "%s #%d" % (name, i), it["q"]))

        n = len(items)
        if n >= 20:
            pos = Counter(it.get("a") for it in items if isinstance(it, dict))
            for k in range(4):
                share = pos.get(k, 0) / n
                if not 0.15 <= share <= 0.35:
                    warns.append("answer position %d is %.0f%% of items (aim for 20-30%%)" % (k, share * 100))
            hard = sum(1 for it in items if isinstance(it, dict) and isinstance(it.get("t"), (int, float)) and it["t"] >= 6.5)
            if hard / n < 0.30:
                warns.append("only %.0f%% of items have t >= 6.5 (aim for 30%%+ multi-step questions)" % (hard / n * 100))
            units = Counter(it.get("g") for it in items if isinstance(it, dict))
            if len(units) < 8:
                warns.append("only %d units (aim for 8-15): %s" % (len(units), dict(units)))
            for u, cnt in units.items():
                if cnt / n > 0.25:
                    warns.append("unit '%s' is %.0f%% of items (max 25%%)" % (u, cnt / n * 100))
            if longest_correct / n > 0.40:
                warns.append("the correct choice is the longest in %.0f%% of items (aim for ~25%%; players learn to pick the longest)" % (longest_correct / n * 100))
            for sk, idxs in skeletons.items():
                if len(idxs) >= 5 and len(idxs) / n > 0.08:
                    warns.append("%d items (%.0f%%) share the same question template '%s' (max 8%%; vary the question forms): #%s"
                                 % (len(idxs), len(idxs) / n * 100, sk, ",".join(map(str, idxs[:12]))))

        total_errors += len(errs)
        if not quiet or errs:
            print("== %s: %d items, %d errors, %d warnings" % (name, n, len(errs), len(warns)))
            for e in errs:
                print("  ERROR " + e)
            if not quiet:
                for w in warns:
                    print("  WARN  " + w)
    return total_errors, loaded


def main(argv):
    paths = shard_paths(argv)
    if not paths:
        print("no shard files found in %s" % SHARD_DIR)
        return 1
    errors, _ = validate(paths)
    print("\n%d shard(s), %d error(s)" % (len(paths), errors))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main(sys.argv[1:]))
