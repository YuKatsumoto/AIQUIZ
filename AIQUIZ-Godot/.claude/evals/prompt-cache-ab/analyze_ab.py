# 比較の集計: gen.json（生成）・accepted.json（ゲームの採用判定）・judged.json（Opus の採点）から report.md を作る。
import json, math, os, statistics, collections

D = os.path.dirname(os.path.abspath(__file__))
load = lambda f: json.load(open(os.path.join(D, f), encoding='utf-8'))
prompts = load('prompts.json')
gen = load('gen.json')
acc = load('accepted.json') if os.path.exists(os.path.join(D, 'accepted.json')) else None
judged = load('judged.json') if os.path.exists(os.path.join(D, 'judged.json')) else None
ARMS = ['old', 'new']
NAME = {'old': '今の並び', 'new': '新しい並び'}
out = []
P = out.append


def wilson(k, n, z=1.96):
    if n == 0:
        return (0, 0, 0)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (p, c - h, c + h)


def pct(k, n):
    p, lo, hi = wilson(k, n)
    return '%d/%d（%.1f%%、%.0f〜%.0f）' % (k, n, p * 100, lo * 100, hi * 100)


def binom_two_sided(k, n):
    # 符号検定（引き分けを除く）
    if n == 0:
        return 1.0
    tail = sum(math.comb(n, i) for i in range(0, min(k, n - k) + 1)) / 2 ** n
    return min(1.0, 2 * tail)


# ── 生成: 費用・キャッシュ・時間 ──
P('## 1. 生成：費用・キャッシュ・時間\n')
P('| | 今の並び | 新しい並び |')
P('|---|---|---|')
rows = {a: [r for r in gen if r['arm'] == a] for a in ARMS}
rounds = {a: collections.defaultdict(list) for a in ARMS}
for a in ARMS:
    for r in rows[a]:
        rounds[a][r['bucket']].append(r)
def cell(f):
    return ' | '.join(f(a) for a in ARMS)
nround = {a: len(rounds[a]) for a in ARMS}
P('| 試合（6本ずつ） | %s |' % cell(lambda a: str(nround[a])))
P('| 生成の費用（合計） | %s |' % cell(lambda a: '$%.3f' % sum(r.get('usd', 0) for r in rows[a])))
P('| 1試合あたり | %s |' % cell(lambda a: '$%.4f' % (sum(r.get('usd', 0) for r in rows[a]) / max(1, nround[a]))))
tok = lambda a, k: sum((r.get('usage') or {}).get(k, 0) or 0 for r in rows[a])
P('| 入力（キャッシュなし）トークン | %s |' % cell(lambda a: '{:,}'.format(tok(a, 'input_tokens'))))
P('| キャッシュ書き込みトークン | %s |' % cell(lambda a: '{:,}'.format(tok(a, 'cache_creation_input_tokens'))))
P('| キャッシュ読み込みトークン | %s |' % cell(lambda a: '{:,}'.format(tok(a, 'cache_read_input_tokens'))))
P('| 出力トークン | %s |' % cell(lambda a: '{:,}'.format(tok(a, 'output_tokens'))))
def hit_rounds(a):
    good = 0
    for recs in rounds[a].values():
        reads = sum(1 for r in recs if ((r.get('usage') or {}).get('cache_read_input_tokens') or 0) > 0)
        good += reads == 5
    return '%d/%d' % (good, nround[a])
P('| 2〜6本目がすべてキャッシュを読んだ試合 | %s |' % cell(hit_rounds))
def lat(a, f):
    vals = [f(recs) for recs in rounds[a].values()]
    vals = [v for v in vals if v is not None]
    return '%.1f秒' % (statistics.median(vals) / 1000) if vals else '-'
first_obj = lambda recs: min([r['first_obj_ms'] for r in recs if r.get('first_obj_ms') is not None], default=None)
all_done = lambda recs: max([r['done_ms'] for r in recs if r.get('done_ms') is not None], default=None)
P('| 最初の1問まで（中央値） | %s |' % cell(lambda a: lat(a, first_obj)))
P('| 6本そろうまで（中央値） | %s |' % cell(lambda a: lat(a, all_done)))
P('| 失敗した呼び出し | %s |' % cell(lambda a: str(sum(1 for r in rows[a] if not r.get('text')))))
P('| 拒否（refusal） | %s |' % cell(lambda a: str(sum(1 for r in rows[a] if r.get('stop_reason') == 'refusal'))))
P('')

