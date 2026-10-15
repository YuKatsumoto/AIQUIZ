@tool
extends Node3D

## Seated spectators of one side stand: the goal stand's block people (same rig,
## hairstyles, palette and clips) sitting in the terrace chairs.
## One MultiMesh per 20 m block keeps each block one draw call and lets the
## renderer cull blocks that are off screen. Animation runs entirely in
## shaders/seated_spectator.gdshader (see SeatedSpectatorKit).
##
## The home team is the player on this side of the course: the right stand
## (+X) cheers for P1, the left one for P2, like the goal stand's halves.
##
## Personalities (docs/crowd_extras.md): dozers, popcorn and hot dog eaters,
## selfie takers, binocular watchers, a cheer leader per block (megaphone or
## drum) who leads the chant, towel twirlers and pairs of friends who high-five
## and sway arm in arm. The mascot stands in the aisle of block 1 and starts the
## stadium wave (StandMascot).

const Kit = preload("res://scripts/world/seated_spectator_kit.gd")
const MascotScript = preload("res://scripts/world/crowd/stand_mascot.gd")
## Hips sit this far behind the cushion centre, against the chair back.
const HIP_BEHIND_SEAT := 0.06
const HOME_SHARE := 0.55
const AWAY_SHARE := 0.12
const DANCER_CHANCE := 0.06
## Of the neutral spectators.
const SLEEPER_CHANCE := 0.06
const EATER_CHANCE := 0.12
const SELFIE_CHANCE := 0.06
const BINOCULARS_CHANCE := 0.05
## Of the team fans.
const TOWEL_CHANCE := 0.10
const PAIR_CHANCE := 0.07
const HAIR_WEIGHTS: Array[int] = [0, 0, 1, 2, 3, 4, 5, 6]   # Short twice, then Long..Headband
const ROLE_CALM := 0
const ROLE_FAN := 1
const ROLE_DANCER := 2
const ROLE_SLEEPER := 3
const ROLE_EATER := 4
const ROLE_SELFIE := 5
const ROLE_BINOCULARS := 6
const ROLE_LEADER := 7
const ROLE_TOWEL := 8
const ROLE_PAIR_L := 9
const ROLE_PAIR_R := 10
## The mascot stands in the aisle nearest this far along the course (block 1's
## aisle on both sides), at the front row, on the aisle's lowest step.
const MASCOT_ALONG := 20.0
const MASCOT_ROW_X := 1.0
const MASCOT_FLOOR_Y := 0.32

var spectator_count := 0
var emote_count := 0
var fan_count := 0
## Spectators per role (ROLE_*), for tests and the debug snapshot.
var role_counts := {}
var home_team := 1
var mascot: Node3D = null
var _density := 0.85
var _seed := 0


func setup(density: float, crowd_seed: int, team: int) -> void:
	_density = clampf(density, 0.0, 1.0)
	_seed = crowd_seed
	home_team = team


