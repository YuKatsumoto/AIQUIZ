class_name ResultFinaleStage
extends Node3D

## Score Tower Finale cast in the real GameWorld: two score towers that rise with
## each player's total, the Blender-choreographed players riding them, the crown,
## and the Godot referee who raises the winner's flag.
##
## The node sits at the players' finishing marks, rotated PI (Blender's camera looks
## from -Y, gameplay from -Z) and mirrored in X when P2 wins, so the authored
## "winner" side always lands in the winner's own lane.

const TOWER_SCENE := preload("res://assets/result_finale/score_tower.glb")
const CROWN_SCENE := preload("res://assets/result_finale/crown.glb")
const TIERS_SCENE := preload("res://assets/result_finale/tower_tiers.glb")
const Motion = preload("res://scripts/world/result_finale/result_finale_motion.gd")
const P1_COLOR := Color(0.95, 0.55, 0.20)
const P2_COLOR := Color(0.20, 0.65, 0.90)
const HANDOFF := 0.18
## Sudden death: after the whistle both finalists lower their arms and open their fists into
## a plain standing pose (elapsed seconds), the pose the live runners take over on the deck.
const SUDDEN_DEATH_CALM := Vector2(8.75, 9.55)
## The platform deck and the collar's hazard ring are both authored at the collar
## height, so a resting pad shared their depth plane and flickered. Keep the whole
## lift (deck, column, cast) this far above its authored height.
const PAD_CLEARANCE := 0.02
const ACCENT_ENERGY := 1.25
const GOLD_ALBEDO := Color(1.0, 0.72, 0.16)
const FINGERS := ["index", "middle", "ring", "pinky"]
## The imported column (build_set.py) bands every 0.5 m and is 3.2 m long; the stage
## hides it and stacks Blender tier modules (build_tower_tiers.py) instead, one per
## point. The stack starts this far below the lift origin (platform 0.20 + gap
## 0.10), the same as pop - collar, so tier k's ring clears the collar exactly when
## the counter reaches k points. Every 5th tier is the gold-banded milestone.
const COLUMN_TOP := -0.30
const MILESTONE_EVERY := 5

static var _tier_column: ArrayMesh

var _state: QuizGameState
var _players: PlayerController
var _camera: Camera3D
var _effects: ResultFinaleEffects
var _winner := -1
var _draw := false
var _towers := {}
var _actors := {}
var _dances := {}
var _crown: Node3D
var _crown_offset := 0.0
var _referee: Node3D
var _referee_animation: AnimationPlayer
var _handoff_poses := {}
## Player index -> released result ghost standing in for an eliminated finalist.
var _ghost_sources := {}
var _latches := {}
var _elapsed := 0.0
var _performance := 0.0
var _cast_visible := false
## Sudden death return (docs 2.3): player index -> {"from": Vector3, "progress": float}
## while the loser flies out of the drain onto the sunken pad; hidden before it.
var _flights := {}
var _hidden_actors := {}
var _hold_clock := 0.0


func setup(state: QuizGameState, players: PlayerController, camera: Camera3D, effects: ResultFinaleEffects) -> void:
	_state = state
	_players = players
	_camera = camera
	_effects = effects
	name = "ResultFinaleStage"
	visible = false


## Called every frame by the director before update_stage (build() clears it).
func set_ghost_sources(ghosts: Dictionary) -> void:
	_ghost_sources = ghosts.duplicate()


func _ghost_source(player_index: int) -> Node3D:
	var ghost := _ghost_sources.get(player_index) as Node3D
	return ghost if ghost != null and is_instance_valid(ghost) else null


func is_built() -> bool:
	return not _towers.is_empty()


## Outcome the stage was built for (-1 before build, 0 draw, 1/2 winner).
func built_winner() -> int:
	return _winner


func player_color(player_index: int) -> Color:
	return P1_COLOR if player_index == 1 else P2_COLOR


## Authored side for a player: "WIN" tracks for the winner (both on a draw).
func side_of(player_index: int) -> String:
	return "WIN" if _draw or player_index == _winner else "LOSE"


func totals() -> Vector2i:
	return Vector2i(_state.result_p1_score, _state.result_p2_score)


