"""参照画像の実測値を較正し、寸法表 dimensions.json と検証レポート measure_report.json を作る。

- 絶対寸法の正はゲーム定数（../game_constants.json）。画像からは比率と、定数で縛られていない
  設計値の確認だけを取る（PROMPTS.md / DIMENSIONS.md の方針）。
- 同じ寸法を2面以上で測れたものは差を出し、許容差（主要 2%、二次 5%、細部 10%）で判定する。
- 灯台の置き場所の候補、ヘリ・カメラ・水路とのクリアランス、2P カメラへの再投影も計算する。

    python measure.py
"""
from __future__ import annotations

import io
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent
sys.path.insert(0, str(SRC / "guides"))
import make_guides as G  # noqa: E402  ゲーム定数・カメラ・暫定設計値を共有する

LM = json.loads((HERE / "landmarks.json").read_text(encoding="utf-8"))
CAL = json.loads((HERE / "calibration.json").read_text(encoding="utf-8"))
TOL = {"primary": 0.02, "secondary": 0.05, "detail": 0.10}


def rel(a: float, b: float) -> float:
    return abs(a - b) / max(abs(b), 1e-9)


def check(name, measured, reference, tier, source):
    err = rel(measured, reference)
    return {"item": name, "measured": round(measured, 3), "reference": round(reference, 3),
            "rel_error": round(err, 4), "tier": tier, "tolerance": TOL[tier],
            "pass": err <= TOL[tier], "reference_source": source}


def p01_runway_side():
    lm = LM["P01_runway_side_elev"]
    sx = CAL["P01_runway_side_elev"]["px_per_m"]            # 59.83 px/m（横）
    sy = 41.739 * CAL["P01_runway_side_elev"]["aspect_scale_y"]  # 59.36 px/m（縦）
    H = 1536
    Y = lambda y: 2.0 + (H / 2 - y) / sy
    m = {
        "mast_top_Y": Y(lm["mast_top_y"]),
        "upper_yard_Y": Y(lm["upper_yard_y"]),
        "upper_yard_len": (lm["upper_yard_x"][1] - lm["upper_yard_x"][0]) / sx,
        "sail_foot_Y": Y(lm["sail_foot_y"]),
        "sail_foot_len": (lm["sail_foot_x"][1] - lm["sail_foot_x"][0]) / sx,
        "mast_spacing": (lm["mast_x"][1] - lm["mast_x"][0]) / sx,
        "mast_diameter": lm["mast_width_px"] / sx,
        "booth_len_along_course": (lm["booth_x"][1] - lm["booth_x"][0]) / sx,
        "booth_panel_width": (lm["booth_panel_x"][1] - lm["booth_panel_x"][0]) / sx,
        "seat_pitch": (lm["seat_centers_x"][-1] - lm["seat_centers_x"][0]) / (len(lm["seat_centers_x"]) - 1) / sx,
        "water_Y": Y(lm["water_row"]),
    }
    checks = [
        check("P01 立面: マストの間隔 = ブロック長", m["mast_spacing"], G.BLOCK, "primary", "BLOCK_LENGTH"),
        check("P01 立面: 水面の高さ", m["water_Y"], G.SEA_Y, "primary", "OCEAN_SURFACE_Y"),
        check("P01 立面: 座席の間隔", m["seat_pitch"], 0.92, "secondary", "SEAT_PITCH"),
        check("P01 立面: マスト頂部の高さ（設計値の再現）", m["mast_top_Y"], G.DESIGN["mast"]["top_y"], "secondary", "DESIGN.mast.top_y"),
        check("P01 立面: 帆の足の長さ（設計値の再現）", m["sail_foot_len"], 2 * G.DESIGN["sail"]["half_len"], "secondary", "DESIGN.sail.half_len×2"),
    ]
    return m, checks


def p01_end():
    lm = LM["P01_end_elev"]
    sx = (lm["front_rail_x"] - lm["mast_axis_x"]) / (G.DESIGN["mast"]["x"] - (-0.6))
    sy = (lm["front_walkway_y"] - lm["rear_platform_y"]) / (G.ROW_BASE + G.DESIGN["rows"] * G.ROW_RISE - 0.22)
    aspect = rel(sx, sy)
    plat = G.ROW_BASE + G.DESIGN["rows"] * G.ROW_RISE
    Z = lambda y: plat + (lm["rear_platform_y"] - y) / sy
    m = {"px_per_m_x": sx, "px_per_m_y": sy, "aspect_mismatch": aspect,
         "mast_top_Y": Z(lm["mast_top_y"]), "yard_Y": Z(lm["yard_y"]),
         "sail_corner_Y": Z(lm["sail_corner"][1]),
         "sail_corner_x": G.DESIGN["mast"]["x"] - (lm["sail_corner"][0] - lm["mast_axis_x"]) / sx,
         "figure_height_by_y_scale": (lm["figure_y"][1] - lm["figure_y"][0]) / sy}
    usable = aspect <= 0.03
    return m, usable