## Seats come from the stand blocks' JSON: [x, cushion top, z, row] in block
## space. `center_z` is the block's position along this stand.
func add_block(index: int, center_z: float, seats: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 7919 + index * 104729
	var taken: Array = []
	for seat: Array in seats:
		taken.append(rng.randf() <= _density)
	# Rows sorted along the stand: pairs of friends sit next to each other.
	var order: Array = range(seats.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa: Array = seats[a]
		var sb: Array = seats[b]
		return sa[3] < sb[3] or (sa[3] == sb[3] and float(sa[2]) < float(sb[2])))
	var people: Array[Dictionary] = []
	var leader_seat := _leader_seat(seats, taken)
	var paired := {}
	for k: int in range(order.size() - 1):
		var a: int = order[k]
		var b: int = order[k + 1]
		if paired.has(a) or not taken[a] or not taken[b] or a == leader_seat or b == leader_seat:
			continue
		var sa: Array = seats[a]
		var sb: Array = seats[b]
		if sa[3] != sb[3] or absf(float(sb[2]) - float(sa[2]) - 0.92) > 0.05:
			continue
		if rng.randf() < PAIR_CHANCE:
			paired[a] = ROLE_PAIR_L     # its left neighbour sits at +Z (the rig's +X)
			paired[b] = ROLE_PAIR_R
	var pair_look := {}
	for i: int in order:
		if not taken[i]:
			continue
		var seat: Array = seats[i]
		var at := Vector3(float(seat[0]) + HIP_BEHIND_SEAT, float(seat[1]), center_z + float(seat[2]))
		var role := -1
		if i == leader_seat:
			role = ROLE_LEADER
		elif paired.has(i):
			role = int(paired[i])
		var person := _person(rng, at, role)
		if role == ROLE_PAIR_R:
			# Partners share phase and speed so they move as one.
			var partner: Dictionary = pair_look[i]
			var custom: Color = person["custom"]
			custom.r = partner.phase
			custom.a = partner.speed
			person["custom"] = custom
		elif role == ROLE_PAIR_L:
			var next_index: int = order[order.find(i) + 1]
			pair_look[next_index] = {"phase": (person["custom"] as Color).r, "speed": (person["custom"] as Color).a}
		people.append(person)
	if people.is_empty():
		return
	# The shader moves arms well above the head and stands people up for the wave;
	# cover the whole block, deep and tall enough for the six rows of AIQUIZ STADIUM
	# as well as four terrace rows.
	var reach_x := 8.0
	var reach_y := 4.0
	for seat: Array in seats:
		reach_x = maxf(reach_x, float(seat[0]) + HIP_BEHIND_SEAT + 1.6)
		reach_y = maxf(reach_y, float(seat[1]) + 2.6)
	var bounds := AABB(Vector3(-1.5, -0.5, center_z - 11.0), Vector3(reach_x + 1.5, reach_y + 0.5, 22.0))
	# Spectators holding a prop use the mesh with the props; the rest skip them.
	var plain := people.filter(func(person: Dictionary) -> bool: return int(person["prop"]) == 0)
	var holders := people.filter(func(person: Dictionary) -> bool: return int(person["prop"]) != 0)
	_add_batch("Block%02d" % (index + 1), plain, Kit.mesh(), bounds)
	_add_batch("Block%02dProps" % (index + 1), holders, Kit.prop_mesh(), bounds)
	spectator_count += people.size()


## One MultiMesh draw for `people` (one block keeps one or two draws).
func _add_batch(batch_name: String, people: Array, mesh: Mesh, bounds: AABB) -> void:
	if people.is_empty():
		return
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = mesh
	instances.instance_count = people.size()
	for i: int in range(people.size()):
		var person: Dictionary = people[i]
		instances.set_instance_transform(i, person["transform"])
		instances.set_instance_color(i, person["shirt"])
		instances.set_instance_custom_data(i, person["custom"])
	instances.custom_aabb = bounds
	var batch := MultiMeshInstance3D.new()
	batch.name = batch_name
	batch.multimesh = instances
	batch.material_override = Kit.material()
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(batch)


## The cheer leader of a block sits mid-row near the front (row 1), if taken.
func _leader_seat(seats: Array, taken: Array) -> int:
	var best := -1
	var best_score := INF
	for i: int in range(seats.size()):
		var seat: Array = seats[i]
		if not taken[i] or int(seat[3]) != 1:
			continue
		var score := absf(float(seat[2]) - 2.0)
		if score < best_score:
			best_score = score
			best = i
	return best


func _person(rng: RandomNumberGenerator, seat: Vector3, forced_role: int = -1) -> Dictionary:
	var roll := rng.randf()
	var team := home_team if roll < HOME_SHARE else ((3 - home_team) if roll < HOME_SHARE + AWAY_SHARE else 0)
	var role := ROLE_FAN if team != 0 else ROLE_CALM
	var prop := 0
	if forced_role in [ROLE_LEADER, ROLE_PAIR_L, ROLE_PAIR_R]:
		team = home_team
		role = forced_role
	elif team == 0:
		var pick := rng.randf()
		var neutral := 1.0 - HOME_SHARE - AWAY_SHARE
		var dancer := DANCER_CHANCE / neutral
		if pick < dancer:
			role = ROLE_DANCER
		elif pick < dancer + SLEEPER_CHANCE:
			role = ROLE_SLEEPER
		elif pick < dancer + SLEEPER_CHANCE + EATER_CHANCE:
			role = ROLE_EATER
		elif pick < dancer + SLEEPER_CHANCE + EATER_CHANCE + SELFIE_CHANCE:
			role = ROLE_SELFIE
		elif pick < dancer + SLEEPER_CHANCE + EATER_CHANCE + SELFIE_CHANCE + BINOCULARS_CHANCE:
			role = ROLE_BINOCULARS
	elif rng.randf() < TOWEL_CHANCE:
		role = ROLE_TOWEL
	match role:
		ROLE_EATER:
			prop = Kit.PROP_POPCORN if rng.randf() < 0.6 else Kit.PROP_HOTDOG
		ROLE_SELFIE:
			prop = Kit.PROP_PHONE
		ROLE_BINOCULARS:
			prop = Kit.PROP_BINOCULARS
		ROLE_LEADER:
			prop = Kit.PROP_MEGAPHONE if rng.randf() < 0.5 else Kit.PROP_DRUM
		ROLE_TOWEL:
			prop = Kit.PROP_TOWEL
	if role == ROLE_DANCER:
		emote_count += 1
	if team != 0:
		fan_count += 1
	role_counts[role] = int(role_counts.get(role, 0)) + 1
	var shirts: Array[Color] = GoalStand.P1_SHIRTS if team == 1 else (GoalStand.P2_SHIRTS if team == 2 else GoalStand.NEUTRAL_SHIRTS)
	var hair := HAIR_WEIGHTS[rng.randi_range(0, HAIR_WEIGHTS.size() - 1)]
	if role == ROLE_LEADER:
		hair = 6          # the headband
	var look := hair \
		+ 7 * rng.randi_range(0, GoalStand.SKINS.size() - 1) \
		+ 42 * rng.randi_range(0, GoalStand.HAIR_COLORS.size() - 1) \
		+ 252 * rng.randi_range(0, GoalStand.PANTS.size() - 1) \
		+ 1260 * rng.randi_range(0, GoalStand.SHOES.size() - 1) \
		+ 5040 * prop
	# Resting pose: a quiet idle or folded arms. Talking, phones and nodding
	# only come in the shader's occasional bursts.
	var idle := Kit.clip_index(&"SPEC_Idle") if rng.randf() < 0.65 else Kit.clip_index(&"SPEC_FoldArms")
	var habit := idle + 8 * role + 128 * team
	var size := rng.randf_range(0.93, 1.03)
	# The rig faces +Z; spectators face the course (stand-local -X).
	var basis := Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * size)
	return {
		"transform": Transform3D(basis, seat),
		"shirt": shirts[rng.randi_range(0, shirts.size() - 1)],
		"custom": Color(rng.randf(), float(look), float(habit), rng.randf_range(0.9, 1.12)),
		"prop": prop,
	}


