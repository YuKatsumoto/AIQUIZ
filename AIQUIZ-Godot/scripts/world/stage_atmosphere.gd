@tool
extends RefCounted

## Air, grade and reflections of the surface stage: static fog with aerial perspective,
## a hemispheric ambient, a mild colour grade, one reflection probe and a vignette.
## Everything here is cheap and static: per pixel only the fog maths, one shadowless
## directional light and (gameplay, balanced and up) one blended full-screen quad; the
## probe renders once per stage shown (high and ultra). No SSR, SSIL, volumetric fog,
## SDFGI, lightmaps or compute. Load it with preload (no class_name), and do NOT preload
## graphics_quality.gd from here (that script is loaded by the callers and a cycle would
## break the preload); compare the quality strings "low", "balanced", "high", "ultra".
##
## Callers:
##   - WeatherCycle._apply calls apply_weather() every frame (it rewrites the fog and the
##     ambient light each frame, so anything set only once is overwritten). Keep it cheap:
##     write only the values that changed.
##   - StageEnvironment._setup_environment / apply_graphics_quality call
##     apply_environment_quality() for the values that depend on the quality only.
##   - StageEnvironment.build calls build() once and adds the returned node as a child of
##     the stage (hidden together with the stage during the sudden death); on a quality
##     change it calls apply_graphics_quality().
##
## What is here, and why (measured on the locked midday, sun at the zenith):
##   - Fog: exponential distance fog in the sky's own horizon colour and brightness, so the
##     sea and everything on it fade into the horizon in the same colour the backdrop
##     shader (aiquiz_backdrop.gdshader: islands, city, far sea) hazes the far scenery
##     with. That shader writes FOG itself, which REPLACES the environment fog on its
##     meshes (scene_forward_clustered.glsl: CUSTOM_FOG_USED skips fog_process; checked in
##     the game: the islands do not change with this density), so they keep their own,
##     thinner haze.
##   - Hemisphere: the sun stands at the zenith, so every vertical face (runners' backs,
##     the wall, the doors) is lit by the flat colour ambient alone. A sky-sourced ambient
##     was measured and rejected: this sky's radiance is deep blue overhead and pale teal
##     below, which would tint the floor blue and make undersides warmer. Instead a
##     shadowless directional light shines up from below with negative energy (a ground
##     bounce darker than the sky): faces turned down get darker and cooler, side and up
##     faces keep exactly the old light (verified on a white sphere: side/up unchanged to
##     0.001). It follows the sun's energy, so it goes out at night and in the sudden
##     death descent with the daylight.
##   - Grade: a small contrast lift after the ACES tonemap (saturation untouched), and on
##     the gameplay screen a soft vignette under the HUD.
##   - Probe (OFF by default, see PROBE_ENABLED: +134 MB of VRAM): one box-projected
##     reflection probe over the course (high and ultra), so the course steel reflects the
##     stands, belt and sea instead of the open sky on every face. Only steel that opts in
##     takes it (COURSE_REFLECTION_LAYER): the running rails here, anything else through
##     receive_course_reflections().

const GRADE_SHADER: Shader = preload("res://shaders/ground_grade.gdshader")

const LOW := "low"
const BALANCED := "balanced"
const HIGH := "high"
const ULTRA := "ultra"

## The sky's horizon colours (aiquiz_day_night_sky.tres horizon_day / _sunset / _night),
## used when the environment's sky does not carry them.
const HORIZON_DAY := Color(0.64, 0.88, 1.0)
const HORIZON_SUNSET := Color(1.0, 0.42, 0.16)
const HORIZON_NIGHT := Color(0.075, 0.15, 0.34)

## Fog density (1/m): 1 - exp(-distance * density) of the horizon colour, a clear day at
## sea (visibility about 10 km): the far stands and the goal (100 to 300 m) take 3 to 9 %,
## the open sea fades toward the horizon (1 km 26 %, the ocean plane's edge at 2 km 45 %).
## The backdrop shader's own haze is thinner (1 / haze_distance = 1 / 10000 m) and, as it
## replaces this fog on its meshes, keeps the islands and the city that clear.
const FOG_DENSITY := 0.0003
## Fog brightness relative to the sky's (Environment.background_energy_multiplier).
const FOG_ENERGY_SCALE := 1.0
## Brightening of the fog toward the sun (0 here: the backdrop haze has none, and at the
## zenith sun it would only show when looking straight up).
const FOG_SUN_SCATTER := 0.0