def p05_ratios():
    lm = LM["P05_front_elev"]
    W = lm["sign_inner_x"][1] - lm["sign_inner_x"][0]
    water = lm["water_row"]
    r = {
        "sign_aspect_inner": W / (lm["sign_inner_y"][1] - lm["sign_inner_y"][0]),
        "sign_frame_border_W": ((lm["sign_outer_x"][1] - lm["sign_outer_x"][0]) - W) / 2 / W,
        "sign_bottom_above_water_W": (water - lm["sign_outer_y"][1]) / W,
        "sign_top_above_water_W": (water - lm["sign_outer_y"][0]) / W,
        "gallery_floor_above_water_W": (water - lm["gallery_floor_y"]) / W,
        "lantern_height_W": (lm["lantern_y"][1] - lm["lantern_y"][0]) / W,
        "lantern_width_W": (lm["lantern_x"][1] - lm["lantern_x"][0]) / W,
        "dome_top_above_water_W": (water - lm["dome_top_y"]) / W,
        "tower_width_top_W": lm["tower_width_top_px"] / W,
        "tower_width_low_W": lm["tower_width_low_px"] / W,
        "plinth_width_W": lm["plinth_width_px"] / W,
        "islet_width_W": (lm["islet_x"][1] - lm["islet_x"][0]) / W,
        "islet_height_W": (water - lm["islet_top_y"]) / W,
    }
    return r


def p07_ratios():
    lm = LM["P07_goal_stand_B_front_elev"]
    led_w = lm["led_x"][1] - lm["led_x"][0]
    return {"led_aspect": led_w / (lm["led_y"][1] - lm["led_y"][0]),
            "house_width_over_led": (lm["house_x"][1] - lm["house_x"][0]) / led_w,
            "deck_width_over_led": (lm["deck_x"][1] - lm["deck_x"][0]) / led_w,
            "flags_span_over_led": (lm["flags_x"][1] - lm["flags_x"][0]) / led_w}


def reprojection_check():
    """ゲームの 2P カメラで、設計どおりの最寄りマスト頂部を投影し、生成画像の位置と比べる。"""
    cam = G.Camera((0.0, G.EYE_2P, -G.BACK_2P), (0.0, G.LOOK_2P, G.AHEAD_2P), G.FOV_2P)
    W_img, H_img = 2752, 1536
    out = []
    lm = LM["V01b_2p_camera_guidefirst"]["nearest_mast_tops"]
    for side, (px, py) in zip((1, -1), lm):
        best = None
        for k in range(0, 20):
            z = G.BACK_Z + G.BLOCK * (k + 0.5)
            c = cam.cam((G.world_x(side, G.DESIGN["mast"]["x"]), G.DESIGN["mast"]["top_y"], z))
            if c[2] <= G.NEAR:
                continue
            x, y = cam.px(c)
            if 0 <= x <= G.W:
                best = (x * W_img / G.W, y * H_img / G.H, z)
                break
        if best:
            dy = abs(best[1] - py) / H_img
            dx = abs(best[0] - px) / W_img
            out.append({"side": "+X (P1, 画面左)" if side > 0 else "-X (P2, 画面右)", "mast_z": best[2],
                        "projected_px": [round(best[0]), round(best[1])], "image_px": [px, py],
                        "error_frame_h": round(dy, 4), "error_frame_w": round(dx, 4), "pass": dy <= 0.03})
    return out


def lighthouse_options(r):
    """灯台の置き場所 2 案。スタート時の 1P/2P カメラからの見かけの大きさと、走路との関係を計算する。"""
    hfov = 2 * math.atan(math.tan(math.radians(G.FOV_2P) / 2) * 16 / 9)
    frame_w = lambda d: 2 * d * math.tan(hfov / 2)
    endless_front = 927.5
    options = []
    for name, x, z, W in (("A 軸上・走路の先（エンドレスの最長 927.5m より奥）", 0.0, 980.0, 90.0),
                          ("B 軸から外した小島（画面右＝-X、ビル群と左右の釣り合い）", -240.0, 600.0, 40.0)):
        eye = (0.0, G.EYE_2P, -G.BACK_2P)
        d = math.dist((x, z), (eye[0], eye[2]))
        ang = math.degrees(math.atan2(abs(x), z - eye[2]))
        options.append({
            "option": name, "position_world_xz": [x, z], "sign_inner_width_W": W,
            "sign_height": round(W / r["sign_aspect_inner"], 1),
            "total_height_above_sea": round(W * r["dome_top_above_water_W"], 1),
            "islet_width": round(W * r["islet_width_W"], 1),
            "start_distance": round(d, 1), "angle_from_axis_deg": round(ang, 1),
            "in_start_view": ang < math.degrees(hfov / 2),
            "sign_width_share_of_frame_at_start": round(W / frame_w(d), 3),
            "overlaps_endless_course": abs(x) < 40 and z < endless_front + 30,
            "hidden_behind_goal_stand_in_2p": abs(x) < 20,
        })
    return options


