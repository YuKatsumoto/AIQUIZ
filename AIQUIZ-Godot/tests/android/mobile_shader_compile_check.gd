extends Node

## Draws every shaders/mobile/*.gdshader on a mesh in a SubViewport for a few frames, so the
## renderer compiles them (a .gdshader only reports compile errors once a material uses it).
## Needs a GPU, so not headless. Run with the Mobile renderer and look for "SHADER ERROR":
##   Godot --path . --rendering-method mobile --resolution 320x180 \
##     res://tests/android/mobile_shader_compile_check.tscn

const SHADERS := {
	"res://shaders/mobile/chair_rocket_smoke_mobile.gdshader": "quad",
	"res://shaders/mobile/menu_heli_shock_ring_mobile.gdshader": "quad",
	"res://shaders/mobile/cistern_column_mobile.gdshader": "cylinder",
}
const FRAMES := 12

var _frames := 0
var _viewport: SubViewport


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 144)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 6.0)
	_viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.7, 0.4, 0.0)
	_viewport.add_child(light)
	var x := -2.5
	for path: String in SHADERS.keys():
		var shader := load(path) as Shader
		if shader == null:
			print("MOBILE_SHADER_LOAD_FAIL ", path)
			continue
		var material := ShaderMaterial.new()
		material.shader = shader
		var mesh_instance := MeshInstance3D.new()
		if String(SHADERS[path]) == "cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.2
			cylinder.bottom_radius = 1.0
			mesh_instance.mesh = cylinder
			material.set_shader_parameter("column_foot_y", -1.0)
		else:
			mesh_instance.mesh = QuadMesh.new()
		mesh_instance.material_override = material
		mesh_instance.position = Vector3(x, 0.0, 0.0)
		x += 2.5
		_viewport.add_child(mesh_instance)
	# Show the result too, so the window is not blank when someone watches the run.
	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	add_child(view)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < FRAMES:
		return
	print(
		"MOBILE_SHADER_CHECK frames=%d method=%s shaders=%d"
		% [
			_frames,
			RenderingServer.get_current_rendering_method(),
			SHADERS.size(),
		]
	)
	get_tree().quit(0)
