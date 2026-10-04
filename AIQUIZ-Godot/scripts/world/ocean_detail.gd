@tool
extends RefCounted

## Quality and sun hooks of the desktop ocean shader (shaders/ocean.gdshader): Fresnel
## horizon colour, sun glints and contact foam. StageEnvironment.configure_ocean_surface
## calls configure() on every new desktop ocean material; WeatherCycle calls set_sun()
## when the sun direction changes. The mobile ocean never goes through here.
##
## Load it with preload (no class_name):
##   const OceanDetailScript = preload("res://scripts/world/ocean_detail.gd")
##
## Everything is arithmetic in the shader (no texture read is added): the reflection is the
## sky's own zenith-to-horizon gradient, not the sky radiance (SubViewports stay safe).
## Low keeps the former plain water; balanced adds the reflection, four ripple waves, glints
## and single-octave foam; high and ultra six ripple waves, brighter glints and finer foam.

## Per quality: the shader uniforms configure() writes.
const SETTINGS := {
	"low": {
		"fresnel_strength": 0.0,
		"ripple_waves": 0,
		"glint_strength": 0.0,
		"foam_strength": 0.0,
		"foam_octaves": 1,
	},
	"balanced": {
		"fresnel_strength": 0.6,
		"fresnel_power": 7.0,
		"ripple_waves": 4,
		"ripple_slope": 0.5,
		"ripple_fresnel": 0.5,
		"reflect_near_share": 0.3,
		"reflect_far_start": 150.0,
		"reflect_far_end": 1000.0,
		"glint_strength": 1.0,
		"glint_density": 0.2,
		"glint_spread": 0.5,
		"glint_cell_pixels": 3.0,
		"glint_level_fade": 0.35,
		"glint_level_gain": 2.0,
		"glint_max_chance": 0.2,
		"foam_strength": 0.7,
		"foam_octaves": 1,
	},
	"high": {
		"fresnel_strength": 0.65,
		"fresnel_power": 7.0,
		"ripple_waves": 6,
		"ripple_slope": 0.5,
		"ripple_fresnel": 0.5,
		"reflect_near_share": 0.3,
		"reflect_far_start": 150.0,
		"reflect_far_end": 1000.0,
		"glint_strength": 1.25,
		"glint_density": 0.2,
		"glint_spread": 0.5,
		"glint_cell_pixels": 3.0,
		"glint_level_fade": 0.35,
		"glint_level_gain": 2.0,
		"glint_max_chance": 0.2,
		"foam_strength": 0.8,
		"foam_octaves": 2,
	},
	"ultra": {
		"fresnel_strength": 0.65,
		"fresnel_power": 7.0,
		"ripple_waves": 6,
		"ripple_slope": 0.5,
		"ripple_fresnel": 0.5,
		"reflect_near_share": 0.3,
		"reflect_far_start": 150.0,
		"reflect_far_end": 1000.0,
		"glint_strength": 1.25,
		"glint_density": 0.2,
		"glint_spread": 0.5,
		"glint_cell_pixels": 3.0,
		"glint_level_fade": 0.35,
		"glint_level_gain": 2.0,
		"glint_max_chance": 0.2,
		"foam_strength": 0.8,
		"foam_octaves": 2,
	},
}

## Sky colours of assets/environment/sky/aiquiz_day_night_sky.tres (sRGB, as written there).
const SKY_DAY := Color(0.08, 0.48, 0.98)
const SKY_SUNSET := Color(0.11, 0.24, 0.58)
const SKY_NIGHT := Color(0.018, 0.055, 0.16)
const HORIZON_DAY := Color(0.64, 0.88, 1.0)
const HORIZON_SUNSET := Color(1.0, 0.42, 0.16)
const HORIZON_NIGHT := Color(0.075, 0.15, 0.34)
## The sky shader's sunset_amount_exponent.
const SUNSET_EXPONENT := 1.15
## The upper sky the steep reflections see is broken by the sky's clouds; this share of
## the horizon colour softens its deep blue (and the stripes of the ripples with it).
const ZENITH_CLOUD_SOFTEN := 0.3


## Sets the per-quality uniforms of `material` (an ocean.gdshader material).
static func configure(material: ShaderMaterial, quality: String) -> void:
	if material == null:
		return
	var values: Dictionary = SETTINGS.get(quality, SETTINGS["balanced"])
	for parameter: String in values:
		material.set_shader_parameter(parameter, values[parameter])


## Gives `material` the direction toward the sun (world space, normalized). May be null.
## Also hands over the sky colours the reflection uses, mixed for that sun the way the
## sky shader mixes them (day / sunset / night) and scaled like WeatherCycle scales the
## sky's energy, so the sea reflects the sky that is drawn behind it.
static func set_sun(material: ShaderMaterial, sun_direction: Vector3) -> void:
	if material == null:
		return
	var sun: Vector3 = sun_direction.normalized() if sun_direction.length_squared() > 0.000001 else Vector3.UP
	var elevation: float = sun.y
	var day_amount: float = smoothstep(-0.16, 0.28, elevation)
	var twilight: float = pow(clampf(exp(-pow(absf(elevation) / 0.23, 2.0)), 0.0, 1.0), SUNSET_EXPONENT)
	var energy: float = maxf(lerpf(0.74, 0.98, day_amount), exp(-pow(absf(elevation) / 0.23, 2.0)) * 0.86)
	# The sky shader mixes its source_color uniforms in linear space.
	var zenith: Color = SKY_NIGHT.srgb_to_linear().lerp(SKY_DAY.srgb_to_linear(), day_amount)
	zenith = zenith.lerp(SKY_SUNSET.srgb_to_linear(), twilight * 0.14)
	var horizon: Color = HORIZON_NIGHT.srgb_to_linear().lerp(HORIZON_DAY.srgb_to_linear(), day_amount)
	var horizon_away: Color = horizon.lerp(HORIZON_SUNSET.srgb_to_linear(), clampf(twilight * 0.28, 0.0, 1.0))
	var horizon_sun: Color = horizon.lerp(HORIZON_SUNSET.srgb_to_linear(), clampf(twilight, 0.0, 1.0))
	zenith = zenith.lerp(horizon_away, ZENITH_CLOUD_SOFTEN)
	material.set_shader_parameter("sun_direction", sun)
	# With the sun high, a shadow on the water means something overhead (a deck, a stand)
	# that also hides the sky from the reflection; a low sun's long shadows do not.
	material.set_shader_parameter("reflect_occlusion", smoothstep(0.35, 0.85, elevation))
	material.set_shader_parameter("reflect_zenith", _rgb(zenith) * energy)
	material.set_shader_parameter("reflect_horizon", _rgb(horizon_away) * energy)
	material.set_shader_parameter("reflect_horizon_sun", _rgb(horizon_sun) * energy)


static func _rgb(colour: Color) -> Vector3:
	return Vector3(colour.r, colour.g, colour.b)
