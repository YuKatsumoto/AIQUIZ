extends Node3D
class_name SawOperatorPresentation

## Presentation only. One evaluated sample drives the v3 console (sticks, pedals, key,
## guarded START, horn, dial, gauges, lamps, LED bars, beacon) and the plush's hands,
## feet, head and body, so every pose follows state/replay time, never frame history.
## saw_operator.glb supplies the flying seat, plush rig, chair-launch kit and dock mount;
## godot_console_v3.glb (tools/saw_operator/build_console_v3.py) supplies the deck,
## pods, dash and every control.
const ASSET := "res://assets/hazards/saw_operator/saw_operator.glb"
const CONSOLE_ASSET := "res://assets/hazards/saw_operator/godot_console_v3.glb"
const KEEP_FROM_SEAT_ASSET := ["OP_SeatFlightRoot", "OP_MountFrame", "OP_SeatSocket"]
const HORN_STREAM := preload("res://assets/hazards/saw_operator/console_horn.wav")
const SWITCH_STREAM := preload("res://assets/hazards/saw_operator/console_switch.wav")
const MOUNT := Vector3(10.70, 0.0, 0.0) # Stowed above the left end; slides onto its end bracket.
const FACING_YAW := -PI / 2.0 # Face across the blade row toward its right end.
const EXTENSION := 2.25
const SUPPORT_OFFSET := 1.42 # Fixed to the existing outboard spine at X=12.12.
const FLOOR_DROP := 0.628274 # Deck top .97 aligns with the resting blade underside .341726.
const DRIVE_THROW := .30 # DRIVE stick tilts toward the travel side: forward travel is the operator's left.
const LIFT_THROW := .30 # BLADE stick: pull back to raise, push to lower.
const CHASE_CYCLE := 7.2
const IDLE_SLOT := 6.5
enum Idle { LOOK, STRETCH, DRUM, SWING, DOZE, WAVE }
## Waiting vignettes in a fixed, non-repeating order (first slot is a calm look-around).
const IDLE_ORDER := [Idle.LOOK, Idle.DRUM, Idle.STRETCH, Idle.DOZE, Idle.SWING, Idle.WAVE,
	Idle.LOOK, Idle.SWING, Idle.DRUM, Idle.WAVE, Idle.STRETCH, Idle.DOZE]
## Running routine per 7.2s cycle: gauge check / hunt left / lift check, then dial / groove / none.
const CHECK_ORDER := [0, 1, 2, 1, 0, 2, 2, 0, 1]
const EXTRA_ORDER := [0, 1, 2, 0, 2, 1, 1, 0, 2]
## Menu stow (wall speed tab) on the stow clock p: STOW on the BLADE stick, watch the rack rise,
## duck while it passes overhead, look back as it parks behind the deck, nod at the lock.
const STOW_REST_FADE := .6 # p span over which the stowed-rest vignettes fade in and out
const RACK_UP := Vector3(.3,2.4,2.2)
const OVERHEAD := Vector3(0.0,2.9,.5)
const BEHIND := Vector3(1.6,1.3,-1.6)
const START_HANDS_DONE := 2.30 # Both hands back on the sticks after the start routine.
const WORK_START := 2.6
const CATCH_SECONDS := 2.4
const STOP_SECONDS := 2.0
const BODY_PIVOT := Vector3(0.0,.55,0.0) # Seat contact; the plush body rocks around it.
const EYE := Vector3(0.0,1.0,.15)
const AHEAD := Vector3(0.0,1.15,3.0)
const TRAVEL_SIDE := Vector3(2.6,.95,1.4) # Skeleton space: forward travel and the players are to the left.
const CAMERA_SIDE := Vector3(1.4,1.35,3.0)
const FLOOR := Vector3(0.0,.15,1.1)
const BODY_BONES := ["DEF-head","DEF-hips","DEF-upper_arm.L","DEF-forearm.L","DEF-hand.L","DEF-upper_arm.R","DEF-forearm.R","DEF-hand.R"]
## Hand anchors relative to the (swaying) shoulder, skeleton space; all inside the short reach.
const PUMP := Vector3(.12,.20,.08)
const STRETCH := Vector3(.05,.24,.0)
const WAVE := Vector3(.12,.18,.12)
const COVER := Vector3(-.06,.20,.06) # Hand on the crown while ducking under the rack.
const LAMP_COLORS := {
	"V3_LampGreen": Color(.15,1.0,.35), "V3_LampAmber": Color(1.0,.55,.06),
	"V3_LampRed": Color(1.0,.10,.05), "V3_LampBlue": Color(.25,.62,1.0), "V3_BeaconLens": Color(1.0,.50,.05),
}
const LAMPS := ["Power","Ready","Saw","Lift","Warn","Fwd","Rev","Up","Down"]
var station: Node3D
var console: Node3D
var skeleton: Skeleton3D
var controls: Dictionary = {}
var rest: Dictionary = {}
var bones: Dictionary = {}
var bone_rest: Dictionary = {}
var rails: Array[MeshInstance3D] = []
var last_sample: Dictionary = {}
var contact_errors: Dictionary = {}
var seat_transfer: SeatLaunchPresentation
## Set by the chair transfer while it owns the pose; fades the body motion out.
var body_weight := 1.0
## The controller enables sounds only for forward, non-replay time.
var audio_enabled := false
var horn_count := 0
var switch_count := 0
var _body := Transform3D.IDENTITY
var _lamps: Dictionary = {} # owner node name -> Array[StandardMaterial3D]
var _horn: AudioStreamPlayer3D
var _switch: AudioStreamPlayer3D

