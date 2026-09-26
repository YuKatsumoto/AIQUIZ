class_name GoalStand
extends Node3D

## Finish-line grandstand at the far end of the conveyor (assets/goal_stand, built
## in Blender through the Higgsfield connector). Three standing tiers of block
## spectators react to the finish: team fans cheer or despair, hotheads pelt the
## loser with eggs, party people dance the game's own emotes, sign holders flip
## their boards to "ブーー！" when their player loses.
##
## Blender builds the stand facing -Y (glTF +Z); this node turns it PI so the crowd
## looks back down the conveyor. Spectators live in the same stand space.

const STAND_SCENE: PackedScene = preload("res://assets/goal_stand/goal_stand.glb")
const SPECTATOR_SCENE: PackedScene = preload("res://assets/goal_stand/goal_stand_spectator.glb")
const PROPS_SCENE: PackedScene = preload("res://assets/goal_stand/goal_stand_props.glb")
const SPECTATOR_SHADER: Shader = preload("res://shaders/goal_stand_spectator.gdshader")
const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const LAYOUT_PATH := "res://assets/goal_stand/goal_stand_layout.json"
const CLIPS_PATH := "res://assets/goal_stand/goal_stand_clips.json"

## Front of the stand past the goal line. The ceremony conveyor ends 24 m past the
## goal and its side frames overhang 1.2 m; the stand starts just beyond.
const GOAL_OFFSET := 25.8
const SPACING := 0.92
const SPAWN_PER_FRAME := 6
const ACTIVE_DISTANCE := 170.0
const FULL_RATE_DISTANCE := 70.0
const FAR_STEP := 1.0 / 15.0
const LOW_STEP := 1.0 / 30.0
const EGG_BUDGET := 18
const EGG_SPEED := 19.0
const MISS_CHANCE := 0.25
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)

enum Kind { FAN, HOTHEAD, DANCER, SIGN, FLAG, FOAM }

const IDLE_CLIPS: Array[StringName] = [&"SPEC_Idle", &"SPEC_Idle", &"SPEC_Talk", &"SPEC_Phone", &"SPEC_Nod"]
const DANCES: Array[StringName] = [&"SPEC_Dance_YMCA", &"SPEC_Dance_Gangnam", &"SPEC_Dance_Silly",
	&"SPEC_Dance_HokeyPokey", &"SPEC_Dance_RunningMan", &"SPEC_Dance_WaveHipHop", &"SPEC_Dance_Swing",
	&"SPEC_DanceBounce"]
const HAIRS: Array[String] = ["Short", "Long", "Cap", "Afro", "Bald", "Bun", "Headband"]
const SKINS: Array[Color] = [Color("#f2c9a5"), Color("#e8b48c"), Color("#d69a6e"), Color("#b97a50"),
	Color("#8d5a3a"), Color("#f6d5bd")]
const HAIR_COLORS: Array[Color] = [Color("#2b1d14"), Color("#3b2a1e"), Color("#5a3a22"), Color("#8a5a2b"),
	Color("#c99a4a"), Color("#1a1a1a")]
const PANTS: Array[Color] = [Color("#2e3a55"), Color("#3b5b8c"), Color("#222222"), Color("#8b7b5a"), Color("#555a60")]
const SHOES: Array[Color] = [Color("#1e1e22"), Color("#f0f0f0"), Color("#b23a3a"), Color("#3a3a3a")]
const P1_SHIRTS: Array[Color] = [Color("#f28c33"), Color("#e8702a"), Color("#f5a04a"), Color("#ef6b3b"), Color("#ffb347")]
const P2_SHIRTS: Array[Color] = [Color("#33a6e6"), Color("#2a86d0"), Color("#4fbdeb"), Color("#2f6fb7"), Color("#5ac8fa")]
const NEUTRAL_SHIRTS: Array[Color] = [Color("#61b887"), Color("#9873c5"), Color("#ec8bab"), Color("#e9e3ce"),
	Color("#f0b541"), Color("#ef6958")]