func tower_height(player_index: int, time: float) -> float:
	var t := totals()
	var total := t.x if player_index == 1 else t.y
	var max_total := maxi(t.x, t.y)
	if _state.sudden_death_pending:
		# The draw branches into the sudden death: both towers sink into the deck.
		return Motion.branch_height(total, max_total, time, QuizGameState.SUDDEN_DEATH_SINK_TIME)
	if _state.sudden_death_winner > 0 or _state.sudden_death_aborted:
		# Back from underground: the loser's tower stays sunk; the riser grows back
		# while the ceremony holds at the verdict.
		var riser := _state.sudden_death_aborted or player_index == _state.sudden_death_winner
		var collar := float(Motion.heights().collar)
		if not riser:
			return collar
		var standing := Motion.tower_height(total, max_total, time)
		if _state.result_return_hold:
			return lerpf(collar, standing, smoothstep(0.0, 1.0, _state.result_return_regrow))
		return standing
	return Motion.tower_height(total, max_total, time)


func build(winner: int) -> void:
	clear()
	_winner = winner
	_draw = winner == 0
	for player_index in [1, 2]:
		_build_tower(player_index)
		_build_actor(player_index)
	var referee := ResultFinaleReferee.create(self, "FinaleReferee")
	_referee = referee.root
	_referee_animation = referee.animation
	if _winner == 2:
		ResultFinaleReferee.unmirror(_referee)
	if not _draw:
		_crown = CROWN_SCENE.instantiate() as Node3D
		_crown.name = "WinnerCrown"
		var mount := _actors[_winner].parts.hat_mount as Node3D
		mount.add_child(_crown)
		_crown_offset = _hat_top(mount)
		_apply_gold(_crown, ["FIN_CrownGold"])
	for player_index in [1, 2]:
		if _draw or player_index == _winner:
			var dance := ResultWinnerDance.new()
			dance.setup(self, _state.get_result_winner_emote(player_index))
			_dances[player_index] = dance


func _side_x(player_index: int) -> float:
	# Blender authored the winner at -X (P1's lane after the PI turn). The P2 mirror
	# moves that side into P2's lane; a draw keeps P1 there and P2 opposite.
	var authored_winner_side := player_index == 1 if _draw else player_index == _winner
	return -Motion.TOWER_X if authored_winner_side else Motion.TOWER_X


func _build_tower(player_index: int) -> void:
	var built := create_tower(player_index, self)
	var tower := built.root as Node3D
	tower.position = Vector3(_side_x(player_index), 0.0, 0.0)
	_towers[player_index] = built


## One score tower (column of tier modules, player-coloured accents, gold trim, no
## shadows) under `parent`: {"root", "lift", "accent", "muzzles"}. The sudden death
## elevator deck carries the same towers, sunk to the collar, down the shaft.
static func create_tower(player_index: int, parent: Node3D) -> Dictionary:
	var tower := TOWER_SCENE.instantiate() as Node3D
	tower.name = "ScoreTowerP%d" % player_index
	parent.add_child(tower)
	var lift := tower.find_child("TowerLift", true, false) as Node3D
	var color := P1_COLOR if player_index == 1 else P2_COLOR
	var accent := StandardMaterial3D.new()
	accent.albedo_color = color
	accent.emission_enabled = true
	accent.emission = color
	accent.emission_energy_multiplier = ACCENT_ENERGY
	accent.roughness = 0.35
	for node: Node in tower.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			if material != null and material.resource_name == "FIN_TowerAccent":
				mesh.set_surface_override_material(surface, accent)
	var column := tower.find_child("*Column*", true, false) as MeshInstance3D
	if column != null:
		column.visible = false
	var tiers := MeshInstance3D.new()
	tiers.name = "TierColumn"
	tiers.mesh = tier_column_mesh()
	for surface in range(tiers.mesh.get_surface_count()):
		var material := tiers.mesh.surface_get_material(surface)
		if material != null and material.resource_name == "FIN_TowerAccent":
			tiers.set_surface_override_material(surface, accent)
	lift.add_child(tiers)
	_apply_gold(tower, ["FIN_CannonMetal", "FIN_TierGold"])
	_disable_shadows(tower)
	var muzzles: Array[Node3D] = []
	for node: Node in tower.find_children("*Muzzle*", "Node3D", true, false):
		muzzles.append(node as Node3D)
	return {"root": tower, "lift": lift, "accent": accent, "muzzles": muzzles}


