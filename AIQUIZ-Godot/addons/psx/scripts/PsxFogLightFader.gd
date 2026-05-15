## Add this to a [Light3D] to automatically handle it fading in and out with fog.
class_name PsxFogLightFader extends Node

## The opacity of fog that must be present in order to enable distance fade culling. 0.0 will always enable (most efficient, but lights will disappear in semi-transparent fog); 1.0 will only enable if the fog is completely opaque (most accurate).
@export var distance_fade_threshold: float = 0.0


@onready var light: Light3D = get_parent()
@onready var light_energy := light.light_energy
var light_energy_prev: float


func _get_configuration_warnings() -> PackedStringArray:
	if get_parent() is not Light3D:
		return ["Parent must be a Light3D."]
	return []


func _ready() -> void:
	if Psx.inst == null:
		var process_mode_prev := process_mode
		process_mode = Node.PROCESS_MODE_DISABLED
		await Psx.await_inst(self )
		process_mode = process_mode_prev

	Psx.inst.fog_changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	if light.distance_fade_enabled: return

	light.light_energy = light_energy * clampf(remap(
		get_viewport().get_camera_3d().global_position.distance_to(light.global_position),
		Psx.fog_near, Psx.fog_far, 1.0, 1.0 - Psx.fog_color.a
	), 0.0, 1.0)


func refresh() -> void:
	light.distance_fade_enabled = Psx.fog_color.a >= distance_fade_threshold
	light.distance_fade_begin = minf(Psx.fog_near, Psx.fog_far)
	light.distance_fade_length = absf(Psx.fog_far - light.distance_fade_begin)

	if light.distance_fade_enabled:
		light.light_energy = light_energy
