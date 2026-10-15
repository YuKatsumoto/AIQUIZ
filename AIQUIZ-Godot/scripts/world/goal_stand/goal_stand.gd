class_name GoalStand
extends Node3D

## Finish-line grandstand at the far end of the conveyor (assets/goal_stand, built
## in Blender through the Higgsfield connector). Three standing tiers of block
## spectators react to the finish: team fans cheer or despair, hotheads pelt the
## loser with eggs, party people dance the game's own emotes, and three sign
## holders standing side by side flip their boards to "OH" "MY" "GOT" when their
## player loses.
##
## Blender builds the stand facing -Y (glTF +Z); this node turns it PI so the crowd
## looks back down the conveyor. Spectators live in the same stand space.
##
## Crowd extras (docs/crowd_extras.md): dozers who jolt awake, popcorn and hot dog
## eaters, a selfie taker, a binocular watcher, a cheer leader per side (megaphone
## or drum) who leads the chant, towel twirlers, two friends who high-five and sway
## arm in arm, a child on a parent's shoulders, two beer vendors walking the aisles
## and the mascot Hatena at the front. They follow CrowdCues: the countdown, the
## start, a wrong door or a fall, lost HP, the stadium wave as it crosses the
## stand, the chant and, after the verdict, the winner's dance in step with the
## winner.
## The structure is AIQUIZ STADIUM's harbour bridge house (aiquiz_stadium_goal_stand.glb:
## same tiers, aisles and GS_ScoreboardScreen LED face as the original goal_stand.glb).

const STAND_SCENE: PackedScene = preload("res://assets/aiquiz_stadium/aiquiz_stadium_goal_stand.glb")
const StadiumMaterials = preload("res://scripts/world/aiquiz_stadium/aiquiz_stadium_materials.gd")
const SPECTATOR_SCENE: PackedScene = preload("res://assets/goal_stand/goal_stand_spectator.glb")
const PROPS_SCENE: PackedScene = preload("res://assets/goal_stand/goal_stand_props.glb")
const SPECTATOR_SHADER: Shader = preload("res://shaders/goal_stand_spectator.gdshader")
const LED_SHADER: Shader = preload("res://shaders/goal_stand_scoreboard_led.gdshader")
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
## After the result screen opens (STATE_CLEAR) the match is written to the history; the
## scoreboard waits for that, but no longer than this (no reel, or a slow disk).
const PROGRAMME_WAIT_MAX := 6.0
const FULL_RATE_DISTANCE := 70.0
## Crowd poses run at 30 Hz up close and 10 Hz down the course, skinned in
## staggered groups so each frame only updates part of the stand.
const NEAR_STEP := 1.0 / 30.0
const FAR_STEP := 1.0 / 10.0
const ANIM_GROUPS := 3
const EGG_SPEED := 19.0
const MISS_CHANCE := 0.25
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)
## Rotating red beacons on the scoreboard's top edge while it shows "SUDDEN DEATH!"
## (the surface goes dark then, so the board and the beacons carry the moment).
const PATROL_COLOR := Color(1.0, 0.1, 0.05)
const PATROL_SPIN := TAU * 1.5
const PATROL_COUNT := 3
const PATROL_LIFT := 0.45
const LED_ENERGY := 2.2
const LED_ENERGY_SUDDEN_DEATH := 3.4
## Boards the losing side's sign row flips to, left to right on screen.
const WORD_SIGNS: Array[Texture2D] = [
	preload("res://assets/goal_stand/goal_stand_spectator_sign_oh.png"),
	preload("res://assets/goal_stand/goal_stand_spectator_sign_my.png"),
	preload("res://assets/goal_stand/goal_stand_spectator_sign_got.png"),
]

enum Kind { FAN, HOTHEAD, DANCER, SIGN, FLAG, FOAM, SLEEPER, EATER, SELFIE, BINOCULARS, LEADER, TOWEL, PAIR,
	CARRIER, KID, VENDOR }

const IDLE_CLIPS: Array[StringName] = [&"SPEC_Idle", &"SPEC_Idle", &"SPEC_Talk", &"SPEC_Phone", &"SPEC_Nod"]
const DANCES: Array[StringName] = [&"SPEC_Dance_YMCA", &"SPEC_Dance_Gangnam", &"SPEC_Dance_Silly",
	&"SPEC_Dance_HokeyPokey", &"SPEC_Dance_RunningMan", &"SPEC_Dance_WaveHipHop", &"SPEC_Dance_Swing",
	&"SPEC_DanceBounce", &"SPEC_Dance_StepHipHop", &"SPEC_Dance_HipHop", &"SPEC_Dance_HipHop2"]
## Props per personality (the towel fan carries both towels: one twirls, one rests
## round the neck).
const KIND_PROPS := {Kind.SELFIE: ["GSP_Phone"], Kind.BINOCULARS: ["GSP_Binoculars"], Kind.TOWEL: ["GSP_Towel", "GSP_TowelNeck"],
	Kind.VENDOR: ["GSP_Keg", "GSP_Cup"]}
## Seconds a woken dozer stays awake after the excitement.
const AWAKE_SECONDS := 18.0
## Synced moves (chant, winner's dance, pairs) re-seek when they drift this far.
const SYNC_TOLERANCE := 0.12
## Beer vendors walk the aisles (Blender x = ±6) between these depths, at this pace.
const VENDOR_Y := Vector2(0.45, 3.85)
const VENDOR_SPEED := 0.85
const TIER_DEPTH := 1.35
## The mascot stands at the front (Blender x, depth, floor), off the middle so
## it does not stack behind the referee on the goal line in the race camera.
const MASCOT_SPOT := Vector3(3.4, 0.42, 0.35)
## Pair clips (SPEC_HighFiveL/R, SPEC_ShoulderL/R) meet a neighbour this far away.
const PAIR_SPACING := 0.92
const HAIRS: Array[String] = ["Short", "Long", "Cap", "Afro", "Bald", "Bun", "Headband"]
## Fair skin tones only; shared with the side stands (SeatedSpectatorKit).
const SKINS: Array[Color] = [Color("#f2c9a5"), Color("#f6d5bd"), Color("#f8dcc8"), Color("#eec1a0"),
	Color("#f4cfb4"), Color("#fae3d3")]
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
	## A hothead pelting the loser (or the referee): throws until the verdict ends.
	var throwing := false
	var throw_started := -1.0
	var released := false
	var next_throw := 0.0
	var boo_sign := false
	var word := -1
	## Crowd extras.
	var prop_names: Array = []
	var pair_side := 0                 # +1 high-fives its left (+X) neighbour, -1 its right
	var partner: Spectator = null
	var kid: Spectator = null
	var awake_until := -1.0
	var wake_started := -1.0
	## A clock-synced move from the cues (wave, chant, winner's dance) or "".
	var overlay := &""
	var wave_played := -INF
	var joins_dance := false
	## Vendor walk: Blender depth along the aisle, direction, pause.
	var aisle_x := 0.0
	var walk_y := 0.0
	var walk_dir := 1.0
	var pause_until := 0.0