func _build_actor(player_index: int) -> void:
	var root := Node3D.new()
	root.name = "P%dFinaleActor" % player_index
	(_towers[player_index].lift as Node3D).add_child(root)
	var hat_id := _state.p1_hat if player_index == 1 else _state.p2_hat
	var parts := EmoteBlockmanPreview.build_player_skeleton(player_index == 1, root, hat_id)
	# Eliminated finalists stay ghosts on the podium (the crown is attached later
	# and keeps its solid gold).
	if _state.is_result_ghost(player_index) and is_instance_valid(_players):
		_players.apply_ghost_look(root, player_index)
	var rest := {}
	for key: Variant in parts:
		if parts[key] is Node3D:
			rest[key] = (parts[key] as Node3D).transform
	_actors[player_index] = {"root": root, "parts": parts, "rest": rest, "hat": hat_id}


## The whole column as one mesh (one surface per material), shared by both towers.
static func tier_column_mesh() -> ArrayMesh:
	if _tier_column != null:
		return _tier_column
	var modules := TIERS_SCENE.instantiate()
	var tier := (modules.find_child("TWR_Tier", true, false) as MeshInstance3D).mesh
	var milestone := (modules.find_child("TWR_TierMilestone", true, false) as MeshInstance3D).mesh
	modules.free()
	var tools := {}
	for index in range(Motion.TIER_COUNT):
		var module := milestone if (index + 1) % MILESTONE_EVERY == 0 else tier
		var place := Transform3D(Basis(), Vector3(0.0, COLUMN_TOP - index * Motion.TIER_HEIGHT, 0.0))
		for surface in range(module.get_surface_count()):
			var material := module.surface_get_material(surface)
			var key := material.resource_name if material != null else ""
			if not tools.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(material)
				tools[key] = tool
			(tools[key] as SurfaceTool).append_from(module, surface, place)
	_tier_column = ArrayMesh.new()
	for key: String in tools:
		(tools[key] as SurfaceTool).commit(_tier_column)
	return _tier_column


## The towers neither cast nor receive shadows: a 10 m column threw a long shadow
## across the stage, and the cast's shadows streaked over the tiers. The stage's own
## overrides (accent, gold) are flagged in place; imported materials get a copy.
static func _disable_shadows(root: Node) -> void:
	var copies := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in range(mesh.mesh.get_surface_count()):
			var override := mesh.get_surface_override_material(surface) as BaseMaterial3D
			if override != null:
				override.disable_receive_shadows = true
				continue
			var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null:
				continue
			if not copies.has(material):
				var copy := material.duplicate() as BaseMaterial3D
				copy.disable_receive_shadows = true
				copies[material] = copy
			mesh.set_surface_override_material(surface, copies[material])


## glTF metal picks up the stadium sky and reads green; use a warm toy gold instead.
static func _apply_gold(root: Node, material_names: Array) -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = GOLD_ALBEDO
	gold.metallic = 0.55
	gold.roughness = 0.32
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.62, 0.12)
	gold.emission_energy_multiplier = 0.22
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			if material != null and material.resource_name in material_names:
				mesh.set_surface_override_material(surface, gold)


## Top of the hat's main body above the mount, so the crown sits on the hat itself.
## The bulkiest mesh decides: small ornaments (pompoms, figures) do not lift the crown.
func _hat_top(mount: Node3D) -> float:
	var best_volume := 0.0
	var top := 0.0
	for node: Node in mount.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or (_crown != null and _crown.is_ancestor_of(mesh)):
			continue
		var to_mount := mount.global_transform.affine_inverse() * mesh.global_transform
		var bounds := AABB()
		var aabb := mesh.get_aabb()
		for corner in range(8):
			var point := to_mount * aabb.get_endpoint(corner)
			bounds = bounds.expand(point) if corner > 0 else AABB(point, Vector3.ZERO)
		var volume := bounds.size.x * bounds.size.y * bounds.size.z
		if volume > best_volume:
			best_volume = volume
			top = bounds.end.y
	return maxf(0.0, top - 0.04)


