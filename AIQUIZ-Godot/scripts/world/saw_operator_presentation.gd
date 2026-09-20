extends Node3D
class_name SawOperatorPresentation

## Presentation only. Controls and contact poses share one evaluated sample.
const ASSET := "res://assets/hazards/saw_operator/saw_operator.glb"
const MOUNT := Vector3(10.70, 0.0, 0.0) # Stowed above the left end; slides onto its end bracket.
const FACING_YAW := -PI / 2.0 # Face across the blade row toward its right end.
const EXTENSION := 2.25
const SUPPORT_OFFSET := 1.42 # Fixed to the existing outboard spine at X=12.12.
const FLOOR_DROP := 0.628274 # Deck top .97 aligns with the resting blade underside .341726.
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

static func sample(entry: float, spin: float, drive: float, lift: float, deployed: bool, lift_speed: float=0.0) -> Dictionary:
	# Clear the ship's front rim before sliding out over the left end bracket.
	var extension := 1.0 if deployed else blend_between(5.40,5.90,entry)
	var lowering := 1.0 if deployed else blend_between(5.90,6.20,entry)
	var shipping := sin(PI * blend_between(4.42,6.20,entry)) if not deployed else 0.0
	var run := clampf(drive,-1.0,1.0)
	var raising := clampf(lift / 2.0,0.0,1.0)
	return {
		"entry":entry,"spin":spin,"extension":extension,"lowering":lowering,
		"drive":shipping if not deployed else run,"lift":raising,
		"lift_motion":clampf(lift_speed/6.0,-1.0,1.0),
		"press":(1.0-blend_between(.12,.40,spin)) if spin > 0.0 else 0.0,
		"cover":blend_between(.48,.85,spin),
		"toggle":blend_between(.9,1.2,spin),
		"dial":blend_between(1.65,2.8,spin),
		"rpm":blend_between(0.0,SawChaseState.SPINUP_SECONDS,spin),
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
	_control("OP_Lever_L").rotate_x(-.24 * float(value.drive))
	_control("OP_Lever_R").rotate_x(-.24 * float(value.lift_motion))
	_control("OP_Pedal_L").rotate_x(.14 * float(value.drive))
	_control("OP_Pedal_R").rotate_x(.10 * float(value.lift_motion))
	for side in ["L","R"]:
		var index := _control("OP_InputIndex_"+side)
		if index!=null:index.position.z+=.065*float(value.drive if side=="L" else value.lift_motion)
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
	# Head looks down at the active control, then back along the track.
	var spin: float = value.spin
	var intent := (blend_between(.1,.5,spin)-blend_between(2.8,3.5,spin))
	var head: int = bones["DEF-head"]
	var head_rest: Transform3D = bone_rest["DEF-head"]
	var lean := .10*intent + .07*(1.0-float(value.extension)) + .065*float(value.drive) + .055*float(value.lift_motion)
	var glance := .08*(blend_between(.3,.5,spin)-blend_between(2.8,3.3,spin)) + .10*float(value.lift_motion)
	skeleton.set_bone_global_pose(head,Transform3D(Basis(Vector3.UP,glance)*Basis(Vector3.RIGHT,lean)*head_rest.basis,head_rest.origin))
	for side in ["L","R"]:
		var target := _control("OP_GripContact_"+side).global_position
		var touch := 0.0
		var touch_target := target
		if side == "L" and spin < .70:
			# Already poised above Start while waiting: contact at the first spin frame.
			touch = (1.0-blend_between(.20,.70,spin))*(1.0-blend_between(0.0,.15,float(value.drive)))
			touch_target = _control("OP_StartContact").global_position
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
		target = target.lerp(touch_target,touch)
		_pose_arm(side,target)
		_pose_leg(side,_control("OP_FootContact_"+side).global_position)
	skeleton.force_update_all_bone_transforms()

func _bone_pose(key: String, origin: Vector3, direction: Vector3) -> void:
	var bind: Transform3D = bone_rest[key]
	var rotation := Quaternion(bind.basis.y.normalized(),direction.normalized())
	skeleton.set_bone_global_pose(int(bones[key]),Transform3D(Basis(rotation)*bind.basis,origin))

func _solve_limb(a: String, b: String, end: String, target: Vector3, pole: Vector3) -> Vector3:
	var ar: Transform3D = bone_rest[a]
	var br: Transform3D = bone_rest[b]
	var er: Transform3D = bone_rest[end]
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

func _pose_arm(side: String, world_contact: Vector3) -> void:
	var target := skeleton.to_local(world_contact)
	# The contact lies on the mitten surface, beyond its wrist bone.
	var palm_offset := Vector3(0.0,0.0,.100)
	var wrist := target-palm_offset
	var reached := _solve_limb("DEF-upper_arm."+side,"DEF-forearm."+side,"DEF-hand."+side,wrist,Vector3(1 if side=="L" else -1,-.35,0))
	_bone_pose("DEF-hand."+side,reached,Vector3.BACK)
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
	var offset := target - shoulder.origin
	var shift := offset.normalized() * maxf(0.0, offset.length() - reach + .002) if weight > 0.0 else Vector3.ZERO
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
