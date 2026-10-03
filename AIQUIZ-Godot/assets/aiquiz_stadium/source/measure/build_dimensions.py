"""寸法表 ../dimensions.json を作る（Blender ビルダーが読む形）。

値の根拠は3種類で、各モジュールの "src" に項目ごとに書く。
- const: ゲーム定数（../game_constants.json、extract_game_constants.py が読み取ったもの）
- measured: 参照画像の実測（measure_report.json）
- design: 設計判断（画像で再現を確認したもの・画像が食い違ったものを含む）

最後にゲーム定数との突き合わせとクリアランスを検算し、失敗があれば終了コード 1 で止まる。

    python measure.py && python build_dimensions.py
"""
from __future__ import annotations

import io
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
sys.path.insert(0, str(SRC / "guides"))
import make_guides as G  # noqa: E402

REPORT = json.loads((HERE / "measure_report.json").read_text(encoding="utf-8"))
CONST = json.loads((SRC / "game_constants.json").read_text(encoding="utf-8"))
LAYOUT = CONST["json"]["goal_stand_layout"]
M = REPORT["P01_runway_side_elev"]
LH = REPORT["P05_lighthouse_ratios"]


def r(v, step=0.05):
    return round(round(v / step) * step, 3)


def side_stand_block():
    rows = G.DESIGN["rows"]
    plat = G.ROW_BASE + rows * G.ROW_RISE
    seat_x = [r(G.ROW_FRONT + i * G.ROW_PITCH, 0.01) for i in range(rows)]
    cushion = [r(0.865 + i * G.ROW_RISE, 0.005) for i in range(rows)]
    d = {
        "frame": "Blender ブロック空間: X＝コースから外向き、Y＝コース方向、Z＝上。原点＝ブロック中央・ワールド高さ 0（走路デッキ上面 +1.2m）。右スタンド（+X、P1）はそのまま、左スタンド（-X、P2）は同じメッシュを Z 軸まわりに 180° 回して使う",
        "placement_world_abs_x": G.DESIGN["stand_center_x"],
        "block_length": G.BLOCK,
        "front_face_x": G.FRONT_X, "back_face_x": G.DESIGN["stand_back_x"],
        "deck_top_z": 0.22, "deck_underside_z": -1.0,
        "front_wall": {"x": -0.6, "top_z": 0.64, "thickness": 0.26, "rail_top_z": 1.15, "top_rail": "cobalt 0.06×0.10", "post_pitch": 2.4},
        "rows": {"count": rows, "first_seat_x": G.ROW_FRONT, "tread": G.ROW_PITCH, "rise": G.ROW_RISE, "base_z": G.ROW_BASE,
                 "seat_x": seat_x, "cushion_top_z": cushion},
        "seats": {"per_row": 19, "pitch": 0.92, "z_range": [-8.28, 8.28], "per_block": rows * 19, "shape": "白いバケットシート 0.61×0.66、背 0.43（着席ポーズ HIP_BEHIND_SEAT 0.06 と合わせる）"},
        "aisle": {"at": "ブロックの +Y 端（Godot の -Z 端）に幅 2.2m、隣のブロックへ 1.1m はみ出す。cap_end には無し（既存の santorini_terrace_stand.gd と同じ約束）", "width": 2.2, "step_rise": 0.2, "step_tread": 0.625, "handrail": "白の支柱＋コバルトの手すり"},
        "rear_walkway": {"top_z": r(plat, 0.01), "x": [r(G.ROW_FRONT - 0.6 + rows * G.ROW_PITCH, 0.01), G.DESIGN["stand_back_x"]], "back_rail_top_z": r(plat + 1.1, 0.01)},
        "booth": {"center_y": 0.0, "x": [8.35, 10.65], "length_y": 3.4, "height": 2.63, "base_z": r(plat, 0.01), "corner_radius": 0.55,
                  "note": "原本の丸みのある箱型ブース（P01 立面の奥行き 3.25 を、原本の丸いブースに合わせて 3.4 に）",
                  "screen": {"face": "-X（走路側）", "width": 2.4, "height": 1.5, "bottom_z": 3.45, "texture": "textures/booth_screen.png（青地に白い「?」）", "emissive": 1.2}},
        "mast": {"x": G.DESIGN["mast"]["x"], "y": 0.0, "section": "八角形", "diameter": r(M["mast_diameter"]), "top_z": G.DESIGN["mast"]["top_y"],
                 "through_booth": True, "top_lamp": {"size": 0.35, "emissive": True}},
        "upper_yard": {"z": r(M["upper_yard_Y"]), "length_y": r(M["upper_yard_len"]), "diameter": 0.2},
        "sail_rig": {
            "design": "原本の帆：スタンドを横切る面に張った三角帆。ヘッド＝マストの頂、タック＝ブームの付け根、クリュー＝ブームの先（走路側の客席の上）。"
                      "コースのカメラから帆の面が正面に見え、ゴール側にある太陽の光が布を透ける（v1 の、走路側へ下がるテント形は不採用）",
            "module": "AQS_SailRig_R / AQS_SailRig_L。左右でふくらむ向きだけが違う別メッシュで、どちらも Godot の +Z（ゴール側）へふくらむ",
            "mast_x": G.DESIGN["mast"]["x"], "mast_top_z": G.DESIGN["mast"]["top_y"],
            "head": [9.27, 0.0, 11.55], "tack": [9.27, 0.0, 6.05], "clew": [1.35, 0.0, 6.55], "clew_offset_y": 0.55,
            "leech_sag": 0.62, "foot_sag": 0.34, "luff_sag": 0.06, "camber_depth": 1.05, "grid": [14, 12],
            "boom_root": [9.5, 0.0, 5.82], "boom_end": [1.15, 0.0, 6.36], "boom_diameter": 0.17, "boom_lamps_t": [0.35, 0.7],
            "fabric": "textures/sail_fabric.png（UV：u＝ラフ→リーチ、v＝フット→ヘッド）、両面、半透明（Godot は backlight）",
            "wind": "UV2.x＝揺れの重み（縁で 0・中央で 1）、UV2.y＝高さ。Godot のシェーダーで法線方向へ揺らす",
            "clearance": "帆の最も低い所 z 約 6.0（最上段の観客の頭 約 3.9 より 2m 上）、走路側の端 |x| 29.35（海落下カメラの通り道 |x|<27.2 の外）"},
        "rigging": {"lines": "シュラウド 2 本（マストの頂→後方通路の両端）、トッピングリフト 1 本（マストの頂→ブームの先）", "min_thickness": 0.06},
        "piles": {"section": 0.6, "pitch_y": G.DESIGN["stand_pile_pitch"], "x": [0.2, 5.4, 10.3], "top_z": -1.0, "bottom_z": -17.2,
                  "runtime": "santorini_waterfront.gd の extend_stand_supports で海底 -129.2 まで伸ばす"},
        "variants": {"bay": "標準（マスト・ヤード・ブースあり。帆は AQS_SailRig を重ねる）", "cap_start / cap_end": "端部：段に沿って下がる白い端壁、見張り塔（屋根上端 z 8.8、旗竿 10.0）、海側の船着き場（z -8.4）へ下りる階段。マスト・帆・ブースは立てない（後端はヘリの経路、前端も左右で入れ替わるため両方とも無し）"},
        "budget": {"triangles_max": 15000, "surfaces": "頂点色の塗装・夜の灯・ブースの画面（帆は別メッシュ）"},
    }
    src = {"placement_world_abs_x": "const", "block_length": "const", "front_face_x": "const", "deck_top_z": "const",
           "front_wall": "const", "rows": "const（段数 6 はユーザー決定）", "seats": "const", "aisle": "const",
           "back_face_x": "design", "rear_walkway": "design", "booth": "measured（奥行き・パネル幅）+ design",
           "mast": "design（P01 立面で 0.6% 以内に再現）+ measured（太さ）", "upper_yard": "measured",
           "sail_rig": "design（原本の帆の形：マストの頂から走路側へ張り出す三角帆。ユーザー指摘の「透け具合・柔らかさ」を形とふくらみで出す）",
           "piles": "design（P01 立面で 5m 間隔を確認）+ const（下端 -17.2）"}
    return d, src


