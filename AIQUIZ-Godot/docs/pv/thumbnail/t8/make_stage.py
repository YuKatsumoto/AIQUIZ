"""t8（絵コンテ gen_v2/a_shoulder.png の肩タックル）の演出の値を作る → stage.json（撮影の台本 pv_thumb_runtime.gd の t8 が読む）。
  python docs/pv/thumbnail/t8/make_stage.py
P1 の姿は pose.json（Sprint_Loop の 0.33 から部品を回す）。破片は 3 種：レンズのすぐ手前の大きな板と P1 のまわりの箱・細かい欠片
（hero_debris：画面の位置とカメラからの距離）、扉の穴の縁の割れ残り（anchored_debris：壁の中心・床からの位置）。
ゲームの破片（物理で飛ぶ 20 個）は隠す（hide_chunks）。手前の板は dof_near でぼかす。
値は画角調整ツール（ThumbnailCameraTuner.cmd t8 76 watch=1）の止めた絵を見ながら決めた（stage.json を書き換えると当て直す）"""
import json, math, random, sys
from pathlib import Path
rng = random.Random(8)
HERE = Path(__file__).resolve().parent
pose = json.loads((HERE / "pose.json").read_text(encoding="utf-8"))
out = []
def rot(k=1.0): return [rng.uniform(-50, 50) * k, rng.uniform(-60, 60) * k, rng.uniform(-50, 50) * k]
# レンズのすぐ手前の大きな板（画面の縁を埋める。左 1/3 の真ん中はロゴのために空ける）
for (u, v, d, s), r in zip([(0.20, 1.02, 0.75, (0.95, 0.45, 0.32)), (0.52, 1.06, 0.70, (0.70, 0.40, 0.30)),
                   (0.90, 0.98, 0.70, (0.80, 0.55, 0.32)), (1.02, 0.55, 0.80, (0.60, 0.80, 0.30)),
                   (0.95, 0.04, 0.85, (0.85, 0.50, 0.30)), (0.62, 0.00, 1.00, (0.75, 0.40, 0.28)),
                   (0.40, 0.03, 1.20, (0.45, 0.30, 0.25))],
                  [(55, 20, 35), (-40, 35, -50), (35, -30, 60), (20, 50, -25), (-30, 25, 40), (45, -20, -30), (30, 40, 20)]):
    out.append([u, v, d, *s, *r])
# P1 の手前と横の中くらいの箱（P1 はカメラから約 2.2 m）
for u, v, d, s in [(0.62, 0.30, 1.6, 0.30), (0.60, 0.66, 1.4, 0.28), (0.97, 0.36, 1.5, 0.36), (0.72, 0.14, 1.8, 0.28),
                   (0.53, 0.46, 1.7, 0.22), (0.70, 0.86, 1.2, 0.28), (0.90, 0.74, 1.4, 0.30), (0.84, 0.18, 1.9, 0.24),
                   (0.46, 0.25, 1.9, 0.18), (0.48, 0.70, 1.5, 0.20)]:
    out.append([u, v, d, s, s * rng.uniform(0.8, 1.2), s * rng.uniform(0.7, 1.1), *rot()])
# 扉の穴から外へ広がる細かい欠片（P1 より手前）
cu, cv = 0.80, 0.42
for i in range(40):
    a = rng.uniform(0, 6.283)
    r = rng.uniform(0.10, 0.48)
    u, v = cu + math.cos(a) * r, cv + math.sin(a) * r * 1.4
    if not (0.40 < u < 1.02 and -0.02 < v < 1.02):
        continue
    s = rng.uniform(0.04, 0.12)
    out.append([u, v, rng.uniform(1.3, 2.2), s, s, s, *rot()])
data = dict(pose)
data["hero_debris"] = [[round(x, 3) for x in p] for p in out]
# 扉の穴の縁の割れ残り（壁基準。穴は x 1.7〜5.3・y 0〜3.58、手前の面は z +0.6）
rem = []
def chunk(x, y, z, s, inward):
    rem.append([x, y, z, s * rng.uniform(0.7, 1.3), s * rng.uniform(0.7, 1.3), s * rng.uniform(0.5, 0.9),
                rng.uniform(-35, 35) + inward[0], rng.uniform(-35, 35) + inward[1], rng.uniform(-35, 35)])
for i in range(9):
    y = 0.2 + i * 0.4
    chunk(1.7 + rng.uniform(0.05, 0.35), y, rng.uniform(0.3, 0.8), rng.uniform(0.35, 0.6), (0, 25))
    chunk(5.3 - rng.uniform(0.05, 0.35), y, rng.uniform(0.3, 0.8), rng.uniform(0.35, 0.6), (0, -25))
for i in range(9):
    x = 1.9 + i * 0.4
    chunk(x, 3.58 - rng.uniform(0.05, 0.35), rng.uniform(0.3, 0.8), rng.uniform(0.35, 0.6), (25, 0))
data["anchored_debris"] = [[round(x, 3) for x in p] for p in rem]
data["dof_near"] = [0.9, 0.4]
(HERE / "stage.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
print(len(out), "pieces")