## Largest deviation of the plush's body bones from rest (its face shares that mesh).
## Determinant of the plush body's drawn transform (negative = drawn mirrored).
func _referee_mesh_determinant() -> float:
	if not is_instance_valid(_referee):
		return 0.0
	var body := _referee.find_child("HERO_GodotPlush", true, false) as Node3D
	return body.global_basis.determinant() if body != null else 0.0


## World positions of the referee's two flag tips (one flag in each hand).
func _referee_flag_tips() -> Array:
	var tips := []
	if is_instance_valid(_referee):
		for knob_name in ["PRP_FlagKnob", "PRP_FlagLKnob"]:
			var knob := _referee.find_child(knob_name, true, false) as Node3D
			if knob != null:
				tips.append(knob.global_position)
	return tips


func referee_body_bend_degrees() -> float:
	if not is_instance_valid(_referee):
		return -1.0
	var skeletons := _referee.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return -1.0
	var skeleton := skeletons[0] as Skeleton3D
	var worst := 0.0
	for bone_name in ["DEF-head", "DEF-hips", "DEF-thigh.L", "DEF-shin.L", "DEF-thigh.R", "DEF-shin.R"]:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var pose := skeleton.get_bone_pose_rotation(bone)
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		worst = maxf(worst, rad_to_deg(pose.angle_to(rest)))
		var scale_error := (skeleton.get_bone_pose_scale(bone) - Vector3.ONE).length()
		worst = maxf(worst, scale_error * 100.0)
	return worst


func update_stage(elapsed: float, stage_origin: Vector3) -> void:
	if not is_built():
		return
	_elapsed = elapsed
	_performance = Motion.performance_time(elapsed)
	var pt := _performance
	visible = true
	transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3(-1, 1, 1) if _winner == 2 else Vector3.ONE), stage_origin)
	for player_index in [1, 2]:
		(_towers[player_index].lift as Node3D).position.y = PAD_CLEARANCE + tower_height(player_index, elapsed if elapsed < Motion.end_time() else Motion.end_time())
		_update_column_visibility(player_index, elapsed)
	_update_cast_visibility(elapsed)
	for player_index in [1, 2]:
		_pose_actor(player_index, pt)
		if _state.sudden_death_pending:
			_calm_actor(player_index, smoothstep(SUDDEN_DEATH_CALM.x, SUDDEN_DEATH_CALM.y, elapsed))
	if elapsed < Motion.CAST_START + HANDOFF:
		_blend_handoff(elapsed)
	# The sudden death whistle (8.4 s) stops the draw dance; both turn to the referee.
	var dance_fade := 1.0
	if _state.sudden_death_pending:
		dance_fade = 1.0 - smoothstep(QuizGameState.SUDDEN_DEATH_BRANCH_TIME, QuizGameState.SUDDEN_DEATH_BRANCH_TIME + 0.35, elapsed)
	for player_index: int in _dances:
		var actor: Dictionary = _actors[player_index]
		var lift := _towers[player_index].lift as Node3D
		(_dances[player_index] as ResultWinnerDance).apply(actor.root, actor.parts, _camera, elapsed, lift.global_position.y, dance_fade)
	if _state.sudden_death_pending:
		_turn_to_referee(smoothstep(QuizGameState.SUDDEN_DEATH_BRANCH_TIME + 0.05, QuizGameState.SUDDEN_DEATH_BRANCH_TIME + 0.55, elapsed))
	_apply_flights()
	if _crown != null:
		var crown_pose := Motion.sample_prop("crown", pt)
		crown_pose.origin.y += _crown_offset
		_crown.transform = crown_pose
		_crown.visible = pt >= Motion.beat("crown_start") - 0.02
	if _state.result_return_hold and _state.sudden_death_winner > 0:
		# Waiting at the verdict: hold the flags low and tremble (the 6.3-6.9 s hush).
		_hold_clock += get_process_delta_time()
		ResultFinaleReferee.pose(_referee_animation, ResultFinaleReferee.animation_for(_winner),
			Motion.beat("hush") + pingpong(_hold_clock, Motion.VERDICT - Motion.beat("hush") - 0.02))
	else:
		_hold_clock = 0.0
		ResultFinaleReferee.pose(_referee_animation, ResultFinaleReferee.animation_for(_winner), pt)
	_update_tower_lights(elapsed)
	_update_effects(elapsed)


