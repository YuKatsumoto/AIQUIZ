extends Node

## Desktop low used to rebuild the menu with ocean_mobile.gdshader after a
## match, while the pre-play menu still used the stylized transparent ocean.
## That swap plus leftover Window FSR washed the sea to sky-cyan.


func _ready() -> void:
	var failed := false
	if GraphicsQuality.uses_lightweight_ocean(GraphicsQuality.LOW):
		push_error("OCEAN_QUALITY_FAIL desktop low must keep the stylized ocean")
		failed = true
	if GraphicsQuality.uses_lightweight_ocean(GraphicsQuality.BALANCED):
		push_error("OCEAN_QUALITY_FAIL balanced must keep the stylized ocean")
		failed = true

	var balanced := MeshInstance3D.new()
	var low_rebuild := MeshInstance3D.new()
	StageEnvironment.configure_ocean_surface(balanced, GraphicsQuality.BALANCED)
	StageEnvironment.configure_ocean_surface(low_rebuild, GraphicsQuality.LOW)
	StageEnvironment.configure_ocean_surface(balanced, GraphicsQuality.LOW)

	var balanced_shader := _ocean_shader_path(balanced)
	var low_shader := _ocean_shader_path(low_rebuild)
	if balanced_shader != "res://shaders/ocean.gdshader":
		push_error("OCEAN_QUALITY_FAIL low apply kept unexpected shader: " + balanced_shader)
		failed = true
	if low_shader != "res://shaders/ocean.gdshader":
		push_error("OCEAN_QUALITY_FAIL low rebuild used unexpected shader: " + low_shader)
		failed = true

	var window_viewport: Viewport = get_viewport()
	window_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	window_viewport.scaling_3d_scale = 0.70
	GraphicsQuality.reset_window_3d_quality(window_viewport)
	if (
		window_viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR
		or not is_equal_approx(window_viewport.scaling_3d_scale, 1.0)
	):
		push_error("OCEAN_QUALITY_FAIL window 3D quality was not reset")
		failed = true

	balanced.free()
	low_rebuild.free()
	if failed:
		get_tree().quit(1)
		return
	print("OCEAN_QUALITY_PASS desktop low keeps stylized ocean and resets window scaling")
	get_tree().quit(0)


func _ocean_shader_path(ocean: MeshInstance3D) -> String:
	var material := ocean.material_override as ShaderMaterial
	if material == null or material.shader == null:
		return ""
	return material.shader.resource_path