if acc:
    P('## 2. ゲームの採用判定（形式・漢字・重複）\n')
    P('| | 今の並び | 新しい並び |')
    P('|---|---|---|')
    ar = {a: [r for r in acc['rows'] if r['arm'] == a] for a in ARMS}
    P('| 生成された問題 | %s |' % cell(lambda a: str(sum(r['raw'] for r in ar[a]))))
    P('| 形式に合格 | %s |' % cell(lambda a: pct(sum(len(r['normalized']) for r in ar[a]), sum(r['raw'] for r in ar[a]))))
    P('| 採用（漢字・重複も合格） | %s |' % cell(lambda a: pct(sum(len(r['accepted']) for r in ar[a]), sum(r['raw'] for r in ar[a]))))
    def short_rounds(a):
        per = collections.Counter()
        for r in ar[a]:
            per[r['bucket']] += len(r['accepted'])
        return '%d/%d' % (sum(1 for v in per.values() if v < 10), len(per))
    P('| 採用が10問に届かない試合 | %s |' % cell(short_rounds))
    P('')

if judged:
    P('## 3. 正しさ：正解を伏せた解き直し（Opus 5.5・effort medium、毎週の判定と同じ基準）\n')
    P('| | 今の並び | 新しい並び |')
    P('|---|---|---|')
    sol = {a: {k: v for k, v in judged['solve'].items() if k.startswith('s-%s-' % a)} for a in ARMS}
    n_ok = lambda a: sum(1 for v in sol[a].values() if v)
    passed = lambda a: sum(1 for v in sol[a].values() if v and v['verdict'] == 'pass')
    P('| 採点できた問題 | %s |' % cell(lambda a: str(n_ok(a))))
    P('| 合格 | %s |' % cell(lambda a: pct(passed(a), n_ok(a))))
    P('| 自信なし（unsure） | %s |' % cell(lambda a: str(sum(1 for v in sol[a].values() if v and v['verdict'] == 'unsure'))))
    P('| 不合格 | %s |' % cell(lambda a: str(sum(1 for v in sol[a].values() if v and v['verdict'] == 'fail'))))
    issues = {a: collections.Counter() for a in ARMS}
    for a in ARMS:
        for v in sol[a].values():
            if v and v['verdict'] == 'fail':
                if v['issues']:
                    issues[a].update(v['issues'])
                else:
                    issues[a]['answer_mismatch'] += 1
    for code in sorted(set(issues['old']) | set(issues['new'])):
        P('| 　%s | %s |' % (code, cell(lambda a: str(issues[a][code]))))
    def usable(a):
        per = collections.Counter()
        for k, v in sol[a].items():
            if v and v['verdict'] == 'pass':
                per[int(k.split('-')[2])] += 1
        vals = [per[b] for b in range(len(prompts['buckets']))]
        return '%.1f問（10問未満 %d試合）' % (statistics.mean(vals), sum(1 for x in vals if x < 10))
    P('| 1試合で使える問題（採用かつ合格、24候補中） | %s |' % cell(usable))
    P('')
    P('## 4. 一対比較（同じ区分・同じ単元の組どうし、Opus 5.5・effort medium、A/B の位置は交互）\n')
    wins = collections.Counter()
    for k, v in judged['pair'].items():
        if not v:
            continue
        order = k.split('-')[3]  # ON: A=old, NO: A=new
        w = v['winner']
        if w == 'tie':
            wins['tie'] += 1
        elif (w == 'A') == (order == 'ON'):
            wins['old'] += 1
        else:
            wins['new'] += 1
    decided = wins['old'] + wins['new']
    P('| 今の並びの勝ち | 新しい並びの勝ち | 引き分け | 符号検定 p |')
    P('|---|---|---|---|')
    P('| %d | %d | %d | %.2f |' % (wins['old'], wins['new'], wins['tie'], binom_two_sided(wins['new'], decided)))
    P('')
    P('採点の費用: $%.3f（Batch API、半額）' % judged['usd'])

open(os.path.join(D, 'report.md'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('wrote report.md')
