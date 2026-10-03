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

const Kit = preload("res://scripts/world/seated_spectator_kit.gd")
## Hips sit this far behind the cushion centre, against the chair back.
const HIP_BEHIND_SEAT := 0.06
const HOME_SHARE := 0.55
const AWAY_SHARE := 0.12
const DANCER_CHANCE := 0.06
const HAIR_WEIGHTS: Array[int] = [0, 0, 1, 2, 3, 4, 5, 6]   # Short twice, then Long..Headband
const ROLE_CALM := 0
const ROLE_FAN := 1
const ROLE_DANCER := 2

var spectator_count := 0
var emote_count := 0
var fan_count := 0
var home_team := 1
var _density := 0.85
var _seed := 0


func setup(density: float, crowd_seed: int, team: int) -> void:
	_density = clampf(density, 0.0, 1.0)
	_seed = crowd_seed
	home_team = team


## Seats come from santorini_terrace_modules.json: [x, cushion top, z, row] in
## block space. `center_z` is the block's position along this stand.
func add_block(index: int, center_z: float, seats: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 7919 + index * 104729
	var people: Array[Dictionary] = []
	for seat: Array in seats:
		if rng.randf() > _density:
			continue
		people.append(_person(rng, Vector3(float(seat[0]) + HIP_BEHIND_SEAT, float(seat[1]), center_z + float(seat[2]))))
	if people.is_empty():
		return
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = Kit.mesh()
	instances.instance_count = people.size()
	for i: int in range(people.size()):
		var person: Dictionary = people[i]
		instances.set_instance_transform(i, person["transform"])
		instances.set_instance_color(i, person["shirt"])
		instances.set_instance_custom_data(i, person["custom"])
	# The shader moves arms well above the head; cover the whole block, deep and
	# tall enough for the six rows of AIQUIZ STADIUM as well as four terrace rows.
	var reach_x := 8.0
	var reach_y := 4.0
	for seat: Array in seats:
		reach_x = maxf(reach_x, float(seat[0]) + HIP_BEHIND_SEAT + 1.6)
		reach_y = maxf(reach_y, float(seat[1]) + 2.2)
	instances.custom_aabb = AABB(Vector3(-1.5, -0.5, center_z - 11.0), Vector3(reach_x + 1.5, reach_y + 0.5, 22.0))
	var batch := MultiMeshInstance3D.new()
	batch.name = "Block%02d" % (index + 1)
	batch.multimesh = instances
	batch.material_override = Kit.material()
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(batch)
	spectator_count += people.size()


func _person(rng: RandomNumberGenerator, seat: Vector3) -> Dictionary:
	var roll := rng.randf()
	var team := home_team if roll < HOME_SHARE else ((3 - home_team) if roll < HOME_SHARE + AWAY_SHARE else 0)
	var role := ROLE_FAN if team != 0 else ROLE_CALM
	if team == 0 and rng.randf() < DANCER_CHANCE / (1.0 - HOME_SHARE - AWAY_SHARE):
		role = ROLE_DANCER
		emote_count += 1
	if role == ROLE_FAN:
		fan_count += 1
	var shirts: Array[Color] = GoalStand.P1_SHIRTS if team == 1 else (GoalStand.P2_SHIRTS if team == 2 else GoalStand.NEUTRAL_SHIRTS)
	var hair := HAIR_WEIGHTS[rng.randi_range(0, HAIR_WEIGHTS.size() - 1)]
	var look := hair \
		+ 7 * rng.randi_range(0, GoalStand.SKINS.size() - 1) \
		+ 42 * rng.randi_range(0, GoalStand.HAIR_COLORS.size() - 1) \
		+ 252 * rng.randi_range(0, GoalStand.PANTS.size() - 1) \
		+ 1260 * rng.randi_range(0, GoalStand.SHOES.size() - 1)
	# Resting pose: a quiet idle or folded arms. Talking, phones and nodding
	# only come in the shader's occasional bursts.
	var idle := Kit.clip_index(&"SPEC_Idle") if rng.randf() < 0.65 else Kit.clip_index(&"SPEC_FoldArms")
	var habit := idle + 8 * role + 32 * team
	var size := rng.randf_range(0.93, 1.03)
	# The rig faces +Z; spectators face the course (stand-local -X).
	var basis := Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * size)
	return {
		"transform": Transform3D(basis, seat),
		"shirt": shirts[rng.randi_range(0, shirts.size() - 1)],
		"custom": Color(rng.randf(), float(look), float(habit), rng.randf_range(0.9, 1.12)),
	}


## Game reactions shared by both side stands (one material). `reaction` comes
## from GoalStand.side_crowd_reaction(): the side fans mirror the goal crowd.
static var _hype := 0.0


static func follow_reaction(reaction: Dictionary, delta: float) -> void:
	if not Kit.is_built():
		return # No side crowd has been built.
	var target := float(reaction.get("amount", 0.0))
	var eased := move_toward(_hype, target, delta / 0.45)
	if is_equal_approx(eased, _hype) and is_equal_approx(target, _hype):
		return
	_hype = eased
	var material := Kit.material()
	material.set_shader_parameter("hype", _hype)
	if target > 0.0:
		material.set_shader_parameter("hype_team", int(reaction.get("team", 0)))
		material.set_shader_parameter("hype_verdict", bool(reaction.get("verdict", false)))