var spectators: Array[Spectator] = []
## Children on their parents' shoulders (posed under the carrier's neck bone).
var kids: Array[Spectator] = []
var mascot: StandMascot = null
var eggs: GoalStandEggs
var scoreboard: GoalStandScoreboard
var quality := "balanced"

var _layout := {}
var _clips := {}
var _material: ShaderMaterial
var _word_materials: Array[Material] = []
var _crowd: Node3D
var _structure: Node3D
var _slots: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
## Seconds the result screen (STATE_CLEAR of the finale) has been open.
var _clear_age := 0.0
var _anim_accumulators := PackedFloat32Array([0.0, NEAR_STEP / 3.0, NEAR_STEP * 2.0 / 3.0])
var _mood := {"key": "idle"}
var _burst_team := 0
var _burst_until := -1.0
var _last_mask := 0
var _update_usec := 0.0
## The crowd already started over for the verdict that came back from the sudden death.
var _sudden_death_refreshed := false
## The director's egg target was there last frame.
var _target_armed := false
var _cues: CrowdCues = null
## Carrier rest space -> the kid's root (goal_stand_clips.json "kid").
var _kid_seat := Vector3(0.0, 1.47, -0.19)
var _kid_scale := 0.62
var _led_material: ShaderMaterial
## {root, spinner, dome, phase} per beacon.
var _patrol_lamps: Array[Dictionary] = []
var _patrol_on := false
var _patrol_phase := 0.0


func setup(graphics_quality: String, crowd_seed: int = 0x51AD) -> void:
	name = "GoalStand"
	quality = QualityRules.normalize(graphics_quality)
	rotation.y = PI
	_rng.seed = crowd_seed
	_layout = _read_json(LAYOUT_PATH)
	var clip_meta := _read_json(CLIPS_PATH)
	_clips = clip_meta.get("clips", {})
	var kid: Dictionary = clip_meta.get("kid", {})
	var seat: Array = kid.get("seat", [])
	if seat.size() == 3:
		_kid_seat = Vector3(float(seat[0]), float(seat[1]), float(seat[2]))
		_kid_scale = float(kid.get("scale", _kid_scale))
	_material = ShaderMaterial.new()
	_material.shader = SPECTATOR_SHADER
	_structure = STAND_SCENE.instantiate() as Node3D
	_structure.name = "Structure"
	add_child(_structure)
	StadiumMaterials.apply(_structure)
	var shadows := QualityRules.is_at_least(quality, QualityRules.HIGH) and not QualityRules.is_mobile_target()
	for node: Node in _structure.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_install_scoreboard()
	_install_patrol_lamps()
	_crowd = Node3D.new()
	_crowd.name = "Crowd"
	add_child(_crowd)
	var props := PROPS_SCENE.instantiate() as Node3D
	var egg_mesh := (props.find_child("GSP_EggProjectile", true, false) as MeshInstance3D).mesh
	var shard_mesh := (props.find_child("GSP_ShellShard", true, false) as MeshInstance3D).mesh
	props.free()
	eggs = GoalStandEggs.new()
	add_child(eggs)
	eggs.setup(egg_mesh, shard_mesh, _material, crowd_seed + 7, quality)
	_plan_crowd()
	_install_mascot()


## Hatena cheers at the front of the stand, facing the course with the crowd.
func _install_mascot() -> void:
	mascot = StandMascot.new()
	mascot.name = "Mascot"
	_crowd.add_child(mascot)
	mascot.position = stand_point(MASCOT_SPOT.x, MASCOT_SPOT.y, MASCOT_SPOT.z)
	mascot.setup(quality)


## The LED face of the scoreboard cabinet (GS_Scoreboard in goal_stand.glb) shows
## the board's SubViewport through the LED shader.
func _install_scoreboard() -> void:
	scoreboard = GoalStandScoreboard.new()
	add_child(scoreboard)
	scoreboard.setup()
	var material := ShaderMaterial.new()
	material.resource_name = "GS_Scoreboard"
	material.shader = LED_SHADER
	material.set_shader_parameter("board", scoreboard.get_texture())
	material.set_shader_parameter("energy", LED_ENERGY)
	_led_material = material
	var level := 1
	for mip: Texture2D in scoreboard.get_mip_textures():
		material.set_shader_parameter("board_mip%d" % level, mip)
		level += 1
	for node: Node in _structure.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.get_surface_override_material_count()):
			var original := mesh.mesh.surface_get_material(surface)
			if original != null and original.resource_name == "GS_ScoreboardScreen":
				mesh.set_surface_override_material(surface, material)


## LED face bounds in stand space (empty AABB when the face is missing).
func _screen_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	for node: Node in _structure.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface)
			if original == null or original.resource_name != "GS_ScoreboardScreen":
				continue
			var to_stand := Transform3D.IDENTITY
			var walk: Node = mesh
			while walk != null and walk != self:
				if walk is Node3D:
					to_stand = (walk as Node3D).transform * to_stand
				walk = walk.get_parent()
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var p := to_stand * vertex
				if found:
					bounds = bounds.expand(p)
				else:
					bounds = AABB(p, Vector3.ZERO)
					found = true
	return bounds