class Spectator:
	var root: Node3D
	var ap: AnimationPlayer
	var skeleton: Skeleton3D
	var body: MeshInstance3D
	var shaded: Array[MeshInstance3D] = []
	var props := {}
	var kind := 0
	var team := 0
	var row := 0
	var hair := "Short"
	var idle_clip := &"SPEC_Idle"
	var clip := &""
	var queued := &""
	var queued_at := -1.0
	var mood := ""
	var next_change := 0.0
	var speed := 1.0
	var anger := 0.0
	var anger_sent := -1.0
	var yaw := 0.0
	var hand_bone := -1
	var throws_left := 0
	var throw_started := -1.0
	var released := false
	var next_throw := 0.0
	var boo_sign := false


var spectators: Array[Spectator] = []
var eggs: GoalStandEggs
var quality := "balanced"

var _layout := {}
var _clips := {}
var _material: ShaderMaterial
var _crowd: Node3D
var _structure: Node3D
var _slots: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _anim_accumulator := 0.0
var _mood := {"key": "idle"}
var _burst_team := 0
var _burst_until := -1.0
var _last_mask := 0
var _egg_budget := EGG_BUDGET
var _cues := {}
var _update_usec := 0.0


func setup(graphics_quality: String, crowd_seed: int = 0x51AD) -> void:
	name = "GoalStand"
	quality = QualityRules.normalize(graphics_quality)
	rotation.y = PI
	_rng.seed = crowd_seed
	_layout = _read_json(LAYOUT_PATH)
	_clips = (_read_json(CLIPS_PATH) as Dictionary).get("clips", {})
	_material = ShaderMaterial.new()
	_material.shader = SPECTATOR_SHADER
	_structure = STAND_SCENE.instantiate() as Node3D
	_structure.name = "Structure"
	add_child(_structure)
	var shadows := quality == QualityRules.HIGH and not QualityRules.is_mobile_target()
	for node: Node in _structure.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_crowd = Node3D.new()
	_crowd.name = "Crowd"
	add_child(_crowd)
	var props := PROPS_SCENE.instantiate() as Node3D
	var egg_mesh := (props.find_child("GSP_EggProjectile", true, false) as MeshInstance3D).mesh
	var shard_mesh := (props.find_child("GSP_ShellShard", true, false) as MeshInstance3D).mesh
	props.free()
	eggs = GoalStandEggs.new()
	add_child(eggs)
	eggs.setup(egg_mesh, shard_mesh, _material, crowd_seed + 7)
	_plan_crowd()


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func density() -> float:
	return 1.0 if quality == QualityRules.HIGH else (0.9 if quality == QualityRules.BALANCED else 0.62)