## The tier column hangs 10.8 m below the lift. Over the sudden death shaft (open
## floor) a sunk tower would show it inside the shaft, so it is hidden while sunk.
func _update_column_visibility(player_index: int, elapsed: float) -> void:
	var tower: Dictionary = _towers[player_index]
	if not tower.has("column"):
		tower["column"] = (tower.lift as Node3D).find_child("TierColumn", true, false)
	var column := tower.column as Node3D
	if column == null:
		return
	var hidden := false
	if _state.sudden_death_pending:
		hidden = elapsed >= QuizGameState.SUDDEN_DEATH_IRIS_TIME - 0.05
	elif _state.sudden_death_winner > 0 or _state.sudden_death_aborted:
		var riser := _state.sudden_death_aborted or player_index == _state.sudden_death_winner
		hidden = not riser or (_state.result_return_hold and _state.result_return_regrow <= 0.0)
	column.visible = not hidden


## Yaw both finalists (0..1) from the camera toward the referee behind them.
func _turn_to_referee(amount: float) -> void:
	if amount <= 0.0 or not is_instance_valid(_referee):
		return
	var rig := _referee.find_child("RIG_Referee", true, false) as Node3D
	var target := rig.global_position if rig != null else _referee.global_position
	for player_index: int in _actors:
		var root := _actors[player_index].root as Node3D
		var to_referee := target - root.global_position
		if Vector2(to_referee.x, to_referee.z).length() < 0.05:
			continue
		var facing := root.global_basis.z
		var delta := angle_difference(atan2(facing.x, facing.z), atan2(to_referee.x, to_referee.z))
		root.global_basis = Basis(Vector3.UP, delta * amount) * root.global_basis


## Sudden death return: `from` (world) is where the actor comes from (the drain);
## progress 0..1 flies it in a tumbling arc onto its own pad. Negative = hidden.
func set_actor_flight(player_index: int, from: Vector3, progress: float) -> void:
	if progress >= 1.0:
		_flights.erase(player_index)
		_hidden_actors.erase(player_index)
		return
	if progress < 0.0:
		_hidden_actors[player_index] = true
		_flights.erase(player_index)
		return
	_hidden_actors.erase(player_index)
	_flights[player_index] = {"from": from, "progress": progress}


func clear_actor_flights() -> void:
	_flights.clear()
	_hidden_actors.clear()


func _apply_flights() -> void:
	for player_index: int in _hidden_actors:
		if _actors.has(player_index):
			(_actors[player_index].root as Node3D).visible = false
	for player_index: int in _flights:
		if not _actors.has(player_index):
			continue
		var root := _actors[player_index].root as Node3D
		var flight: Dictionary = _flights[player_index]
		var u := clampf(float(flight.progress), 0.0, 1.0)
		var landing := root.global_transform
		var from: Vector3 = flight.from
		var ground := from.lerp(landing.origin, u)
		var peak := maxf(from.y, landing.origin.y) + 5.5
		var arc := 4.0 * u * (1.0 - u) * (peak - lerpf(from.y, landing.origin.y, 0.5))
		# Two tumbles in the air, settling upright for the landing.
		var tumble := Basis(Vector3.RIGHT, -TAU * 2.0 * smoothstep(0.0, 0.92, u) * (1.0 - smoothstep(0.85, 1.0, u)))
		root.global_transform = Transform3D(landing.basis * tumble, ground + Vector3.UP * arc)
		root.visible = true


## Hide the celebration bursts that already happened (the aborted descent resumes
## the draw near its end without firing the cannons again).
func skip_effects_before(elapsed: float) -> void:
	for latch_name in ["confetti", "confetti_rain", "firework_0", "firework_1", "firework_2", "firework_3"]:
		if not _latches.has(latch_name):
			_latches[latch_name] = elapsed