## Three beacons along the top of the LED face: a dark base, a red glass dome and a
## reflector spinning a red spot inside it. Hidden until the board says "SUDDEN DEATH!".
func _install_patrol_lamps() -> void:
	var bounds := _screen_bounds()
	if bounds.size == Vector3.ZERO:
		return
	var along := Vector3.RIGHT if bounds.size.x >= bounds.size.z else Vector3.BACK
	var half := (bounds.size.x if along == Vector3.RIGHT else bounds.size.z) * 0.5
	var top := bounds.get_center() + Vector3(0.0, bounds.size.y * 0.5, 0.0)
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.34
	base_mesh.bottom_radius = 0.4
	base_mesh.height = 0.22
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.06, 0.06, 0.07)
	base_mat.roughness = 0.5
	base_mesh.material = base_mat
	var dome_mesh := CylinderMesh.new()
	dome_mesh.top_radius = 0.24
	dome_mesh.bottom_radius = 0.3
	dome_mesh.height = 0.55
	for index in range(PATROL_COUNT):
		var u := -1.0 + 2.0 * float(index) / float(PATROL_COUNT - 1)
		var root := Node3D.new()
		root.name = "PatrolLamp%d" % index
		root.position = top + along * (u * (half - 0.4)) + Vector3.UP * PATROL_LIFT * 0.5
		root.visible = false
		add_child(root)
		var base := MeshInstance3D.new()
		base.mesh = base_mesh
		base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(base)
		var dome_mat := StandardMaterial3D.new()
		dome_mat.albedo_color = Color(PATROL_COLOR, 0.85)
		dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dome_mat.emission_enabled = true
		dome_mat.emission = PATROL_COLOR
		dome_mat.emission_energy_multiplier = 3.0
		var dome := MeshInstance3D.new()
		dome.mesh = dome_mesh
		dome.material_override = dome_mat
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.position.y = 0.38
		root.add_child(dome)
		var spinner := Node3D.new()
		spinner.position.y = 0.38
		root.add_child(spinner)
		var spot := SpotLight3D.new()
		spot.light_color = PATROL_COLOR
		spot.light_energy = 14.0
		spot.spot_range = 28.0
		spot.spot_angle = 26.0
		spot.spot_attenuation = 1.1
		spot.shadow_enabled = false
		spot.light_volumetric_fog_energy = 2.5
		spot.rotation.x = deg_to_rad(-12.0)
		spinner.add_child(spot)
		var back := spot.duplicate() as SpotLight3D
		back.rotation.y = PI
		spinner.add_child(back)
		var glow := OmniLight3D.new()
		glow.light_color = PATROL_COLOR
		glow.light_energy = 2.0
		glow.omni_range = 4.0
		glow.shadow_enabled = false
		glow.position.y = 0.38
		root.add_child(glow)
		_patrol_lamps.append({"root": root, "spinner": spinner, "dome": dome_mat, "phase": 0.9 * float(index)})


## Beacons on and the LED pushed brighter while the board shows "SUDDEN DEATH!".
func _update_patrol(delta: float, state: QuizGameState) -> void:
	var on := GoalStandScoreboard.shows_sudden_death(state)
	if on != _patrol_on:
		_patrol_on = on
		for lamp: Dictionary in _patrol_lamps:
			(lamp.root as Node3D).visible = on
		if _led_material != null:
			_led_material.set_shader_parameter("energy", LED_ENERGY_SUDDEN_DEATH if on else LED_ENERGY)
	if not on:
		return
	_patrol_phase = fposmod(_patrol_phase + PATROL_SPIN * delta, TAU)
	for lamp: Dictionary in _patrol_lamps:
		var angle := _patrol_phase + float(lamp.phase)
		(lamp.spinner as Node3D).rotation.y = angle
		# The dome flares as a beam sweeps past the front.
		(lamp.dome as StandardMaterial3D).emission_energy_multiplier = 2.0 + 6.0 * pow(absf(cos(angle)), 6.0)


func scoreboard_installed() -> bool:
	for node: Node in _structure.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.get_surface_override_material_count()):
			var material := mesh.get_surface_override_material(surface)
			if material != null and material.resource_name == "GS_Scoreboard":
				return true
	return false


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func density() -> float:
	return 1.0 if QualityRules.is_at_least(quality, QualityRules.HIGH) else (0.9 if quality == QualityRules.BALANCED else 0.62)


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
				var keep := _rng.randf() <= density()
				if row == 0 and absf(x - MASCOT_SPOT.x) < 1.0:
					continue      # the mascot's spot
				_slots.append({"row": row, "position": stand_point(x, y, float(tier.floor_z)), "x": x, "y": y,
					"keep": keep})
	# Roles are decided on the full seat map so every quality keeps the same cast.
	var by_side := {1: [], 2: []}
	for index in range(_slots.size()):
		by_side[team_for_side(float(_slots[index].x))].append(index)
	for team: int in [1, 2]:
		var side: Array = by_side[team]
		var front := side.filter(func(i: int) -> bool: return int(_slots[i].row) <= 1)
		var back := side.filter(func(i: int) -> bool: return int(_slots[i].row) >= 1)
		_assign(front, Kind.HOTHEAD, 3, team)
		_assign_sign_row(back, team)
		_assign(side, Kind.FLAG, 2, team)
		_assign(side, Kind.FOAM, 2, team)
		_assign(side, Kind.DANCER, 5, 0)
		# Crowd extras: one cheer leader, a pair of friends and a parent with a child
		# on the shoulders (top tier, so nobody sits behind the child) per side.
		_assign(front, Kind.LEADER, 1, team)
		_assign_pair(side.filter(func(i: int) -> bool: return int(_slots[i].row) == 1), team)
		_assign(side.filter(func(i: int) -> bool: return int(_slots[i].row) == 2), Kind.CARRIER, 1, team)
		_assign(side, Kind.TOWEL, 2, team)
		_assign(side, Kind.SLEEPER, 2, 0)
		_assign(side, Kind.EATER, 3, 0)
		_assign(side, Kind.SELFIE, 1, 0)
		_assign(side, Kind.BINOCULARS, 1, 0)
	for slot: Dictionary in _slots:
		if not slot.has("kind"):
			slot.kind = Kind.FAN
			var majority := team_for_side(float(slot.x))
			var roll := _rng.randf()
			slot.team = 0 if roll < 0.10 else (majority if roll < 0.82 else 3 - majority)
		# Hotheads always appear so the verdict has egg throwers at every quality,
		# and the sign row always spells the whole phrase. The leaders, the pairs
		# and the shoulder ride stay too: the chant and the extras need them.
		if slot.kind in [Kind.HOTHEAD, Kind.SIGN, Kind.LEADER, Kind.PAIR, Kind.CARRIER]:
			slot.keep = true
	# Two beer vendors walk the aisles.
	for aisle: float in _layout.get("aisles", []):
		var walk := _rng.randf_range(VENDOR_Y.x, VENDOR_Y.y)
		_slots.append({"row": 0, "position": stand_point(aisle, walk, _aisle_floor(walk)), "x": aisle, "y": walk,
			"kind": Kind.VENDOR, "team": 0, "keep": true})