## Post-tonemap grade (applied after ACES, in sRGB around mid grey 0.5).
const GRADE_BRIGHTNESS := 1.0
const GRADE_CONTRAST := 1.04
const GRADE_SATURATION := 1.0

## Ground bounce (see the header): linear energy taken away from faces turned straight
## down, and its colour (warm, so what remains is cooler).
const FILL_ENERGY := 0.16
const FILL_COLOR := Color(1.0, 0.92, 0.72)
## The sun's energy at midday (WeatherCycle: 1.05). The fill scales with sun / this.
const SUN_DAY_ENERGY := 1.05

## Vignette (shaders/ground_grade.gdshader), gameplay screen only, not on low.
const VIGNETTE_LAYER := -20
const VIGNETTE_STRENGTH := 0.18
const VIGNETTE_START := 0.55
const VIGNETTE_END := 1.3
const VIGNETTE_ROUNDNESS := 0.5

## The reflection probe is OFF. Measured on the ground harness (1280x720, high): one probe makes
## the renderer allocate the whole reflection atlas (project reflection_count = 16 slots), +134 MB
## of VRAM for a sheen on the rails only (718 -> 895 MB in total), and the atlas then stays for
## the session. The frame cost is small, the memory is not worth it. Everything below still works:
## set PROBE_ENABLED, or tests set overrides["probe"], to bring it back (for example once the
## cistern shares the slots, or the atlas gets smaller).
const PROBE_ENABLED := false

## Reflection probe over the course (high and ultra). x covers the floor and reaches the
## stands' inner faces (|x| 27.2); y spans the sea surface (-9.2) to above the stand roofs;
## z runs from behind the floor's back end to the stretch the gameplay camera looks at.
const PROBE_HALF_X := 29.0
const PROBE_BOTTOM_Y := -9.2
const PROBE_TOP_Y := 16.0
const PROBE_BACK_Z := -20.0
const PROBE_FRONT_Z := 90.0
## Capture point: over the belt centre, a little above runner height, ahead of the runners.
const PROBE_CAPTURE := Vector3(0.0, 2.0, 14.0)
const PROBE_MAX_DISTANCE := 400.0
const PROBE_BLEND := 4.0
const PROBE_LOD_THRESHOLD := 4.0
## Frames after the stage is shown (or the quality changed) before the probe is captured
## again: the floor length, stands and crowd are settled by then.
const PROBE_CAPTURE_DELAY_FRAMES := 8
## Only the course steel takes the probe's reflections. Everything on the surface is on
## render layer 1, so the probe would otherwise also replace the sky's sheen on the
## runners, the wall and the doors (measured: the runners' darkest channel -11 %). The
## steel opts in by also being on this layer (layers in use: 1 the stage, 11 the cistern
## hall, 19 / 20 the ghost presentation).
const COURSE_REFLECTION_LAYER := 12
const COURSE_REFLECTION_MASK := 1 << (COURSE_REFLECTION_LAYER - 1)
## Children of the stage (StageEnvironment) that are steel and opt in on their own.
const STAGE_STEEL_NODES: PackedStringArray = ["ConveyorRunningRails"]

## Look-development overrides (key -> value, the constant names above in lower case, plus
## "enabled"). Tests set them before the stage is built; the game leaves this empty.
static var overrides: Dictionary = {}

## Environment instance id -> the weather key last applied in full (see apply_weather).
static var _applied: Dictionary = {}


static func _tune(key: StringName, value: Variant) -> Variant:
	if overrides.is_empty():
		return value
	return overrides.get(key, value)


static func _enabled() -> bool:
	return bool(_tune(&"enabled", true))


static func _normalize(quality: String) -> String:
	return quality if quality in [LOW, BALANCED, HIGH, ULTRA] else BALANCED


static func _rank(quality: String) -> int:
	return [LOW, BALANCED, HIGH, ULTRA].find(_normalize(quality))