func _update_cast_visibility(elapsed: float) -> void:
	var cast := elapsed >= Motion.CAST_START
	# Capture while the normal walk still owns the live avatars.
	if not cast and _state.result_ceremony_phase == QuizGameState.ResultCeremonyPhase.WALK and is_instance_valid(_players):
		_handoff_poses.clear()
		for player_index in [1, 2]:
			var source: Dictionary = _players.p1_parts if player_index == 1 else _players.p2_parts
			var ghost := _ghost_source(player_index)
			if ghost != null:
				var ghost_parts: Variant = ghost.get_meta("ghost_mount_parts", {})
				if ghost_parts is Dictionary:
					source = ghost_parts
			var pose := {}
			for key: Variant in source:
				if source[key] is Node3D:
					pose[key] = (source[key] as Node3D).global_transform
			_handoff_poses[player_index] = pose
	for player_index in [1, 2]:
		(_actors[player_index].root as Node3D).visible = cast
	if is_instance_valid(_players):
		_players.visible = not cast
	for ghost: Variant in _ghost_sources.values():
		if ghost is Node3D and is_instance_valid(ghost):
			(ghost as Node3D).visible = not cast
	_cast_visible = cast


func _pose_actor(player_index: int, pt: float) -> void:
	var actor: Dictionary = _actors[player_index]
	var parts: Dictionary = actor.parts
	var rest: Dictionary = actor.rest
	var side := side_of(player_index)
	for key: Variant in rest:
		(parts[key] as Node3D).transform = rest[key]
	(actor.root as Node3D).transform = Motion.sample_actor(side, pt)
	for joint: String in Motion.joints():
		var node := parts.get(joint) as Node3D
		if node != null:
			node.quaternion = Motion.sample_joint(side, joint, pt)
	var fists := Motion.sample_fists(side, pt)
	for hand in ["l", "r"]:
		var fist := fists.x if hand == "l" else fists.y
		for finger: String in FINGERS:
			for segment: Array in [["_prox", 88.0], ["_mid", 96.0], ["_dist", 64.0]]:
				var node := parts.get(hand + "_" + finger + segment[0]) as Node3D
				if node != null:
					node.quaternion = (rest[hand + "_" + finger + segment[0]] as Transform3D).basis.get_rotation_quaternion() \
						* Quaternion(Vector3.RIGHT, deg_to_rad(-float(segment[1]) * fist))
		var thumb := parts.get(hand + "_thumb_prox") as Node3D
		if thumb != null:
			thumb.quaternion = (rest[hand + "_thumb_prox"] as Transform3D).basis.get_rotation_quaternion() \
				* Quaternion(Vector3.RIGHT, deg_to_rad(-30.0 * fist))