## Two neighbours on one tier and span, set exactly SPACING apart: the left one
## (smaller x, its left hand towards +X) high-fives and hugs the right one.
func _assign_pair(candidates: Array, team: int) -> void:
	var runs: Array = []
	for i: int in candidates:
		var j := i + 1
		if j >= _slots.size() or not candidates.has(j) or _slots[i].has("kind") or _slots[j].has("kind"):
			continue
		if int(_slots[j].row) != int(_slots[i].row) or absf(float(_slots[j].x) - float(_slots[i].x)) > SPACING * 1.5:
			continue
		runs.append([i, j])
	if runs.is_empty():
		return
	var pick: Array = runs[_rng.randi_range(0, runs.size() - 1)]
	var a: Dictionary = _slots[pick[0]]
	var b: Dictionary = _slots[pick[1]]
	var mid := (float(a.x) + float(b.x)) * 0.5
	var y := (float(a.y) + float(b.y)) * 0.5
	var floor_z := float((_layout.tiers[int(a.row)] as Dictionary).floor_z)
	for k: int in range(2):
		var slot: Dictionary = a if k == 0 else b
		slot.kind = Kind.PAIR
		slot.team = team
		slot.x = mid + (-0.5 if k == 0 else 0.5) * PAIR_SPACING
		slot.y = y
		slot.position = stand_point(float(slot.x), y, floor_z)
		slot.pair_side = 1 if k == 0 else -1
		slot.pair_id = int(pick[0])


## The aisle's step under Blender depth `y`: the tier floors, eased over a step.
func _aisle_floor(y: float) -> float:
	var tiers: Array = _layout.get("tiers", [])
	if tiers.is_empty():
		return 0.35
	var front := float(_layout.get("front_y", 0.0))
	var height := float((tiers[0] as Dictionary).floor_z)
	for index: int in range(1, tiers.size()):
		var edge := front + TIER_DEPTH * index
		var lift := float((tiers[index] as Dictionary).floor_z) - float((tiers[index - 1] as Dictionary).floor_z)
		height += lift * smoothstep(edge - 0.18, edge + 0.18, y)
	return height


func _assign(candidates: Array, kind: int, amount: int, team: int) -> void:
	var free := candidates.filter(func(i: int) -> bool: return not _slots[i].has("kind"))
	for _n in range(amount):
		if free.is_empty():
			return
		var pick: int = free.pop_at(_rng.randi_range(0, free.size() - 1))
		_slots[pick].kind = kind
		_slots[pick].team = team


## Three neighbours on one tier hold the signs; on a loss their boards read
## "OH" "MY" "GOT". Screen left is stand-local -X (the stand is turned around).
func _assign_sign_row(candidates: Array, team: int) -> void:
	var runs: Array = []
	for i: int in candidates:
		var row := [i, i + 1, i + 2]
		var free := true
		for j: int in row:
			# Consecutive slots on one span of one tier are neighbours.
			free = free and j < _slots.size() and candidates.has(j) and not _slots[j].has("kind") \
				and int(_slots[j].row) == int(_slots[i].row) \
				and absf(float(_slots[j].x) - float(_slots[i].x)) <= SPACING * (j - i) * 1.5
		if free:
			runs.append(row)
	if runs.is_empty():
		return
	var pick: Array = runs[_rng.randi_range(0, runs.size() - 1)]
	for word in range(pick.size()):
		_slots[pick[word]].kind = Kind.SIGN
		_slots[pick[word]].team = team
		_slots[pick[word]].word = word


## Spawns a few spectators per call so the stand never hitches a frame.
func is_populated() -> bool:
	return _slots.is_empty()


func _spawn_some(amount: int) -> void:
	while amount > 0 and not _slots.is_empty():
		var slot: Dictionary = _slots.pop_front()
		if not slot.keep:
			continue
		var s := _spawn(slot)
		spectators.append(s)
		if slot.has("pair_id"):
			var partner: Spectator = _pairs_pending.get(slot.pair_id)
			if partner == null:
				_pairs_pending[slot.pair_id] = s
			else:
				_pairs_pending.erase(slot.pair_id)
				s.partner = partner
				partner.partner = s
		if s.kind == Kind.CARRIER:
			s.kid = _spawn_kid(s)
		amount -= 1


var _pairs_pending := {}


func _spawn(slot: Dictionary, parent: Node3D = null) -> Spectator:
	var s := Spectator.new()
	s.kind = int(slot.kind)
	s.team = int(slot.team)
	s.row = int(slot.row)
	s.word = int(slot.get("word", -1))
	s.pair_side = int(slot.get("pair_side", 0))
	s.root = Node3D.new()
	s.root.name = "Spectator%02d" % spectators.size() if s.kind != Kind.KID else "Kid"
	(parent if parent != null else _crowd).add_child(s.root)
	if slot.has("transform"):
		s.root.transform = slot.transform
	else:
		s.root.position = slot.position
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
		Kind.EATER:
			wanted.append("GSP_Popcorn" if _rng.randf() < 0.6 else "GSP_HotDog")
		Kind.LEADER:
			wanted.append("GSP_Megaphone" if s.team == 1 else "GSP_Drum")
		_:
			wanted += KIND_PROPS.get(s.kind, [])
	s.prop_names = wanted.slice(1)
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
		else:
			_sharpen_sign(mesh)
	if s.word >= 0 and s.props.has("GSP_SignBoo"):
		var board := s.props["GSP_SignBoo"] as MeshInstance3D
		board.material_override = _word_material(board, s.word)
	s.body = s.props["SPEC_Body_" + s.hair]
	s.body.mesh = SeatedSpectatorKit.fixed_body(s.body.mesh, s.body.skin)
	_set_visible(s, "GSP_Egg", false)
	_set_visible(s, "GSP_SignBoo", false)
	_set_visible(s, "GSP_SignStickBoo", false)
	_set_visible(s, "GSP_Towel", false)
	_paint(s)
	s.speed = _rng.randf_range(0.9, 1.12)
	s.joins_dance = s.team != 0 and _rng.randf() < 0.38
	s.idle_clip = &"SPEC_FoldArms" if s.kind == Kind.HOTHEAD else IDLE_CLIPS[_rng.randi_range(0, IDLE_CLIPS.size() - 1)]
	match s.kind:
		Kind.SLEEPER: s.idle_clip = &"SPEC_Doze"
		Kind.EATER: s.idle_clip = &"SPEC_Eat"
		Kind.BINOCULARS: s.idle_clip = &"SPEC_Binoculars"
		Kind.CARRIER: s.idle_clip = &"SPEC_CarryKid"
		Kind.KID: s.idle_clip = &"SPEC_KidSit"
		Kind.VENDOR: s.idle_clip = &"SPEC_VendorWalk"
		Kind.LEADER: s.idle_clip = &"SPEC_Idle"
	if s.kind == Kind.VENDOR:
		s.aisle_x = float(slot.x)
		s.walk_y = float(slot.y)
		s.walk_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	if s.kind == Kind.PAIR:
		# Partners move as one: same pace, facing straight ahead.
		s.speed = 1.0
	_play(s, s.idle_clip, 0.0)
	s.ap.seek(_rng.randf_range(0.0, s.ap.current_animation_length), true)
	s.next_change = _clock + _rng.randf_range(3.0, 9.0)
	return s


