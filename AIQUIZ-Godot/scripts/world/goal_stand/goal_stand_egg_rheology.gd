class_name GoalStandEggRheology
extends RefCounted

## Raw egg as a material, for the goal stand's cartoon-sized eggs (GoalStandEggs).
##
## The thrown egg is about S = 5.6 times a real one (0.32 m long against 0.057 m),
## but it falls under real gravity. So that it still moves like a real egg filmed up
## close, every constant is carried over by Froude and Bond similarity: speeds and
## times grow with sqrt(S), kinematic viscosity with S^1.5, surface tension over
## density with S^2, yield stress over density with S and volumes with S^3. The
## real values (comments) are orders of magnitude from the egg rheology literature.
##
## Pure data and functions: no nodes, so the models can be checked headless.

const GRAVITY := 9.8
const REAL_EGG_LENGTH := 0.057
## A real large egg: 33 ml of white (43 % thin, watery albumen; 57 % thick gel), 17 ml of yolk.
const REAL_WHITE_VOLUME := 3.3e-5
const THIN_SHARE := 0.43
const REAL_YOLK_VOLUME := 1.7e-5
## Thin albumen: about 3 mPa s, nearly Newtonian (m^2/s).
const REAL_THIN_NU := 3.0e-6
## Thick albumen: zero-shear viscosity about 2 Pa s, a weak gel (m^2/s), relaxation (s).
const REAL_THICK_NU := 2.0e-3
const REAL_THICK_RELAXATION := 0.5
## Yolk contents: about 1 Pa s.
const REAL_YOLK_NU := 1.0e-3
## Protein-laden surface tension, about 48 mN/m, over the density (m^3/s^2).
const REAL_GAMMA_RHO := 4.6e-5
## Thin albumen does not run freely: its contact line pins on the surface.
const FILM_PINNING := 0.12
## Thick albumen holds on a wall until its dome is this thin (real m); it thins as it creeps.
const REAL_THICK_HOLD := 0.0062
const REAL_THICK_CREEP_RUN := 0.027
## The yolk membrane: wobble frequency (real Hz) and damping ratio.
const REAL_YOLK_WOBBLE_HZ := 7.6
const YOLK_DAMPING_RATIO := 0.4
## Height over width of a yolk resting on a flat plate.
const YOLK_REST_ASPECT := 0.58
## Harkins-Brown correction of Tate's law for a drop hanging off an edge.
const TATE_FACTOR := 0.6

var scale := 1.0
var time_scale := 1.0
var white_volume := 0.0
var thin_volume := 0.0
var thick_volume := 0.0
var yolk_volume := 0.0
var yolk_radius := 0.0
var thin_nu := 0.0
var thick_nu := 0.0
var thick_relaxation := 0.0
var yolk_nu := 0.0
var gamma_rho := 0.0
var capillary_length := 0.0
var thick_hold := 0.0
var thick_creep_run := 0.0
var yolk_omega := 0.0


func _init(egg_scale: float = 5.6) -> void:
	scale = egg_scale
	time_scale = sqrt(scale)
	var volume := pow(scale, 3.0)
	white_volume = REAL_WHITE_VOLUME * volume
	thin_volume = white_volume * THIN_SHARE
	thick_volume = white_volume - thin_volume
	yolk_volume = REAL_YOLK_VOLUME * volume
	yolk_radius = pow(3.0 * yolk_volume / (4.0 * PI), 1.0 / 3.0)
	thin_nu = REAL_THIN_NU * pow(scale, 1.5)
	thick_nu = REAL_THICK_NU * pow(scale, 1.5)
	thick_relaxation = REAL_THICK_RELAXATION * time_scale
	yolk_nu = REAL_YOLK_NU * pow(scale, 1.5)
	gamma_rho = REAL_GAMMA_RHO * scale * scale
	capillary_length = sqrt(gamma_rho / GRAVITY)
	thick_hold = REAL_THICK_HOLD * scale
	thick_creep_run = REAL_THICK_CREEP_RUN * scale
	yolk_omega = TAU * REAL_YOLK_WOBBLE_HZ / time_scale


## Scale of an egg whose longest side is `length` (m) against a real one.
static func scale_for_length(length: float) -> float:
	return maxf(length, 0.001) / REAL_EGG_LENGTH


## Speed of a thin film of height `h` running down a slope (Nusselt film), slowed by
## its pinned contact line.
func film_speed(h: float, sin_theta: float) -> float:
	return FILM_PINNING * GRAVITY * maxf(sin_theta, 0.0) * h * h / (3.0 * thin_nu)


## Creep of the thick albumen dome (Bingham-like): it holds while its weight along
## the slope is under the gel's hold, then flows slowly.
func thick_creep_speed(h: float, sin_theta: float) -> float:
	var excess := GRAVITY * maxf(sin_theta, 0.0) * (h - thick_hold)
	return maxf(excess, 0.0) * h / (3.0 * thick_nu)


## Volume of the drop that tears off an edge of radius `r` (Tate's law).
func tate_volume(r: float) -> float:
	return TATE_FACTOR * TAU * r * gamma_rho / GRAVITY


## Height of a thin albumen puddle at rest (two capillary lengths, about 60 degrees).
func puddle_height() -> float:
	return capillary_length * 0.95


## Viscous thread under a hanging weight: length grows exponentially, and the
## radius thins as the thread keeps its volume.
static func thread_length(l0: float, t: float, tau: float) -> float:
	return l0 * exp(maxf(t, 0.0) / maxf(tau, 0.001))


static func thread_radius(a0: float, l0: float, length: float) -> float:
	return a0 * sqrt(l0 / maxf(length, l0))


## One semi-implicit step of a damped oscillator around `target`. Returns (x, v).
static func oscillator_step(x: float, v: float, target: float, omega: float, zeta: float, dt: float) -> Vector2:
	v += (-omega * omega * (x - target) - 2.0 * zeta * omega * v) * dt
	return Vector2(x + v * dt, v)


## Radius of a sphere of volume `v`.
static func sphere_radius(v: float) -> float:
	return pow(3.0 * maxf(v, 0.0) / (4.0 * PI), 1.0 / 3.0)


## Volume of the domed puddle the shader draws: radius `r`, peak height `h`.
static func dome_volume(r: float, h: float) -> float:
	return 0.45 * PI * r * r * h