def runway():
    d = {
        "frame": "Godot ワールド座標（+X＝P1＝画面左、+Z＝コース前方、走路上面 Y=-1.2）",
        "width": G.HALF_W * 2, "deck_top_y": G.DECK_Y,
        "surface": "既存のベルトシェーダー（白いスラットの見た目は conveyor_belt_floor.gdshader 側で合わせる）",
        "edge_band_abs_x": [11.15, 12.0],
        "curb": {"center_abs_x": G.CURB_X, "width": 0.16, "top_above_deck": G.CURB_TOP, "color": "cobalt", "collision": False},
        "side_frame": {"abs_x": 11.88, "width": 0.24, "height": 1.05, "color": "steel grey"},
        "bents": {"pitch_z": 10.0, "piles_abs_x": list(G.DESIGN["runway_pile_x"]), "pile_section": 0.7,
                  "cross_beam": {"under_deck_y": -2.3, "depth": 0.5}, "x_bracing": {"from_y": -2.8, "to_y": -8.5, "section": 0.25},
                  "edge_lamps": {"abs_x": [12.01, 12.13], "pitch_z": 2.5, "length_z": 0.24, "from_deck": -0.1, "top_above_deck": 0.32,
                                 "note": "側桁のすぐ外の小さな鋲。縁石（上端 +0.26）越しに 1P / 2P の視点から点で見える高さ。夕暮れ・夜だけ光る（V01 夜）"},
                  "pile_bottom_y": -17.2},
        "ends": "後端 z=-12.5 のローラー側はノコギリ船が出入りするため開けたまま。前端は長さが変わるので杭の組を 10m ごとに手続き的に並べる",
    }
    src = {"width": "const", "deck_top_y": "const", "edge_band_abs_x": "const", "curb": "const（P09 の 1m の壁は不採用）",
           "side_frame": "const", "bents": "design（P04 アンカー・断面・V06 の X 筋交い）"}
    return d, src


