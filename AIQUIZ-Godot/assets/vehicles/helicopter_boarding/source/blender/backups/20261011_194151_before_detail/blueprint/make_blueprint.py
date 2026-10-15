"""乗り込めるヘリとパイロットの設計図（v1）を作る。

  python artifacts/heli_blueprint/make_blueprint.py

出力（artifacts/heli_blueprint/ の下）
  sheets/sheet_XX.svg   図面（1 枚ずつ）
  png/sheet_XX.png      同じ図面の PNG（Edge のヘッドレスで書き出す）
  heli_pilot_blueprint.html   全部の図面を 1 ページに並べたもの
  heli_pilot_spec.json        寸法・マーカー・チェックの数値（Blender / Godot の実装はこの数値を使う）

数値の元：heli_design.py（ヘリの寸法）、cast.py（人物の置き方）、analysis.py（集計とチェック）。
人物の寸法は Godot で採寸したもの（data/poses.json、data/hats.json。probes/ のスクリプトで取り直せる）。
"""
import json
import math
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import analysis  # noqa: E402
import cast  # noqa: E402
import heli_design as hd  # noqa: E402
from blueprint_lib import Mesh, affine, glb_meshes, iso_view, render, rot_axis, yaw  # noqa: E402
from svg_sheet import ACCENT, DIM, INK, MARK, MUTED, NG, OK, Sheet, fmt  # noqa: E402

ROOT = HERE.parents[1]
OLD_HELI = ROOT / "assets" / "vehicles" / "helicopter" / "helicopter_drop.glb"
OLD_SKID_DROP = 1.392
OLD_PILOT_POS = (0.0, -0.16, -1.08)
OLD_PILOT_ROT = (8.0, 180.0, 0.0)
OLD_GP_SEAT = (0.0, 0.10, -0.42)
YOKES = cast.yoke_specs()
CHECKS = analysis.check_rows()
OVERALL = analysis.overall()
INTERIOR = analysis.interior()
BLUE_TINT = (0.20, 0.65, 0.90)


# ---------------------------------------------------------------- 場面

def new_scene(door_l=0.0, door_r=0.0, player=("sit_idle", hd.PASSENGER_PELVIS, 180.0, "seat"), hatena="seated",
              cut=None, hatch=0.0, paint=hd.BODY_PAINT, tint=cast.P1_TINT, extra_players=()):
    meshes = hd.build_heli(door_l=door_l, door_r=door_r, hatch=hatch, yokes=YOKES, paint=paint, cut=cut)
    if hatena:
        hm, _, _ = cast.hatena(hatena)
        meshes += hm
    for p in ([player] if player else []) + list(extra_players):
        pose, anchor, yaw_deg, mode = p
        pm, _ = cast.player(pose, anchor, yaw_deg, mode, tint)
        meshes += pm
    return meshes


def old_scene(with_pilot=True, gp_passenger=True, pilot_pose="current", cut_x=None):
    tint = {"BodyPaint": hd.BODY_PAINT, "Charcoal": hd.CHARCOAL, "DropHatchInterior": (0.35, 0.33, 0.30), "Windows": hd.GLASS}
    meshes = [m.transformed(affine(None, (0, OLD_SKID_DROP, 0))) for m in glb_meshes(OLD_HELI, tint)]
    if cut_x is not None:
        meshes = [Mesh(m.name, m.tris[m.tris.mean(1)[:, 0] > cut_x], m.color, m.glass, m.emissive, m.back_color) for m in meshes]
        meshes = [m for m in meshes if len(m.tris)]
    if with_pilot:
        R = yaw(OLD_PILOT_ROT[1]) @ rot_axis([1, 0, 0], math.radians(OLD_PILOT_ROT[0]))
        pos = (OLD_PILOT_POS[0], OLD_PILOT_POS[1] + OLD_SKID_DROP, OLD_PILOT_POS[2])
        hm, _, _ = cast.hatena(pilot_pose, xform=affine(R, pos, 0.35))
        meshes += hm
    if gp_passenger:
        pel = (OLD_GP_SEAT[0], OLD_GP_SEAT[1] + OLD_SKID_DROP, OLD_GP_SEAT[2])
        pm, _ = cast.player("proc_sit", pel, 0.0, "seat")
        meshes += pm
    return meshes


def outline_z(s, vp, z, u_clip=None, inner=True):
    """z で切った断面の輪郭を太線で（外板）と点線で（内張り）。"""
    s.poly([vp.px((x, y, z)) for x, y in hd.section_outline("z", z)], INK, 3.0, closed=True)
    if inner:
        s.poly([vp.px((x, y, z)) for x, y in hd.section_outline("z", z, inner=True)], INK, 1.0, closed=True, dash="5 3")


# ---------------------------------------------------------------- 図 1 まとめ

