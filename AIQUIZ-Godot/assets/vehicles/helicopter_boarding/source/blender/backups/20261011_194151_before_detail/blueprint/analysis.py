"""寸法の集計、マーカー、すき間のチェック（図面の数値はここから出す）。"""
import math

import numpy as np

import cast
import heli_design as hd

# ---- 乗り込みの立ち位置（地面基準）
BOARD_Z = (hd.STEP["z0"] + hd.STEP["z1"]) / 2
MK = {
    "MK_GroundContact": dict(pos=(0.0, 0.0, 0.0), note="スキッドの下面の中心（着地の基準）。原点からの高さ＝SKID_DROP"),
    "MK_IdleSpot": dict(pos=(-4.30, 0.0, BOARD_Z), yaw=90, note="メニューで待つ立ち位置（デッキ上。ヘリポート側で決めてよい）"),
    "MK_BoardStand": dict(pos=(-2.72, 0.0, BOARD_Z), yaw=90, note="ステップの前。ここで止まり、ヘリの方を向く"),
    "MK_Step": dict(pos=((hd.STEP["x0"] + hd.STEP["x1"]) / 2, hd.STEP_Y, BOARD_Z), yaw=90, note="ステップの上面（1 段目）"),
    "MK_DoorSill": dict(pos=(-1.25, hd.FLOOR_Y, BOARD_Z), yaw=90, note="ドアを入ってすぐの床（2 段目）。ここでかがむ"),
    "MK_SeatFront": dict(pos=(-hd.SEAT_X, hd.FLOOR_Y, -1.66), yaw=180, note="座席の前で機首を向いて立つ。Sitting_Enter の始まり"),
    "MK_SeatPassenger": dict(pos=hd.PASSENGER_PELVIS, yaw=180, note="座ったプレイヤーの pelvis（ももの下面＝座面）"),
    "MK_SeatPilot": dict(pos=None, yaw=180, note="ハテナの原点（足元の基準。等倍）。体の下端がクッションの上"),
    "MK_HatchDrop": dict(pos=(0.0, hd.BELLY_Y, (hd.HATCH_Z[0] + hd.HATCH_Z[1]) / 2), note="床下ハッチの中心（本編の投下）"),
    "MK_CabinWait": dict(pos=(0.0, hd.FLOOR_Y + 0.32, (hd.HATCH_Z[0] + hd.HATCH_Z[1]) / 2), note="ハッチの上でかがんで待つ pelvis（今の CABIN_WAIT_PELVIS_HEIGHT と同じ 0.32）"),
    "MK_CockpitLight": dict(pos=(0.0, 3.05, -1.45), note="操縦室の明かり"),
    "MK_CabinLight": dict(pos=(0.0, 2.85, 0.40), note="荷室（ハッチの上）の明かり"),
}
MK["MK_SeatPilot"]["pos"] = tuple(float(v) for v in cast.hatena_root())


def to_model(p):
    return (p[0], p[1] - hd.ORIGIN_Y, p[2])


def interior_ceiling(x, z):
    return hd.section_extent(z, x=x, inner=True)


def interior_half_width(y, z):
    return hd.section_extent(z, y=y, inner=True)