def goal_gate():
    d = {"frame": "Godot ワールド、原点＝ゴールライン中央・デッキ上面", "pillar_center_abs_x": 11.55, "pillar_section": 0.7,
         "clear_height": 5.0, "crossbar_depth": 0.9, "board": {"width": 8.0, "height": 1.2, "frame": 0.1, "text": "GOAL（テクスチャ、生成画像には文字を描かせない）"},
         "plinth": [0.9, 0.35, 0.9], "floodlight_box": 0.6, "accent": "柱の前面に cobalt 0.10 の帯",
         "hidden_after_finale_s": 0.4}
    src = {"pillar_center_abs_x": "design（0.7m の柱と 0.9m の台座がデッキ端 12.0 からはみ出さないよう、現行の ±11.8 から内側へ）",
           "clear_height": "const（現行ゲート）", "board": "design", "others": "design（P06 の意匠。P06 の柱位置・高さは下敷きと食い違ったため不採用）"}
    return d, src


def goal_stand_b():
    sb = LAYOUT["scoreboard"]
    d = {"frame": "既存ゴール観客席と同じ：Blender で -Y 向きに作り、Godot で 180° 回す。原点＝前面中央・デッキ上面。仕組み（goal_stand.gd）と layout JSON の値は変えない",
         "width": LAYOUT["width"], "tiers": LAYOUT["tiers"], "aisles_x": LAYOUT["aisles"], "aisle_width": LAYOUT["aisle_width"],
         "parapet_top": LAYOUT["parapet_top"], "back_y": LAYOUT["back_y"], "back_top": LAYOUT["back_top"],
         "flags_x": [LAYOUT["flags"]["p1_x"], LAYOUT["flags"]["p2_x"]],
         "scoreboard": sb,
         "bridge_house": {"width": 17.6, "side_tower_width": 3.2, "depth": 3.0, "roof_top": 11.77, "corner_radius": 1.0,
                          "side_tower_window": [1.2, 1.4], "cobalt_stripes": 2},
         "lower_deckhouse": {"width": LAYOUT["width"], "z": [0.0, LAYOUT["back_top"]], "portholes_per_side": 4, "porthole_diameter": 0.8, "porthole_pitch": 1.6},
         "mast": {"base_z": 11.8, "top_z": 19.5, "crows_nest": {"z": 16.5, "diameter": 1.6, "height": 1.0},
                  "yards": [{"z": 15.0, "length": 7.0}, {"z": 18.3, "length": 4.4}],
                  "flags": "オレンジ＝P1 側（Godot の +X、画面左）、青＝P2 側"},
         "roof_sails": {"note": "中央区画を覆うテントは、フィナーレのカメラから LED の下部を隠すため不採用。代わりにマストから屋根の両端へ 2 枚の三角帆（屋根より上）", "apex_z": 18.8, "foot_z": 12.0, "foot_abs_x": 7.5},
         "led_note": f"LED は 11.2×4.8（縦横比 2.33）。生成画像は縦横比 {REPORT['P07_goal_stand_B_ratios']['led_aspect']} で細かったが、表示の仕組みに合わせて定数を正とする"}
    src = {"width/tiers/aisles/parapet/back/flags/scoreboard": "const（goal_stand_layout.json）",
           "bridge_house/lower_deckhouse/mast/roof_sails": "design（P07 B 案の意匠。正面図は縦が圧縮されていたため比率のみ参考）"}
    return d, src