## Blend every animated joint (0..1) back to the skeleton's rest: arms down, hands open.
func _calm_actor(player_index: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var actor: Dictionary = _actors[player_index]
	var parts: Dictionary = actor.parts
	var rest: Dictionary = actor.rest
	for key: Variant in rest:
		var node := parts.get(key) as Node3D
		if node == null or key == "hat_mount":
			continue
		var still := (rest[key] as Transform3D).basis.get_rotation_quaternion()
		node.quaternion = node.quaternion.slerp(still, amount)


## The finale's referee (the sudden death deck carries a copy of it down the shaft).
func referee_node() -> Node3D:
	return _referee if is_instance_valid(_referee) else null


func _blend_handoff(elapsed: float) -> void:
	if _handoff_poses.size() != 2 or elapsed < Motion.CAST_START:
		return
	var weight := smoothstep(Motion.CAST_START, Motion.CAST_START + HANDOFF, elapsed)
	for player_index in [1, 2]:
		var parts: Dictionary = _actors[player_index].parts
		var target := {}
		for key: Variant in parts:
			if parts[key] is Node3D:
				target[key] = (parts[key] as Node3D).global_transform
		# Hierarchy order: parents are written before their children read them.
		for key: Variant in target:
			if not (_handoff_poses[player_index] as Dictionary).has(key):
				continue
			var start: Transform3D = _handoff_poses[player_index][key]
			var finish: Transform3D = target[key]
			if start.basis.determinant() * finish.basis.determinant() < 0.0:
				start.basis.x = -start.basis.x
			(parts[key] as Node3D).global_transform = start.interpolate_with(finish, weight)


func _latch(name_value: String, when: bool) -> bool:
	if when and not _latches.has(name_value):
		_latches[name_value] = _elapsed
		return true
	return false


func _update_tower_lights(elapsed: float) -> void:
	var t := totals()
	var max_total := maxi(t.x, t.y)
	for player_index in [1, 2]:
		var accent := _towers[player_index].accent as StandardMaterial3D
		var total := t.x if player_index == 1 else t.y
		var energy := ACCENT_ENERGY
		var lock := Motion.lock_time(total, max_total)
		if elapsed >= lock:
			energy += 3.0 * exp(-(elapsed - lock) * 6.0)
		if not _draw and player_index != _winner and elapsed >= Motion.VERDICT:
			energy = lerpf(energy, 0.25, smoothstep(Motion.VERDICT, Motion.VERDICT + 0.35, elapsed))
		elif elapsed >= Motion.VERDICT:
			energy += 1.2 + 0.6 * sin((elapsed - Motion.VERDICT) * 6.0)
		accent.emission_energy_multiplier = energy


func _update_effects(elapsed: float) -> void:
	if _effects == null:
		return
	var palette_for := func(player_index: int) -> Array:
		return [player_color(player_index), ResultFinaleEffects.GOLD, ResultFinaleEffects.WHITE,
			ResultFinaleEffects.PINK, ResultFinaleEffects.MINT]
	if _latch("confetti", elapsed >= Motion.VERDICT + 0.02):
		for player_index in [1, 2]:
			if _draw or player_index == _winner:
				var muzzles: Array[Node3D] = []
				muzzles.assign(_towers[player_index].muzzles)
				_effects.burst_confetti(muzzles, palette_for.call(player_index), elapsed)
	if _latch("confetti_rain", elapsed >= Motion.VERDICT + 0.3):
		# Rain starts above the tallest head.
		var t := totals()
		var centre := to_global(Vector3(0.0 if _draw else -Motion.TOWER_X, maxf(7.5, Motion.stop_height(maxi(t.x, t.y)) + 4.0), 0.3))
		_effects.start_confetti_rain(centre, 11.0 if _draw else 7.0, palette_for.call(_winner if _winner > 0 else 1), elapsed)
	var bursts := [[7.05, Vector3(-4.5, 9.5, -15.0)], [7.55, Vector3(3.0, 11.0, -17.0)],
		[8.25, Vector3(-1.0, 12.0, -18.0)], [9.3, Vector3(5.5, 9.0, -16.0)]]
	for index in range(bursts.size()):
		var when: float = bursts[index][0]
		if _latch("firework_%d" % index, elapsed >= when):
			var color: Color = [ResultFinaleEffects.GOLD, player_color(maxi(_winner, 1)), ResultFinaleEffects.WHITE,
				ResultFinaleEffects.PINK][index]
			_effects.firework(to_global(bursts[index][1]), color, elapsed)
	var spot := smoothstep(Motion.VERDICT - 0.05, Motion.VERDICT + 0.2, elapsed)
	if _draw:
		_effects.set_spotlight(to_global(Vector3(0.0, 0.0, 0.0)) + Vector3.UP * 0.05, 0.0, ResultFinaleEffects.GOLD)
	else:
		var lift := _towers[_winner].lift as Node3D
		_effects.set_spotlight(lift.global_position, spot, Color(1.0, 0.92, 0.72))


func actor_parts(player_index: int) -> Dictionary:
	return _actors.get(player_index, {}).get("parts", {})


## What the goal stand's hotheads throw eggs at: the loser's chest, or the
## referee when a draw leaves nobody to blame.
func egg_target() -> Node3D:
	if not is_built() or not visible:
		return null
	if _draw:
		var rig := _referee.find_child("RIG_Referee", true, false) as Node3D if is_instance_valid(_referee) else null
		return rig if rig != null else _referee
	return actor_parts(3 - _winner).get("spine") as Node3D


func clear() -> void:
	for dance: Variant in _dances.values():
		(dance as ResultWinnerDance).clear()
	_dances.clear()
	for child: Node in get_children():
		child.queue_free()
	_towers.clear()
	_actors.clear()
	_crown = null
	_referee = null
	_referee_animation = null
	_handoff_poses.clear()
	_ghost_sources.clear()
	_latches.clear()
	_flights.clear()
	_hidden_actors.clear()
	_hold_clock = 0.0
	_winner = -1
	_draw = false
	_cast_visible = false
	visible = false
	if is_instance_valid(_players):
		_players.visible = true


func get_debug_snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for player_index: int in _actors:
		var actor: Dictionary = _actors[player_index]
		var parts: Dictionary = actor.parts
		var bounds := Rect2()
		var has_bounds := false
		var lowest := INF
		if is_instance_valid(_camera):
			for node: Node in (actor.root as Node3D).find_children("*", "MeshInstance3D", true, false):
				var mesh := node as MeshInstance3D
				if mesh.mesh == null or not mesh.is_visible_in_tree() or (_crown != null and _crown.is_ancestor_of(mesh)):
					continue
				var aabb := mesh.get_aabb()
				for corner in range(8):
					var world := mesh.global_transform * aabb.get_endpoint(corner)
					lowest = minf(lowest, world.y)
					var screen := _camera.unproject_position(world)
					bounds = bounds.expand(screen) if has_bounds else Rect2(screen, Vector2.ZERO)
					has_bounds = true
		var head := (parts.head as Node3D).global_position
		var ghost_look := false
		for node: Node in (actor.root as Node3D).find_children("*", "MeshInstance3D", true, false):
			var material := (node as MeshInstance3D).material_override as BaseMaterial3D
			if material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				ghost_look = true
				break
		actors.append({"player": player_index, "side": side_of(player_index), "hat": actor.hat,
			"ghost": ghost_look,
			"head_world": head, "head": _camera.unproject_position(head) if is_instance_valid(_camera) else Vector2.ZERO,
			"root_world": (actor.root as Node3D).global_position, "screen_bounds": bounds,
			"lowest": lowest, "platform_y": (_towers[player_index].lift as Node3D).global_position.y,
			"tower_x": (_towers[player_index].root as Node3D).global_position.x,
			"pose": str((parts.spine as Node3D).global_transform) + str((parts.l_hand as Node3D).global_transform)})
	var crown := {}
	if _crown != null:
		var head_top := (_actors[_winner].parts.hat_mount as Node3D).global_position
		crown = {"visible": _crown.visible, "world": _crown.global_position, "above_mount": _crown.global_position.y - head_top.y,
			"offset": _crown_offset, "parent": str(_crown.get_parent().name)}
	var dance_state := {}
	for player_index: int in _dances:
		var dance := _dances[player_index] as ResultWinnerDance
		dance_state[player_index] = {"emote": dance.emote_id, "ready": not dance.clips.is_empty(), "time": dance.sample_time}
	return {"built": is_built(), "visible": visible, "winner": _winner, "draw": _draw, "cast_visible": _cast_visible,
		"elapsed": _elapsed, "performance": _performance,
		"heights": {1: (_towers[1].lift as Node3D).position.y, 2: (_towers[2].lift as Node3D).position.y} if is_built() else {},
		"stage_origin": global_position, "mirrored": global_basis.determinant() < 0.0,
		"actors": actors, "crown": crown, "dances": dance_state,
		"referee_animation": _referee_animation.assigned_animation if is_instance_valid(_referee_animation) else "",
		"referee_time": _referee_animation.current_animation_position if is_instance_valid(_referee_animation) else -1.0,
		"referee_body_bend": referee_body_bend_degrees(),
		"referee_world": _referee.find_child("RIG_Referee", true, false).global_position if is_instance_valid(_referee) and _referee.find_child("RIG_Referee", true, false) != null else Vector3.ZERO,
		# The plush must never render mirrored (it is lit inside out; see ResultFinaleReferee.unmirror).
		"referee_rig_determinant": _referee_mesh_determinant(),
		"referee_flags": _referee_flag_tips(),
		"effects": _effects.events.duplicate(true) if _effects != null else [],
		"particles": _effects.particle_count() if _effects != null else 0}
