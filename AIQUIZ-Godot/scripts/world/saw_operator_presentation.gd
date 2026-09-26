extends Node3D
class_name SawOperatorPresentation

## Presentation only. Controls and contact poses share one evaluated sample.
const ASSET := "res://assets/hazards/saw_operator/saw_operator.glb"
const MOUNT := Vector3(10.70, 0.0, 0.0) # Stowed above the left end; slides onto its end bracket.
const FACING_YAW := -PI / 2.0 # Face across the blade row toward its right end.
const EXTENSION := 2.25
const SUPPORT_OFFSET := 1.42 # Fixed to the existing outboard spine at X=12.12.
const FLOOR_DROP := 0.628274 # Deck top .97 aligns with the resting blade underside .341726.
const LEVER_THROW := .30
const CHASE_CYCLE := 6.4 # Gauge, track and dial checks repeat while the saw runs.
const IDLE_CYCLE := 7.2
const BODY_PIVOT := Vector3(0.0,.55,0.0) # Seat contact; the plush body rocks around it.
const EYE := Vector3(0.0,1.0,.15)
const AHEAD := Vector3(0.0,1.15,3.0)
const BODY_BONES := ["DEF-head","DEF-hips","DEF-upper_arm.L","DEF-forearm.L","DEF-hand.L","DEF-upper_arm.R","DEF-forearm.R","DEF-hand.R"]
var station: Node3D
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
var _body := Transform3D.IDENTITY

func _ready() -> void:
	station = (load(ASSET) as PackedScene).instantiate()
	add_child(station)
	position = MOUNT
	rotation.y = FACING_YAW
	skeleton = station.find_child("Skeleton3D", true, false) as Skeleton3D
	for item: Node in station.find_children("OP_*", "Node3D", true, false):
		controls[str(item.name)] = item
		rest[str(item.name)] = (item as Node3D).transform
	if skeleton != null:
		for index in skeleton.get_bone_count():
			var key := str(skeleton.get_bone_name(index))
			bones[key] = index
			bone_rest[key] = skeleton.get_bone_global_rest(index)
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

static func blend_between(a: float, b: float, value: float) -> float:
	return smoothstep(a,b,value)

## Rises over a..b, holds, falls over c..d. Continuous, zero outside a..d.
static func window(a: float, b: float, c: float, d: float, value: float) -> float:
	return blend_between(a,b,value) - blend_between(c,d,value)

## Zero at both ends of a..b, one at its middle: a lifted arc between contacts.
static func arc(a: float, b: float, value: float) -> float:
	return sin(PI * blend_between(a,b,value))

static func sample(entry: float, spin: float, drive: float, lift: float, deployed: bool, lift_speed: float=0.0, idle: float=0.0) -> Dictionary:
	# Clear the ship's front rim before sliding out over the left end bracket.
	var extension := 1.0 if deployed else blend_between(5.40,5.90,entry)
	var lowering := 1.0 if deployed else blend_between(5.90,6.20,entry)
	var shipping := sin(PI * blend_between(4.42,6.20,entry)) if not deployed else 0.0
	var run := clampf(drive,-1.0,1.0) if deployed else shipping
	var raising := clampf(lift / 2.0,0.0,1.0)
	var lift_motion := clampf(lift_speed/6.0,-1.0,1.0)
	# Waiting: the idle clock only exists before the start sequence takes over.
	var waiting := 1.0 - blend_between(0.0,.3,spin)
	var wait_time := idle if spin < .3 else 0.0
	var wait_phase := fposmod(wait_time,IDLE_CYCLE)
	# Running: deterministic check routine, varied per cycle so it never loops visibly.
	var work := blend_between(3.3,3.8,spin)
	var run_time := maxf(spin-3.3,0.0)
	var cycle := floorf(run_time/CHASE_CYCLE)
	var phase := run_time - cycle*CHASE_CYCLE
	var variant := fposmod(sin(cycle*12.9898+.37)*43758.5453,1.0)
	var taps := variant < .65
	var tap := work * window(3.7,4.1,4.6,5.0,phase) if taps else 0.0
	var tap_turn := work * sin(TAU*clampf((phase-4.1)/.5,0.0,1.0)) if taps else 0.0
	var ahead := work * (window(2.1,2.45,3.0,3.35,phase) + (0.0 if taps else window(3.7,4.1,4.6,5.0,phase)))
	# Small continuous lever corrections; stronger while the carriage is travelling.
	var trim := work * (.3+.7*absf(run)) * (.045*sin(2.1*run_time+.3) + .025*sin(4.7*run_time+1.3) + .012*sin(9.3*run_time+.4))
	var lift_trim := absf(lift_motion) * (.035*sin(3.3*run_time+.8) + .015*sin(7.1*run_time+2.0))
	var breath_time := spin if spin > 0.0 else wait_time
	return {
		"entry":entry,"spin":spin,"extension":extension,"lowering":lowering,
		"drive":run,"lift":raising,
		"lift_motion":lift_motion,
		"press":(1.0-blend_between(.12,.40,spin)) if spin > 0.0 else 0.0,
		"cover":blend_between(.48,.85,spin),
		"toggle":blend_between(.9,1.2,spin) + .12*sin(PI*clampf((spin-1.05)/.35,0.0,1.0)),
		"dial":blend_between(1.65,2.8,spin) + .10*tap_turn,
		"rpm":blend_between(0.0,SawChaseState.SPINUP_SECONDS,spin) + .012*work*sin(13.0*run_time),
		"idle":wait_time,
		"work":work,"trim":trim,"lift_trim":lift_trim,
		"breath":sin(TAU*breath_time/3.4),
		"tap":tap,"tap_turn":tap_turn,
		# Eyes swing from Start (left) to the cover (right) without whipping the head.
		"look_press":window(0.0,.25,.30,.80,spin) if spin > 0.0 else 0.0,
		"look_console":window(.50,1.0,2.8,3.3,spin),
		"look_gauge_L":work*window(.4,.85,1.45,1.9,phase) + waiting*window(.8,1.3,2.0,2.5,wait_phase),
		"look_gauge_R":work*window(5.05,5.5,5.8,6.25,phase) + waiting*window(5.0,5.4,6.2,6.7,wait_phase),
		"look_ahead":ahead + waiting*window(3.0,3.5,4.2,4.7,wait_phase),
		"regrip":waiting*(arc(1.0,1.7,wait_phase) + arc(4.0,4.7,wait_phase)) if wait_time > 0.0 else 0.0,
	}