## Per-frame values driven by the day cycle (fog, hemispheric ambient). `day_amount` and
## `twilight_amount` are the 0..1 values WeatherCycle computes. The ambient itself stays
## WeatherCycle's colour ambient; its hemisphere is the ground-bounce light of build().
##
## WeatherCycle switches the fog off every frame right before this call, so fog_enabled is
## checked every frame. Everything else is written only when its weather key (quality,
## day, twilight) differs from the one last applied to this environment, and then only the
## properties whose value differs. Several environments (game, menu, settings previews)
## are told apart by instance id.
static func apply_weather(env: Environment, day_amount: float, twilight_amount: float, quality: String) -> void:
	if env == null or not _enabled():
		return
	if not env.fog_enabled:
		env.fog_enabled = true
	var key: int = _rank(quality) + 4 * (
		roundi(clampf(day_amount, 0.0, 1.0) * 1000.0)
		+ 1001 * roundi(clampf(twilight_amount, 0.0, 1.0) * 1000.0)
	)
	var id: int = env.get_instance_id()
	if overrides.is_empty() and int(_applied.get(id, -1)) == key:
		# The sky's energy is WeatherCycle's to change; the fog follows it.
		_set_fog_energy(env)
		return
	_apply_fog(env, day_amount, twilight_amount)
	if _applied.size() > 32:
		for stale: int in _applied.keys():
			if not is_instance_id_valid(stale):
				_applied.erase(stale)
	_applied[id] = key


static func _apply_fog(env: Environment, day_amount: float, twilight_amount: float) -> void:
	if env.fog_mode != Environment.FOG_MODE_EXPONENTIAL:
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	var colour: Color = _horizon_colour(env, day_amount, twilight_amount)
	if not env.fog_light_color.is_equal_approx(colour):
		env.fog_light_color = colour
	_set_fog_energy(env)
	_set_float(env, &"fog_density", float(_tune(&"fog_density", FOG_DENSITY)))
	_set_float(env, &"fog_sun_scatter", float(_tune(&"fog_sun_scatter", FOG_SUN_SCATTER)))
	# A constant colour (the sky's horizon) rather than the blurred sky radiance: the
	# radiance mip that aerial perspective reads mixes in the deep blue zenith, which
	# would not match the backdrop haze or the sky at the horizon.
	_set_float(env, &"fog_aerial_perspective", 0.0)
	# The sky stays clear (the haze is in front of it, not on it).
	_set_float(env, &"fog_sky_affect", 0.0)
	_set_float(env, &"fog_height_density", 0.0)


static func _set_fog_energy(env: Environment) -> void:
	_set_float(env, &"fog_light_energy", env.background_energy_multiplier * float(_tune(&"fog_energy_scale", FOG_ENERGY_SCALE)))


static func _set_float(object: Object, property: StringName, value: float) -> void:
	if not is_equal_approx(float(object.get(property)), value):
		object.set(property, value)


## The sky's horizon colour for this sun (the same mix as aiquiz_backdrop.gdshader, with
## the sunset share averaged over the view directions), in sRGB like the Color properties.
static func _horizon_colour(env: Environment, day_amount: float, twilight_amount: float) -> Color:
	var day := HORIZON_DAY
	var sunset := HORIZON_SUNSET
	var night := HORIZON_NIGHT
	var sky_material: ShaderMaterial = null
	if env.sky != null:
		sky_material = env.sky.sky_material as ShaderMaterial
	if sky_material != null:
		var value: Variant = sky_material.get_shader_parameter(&"horizon_day")
		if value is Color:
			day = value
		value = sky_material.get_shader_parameter(&"horizon_sunset")
		if value is Color:
			sunset = value
		value = sky_material.get_shader_parameter(&"horizon_night")
		if value is Color:
			night = value
	var linear: Color = night.srgb_to_linear().lerp(day.srgb_to_linear(), clampf(day_amount, 0.0, 1.0))
	linear = linear.lerp(sunset.srgb_to_linear(), clampf(twilight_amount * 0.55, 0.0, 1.0))
	return Color(linear.linear_to_srgb(), 1.0)