## The stand's mascot in the aisle nearest MASCOT_ALONG, at the front row.
## `aisle_z` is the aisle's stand-local z. The side stands are far from the
## lanes, so the light body is enough.
func add_mascot(aisle_z: float) -> void:
	if mascot != null:
		return
	mascot = MascotScript.new()
	mascot.name = "Mascot"
	# A sibling of the seat batches (stand space = this node's space), so this node
	# only holds MultiMesh blocks.
	(get_parent() if get_parent() != null else self).add_child(mascot)
	mascot.position = transform * Vector3(MASCOT_ROW_X, MASCOT_FLOOR_Y, aisle_z)
	# Faces the course (stand-local -X); the mascot rig faces +Z.
	mascot.rotation.y = rotation.y - PI * 0.5
	mascot.setup("balanced")


## Live side stand crowds, so the game can animate their mascots.
static var _crowds: Array = []


func _enter_tree() -> void:
	if not _crowds.has(self):
		_crowds.append(self)


func _exit_tree() -> void:
	_crowds.erase(self)


## Moves the side stands' mascots with the cues: the right one leads the wave
## as it leaves, both clap with the chant, cheer and dance with the crowd.
static func update_mascots(cues: CrowdCues, delta: float, camera: Camera3D) -> void:
	if cues == null:
		return
	for crowd: Variant in _crowds:
		if not is_instance_valid(crowd) or crowd.mascot == null or not crowd.mascot.is_inside_tree():
			continue
		var m: Node3D = crowd.mascot
		var distance := camera.global_position.distance_to(m.global_position) if is_instance_valid(camera) else 0.0
		var since := -1.0
		if cues.wave_time() >= 0.0:
			since = cues.wave_time() - cues.wave_arrival_side(m.global_position.x > 0.0, m.global_position.z - cues.course_z)
		m.follow(cues, delta, since, distance)