## A child on the carrier's shoulders: a small spectator under a BoneAttachment3D
## on the carrier's neck, placed like a vertex skinned to that bone (the same seat
## Blender's preview uses: author_crowd_extras.KID_SEAT).
func _spawn_kid(carrier: Spectator) -> Spectator:
	var neck := carrier.skeleton.find_bone("neck_01")
	if neck < 0:
		return null
	var attach := BoneAttachment3D.new()
	attach.name = "KidSeat"
	attach.bone_name = "neck_01"
	carrier.skeleton.add_child(attach)
	var rest := carrier.skeleton.get_bone_global_rest(neck)
	var seat := Transform3D(Basis.from_scale(Vector3.ONE * _kid_scale), _kid_seat)
	var kid := _spawn({"kind": Kind.KID, "team": carrier.team, "row": carrier.row, "transform": rest.affine_inverse() * seat}, attach)
	kid.speed = 1.0
	kid.next_change = _clock + _rng.randf_range(2.0, 5.0)
	kids.append(kid)
	return kid


## Sign lettering is read at a slant from the lanes. The imported picture material
## is shared, so switching it to anisotropic filtering once covers every board.
static func _sharpen_sign(board: MeshInstance3D) -> void:
	if board.mesh == null:
		return
	var picture := board.mesh.surface_get_material(0) as BaseMaterial3D
	if picture != null:
		picture.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


## The flip-side board keeps the imported sign material; only its picture changes.
func _word_material(board: MeshInstance3D, word: int) -> Material:
	if _word_materials.is_empty():
		var source := board.mesh.surface_get_material(0)
		for texture: Texture2D in WORD_SIGNS:
			var material := (source.duplicate() if source is BaseMaterial3D else StandardMaterial3D.new()) as BaseMaterial3D
			material.albedo_texture = texture
			_word_materials.append(material)
	return _word_materials[word]


func _pick_hair(s: Spectator) -> String:
	if s.kind == Kind.HOTHEAD:
		return "Headband" if _rng.randf() < 0.6 else "Bald"
	if s.kind == Kind.LEADER:
		return "Headband"
	if s.kind == Kind.VENDOR:
		return "Cap"
	if s.kind == Kind.KID:
		return ["Bun", "Short", "Cap", "Afro"][_rng.randi_range(0, 3)]
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
		# Dances end so a new emote is picked; the winner's dance keeps looping
		# because _play_synced restarts it on the dance clock.
		var loop := bool(info.get("loop", true)) and not String(clip_name).begins_with("SPEC_Dance_")
		var mode := Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		if animation.loop_mode != mode:
			animation.loop_mode = mode


func _set_visible(s: Spectator, prop: String, value: bool) -> void:
	var mesh := s.props.get(prop) as MeshInstance3D
	if mesh != null:
		mesh.visible = value


func _play(s: Spectator, clip: StringName, blend: float = 0.25, restart: bool = false, synced: bool = false) -> void:
	if not s.ap.has_animation(clip):
		return
	if s.clip == clip and not restart:
		return
	s.clip = clip
	# Clock-synced and one-shot moves run at real speed; the rest at the spectator's pace.
	var real_speed := synced or clip in [&"SPEC_Throw", &"SPEC_StandWave", &"SPEC_WakeUp"]
	s.ap.speed_scale = 1.0 if real_speed else s.speed
	if restart:
		s.ap.stop()
		s.ap.play(clip, 0.0)
	else:
		s.ap.play(clip, blend)
	if s.props.has("GSP_Towel"):
		# The towel twirls in the hand, otherwise it rests round the neck.
		_set_visible(s, "GSP_Towel", clip == &"SPEC_TowelSpin")
		_set_visible(s, "GSP_TowelNeck", clip != &"SPEC_TowelSpin")


## Plays `clip` on a shared clock (`time` seconds into it): starts it there and
## re-seeks whenever the spectator drifts off the beat.
func _play_synced(s: Spectator, clip: StringName, time: float) -> void:
	if not s.ap.has_animation(clip):
		return
	var length := s.ap.get_animation(clip).length
	if length <= 0.0:
		return
	var at := fposmod(time, length)
	if s.clip != clip or not s.ap.is_playing():
		_play(s, clip, 0.2, s.clip == clip, true)
		s.ap.seek(at, true)
		return
	var drift := absf(s.ap.current_animation_position - at)
	if drift > SYNC_TOLERANCE and drift < length - SYNC_TOLERANCE:
		s.ap.seek(at, true)


func _clip_length(clip: StringName) -> float:
	return float((_clips.get(String(clip), {}) as Dictionary).get("seconds", 1.0))


# ------------------------------------------------------------------ per frame

## `director` is the ResultCeremonyDirector (egg target and ceremony clock).
## `reel_ready` is true when the match just played is on disk (MatchReel.is_ready, or
## there is no reel): the scoreboard then hands over to the AIQUIZ VISION programme.
## `cues` are the crowd's cues (wave, chant, the winner's dance, game events).
func update_stand(delta: float, state: QuizGameState, director: Node, camera: Camera3D,
		reel_ready: bool = true, cues: CrowdCues = null) -> void:
	var started_usec := Time.get_ticks_usec()
	_cues = cues
	_update(delta, state, director, camera, reel_ready)
	_update_usec = lerpf(_update_usec, float(Time.get_ticks_usec() - started_usec), 0.1)