## Values that depend on the quality only (colour adjustment, tonemap).
## The grade is the same on every tier (it costs nothing in the tonemap pass), so the
## look does not change with the quality. The ACES tonemap (white 6) is left as built.
static func apply_environment_quality(env: Environment, _quality: String) -> void:
	if env == null or not _enabled():
		return
	if not env.adjustment_enabled:
		env.adjustment_enabled = true
	_set_float(env, &"adjustment_brightness", float(_tune(&"grade_brightness", GRADE_BRIGHTNESS)))
	_set_float(env, &"adjustment_contrast", float(_tune(&"grade_contrast", GRADE_CONTRAST)))
	_set_float(env, &"adjustment_saturation", float(_tune(&"grade_saturation", GRADE_SATURATION)))


## The nodes of the stage atmosphere (ground bounce light, reflection probe, vignette), or
## null for none. `gameplay` is false for the menu preview. Never called with a vignette in
## the editor (Engine.is_editor_hint()): return null there.
static func build(parent: Node3D, quality: String, gameplay: bool) -> Node3D:
	if Engine.is_editor_hint() or parent == null or not _enabled():
		return null
	var node := AtmosphereNode.new()
	node.name = "StageAtmosphere"
	node.setup(parent, gameplay, _node_parameters())
	node.apply_quality(_normalize(quality), _wants_vignette(quality, gameplay), _wants_probe(quality))
	return node


## Re-applies the quality to the node build() returned.
static func apply_graphics_quality(container: Node3D, quality: String) -> void:
	if container == null or not is_instance_valid(container):
		return
	var node := container as AtmosphereNode
	if node != null:
		node.apply_quality(_normalize(quality), _wants_vignette(quality, node.is_gameplay()), _wants_probe(quality))


## Lets the steel under `root` (rail heads, saw blades, goal trusses...) take the course
## reflection probe (high and ultra): adds COURSE_REFLECTION_LAYER to every
## GeometryInstance3D at and under `root`, keeping their other layers. Returns how many.
## Not for the runners, the wall or the doors (see COURSE_REFLECTION_LAYER).
static func receive_course_reflections(root: Node) -> int:
	return AtmosphereNode.add_reflection_layer(root)


## The vignette is for the gameplay screen, on balanced and up.
static func _wants_vignette(quality: String, gameplay: bool) -> bool:
	return gameplay and _normalize(quality) != LOW


## The probe is for high and ultra, and only while PROBE_ENABLED.
static func _wants_probe(quality: String) -> bool:
	return _rank(quality) >= _rank(HIGH) and bool(_tune(&"probe", PROBE_ENABLED))


## The tuned values the node needs (the inner class cannot call this script's statics).
static func _node_parameters() -> Dictionary:
	return {
		"fill_energy": float(_tune(&"fill_energy", FILL_ENERGY)),
		"fill_color": _tune(&"fill_color", FILL_COLOR) as Color,
		"vignette_strength": float(_tune(&"vignette_strength", VIGNETTE_STRENGTH)),
		"vignette_start": float(_tune(&"vignette_start", VIGNETTE_START)),
		"vignette_end": float(_tune(&"vignette_end", VIGNETTE_END)),
		"vignette_roundness": float(_tune(&"vignette_roundness", VIGNETTE_ROUNDNESS)),
	}