func _ready() -> void:
	station = (load(ASSET) as PackedScene).instantiate()
	add_child(station)
	# The seat asset still carries the v2 console; only the chair, rig and dock mount stay.
	var holder := station.find_child("OP_SeatFlightRoot", true, false).get_parent()
	for child: Node in holder.get_children():
		if str(child.name) not in KEEP_FROM_SEAT_ASSET:
			holder.remove_child(child)
			child.free()
	console = (load(CONSOLE_ASSET) as PackedScene).instantiate()
	console.name = "ConsoleV3Asset"
	holder.add_child(console)
	GraphicsQuality.drop_tiny_shadow_casters(console)
	position = MOUNT
	rotation.y = FACING_YAW
	skeleton = station.find_child("Skeleton3D", true, false) as Skeleton3D
	for item: Node in station.find_children("OP_*", "Node3D", true, false):
		if item is MeshInstance3D: continue
		controls[str(item.name)] = item
		rest[str(item.name)] = (item as Node3D).transform
	if skeleton != null:
		for index in skeleton.get_bone_count():
			var key := str(skeleton.get_bone_name(index))
			bones[key] = index
			bone_rest[key] = skeleton.get_bone_global_rest(index)
	_collect_lamps()
	_horn = _sound(HORN_STREAM, "OP_Horn", -6.0)
	_switch = _sound(SWITCH_STREAM, "OP_Start", -8.0)
	_build_support()
	apply_sample(sample(0.0, 0.0, 0.0, 0.0, false))
	seat_transfer = preload("res://scripts/world/seat_launch_presentation.gd").new()
	seat_transfer.name = "ChairTransfer"
	add_child(seat_transfer)
	seat_transfer.setup(self)

func _build_support() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(.30,.35,.39)
	steel.metallic = .8
	steel.roughness = .32
	for x in [-.32,.32]:
		var rail := MeshInstance3D.new()
		rail.name = "TelescopingSupportL" if x > 0.0 else "TelescopingSupportR"
		var box := BoxMesh.new()
		box.size = Vector3(.10,.16,1.0)
		rail.mesh = box
		rail.material_override = steel
		add_child(rail)
		rail.position = Vector3(x,.78,-.35)
		rails.append(rail)

func _collect_lamps() -> void:
	# Each lamp, LED segment and the beacon dome gets its own emissive material instance.
	for node: Node in console.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(surface) as StandardMaterial3D
			if source == null or not LAMP_COLORS.has(source.resource_name): continue
			var lit := source.duplicate() as StandardMaterial3D
			lit.emission_enabled = true
			lit.emission = LAMP_COLORS[source.resource_name]
			lit.emission_energy_multiplier = 0.0
			mesh_node.set_surface_override_material(surface, lit)
			var owner_name := str(mesh_node.get_parent().name)
			if not _lamps.has(owner_name): _lamps[owner_name] = []
			(_lamps[owner_name] as Array).append(lit)