def check_rows():
    """[(項目, 値, 基準, ok, メモ)]"""
    rows = []
    hats = [v for v in cast.HATS.values() if v["min"][0] < 1e8]

    # 1. 座ったときの帽子と天井
    worst = None
    for pose in ("sit_idle", "driving", "proc_sit"):
        xf = cast.player_xform(pose, hd.PASSENGER_PELVIS)
        mount = cast.player_joint(pose, "hat_mount", xf)
        for h in hats:
            half = max(abs(h["min"][0]), abs(h["max"][0]))
            top = mount[1] + h["max"][1]
            for dx in (-half, 0.0, half):
                c = interior_ceiling(mount[0] + dx, mount[2])
                gap = c - top
                if worst is None or gap < worst[0]:
                    worst = (gap, h["name"], pose)
    rows.append(("座ったプレイヤーの帽子と天井", worst[0], "≥ 0.03", worst[0] >= 0.03, f"いちばん近いのは「{worst[1]}」（{worst[2]}）"))

    # 2. 座ったプレイヤーと横の壁
    worst = None
    for pose in ("sit_idle", "driving", "proc_sit", "sit_talk"):
        xf = cast.player_xform(pose, hd.PASSENGER_PELVIS)
        pts = cast.player_points(pose, xf)
        for p in pts:
            if p[1] < hd.FLOOR_Y + 0.05:
                continue
            w = interior_half_width(p[1], p[2])
            gap = w - abs(p[0])
            if worst is None or gap < worst[0]:
                worst = (gap, pose)
    rows.append(("座ったプレイヤーの腕と横の壁", worst[0], "≥ 0.03", worst[0] >= 0.03, f"いちばん近いのは {worst[1]}"))

    # 3. 卒業帽（いちばん広い帽子）のつばと壁
    xf = cast.player_xform("sit_idle", hd.PASSENGER_PELVIS)
    mount = cast.player_joint("sit_idle", "hat_mount", xf)
    wide = max(hats, key=lambda h: max(abs(h["min"][0]), abs(h["max"][0])))
    half = max(abs(wide["min"][0]), abs(wide["max"][0]))
    y_brim = mount[1] + wide["max"][1]
    gap = interior_half_width(y_brim, mount[2]) - abs(mount[0] - half)
    rows.append(("いちばん広い帽子のつばと壁", gap, "≥ 0.03", gap >= 0.03, f"「{wide['name']}」半幅 {half:.2f}"))

    # 4. ひざ・足と計器盤
    worst = None
    for pose in ("sit_idle", "driving", "sit_talk"):
        xf = cast.player_xform(pose, hd.PASSENGER_PELVIS)
        pts = cast.player_points(pose, xf)
        sel = pts[(pts[:, 1] > hd.DASH_BOTTOM_Y - 0.05) & (pts[:, 1] < hd.DASH_TOP_Y + 0.05)]
        if len(sel):
            gap = sel[:, 2].min() - hd.DASH_BACK_Z
            if worst is None or gap < worst[0]:
                worst = (gap, pose)
    rows.append(("座ったプレイヤーの手・ひざと計器盤", worst[0], "≥ 0.05", worst[0] >= 0.05, f"いちばん近いのは {worst[1]}"))

    # 5. 足の裏と床
    xf = cast.player_xform("sit_idle", hd.PASSENGER_PELVIS)
    sole = cast.player_points("sit_idle", xf)[:, 1].min()
    rows.append(("座ったプレイヤーの足の裏と床", sole - hd.FLOOR_Y, "−0.03〜+0.06", -0.03 <= sole - hd.FLOOR_Y <= 0.06, "Sitting_Idle_Loop"))

    # 6. ハテナと天井・壁
    _, verts, _ = cast.hatena("seated")
    gaps_c = [interior_ceiling(v[0], v[2]) - v[1] for v in verts[::7] if interior_ceiling(v[0], v[2]) is not None]
    gaps_w = [interior_half_width(v[1], v[2]) - abs(v[0]) for v in verts[::7] if v[1] > hd.FLOOR_Y + 0.1]
    rows.append(("ハテナの「？」と天井", min(gaps_c), "≥ 0.10", min(gaps_c) >= 0.10, "等倍（1.0）"))
    rows.append(("ハテナの腕と横の壁", min(gaps_w), "≥ 0.03", min(gaps_w) >= 0.03, ""))
    # 7. 2 人の間（プレイヤーの右腕とハテナの左手）
    xf = cast.player_xform("sit_idle", hd.PASSENGER_PELVIS)
    p_in = cast.player_points("sit_idle", xf)[:, 0].max()
    h_in = verts[:, 0].min()
    rows.append(("プレイヤーとハテナのあいだ", h_in - p_in, "≥ 0.05", h_in - p_in >= 0.05, "左右の席の内側どうし"))

    # 8. 正面から顔が見えるか（計器盤の上端より上）
    dash_line = hd.DASH_TOP_Y + 0.06
    xf = cast.player_xform("sit_idle", hd.PASSENGER_PELVIS)
    head = cast.player_joint("sit_idle", "head_pivot", xf)[1] + 0.22
    eyes = cast.hatena_root()[1] + 1.105
    mouth = cast.hatena_root()[1] + 0.986
    rows.append(("プレイヤーの顔の中心と計器盤の上端", head - dash_line, "≥ 0.30", head - dash_line >= 0.30, "正面カメラで顔が隠れない"))
    rows.append(("ハテナの口と計器盤の上端", mouth - dash_line, "≥ 0.10", mouth - dash_line >= 0.10, f"目の高さ {eyes:.2f}"))

    # 9. 立って乗り込むとき：開いたドアと帽子（いちばん高い帽子）
    door = [m for m in hd.build_heli(door_l=1.0) if m.name == "door_L"]
    door_pts = np.concatenate([m.tris.reshape(-1, 3) for m in door])
    tall = cast.tallest_hat()
    tall_half = max(abs(tall["min"][0]), abs(tall["max"][0]), abs(tall["min"][2]), abs(tall["max"][2]))
    for label, pose, mk in (("ステップの上", "walk_b", "MK_Step"), ("ドアの入口（かがむ）", "crouch_fwd", "MK_DoorSill"), ("座席の前（立つ）", "sit_enter_0", "MK_SeatFront")):
        m = MK[mk]
        xf = cast.player_xform(pose, m["pos"], m["yaw"], mode="feet")
        mount = cast.player_joint(pose, "hat_mount", xf)
        top = mount[1] + tall["max"][1]
        near = door_pts[(np.abs(door_pts[:, 0] - mount[0]) < tall_half + 0.05) & (np.abs(door_pts[:, 2] - mount[2]) < tall_half + 0.05)]
        above = near[near[:, 1] > mount[1]]
        roof = interior_ceiling(mount[0] + math.copysign(tall_half, -mount[0]), mount[2]) if abs(mount[0]) - tall_half < hd.DOOR_HINGE_X else None
        gap = (above[:, 1].min() - top) if len(above) else 9.0
        if roof is not None:
            gap = min(gap, roof - top)
        rows.append((f"開いたドアと帽子：{label}", gap, "≥ 0.05", gap >= 0.05, f"「{tall['name']}」で確認"))

    # 10. 開いたドアとローターのブレード（前後に止めた向き）
    blades = np.concatenate([m.tris.reshape(-1, 3) for m in hd.build_heli(door_l=1.0) if m.name == "blade"])
    d = np.min(np.linalg.norm(door_pts[::3, None, :] - blades[None, ::2, :], axis=2))
    rows.append(("開いたドアとローターのブレード", d, "≥ 0.20", d >= 0.20, "ブレードを前後に止めたとき"))

    # 11. ブレードの先と地面に立つ人（いちばん高い帽子）
    idle_top = cast.player_points("idle", np.eye(4))
    stand_h = (cast.player_joint("idle", "hat_mount", np.eye(4))[1] - idle_top[:, 1].min()) + tall["max"][1]
    tip = hd.ROTOR_HUB_Y - 0.12 - 0.025
    rows.append(("止まったブレードの先と、地面に立つ人の帽子", tip - stand_h, "≥ 0.50", tip - stand_h >= 0.50, f"立った高さ（帽子込み）{stand_h:.2f}"))
    tr = hd.TAIL_ROTOR
    rows.append(("尾のローターの下端と、地面に立つ人の帽子", tr["y"] - tr["radius"] - stand_h, "≥ 0.00", tr["y"] - tr["radius"] - stand_h >= 0, "尾のそばを歩かせない前提"))

    # 12. 段差
    leg = cast.player_joint("idle", "pelvis", np.eye(4))[1] - idle_top[:, 1].min()
    rows.append(("1 段の高さ（地面→ステップ→床）", hd.STEP_Y, f"≤ 足の長さの 35%（{leg * 0.35:.2f}）", hd.STEP_Y <= leg * 0.35, f"足の長さ（pelvis〜足の裏）{leg:.2f}"))
    return rows


