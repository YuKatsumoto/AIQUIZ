extends Control
class_name EmoteDancer2D

## エモートFBXのスケルトンを毎フレーム「正面2D投影」し、平面のキャラとして _draw() で描く。
## 手描き2D素材を持たないため、3Dエモートアニメをそのまま2D表示へ流用するライブ・ベクターキャラ。
## 非表示の極小 SubViewport 内に FBX を置いてアニメだけ回し、ボーンの姿勢を読み取って描画する。

## hips 基準・ワールド単位での標準身長（足〜頭）。スケール基準に使う。
const REF_HEIGHT: float = 1.65
## 左右反転（+1 で素のまま）。正面ショーケースなので見栄え優先で固定。
const MIRROR_X: float = 1.0

## 描画する関節キー（map_mixamo_bones のキーに対応）
const JOINT_KEYS: Array[String] = [
	"hips", "spine", "neck", "head",
	"l_upper_arm", "l_lower_arm", "l_hand",
	"r_upper_arm", "r_lower_arm", "r_hand",
	"l_upper_leg", "l_lower_leg", "l_foot",
	"r_upper_leg", "r_lower_leg", "r_foot",
]

## エモート未設定（なし）の静止立ちポーズ（hips 基準ワールド座標 x:右 y:上）
const DEFAULT_POSE: Dictionary = {
	"hips": Vector3(0.0, 0.0, 0.0),
	"spine": Vector3(0.0, 0.22, 0.0),
	"neck": Vector3(0.0, 0.45, 0.0),
	"head": Vector3(0.0, 0.62, 0.0),
	"l_upper_arm": Vector3(-0.16, 0.42, 0.0),
	"l_lower_arm": Vector3(-0.20, 0.18, 0.0),
	"l_hand": Vector3(-0.22, -0.02, 0.0),
	"r_upper_arm": Vector3(0.16, 0.42, 0.0),
	"r_lower_arm": Vector3(0.20, 0.18, 0.0),
	"r_hand": Vector3(0.22, -0.02, 0.0),
	"l_upper_leg": Vector3(-0.10, -0.05, 0.0),
	"l_lower_leg": Vector3(-0.11, -0.50, 0.0),
	"l_foot": Vector3(-0.12, -0.92, 0.0),
	"r_upper_leg": Vector3(0.10, -0.05, 0.0),
	"r_lower_leg": Vector3(0.11, -0.50, 0.0),
	"r_foot": Vector3(0.12, -0.92, 0.0),
}

var _vp: SubViewport
var _fbx_node: Node3D
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _bones: Dictionary = {}

var _cur_emote_id: int = -999
var _cur_is_p1: bool = true
var _is_none: bool = true

## 画面座標へ投影済みの関節（key -> Vector2）
var _pts: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_ensure_viewport()


func _ensure_viewport() -> void:
	if _vp and is_instance_valid(_vp):
		return
	# 描画はしない（姿勢計算だけ回す）極小・更新無効の SubViewport
	_vp = SubViewport.new()
	_vp.size = Vector2i(4, 4)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)


## 選択中スロットのエモートを表示対象に設定。直前と同じなら何もしない。
func set_emote(emote_id: int, is_p1: bool) -> void:
	var norm := EmoteData.normalize_emote_id(emote_id)
	if norm == _cur_emote_id and is_p1 == _cur_is_p1 and (_skel != null or _is_none):
		return
	_cur_emote_id = norm
	_cur_is_p1 = is_p1
	_load_emote(norm)
	queue_redraw()


func _load_emote(emote_id: int) -> void:
	_ensure_viewport()
	_clear_fbx()

	if emote_id == EmoteData.EMOTE_NONE:
		_is_none = true
		return

	var fbx_path := EmoteData.get_emote_fbx(emote_id)
	if fbx_path.is_empty() or not ResourceLoader.exists(fbx_path):
		_is_none = true
		return
	var scene := load(fbx_path) as PackedScene
	if not scene:
		_is_none = true
		return

	var node := scene.instantiate() as Node3D
	if not node:
		_is_none = true
		return
	_fbx_node = node
	_vp.add_child(node)

	# メッシュは描画に使わない。姿勢だけ読む。
	for child in node.find_children("*", "MeshInstance3D", true, false):
		child.hide()

	for child in node.find_children("*", "Skeleton3D", true, false):
		_skel = child as Skeleton3D
		break
	if _skel:
		_bones = EmoteBlockmanPreview.map_mixamo_bones(_skel)

	for child in node.find_children("*", "AnimationPlayer", true, false):
		_anim = child as AnimationPlayer
		break

	if _anim:
		var best := EmoteBlockmanPreview.pick_best_emote_animation(_anim)
		if best != "":
			var a: Animation = _anim.get_animation(best)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR
			_anim.play(best)

	_is_none = _skel == null


func _clear_fbx() -> void:
	if _fbx_node and is_instance_valid(_fbx_node):
		_fbx_node.queue_free()
	_fbx_node = null
	_skel = null
	_anim = null
	_bones = {}


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if size.y < 12.0 or size.x < 12.0:
		return
	_rebuild_points()
	queue_redraw()