func reset_pose() -> void:
	last_sample.clear()
	apply_sample(sample(0.0,0.0,0.0,0.0,true))

func _control(key: String) -> Node3D:
	return controls.get(key) as Node3D

func apply_sample(value: Dictionary) -> void:
	if skeleton == null: return
	last_sample = value.duplicate()
	station.position.z = -EXTENSION * float(value.extension)
	var drop := FLOOR_DROP * float(value.lowering)
	station.position.y = -drop
	for rail in rails:
		var travel := EXTENSION * float(value.extension)
		rail.scale.z = absf(travel - SUPPORT_OFFSET) + .22
		rail.position.z = -(SUPPORT_OFFSET + travel) * .5
		rail.position.y = .78 - drop
	for key: String in controls:
		(controls[key] as Node3D).transform = rest[key]
	_control("OP_MountFrame").position.z = EXTENSION * float(value.extension)
	_control("OP_MountFrame").position.y = drop
	for side in ["L", "R"]:
		var support := _control("OP_LiftSupport_" + side)
		support.position.y = (.50 + .84 - drop) * .5
		support.scale.y = absf(.84 - drop - .50) + .08
	# Travel lever keeps its small corrections; the lift lever only moves while the
	# right hand is on it, so a height hold (and a dial check) leaves it neutral.
	var travel := float(value.drive) + float(value.get("trim",0.0))/LEVER_THROW
	var lifting := (float(value.lift_motion) + float(value.get("lift_trim",0.0))/LEVER_THROW) * (1.0-float(value.get("tap",0.0)))
	_control("OP_Lever_L").rotate_x(-LEVER_THROW * travel)
	_control("OP_Lever_R").rotate_x(-LEVER_THROW * lifting)
	_control("OP_Pedal_L").rotate_x(.14 * clampf(travel,-1.0,1.0))
	_control("OP_Pedal_R").rotate_x(.10 * lifting)
	for side in ["L","R"]:
		var index := _control("OP_InputIndex_"+side)
		if index!=null:index.position.z+=.065*(travel if side=="L" else lifting)
	_control("OP_Start").position.y -= .012 * float(value.press)
	_control("OP_Cover").rotate_x(1.7 * float(value.cover))
	_control("OP_Toggle").rotate_x(-.42 * float(value.toggle))
	_control("OP_Dial").rotate_y(2.4 * float(value.dial))
	_control("OP_Needle_L").rotate_z(2.2 - 4.4 * float(value.rpm))
	_control("OP_Needle_R").rotate_z(2.2 - 4.4 * float(value.lift))
	# The fixed station follows its dock even while the chair owns the mascot.
	if seat_transfer != null and seat_transfer.owns_pose() and not seat_transfer.applying_base:
		return
	skeleton.reset_bone_poses()
	var weight := body_weight if seat_transfer != null and seat_transfer.owns_pose() else 1.0
	var spin: float = value.spin
	var drive := float(value.drive)
	var lift_motion := float(value.lift_motion)
	var tap := float(value.get("tap",0.0))
	var console := float(value.get("look_console",0.0))
	var press := float(value.get("look_press",0.0))
	# The head follows whichever control or gauge the routine is checking.
	var look := _look_angles([
		[press,_sk(_control("OP_StartContact"))],
		[console,_sk(_control("OP_CoverContact")).lerp(_sk(_control("OP_DialContact")),blend_between(1.0,1.65,spin))],
		[value.get("look_gauge_L",0.0),_sk(_control("OP_GaugeMount_L"))],
		[float(value.get("look_gauge_R",0.0)) + .5*absf(lift_motion),_sk(_control("OP_GaugeMount_R"))],
		[value.get("look_ahead",0.0),AHEAD],
		[tap,_sk(_control("OP_DialContact"))],
	])
	# Whole plush body: lean into pushes and presses, settle back while pulling,
	# tip toward the side that is working, and breathe.
	var pitch := .05*(1.0-float(value.extension)) + .12*maxf(0.0,-travel) - .035*maxf(0.0,travel)
	pitch += .12*maxf(0.0,-lifting) + .03*maxf(0.0,lifting) + .06*press
	pitch += .012*float(value.get("breath",0.0)) + .3*look.y
	var roll := .045*console + .035*tap - .03*press
	# The reaching shoulder leads: the right hand's console work turns the body
	# toward +X, the left hand's press toward -X. Looking is mostly the head.
	# A forward push on the travel lever needs the left shoulder: stay square.
	var yaw := (.10*console + .06*tap)*(1.0-maxf(0.0,-travel)) - .08*press
	var body_basis := Basis(Vector3.UP,yaw*weight)*Basis(Vector3.BACK,roll*weight)*Basis(Vector3.RIGHT,pitch*weight)
	_body = Transform3D(body_basis,BODY_PIVOT-body_basis*BODY_PIVOT)
	var hips_rest: Transform3D = bone_rest["DEF-hips"]
	skeleton.set_bone_global_pose(bones["DEF-hips"],_body*hips_rest)
	var head_rest: Transform3D = bone_rest["DEF-head"]
	var head_turn := Basis(Vector3.UP,(.5*look.x-yaw)*weight)*Basis(Vector3.RIGHT,.7*look.y*weight)
	skeleton.set_bone_global_pose(bones["DEF-head"],Transform3D(body_basis*head_turn*head_rest.basis,_body*head_rest.origin))
	var up := skeleton.global_basis*Vector3.UP
	for side in ["L","R"]:
		var target := _control("OP_GripContact_"+side).global_position
		var touch := 0.0
		var touch_target := target
		var lifted := 0.0
		var roll_hand := 0.0
		if side == "L" and spin < .70:
			# Already poised above Start while waiting: contact at the first spin frame.
			touch = (1.0-blend_between(.20,.70,spin))*(1.0-blend_between(0.0,.15,drive))
			touch_target = _control("OP_StartContact").global_position
			lifted = .04*arc(.20,.70,spin)
		elif side == "R":
			var cover := _control("OP_CoverContact").global_position
			var toggle := _control("OP_ToggleContact").global_position
			var dial := _control("OP_DialContact").global_position
			touch = 1.0
			if spin < .48:
				touch_target = target.lerp(cover,blend_between(.30,.48,spin))
			elif spin < .85:
				touch_target = cover
			elif spin < 1.0:
				touch_target = cover.lerp(toggle,blend_between(.85,1.0,spin))
			elif spin < 1.2:
				touch_target = toggle
			elif spin < 1.65:
				touch_target = toggle.lerp(dial,blend_between(1.2,1.65,spin))
			elif spin < 2.8:
				touch_target = dial
			else:
				touch_target = dial.lerp(target,blend_between(2.8,3.3,spin))
			# Running checks: reach over to trim the dial, then return to the lever.
			touch_target = touch_target.lerp(dial,tap)
			lifted = .02*arc(.30,.48,spin) + .05*arc(1.2,1.65,spin) + .05*arc(2.8,3.3,spin) + .04*sin(PI*tap)
			lifted += .025*float(value.get("regrip",0.0))
			roll_hand = .9*blend_between(1.65,2.8,spin)*(1.0-blend_between(2.8,3.3,spin)) + .5*float(value.get("tap_turn",0.0))
		target = target.lerp(touch_target,touch) + up*lifted
		_pose_arm(side,target,roll_hand)
		_pose_leg(side,_control("OP_FootContact_"+side).global_position)
	skeleton.force_update_all_bone_transforms()

func _sk(node: Node3D) -> Vector3:
	return skeleton.to_local(node.global_position)

## Weighted yaw (x) and downward pitch (y) toward skeleton-space targets.
func _look_angles(targets: Array) -> Vector2:
	var total := 0.0
	var angles := Vector2.ZERO
	for entry: Array in targets:
		var amount := float(entry[0])
		if amount <= 0.0: continue
		var offset: Vector3 = entry[1] - EYE
		var yaw := clampf(atan2(offset.x,offset.z),-.55,.55)
		var down := clampf(atan2(-offset.y,Vector2(offset.x,offset.z).length()),-.2,.35)
		angles += Vector2(yaw,down)*amount
		total += amount
	return angles/total if total > 1.0 else angles

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