## The container build() returns: the ground-bounce light (every tier), the vignette layer
## (gameplay, balanced and up) and the reflection probe (high and ultra). It keeps the
## vignette's visibility with the stage (a CanvasLayer does not hide with its Node3D
## parent), keeps the bounce in step with the sun, and re-captures the probe a few frames
## after the stage is shown or the quality changes, then stops processing.
class AtmosphereNode extends Node3D:
	var _stage: Node3D = null
	var _quality := BALANCED
	var _gameplay := false
	var _fill: DirectionalLight3D = null
	var _grade_layer: CanvasLayer = null
	var _probe: ReflectionProbe = null
	var _weather: Node = null
	var _sun: DirectionalLight3D = null
	var _capture_in := -1
	var _nudge := 1.0
	var _captures := 0
	var _parameters: Dictionary = {}

	func setup(stage: Node3D, gameplay: bool, parameters: Dictionary) -> void:
		_stage = stage
		_gameplay = gameplay
		_parameters = parameters
		_fill = DirectionalLight3D.new()
		_fill.name = "GroundBounce"
		# DirectionalLight3D shines along -Z: +90 deg about X points it straight up, so
		# it reaches the faces turned down.
		_fill.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_fill.light_color = _parameters.get("fill_color", FILL_COLOR) as Color
		_fill.light_energy = 0.0
		_fill.light_specular = 0.0
		_fill.light_indirect_energy = 0.0
		_fill.light_volumetric_fog_energy = 0.0
		_fill.light_bake_mode = Light3D.BAKE_DISABLED
		_fill.shadow_enabled = false
		_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		# The stage's layer only (not the cistern hall or the ghost presentation layers).
		_fill.light_cull_mask = 1
		add_child(_fill)

	func is_gameplay() -> bool:
		return _gameplay

	func apply_quality(quality: String, want_grade: bool, want_probe: bool) -> void:
		_quality = quality
		if want_grade and _grade_layer == null:
			_grade_layer = _make_grade_layer()
			add_child(_grade_layer)
		elif not want_grade and _grade_layer != null:
			_grade_layer.queue_free()
			_grade_layer = null
		if want_probe and _probe == null:
			_probe = _make_probe()
			add_child(_probe)
		elif not want_probe and _probe != null:
			_probe.queue_free()
			_probe = null
		_sync_grade_visibility()
		_schedule_capture()

	func get_debug() -> Dictionary:
		return {
			"quality": _quality,
			"gameplay": _gameplay,
			"fill_energy": _fill.light_energy if _fill != null else 0.0,
			"vignette": _grade_layer != null,
			"vignette_visible": _grade_layer.visible if _grade_layer != null else false,
			"probe": _probe != null,
			"probe_captures": _captures,
		}

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_READY:
				_connect_weather()
				_sync_grade_visibility()
				_schedule_capture()
			NOTIFICATION_VISIBILITY_CHANGED:
				_sync_grade_visibility()
				if is_visible_in_tree():
					_schedule_capture()
			NOTIFICATION_EXIT_TREE:
				_disconnect_weather()

	func _process(_delta: float) -> void:
		if _capture_in < 0:
			set_process(false)
			return
		if not is_visible_in_tree():
			return
		_capture_in -= 1
		if _capture_in > 0:
			return
		_capture_in = -1
		set_process(false)
		if _probe != null:
			_fit_probe()
			_opt_in_stage_steel()
			if not _probe.visible:
				# First capture: the probe waited hidden for the stage to settle.
				_probe.visible = true
			else:
				# UPDATE_ONCE renders again when the probe moves: a sub-millimetre nudge.
				_nudge = -_nudge
				_probe.position.x = 0.0005 * _nudge
			_captures += 1

	func _schedule_capture() -> void:
		if _probe == null or not is_inside_tree():
			return
		_capture_in = PROBE_CAPTURE_DELAY_FRAMES
		set_process(true)

	## A CanvasLayer is not hidden by a hidden Node3D parent: follow the stage by hand.
	func _sync_grade_visibility() -> void:
		if _grade_layer != null:
			_grade_layer.visible = is_inside_tree() and is_visible_in_tree()

	func _connect_weather() -> void:
		if _stage == null:
			return
		_sun = _stage.get("directional_light") as DirectionalLight3D
		_weather = _stage.get("weather_cycle") as Node
		if _weather != null and _weather.has_signal(&"night_amount_changed"):
			if not _weather.is_connected(&"night_amount_changed", _on_weather):
				_weather.connect(&"night_amount_changed", _on_weather)
		_on_weather(0.0)

	func _disconnect_weather() -> void:
		if is_instance_valid(_weather) and _weather.is_connected(&"night_amount_changed", _on_weather):
			_weather.disconnect(&"night_amount_changed", _on_weather)
		_weather = null

	## The bounce is sunlight off the belt and the sea: it scales with the sun (night,
	## and the sudden death descent fading the daylight, take it away with the sun).
	func _on_weather(_night_amount: float) -> void:
		if _fill == null:
			return
		var sun_scale := 1.0
		if is_instance_valid(_sun):
			sun_scale = clampf(_sun.light_energy / SUN_DAY_ENERGY, 0.0, 1.0)
		var energy: float = -float(_parameters.get("fill_energy", FILL_ENERGY)) * sun_scale
		if not is_equal_approx(_fill.light_energy, energy):
			_fill.light_energy = energy
		var on: bool = energy < -0.0001
		if _fill.visible != on:
			_fill.visible = on

	func _make_grade_layer() -> CanvasLayer:
		var layer := CanvasLayer.new()
		layer.name = "Grade"
		layer.layer = VIGNETTE_LAYER
		layer.set_meta(&"stage_atmosphere_vignette", true)
		var material := ShaderMaterial.new()
		material.shader = GRADE_SHADER
		material.set_shader_parameter(&"strength", float(_parameters.get("vignette_strength", VIGNETTE_STRENGTH)))
		material.set_shader_parameter(&"start", float(_parameters.get("vignette_start", VIGNETTE_START)))
		material.set_shader_parameter(&"end", float(_parameters.get("vignette_end", VIGNETTE_END)))
		material.set_shader_parameter(&"roundness", float(_parameters.get("vignette_roundness", VIGNETTE_ROUNDNESS)))
		var overlay := ColorRect.new()
		overlay.name = "Vignette"
		overlay.material = material
		overlay.color = Color.WHITE
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(overlay)
		return layer

	func _make_probe() -> ReflectionProbe:
		var probe := ReflectionProbe.new()
		probe.name = "CourseProbe"
		probe.box_projection = true
		# Outdoors: the sky is part of what the steel reflects.
		probe.interior = false
		probe.enable_shadows = false
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.max_distance = PROBE_MAX_DISTANCE
		probe.blend_distance = PROBE_BLEND
		probe.intensity = 1.0
		probe.mesh_lod_threshold = PROBE_LOD_THRESHOLD
		# Captures the stage (layer 1: not the cistern hall or the ghost presentation layers)
		# and lights only the opted-in steel.
		probe.cull_mask = 1
		probe.reflection_mask = COURSE_REFLECTION_MASK
		# Hidden until the first scheduled capture, so it does not render once on entering
		# the tree and again a few frames later.
		probe.visible = false
		_fit_probe_to(probe)
		return probe

	func _opt_in_stage_steel() -> void:
		if _stage == null:
			return
		for node_name: String in STAGE_STEEL_NODES:
			var steel := _stage.get_node_or_null(NodePath(node_name))
			if steel != null:
				add_reflection_layer(steel)

	static func add_reflection_layer(root: Node) -> int:
		if root == null:
			return 0
		var count := 0
		var nodes: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
		if root is GeometryInstance3D:
			nodes.append(root)
		for node: Node in nodes:
			var geometry := node as GeometryInstance3D
			if geometry.layers & COURSE_REFLECTION_MASK == 0:
				geometry.layers |= COURSE_REFLECTION_MASK
			count += 1
		return count

	func _fit_probe() -> void:
		if _probe != null:
			_fit_probe_to(_probe)

	## The box over the course: from behind the floor's back end to PROBE_FRONT_Z (or the
	## floor front, if nearer), capture point PROBE_CAPTURE.
	func _fit_probe_to(probe: ReflectionProbe) -> void:
		var back_z: float = PROBE_BACK_Z
		var front_z: float = PROBE_FRONT_Z
		if _stage != null and _stage.has_method("get_floor_center_z") and _stage.has_method("get_floor_length"):
			var center: float = float(_stage.call("get_floor_center_z"))
			var length: float = float(_stage.call("get_floor_length"))
			back_z = minf(back_z, center - length * 0.5 - 4.0)
			front_z = clampf(center + length * 0.5 + 4.0, back_z + 40.0, front_z)
		var size := Vector3(PROBE_HALF_X * 2.0, PROBE_TOP_Y - PROBE_BOTTOM_Y, front_z - back_z)
		var middle := Vector3(0.0, (PROBE_TOP_Y + PROBE_BOTTOM_Y) * 0.5, (front_z + back_z) * 0.5)
		probe.size = size
		probe.position = Vector3(probe.position.x, middle.y, middle.z)
		var capture := PROBE_CAPTURE
		capture.z = clampf(capture.z, back_z + 1.0, front_z - 1.0)
		probe.origin_offset = capture - middle