def sheet_cover():
    s = Sheet(1, "全体のまとめ", "プレイヤーが乗り込めるヘリと、ちゃんと座る操縦士ハテナ")
    scene = new_scene(door_l=1.0, hatena="wave", player=("walk_a", analysis.MK["MK_Step"]["pos"], 90.0, "feet"))
    view = iso_view(40, 15)
    r = render(scene, view, (-6.0, 6.0, -2.3, 5.8), 86)
    s.place(r, view, 40, 150)
    s.text(60, 136, "完成形のブロックアウト（左のドアを開け、ステップに乗ったところ。ハテナは右の席で手を振る）", 15, 400, MUTED)
    x0 = 1090
    y = s.note_box(x0, 112, 670, "この設計でできること", [
        "・プレイヤー（2.3 m の箱の人形）が、歩いて → ステップ → 床 と 2 段で乗り込み、左の席に座る。",
        "・操縦士ハテナは等倍（今は 0.35 倍）で右の席に座り、U 字の操縦かんを握る。",
        "・ドアはガルウィング（屋根の梁のふちを軸に上へ 90° 開く）。いちばん高い帽子でも頭をぶつけない。",
        "・正面カメラで 2 人の顔が計器盤の上に見える（並んで飛ぶカット用）。",
        "・床下ハッチ（本編の投下）は名前もしくみも今のまま残す。",
    ], size=15, fill="#f2f7ff", stroke=DIM)
    rows = [["項目", "新しいヘリ", "今のヘリ"],
            ["全長（機首〜尾）", f"{OVERALL['length_body']:.2f} m", "7.54 m"],
            ["胴体の幅", f"{OVERALL['width_body']:.2f} m", "1.75 m"],
            ["高さ（屋根／ローター軸）", f"{OVERALL['height_roof']:.2f} / {OVERALL['height_hub']:.2f} m", "2.88 / 2.73 m"],
            ["メインローターの直径", f"{OVERALL['rotor_diameter']:.2f} m（2 枚）", "約 7.6 m"],
            ["キャビンの高さ（座席の上の床〜天井）", f"{INTERIOR['headroom_at_seat']:.2f} m", "約 1.1 m（ハッチの箱）"],
            ["座席", "2（左：プレイヤー、右：ハテナ）", "なし"],
            ["ドア", f"ガルウィング 2 枚（開口 {INTERIOR['door_open_length']:.2f} m）", "なし（床下ハッチだけ）"],
            ["操縦士ハテナ", "等倍 1.0・座席に座る", "0.35 倍・宙に浮く"]]
    y = s.table(x0, y + 22, [250, 250, 170], rows, size=14) + 26
    ok = sum(1 for c in CHECKS if c[3])
    s.text(x0, y + 4, f"すき間のチェック：{ok} / {len(CHECKS)} 項目 OK（図 4）", 16, 700, OK if ok == len(CHECKS) else NG)
    y += 30
    s.note_box(x0, y, 670, "決めてほしいこと", [
        "① 左右の席：左＝プレイヤー、右＝ハテナ（正面から見ると、プレイヤーは画面の右側）。逆にしたい場合は席を入れ替えるだけ（左右同じ寸法）。",
        "② プレイヤーの席にも操縦かんを付けて、飛んでいる間は Driving_Loop（ハンドルを握る）にするか。付けない場合は Sitting_Idle_Loop（図 7 の下）。",
        "③ ゲーム本編のヘリ（ハッチから投下）もこの機体に替えるか。大きさが 2 倍近くになるので、本編の演出の高さ・カメラは調整が要る（段階 2）。",
    ], size=14)
    yb = 960
    s.text(60, yb, "図面の一覧", 18, 700)
    items = ["図 1 全体のまとめ", "図 2 今のヘリの問題", "図 3 外形三面図", "図 4 操縦室の断面とすき間のチェック",
             "図 5 ドア・ステップ・ローターの止め方", "図 6 乗り込みの手順とタイムライン", "図 7 操縦士ハテナ", "図 8 ノード構成と Godot との約束", "図 9 完成イメージ（Codex で生成）"]
    for i, it in enumerate(items):
        s.text(60 + (i % 3) * 340, yb + 32 + (i // 3) * 26, it, 15, 400, INK)
    s.para(60, yb + 124, "単位は m（Godot の 1 = 1 m）。高さは地面（スキッドの下面）を 0 とした値。GLB の原点は「メインローターの軸 × 地面から 1.75 m」（今のヘリと同じく、原点から SKID_DROP 下がスキッドの下面）。機首は -Z、プレイヤーの席は -X 側。", 1000, 14, MUTED)
    return s


# ---------------------------------------------------------------- 図 2 今の問題

def sheet_problems():
    s = Sheet(2, "今のヘリの問題", "同じ縮尺（1 m = 62 px）。機体は真ん中（x = 0）で切って中を見せ、人物は切らない")
    ppm = 62
    stand_front = cast.player("idle", (0.0, 0.0, -4.4), 90.0, "feet")[0]
    r_old = render(old_scene(cut_x=0.0) + stand_front, "side", (-5.4, 5.6, -0.2, 3.6), ppm)
    vp = s.place(r_old, "side", 50, 175, "今のヘリ（左から・真ん中で切る）")
    s.hline_world(vp, 0.0, (-5.4, 5.6), None, MUTED)
    s.leader(vp, (0, 2.0, -4.4), 150, 195, ["プレイヤー（立つ）2.30 m", "帽子込みで最大 2.98 m"], INK, 13)
    s.leader(vp, (0, OLD_SKID_DROP - 0.16 + 0.42, -1.08), 300, 455, ["操縦士ハテナ 0.35 倍（0.71 m）", "座席がなく宙に浮く"], NG, 13, 700)
    s.leader(vp, (0, OLD_SKID_DROP + 0.10 + 0.5, -0.42), 560, 455, ["本編の乗客（GP_PASSENGER_SEAT）", "床・座席・ドアのない所に直接置く"], NG, 13, 700)
    s.dim(vp, (0, OLD_SKID_DROP - 0.606, -2.55), (0, OLD_SKID_DROP + 1.492, -2.55), -26, "胴体 2.10", orient="v")
    stand_front_new = cast.player("idle", (0.0, 0.0, -4.4), 90.0, "feet")[0]
    new = new_scene(cut=("x", 0.0, "+")) + stand_front_new
    r_new = render(new, "side", (-5.4, 7.6, -0.2, 4.3), ppm)
    vp2 = s.place(r_new, "side", 930, 175 - 0.7 * ppm, "新しいヘリ（左から・真ん中で切る）")
    s.hline_world(vp2, 0.0, (-5.4, 7.6), None, MUTED)
    s.leader(vp2, (0, 2.3, -1.10), 1320, 470, ["プレイヤーは左の席に座る", "（いちばん高い帽子でも天井まで 0.14 m）"], OK, 13, 700)
    s.leader(vp2, (0, 2.0, -1.45), 1060, 470, ["ハテナは等倍で右の席"], OK, 13, 700)
    s.dim(vp2, (0, hd.BELLY_Y, -3.0), (0, OVERALL["height_roof"], -3.0), -20, f"胴体 {OVERALL['height_roof'] - hd.BELLY_Y:.2f}", orient="v")
    # 接写（正面）
    r_close = render(old_scene(gp_passenger=False), "front", (-1.2, 1.2, 1.0, 3.0), 180)
    vpc = s.place(r_close, "front", 50, 560, "今の操縦席（正面から接写）")
    s.leader(vpc, (0.0, OLD_SKID_DROP - 0.16 + 0.10, -1.08), 540, 650, ["足が体の下に折れて見える", "（骨に絶対の回転を入れている）"], NG, 13, 700)
    s.leader(vpc, (0.3, OLD_SKID_DROP + 0.05, -1.3), 540, 760, ["中が空っぽ：座席・計器盤・", "操縦かんがない"], NG, 13, 700)
    r_new_front = render(new_scene(), "front", (-2.0, 2.0, 0.95, 3.55), 128)
    vpn = s.place(r_new_front, "front", 930, 560, "新しい操縦席（正面から）")
    s.leader(vpn, (hd.SEAT_X, cast.hatena_root()[1] + 1.25, -1.8), 1500, 620, ["ハテナ（等倍）は右の席", "U 字の操縦かんを握る"], OK, 13, 700)
    s.leader(vpn, (-hd.SEAT_X, 2.45, -1.3), 1500, 720, ["プレイヤーは左の席", "（正面からは画面の右）"], OK, 13, 700)
    s.note_box(50, 960, 1700, "問題（数値は Godot で採寸）", [
        "1. 大きさが合わない：プレイヤーは立って 2.30 m・腕込みの幅 1.7 m。今の胴体は幅 1.75 m・高さ 2.10 m、ハッチの箱は 0.85×1.13×1.00 m しかなく、座る場所もドアもない。",
        "2. 操縦士だけ縮めている：ハテナは審判・ノコギリでは等倍（2.04 m）なのに、ヘリでは 0.35 倍（0.71 m）。プレイヤーと並ぶと人形のように見える。",
        "3. 座り方がおかしい：set_bone_pose_rotation に「初期姿勢を無視した絶対の回転」を入れているため、もも（+78°）が後ろへ折れ、腕は上がる。座席もないので体が宙に浮く。",
        "4. 立ち位置の基準：プレイヤーの足の裏は BASE_Y（-1.20）より 0.14〜0.19 m 下にある（ポーズによる）。乗り込みの位置合わせは BASE_Y ではなく足の裏の実測で行う。",
    ], size=14, fill="#fff5f5", stroke=NG)
    return s


# ---------------------------------------------------------------- 図 3 三面図

def sheet_three_view():
    s = Sheet(3, "外形三面図", "ドアを閉じ、ローターを前後に止めた状態。人物なし")
    ppm = 58
    heli = hd.build_heli(yokes=YOKES)
    ov = OVERALL
    z0, z1 = -5.7, 7.4
    r_side = render(heli, "side", (z0, z1, -0.2, 4.5), ppm)
    vs = s.place(r_side, "side", 70, 200, "横から（左側）")
    s.hline_world(vs, 0.0, (z0, z1), None, MUTED)
    s.text(vs.uv_px(z1, 0)[0] - 4, vs.uv_px(z1, 0)[1] + 18, "地面（スキッドの下面）", 12, 400, MUTED, "end")
    s.dim(vs, (0, ov["height_hub"], -hd.ROTOR_RADIUS), (0, ov["height_hub"], hd.ROTOR_RADIUS), -14, f"ローター直径 {ov['rotor_diameter']:.2f}")
    s.dim(vs, (0, 1.3, ov["nose_z"]), (0, 4.1, ov["tail_z"]), -52, f"全長 {ov['length_body']:.2f}")
    s.dim(vs, (0, 0, ov["nose_z"]), (0, 0, 0.0), 40, f"機首〜ローター軸 {-ov['nose_z']:.2f}")
    s.dim(vs, (0, 0, 0.0), (0, 0, hd.TAIL_ROTOR["z"]), 40, f"ローター軸〜尾のローター {hd.TAIL_ROTOR['z']:.2f}")
    s.dim(vs, (0, 0, ov["tail_z"]), (0, ov["height_fin"], ov["tail_z"]), 22, f"尾翼 {ov['height_fin']:.2f}", orient="v")
    s.dim(vs, (0, 0, ov["nose_z"]), (0, ov["height_roof"], ov["nose_z"]), -40, f"屋根 {ov['height_roof']:.2f}", orient="v")
    s.dim(vs, (0, 0, -4.6), (0, ov["height_hub"], -4.6), -14, f"ハブ {ov['height_hub']:.2f}", orient="v")
    s.dim(vs, (0, 0, 2.4), (0, hd.BELLY_Y, 2.4), 12, f"{hd.BELLY_Y:.2f}", orient="v")
    s.marker(vs, (0, hd.ORIGIN_Y, 0), "原点（重心・ローター軸）", 12, -10)
    # 上から
    r_top = render(heli, "top", (z0, z1, -2.7, 2.7), ppm)
    vt = s.place(r_top, "top", 70, 200 + r_side.image.size[1] + 90, "上から（機首が左・機体の右が上）")
    s.dim(vt, (-ov["width_body"] / 2, 0, ov["nose_z"] - 0.1), (ov["width_body"] / 2, 0, ov["nose_z"] - 0.1), -40, f"胴体の幅 {ov['width_body']:.2f}", orient="v")
    s.dim(vt, (-hd.SKID_X, 0, hd.SKID_Z[1]), (hd.SKID_X, 0, hd.SKID_Z[1]), 30, f"スキッド {ov['skid_track']:.2f}", orient="v")
    s.dim(vt, (-hd.STAB["half_span"], 0, hd.STAB["z0"]), (hd.STAB["half_span"], 0, hd.STAB["z0"]), -18, f"{2 * hd.STAB['half_span']:.2f}", orient="v")
    st = hd.STEP
    s.leader(vt, ((st["x0"] + st["x1"]) / 2, 3.0, (st["z0"] + st["z1"]) / 2), vt.px((0, 0, -0.2))[0], vt.y + r_top.image.size[1] + 24, "乗り込みステップ（左だけ）", INK, 13)
    s.text(vt.x + r_top.image.size[0] - 4, vt.y + r_top.image.size[1] + 48, "メインローターは前後（機首と尾の向き）に止める", 13, 400, MUTED, "end")
    # 正面
    r_front = render(heli, "front", (-2.6, 2.6, -0.2, 4.5), ppm)
    xf = 70 + r_side.image.size[0] + 80
    vf = s.place(r_front, "front", xf, 200, "正面から（機体の左が画面の右）")
    s.hline_world(vf, 0.0, (-2.6, 2.6), None, MUTED)
    s.dim(vf, (hd.SKID_X, 0, 0), (-hd.SKID_X, 0, 0), 40, f"スキッド {ov['skid_track']:.2f}")
    s.dim(vf, (ov["width_body"] / 2, 1.0, 0), (-ov["width_body"] / 2, 1.0, 0), 0, f"胴体の幅 {ov['width_body']:.2f}", ext=False)
    rows = [["寸法", "値（m）"],
            ["全長（機首〜尾の端）", fmt(ov["length_body"])], ["ローター込みの長さ", fmt(ov["overall_length_rotor"])],
            ["胴体の幅／屋根の高さ", f"{ov['width_body']:.2f} / {ov['height_roof']:.2f}"],
            ["ローター軸の高さ（ハブ上面）", fmt(ov["height_hub"])], ["垂直尾翼の上端", fmt(ov["height_fin"])],
            ["メインローター直径（2 枚・弦 0.34）", fmt(ov["rotor_diameter"])],
            ["尾のローター直径（右側・中心の高さ 3.62）", fmt(ov["tail_rotor_diameter"])],
            ["スキッド：間隔／長さ／管の太さ", f"{ov['skid_track']:.2f} / {ov['skid_length']:.2f} / 0.12"],
            ["胴体の下面／床／ステップ", f"{hd.BELLY_Y:.2f} / {hd.FLOOR_Y:.2f} / {hd.STEP_Y:.2f}"],
            ["GLB の原点（地面からの高さ＝SKID_DROP）", fmt(hd.ORIGIN_Y)]]
    xt = xf + r_front.image.size[0] + 50
    s.table(xt, 200, [330, 170], rows, size=13.5)
    s.note_box(xf, 640, 1760 - xf, "形のねらい", [
        "・人物（2.3 m）が乗るので、胴体は今の約 2 倍の幅。ずんぐりした「おもちゃのヘリ」の形にして、子どもに読みやすくする。",
        "・前と上は一枚の大きな風防（バブル）。正面と斜め上から、中の 2 人がよく見える。",
        "・断面は角の丸い箱（上半分の丸み n = 3.3、下半分 n = 3.6）。形の数値は heli_design.py の BODY_* にある。",
        "・尾のローターは右側。下の端は 2.97 m で、いちばん高い帽子の人（2.92 m）より上。それでも尾のそばは歩かせない。",
    ], size=14, fill="#f2f7ff", stroke=DIM)
    return s


# ---------------------------------------------------------------- 図 4 断面

def hat_envelope_pts(mount):
    """どの帽子でも入る外形（正面から見た段）。(x, y) の折れ線と、いちばん高い値。"""
    hats = [(max(abs(h["min"][0]), abs(h["max"][0])), h["max"][1]) for h in cast.HATS.values() if h["min"][0] < 1e8]
    halves = sorted({round(h, 3) for h, _ in hats}, reverse=True)
    env = [(hw, max(t for h, t in hats if h >= hw - 1e-6)) for hw in halves]
    cx, base = mount[0], mount[1]
    left, prev = [(cx - env[0][0], base)], None
    for hw, top in env:
        if prev is not None:
            left.append((cx - hw, base + prev))
        left.append((cx - hw, base + top))
        prev = top
    right = [(2 * cx - x, y) for x, y in reversed(left)]
    return left + right, max(t for _, t in hats)


def sheet_sections():
    s = Sheet(4, "操縦室の断面とすき間のチェック", "A-A：座った pelvis の位置（z = -1.10）で前後に切る　B-B：プレイヤーの席の中心（x = -0.77）で左右に切る")
    ppm = 138
    za = hd.PASSENGER_PELVIS[2]
    r_a = render(new_scene(cut=("z", za, "+")), "front", (-2.05, 2.05, 0.35, 3.85), ppm)
    va = s.place(r_a, "front", 60, 150, "A-A 断面（前から見る。左がハテナ、右がプレイヤー。青い点線＝計器盤の上端）")
    outline_z(s, va, za)
    xf = cast.player_xform("sit_idle", hd.PASSENGER_PELVIS)
    mount = cast.player_joint("sit_idle", "hat_mount", xf)
    stair, hmax = hat_envelope_pts(mount)
    s.poly([va.px((x, y, za)) for x, y in stair], ACCENT, 1.8, dash="5 3")
    s.leader(va, (mount[0] - 0.05, mount[1] + hmax, za), va.x + r_a.image.size[0] - 8, va.y + 24, ["帽子 16 種が入る外形", f"いちばん高い +{hmax:.2f}"], ACCENT, 13, 700)
    ceil = analysis.interior_ceiling(mount[0], za)
    s.dim(va, (mount[0] - 0.55, hd.FLOOR_Y, za), (mount[0] - 0.55, ceil, za), 0, f"床〜天井 {ceil - hd.FLOOR_Y:.2f}", orient="v", ext=False)
    s.dim(va, (hd.SEAT_X, hd.FLOOR_Y, za), (-hd.SEAT_X, hd.FLOOR_Y, za), 30, f"座席の中心の間 {2 * hd.SEAT_X:.2f}")
    w_in = analysis.interior_half_width(1.9, za)
    s.dim(va, (w_in, 1.9, za), (-w_in, 1.9, za), 0, f"内のり幅 {2 * w_in:.2f}", ext=False)
    s.hline_world(va, hd.DASH_TOP_Y + 0.06, (-1.65, 1.65), None, DIM, "4 3")
    s.hline_world(va, hd.SEAT_TOP_Y, (0.25, 1.35), None, MUTED, "2 3")
    s.text(va.uv_px(1.35, 0)[0], va.uv_px(0, hd.SEAT_TOP_Y)[1] - 4, f"座面 {hd.SEAT_TOP_Y:.2f}", 12, 400, MUTED, "end")
    s.hline_world(va, hd.SEAT_TOP_Y + hd.BOOSTER_H, (-1.35, -0.25), None, MUTED, "2 3")
    s.text(va.uv_px(-1.35, 0)[0], va.uv_px(0, hd.SEAT_TOP_Y + hd.BOOSTER_H)[1] - 4, f"クッション {hd.SEAT_TOP_Y + hd.BOOSTER_H:.2f}", 12, 400, MUTED)
    # B-B
    xb = -hd.SEAT_X
    bz0, bz1 = -3.25, 0.25
    r_b = render(new_scene(cut=("x", xb, "+")), "side", (bz0, bz1, 0.35, 3.85), ppm)
    vb = s.place(r_b, "side", 60 + r_a.image.size[0] + 40, 150, "B-B 断面（左から見る）")
    up, lo = hd.section_outline("x", xb)
    upi, _ = hd.section_outline("x", xb, inner=True)
    clip = lambda pts: [p for p in pts if bz0 <= p[0] <= bz1]  # noqa: E731
    s.poly([vb.px((xb, y, z)) for z, y in clip(up)], INK, 3.0)
    s.poly([vb.px((xb, y, z)) for z, y in clip(lo)], INK, 3.0)
    s.poly([vb.px((xb, y, z)) for z, y in clip(upi)], INK, 1.0, dash="5 3")
    s.dim(vb, (xb, hd.FLOOR_Y, hd.SEAT_FRONT_Z), (xb, hd.SEAT_TOP_Y, hd.SEAT_FRONT_Z), -24, f"座面 {hd.SEAT_TOP_Y - hd.FLOOR_Y:.2f}", orient="v")
    s.dim(vb, (xb, hd.FLOOR_Y + 0.14, hd.SEAT_FRONT_Z), (xb, hd.FLOOR_Y + 0.14, hd.SEAT_BACK_Z), 0, f"奥行き {hd.SEAT_BACK_Z - hd.SEAT_FRONT_Z:.2f}", ext=False)
    s.dim(vb, (xb, hd.FLOOR_Y, hd.DASH_BACK_Z), (xb, hd.FLOOR_Y, hd.SEAT_FRONT_Z), 26, f"足元 {hd.SEAT_FRONT_Z - hd.DASH_BACK_Z:.2f}")
    s.marker(vb, hd.PASSENGER_PELVIS, "MK_SeatPassenger", 10, 24)
    lx = vb.x + r_b.image.size[0] + 26
    s.leader(vb, (xb, hd.SEAT_BACK_TOP_Y - 0.1, hd.SEAT_BACK_Z + 0.22), lx, 230, [f"背もたれ：{hd.SEAT_BACK_TILT_DEG:.0f}° 後ろへ", f"上端 {hd.SEAT_BACK_TOP_Y:.2f}"], INK, 13)
    g = YOKES[0]
    s.leader(vb, (xb, g["grip_l"][1], g["grip_l"][2]), lx, 320, ["操縦かんの握り", f"高さ {g['grip_l'][1]:.2f}・z {g['grip_l'][2]:.2f}", "（Driving_Loop の手首の位置）"], INK, 13)
    s.leader(vb, (xb, hd.DASH_TOP_Y - 0.1, hd.DASH_BACK_Z - 0.05), lx, 420, ["計器盤", f"上端 {hd.DASH_TOP_Y:.2f}・座席側の面 z {hd.DASH_BACK_Z:.2f}"], INK, 13)
    s.leader(vb, (xb, hd.SEAT_TOP_Y - 0.05, -1.2), lx, 500, ["座面：床から 0.48", "ももの下面が座面に乗る"], INK, 13)
    s.leader(vb, (xb, 1.0, hd.DOOR_FRONT_Z + 0.02), lx, 580, ["ドアの前端 z -2.25", "（ここより前は一枚の風防）"], INK, 13)
    rows = [["チェック項目", "すき間（m）", "基準", "結果", "メモ"]]
    colors = {}
    for i, (name, val, crit, ok, memo) in enumerate(CHECKS, start=1):
        rows.append([name, f"{val:+.3f}", crit, "OK" if ok else "NG", memo])
        colors[(i, 3)] = OK if ok else NG
    s.text(60, 690, "すき間のチェック（Godot で採寸した人物のポーズ × この寸法で計算。analysis.py）", 17, 700)
    s.table(60, 704, [420, 130, 220, 70, 840], rows, size=13, row_h=24, colors=colors)
    return s


# ---------------------------------------------------------------- 図 5 ドアとステップ

CUT_BOARD = -1.95   # 乗り込みの図は、ステップの少し前（乗る人の前）で切って前から見る


def sheet_door():
    s = Sheet(5, "ドア・ステップ・ローターの止め方", "左のドア（プレイヤー側）。右のドアは左右対称で、ふだんは閉じたまま")
    ppm = 86
    mk = analysis.MK
    scene = new_scene(door_l=1.0, hatena="wave", player=("walk_a", mk["MK_Step"]["pos"], 90.0, "feet"), cut=("z", CUT_BOARD, "+"))
    r = render(scene, "front", (-2.2, 4.6, -0.2, 5.6), ppm)
    vf = s.place(r, "front", 60, 160, f"C-C 断面（乗る人の前 z = {CUT_BOARD:.2f} で切って前から見る）")
    outline_z(s, vf, CUT_BOARD, inner=False)
    p0, p1 = hd.door_hinge("L")
    zc = mk["MK_Step"]["pos"][2]
    t = (zc - p0[2]) / (p1[2] - p0[2])
    hinge = p0 + (p1 - p0) * t
    closed = np.concatenate([m.tris.reshape(-1, 3) for m in hd.build_heli() if m.name == "door_L"])
    ring = closed[np.abs(closed[:, 2] - zc) < 0.03]
    ring = ring[np.argsort(np.arctan2(ring[:, 1] - hinge[1], ring[:, 0] - hinge[0]))]
    s.poly([vf.px(p) for p in ring], ACCENT, 1.2, dash="2 3")
    sill = ring[np.argmin(ring[:, 1])]
    rad = math.hypot(sill[0] - hinge[0], sill[1] - hinge[1])
    a0 = math.atan2(sill[1] - hinge[1], sill[0] - hinge[0])
    arc = [vf.px((hinge[0] + rad * math.cos(a0 - u), hinge[1] + rad * math.sin(a0 - u), zc)) for u in np.linspace(0, math.radians(hd.DOOR_OPEN_DEG), 40)]
    s.poly(arc, ACCENT, 1.4, dash="6 4")
    s.marker(vf, hinge, "ヒンジ", -12, -12)
    s.text(arc[24][0] + 10, arc[24][1] + 4, f"上へ {hd.DOOR_OPEN_DEG:.0f}°", 15, 700, ACCENT)
    s.hline_world(vf, 0.0, (-2.2, 4.6), None, MUTED)
    s.hline_world(vf, hd.STEP_Y, (2.15, 3.2), f"ステップ {hd.STEP_Y:.2f}", INK, "3 3")
    s.hline_world(vf, hd.FLOOR_Y, (1.3, 3.2), f"床 {hd.FLOOR_Y:.2f}", INK, "3 3")
    s.leader(vf, (mk["MK_Step"]["pos"][0], 3.25, zc), vf.x + r.image.size[0] - 10, vf.y + 40, ["いちばん高い帽子（チキン）でも", "開いたドアまで 1.4 m 以上あく"], OK, 13, 700)
    # 横から
    ppm2 = 122
    r2 = render(new_scene(player=None), "side", (-3.3, 0.3, -0.15, 4.0), ppm2)
    x2 = 60 + r.image.size[0] + 40
    vs = s.place(r2, "side", x2, 160, "横から：ドアの開口とステップ")
    door_poly = [(hd.DOOR_FRONT_Z, hd.DOOR_SILL_Y), (hd.DOOR_REAR_Z, hd.DOOR_SILL_Y)]
    for z in np.linspace(hd.DOOR_REAR_Z, hd.DOOR_FRONT_Z, 30):
        door_poly.append((z, hd.section_extent(z, x=hd.DOOR_HINGE_X)))
    s.poly([vs.px((-2, y, z)) for z, y in door_poly], ACCENT, 2.2, closed=True, dash="7 4")
    s.dim(vs, (-2, hd.DOOR_SILL_Y, hd.DOOR_FRONT_Z), (-2, hd.DOOR_SILL_Y, hd.DOOR_REAR_Z), -30, f"開口の長さ {hd.DOOR_REAR_Z - hd.DOOR_FRONT_Z:.2f}", ext=False)
    s.dim(vs, (-2, 0, -0.30), (-2, hd.DOOR_SILL_Y, -0.30), 8, f"敷居 {hd.DOOR_SILL_Y:.2f}", orient="v")
    s.dim(vs, (-2, hd.DOOR_SILL_Y, 0.18), (-2, INTERIOR["door_hinge_rear"], 0.18), 4, f"{INTERIOR['door_hinge_rear'] - hd.DOOR_SILL_Y:.2f}", orient="v")
    st = hd.STEP
    s.dim(vs, (-2, hd.STEP_Y, st["z0"]), (-2, hd.STEP_Y, st["z1"]), 64, f"ステップ {st['z1'] - st['z0']:.2f}")
    s.para(x2, vs.y + r2.image.size[1] + 92, f"ステップ：上面 {hd.STEP_Y:.2f}・奥行き {st['x1'] - st['x0']:.2f}（外へ張り出す）・幅 {st['z1'] - st['z0']:.2f}。前のクロスチューブに固定し、白にする（足を置く所がわかる）。", r2.image.size[0], 13, INK)
    # 上から
    ppm3 = 24
    r3 = render(hd.build_heli(door_l=1.0, door_r=1.0, yokes=YOKES), "top", (-6.0, 7.4, -5.6, 5.6), ppm3)
    x3 = x2 + r2.image.size[0] + 40
    vt = s.place(r3, "top", x3, 160, "上から：ブレードは前後に止める")
    s.circle(*vt.px((0, 0, 0)), hd.ROTOR_RADIUS * ppm3, stroke=MUTED, dash="6 4")
    s.para(x3, 160 + r3.image.size[1] + 26, "両方のドアを開けた状態。開いたドアとブレードは 0.42 m あく（図 4 のチェック）。", r3.image.size[0], 13, INK)
    s.note_box(60, 160 + r.image.size[1] + 30, r.image.size[0], "ドアの決まり", [
        f"・ガルウィング：ヒンジは屋根の梁のふち（x = ±{hd.DOOR_HINGE_X:.2f}）を前後に通る線（前端の高さ {INTERIOR['door_hinge_front']:.2f}、後端 {INTERIOR['door_hinge_rear']:.2f}。少し傾いている）。",
        f"・開く角度 {hd.DOOR_OPEN_DEG:.0f}°。開くのに 0.6 秒（ゆっくり止まる）、閉じるのに 0.6 秒。開いたドアは空のほうへ立ち、乗り込む人の頭の上をふさがない。",
        "・ドアの上半分はガラス（Windows 材質）、下は機体の色（BodyPaint）＋白い帯。ドアを開けている間はローターを回さない。",
        "・ローターは止まるとき必ず前後方向（ブレードが機首と尾の向き）にそろえる。開いたドアとブレードは 0.42 m あく。",
    ], size=14, fill="#fff7ef")
    return s


# ---------------------------------------------------------------- 図 6 乗り込みの手順

BOARDING = [
    (0.00, "① ボタンを押す", "idle", analysis.MK["MK_IdleSpot"]["pos"], 90.0, "feet", 0.05, "wave", "Idle_Loop → ヘリのほうを向く"),
    (0.70, "② ステップの前へ", "walk_b", analysis.MK["MK_BoardStand"]["pos"], 90.0, "feet", 1.0, "wave", "Walk_Loop（1.4 倍速）"),
    (1.05, "③ 1 段目（ステップ）", "walk_a", analysis.MK["MK_Step"]["pos"], 90.0, "feet", 1.0, "wave", "Walk の 1 歩＋root を +0.35"),
    (1.45, "④ 2 段目（床）・かがむ", "crouch_fwd", analysis.MK["MK_DoorSill"]["pos"], 90.0, "feet", 1.0, "seated", "Crouch_Fwd_Loop＋root を +0.35"),
    (1.95, "⑤ 機首へ向いて座席の前", "sit_enter_0", analysis.MK["MK_SeatFront"]["pos"], 180.0, "feet", 1.0, "seated", "その場で 90° 回る（0.3 秒）"),
    (2.60, "⑥ 座る", "sit_enter_2", (-hd.SEAT_X, hd.FLOOR_Y, -1.30), 180.0, "feet", 1.0, "seated", "Sitting_Enter（1.3 秒）＋後ろへ 0.56"),
    (3.30, "⑦ ベルト・ドアを閉じる", "sit_idle", hd.PASSENGER_PELVIS, 180.0, "seat", 0.35, "seated", "Sitting_Idle_Loop／Driving_Loop"),
]


def sheet_boarding():
    s = Sheet(6, "乗り込みの手順とタイムライン", f"「マッチング開始」を押してから離陸まで約 4.4 秒。絵は乗る人の前（z = {CUT_BOARD:.2f}）で切って前から見る")
    ppm = 46
    bounds = (-2.0, 5.0, -0.2, 5.4)
    x, y = 50, 140
    cell_w = cell_h = 0
    for i, (t, title, pose, anchor, yaw_deg, mode, door, hat, clip) in enumerate(BOARDING):
        scene = new_scene(door_l=door, hatena=hat, player=(pose, anchor, yaw_deg, mode), cut=("z", CUT_BOARD, "+"))
        r = render(scene, "front", bounds, ppm)
        cell_w, cell_h = r.image.size
        col, row = i % 4, i // 4
        px, py = x + col * (cell_w + 22), y + row * (cell_h + 92)
        s.rect(px - 4, py - 4, cell_w + 8, cell_h + 70, fill="#ffffff", stroke="#d5dce8", rx=6)
        vp = s.place(r, "front", px, py)
        outline_z(s, vp, CUT_BOARD, inner=False)
        s.hline_world(vp, 0.0, (bounds[0], bounds[1]), None, MUTED, "3 3")
        s.badge(px + 6, py + 22, f"{t:.2f} 秒", INK, size=13)
        s.text(px + 6, py + cell_h + 22, title, 15, 700)
        s.text(px + 6, py + cell_h + 44, clip, 13, 400, MUTED)
    ppm2 = 34
    mk = analysis.MK
    heli = hd.build_heli(door_l=1.0, yokes=YOKES)
    hm, _, _ = cast.hatena("seated")
    pm, _ = cast.player("sit_idle", hd.PASSENGER_PELVIS)
    r2 = render(heli + hm + pm, "top", (-3.6, 2.2, -4.9, 2.1), ppm2)
    px, py = x + 3 * (cell_w + 22), y + (cell_h + 92)
    s.rect(px - 4, py - 4, cell_w + 8, cell_h + 70, fill="#ffffff", stroke="#d5dce8", rx=6)
    vt = s.place(r2, "top", px + 8, py + 4)
    s.text(px + 6, py + cell_h + 44, "上から：通り道とマーカー（MK_ を省略）", 13, 700, INK)
    path = [mk[k]["pos"] for k in ("MK_IdleSpot", "MK_BoardStand", "MK_Step", "MK_DoorSill")] + [(-hd.SEAT_X, 0.7, mk["MK_DoorSill"]["pos"][2]), mk["MK_SeatFront"]["pos"], hd.PASSENGER_PELVIS]
    s.poly([vt.px(p) for p in path], ACCENT, 2.4)
    for k, dx, dy in (("MK_IdleSpot", 12, 4), ("MK_BoardStand", 12, 4), ("MK_Step", 12, 4), ("MK_DoorSill", 12, 4), ("MK_SeatFront", -12, -6), ("MK_SeatPassenger", 12, -8)):
        s.marker(vt, mk[k]["pos"], k.replace("MK_", ""), dx, dy, size=11)
    ty = y + 2 * (cell_h + 92) + 26
    s.text(50, ty, "タイムライン（秒）", 17, 700)
    tl_x, tl_w, t_max = 230, 1500, 4.6
    sx = lambda t: tl_x + t / t_max * tl_w  # noqa: E731
    lanes = [
        ("プレイヤー", [(0.0, 0.15, "向く", "#f6c08f"), (0.15, 0.90, "歩く（Walk 1.4×）", "#f6c08f"), (0.90, 1.25, "1 段目", "#f1a35e"),
                       (1.25, 1.65, "2 段目・かがむ", "#f1a35e"), (1.65, 1.95, "回る", "#f6c08f"), (1.95, 3.25, "Sitting_Enter（＋後ろへ 0.56）", "#e8792b"), (3.25, 4.6, "Sitting_Idle／Driving", "#f6c08f")]),
        ("左のドア", [(0.0, 0.6, "開く 0.6", "#9cc3ef"), (0.6, 3.0, "開いたまま", "#d6e6f8"), (3.0, 3.6, "閉じる 0.6", "#9cc3ef")]),
        ("ベルト", [(3.25, 3.40, "カチッ", "#b9d98a")]),
        ("ハテナ", [(0.0, 1.2, "手をふる（Pilot_Wave）", "#e5e5e5"), (1.2, 3.3, "Pilot_SitIdle", "#f2f2f2"), (3.3, 4.0, "前を指す", "#e5e5e5"), (4.0, 4.6, "Pilot_Steer", "#f2f2f2")]),
        ("ローター", [(3.2, 4.4, "回りはじめ（spool 0→0.6）", "#c8cdd6"), (4.4, 4.6, "離陸", "#8f99a8")]),
        ("カメラ", [(0.0, 3.6, "デッキの高さ・横から（絵コンテ ②）", "#e9eef6"), (3.6, 4.6, "見上げへ（③）", "#d3dcea")]),
    ]
    lane_h = 30
    for k in range(int(t_max * 2) + 1):
        tt = k / 2
        s.line(sx(tt), ty + 14, sx(tt), ty + 22 + len(lanes) * (lane_h + 6), "#e1e6ee", 1)
        s.text(sx(tt), ty + 12, f"{tt:.1f}", 12, 400, MUTED, "middle")
    for li, (name, bars) in enumerate(lanes):
        ly = ty + 22 + li * (lane_h + 6)
        s.text(tl_x - 12, ly + 20, name, 14, 700, INK, "end")
        for t0, t1, label, color in bars:
            s.rect(sx(t0), ly, sx(t1) - sx(t0), lane_h, fill=color, stroke="#ffffff", rx=4)
            s.text(sx(t0) + 6, ly + 20, label, 12, 400, INK)
    s.text(50, ty + 22 + len(lanes) * (lane_h + 6) + 26, "絵コンテでは「乗り込む」を 1.2 秒としていたが、ドアの開け閉めと 2 段の乗り込みを入れると約 3.3 秒かかる。検索の通信は押した瞬間に始め、乗り込み中に相手が見つかっても最後まで見せてから合流へ進む。", 13, 400, MUTED)
    return s


# ---------------------------------------------------------------- 図 7 ハテナ

def sheet_pilot():
    s = Sheet(7, "操縦士ハテナ", "等倍で右の席に座り、U 字の操縦かんを握る（足を前に出す「ぬいぐるみ座り」）")
    old = old_scene(gp_passenger=False)
    r_old = render(old_scene(gp_passenger=False, cut_x=0.0), "side", (-2.0, 0.2, 0.9, 3.0), 150)
    s.place(r_old, "side", 50, 150, "今（真ん中で切って横から・0.35 倍）")
    r_old_f = render(old, "front", (-1.0, 1.0, 0.9, 3.0), 150)
    s.place(r_old_f, "front", 50 + r_old.image.size[0] + 20, 150, "今（正面）")
    r_new = render(hd.build_heli(cut=("x", hd.SEAT_X - 0.05, "+"), yokes=YOKES) + cast.hatena("seated")[0], "side", (-2.6, 0.0, 0.7, 3.4), 118)
    vn = s.place(r_new, "side", 50, 520, "新（右の席の中心で切って横から・等倍）")
    root = cast.hatena_root()
    s.marker(vn, root, "MK_SeatPilot（原点）", 10, 18)
    s.hline_world(vn, hd.SEAT_TOP_Y + hd.BOOSTER_H, (-1.6, -0.05), None, ACCENT, "3 3")
    s.text(vn.uv_px(-0.08, 0)[0], vn.uv_px(0, hd.SEAT_TOP_Y + hd.BOOSTER_H)[1] + 16, f"クッションの上面 {hd.SEAT_TOP_Y + hd.BOOSTER_H:.2f}", 12, 700, ACCENT, "end")
    g = YOKES[1]
    s.leader(vn, g["grip_r"], vn.x + 200, vn.y + r_new.image.size[1] + 22, ["操縦かんの握り（ミトンの中心）", f"高さ {g['grip_r'][1]:.2f}・z {g['grip_r'][2]:.2f}"], INK, 13)
    r_new_f = render(new_scene(player=None), "front", (-2.0, 0.15, 0.9, 3.4), 118)
    s.place(r_new_f, "front", 50 + r_new.image.size[0] + 20, 520, "新（正面）")
    _, _, local = cast.hatena("seated")
    heads = cast.rig().bone_heads(local)
    xf = cast.hatena_xform()
    rows = [["骨", "向き（ハテナの空間・前が +Z）", "根元の位置（機体・地面基準）"]]
    for bone in ("DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L"):
        d = cast.HATENA_SEATED.get(bone)
        p = xf[:3, :3] @ heads[bone] + xf[:3, 3]
        rows.append([bone, "—（前腕にそろえる）" if d is None else "(" + ", ".join(f"{v:+.2f}" for v in d) + ")", f"({p[0]:+.2f}, {p[1]:.2f}, {p[2]:+.2f})"])
    rows.append(["DEF-hips / DEF-head", "動かさない（体はまっすぐ）", f"原点 ({root[0]:+.2f}, {root[1]:.2f}, {root[2]:+.2f})"])
    x2 = 900
    s.text(x2, 150, "座り方（骨の向きで決める。.R は x を反転）", 17, 700)
    yy = s.table(x2, 164, [190, 300, 360], rows, size=13, row_h=24)
    yy = s.note_box(x2, yy + 20, 850, "作り方（今の「骨に絶対の回転」をやめる）", [
        "1. aiquiz_mascot.blend に動き（Action）を作り、mascot_model.glb に入れて書き出す：Pilot_Sit（止め）、Pilot_SitIdle（2.0 秒。体が 1 cm 上下し、「？」が ±4° ゆれる）、Pilot_Steer（1.6 秒。握りが ±0.04 m）、Pilot_Wave（1.2 秒。左手）、Pilot_Point（0.7 秒。前を指す）。",
        "2. Godot は AnimationPlayer でこれを流す。_pose_pilot_seated と _mount_pilot の骨を回すコードは消す。",
        "3. 大きさは等倍（PILOT_SCALE = 1.0）。原点を MK_SeatPilot に合わせ、向きは機首（yaw 180°）。",
        "4. 審判・ノコギリの役は今のまま（動きの名前は Pilot_ で始めて、重ならないようにする）。",
    ], size=14, fill="#f2f7ff", stroke=DIM)
    yy = s.note_box(x2, yy + 16, 850, "操縦士の小物", [
        "・ヘッドセット Pilot_Headset（ハテナ専用のメッシュ。DEF-head に付ける）：頭の上を通るバンド（「？」の付け根の後ろ）、目の高さ（体の中心から +0.08）に左右の耳あて（直径 0.20・厚さ 0.08）、口の横へのびるマイク。チャコールとオレンジ。審判・ノコギリの役では隠す。",
        f"・クッション（ブースター）：右の席の座面に載せる。高さ {hd.BOOSTER_H:.2f}、機体の色。ハテナの口が計器盤の上に出る高さ。",
        "・ベルト：ボールの下のほうを横切る帯（Belt_R）。プレイヤー側は太ももの上（Belt_L）。座ったときに「カチッ」と出す。",
    ], size=14)
    # プレイヤーの座り方（決めてほしいこと②）
    yb = 908
    s.text(50, yb - 6, "プレイヤーの座り方（決めてほしいこと②）：左の席の中心で切って横から", 15, 700)
    xb = -hd.SEAT_X
    for i, (pose, label) in enumerate((("sit_idle", "Sitting_Idle_Loop（手はひざ）"), ("driving", "Driving_Loop（操縦かんを握る）"))):
        sc = hd.build_heli(cut=("x", xb, "+"), yokes=YOKES) + cast.player(pose, hd.PASSENGER_PELVIS)[0]
        rr = render(sc, "side", (-2.5, -0.3, 0.6, 3.1), 86)
        px = 50 + i * (rr.image.size[0] + 30)
        s.place(rr, "side", px, yb + 6)
        s.text(px + 6, yb + 6 + rr.image.size[1] + 20, label, 13, 400, INK)
    return s


# ---------------------------------------------------------------- 図 9 完成イメージ

def sheet_concept():
    s = Sheet(9, "完成イメージ（Codex で生成）", "図面のブロックアウトを参照に描いたイメージ。寸法・席の左右は図面が正")
    paths = [HERE / "concept" / "concept_01_boarding.png", HERE / "concept" / "concept_02_parallel_flight.png"]
    caps = ["ヘリポートで乗り込む（左のドアを開け、ステップに乗る。ハテナは右の席で手を振る）",
            "並んで飛ぶ 2 機を正面から（絵コンテ ⑦ のカット）"]
    for i, (p, cap) in enumerate(zip(paths, caps)):
        x = 50 + i * 860
        if not p.exists():
            s.text(x, 200, f"（{p.name} がない）", 16, 400, NG)
            continue
        img = Image.open(p).convert("RGB")
        w = 840
        h = int(img.size[1] * w / img.size[0])
        s.image(img.resize((w, h), Image.LANCZOS), x, 110)
        s.para(x, 110 + h + 26, cap, w, 15, INK, weight=700)
    s.note_box(50, 700, 1700, "絵と図面のちがい（実装は図面に合わせる）", [
        "・席の左右：2 枚目はプレイヤーが画面の左にいる。図面では、正面から見るとプレイヤーは画面の右（機体の左の席）。",
        "・ドア：1 枚目のドアは屋根だけがはね上がっている。図面のドアは横の面ごと上へ 90° 開く。",
        "・白い帯：ギザギザに見えるのは、参照に渡したブロックアウトの描き方のせい。実際の帯はまっすぐ。",
        "・ハテナのヘッドセット・プレイヤーの帽子は、絵のとおり付けられる（ヘッドセットは図 7）。",
        "・生成：Codex CLI（画像生成）。参照画像はブロックアウト 2 枚・ゲームの VS 画面・ハテナの正面。",
    ], size=14, fill="#f2f7ff", stroke=DIM)
    return s


# ---------------------------------------------------------------- 図 8 ノードと約束

NODE_TREE = [
    "HelicopterRoot                （原点＝ローター軸 × 地面から 1.75。機首 -Z）",
    "├ BodyPaint        胴体・尾（材質 BodyPaint：色替え）",
    "├ BodyTrim         白い帯・水平尾翼の端板（材質 Trim）",
    "├ Windows          前の風防・荷室の窓（材質 Windows：今と同じ名前）",
    "├ Door_L           左ドア（原点＝ヒンジ前端、ローカル +Z＝ヒンジ線）",
    "│  ├ Door_L_Paint   （BodyPaint／Trim）",
    "│  └ Door_L_Glass   （Windows）",
    "├ Door_R           右ドア（左右対称）",
    "├ Interior         床・内張り・後ろの仕切り（材質 Interior）",
    "├ Dash / DashScreens   計器盤と画面（画面は発光）",
    "├ Seat_L / Seat_R / Booster_R / Console",
    "├ Yoke_L / Yoke_R  U 字の操縦かん（Yoke_L は付けない選択もできる）",
    "├ Belt_L / Belt_R  ベルト（ふだん非表示）",
    "├ Step_L           乗り込みステップ",
    "├ FrameAndSkids    スキッド（今と同じ名前）",
    "├ DropBayFrame / DropBayInterior / DropHatchLeft / DropHatchRight（今と同じ）",
    "├ MainRotor        原点＝ハブ（Y 軸で回る）",
    "├ TailRotor        原点＝ハブ（X 軸で回る）",
    "├ NavLight_L / NavLight_R / Beacon",
    "└ Markers          MK_* の空のノード（下の表）",
]


def sheet_contract():
    s = Sheet(8, "ノード構成と Godot との約束", "GLB の中身・マーカー・材質・作業の順番")
    s.text(50, 140, "ノード構成（GLB）", 17, 700)
    for i, row in enumerate(NODE_TREE):
        s.add(f'<text x="50" y="{170 + i * 22}" font-size="13.5" fill="{INK}" style="font-family:Consolas, \'BIZ UDGothic\', monospace" xml:space="preserve">{row.replace("&", "&amp;").replace("<", "&lt;")}</text>')
    # マーカーの表
    rows = [["マーカー", "地面基準 (x, y, z)", "GLB の座標", "向き", "使いみち"]]
    for name, m in analysis.MK.items():
        p = m["pos"]
        q = analysis.to_model(p)
        rows.append([name, f"({p[0]:+.2f}, {p[1]:.2f}, {p[2]:+.2f})", f"({q[0]:+.2f}, {q[1]:+.2f}, {q[2]:+.2f})",
                     f"{m['yaw']}°" if "yaw" in m else "—", m["note"]])
    s.text(820, 140, "マーカー（コードは定数ではなく、このノードの位置を読む）", 17, 700)
    yy = s.table(820, 154, [170, 170, 170, 54, 366], rows, size=12.5, row_h=22)
    # 材質と予算
    rows2 = [["材質", "色・設定", "メモ"],
             ["BodyPaint", "オレンジ（P1）／ブルー（P2）", "今と同じ名前。_apply_body_tint がそのまま効く"],
             ["Trim", "白 #F5F5F0", "帯・ステップ・端板"],
             ["Windows", "水色・半透明 0.34", "今と同じ名前。_apply_window_glass が効く"],
             ["Charcoal", "#2B3038", "スキッド・ローター・操縦かん"],
             ["Interior / Seat / Dash", "灰 / 紺 / 黒っぽい灰", "画面は発光（水色）"]]
    yy = s.table(820, yy + 24, [190, 260, 460], rows2, size=13, row_h=24)
    s.note_box(820, yy + 18, 910, "大きさの予算", [
        "・三角形 1 万前後（実測 10,012：胴体 5,100、ドア 2 枚 1,250、内装・座席 2,000、ローター・スキッド 1,300 ほか）。画面に 2 機＋ハテナ 2 体（各 3.4 万）が出る前提。",
        "・テクスチャは使わず、単色の材質＋頂点カラーで AO（今のヘリポートと同じ作り）。",
    ], size=13.5, fill="#f2f7ff", stroke=DIM)
    # 作業の順番
    s.note_box(50, 640, 740, "作業の順番", [
        "段階 1（オンラインのヘリポート）",
        "1. Blender（ライブ）で新しいヘリを作る：assets/vehicles/helicopter_boarding/source/blender/build_helicopter_boarding.py。数値は heli_pilot_spec.json を読む。.blend を保存。（済）",
        "2. helicopter_boarding.glb に書き出し、Godot で取り込む。tests/helicopter_boarding_check.gd で確かめる。（済）",
        "3. ハテナの動き（Pilot_*）を aiquiz_mascot.blend に作り、書き出し直す。",
        "4. OnlineHeliportHelicopter：マーカーを読む・set_door(side, t)・座席に座らせる API。",
        "5. PlayerController：乗り込みの動き（図 6）を足す。足の裏の高さで位置を合わせる。",
        "6. ヘリポートを 1 つだけの形に作り直す（別の作業）。",
        "段階 2（本編の登場演出・決めてから）",
        "7. helicopter_arrival_director の定数（PILOT_*、GP_PASSENGER_SEAT など）をマーカーに置きかえ、高さ・カメラを合わせる。",
    ], size=13.5)
    s.note_box(820, 840, 910, "確かめ方", [
        "・構造：GLB のノード名・マーカーがそろっているかをテストで確かめる（tests/ に追加）。",
        "・すき間：analysis.py と同じ計算を、Godot 上の本物のモデルでもう一度行う（帽子 16 種 × 座る・立つ）。",
        "・見た目：ヘリポートで乗り込み〜離陸を実際に動かしてスクリーンショット（横・正面・上）。",
    ], size=13.5)
    return s


SHEETS = [sheet_cover, sheet_problems, sheet_three_view, sheet_sections, sheet_door, sheet_boarding, sheet_pilot, sheet_contract, sheet_concept]


def spec_json():
    return {
        "version": 1,
        "units": "m (Godot 1 = 1 m). y はスキッド下面を 0。GLB の座標は y - origin_y",
        "origin_y": hd.ORIGIN_Y,
        "body_profile": {"z": hd.BODY_Z, "top": hd.BODY_TOP, "bottom": hd.BODY_BOTTOM, "belt": hd.BODY_BELT, "half_width": hd.BODY_HALF_W,
                         "n_top": hd.N_TOP, "n_bottom": hd.N_BOTTOM, "wall": hd.WALL},
        "floor_y": hd.FLOOR_Y, "belly_y": hd.BELLY_Y, "step_y": hd.STEP_Y, "step": hd.STEP,
        "seat": {"x": hd.SEAT_X, "top_y": hd.SEAT_TOP_Y, "front_z": hd.SEAT_FRONT_Z, "back_z": hd.SEAT_BACK_Z, "width": hd.SEAT_W,
                 "back_top_y": hd.SEAT_BACK_TOP_Y, "back_tilt_deg": hd.SEAT_BACK_TILT_DEG, "booster_h": hd.BOOSTER_H},
        "dash": {"back_z": hd.DASH_BACK_Z, "front_z": hd.DASH_FRONT_Z, "top_y": hd.DASH_TOP_Y, "bottom_y": hd.DASH_BOTTOM_Y},
        "door": {"front_z": hd.DOOR_FRONT_Z, "rear_z": hd.DOOR_REAR_Z, "hinge_x": hd.DOOR_HINGE_X, "sill_y": hd.DOOR_SILL_Y,
                 "open_deg": hd.DOOR_OPEN_DEG, "window_belt_y": hd.WINDOW_BELT_Y,
                 "hinge_L": [list(map(float, p)) for p in hd.door_hinge("L")]},
        "hatch": {"half_w": hd.HATCH_HALF_W, "z": hd.HATCH_Z, "open_deg": 78},
        "stripe_y": hd.STRIPE_Y, "bay": {"front_z": hd.BAY_FRONT_Z, "rear_z": hd.BAY_REAR_Z},
        "mast_fairing": hd.MAST_FAIRING, "console_half_w": hd.CONSOLE_HALF_W,
        "colors": {"body_paint": hd.BODY_PAINT, "trim": hd.TRIM, "charcoal": hd.CHARCOAL, "glass": hd.GLASS,
                   "interior": hd.INTERIOR, "seat": hd.SEAT_COLOR, "dash": hd.DASH_COLOR, "screen": hd.SCREEN},
        "rotor": {"hub_y": hd.ROTOR_HUB_Y, "radius": hd.ROTOR_RADIUS, "chord": hd.ROTOR_CHORD, "blades": hd.ROTOR_BLADES, "park_deg": hd.ROTOR_PARK_DEG},
        "tail_rotor": hd.TAIL_ROTOR, "boom": hd.BOOM, "fin": hd.FIN, "stab": hd.STAB,
        "skid": {"x": hd.SKID_X, "z": hd.SKID_Z, "r": hd.SKID_R, "cross_z": hd.CROSS_Z},
        "yokes": [{k: (list(map(float, v)) if hasattr(v, "__len__") else float(v)) for k, v in y.items()} for y in YOKES],
        "hatena": {"scale": 1.0, "root": list(map(float, cast.hatena_root())), "seated_aims": cast.HATENA_SEATED},
        "markers": {k: {"ground": list(map(float, v["pos"])), "model": list(map(float, analysis.to_model(v["pos"]))), "yaw": v.get("yaw"), "note": v["note"]}
                    for k, v in analysis.MK.items()},
        "overall": OVERALL, "interior": {k: float(v) for k, v in INTERIOR.items()},
        "checks": [{"name": c[0], "value": float(c[1]), "criterion": c[2], "ok": bool(c[3]), "memo": c[4]} for c in CHECKS],
    }


def write_spec():
    """数値の JSON を書く。artifacts/ は git の管理外なので、Blender のビルダーが読む写しを素材のフォルダ（管理下）にも置く。"""
    text = json.dumps(spec_json(), ensure_ascii=False, indent=1, default=float)
    (HERE / "heli_pilot_spec.json").write_text(text, encoding="utf-8")
    (ROOT / "assets" / "vehicles" / "helicopter_boarding" / "source" / "heli_pilot_spec.json").write_text(text, encoding="utf-8")


def export_png(svg_path, png_path, w, h):
    edge = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    prof = Path(tempfile.gettempdir()) / "heli_blueprint_edge_profile"  # Edge の作業用（リポジトリの外）
    cmd = [edge, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
           f"--user-data-dir={prof}", f"--window-size={w},{h}", f"--screenshot={png_path}", svg_path.resolve().as_uri()]
    if png_path.exists():
        png_path.unlink()
    subprocess.run(cmd, check=False, capture_output=True, timeout=120)
    for _ in range(40):  # Edge は終了したあとに書き出すことがある
        if png_path.exists():
            break
        time.sleep(0.25)


def main():
    if "spec" in sys.argv[1:]:
        write_spec()
        print("spec only")
        return
    only = [int(a) for a in sys.argv[1:] if a.isdigit()]
    (HERE / "sheets").mkdir(exist_ok=True)
    (HERE / "png").mkdir(exist_ok=True)
    built = []
    for i, fn in enumerate(SHEETS, start=1):
        if only and i not in only:
            continue
        sheet = fn()
        sheet.font_prefix = "../../../resources/fonts/"
        svg_path = HERE / "sheets" / f"sheet_{i:02d}.svg"
        svg_path.write_text(sheet.svg(), encoding="utf-8")
        png_path = HERE / "png" / f"sheet_{i:02d}.png"
        export_png(svg_path, png_path, sheet.w, sheet.h)
        built.append((i, sheet))
        print("sheet", i, sheet.title, png_path.exists())
    write_spec()
    if not only:
        parts = []
        for i, sheet in built:
            sheet.font_prefix = "../../resources/fonts/"
            parts.append(f'<section id="s{i}">{sheet.svg()}</section>')
        html = f'''<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>ヘリとパイロットの設計図</title>
<style>body{{margin:0;background:#dfe5ee;}} section{{margin:24px auto;width:1800px;box-shadow:0 2px 12px #0002;}} svg{{display:block;}}</style></head>
<body>{"".join(parts)}</body></html>'''
        (HERE / "heli_pilot_blueprint.html").write_text(html, encoding="utf-8")


if __name__ == "__main__":
    main()