func _update(delta: float, state: QuizGameState, director: Node, camera: Camera3D, reel_ready: bool) -> void:
	_clock += delta
	_spawn_some(SPAWN_PER_FRAME)
	if state == null:
		return
	var distance := camera.global_position.distance_to(global_position) if is_instance_valid(camera) else 0.0
	var mood := _read_mood(state, director)
	# The board shows the winner's cut-in from the moment the verdict "WIN" is out.
	var verdict_winner := int(mood.get("winner", 0)) if mood.key == "verdict" else -1
	# Only the local finale (result_presentation_active) plays the programme: online,
	# tutorial and replay clears keep the cut-in.
	var on_result_screen := state.result_presentation_active and state.game_state == Constants.STATE_CLEAR
	_clear_age = _clear_age + delta if on_result_screen else 0.0
	var programme_ready := on_result_screen and (reel_ready or _clear_age > PROGRAMME_WAIT_MAX)
	scoreboard.sync(state, _clock, distance <= ACTIVE_DISTANCE, verdict_winner, programme_ready)
	_update_patrol(delta, state)
	_track_arrivals(state)
	if distance > ACTIVE_DISTANCE and not state.result_presentation_active:
		# A few hundred metres down the course the crowd is a frozen backdrop.
		_mood = mood
		return
	_refresh_after_sudden_death(state, mood)
	var target := _egg_target(director) if bool(mood.get("eggs", false)) else null
	_arm_waiting_throwers(is_instance_valid(target))
	var focus := _focus_point(state, target)
	for s: Spectator in spectators:
		if s.kind == Kind.VENDOR:
			_update_vendor(s, delta)
			continue
		_react(s, mood, target)
		_face(s, focus, target, delta)
		_update_anger(s, delta)
	for kid: Spectator in kids:
		_react(kid, mood, target)
	if mascot != null:
		var wave_since := -1.0
		if _cues != null and _cues.wave_time() >= 0.0:
			wave_since = _cues.wave_time() - _cues.wave_arrival_goal_stand(mascot.global_position.x)
		mascot.follow(_cues, delta, wave_since, distance)
	# Animation cost scales with distance; far away the crowd freezes in pose.
	if distance <= ACTIVE_DISTANCE:
		var interval := FAR_STEP if distance > FULL_RATE_DISTANCE else NEAR_STEP
		for group: int in range(ANIM_GROUPS):
			_anim_accumulators[group] += delta
			if _anim_accumulators[group] < interval:
				continue
			var step := _anim_accumulators[group]
			_anim_accumulators[group] = 0.0
			for index: int in range(group, spectators.size(), ANIM_GROUPS):
				spectators[index].ap.advance(step)
			for index: int in range(group, kids.size(), ANIM_GROUPS):
				kids[index].ap.advance(step)
	eggs.update(delta, camera)
	if String(_mood.get("key", "")) == "verdict" and mood.key != "verdict":
		_reset_reactions()
	_mood = mood


## What the side stands should do right now (GrandstandCrowd.follow_reaction):
## cheer with a player's fans when that player reaches the goal, and follow the
## verdict (winner 0 = draw, everyone cheers).
func side_crowd_reaction() -> Dictionary:
	if _clock < _burst_until:
		return {"amount": 1.0, "team": _burst_team, "verdict": false}
	if String(_mood.get("key", "")) == "verdict":
		return {"amount": 1.0, "team": int(_mood.get("winner", 0)), "verdict": true}
	return {"amount": 0.0}


func _read_mood(state: QuizGameState, director: Node) -> Dictionary:
	if state.result_presentation_active and director != null and director.has_method("result_elapsed"):
		var t: float = director.result_elapsed()
		if t >= Motion.VERDICT:
			return {"key": "verdict", "winner": state.result_winner, "eggs": true}
		if t >= Motion.beat("climb"):
			return {"key": "nervous"}
		return {"key": "applause"}
	match state.game_state:
		Constants.STATE_GOAL_RACE:
			return {"key": "hype"}
		Constants.STATE_CLEAR:
			return {"key": "verdict", "winner": state.goal_winner, "eggs": false}
	# The game's moments during play (CrowdCues): countdown, start, a miss, lost HP.
	if _cues != null and _cues.cue_weight() > 0.3:
		match _cues.cue:
			CrowdCues.Cue.COUNTDOWN:
				return {"key": "countdown"}
			CrowdCues.Cue.START:
				return {"key": "start"}
			CrowdCues.Cue.MISS:
				return {"key": "miss%d" % _cues.cue_team}
			CrowdCues.Cue.HURT:
				return {"key": "hurt%d" % _cues.cue_team}
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
		if s.kind == Kind.SLEEPER and _exciting(key) and s.clip == &"SPEC_Doze":
			# Jolted awake; stays up for a while after the excitement.
			s.queued = &"SPEC_WakeUp"
			s.wake_started = _clock
		else:
			s.queued = _choose(s, key)
		if s.kind == Kind.SLEEPER and _exciting(key):
			s.awake_until = _clock + AWAKE_SECONDS
		s.queued_at = _clock + _rng.randf_range(0.04, 0.5)
		s.throw_started = -1.0
		if key.begins_with("verdict"):
			_on_verdict(s, int(mood.get("winner", 0)), bool(mood.get("eggs", false)))
	# The cues' synced moves (the wave, the chant, the winner's dance) come first.
	var overlay := _overlay_for(s)
	if not overlay.is_empty():
		s.overlay = overlay.clip
		_play_synced(s, overlay.clip, float(overlay.time))
		return
	if s.overlay != &"":
		s.overlay = &""
		s.next_change = _clock
	if s.queued != &"" and _clock >= s.queued_at:
		_play(s, s.queued, 0.3, s.queued == &"SPEC_WakeUp")
		s.queued = &""
		s.next_change = _clock + (1.2 if s.clip == &"SPEC_WakeUp" else _vary_after(s))
	if s.kind == Kind.HOTHEAD and s.throwing and is_instance_valid(target):
		_update_thrower(s, target)
	elif s.queued == &"" and _clock >= s.next_change and s.throw_started < 0.0:
		var next := _choose(s, key)
		if s.kind == Kind.PAIR and next in PAIR_CLIPS:
			# Both friends on the stand's clock, so their hands and sway meet.
			_play_synced(s, next, _clock)
		else:
			_play(s, next, 0.35)
		s.next_change = _clock + _vary_after(s)
	elif s.kind == Kind.PAIR and s.clip in PAIR_CLIPS:
		_play_synced(s, s.clip, _clock)


const PAIR_CLIPS: Array[StringName] = [&"SPEC_HighFiveL", &"SPEC_HighFiveR", &"SPEC_ShoulderL", &"SPEC_ShoulderR"]


## Keys that wake a dozer.
static func _exciting(key: String) -> bool:
	return key != "idle" and key != "countdown" and not key.begins_with("hurt")