func _sound(stream: AudioStream, at: String, volume: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	player.unit_size = 10.0
	player.volume_db = volume
	player.max_polyphony = 2
	var node := controls.get(at) as Node3D
	(node if node != null else self).add_child(player)
	return player

# ---------------------------------------------------------------- evaluation helpers
static func blend(a: float, b: float, value: float) -> float:
	return smoothstep(a,b,value)

## Rises over a..b, holds, falls over c..d. Continuous, zero outside a..d.
static func window(a: float, b: float, c: float, d: float, value: float) -> float:
	return blend(a,b,value) - blend(c,d,value)

## Zero at both ends of a..b, one at its middle: a lifted arc between contacts.
static func arc(a: float, b: float, value: float) -> float:
	return sin(PI * blend(a,b,value))

## Rectified beats (0..1) at the given rate, only inside the window.
static func beats(rate: float, start: float, value: float, weight: float) -> float:
	return absf(sin(PI * rate * (value - start))) * weight

static func blink(rate: float, value: float) -> float:
	return pow(.5 + .5 * sin(TAU * rate * value), 3.0)

## A hand path through named anchors that starts and ends on "grip".
## moves: [[t0, t1, anchor, arc_height], ...]; returns [anchor mix, lift].
static func path(moves: Array, t: float) -> Array:
	var at := "grip"
	for move: Array in moves:
		if t < float(move[0]): break
		var m := blend(float(move[0]), float(move[1]), t)
		if m < 1.0:
			var mix := {at: 1.0 - m}
			mix[move[2]] = float(mix.get(move[2], 0.0)) + m
			return [mix, float(move[3]) * sin(PI * m)]
		at = str(move[2])
	return [{at: 1.0}, 0.0]

## Blends one program's hand path over whatever lower-priority programs produced.
static func layer(hand: Dictionary, program: Array, weight: float) -> void:
	if weight <= 0.0: return
	var mix: Dictionary = hand.mix
	for key: String in mix.keys(): mix[key] = float(mix[key]) * (1.0 - weight)
	for key: String in program[0]:
		mix[key] = float(mix.get(key, 0.0)) + float(program[0][key]) * weight
	hand.lift = float(hand.lift) * (1.0 - weight) + float(program[1]) * weight

static func _hand() -> Dictionary:
	return {"mix": {"grip": 1.0}, "lift": 0.0, "off": Vector3.ZERO, "roll": 0.0}

## Everything the console and the plush do at one instant. extra: {catch: seconds since
## the last blade catch, stop: seconds into the machine stop, rpm: blade speed 0..1}.
static func sample(entry: float, spin: float, drive: float, lift: float, deployed: bool, lift_speed: float=0.0, idle: float=0.0, extra: Dictionary={}) -> Dictionary:
	var catch_age := float(extra.get("catch", -1.0))
	var stop_age := float(extra.get("stop", -1.0))
	var rpm_override := float(extra.get("rpm", -1.0))
	var s := spin
	var v := {}
	var hand_l := _hand()
	var hand_r := _hand()
	var foot_l := Vector3.ZERO
	var foot_r := Vector3.ZERO
	var look := {}
	var pitch := 0.0 # + leans forward
	var roll := 0.0 # + tips toward the right hand
	var yaw := 0.0 # + turns left
	var bob := 0.0
	var head_pitch := 0.0 # + nods down
	var head_roll := 0.0
	# ---- transport: slide out past the ship's rim, drop to blade level, settle.
	var extension := 1.0 if deployed else blend(5.40,5.90,entry)
	var lowering := 1.0 if deployed else blend(5.90,6.20,entry)
	var shipping := 0.0 if deployed else sin(PI*blend(4.42,6.20,entry))
	var run := clampf(drive,-1.0,1.0) if deployed else .55*shipping
	if not deployed:
		pitch += .04*(arc(2.35,2.8,entry) - .6*arc(3.8,4.2,entry)) + .06*(arc(5.40,5.65,entry) - arc(5.65,5.90,entry))
		roll += .05*(arc(4.42,5.30,entry) - arc(5.30,6.20,entry))
		look.travel = window(2.4,2.9,3.4,3.9,entry)
		look.rpm = window(3.9,4.3,4.8,5.2,entry)
	# The floor drop keeps settling on the dock clock after the deck is deployed.
	bob += .020*arc(5.90,6.05,entry) - .030*arc(6.08,6.30,entry) + .010*arc(6.30,6.60,entry)
	look.floor = window(5.65,5.85,6.25,6.55,entry)
	var raising := clampf(lift/2.0,0.0,1.0)
	var lift_motion := clampf(lift_speed/6.0,-1.0,1.0)
	var rpm := blend(0.0,SawChaseState.SPINUP_SECONDS,s) if rpm_override < 0.0 else clampf(rpm_override,0.0,1.0)
	# Menu stow: p rises while stowing and falls while deploying; the chase clocks are frozen.
	var stow_p := float(extra.get("stow", 0.0))
	var stow_len := float(extra.get("stow_length", 12.4167))
	var stow_rate := float(extra.get("stow_rate", 0.0))
	var stow_idle := float(extra.get("stow_idle", -1.0))
	var stow_w := blend(0.0,1.0,stow_p) if extra.has("stow") else 0.0
	var stow_rest := stow_w*blend(stow_len-STOW_REST_FADE,stow_len,stow_p) if stow_idle >= 0.0 else 0.0
	var stow_working := stow_w*blend(0.0,.15,absf(stow_rate))
	# The BLADE stick is the rack command: pulled back to stow, pushed forward to deploy.
	lift_motion = lerpf(lift_motion, .85*clampf(stow_rate,-1.0,1.0), stow_w)
	var stopping := stop_age >= 0.0
	var st := clampf(stop_age,0.0,STOP_SECONDS) if stopping else 0.0
	var stop_w := blend(0.0,.25,stop_age) if stopping else 0.0
	# ---- machine state: key, guard, START, lamps
	var key_on := blend(.32,.50,s)
	var key := key_on * (1.0 - blend(.75,1.0,st))
	var power := blend(.45,.55,s) * (1.0 - blend(.85,.95,st))
	var guard := blend(.30,.55,s) * (1.0 - blend(1.25,1.55,st))
	var pressed := blend(.81,.86,s)
	var test := window(.50,.56,.86,.95,s)
	var catch_w := 0.0
	if catch_age >= 0.0:
		catch_w = blend(0.0,.15,catch_age) * (1.0 - blend(CATCH_SECONDS-.15,CATCH_SECONDS,catch_age)) * (1.0 - stop_w)
	var horn := catch_w * (arc(.36,.48,catch_age) + arc(.56,.68,catch_age))
	var saw_steady := blend(.90,.99,rpm)
	v.power = power
	v.key = key
	v.guard = guard
	v.press = window(.79,.84,.98,1.10,s)
	v.horn = horn
	v.gauge_test = sin(PI*blend(.50,1.15,s))
	v.lamp_Power = maxf(test, power)
	v.lamp_Ready = maxf(test, power*(pressed + (1.0-pressed)*blink(2.5,s)))
	v.lamp_Saw = maxf(test, power*pressed*blend(.02,.08,rpm)*(saw_steady + (1.0-saw_steady)*blink(4.0,s)))
	v.lamp_Lift = maxf(test, power*blend(.05,.2,absf(lift_motion)))
	var warn := blend(.05,.2,-run)*blink(3.0,s) + catch_w*window(0.0,.1,1.2,1.5,catch_age)*blink(5.0,catch_age)
	warn += stow_working*blink(2.5,stow_p)
	warn += stop_w*(1.0-blend(.85,.95,st))*blink(3.0,st)
	v.lamp_Warn = maxf(test, minf(1.0,power*warn))
	v.lamp_Fwd = power*blend(.05,.2,run)
	v.lamp_Rev = power*blend(.05,.2,-run)*blink(3.0,s)
	v.lamp_Up = power*blend(.05,.2,lift_motion)
	v.lamp_Down = power*blend(.05,.2,-lift_motion)
	v.bar_L = maxf(test, power*absf(run))
	# The right bar shows the rack's progress while it stows.
	v.bar_R = maxf(test, power*maxf(raising, stow_w*clampf(stow_p/stow_len,0.0,1.0)))
	v.beacon = maxf(pressed * power * blend(.02,.15,rpm), power*stow_working)
	v.beacon_angle = TAU*1.4*(maxf(s-.86,0.0) + stow_p)
	# ---- waiting vignettes on the idle clock (frozen once the start begins)
	var waiting := (1.0-blend(0.0,.3,s)) if deployed else 0.0
	# The eyes let go of a vignette more slowly than the hands do.
	var gaze := (1.0-blend(0.0,.8,s)) if deployed else 0.0
	var wait_time := idle if s < .8 else 0.0
	# Racked in the wall speed tab, the same vignettes run on the stowed-rest clock.
	var vw := waiting
	var vg := gaze
	var vt := wait_time
	if stow_rest > 0.0:
		vw = stow_rest
		vg = stow_rest
		vt = maxf(stow_idle-1.6,0.0)
	var slot := floorf(vt/IDLE_SLOT)
	var u := vt - slot*IDLE_SLOT
	var kind: int = IDLE_ORDER[int(slot) % IDLE_ORDER.size()]
	var env := vw * window(.4,1.2,IDLE_SLOT-1.0,IDLE_SLOT-.2,u)
	var env_gaze := vg * window(.4,1.2,IDLE_SLOT-1.0,IDLE_SLOT-.2,u)
	v.idle_kind = kind if vw > 0.0 else -1
	match kind:
		Idle.LOOK:
			look.travel = float(look.get("travel",0.0)) + env_gaze*window(.9,1.5,2.1,2.7,u)
			look.rpm = float(look.get("rpm",0.0)) + env_gaze*window(2.6,3.1,3.5,4.0,u)
			look.lift = env_gaze*window(3.9,4.4,4.9,5.4,u)
			hand_r.lift = .025*env*arc(4.6,5.1,u) # regrip
		Idle.STRETCH:
			var both := path([[1.0,1.8,"stretch",0.0],[3.6,4.5,"grip",.03]], u)
			layer(hand_l, both, vw)
			layer(hand_r, both, vw)
			var hold := window(1.8,2.0,3.4,3.6,u)
			hand_l.off += Vector3(.015*sin(TAU*1.5*u),0,0)*hold*vw
			hand_r.off += Vector3(-.015*sin(TAU*1.5*u),0,0)*hold*vw
			var reach := env*window(1.0,1.8,3.6,4.5,u)
			pitch -= .10*reach
			head_pitch -= .16*reach
			bob += .015*reach
			var legs := env*window(1.2,1.9,3.5,4.3,u)
			foot_l += Vector3(0,.05,.02)*legs
			foot_r += Vector3(0,.05,.02)*legs
		Idle.DRUM:
			var drum := vw*window(1.2,1.5,4.2,4.5,u)
			hand_l.off += Vector3(0,.022,0)*beats(2.4,1.4,u,drum)
			hand_r.off += Vector3(0,.022,0)*beats(2.4,1.4+1.0/4.8,u,drum)
			head_pitch += .035*beats(2.4,1.4,u,drum)
			look.ahead = env_gaze
		Idle.SWING:
			var swing := env*window(.8,1.3,4.8,5.4,u)
			foot_l += Vector3(0,.05+.02*sin(TAU*.9*u),.03*sin(TAU*.9*u))*swing
			foot_r += Vector3(0,.05-.02*sin(TAU*.9*u),-.03*sin(TAU*.9*u))*swing
			roll += .02*sin(TAU*.9*u)*swing
			head_roll += .04*sin(TAU*.9*u)*swing
			look.ahead = env_gaze*.6
		Idle.DOZE:
			var droop := vw*window(1.0,3.6,3.7,4.35,u)
			var jolt := vw*arc(3.75,4.4,u)
			head_pitch += .30*droop - .10*jolt
			head_roll += .12*droop
			pitch += .07*droop - .03*jolt
			bob -= .012*droop - .012*jolt
			look.travel = float(look.get("travel",0.0)) + env_gaze*window(4.1,4.45,4.6,4.95,u)
			look.back = env_gaze*window(4.95,5.3,5.4,5.8,u)
			hand_l.lift += .02*jolt
			hand_r.lift += .02*jolt
		Idle.WAVE:
			layer(hand_r, path([[1.0,1.6,"wave",.02],[3.5,4.2,"grip",.03]], u), vw)
			var waving := vw*window(1.6,1.8,3.3,3.5,u)
			hand_r.off += Vector3(.035*sin(TAU*2.0*(u-1.6)),0,0)*waving
			head_roll -= .08*sin(TAU*1.0*(u-1.6))*waving
			roll -= .04*env*window(1.0,1.6,3.5,4.2,u)
			look.camera = env_gaze*window(1.0,1.5,3.6,4.1,u)
	# ---- running: continuous corrections plus one check and one extra per cycle
	# The running routine is frozen with the chase clock while the blades are racked.
	var work := blend(WORK_START,WORK_START+.6,s) * (1.0 - stow_w)
	var run_time := maxf(s-WORK_START,0.0)
	var cycle := floorf(run_time/CHASE_CYCLE)
	var phase := run_time - cycle*CHASE_CYCLE
	var check: int = CHECK_ORDER[int(cycle) % CHECK_ORDER.size()]
	var extra_move: int = EXTRA_ORDER[int(cycle) % EXTRA_ORDER.size()]
	var trim := work*(.3+.7*absf(run))*(.045*sin(2.1*run_time+.3) + .025*sin(4.7*run_time+1.3) + .012*sin(9.3*run_time+.4))
	var lift_trim := absf(lift_motion)*(.035*sin(3.3*run_time+.8) + .015*sin(7.1*run_time+2.0))
	var first := work*window(.6,1.1,2.8,3.3,phase)
	match check:
		0:
			look.rpm = float(look.get("rpm",0.0)) + work*window(.6,1.1,1.6,2.0,phase)
			look.speed = work*window(1.9,2.3,2.7,3.3,phase)
		1:
			look.travel = float(look.get("travel",0.0)) + first
			pitch += .06*first
			roll -= .04*first
		2:
			look.lift = float(look.get("lift",0.0)) + work*window(.6,1.2,1.5,2.1,phase)
			look.bar_R = work*window(1.7,2.2,2.7,3.4,phase)
	var dial_w := 0.0
	var dial_turn := 0.0
	if extra_move == 0:
		# Trim the dial with the right hand, only while the blade height is held.
		dial_w = work*(1.0-blend(.05,.25,absf(lift_motion)))
		layer(hand_r, path([[3.6,4.0,"dial",.04],[4.95,5.35,"grip",.04]], phase), dial_w)
		dial_turn = sin(TAU*blend(4.05,4.85,phase))*window(3.9,4.05,4.85,5.0,phase)
		hand_r.roll = float(hand_r.roll) + .6*dial_turn*dial_w
		look.dial = dial_w*window(3.3,3.8,4.9,5.4,phase)
	elif extra_move == 1:
		# A little seat dance to the saw's rhythm.
		var groove := work*window(3.6,4.0,6.0,6.6,phase)
		head_roll += .06*sin(TAU*2.2*phase)*groove
		roll += .025*sin(TAU*2.2*phase)*groove
		bob += .010*beats(2.2,0.0,phase,groove)
	# Hunting: the carriage chases players on the left; reversing glances back.
	look.travel = float(look.get("travel",0.0)) + work*.5*blend(.1,.8,run)
	look.back = float(look.get("back",0.0)) + work*.6*blend(.1,.5,-run)
	look.lift = float(look.get("lift",0.0)) + .45*absf(lift_motion)*work
	roll -= .05*run*work
	v.dial = .12*dial_turn*dial_w
	# ---- start: key -> guard -> wind-up -> slam START -> fist pump -> sticks
	if s > 0.0 and s < START_HANDS_DONE:
		var start_w := blend(0.0,.3,s)
		layer(hand_l, path([[0.0,.32,"key",.04],[.62,1.05,"grip",.04]], s), start_w)
		layer(hand_r, path([[.05,.30,"guard",.03],[.52,.70,"windup",0.0],[.72,.82,"start",0.0],[1.10,1.35,"pump",.02],[1.85,2.30,"grip",.04]], s), start_w)
		hand_l.roll = float(hand_l.roll) + 1.1*blend(.32,.50,s)*(1.0-blend(.62,.85,s))*start_w
		hand_r.off += Vector3(0,.035,0)*beats(2.0,1.35,s,window(1.30,1.40,1.80,1.90,s))
	# The key turns by feel; the eyes go to the guard and START, then the RPM climb.
	look.start = window(.1,.8,.95,1.45,s)
	look.rpm = float(look.get("rpm",0.0)) + window(1.0,1.5,2.0,2.6,s)
	look.travel = float(look.get("travel",0.0)) + window(2.1,2.8,2.9,3.5,s)
	pitch += -.05*window(.50,.70,.70,.82,s) + .10*window(.70,.90,.95,1.2,s)
	head_pitch += .05*arc(.76,1.05,s)
	roll += .04*window(.05,.3,1.0,1.2,s) - .03*window(0.0,.3,.55,.7,s)
	bob += .015*beats(2.0,1.35,s,window(1.30,1.40,1.80,1.90,s))
	# ---- blade catch: honk twice, fist pump, cheer in the seat
	if catch_w > 0.0:
		var a := catch_age
		layer(hand_l, path([[.10,.30,"horn",.03],[.74,1.02,"pump",.02],[1.75,2.20,"grip",.04]], a), catch_w)
		hand_l.off += Vector3(0,.04,0)*beats(2.2,1.05,a,window(1.02,1.10,1.65,1.75,a))*catch_w
		var cheer := catch_w*window(.85,1.0,1.8,2.0,a)
		bob += .015*beats(3.0,.9,a,cheer)
		roll += .05*sin(TAU*3.0*(a-.9))*cheer
		head_roll += .08*sin(TAU*1.5*(a-.9))*cheer
		foot_l += Vector3(0,.045,0)*beats(3.0,.9,a,cheer)
		foot_r += Vector3(0,.045,0)*beats(3.0,.9+1.0/6.0,a,cheer)
		look.travel = float(look.get("travel",0.0)) + catch_w*window(0.0,.3,1.9,2.3,a)
	# ---- menu stow / deploy on the stow clock p (deploy plays the same p backwards)
	if stow_w > 0.0:
		var p := stow_p
		var moving := stow_w * (1.0 - stow_rest)
		# Right hand holds BLADE (the rack command); the left covers the crown under the rack.
		layer(hand_r, [{"grip": 1.0}, 0.0], moving)
		layer(hand_l, path([[7.2,7.7,"cover",.02],[9.2,9.7,"grip",.03]], p), moving)
		var duck := stow_w*window(7.3,8.1,8.9,9.6,p)
		pitch += .10*duck + .05*stow_w*window(0.0,.5,1.0,1.8,p)
		head_pitch += .16*duck + .08*stow_w*arc(11.8,12.4,p)
		bob -= .02*duck
		yaw += .07*stow_w*window(9.3,10.1,11.4,12.1,p)
		look.rpm = float(look.get("rpm",0.0)) + stow_w*window(0.0,.5,.9,1.9,p)
		look.rack_up = stow_w*window(1.0,2.0,5.2,6.0,p)
		look.overhead = stow_w*window(5.5,6.4,7.0,7.8,p)
		look.behind = stow_w*window(9.3,10.1,11.4,12.1,p)
		# Locked and racked: a fist pump before the waiting vignettes take over.
		if stow_rest > 0.0:
			layer(hand_l, path([[.1,.4,"pump",.02],[1.0,1.4,"grip",.03]], stow_idle), stow_rest)
			hand_l.off += Vector3(0,.035,0)*beats(2.2,.4,stow_idle,window(.35,.45,.85,.95,stow_idle))*stow_rest
	# ---- machine stop: sticks home, key off, close the guard, lean back
	if stopping:
		layer(hand_l, path([[.35,.75,"key",.04],[1.05,1.50,"grip",.04]], st), stop_w)
		layer(hand_r, path([[.90,1.25,"guard",.04],[1.55,1.95,"grip",.04]], st), stop_w)
		hand_l.roll = float(hand_l.roll) + 1.1*window(.40,.75,.75,1.0,st)*stop_w
		look.key = .6*stop_w*window(.2,.6,.75,1.35,st)
		look.start = float(look.get("start",0.0)) + stop_w*window(.75,1.35,1.5,1.95,st)
		var relax := stop_w*blend(1.4,2.0,st)
		pitch -= .06*relax
		head_pitch -= .12*arc(1.3,2.0,st)*stop_w + .04*relax
		bob -= .008*relax
	var breath_time := s if s > 0.0 else wait_time + entry
	var breath := sin(TAU*breath_time/3.4)
	v.merge({
		"entry":entry,"spin":spin,"extension":extension,"lowering":lowering,
		"drive":run,"lift":raising,"lift_motion":lift_motion,"rpm":rpm + .012*work*sin(13.0*run_time),
		"idle":wait_time,"work":work,"trim":trim,"lift_trim":lift_trim,"dial_hold":dial_w,
		"catch":catch_w,"stop":stop_w,"stow":stow_w,"stow_rest":stow_rest,"breath":breath,
		"hand_L":hand_l,"hand_R":hand_r,"foot_L":foot_l,"foot_R":foot_r,"look":look,
		"pitch":pitch + .012*breath,"roll":roll,"yaw":yaw,"bob":bob + .004*breath,
		"head_pitch":head_pitch,"head_roll":head_roll,
	})
	return v

func reset_pose() -> void:
	last_sample.clear()
	apply_sample(sample(0.0,0.0,0.0,0.0,true))

func _control(key: String) -> Node3D:
	return controls.get(key) as Node3D

func apply_sample(value: Dictionary) -> void:
	if skeleton == null: return
	var previous := last_sample
	last_sample = value.duplicate(true)
	station.position.z = -EXTENSION * float(value.extension)
	var drop := FLOOR_DROP * float(value.lowering)
	station.position.y = -drop
	for rail in rails:
		var travel_out := EXTENSION * float(value.extension)
		rail.scale.z = absf(travel_out - SUPPORT_OFFSET) + .22
		rail.position.z = -(SUPPORT_OFFSET + travel_out) * .5
		rail.position.y = .78 - drop
	for key: String in controls:
		(controls[key] as Node3D).transform = rest[key]
	_control("OP_MountFrame").position.z = EXTENSION * float(value.extension)
	_control("OP_MountFrame").position.y = drop
	for side in ["L", "R"]:
		var support := _control("OP_LiftSupport_" + side)
		support.position.y = (.50 + .84 - drop) * .5
		support.scale.y = absf(.84 - drop - .50) + .08
	# DRIVE keeps its small corrections; BLADE only moves while the right hand holds it.
	var travel := float(value.drive) + float(value.trim)/DRIVE_THROW
	var lifting := (float(value.lift_motion) + float(value.lift_trim)/LIFT_THROW) * (1.0 - float(value.dial_hold))
	_control("OP_Lever_L").rotate_z(-DRIVE_THROW * clampf(travel,-1.2,1.2))
	_control("OP_Lever_R").rotate_x(-LIFT_THROW * lifting)
	_control("OP_Pedal_L").rotate_x(.14 * clampf(travel,-1.0,1.0))
	_control("OP_Pedal_R").rotate_x(.10 * clampf(lifting,-1.0,1.0))
	_control("OP_Key").rotate_y(-1.2 * float(value.key))
	_control("OP_Guard").rotate_x(-1.75 * float(value.guard))
	_control("OP_Start").position.y -= .010 * float(value.press)
	_control("OP_Horn").position.y -= .008 * float(value.horn)
	_control("OP_Dial").rotate_y(2.4 * float(value.dial))
	_control("OP_Beacon").rotate_y(float(value.beacon_angle))
	var test := float(value.gauge_test)
	_needle("Speed", maxf(absf(float(value.drive)), test))
	_needle("RPM", maxf(float(value.rpm), test))
	_needle("Lift", maxf(float(value.lift), test))
	for lamp: String in LAMPS: _lamp("OP_Lamp_" + lamp, float(value["lamp_" + lamp]))
	for i in 8:
		_lamp("OP_Bar_L%d" % i, clampf(float(value.bar_L)*8.0 - i, 0.0, 1.0))
		_lamp("OP_Bar_R%d" % i, clampf(float(value.bar_R)*8.0 - i, 0.0, 1.0))
	var beacon := float(value.beacon)
	_lamp("OP_BeaconDome", beacon * (.45 + .55*pow(maxf(0.0,cos(float(value.beacon_angle))),4.0)))
	_play_events(previous, value)
	# The fixed station follows its dock even while the chair owns the mascot.
	if seat_transfer != null and seat_transfer.owns_pose() and not seat_transfer.applying_base:
		return
	skeleton.reset_bone_poses()
	var weight := body_weight if seat_transfer != null and seat_transfer.owns_pose() else 1.0
	var look := _look_angles(value.look)
	var pitch := float(value.pitch) + .12*maxf(0.0,-lifting) + .03*maxf(0.0,lifting) + .3*look.y
	var roll := float(value.roll)
	var yaw := float(value.yaw) + .08*look.x
	var body_basis := Basis(Vector3.UP,yaw*weight)*Basis(Vector3.BACK,roll*weight)*Basis(Vector3.RIGHT,pitch*weight)
	_body = Transform3D(body_basis,BODY_PIVOT-body_basis*BODY_PIVOT + Vector3.UP*float(value.bob)*weight)
	var hips_rest: Transform3D = bone_rest["DEF-hips"]
	skeleton.set_bone_global_pose(bones["DEF-hips"],_body*hips_rest)
	var head_rest: Transform3D = bone_rest["DEF-head"]
	var head_turn := Basis(Vector3.UP,.47*look.x*weight)*Basis(Vector3.BACK,float(value.head_roll)*weight)*Basis(Vector3.RIGHT,(.7*look.y+float(value.head_pitch))*weight)
	skeleton.set_bone_global_pose(bones["DEF-head"],Transform3D(body_basis*head_turn*head_rest.basis,_body*head_rest.origin))
	var up := skeleton.global_basis*Vector3.UP
	for side in ["L","R"]:
		var hand: Dictionary = value["hand_" + side]
		var target := Vector3.ZERO
		for anchor: String in hand.mix:
			target += _anchor(side, anchor) * float(hand.mix[anchor])
		target += up*float(hand.lift) + skeleton.global_basis*(hand.off as Vector3)
		_pose_arm(side,target,float(hand.roll))
		var foot := skeleton.to_global(_sk(_control("OP_FootContact_"+side)) + (value["foot_" + side] as Vector3))
		_pose_leg(side,foot)
	skeleton.force_update_all_bone_transforms()

## World position of a named hand anchor. Controls give their contact empties; the rest
## are shoulder-relative so they ride along with the swaying body.
func _anchor(side: String, anchor: String) -> Vector3:
	var sign_x := 1.0 if side == "L" else -1.0
	match anchor:
		"grip": return _control("OP_GripContact_" + side).global_position
		"key": return _control("OP_KeyContact").global_position
		"horn": return _control("OP_HornContact").global_position
		"guard": return _control("OP_GuardContact").global_position
		"start": return _control("OP_StartContact").global_position
		"dial": return _control("OP_DialContact").global_position
		"windup":
			var basis := station.global_basis
			return _control("OP_StartContact").global_position + basis.y*.10 - basis.z*.04
	var offset: Vector3 = {"pump": PUMP, "stretch": STRETCH, "wave": WAVE, "cover": COVER}[anchor]
	return skeleton.to_global(_rest("DEF-upper_arm." + side).origin + Vector3(offset.x*sign_x, offset.y, offset.z))

func _needle(gauge: String, value: float) -> void:
	# Needles sweep 270 degrees clockwise about the gauge face normal.
	_control("OP_Needle_" + gauge).rotate_y(deg_to_rad(135.0) - deg_to_rad(270.0)*clampf(value,0.0,1.0))

func _lamp(owner_name: String, value: float) -> void:
	for material: StandardMaterial3D in _lamps.get(owner_name, []):
		material.emission_energy_multiplier = 2.6*clampf(value,0.0,1.0)

func _play_events(previous: Dictionary, now: Dictionary) -> void:
	if previous.is_empty() or not audio_enabled: return
	if float(previous.get("horn",0.0)) < .6 and float(now.horn) >= .6:
		horn_count += 1
		if is_inside_tree(): _horn.play()
	var clunk := (float(previous.get("press",0.0)) < .6 and float(now.press) >= .6)
	clunk = clunk or (float(previous.get("key",0.0)) < .9 and float(now.key) >= .9)
	clunk = clunk or (float(previous.get("key",0.0)) > .1 and float(now.key) <= .1)
	if clunk:
		switch_count += 1
		if is_inside_tree():
			_switch.pitch_scale = .8 if float(now.press) >= .6 else 1.35
			_switch.play()

func _sk(node: Node3D) -> Vector3:
	return skeleton.to_local(node.global_position)

## Weighted yaw (x, + left) and downward pitch (y) toward skeleton-space targets.
func _look_angles(weights: Dictionary) -> Vector2:
	var total := 0.0
	var angles := Vector2.ZERO
	for key: String in weights:
		var amount := float(weights[key])
		if amount <= 0.0: continue
		var offset: Vector3 = _look_target(key) - EYE
		var turn := clampf(atan2(offset.x,offset.z),-.65,.65)
		var down := clampf(atan2(-offset.y,Vector2(offset.x,offset.z).length()),-.25,.45)
		angles += Vector2(turn,down)*amount
		total += amount
	return angles/total if total > 1.0 else angles

func _look_target(key: String) -> Vector3:
	match key:
		"key": return _sk(_control("OP_KeyContact"))
		"start": return _sk(_control("OP_StartContact"))
		"horn": return _sk(_control("OP_HornContact"))
		"dial": return _sk(_control("OP_DialContact"))
		"rpm": return _sk(_control("OP_Gauge_RPM"))
		"speed": return _sk(_control("OP_Gauge_Speed"))
		"lift": return _sk(_control("OP_Gauge_Lift"))
		"bar_R": return _sk(_control("OP_Bar_R3"))
		"travel": return TRAVEL_SIDE
		"back": return Vector3(-TRAVEL_SIDE.x, TRAVEL_SIDE.y, TRAVEL_SIDE.z*.5)
		"camera": return CAMERA_SIDE
		"floor": return FLOOR
		"rack_up": return RACK_UP
		"overhead": return OVERHEAD
		"behind": return BEHIND
	return AHEAD

## Rest transform of a bone, carried by the swaying body for the upper half.
func _rest(key: String) -> Transform3D:
	var bind: Transform3D = bone_rest[key]
	return _body*bind if key in BODY_BONES else bind

func _bone_pose(key: String, origin: Vector3, direction: Vector3, roll: float=0.0) -> void:
	var bind := _rest(key)
	var rotation := Quaternion(bind.basis.y.normalized(),direction.normalized())
	skeleton.set_bone_global_pose(int(bones[key]),Transform3D(Basis(direction.normalized(),roll)*Basis(rotation)*bind.basis,origin))

func _solve_limb(a: String, b: String, end: String, target: Vector3, pole: Vector3) -> Vector3:
	var ar := _rest(a)
	var br := _rest(b)
	var er := _rest(end)
	var origin := ar.origin
	var length_a := origin.distance_to(br.origin)
	var length_b := br.origin.distance_to(er.origin)
	var offset := target-origin
	var distance := clampf(offset.length(),absf(length_a-length_b)+.00001,length_a+length_b-.00001)
	var direction := offset.normalized()
	var bend := pole-direction*pole.dot(direction)
	if bend.length_squared() < .000001: bend = Vector3.UP.cross(direction)
	bend = bend.normalized()
	var along := (length_a*length_a-length_b*length_b+distance*distance)/(2.0*distance)
	var height := sqrt(maxf(0.0,length_a*length_a-along*along))
	var elbow := origin+direction*along+bend*height
	var reached := origin+direction*distance
	_bone_pose(a,origin,elbow-origin)
	_bone_pose(b,elbow,reached-elbow)
	return reached

func _pose_arm(side: String, world_contact: Vector3, roll: float=0.0) -> void:
	var target := skeleton.to_local(world_contact)
	# The contact lies on the mitten surface, beyond its wrist bone.
	var palm_offset := Vector3(0.0,0.0,.100)
	var wrist := target-palm_offset
	var reached := _solve_limb("DEF-upper_arm."+side,"DEF-forearm."+side,"DEF-hand."+side,wrist,Vector3(1 if side=="L" else -1,-.35,0))
	_bone_pose("DEF-hand."+side,reached,Vector3.BACK,roll)
	contact_errors["hand_"+side] = skeleton.to_global(reached+palm_offset).distance_to(world_contact)

func pose_belt_hand(side: String, world_contact: Vector3, weight: float) -> void:
	# Allow the soft plush shoulder to follow the reach; restore the rest data
	# immediately so normal lever/pedal IK and replay poses remain unchanged.
	var key := "DEF-upper_arm." + side
	var forearm_key := "DEF-forearm." + side
	var hand_key := "DEF-hand." + side
	var shoulder: Transform3D = bone_rest[key]
	var forearm: Transform3D = bone_rest[forearm_key]
	var hand: Transform3D = bone_rest[hand_key]
	var target := skeleton.to_local(world_contact) - Vector3(0,0,.100)
	var reach := shoulder.origin.distance_to(forearm.origin) + forearm.origin.distance_to(hand.origin)
	var offset := target - _rest(key).origin
	# The shift is stored in rest space; the swaying body carries it afterwards.
	var shift := _body.basis.inverse() * (offset.normalized() * maxf(0.0, offset.length() - reach + .002)) if weight > 0.0 else Vector3.ZERO
	bone_rest[key] = Transform3D(shoulder.basis, shoulder.origin + shift)
	bone_rest[forearm_key] = Transform3D(forearm.basis, forearm.origin + shift)
	bone_rest[hand_key] = Transform3D(hand.basis, hand.origin + shift)
	_pose_arm(side, world_contact)
	bone_rest[key] = shoulder
	bone_rest[forearm_key] = forearm
	bone_rest[hand_key] = hand

func _pose_leg(side: String, world_contact: Vector3) -> void:
	var target := skeleton.to_local(world_contact)
	var angle: float = _control("OP_Pedal_"+side).rotation.x
	# Calibrated against the skinned sole surface, not only the ankle marker.
	var sole_offset := Vector3(0,-.17,.38).rotated(Vector3.RIGHT,angle) - Vector3.UP*.004
	var reached := _solve_limb("DEF-thigh."+side,"DEF-shin."+side,"DEF-foot."+side,target-sole_offset,Vector3.BACK)
	_bone_pose("DEF-foot."+side,reached,Vector3(0,-.67,.74).rotated(Vector3.RIGHT,angle))
	contact_errors["foot_"+side] = skeleton.to_global(reached+sole_offset).distance_to(world_contact)
