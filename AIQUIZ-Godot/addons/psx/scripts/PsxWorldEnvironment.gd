@tool class_name PsxWorldEnvironment extends WorldEnvironment


func _process(delta: float) -> void:
	var psx_fog_color = environment.fog_light_color if environment.fog_enabled else Color.TRANSPARENT
	psx_fog_color.a *= environment.fog_density

	Psx.fog_color = psx_fog_color
	Psx.fog_near = environment.fog_depth_begin
	Psx.fog_far = environment.fog_depth_end