## Blender stand space (x, y, z) -> this node's local space.
static func stand_point(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


## World +X (P1's lane) is stand-local -X because the stand is turned around.
static func team_for_side(local_x: float) -> int:
	return 1 if local_x < 0.0 else 2


func _plan_crowd() -> void:
	var tiers: Array = _layout.get("tiers", [])
	for row in range(tiers.size()):
		var tier: Dictionary = tiers[row]
		for span: Array in tier.get("spans", []):
			var x0 := float(span[0]) + 0.35
			var x1 := float(span[1]) - 0.35
			var count := int(floor((x1 - x0) / SPACING)) + 1
			var step := (x1 - x0) / maxf(1.0, float(count - 1))
			var stagger := 0.25 * step if row % 2 == 1 else 0.0
			for index in range(count):
				var x := clampf(x0 + index * step + stagger + _rng.randf_range(-0.07, 0.07), x0 - 0.1, x1 + 0.1)
				var y := float(tier.stand_y) + _rng.randf_range(-0.07, 0.09)
				_slots.append({"row": row, "position": stand_point(x, y, float(tier.floor_z)), "x": x,
					"keep": _rng.randf() <= density()})
	# Roles are decided on the full seat map so every quality keeps the same cast.
	var by_side := {1: [], 2: []}
	for index in range(_slots.size()):
		by_side[team_for_side(float(_slots[index].x))].append(index)
	for team: int in [1, 2]:
		var side: Array = by_side[team]
		var front := side.filter(func(i: int) -> bool: return int(_slots[i].row) <= 1)
		var back := side.filter(func(i: int) -> bool: return int(_slots[i].row) >= 1)
		_assign(front, Kind.HOTHEAD, 3, team)
		_assign(back, Kind.SIGN, 2, team)
		_assign(side, Kind.FLAG, 2, team)
		_assign(side, Kind.FOAM, 2, team)
		_assign(side, Kind.DANCER, 5, 0)
	for slot: Dictionary in _slots:
		if not slot.has("kind"):
			slot.kind = Kind.FAN
			var majority := team_for_side(float(slot.x))
			var roll := _rng.randf()
			slot.team = 0 if roll < 0.10 else (majority if roll < 0.82 else 3 - majority)
		# Hotheads always appear so the verdict has egg throwers at every quality.
		if slot.kind == Kind.HOTHEAD:
			slot.keep = true


func _assign(candidates: Array, kind: int, amount: int, team: int) -> void:
	var free := candidates.filter(func(i: int) -> bool: return not _slots[i].has("kind"))
	for _n in range(amount):
		if free.is_empty():
			return
		var pick: int = free.pop_at(_rng.randi_range(0, free.size() - 1))
		_slots[pick].kind = kind
		_slots[pick].team = team


## Spawns a few spectators per call so the stand never hitches a frame.
func is_populated() -> bool:
	return _slots.is_empty()


func _spawn_some(amount: int) -> void:
	while amount > 0 and not _slots.is_empty():
		var slot: Dictionary = _slots.pop_front()
		if not slot.keep:
			continue
		spectators.append(_spawn(slot))
		amount -= 1


func _spawn(slot: Dictionary) -> Spectator:
	var s := Spectator.new()
	s.kind = int(slot.kind)
	s.team = int(slot.team)
	s.row = int(slot.row)
	s.root = Node3D.new()
	s.root.name = "Spectator%02d" % spectators.size()
	s.root.position = slot.position
	_crowd.add_child(s.root)
	var instance := SPECTATOR_SCENE.instantiate() as Node3D
	s.root.add_child(instance)
	s.ap = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	s.skeleton = instance.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	s.hand_bone = s.skeleton.find_bone("hand_r")
	s.ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_prepare_animations(s.ap)
	s.hair = _pick_hair(s)
	var wanted := ["SPEC_Body_" + s.hair]
	match s.kind:
		Kind.HOTHEAD:
			wanted += ["GSP_Carton", "GSP_Egg"]
		Kind.SIGN:
			var key := "P1" if s.team == 1 else "P2"
			wanted += ["GSP_Sign" + key, "GSP_SignStick" + key, "GSP_SignBoo", "GSP_SignStickBoo"]
		Kind.FLAG:
			wanted.append("GSP_Flag")
		Kind.FOAM:
			wanted.append("GSP_FoamFinger")
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not String(mesh.name) in wanted:
			mesh.queue_free()
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mesh.visibility_range_end = 260.0
		s.props[String(mesh.name)] = mesh
		if not String(mesh.name).begins_with("GSP_Sign") or String(mesh.name).begins_with("GSP_SignStick"):
			mesh.material_override = _material
			s.shaded.append(mesh)
	s.body = s.props["SPEC_Body_" + s.hair]
	_set_visible(s, "GSP_Egg", false)
	_set_visible(s, "GSP_SignBoo", false)
	_set_visible(s, "GSP_SignStickBoo", false)
	_paint(s)
	s.speed = _rng.randf_range(0.9, 1.12)
	s.idle_clip = &"SPEC_FoldArms" if s.kind == Kind.HOTHEAD else IDLE_CLIPS[_rng.randi_range(0, IDLE_CLIPS.size() - 1)]
	_play(s, s.idle_clip, 0.0)
	s.ap.seek(_rng.randf_range(0.0, s.ap.current_animation_length), true)
	s.next_change = _clock + _rng.randf_range(3.0, 9.0)
	return s


func _pick_hair(s: Spectator) -> String:
	if s.kind == Kind.HOTHEAD:
		return "Headband" if _rng.randf() < 0.6 else "Bald"
	if s.kind == Kind.DANCER:
		return ["Afro", "Long", "Bun", "Cap"][_rng.randi_range(0, 3)]
	return ["Short", "Short", "Long", "Cap", "Afro", "Bald", "Bun"][_rng.randi_range(0, 6)]


func _paint(s: Spectator) -> void:
	var shirts := P1_SHIRTS if s.team == 1 else (P2_SHIRTS if s.team == 2 else NEUTRAL_SHIRTS)
	var accent := P1_COLOR if s.team == 1 else (P2_COLOR if s.team == 2 else NEUTRAL_SHIRTS[_rng.randi_range(0, NEUTRAL_SHIRTS.size() - 1)])
	var hair := Color("#9a9a9a") if s.hair == "Bald" and _rng.randf() < 0.6 else HAIR_COLORS[_rng.randi_range(0, HAIR_COLORS.size() - 1)]
	var params := {
		"skin_color": SKINS[_rng.randi_range(0, SKINS.size() - 1)],
		"shirt_color": shirts[_rng.randi_range(0, shirts.size() - 1)],
		"pants_color": PANTS[_rng.randi_range(0, PANTS.size() - 1)],
		"hair_color": hair,
		"shoe_color": SHOES[_rng.randi_range(0, SHOES.size() - 1)],
		"accent_color": accent,
		"anger": 0.0,
	}
	for mesh: MeshInstance3D in s.shaded:
		for key: String in params:
			mesh.set_instance_shader_parameter(key, params[key])


func _prepare_animations(ap: AnimationPlayer) -> void:
	# The imported animations are shared by every spectator; set loop modes once.
	for clip_name: StringName in ap.get_animation_list():
		var animation := ap.get_animation(clip_name)
		var info: Dictionary = _clips.get(String(clip_name), {})
		var loop := bool(info.get("loop", true)) and not String(clip_name).begins_with("SPEC_Dance_")
		var mode := Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		if animation.loop_mode != mode:
			animation.loop_mode = mode


func _set_visible(s: Spectator, prop: String, value: bool) -> void:
	var mesh := s.props.get(prop) as MeshInstance3D
	if mesh != null:
		mesh.visible = value


func _play(s: Spectator, clip: StringName, blend: float = 0.25, restart: bool = false) -> void:
	if not s.ap.has_animation(clip):
		return
	if s.clip == clip and not restart:
		return
	s.clip = clip
	s.ap.speed_scale = 1.0 if clip == &"SPEC_Throw" else s.speed
	if restart:
		s.ap.stop()
		s.ap.play(clip, 0.0)
	else:
		s.ap.play(clip, blend)


func _clip_length(clip: StringName) -> float:
	return float((_clips.get(String(clip), {}) as Dictionary).get("seconds", 1.0))


# ------------------------------------------------------------------ per frame

## `director` is the ResultCeremonyDirector (egg target and ceremony clock).
func update_stand(delta: float, state: QuizGameState, director: Node, camera: Camera3D) -> void:
	var started_usec := Time.get_ticks_usec()
	_update(delta, state, director, camera)
	_update_usec = lerpf(_update_usec, float(Time.get_ticks_usec() - started_usec), 0.1)


func _update(delta: float, state: QuizGameState, director: Node, camera: Camera3D) -> void:
	_clock += delta
	_spawn_some(SPAWN_PER_FRAME)
	if state == null:
		return
	var distance := camera.global_position.distance_to(global_position) if is_instance_valid(camera) else 0.0
	var mood := _read_mood(state, director)
	_track_arrivals(state)
	if distance > ACTIVE_DISTANCE and not state.result_presentation_active:
		# A few hundred metres down the course the crowd is a frozen backdrop.
		_mood = mood
		return
	var target := _egg_target(director) if bool(mood.get("eggs", false)) else null
	var focus := _focus_point(state, target)
	for s: Spectator in spectators:
		_react(s, mood, target)
		_face(s, focus, target, delta)
		_update_anger(s, delta)
	_update_sounds(mood, state, distance)
	# Animation cost scales with distance (and LOW quality poses at 30 Hz);
	# far away the crowd freezes in pose.
	var step := 0.0
	if distance <= ACTIVE_DISTANCE:
		var interval := FAR_STEP if distance > FULL_RATE_DISTANCE else (LOW_STEP if quality == QualityRules.LOW else 0.0)
		_anim_accumulator += delta
		if _anim_accumulator >= interval:
			step = _anim_accumulator
			_anim_accumulator = 0.0
	if step > 0.0:
		for s: Spectator in spectators:
			s.ap.advance(step)
	for impact: Dictionary in eggs.update(delta, camera):
		if is_instance_valid(AudioManager) and AudioManager.has_method("play_crowd_cue"):
			AudioManager.play_crowd_cue(&"egg_splat", -3.0 if impact.hit else -8.0, _rng.randf_range(0.88, 1.15))
	if String(_mood.get("key", "")) == "verdict" and mood.key != "verdict":
		_reset_reactions()
	_mood = mood


func _read_mood(state: QuizGameState, director: Node) -> Dictionary:
	if state.result_presentation_active and director != null and director.has_method("result_elapsed"):
		var t: float = director.result_elapsed()
		if t >= Motion.VERDICT:
			return {"key": "verdict", "winner": state.result_winner, "eggs": true, "since": t - Motion.VERDICT}
		if t >= Motion.beat("climb"):
			return {"key": "nervous"}
		return {"key": "applause"}
	match state.game_state:
		Constants.STATE_GOAL_RACE:
			return {"key": "hype"}
		Constants.STATE_CLEAR:
			return {"key": "verdict", "winner": state.goal_winner, "eggs": false, "since": 0.0}
	return {"key": "idle"}


func _track_arrivals(state: QuizGameState) -> void:
	var mask := state.goal_reached_mask
	if mask == 0:
		_last_mask = 0
		return
	var fresh := mask & ~_last_mask
	_last_mask = mask
	if fresh == 0 or state.result_presentation_active:
		return
	_burst_team = 1 if fresh & 1 else 2
	_burst_until = _clock + 2.8
	_cue(StringName("cheer_%d_%d" % [_burst_team, int(_clock * 10.0)]), &"cheer", -4.0)


func _egg_target(director: Node) -> Node3D:
	if director != null and director.has_method("crowd_egg_target"):
		return director.crowd_egg_target() as Node3D
	return null


func _focus_point(state: QuizGameState, target: Node3D) -> Vector3:
	if is_instance_valid(target):
		return target.global_position
	var goal := state.get_local_result_goal_z() + QuizGameState.RESULT_WALK_FINISH_OFFSET - state.world_scroll_z
	return Vector3(0.0, StageConstants.FLOOR_TOP_Y + 1.5, goal)


func _react(s: Spectator, mood: Dictionary, target: Node3D) -> void:
	var key := String(mood.key)
	var bursting := _clock < _burst_until and key == "hype"
	if bursting:
		key = "burst%d" % _burst_team
	if key == "verdict":
		key += str(mood.get("winner", 0))
	if s.mood != key:
		# Everyone reacts, but not in lockstep.
		s.mood = key
		s.queued = _choose(s, key)
		s.queued_at = _clock + _rng.randf_range(0.04, 0.5)
		s.throw_started = -1.0
		if key.begins_with("verdict"):
			_on_verdict(s, int(mood.get("winner", 0)), target)
	if s.queued != &"" and _clock >= s.queued_at:
		_play(s, s.queued, 0.3)
		s.queued = &""
		s.next_change = _clock + _vary_after(s)
	if s.kind == Kind.HOTHEAD and s.throws_left > 0 and is_instance_valid(target):
		_update_thrower(s, target)
	elif s.queued == &"" and _clock >= s.next_change and s.throw_started < 0.0:
		_play(s, _choose(s, key), 0.35)
		s.next_change = _clock + _vary_after(s)


func _vary_after(s: Spectator) -> float:
	if s.clip in DANCES:
		return maxf(1.5, _clip_length(s.clip) / s.speed - 0.3)
	return _rng.randf_range(3.5, 8.0)


func _choose(s: Spectator, key: String) -> StringName:
	var pick := func(options: Array) -> StringName: return options[_rng.randi_range(0, options.size() - 1)]
	if s.kind == Kind.DANCER and key != "idle" and key != "nervous":
		return pick.call(DANCES)
	match key:
		"idle":
			return s.idle_clip if _rng.randf() < 0.7 else pick.call(IDLE_CLIPS)
		"hype":
			match s.kind:
				Kind.SIGN, Kind.FOAM: return &"SPEC_SignUp" if s.kind == Kind.SIGN else &"SPEC_Cheer"
				Kind.FLAG: return &"SPEC_Wave"
				Kind.HOTHEAD: return pick.call([&"SPEC_Shout", &"SPEC_FoldArms"])
			return pick.call([&"SPEC_Wave", &"SPEC_Clap", &"SPEC_Shout", &"SPEC_Anticipate", &"SPEC_Clap"])
		"applause":
			match s.kind:
				Kind.SIGN: return &"SPEC_SignUp"
				Kind.FLAG: return &"SPEC_Wave"
				Kind.HOTHEAD: return &"SPEC_FoldArms"
			return pick.call([&"SPEC_Clap", &"SPEC_Clap", &"SPEC_Wave", &"SPEC_Cheer"])
		"nervous":
			return &"SPEC_FoldArms" if s.kind == Kind.HOTHEAD else pick.call([&"SPEC_Anticipate", &"SPEC_Anticipate", &"SPEC_Nod"])
	if key.begins_with("burst"):
		var team := int(key.substr(5))
		if s.team == team:
			return &"SPEC_SignUp" if s.kind == Kind.SIGN else (&"SPEC_Wave" if s.kind == Kind.FLAG else &"SPEC_Cheer")
		return &"SPEC_Clap"
	if key.begins_with("verdict"):
		var winner := int(key.substr(7))
		var won := winner == 0 or s.team == winner or s.team == 0
		if s.kind == Kind.HOTHEAD:
			return pick.call([&"SPEC_Cheer", &"SPEC_PointLaugh"]) if won and winner != 0 else &"SPEC_Rage"
		if won:
			match s.kind:
				Kind.SIGN: return &"SPEC_SignUp"
				Kind.FLAG: return pick.call([&"SPEC_Wave", &"SPEC_Cheer"])
				Kind.FOAM: return &"SPEC_Cheer"
			if winner == 0:
				return pick.call([&"SPEC_Clap", &"SPEC_Cheer", &"SPEC_Nod"])
			return pick.call([&"SPEC_Cheer", &"SPEC_Cheer", &"SPEC_PointLaugh", &"SPEC_Wave", &"SPEC_Clap"])
		if s.kind == Kind.SIGN:
			return &"SPEC_SignUp"
		return pick.call([&"SPEC_Despair", &"SPEC_ShakeHead", &"SPEC_Despair", &"SPEC_FoldArms"])
	return s.idle_clip


func _on_verdict(s: Spectator, winner: int, target: Node3D) -> void:
	var lost := winner != 0 and s.team != 0 and s.team != winner
	if s.kind == Kind.SIGN and lost and not s.boo_sign:
		# The fan's board flips over: "ブーー！"
		s.boo_sign = true
		var key := "P1" if s.team == 1 else "P2"
		_set_visible(s, "GSP_Sign" + key, false)
		_set_visible(s, "GSP_SignStick" + key, false)
		_set_visible(s, "GSP_SignBoo", true)
		_set_visible(s, "GSP_SignStickBoo", true)
	if s.kind == Kind.HOTHEAD and (lost or winner == 0) and is_instance_valid(target):
		s.throws_left = 3 if winner != 0 else 2
		s.next_throw = _clock + _rng.randf_range(0.5, 1.6)


func _update_thrower(s: Spectator, target: Node3D) -> void:
	if s.throw_started >= 0.0:
		var t := _clock - s.throw_started
		if not s.released and t >= float(_clips.SPEC_Throw.get("release", 0.3)):
			s.released = true
			_set_visible(s, "GSP_Egg", false)
			_launch_egg(s, target)
		if t >= _clip_length(&"SPEC_Throw") - 0.05:
			s.throw_started = -1.0
			s.throws_left -= 1
			s.next_throw = _clock + _rng.randf_range(0.5, 1.3)
			_play(s, &"SPEC_Rage", 0.2)
		return
	if _clock >= s.next_throw and _egg_budget > 0 and s.queued == &"":
		_egg_budget -= 1
		s.throw_started = _clock
		s.released = false
		_set_visible(s, "GSP_Egg", true)
		_play(s, &"SPEC_Throw", 0.0, true)
	elif _egg_budget <= 0:
		s.throws_left = 0


func _launch_egg(s: Spectator, target: Node3D) -> void:
	var hand := s.skeleton.global_transform * s.skeleton.get_bone_global_pose(s.hand_bone)
	var start := hand * Vector3(0.0, 0.1, 0.0)
	var miss := _rng.randf() < MISS_CHANCE
	# The referee's rig origin is at his feet; the losers' spine is already chest high.
	var lift := 0.55 if String(target.name).contains("Referee") else 0.05
	var aim := target.global_position + Vector3(_rng.randf_range(-0.22, 0.22), _rng.randf_range(lift, lift + 0.4), _rng.randf_range(-0.15, 0.15))
	if miss:
		var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 0.3)).normalized()
		aim = Vector3(aim.x, StageConstants.FLOOR_TOP_Y, aim.z) + side * _rng.randf_range(0.9, 1.6)
	var flight := clampf(start.distance_to(aim) / EGG_SPEED, 0.8, 1.5)
	eggs.launch(start, aim, flight, target, miss)
	_cue(StringName("egg_throw_%d" % eggs.launched), &"egg_throw", -14.0)
	if eggs.launched == 1:
		_cue(&"voice_angry", &"voice_angry", -3.0)


