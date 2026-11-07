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
##
## With enable_sim() the stand's crowd becomes a management sim (CrowdSim,
## docs/crowd_sim.md): people come late, fetch snacks, go to the toilet and leave.
## Each block's batches then keep room for all its people and draw the ones in
## their seats first (visible_instance_count); the people on foot are one more
## batch (Walkers). Without it every seat stays taken as built.

const Kit = preload("res://scripts/world/seated_spectator_kit.gd")
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
## Phones: every spectator is ~700 skinned triangles (all hair styles share one mesh) and both
## stands held ~2.2 M of a match's 2.4 M triangles. Fewer seats are taken there, and the
## snack holders use the plain body (the prop mesh carries every prop, 2150 triangles).
const MOBILE_DENSITY_SCALE := 0.55
const MascotScript = preload("res://scripts/world/crowd/stand_mascot.gd")
## A block farther than this from the camera does not walk (people just appear).
const WATCH_DISTANCE := 150.0
## People in a block farther than this from the camera along the stand keep what they
## are doing (CrowdSim.tick()'s `awake`): a spectator there is about a pixel tall.
const AWAKE_DISTANCE := 600.0
## The side stands' beer vendors: a staff shirt and a cap.
const VENDOR_SHIRT := Color(0.98, 0.80, 0.20)
const VENDOR_HAIR := 2
const FAR_CLIP_Z := &"far_clip_z"
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
## The management sim (enable_sim()), or null.
var sim: CrowdSim = null
var _density := 0.85
var _seed := 0
var _paths: StandPaths = null
## Sim only, per person (the sim's index): block, batch (0 plain, 1 props, -1
## not drawn), slot in it, transform, shirt, custom, prop, team, size.
var _drawn: Array[Dictionary] = []
## Sim only, per block: [plain, props] batches, their slot -> person lists, centre z.
var _batches := {}
var _slots := {}
var _centers := {}
## The same centres in rising order with their blocks, and the highest block: the
## per-frame checks look up the blocks near the camera instead of going over all of
## them (an endless course keeps adding blocks).
var _center_z := PackedFloat32Array()
var _center_block := PackedInt32Array()
var _last_block := -1
var _walkers: MultiMeshInstance3D = null
## Sim only: each vendor's look, drawn like a person (custom, shirt, team, size).
var _vendor_drawn: Array[Dictionary] = []


func setup(density: float, crowd_seed: int, team: int) -> void:
	_density = clampf(density, 0.0, 1.0)
	if QualityRules.is_mobile_target():
		_density *= MOBILE_DENSITY_SCALE
	_seed = crowd_seed
	home_team = team


## Turns the crowd into the management sim with `pool` walkers and `vendors` beer
## vendors. Call before the first add_block().
func enable_sim(pool: int, vendors := 0) -> void:
	if sim != null:
		return
	_paths = StandPaths.new()
	sim = CrowdSim.new(_paths, _seed * 31 + home_team, pool, vendors)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 13 + home_team
	for _k: int in range(vendors):
		var look := VENDOR_HAIR \
			+ 7 * rng.randi_range(0, GoalStand.SKINS.size() - 1) \
			+ 42 * rng.randi_range(0, GoalStand.HAIR_COLORS.size() - 1) \
			+ 252 * rng.randi_range(0, GoalStand.PANTS.size() - 1) \
			+ 1260 * rng.randi_range(0, GoalStand.SHOES.size() - 1) \
			+ 5040 * Kit.PROP_VENDOR
		_vendor_drawn.append({"custom": Color(rng.randf(), float(look), float(8 * ROLE_CALM), 1.0), "shirt": VENDOR_SHIRT,
			"team": 0, "size": 1.0})
	_walkers = MultiMeshInstance3D.new()
	_walkers.name = "Walkers"
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = Kit.prop_mesh()
	instances.instance_count = pool + vendors
	instances.visible_instance_count = 0
	# People walk the whole stand, both ways along it.
	instances.custom_aabb = AABB(Vector3(-2.0, -1.0, -1000.0), Vector3(16.0, 8.0, 2000.0))
	_walkers.multimesh = instances
	_walkers.material_override = Kit.material()
	_walkers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_walkers.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_walkers)


