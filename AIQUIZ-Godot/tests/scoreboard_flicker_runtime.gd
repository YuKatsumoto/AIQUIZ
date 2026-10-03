extends Node

## Distant-scoreboard shimmer check (rendered, not headless). A camera looks at the
## goal stand from 60 / 120 / 220 / 400 m and drifts sideways 2 cm a frame; the mean
## frame-to-frame luminance change inside the board's screen rect is the flicker
## score. The LED shader is compared with a naive single-tap version of itself and
## with a mipmapped copy of the board (the ideal floor).
## Run: Godot --path . --script tests/scoreboard_flicker_bootstrap.gd

const OUT := "res://artifacts/scoreboard_flicker/"
const DISTANCES := [60.0, 120.0, 220.0, 400.0]
const FRAMES := 40
const NAIVE_CODE := """
shader_type spatial;
uniform sampler2D board : source_color, filter_linear, repeat_disable;
uniform float energy = 2.2;
void fragment() {
	ALBEDO = vec3(0.012);
	ROUGHNESS = 0.28;
	EMISSION = texture(board, UV).rgb * energy;
}
"""

var stand: GoalStand
var state: QuizGameState
var camera: Camera3D
var failures: Array[String] = []
var report := {}


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.72, 0.9)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	stand = GoalStand.new()
	add_child(stand)
	stand.setup("balanced")
	state = QuizGameState.new()
	state.num_players = 2
	state.mode = Constants.MODE_TEN
	state.game_state = Constants.STATE_WAITING_START   # no blinking column while measuring
	for mask in [1, 2, 0, 1, 1, 2]:
		state.record_question_winner(state.question_winners.size(), mask)
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.make_current()
	for i in range(30):
		stand.update_stand(1.0 / 60.0, state, null, camera)
		await get_tree().process_frame
	var led := screen_material()
	var naive := ShaderMaterial.new()
	naive.shader = Shader.new()
	naive.shader.code = NAIVE_CODE
	naive.set_shader_parameter("board", stand.scoreboard.get_texture())
	# Reference: the same board as a mipmapped texture (what ideal filtering looks like).
	var image := stand.scoreboard.get_texture().get_image()
	image.generate_mipmaps()
	var mipped := ShaderMaterial.new()
	mipped.shader = Shader.new()
	mipped.shader.code = NAIVE_CODE.replace("filter_linear,", "filter_linear_mipmap_anisotropic,")
	mipped.set_shader_parameter("board", ImageTexture.create_from_image(image))
	for distance: float in DISTANCES:
		var row := {}
		for entry: Array in [["led", led], ["naive", naive], ["mipmap", mipped]]:
			set_screen_material(entry[1])
			row[entry[0]] = await measure(distance, "%s_%dm" % [entry[0], int(distance)])
		set_screen_material(led)
		row["ratio"] = snappedf(float(row.led) / maxf(float(row.naive), 1e-6), 0.001)
		row["vs_mipmap"] = snappedf(float(row.led) / maxf(float(row.mipmap), 1e-6), 0.001)
		report["%dm" % int(distance)] = row
		# Some change is legitimate (the camera moves); a properly mipmapped copy of the
		# board is the floor. The LED face must stay close to it and below a single tap.
		check(float(row.led) <= float(row.mipmap) * 1.3 + 0.1, "%dm: LED shader filters like a mipmap (%s)" % [int(distance), row])
		check(float(row.led) <= float(row.naive) + 0.05, "%dm: LED shader never shimmers more than a single tap (%s)" % [int(distance), row])
	print("SCOREBOARD_FLICKER " + JSON.stringify({"passed": failures.is_empty(), "failures": failures, "report": report}))
	get_tree().quit(0 if failures.is_empty() else 1)


func screen_material() -> Material:
	for mesh: MeshInstance3D in stand_meshes():
		for surface in range(mesh.get_surface_override_material_count()):
			var material := mesh.get_surface_override_material(surface)
			if material != null and material.resource_name == "GS_Scoreboard":
				return material
	return null


func set_screen_material(material: Material) -> void:
	for mesh: MeshInstance3D in stand_meshes():
		for surface in range(mesh.get_surface_override_material_count()):
			var original := mesh.mesh.surface_get_material(surface)
			if original != null and original.resource_name == "GS_ScoreboardScreen":
				mesh.set_surface_override_material(surface, material)


func stand_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in stand.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	return meshes


func board_center() -> Vector3:
	var board: Dictionary = (stand.get("_layout") as Dictionary).scoreboard
	return stand.global_transform * GoalStand.stand_point(0.0, float(board.screen_y), float(board.screen_z) + float(board.screen_height) * 0.5)


func board_rect() -> Rect2:
	var board: Dictionary = (stand.get("_layout") as Dictionary).scoreboard
	var rect := Rect2()
	var first := true
	for sx in [-0.5, 0.5]:
		for sz in [0.0, 1.0]:
			var p := stand.global_transform * GoalStand.stand_point(sx * float(board.screen_width), float(board.screen_y),
				float(board.screen_z) + sz * float(board.screen_height))
			var s := camera.unproject_position(p)
			rect = Rect2(s, Vector2.ZERO) if first else rect.expand(s)
			first = false
	return rect.grow(-2.0)


## Mean absolute luminance change (0-255) between consecutive frames inside the board.
func measure(distance: float, tag: String) -> float:
	var center := board_center()
	var facing := (stand.global_transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var side := facing.cross(Vector3.UP).normalized()
	var previous: PackedFloat32Array = []
	var total := 0.0
	var samples := 0
	for frame in range(FRAMES):
		camera.global_position = center + facing * distance + Vector3(0.0, 2.0, 0.0) + side * (0.02 * frame)
		camera.look_at(center + side * (0.02 * frame), Vector3.UP)
		stand.update_stand(1.0 / 60.0, state, null, camera)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var rect := board_rect()
		var lum := PackedFloat32Array()
		for y in range(int(rect.position.y), int(rect.end.y)):
			for x in range(int(rect.position.x), int(rect.end.x)):
				var c := image.get_pixel(x, y)
				lum.append((0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0)
		if frame == FRAMES - 1:
			var crop_rect := Rect2i(rect.grow(40.0)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
			image.get_region(crop_rect).save_png(OUT + tag + ".png")
		if previous.size() == lum.size() and frame > 1:
			for i in range(lum.size()):
				total += absf(lum[i] - previous[i])
			samples += lum.size()
		previous = lum
	return snappedf(total / maxf(1.0, float(samples)), 0.001)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