## The cues' clock-synced move for `s`, or {}: the stadium wave crossing the stand
## (dozers sleep through it), the winner's dance (party people and some of the
## winner's fans), the chant (fans clap, leaders drum or shout, friends sway).
func _overlay_for(s: Spectator) -> Dictionary:
	if _cues == null or s.kind in [Kind.VENDOR, Kind.KID, Kind.CARRIER] or s.throwing:
		return {}
	var wave := _cues.wave_time()
	if wave >= 0.0 and s.kind != Kind.SLEEPER:
		var since := wave - _cues.wave_arrival_goal_stand(s.root.global_position.x)
		if since >= 0.0 and since < _clip_length(&"SPEC_StandWave"):
			return {"clip": &"SPEC_StandWave", "time": since}
	if _cues.sync_weight > 0.3 and s.kind not in [Kind.HOTHEAD, Kind.SIGN, Kind.PAIR]:
		var side := team_for_side(s.root.position.x)
		var winner := _cues.sync_team
		var joins := s.kind == Kind.DANCER or (s.joins_dance and s.team != 0 and (winner == 0 or s.team == winner))
		if joins:
			var clip: StringName = _cues.sync_clips[winner if winner != 0 else side]
			if s.ap.has_animation(clip):
				return {"clip": clip, "time": CrowdCues.dance_time(clip, _cues.sync_elapsed)}
	if _cues.chant_weight() > 0.3 and s.team != 0 and (_cues.chant_team == 0 or s.team == _cues.chant_team):
		var beat := _cues.chant_time()
		match s.kind:
			Kind.LEADER:
				return {"clip": &"SPEC_Megaphone" if s.props.has("GSP_Megaphone") else &"SPEC_Drum", "time": beat}
			Kind.PAIR:
				return {"clip": &"SPEC_ShoulderL" if s.pair_side > 0 else &"SPEC_ShoulderR", "time": beat}
			Kind.FAN, Kind.TOWEL, Kind.FOAM:
				return {"clip": &"SPEC_ChantClap", "time": beat}
	return {}


## Beer vendors climb and descend their aisle, stopping now and then to call out.
func _update_vendor(s: Spectator, delta: float) -> void:
	if _clock < s.pause_until:
		_play(s, &"SPEC_VendorCall", 0.3)
		s.yaw = lerp_angle(s.yaw, 0.0, 1.0 - exp(-delta * 4.0))
	else:
		_play(s, &"SPEC_VendorWalk", 0.3)
		s.walk_y += s.walk_dir * VENDOR_SPEED * delta
		if s.walk_y > VENDOR_Y.y or s.walk_y < VENDOR_Y.x:
			s.walk_y = clampf(s.walk_y, VENDOR_Y.x, VENDOR_Y.y)
			s.walk_dir = -s.walk_dir
			s.pause_until = _clock + _rng.randf_range(2.5, 4.5)
		elif _rng.randf() < delta * 0.08:
			s.pause_until = _clock + _rng.randf_range(2.0, 3.5)
		# Up the aisle is the stand's -Z (Blender +Y): face the way the vendor walks.
		var heading := PI if s.walk_dir > 0.0 else 0.0
		s.yaw = lerp_angle(s.yaw, heading, 1.0 - exp(-delta * 5.0))
	s.root.position = stand_point(s.aisle_x, s.walk_y, _aisle_floor(s.walk_y))
	s.root.rotation.y = s.yaw


func _vary_after(s: Spectator) -> float:
	if s.clip in DANCES:
		return maxf(1.5, _clip_length(s.clip) / s.speed - 0.3)
	return _rng.randf_range(3.5, 8.0)


func _choose(s: Spectator, key: String) -> StringName:
	var pick := func(options: Array) -> StringName: return options[_rng.randi_range(0, options.size() - 1)]
	var extra := _choose_extra(s, key, pick)
	if extra != &"":
		return extra
	var calm_key := key == "idle" or key == "nervous" or key == "countdown" or key.begins_with("hurt") or key.begins_with("miss")
	if s.kind == Kind.DANCER and not calm_key:
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
		"countdown":
			match s.kind:
				Kind.SIGN: return &"SPEC_SignUp"
				Kind.FLAG: return &"SPEC_Wave"
				Kind.HOTHEAD: return &"SPEC_FoldArms"
			return &"SPEC_Anticipate"
		"start":
			match s.kind:
				Kind.SIGN: return &"SPEC_SignUp"
				Kind.FLAG: return &"SPEC_Wave"
			return pick.call([&"SPEC_Cheer", &"SPEC_Cheer", &"SPEC_Clap"])
	if key.begins_with("miss"):
		var player := int(key.substr(4))
		if s.team == player:
			return &"SPEC_SignUp" if s.kind == Kind.SIGN else pick.call([&"SPEC_Despair", &"SPEC_ShakeHead"])
		if s.team != 0 and _cues != null and _cues.two_players:
			return &"SPEC_SignUp" if s.kind == Kind.SIGN else &"SPEC_PointLaugh"
		return pick.call([&"SPEC_Gasp", &"SPEC_ShakeHead"])
	if key.begins_with("hurt"):
		if s.team == int(key.substr(4)) and s.kind != Kind.SIGN:
			return &"SPEC_ShakeHead"
		return _choose(s, "idle")
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


## The personalities' own choices (crowd extras), or &"" for the shared rules.
func _choose_extra(s: Spectator, key: String, pick: Callable) -> StringName:
	var verdict_for := int(key.substr(7)) if key.begins_with("verdict") else -1
	var cheering := key == "start" or key == "hype" or key == "applause" \
		or (key.begins_with("burst") and int(key.substr(5)) == s.team) \
		or (verdict_for == 0 or (verdict_for > 0 and verdict_for == s.team))
	var lost := verdict_for > 0 and s.team != 0 and verdict_for != s.team
	var shocked := key.begins_with("miss")
	match s.kind:
		Kind.CARRIER:
			return &"SPEC_CarryKid"
		Kind.KID:
			return &"SPEC_KidRide" if cheering or key.begins_with("burst") else &"SPEC_KidSit"
		Kind.VENDOR:
			return &"SPEC_VendorWalk"
		Kind.SLEEPER:
			if not _exciting(key) and _clock >= s.awake_until:
				return &"SPEC_Doze"
			return &"SPEC_Gasp" if shocked else &""
		Kind.EATER:
			if shocked:
				return &"SPEC_Gasp"
			if key == "start" or key.begins_with("burst"):
				return &"SPEC_Cheer"
			if verdict_for >= 0:
				return &"SPEC_Clap"
			return &"SPEC_Eat"
		Kind.SELFIE:
			if shocked:
				return &"SPEC_Gasp"
			if cheering or key.begins_with("burst") or verdict_for >= 0:
				return &"SPEC_Selfie"
			if key == "idle":
				return &"SPEC_Selfie" if _rng.randf() < 0.3 else pick.call([&"SPEC_Idle", &"SPEC_Phone", &"SPEC_Talk"])
		Kind.BINOCULARS:
			if shocked:
				return &"SPEC_Gasp"
			if key == "start" or key.begins_with("burst") or verdict_for >= 0:
				return &"SPEC_Clap"
			return &"SPEC_Binoculars"
		Kind.LEADER:
			var lead := &"SPEC_Megaphone" if s.props.has("GSP_Megaphone") else &"SPEC_Drum"
			if lost:
				return &"SPEC_Despair"
			if shocked:
				return lead if int(key.substr(4)) != s.team else &"SPEC_ShakeHead"
			if cheering or key == "countdown" or key == "nervous":
				return lead
			if key == "idle":
				return lead if _rng.randf() < 0.4 else &"SPEC_Idle"
		Kind.TOWEL:
			if cheering and key != "applause":
				return &"SPEC_TowelSpin"
		Kind.PAIR:
			if cheering and key != "applause":
				return &"SPEC_HighFiveL" if s.pair_side > 0 else &"SPEC_HighFiveR"
			if key == "nervous" or key == "applause":
				return &"SPEC_ShoulderL" if s.pair_side > 0 else &"SPEC_ShoulderR"
	return &""


