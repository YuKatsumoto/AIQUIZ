extends RefCounted
class_name AnimationRig

## P1/P2共通のアニメーションリグ管理クラス
## 8種のFBXアニメーションの読み込み・再生・排他制御を一元管理する

const SLOT_TAUNT := 0
const SLOT_RUN := 1
const SLOT_GANGNAM := 2
const SLOT_SLIDE := 3
const SLOT_MOONWALK := 4
const SLOT_DROWNING := 5
const SLOT_FLAIR := 6
const SLOT_JUMP := 7

const FBX_PATHS := [
	"res://assets/animations/Y Bot@Step Hip Hop Dance.fbx",
	"res://assets/animations/Run.fbx",
	"res://assets/animations/Y Bot@Gangnam Style.fbx",
	"res://assets/animations/Slide Hip Hop Dance.fbx",
	"res://assets/animations/Moonwalk.fbx",
	"res://assets/animations/Drowning.fbx",
	"res://assets/animations/Flair.fbx",
	"res://assets/animations/Jumping.fbx",
]

const SLOT_NAMES := [
	"Taunt", "Run", "Gangnam", "Slide",
	"Moonwalk", "Drowning", "Flair", "Jump",
]

# 各スロットのデータ (nullを許容するためVariant型の配列)
var scenes: Array = []           # Node3D or null
var skeletons: Array = []        # Skeleton3D or null
var aps: Array = []              # AnimationPlayer or null
var bone_indices_list: Array = [] # Dictionary
var anim_names: Array = []       # String

# 現在アクティブなスケルトン情報
var active_skeleton: Skeleton3D = null
var active_bone_indices: Dictionary = {}
var mirror_x: bool = false
var is_rigged: bool = false
var loaded_emotes: Array[int] = [1, 2, 3]

var _prefix: String = "P1"

func _init(prefix: String = "P1") -> void:
	_prefix = prefix
	for i in range(8):
		scenes.append(null)
		skeletons.append(null)
		aps.append(null)
		bone_indices_list.append({})
		anim_names.append("")

func load_all(parent: Node3D, loader: Callable, emote_slots: Array[int] = []) -> void:
	"""全FBXを読み込む。loader は _load_fbx_scene(path, name) -> Variant を渡す"""
	if not emote_slots.is_empty():
		loaded_emotes = emote_slots.duplicate()
	print("[RIG] %s load_all - loaded_emotes: %s" % [_prefix, str(loaded_emotes)])

	var emote_paths = FBX_PATHS.duplicate()
	if loaded_emotes.size() > 0:
		var path_0 = EmoteData.get_emote_fbx(loaded_emotes[0])
		if not path_0.is_empty():
			emote_paths[SLOT_TAUNT] = path_0
	if loaded_emotes.size() > 1:
		var path_1 = EmoteData.get_emote_fbx(loaded_emotes[1])
		if not path_1.is_empty():
			emote_paths[SLOT_GANGNAM] = path_1
	if loaded_emotes.size() > 2:
		var path_2 = EmoteData.get_emote_fbx(loaded_emotes[2])
		if not path_2.is_empty():
			emote_paths[SLOT_SLIDE] = path_2

	for i in range(8):
		var rig_name: String = _prefix + str(SLOT_NAMES[i]) + "Rig"
		var path: String = emote_paths[i]
		if path.is_empty():
			continue
		var data = loader.call(path, rig_name)
		if data:
			scenes[i] = data["node"]
			skeletons[i] = data["skeleton"]
			aps[i] = data["anim_player"]
			bone_indices_list[i] = data["bone_indices"]
			anim_names[i] = data["anim_name"]
			if i == SLOT_JUMP:
				var anim = aps[i].get_animation(anim_names[i])
				if anim:
					anim.loop_mode = Animation.LOOP_NONE
			print("[RIG] %s %s scene ready: %s" % [_prefix, SLOT_NAMES[i], anim_names[i]])
	is_rigged = (skeletons[SLOT_TAUNT] != null) or (skeletons[SLOT_RUN] != null)
	if is_rigged:
		print("[RIG] Rig mode ENABLED for %s" % _prefix)

func play_slot(slot: int) -> bool:
	"""指定スロットを再生し、他を全て停止。成功時trueを返す"""
	var target_ap = aps[slot] as AnimationPlayer
	var target_anim: String = anim_names[slot]
	if not target_ap or target_anim == "":
		return false
	# 他のAPを停止
	for i in range(8):
		var ap = aps[i] as AnimationPlayer
		if ap and ap != target_ap and ap.is_playing():
			ap.stop()
	# 再生開始
	if not target_ap.is_playing():
		if slot == SLOT_JUMP:
			target_ap.play(target_anim, -1, 1.0)
		else:
			target_ap.play(target_anim)
	active_skeleton = skeletons[slot]
	active_bone_indices = bone_indices_list[slot]
	mirror_x = true
	return true

func stop_all() -> void:
	"""全APを停止"""
	for i in range(8):
		var ap = aps[i] as AnimationPlayer
		if ap and ap.is_playing():
			ap.stop()

func select_animation(player_y: float, jump_trigger: bool, emote: int,
		moving_back: bool, is_active_state: bool,
		jump_ap_playing: bool) -> bool:
	"""状態から再生すべきアニメーションを決定し実行。リグ適用すべきならtrueを返す"""
	# Priority 1: 溺死（マグマ落下中）
	if player_y < -1.0:
		return play_slot(SLOT_DROWNING)

	# Priority 2: ジャンプ
	# 物理ジャンプ中はFBXアニメーションを適用せず、従来のプロシージャルジャンプを使用する
	if player_y > 0.01:
		stop_all()
		return false

	# Priority 3: エモート
	if emote > 0:
		var idx = loaded_emotes.find(emote)
		print("[RIG] %s select_animation - emote: %d, loaded_emotes: %s, idx: %d" % [_prefix, emote, str(loaded_emotes), idx])
		if idx != -1:
			var slot_map := {0: SLOT_TAUNT, 1: SLOT_GANGNAM, 2: SLOT_SLIDE}
			if slot_map.has(idx):
				return play_slot(slot_map[idx])

	# Priority 4: 走行（プレイ中 or ゴールレース中）
	if is_active_state:
		if moving_back:
			return play_slot(SLOT_MOONWALK)
		else:
			return play_slot(SLOT_RUN)

	# Idle: 全停止
	stop_all()
	return false

func is_jump_playing() -> bool:
	"""ジャンプAPが再生中かどうか"""
	var ap = aps[SLOT_JUMP] as AnimationPlayer
	return ap != null and ap.is_playing()

func is_emote_playing() -> bool:
	"""エモート再生中かどうか"""
	for slot in [SLOT_TAUNT, SLOT_GANGNAM, SLOT_SLIDE, SLOT_FLAIR]:
		var ap = aps[slot] as AnimationPlayer
		if ap and ap.is_playing():
			return true
	return false