# ------------------------------------------------------------------ cues

static var _hype := 0.0
static var _sync_slots := {1: &"", 2: &""}


## Game reactions shared by both side stands (one material). `reaction` comes
## from GoalStand.side_crowd_reaction(): the side fans mirror the goal crowd.
## Kept for tools and tests; the game drives follow_cues().
static func follow_reaction(reaction: Dictionary, delta: float) -> void:
	if not Kit.is_built():
		return # No side crowd has been built.
	var target := float(reaction.get("amount", 0.0))
	var eased := move_toward(_hype, target, delta / 0.45)
	if is_equal_approx(eased, _hype) and is_equal_approx(target, _hype):
		return
	_hype = eased
	var material := Kit.material()
	material.set_shader_parameter("cue_weight", _hype)
	material.set_shader_parameter("cue_time", 0.0)
	if target > 0.0:
		material.set_shader_parameter("cue_kind", 2 if bool(reaction.get("verdict", false)) else 1)
		material.set_shader_parameter("cue_team", int(reaction.get("team", 0)))


## Pushes the crowd's cues (CrowdCues) to the shared side stand material.
static func follow_cues(cues: CrowdCues) -> void:
	if not Kit.is_built() or cues == null:
		return
	var material := Kit.material()
	material.set_shader_parameter("cue_kind", int(cues.cue))
	material.set_shader_parameter("cue_team", cues.cue_team)
	material.set_shader_parameter("cue_time", cues.cue_time())
	material.set_shader_parameter("cue_weight", cues.cue_weight())
	material.set_shader_parameter("rivals_react", cues.two_players)
	material.set_shader_parameter("course_z", cues.course_z)
	material.set_shader_parameter("shock_z", cues.shock_course)
	material.set_shader_parameter("shock_time", cues.shock_time())
	material.set_shader_parameter("wave_time", cues.wave_time())
	material.set_shader_parameter("wave_speed", CrowdCues.WAVE_SPEED)
	material.set_shader_parameter("wave_origin", cues.wave_origin)
	material.set_shader_parameter("wave_goal", cues.goal_course)
	material.set_shader_parameter("wave_cross", cues.wave_cross())
	material.set_shader_parameter("chant_time", cues.chant_time())
	material.set_shader_parameter("chant_weight", cues.chant_weight())
	material.set_shader_parameter("chant_team", cues.chant_team)
	# The winner's dance: bake the clips as soon as they are known, a few frames a
	# frame, and play them on the dance clock once baked.
	for slot: int in [1, 2]:
		var clip: StringName = cues.sync_clips[slot]
		if clip != &"" and clip != _sync_slots[slot]:
			_sync_slots[slot] = clip
			Kit.prepare_sync(slot, clip)
	Kit.step_sync()
	material.set_shader_parameter("sync_weight", cues.sync_weight)
	material.set_shader_parameter("sync_team", cues.sync_team)
	for slot: int in [1, 2]:
		material.set_shader_parameter("sync_time_%d" % slot, CrowdCues.dance_time(_sync_slots[slot], cues.sync_elapsed))


## Prepares the winner's dances ahead of the verdict (both players' emotes).
static func prepare_dances(emote_p1: int, emote_p2: int) -> void:
	if not Kit.is_built():
		return
	for slot: int in [1, 2]:
		var clip := CrowdCues.crowd_dance_for(emote_p1 if slot == 1 else emote_p2)
		if clip != _sync_slots[slot]:
			_sync_slots[slot] = clip
			Kit.prepare_sync(slot, clip)