## `eggs`: the finale's verdict, where hotheads throw. They wait for the director's
## egg target (it can take a moment, e.g. back from the sudden death) before the first.
func _on_verdict(s: Spectator, winner: int, eggs: bool) -> void:
	var lost := winner != 0 and s.team != 0 and s.team != winner
	if s.kind == Kind.SIGN and lost and not s.boo_sign:
		# The fan's board flips over: "OH" "MY" "GOT" along the sign row.
		s.boo_sign = true
		var key := "P1" if s.team == 1 else "P2"
		_set_visible(s, "GSP_Sign" + key, false)
		_set_visible(s, "GSP_SignStick" + key, false)
		_set_visible(s, "GSP_SignBoo", true)
		_set_visible(s, "GSP_SignStickBoo", true)
	if s.kind == Kind.HOTHEAD and (lost or winner == 0) and eggs:
		s.throwing = true
		s.next_throw = _clock + _rng.randf_range(0.5, 1.6)


## Hotheads that had their verdict before the egg target existed start throwing,
## staggered, from the moment it shows up.
func _arm_waiting_throwers(armed: bool) -> void:
	if armed and not _target_armed:
		for s: Spectator in spectators:
			if s.kind == Kind.HOTHEAD and s.throwing and s.throw_started < 0.0:
				s.next_throw = maxf(s.next_throw, _clock + _rng.randf_range(0.4, 1.3))
	_target_armed = armed


## Back from the sudden death the verdict is out again, now with a winner
## (docs/sudden_death_underground.md 2.3): the crowd starts over as for a fresh
## verdict. Boards flip back and old eggs are cleared, and every spectator
## reacts to the new verdict.
func _refresh_after_sudden_death(state: QuizGameState, mood: Dictionary) -> void:
	if state.sudden_death_winner <= 0:
		_sudden_death_refreshed = false
		return
	if _sudden_death_refreshed or String(mood.key) != "verdict" or not state.result_presentation_active:
		return
	_sudden_death_refreshed = true
	_reset_reactions()
	for s: Spectator in spectators:
		s.mood = ""
		s.queued = &""


func _update_thrower(s: Spectator, target: Node3D) -> void:
	if s.throw_started >= 0.0:
		var t := _clock - s.throw_started
		if not s.released and t >= float(_clips.SPEC_Throw.get("release", 0.3)):
			s.released = true
			_set_visible(s, "GSP_Egg", false)
			_launch_egg(s, target)
		if t >= _clip_length(&"SPEC_Throw") - 0.05:
			s.throw_started = -1.0
			s.next_throw = _clock + _rng.randf_range(0.5, 1.3)
			_play(s, &"SPEC_Rage", 0.2)
		return
	if _clock >= s.next_throw and s.queued == &"":
		s.throw_started = _clock
		s.released = false
		_set_visible(s, "GSP_Egg", true)
		_play(s, &"SPEC_Throw", 0.0, true)


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


func _face(s: Spectator, focus: Vector3, target: Node3D, delta: float) -> void:
	if s.kind == Kind.PAIR:
		return      # friends face straight ahead so their hands meet
	var aim := focus
	var limit := 0.45
	if s.kind == Kind.HOTHEAD and s.throwing and is_instance_valid(target):
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


# ------------------------------------------------------------------ inspection

## A new race on the same course: boards flip back, the eggs are cleared.
func _reset_reactions() -> void:
	clear_eggs()
	for s: Spectator in spectators:
		s.throwing = false
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
	if eggs != null:
		eggs.clear()


func get_debug_snapshot() -> Dictionary:
	var kinds := {}
	var clips := {}
	var boo_signs := 0
	var words := []
	var angry := 0
	for s: Spectator in spectators:
		kinds[Kind.keys()[s.kind]] = int(kinds.get(Kind.keys()[s.kind], 0)) + 1
		clips[String(s.clip)] = int(clips.get(String(s.clip), 0)) + 1
		boo_signs += 1 if s.boo_sign else 0
		if s.word >= 0:
			words.append({"team": s.team, "word": s.word, "row": s.row, "world": s.root.global_position, "flipped": s.boo_sign})
		angry += 1 if s.anger > 0.5 else 0
	return {"spectators": spectators.size(), "pending": _slots.size(), "kinds": kinds, "clips": clips,
		"mood": _mood.get("key", ""), "eggs_launched": eggs.launched if eggs else 0,
		"eggs_hit": eggs.hits if eggs else 0, "eggs_missed": eggs.misses if eggs else 0,
		"eggs_in_flight": eggs.in_flight() if eggs else 0, "egg_debris": eggs.active_counts() if eggs else {}, "boo_signs": boo_signs, "word_signs": words, "angry": angry,
		"world": global_position, "update_usec": _update_usec,
		"kids": kids.size(), "overlays": spectators.filter(func(s: Spectator) -> bool: return s.overlay != &"").size(),
		"mascot": String(mascot.action) if mascot != null else "",
		"vendors": spectators.filter(func(s: Spectator) -> bool: return s.kind == Kind.VENDOR).map(
			func(s: Spectator) -> Dictionary: return {"y": snappedf(s.walk_y, 0.01), "clip": String(s.clip), "height": snappedf(s.root.position.y, 0.01)}),
		"scoreboard": {"marks": Array(scoreboard.marks), "totals": scoreboard.totals(), "cutin": scoreboard.cutin_player,
			"programme": scoreboard.is_programme_started(), "programme_playing": scoreboard.is_programme_playing(),
			"segment": str(scoreboard.programme_segment().get("comp", ""))}}