def clearances():
    d = G.DESIGN
    mast_x = G.DESIGN["stand_center_x"] + d["mast"]["x"]
    heli_start = (16.5 + 20.0, 11.4 - 1.2 + 3.5)   # helicopter_arrival_director: hover ±16.5, 10.2 +3.5, 20m 外から
    return {
        "stand_inner_face_abs_x": G.DESIGN["stand_center_x"] + G.FRONT_X,
        "required_min_abs_x": 27.2,
        "sail_corner_abs_x": G.DESIGN["stand_center_x"] + d["sail"]["low_x"],
        "sail_corner_Y": d["sail"]["low_y"],
        "sail_post_abs_x": G.DESIGN["stand_center_x"] - 0.6,
        "mast_abs_x": mast_x, "mast_top_Y": d["mast"]["top_y"],
        "helicopter_start_abs_x_Y": heli_start,
        "helicopter_vs_mast_dx": round(mast_x - heli_start[0], 2),
        "helicopter_vs_mast_dY": round(heli_start[1] - d["mast"]["top_y"], 2),
        "water_lane_width": round(G.DESIGN["stand_center_x"] + G.FRONT_X - G.HALF_W, 2),
        "shark_orbit_abs_x": [15.7, 20.3],
    }


def main():
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    p01, p01_checks = p01_runway_side()
    end, end_usable = p01_end()
    lh = p05_ratios()
    gs = p07_ratios()
    reproj = reprojection_check()
    lho = lighthouse_options(lh)
    clr = clearances()
    cross = [
        check("マスト頂部の高さ：端面 vs 立面", end["mast_top_Y"], p01["mast_top_Y"], "secondary", "P01 立面の実測"),
        check("上のヤードの高さ：端面 vs 立面", end["yard_Y"], p01["upper_yard_Y"], "secondary", "P01 立面の実測"),
        check("帆の角の高さ：端面 vs 立面", end["sail_corner_Y"], p01["sail_foot_Y"], "secondary", "P01 立面の実測"),
    ]
    if not end_usable:  # 縦横の縮尺がずれた図との比較は判定しない（形の参考のみ）
        for c in cross:
            c["pass"] = None
            c["excluded"] = "P01 端面は縦横の縮尺差が 3% を超えるため寸法の照合に使わない"
    report = {
        "P01_runway_side_elev": {k: round(v, 3) for k, v in p01.items()},
        "P01_runway_side_checks": p01_checks,
        "P01_end_elev": {k: round(v, 3) if isinstance(v, float) else v for k, v in end.items()},
        "P01_end_elev_usable_for_dimensions": end_usable,
        "cross_view_checks": cross,
        "P05_lighthouse_ratios": {k: round(v, 3) for k, v in lh.items()},
        "P07_goal_stand_B_ratios": {k: round(v, 3) for k, v in gs.items()},
        "reprojection_2p_camera": reproj,
        "lighthouse_options": lho,
        "clearances": clr,
    }
    (HERE / "measure_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for c in p01_checks + cross:
        tag = "SKIP " if c["pass"] is None else ("PASS " if c["pass"] else "FAIL ")
        print(tag + c["item"], c["measured"], "vs", c["reference"], f"({c['rel_error']:.1%})")
    print("P01 端面: 縦横の縮尺差", f"{end['aspect_mismatch']:.1%}", "→ 寸法に", "使う" if end_usable else "使わない")
    for r in reproj:
        print("再投影", r["side"], "誤差 フレーム高さの", f"{r['error_frame_h']:.1%}", "PASS" if r["pass"] else "FAIL")
    for o in lho:
        print("灯台", o["option"], "高さ", o["total_height_above_sea"], "m, 画面幅の", o["sign_width_share_of_frame_at_start"])
    print("クリアランス", clr)


if __name__ == "__main__":
    main()