def overall():
    meshes = hd.build_heli()
    pts = np.concatenate([m.tris.reshape(-1, 3) for m in meshes])
    body = np.concatenate([m.tris.reshape(-1, 3) for m in meshes if m.name in ("body", "canopy", "door_L", "door_R", "bay_window")])
    blade = np.concatenate([m.tris.reshape(-1, 3) for m in meshes if m.name == "blade"])
    fin = np.concatenate([m.tris.reshape(-1, 3) for m in meshes if m.name == "fin"])
    tail = np.concatenate([m.tris.reshape(-1, 3) for m in meshes if m.name in ("tail_blade", "tail_hub")])
    return dict(
        length_body=float(fin[:, 2].max() - body[:, 2].min()),
        nose_z=float(body[:, 2].min()), tail_z=float(max(fin[:, 2].max(), tail[:, 2].max())),
        width_body=float(body[:, 0].max() - body[:, 0].min()),
        height_roof=float(body[:, 1].max()), height_hub=hd.ROTOR_HUB_Y + 0.10, height_fin=float(fin[:, 1].max()),
        rotor_diameter=2 * hd.ROTOR_RADIUS, tail_rotor_diameter=2 * hd.TAIL_ROTOR["radius"],
        skid_track=2 * hd.SKID_X, skid_length=hd.SKID_Z[1] - hd.SKID_Z[0] + 0.42,
        overall_length_rotor=float(max(pts[:, 2].max(), blade[:, 2].max()) - min(pts[:, 2].min(), blade[:, 2].min())),
    )


def interior():
    z = hd.PASSENGER_PELVIS[2]
    return dict(
        width_at_shoulder=2 * interior_half_width(2.0, z),
        ceiling_center=interior_ceiling(0.0, z), ceiling_at_seat=interior_ceiling(hd.SEAT_X, z),
        headroom_at_seat=interior_ceiling(hd.SEAT_X, z) - hd.FLOOR_Y,
        door_open_length=hd.DOOR_REAR_Z - hd.DOOR_FRONT_Z,
        door_sill=hd.DOOR_SILL_Y,
        door_hinge_front=hd.door_hinge("L")[0][1], door_hinge_rear=hd.door_hinge("L")[1][1],
    )