## 現在の姿勢（FBX か既定ポーズ）を画面座標へ投影して _pts に格納
func _rebuild_points() -> void:
	var rel: Dictionary = {}
	if _is_none or _skel == null or not is_instance_valid(_skel):
		for k in DEFAULT_POSE.keys():
			rel[k] = DEFAULT_POSE[k] as Vector3
	else:
		if not _bones.has("hips"):
			return
		var hips_origin: Vector3 = _skel.get_bone_global_pose(int(_bones["hips"])).origin
		for k in JOINT_KEYS:
			if not _bones.has(k):
				continue
			var p: Vector3 = _skel.get_bone_global_pose(int(_bones[k])).origin
			rel[k] = p - hips_origin

	var scale_px: float = (size.y * 0.80) / REF_HEIGHT
	var hips_screen := Vector2(size.x * 0.5, size.y * 0.50)
	_pts.clear()
	for k in rel.keys():
		var v: Vector3 = rel[k]
		_pts[k] = hips_screen + Vector2(MIRROR_X * v.x, -v.y) * scale_px


func _draw() -> void:
	if _pts.is_empty():
		return
	var is_p1 := _cur_is_p1
	var body_col: Color = PlayerController.P1_BODY if is_p1 else PlayerController.P2_BODY
	var head_col: Color = PlayerController.P1_HEAD if is_p1 else PlayerController.P2_HEAD
	var limb_col: Color = PlayerController.P1_LIMB if is_p1 else PlayerController.P2_LIMB

	var scale_px: float = (size.y * 0.80) / REF_HEIGHT
	var torso_w := scale_px * 0.24
	var limb_w := scale_px * 0.13
	var head_r := scale_px * 0.17
	var hand_r := scale_px * 0.075
	var foot_r := scale_px * 0.085

	# 足元の楕円シャドウ
	_draw_floor_shadow(scale_px)

	# 脚（先に描いて胴の後ろへ）
	_draw_limb("l_upper_leg", "l_lower_leg", limb_w, limb_col)
	_draw_limb("l_lower_leg", "l_foot", limb_w, limb_col)
	_draw_limb("r_upper_leg", "r_lower_leg", limb_w, limb_col)
	_draw_limb("r_lower_leg", "r_foot", limb_w, limb_col)
	_draw_joint_dot("l_foot", foot_r, limb_col)
	_draw_joint_dot("r_foot", foot_r, limb_col)

	# 胴（hips→spine→neck の太い帯）
	_draw_limb("hips", "spine", torso_w, body_col)
	_draw_limb("spine", "neck", torso_w, body_col)
	if _pts.has("l_upper_leg") and _pts.has("r_upper_leg"):
		draw_line(_pts["l_upper_leg"], _pts["r_upper_leg"], body_col, torso_w * 0.9, true)
	_draw_joint_dot("hips", torso_w * 0.5, body_col)
	_draw_joint_dot("spine", torso_w * 0.5, body_col)
	_draw_joint_dot("neck", torso_w * 0.5, body_col)

	# 腕
	_draw_limb("l_upper_arm", "l_lower_arm", limb_w, limb_col)
	_draw_limb("l_lower_arm", "l_hand", limb_w, limb_col)
	_draw_limb("r_upper_arm", "r_lower_arm", limb_w, limb_col)
	_draw_limb("r_lower_arm", "r_hand", limb_w, limb_col)
	if _pts.has("neck") and _pts.has("l_upper_arm"):
		draw_line(_pts["neck"], _pts["l_upper_arm"], body_col, torso_w * 0.7, true)
	if _pts.has("neck") and _pts.has("r_upper_arm"):
		draw_line(_pts["neck"], _pts["r_upper_arm"], body_col, torso_w * 0.7, true)
	_draw_joint_dot("l_hand", hand_r, limb_col)
	_draw_joint_dot("r_hand", hand_r, limb_col)

	# 頭
	if _pts.has("head"):
		var hp: Vector2 = _pts["head"]
		draw_circle(hp, head_r, head_col)
		# 簡易の目（正面）
		var eye_dx := head_r * 0.36
		var eye_r := head_r * 0.16
		var eye_col := Color(0.12, 0.12, 0.16)
		draw_circle(hp + Vector2(-eye_dx, -head_r * 0.05), eye_r, eye_col)
		draw_circle(hp + Vector2(eye_dx, -head_r * 0.05), eye_r, eye_col)


func _draw_floor_shadow(scale_px: float) -> void:
	# 足の平均位置の下に薄い楕円
	var fy := size.y * 0.5
	var fx := size.x * 0.5
	var cnt := 0
	if _pts.has("l_foot"):
		fy = max(fy, _pts["l_foot"].y)
		cnt += 1
	if _pts.has("r_foot"):
		fy = max(fy, _pts["r_foot"].y)
		cnt += 1
	var rx := scale_px * 0.34
	var ry := scale_px * 0.10
	var center := Vector2(fx, fy + ry * 0.6)
	var pts := PackedVector2Array()
	for i in range(20):
		var ang := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.22))


func _draw_limb(a_key: String, b_key: String, width: float, color: Color) -> void:
	if not _pts.has(a_key) or not _pts.has(b_key):
		return
	draw_line(_pts[a_key], _pts[b_key], color, width, true)
	# 角を丸める
	draw_circle(_pts[a_key], width * 0.5, color)
	draw_circle(_pts[b_key], width * 0.5, color)


func _draw_joint_dot(key: String, radius: float, color: Color) -> void:
	if not _pts.has(key):
		return
	draw_circle(_pts[key], radius, color)