func _face(s: Spectator, focus: Vector3, target: Node3D, delta: float) -> void:
	var aim := focus
	var limit := 0.45
	if s.kind == Kind.HOTHEAD and s.throws_left > 0 and is_instance_valid(target):
		aim = target.global_position
		limit = 1.0
	var local := _crowd.to_local(aim) - s.root.position
	var desired := clampf(atan2(local.x, local.z), -limit, limit)
	s.yaw = lerp_angle(s.yaw, desired, 1.0 - exp(-delta * 3.0))
	s.root.rotation.y = s.yaw


func _update_anger(s: Spectator, delta: float) -> void:
	var goal := 1.0 if s.clip in [&"SPEC_Rage", &"SPEC_Throw"] else 0.0
	s.anger = move_toward(s.anger, goal, delta * 1.6)
	if absf(s.anger - s.anger_sent) > 0.02:
		s.anger_sent = s.anger
		s.body.set_instance_shader_parameter("anger", s.anger)


# ------------------------------------------------------------------ sound

func _cue(id: StringName, cue: StringName, volume_db: float) -> void:
	if _cues.has(id):
		return
	_cues[id] = _clock
	if is_instance_valid(AudioManager) and AudioManager.has_method("play_crowd_cue"):
		AudioManager.play_crowd_cue(cue, volume_db)