def lighthouse():
    opt = next(o for o in REPORT["lighthouse_options"] if o["option"].startswith("B"))
    W = opt["sign_inner_width_W"]
    d = {"frame": "Godot ワールド、原点＝小島の中心・海面", "option": opt["option"],
         "decision": "B に決定（ユーザー決定）。軸から 21.5° 外した小島で、エンドレスの走路とも 2P のゴール観客席とも重ならない。スタート時は右スタンドの帆の後ろに一部重なる（artifacts/aiquiz_stadium/reference_r1/measure/lighthouse_options_2p.png）",
         "yaw_deg": -21.5, "yaw_note": "看板の面をスタート地点（Godot の原点付近）へ向ける。Blender の Z 回り・Godot の Y 回りとも同じ符号",
         "position_world_xz": opt["position_world_xz"],
         "sign_inner_width_W": W,
         "proportions_of_W": LH,
         "resolved": {k.replace("_W", ""): r(v * W, 0.1) for k, v in LH.items() if k.endswith("_W")},
         "sign_aspect": "2.5:1（assets/goal_stand/source/textures/sb_header.png を流用）",
         "lantern_emissive": True, "rotating_beam": "夕方・夜のみ（光の帯は加算の大きな板を使わない）",
         "alternatives": REPORT["lighthouse_options"]}
    src = {"proportions_of_W": "measured（P05 正面の正投影）", "W/position": "design + user（置き場所の比較から B をユーザーが選択）"}
    return d, src