## Where the stand's blocks, booths and aisles are now (stand space; the stand
## calls this whenever it grows), and the blocks' walk (StandPaths.configure()).
func set_layout(centers: Array, kinds: Array, aisles: Array, walk: Dictionary = {}) -> void:
	if sim == null:
		return
	_paths.configure(walk)
	_paths.set_blocks(centers, kinds, aisles)
	sim.refresh_aisles()


## The stretch of the stand that is shown (stand space z, from < to); the beer
## vendors keep to it (CrowdSim.set_walk_z()).
func set_walk_z(from_z: float, to_z: float) -> void:
	if sim != null:
		sim.set_walk_z(Vector2(from_z, to_z))


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
	var rows := PackedInt32Array()
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
		rows.append(int(seat[3]))
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
	spectator_count += people.size()
	if sim != null:
		_add_sim_block(index, center_z, people, rows, bounds)
		return
	if QualityRules.is_mobile_target():
		_add_batch("Block%02d" % (index + 1), people, Kit.mesh(), bounds)
		return
	# Spectators holding a prop use the mesh with the props; the rest skip them.
	var plain := people.filter(func(person: Dictionary) -> bool: return int(person["prop"]) == 0)
	var holders := people.filter(func(person: Dictionary) -> bool: return int(person["prop"]) != 0)
	_add_batch("Block%02d" % (index + 1), plain, Kit.mesh(), bounds)
	_add_batch("Block%02dProps" % (index + 1), holders, Kit.prop_mesh(), bounds)


## One MultiMesh draw for `people` (one block keeps one or two draws). `room`
## (the sim) keeps that many instances and draws none until they are filled.
func _add_batch(batch_name: String, people: Array, mesh: Mesh, bounds: AABB, room := 0) -> MultiMeshInstance3D:
	if people.is_empty() and room == 0:
		return null
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = mesh
	instances.instance_count = maxi(people.size(), room)
	if room > 0:
		instances.visible_instance_count = people.size()
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
	return batch


## The sim's block: both batches with room for everybody (a snack moves a person
## to the props batch), the people handed to the sim in row order.
func _add_sim_block(index: int, center_z: float, people: Array[Dictionary], rows: PackedInt32Array,
		bounds: AABB) -> void:
	var batches: Array[MultiMeshInstance3D] = [
		_add_batch("Block%02d" % (index + 1), [], Kit.mesh(), bounds, people.size()),
		_add_batch("Block%02dProps" % (index + 1), [], Kit.mesh() if QualityRules.is_mobile_target() else Kit.prop_mesh(), bounds, people.size()),
	]
	_batches[index] = batches
	_slots[index] = [[], []]
	if _centers.has(index):
		var old := _center_block.find(index)
		_center_z.remove_at(old)
		_center_block.remove_at(old)
	_centers[index] = center_z
	var at := _center_z.bsearch(center_z)
	_center_z.insert(at, center_z)
	_center_block.insert(at, index)
	_last_block = maxi(_last_block, index)
	var previous := -1
	for k: int in range(people.size()):
		var person: Dictionary = people[k]
		var transform: Transform3D = person["transform"]
		var role: int = person["role"]
		var neighbour := -1
		if k > 0 and rows[k] == rows[k - 1] \
				and absf(transform.origin.z - (people[k - 1]["transform"] as Transform3D).origin.z - 0.92) < 0.05:
			neighbour = previous
		var drawn := person.duplicate()
		drawn["block"] = index
		drawn["batch"] = -1
		drawn["slot"] = -1
		_drawn.append(drawn)
		previous = sim.add_person(index, transform.origin, transform * Kit.stand_floor(), rows[k], int(person["team"]),
			role in [ROLE_LEADER, ROLE_PAIR_L, ROLE_PAIR_R],
			int(person["prop"]) == 0 and role in [ROLE_CALM, ROLE_FAN, ROLE_DANCER], neighbour)
		# A block added during a match opens empty (its people are on the way).
		if sim.seat_view(previous).shown:
			_put_in(previous, 0 if int(person["prop"]) == 0 else 1)
		sim.changed.erase(previous)


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
		"role": role,
		"team": team,
		"size": size,
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