func _update_sounds(mood: Dictionary, state: QuizGameState, distance: float) -> void:
	var key := String(mood.key)
	if key == "idle":
		if not _cues.is_empty() and _mood.get("key", "") != "idle":
			_cues.clear()
		return
	if distance > 90.0:
		return
	if key == "hype":
		_cue(&"hype", &"voice_hype", -5.0)
	elif key == "applause":
		if state.result_ceremony_elapsed >= QuizGameState.RESULT_ASSEMBLE_DURATION:
			_cue(&"applause", &"applause", -6.0)
	elif key == "verdict":
		var winner := int(mood.get("winner", 0))
		_cue(&"verdict_cheer", &"cheer", -3.0)
		if winner == 0:
			_cue(&"verdict_draw", &"voice_draw", -3.0)
		elif float(mood.get("since", 0.0)) >= 0.35:
			_cue(&"verdict_boo", &"boo", -6.0)


# ------------------------------------------------------------------ inspection

## A new race on the same course: boards flip back, eggs are restocked.
func _reset_reactions() -> void:
	clear_eggs()
	for s: Spectator in spectators:
		s.throws_left = 0
		s.throw_started = -1.0
		_set_visible(s, "GSP_Egg", false)
		if s.boo_sign:
			s.boo_sign = false
			var key := "P1" if s.team == 1 else "P2"
			_set_visible(s, "GSP_Sign" + key, true)
			_set_visible(s, "GSP_SignStick" + key, true)
			_set_visible(s, "GSP_SignBoo", false)
			_set_visible(s, "GSP_SignStickBoo", false)


func clear_eggs() -> void:
	_egg_budget = EGG_BUDGET
	if eggs != null:
		eggs.clear()


func get_debug_snapshot() -> Dictionary:
	var kinds := {}
	var clips := {}
	var boo_signs := 0
	var angry := 0
	for s: Spectator in spectators:
		kinds[Kind.keys()[s.kind]] = int(kinds.get(Kind.keys()[s.kind], 0)) + 1
		clips[String(s.clip)] = int(clips.get(String(s.clip), 0)) + 1
		boo_signs += 1 if s.boo_sign else 0
		angry += 1 if s.anger > 0.5 else 0
	return {"spectators": spectators.size(), "pending": _slots.size(), "kinds": kinds, "clips": clips,
		"mood": _mood.get("key", ""), "eggs_launched": eggs.launched if eggs else 0,
		"eggs_hit": eggs.hits if eggs else 0, "eggs_missed": eggs.misses if eggs else 0,
		"eggs_in_flight": eggs.in_flight() if eggs else 0, "boo_signs": boo_signs, "angry": angry,
		"world": global_position, "update_usec": _update_usec}