def background():
    d = {"frame": "方位 bearing_deg はスタート地点から見た角度（正＝左＝Godot の +X）。Godot の位置 = (d·sinθ, 海面, d·cosθ)。カメラの far 5000m の内側に置く",
         "camera_far": 5000.0,
         "islands": [
             {"name": "AQS_BG_IslandLush", "bearing_deg": 38.0, "distance": 2100.0, "width": 950.0, "depth": 420.0, "height": 95.0,
              "style": "lush", "note": "原本の左の島：丸い茂みの丘・砂浜・ヤシ・水際の丸い岩"},
             {"name": "AQS_BG_IsletPalms", "bearing_deg": 22.0, "distance": 1500.0, "width": 230.0, "depth": 140.0, "height": 24.0,
              "style": "islet", "note": "原本の中央左の小島：ヤシの並ぶ低い島"},
             {"name": "AQS_BG_IslandRocky", "bearing_deg": -36.0, "distance": 1900.0, "width": 900.0, "depth": 400.0, "height": 110.0,
              "style": "rocky", "note": "原本の右の島：桃色がかった岩の丘・茂み・ヤシ・長い砂浜"},
             {"name": "AQS_BG_IsletFar", "bearing_deg": -8.0, "distance": 2900.0, "width": 260.0, "depth": 150.0, "height": 26.0,
              "style": "islet", "note": "原本の遠い小島"}],
         "city": {"name": "AQS_BG_City", "bearing_deg": 10.0, "distance": 4250.0, "width": 1100.0, "depth": 420.0, "tallest": 340.0,
                  "note": "原本の街：水平線に立つ細いガラスの高層ビル群（左寄り）。足元に低い街並みと海岸。遠景らしい淡い青みを外壁のテクスチャに入れる",
                  "facades": ["textures/city_facade_a.png（青いガラス）", "textures/city_facade_b.png（白い外壁）", "textures/city_facade_c.png（青緑のガラスと縦のフィン）"],
                  "facade_tile_m": [28.0, 32.0], "night": "窓明かりのテクスチャ（*_night.png）を夜の発光に"},
         "sailboats": [
             {"name": "AQS_BG_Sailboat1", "bearing_deg": 30.0, "distance": 430.0, "heading_deg": 60.0, "length": 9.0, "sail": "cobalt"},
             {"name": "AQS_BG_Sailboat2", "bearing_deg": -13.0, "distance": 520.0, "heading_deg": -40.0, "length": 8.0, "sail": "orange"},
             {"name": "AQS_BG_Sailboat3", "bearing_deg": 15.0, "distance": 900.0, "heading_deg": 110.0, "length": 10.0, "sail": "white"},
             {"name": "AQS_BG_Sailboat4", "bearing_deg": -29.0, "distance": 1150.0, "heading_deg": 20.0, "length": 11.0, "sail": "white"},
             {"name": "AQS_BG_Sailboat5", "bearing_deg": 5.0, "distance": 1700.0, "heading_deg": -80.0, "length": 9.0, "sail": "orange"},
             {"name": "AQS_BG_Sailboat6", "bearing_deg": 47.0, "distance": 650.0, "heading_deg": 150.0, "length": 8.0, "sail": "cobalt"}]}
    src = {"islands": "design（原本の配置：左に大きな茂みの島、中央左に小島、右に岩の島）", "city": "design（原本の街並み。ユーザー指摘の「街やビルの配置」）",
           "sailboats": "design（原本のヨット）"}
    return d, src