# ------------------------------------------------------------------ the sim

## The sim's clock, shared by both stands (one material): scripts start on it.
static var _sim_clock := 0.0


## Advances the side stands' sims (docs/crowd_sim.md) and draws what changed.
## `camera` decides which blocks walk; without one nobody walks.
static func update_sim(mood: CrowdMood, delta: float, camera: Camera3D) -> void:
	if mood == null or not Kit.is_built():
		return
	_sim_clock += delta
	Kit.material().set_shader_parameter("sim_clock", _sim_clock)
	for crowd: Variant in _crowds:
		if is_instance_valid(crowd) and crowd.sim != null and crowd.is_inside_tree():
			crowd._step_sim(mood, delta, camera)


func _step_sim(mood: CrowdMood, delta: float, camera: Camera3D) -> void:
	sim.tick(_sim_clock, delta, mood, _watched_blocks(camera), _awake_blocks(camera))
	for index: int in sim.changed:
		_draw_seat(index)
	sim.changed.clear()
	_draw_walkers()


## 1 for the blocks the camera sees: shown whole (not hidden or cut by the stand's
## end), near enough and with some of the block (front deck to back rail) in view.
func _watched_blocks(camera: Camera3D) -> PackedByteArray:
	var watched := PackedByteArray()
	watched.resize(_last_block + 1)
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return watched
	# The eye in stand space (the stand only moves and turns, so distances match).
	var eye := global_transform.affine_inverse() * camera.global_position
	var planes := camera.get_frustum()
	# A block within WATCH_DISTANCE is within it along the stand too (+1 m for the
	# rounded centres).
	var near := _blocks_near(eye.z, WATCH_DISTANCE + 1.0)
	for k: int in range(near.x, near.y):
		var index := _center_block[k]
		var center: float = _centers[index]
		# 遠いブロックを先に除く（客席が長くても、毎フレームの確認は近くのブロックだけ）。
		if eye.distance_to(Vector3(5.0, 1.5, center)) > WATCH_DISTANCE:
			continue
		var batch: MultiMeshInstance3D = _batches[index][0]
		if not batch.is_visible_in_tree() or batch.position.z != 0.0:
			continue
		var clip: Variant = batch.get_instance_shader_parameter(FAR_CLIP_Z)
		if clip != null and float(clip) < 1e8:
			continue
		if _in_view(planes, center):
			watched[index] = 1
	return watched


## 1 for the blocks within AWAKE_DISTANCE of the camera along the stand. Empty
## without a camera: then every block stays awake.
func _awake_blocks(camera: Camera3D) -> PackedByteArray:
	var awake := PackedByteArray()
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return awake
	awake.resize(_last_block + 1)
	var near := _blocks_near((global_transform.affine_inverse() * camera.global_position).z, AWAKE_DISTANCE)
	for k: int in range(near.x, near.y):
		awake[_center_block[k]] = 1
	return awake


## The blocks whose centre is within `reach` of stand z `z`, as a range of
## _center_z: Vector2i(first, past the last).
func _blocks_near(z: float, reach: float) -> Vector2i:
	return Vector2i(_center_z.bsearch(z - reach), _center_z.bsearch(z + reach, false))


## Some of the block around stand z `center` is inside the frustum `planes`
## (their normals point out of it): no plane has all the block's corners outside.
func _in_view(planes: Array[Plane], center: float) -> bool:
	var corners: Array[Vector3] = []
	for x: float in [-1.0, 12.5]:
		for y: float in [-0.5, 5.5]:
			for z: float in [center - 10.0, center + 10.0]:
				corners.append(global_transform * Vector3(x, y, z))
	for plane: Plane in planes:
		var outside := true
		for corner: Vector3 in corners:
			if not plane.is_point_over(corner):
				outside = false
				break
		if outside:
			return false
	return true