def verify(dims) -> list[str]:
    errs = []
    st = dims["modules"]["side_stand_block"]["data"]
    if abs(dims["world"]["runway_width"] - 24.0) > 1e-6:
        errs.append("走路幅が 24m でない")
    if abs(dims["world"]["deck_above_sea"] - 8.0) > 1e-6:
        errs.append("デッキ高が海面上 8m でない")
    if st["block_length"] != 20.0:
        errs.append("ブロック長が 20m でない")
    if st["placement_world_abs_x"] + st["front_face_x"] < 27.2 - 1e-6:
        errs.append("スタンド内側面が |x|27.2 より内側")
    sr = st["sail_rig"]
    if st["placement_world_abs_x"] + min(sr["clew"][0], sr["boom_end"][0]) < 27.2:
        errs.append("帆・ブームの先が |x|27.2 より内側")
    if min(sr["tack"][2], sr["boom_root"][2]) - sr["foot_sag"] < 5.0:
        errs.append("帆・ブームが観客の頭の近くまで下がっている")
    bg = dims["modules"]["background"]["data"]
    for item in bg["islands"] + [bg["city"]]:
        reach = item["distance"] + 0.5 * item["depth"] + 0.5 * item["width"] * 0.15
        if reach > bg["camera_far"] - 200:
            errs.append(f"{item['name']} がカメラの far に近すぎる")
    if st["rows"]["count"] != 6 or st["seats"]["per_block"] != 114:
        errs.append("6段・114席になっていない")
    if 20.0 % st["piles"]["pitch_y"] != 0 or 20.0 % dims["modules"]["runway"]["data"]["bents"]["pitch_z"] not in (0, 0.0):
        errs.append("杭のピッチが 20m を割り切らない")
    gs = dims["modules"]["goal_stand_B"]["data"]
    if abs(gs["width"] - 26.0) > 1e-6:
        errs.append("ゴール観客席の幅が 26m でない")
    c = REPORT["clearances"]
    if c["helicopter_vs_mast_dY"] < 1.0:
        errs.append("ヘリの開始位置とマスト頂部の上下の余裕が 1m 未満")
    for chk in REPORT["P01_runway_side_checks"]:
        if not chk["pass"]:
            errs.append("実測チェック失敗: " + chk["item"])
    for rp in REPORT["reprojection_2p_camera"]:
        if not rp["pass"]:
            errs.append("再投影が 3% を超えてずれた")
    return errs


def main():
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    modules = {}
    for key, fn in (("side_stand_block", side_stand_block), ("runway", runway), ("goal_gate", goal_gate),
                    ("goal_stand_B", goal_stand_b), ("lighthouse", lighthouse), ("background", background)):
        data, src = fn()
        modules[key] = {"data": data, "src": src}
    dims = {
        "meta": {"units": "metres", "git_head": CONST["git_head"], "constants": "game_constants.json",
                 "measurements": "measure/measure_report.json", "rounding": "構造 0.05m / 大物 0.25m / ピッチは 20m を割り切る値",
                 "godot_from_blender": "Godot = (X, Z, -Y)"},
        "world": {"runway_width": G.HALF_W * 2, "deck_top_y": G.DECK_Y, "sea_y": G.SEA_Y, "deck_above_sea": G.DECK_Y - G.SEA_Y,
                  "seabed_y": G.SEA_Y - 120.0, "course_back_z": G.BACK_Z, "wall_start_z": G.WALL_START, "wall_spacing": G.WALL_SPACING,
                  "p1": "+X（画面左、オレンジ）", "p2": "-X（画面右、青）", "fog": "毎フレーム強制オフ（かすみは頂点色で表現）"},
        "modules": modules,
        "clearances": REPORT["clearances"],
        "open_items": [
            "ヘリの開始位置（|x|36.5, Y13.7）とマスト（|x|37.5, 頂部灯の上端 12.5）は横 1.0m・縦 1.2m。両端のブロック（cap_start / cap_end）にはマストを立てない設計で回避したが、実機でローターとの干渉を確認する",
            "観客の描画範囲（grandstand_crowd.gd:62、x≤8.0・y≤4.0）と背面位置 BACK_X を 6段・背面 10.9m に合わせて広げる",
            "夜の帆は布の材質 AQS_Sail の発光（NightStrength × 0.12）で表す。Godot の昼夜切り替えにこの材質を加える",
        ],
    }
    errs = verify(dims)
    dims["verification"] = {"passed": not errs, "errors": errs}
    (SRC / "dimensions.json").write_text(json.dumps(dims, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("dimensions.json", "OK" if not errs else "NG", errs)
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