## Puts person `index` in its seat as the sim has it: shown or not, in which
## batch (a snack needs the props), standing up or sitting down.
func _draw_seat(index: int) -> void:
	var drawn := _drawn[index]
	var view := sim.seat_view(index)
	var food := int(view.food)
	var want := -1
	if view.shown:
		want = 1 if int(drawn.prop) != 0 or food != 0 else 0
	if int(drawn.batch) != want:
		if int(drawn.batch) >= 0:
			_take_out(index)
		if want >= 0:
			_put_in(index, want)
	if want < 0:
		return
	var batch: MultiMeshInstance3D = _batches[drawn.block][want]
	batch.multimesh.set_instance_custom_data(int(drawn.slot),
		_custom(drawn, food, view.clip, float(view.start), 1.0, bool(view.get("loop", false))))


func _put_in(index: int, which: int) -> void:
	var drawn := _drawn[index]
	var instances := (_batches[drawn.block][which] as MultiMeshInstance3D).multimesh
	var slot := instances.visible_instance_count
	instances.visible_instance_count = slot + 1
	instances.set_instance_transform(slot, drawn.transform)
	instances.set_instance_color(slot, drawn.shirt)
	instances.set_instance_custom_data(slot, drawn.custom)
	(_slots[drawn.block][which] as Array).append(index)
	drawn.batch = which
	drawn.slot = slot


## Out of its batch: the batch's last person takes the slot, so the people in
## their seats stay first.
func _take_out(index: int) -> void:
	var drawn := _drawn[index]
	var slots: Array = _slots[drawn.block][drawn.batch]
	var instances := (_batches[drawn.block][drawn.batch] as MultiMeshInstance3D).multimesh
	var last := instances.visible_instance_count - 1
	var slot: int = drawn.slot
	if slot != last:
		var moved: int = slots[last]
		instances.set_instance_transform(slot, instances.get_instance_transform(last))
		instances.set_instance_color(slot, instances.get_instance_color(last))
		instances.set_instance_custom_data(slot, instances.get_instance_custom_data(last))
		slots[slot] = moved
		_drawn[moved].slot = slot
	slots.pop_back()
	instances.visible_instance_count = last
	drawn.batch = -1
	drawn.slot = -1


## The person's custom data with a snack in hand (an eater, prop 0 before) and a
## scripted clip (CrowdSim) from `start` on the sim's clock.
func _custom(drawn: Dictionary, food: int, clip: StringName, start: float, rate: float, loop: bool) -> Color:
	var base: Color = drawn.custom
	var look := base.g
	var habit := base.b
	if food != 0:
		look += 5040.0 * food
		habit = float(int(habit) % 8 + 8 * ROLE_EATER + 128 * int(drawn.team))
	if clip == &"":
		return Color(base.r, look, habit, base.a)
	var scripted := Kit.clip_index(clip) + 1 + (64 if loop else 0)
	return Color(start, look, habit + 512.0 * scripted, rate)


## The people on foot, from the sim's walkers, then the vendors.
func _draw_walkers() -> void:
	var instances := _walkers.multimesh
	var count := mini(sim.walkers.size(), instances.instance_count - sim.vendors.size())
	instances.visible_instance_count = count + sim.vendors.size()
	var floor_point := Kit.stand_floor()
	for k: int in range(sim.vendors.size()):
		var v: CrowdSim.Vendor = sim.vendors[k]
		var drawn := _vendor_drawn[k]
		var basis := Basis(Vector3.UP, v.yaw)
		instances.set_instance_transform(count + k, Transform3D(basis, v.position - basis * floor_point))
		instances.set_instance_color(count + k, drawn.shirt)
		var start := _sim_clock - v.phase / maxf(v.rate, 0.01)
		instances.set_instance_custom_data(count + k, _custom(drawn, 0, v.clip, start, v.rate, v.loop))
	for k: int in range(count):
		var w: CrowdSim.Walker = sim.walkers[k]
		var drawn := _drawn[w.person]
		var basis := Basis(Vector3.UP, w.yaw).scaled(Vector3.ONE * float(drawn.size))
		instances.set_instance_transform(k, Transform3D(basis, w.position - basis * floor_point))
		instances.set_instance_color(k, drawn.shirt)
		var start := _sim_clock - w.phase / maxf(w.rate, 0.01)
		instances.set_instance_custom_data(k, _custom(drawn, sim.people[w.person].food, w.clip, start, w.rate, w.loop))


func sim_snapshot() -> Dictionary:
	return sim.snapshot() if sim != null else {}
