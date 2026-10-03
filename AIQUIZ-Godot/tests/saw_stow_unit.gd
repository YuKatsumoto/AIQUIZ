extends Node
## Wall speed tab stow v2: Blender "Stow"/"Deploy" clips on one stow clock p (SawChaseController).
var failures: Array[String]=[]
var checks:=0
var report:={}
const PARK_HUB_X:=[-16.6075,-15.7575,-14.9075,-14.0575,14.0575,14.9075,15.7575,16.6075]
const PARK_HUB_Y:=-1.90
const WALL_HALF_WIDTH:=11.9 # QuizWall spans the floor minus 0.1 m per side
const SHAFT_STUB:=.1075 # spindle stub pointing back toward the belt from the parked hub
const HUB_SPEED:=4.85*SawChaseController.STOW_SPEED # m/s: 4.5 m/s carry/gather peaks plus the baked sway and rocking, played faster
const VELOCITY_JUMP:=.5 # m/s between consecutive frames
const REVERSALS:=[0.8,2.5,4.0,6.2,7.5,10.0]
# Service-vessel lift-bay posts (carriage frame, Blender axes): |x| >= 12.275, |y| 1.14..1.66, top z 0.605.
const POST_X:=12.265
const POST_Y:=Vector2(1.13,1.67)
const POST_TOP:=.615

func check(value: bool,label: String) -> void:
	checks+=1
	if not value and not failures.has(label):failures.append(label)

func _ready() -> void:
	var stowed_poses:=[]
	var p_at_5:=[]
	for fps in [30,60,120]:
		var dt:=1.0/float(fps)
		var saw:=SawChaseController.new()
		add_child(saw)
		saw.update_preview(5.0)
		var sk:=saw.skeleton
		var length:=saw.stow_length()
		if fps==30:_check_clips(saw)
		check(saw.is_stow_clear() and _at_rest(saw),"deployed pose is rest")
		check(not saw.beacons_lit(),"beacons dark at rest")
		# Stow the way the menu does: preview clock frozen, stow advanced every frame.
		saw.stow_target=true
		var track:=_Track.new(saw)
		var spin_before:=saw._spin_extra
		var lit:=false
		var servo_heard:=false
		var frames:=0
		while not saw.is_fully_stowed() and frames<int((length+3.0)*fps):
			saw.update_preview(0.0)
			saw.advance_stow(dt)
			track.step(saw,dt)
			lit=lit or saw.beacons_lit()
			servo_heard=servo_heard or saw._stow_servo.playing
			frames+=1
			if frames==5*fps:p_at_5.append(saw.stow_time())
		var stow_seconds:=frames*dt
		# The towers stand up first: the clip waits at the hold point until they are upright.
		var stow_expected:=length/SawChaseController.STOW_SPEED+maxf(0.0,SawChaseController.TOWER_LAY_SECONDS-saw._tower_hold_p/SawChaseController.STOW_SPEED)
		check(saw.is_fully_stowed() and absf(stow_seconds-stow_expected)<=dt+.08,"stow completes on the clip clock (%.3f s of %.3f)"%[stow_seconds,stow_expected])
		check(track.max_speed<=HUB_SPEED,"stow hub speed %.2f m/s"%track.max_speed)
		check(track.max_jump<=VELOCITY_JUMP,"stow velocity continuous (%.3f m/s jump at p=%.3f, %d fps)"%[track.max_jump,track.jump_at,fps])
		check(lit,"beacons flash while the machine works")
		check(servo_heard,"servo sound follows the hydraulics")
		var coast:=saw._spin_extra-spin_before
		check(coast>.05 and coast<saw.stow_brake_seconds(),"blades coast to a stop")
		var spin_q:=sk.get_bone_pose_rotation(saw.spin_bones[0])
		saw.advance_stow(dt)
		check(sk.get_bone_pose_rotation(saw.spin_bones[0]).is_equal_approx(spin_q),"racked blades stay still")
		check(not saw.beacons_lit() and not saw._stow_servo.playing,"beacons and servo stop once parked")
		var centers:=_centers(saw)
		for i in 8:
			var side:=-1.0 if i<4 else 1.0
			var expected:=Vector3(PARK_HUB_X[i],PARK_HUB_Y,0.0)
			check(centers[i].distance_to(expected)<.003,"blade %d hung beside the conveyor at %s"%[i+1,expected])
			var axis:=(sk.get_bone_global_pose(saw.spin_bones[i]).basis.y).normalized()
			check(absf(axis.y)<.01 and axis.x*side>.99,"blade %d upright, print facing outward"%[i+1])
			check(absf(centers[i].x)-SHAFT_STUB-.03>WALL_HALF_WIDTH+2.0,"blade %d clear of the walls and the operator deck"%[i+1])
			check(centers[i].y+SawChaseState.BLADE_RADIUS<-.4,"blade %d below the belt surface"%[i+1])
			if i%4!=0:check(absf(centers[i].x-centers[i-1].x)>=.8,"rack spacing %d"%[i+1])
		stowed_poses.append(_pose(saw))
		if fps==60:
			report.stowed_centers=centers.map(func(c:Vector3):return [snappedf(c.x,.001),snappedf(c.y,.001),snappedf(c.z,.001)])
			report.stow_hub_speed=snappedf(track.max_speed,.001)
			report.stow_velocity_jump=snappedf(track.max_jump,.001)
		# Deploy back to the chase pose.
		saw.stow_target=false
		track=_Track.new(saw)
		frames=0
		while not saw.is_stow_clear() and frames<int((length+3.0)*fps):
			saw.update_preview(0.0)
			saw.advance_stow(dt)
			track.step(saw,dt)
			frames+=1
		check(saw.is_stow_clear() and _at_rest(saw),"deploy restores every bone to rest")
		check(absf(frames*dt-length/SawChaseController.STOW_SPEED)<=dt+.03,"deploy takes the clip length (%.3f s)"%(frames*dt))
		for i in int(SawChaseController.TOWER_LAY_SECONDS/dt)+2:saw.advance_stow(dt)
		check(is_equal_approx(saw._tower_lay,1.0),"towers lie flat after the deploy")
		check(track.max_speed<=HUB_SPEED and track.max_jump<=VELOCITY_JUMP,"deploy motion continuous (%.2f m/s, %.3f jump at p=%.3f, %d fps)"%[track.max_speed,track.max_jump,track.jump_at,fps])
		check(not saw.beacons_lit(),"beacons dark after deploy")
		var before:=sk.get_bone_pose_rotation(saw.spin_bones[0])
		saw.update_preview(dt)
		check(not sk.get_bone_pose_rotation(saw.spin_bones[0]).is_equal_approx(before),"spin resumes after deploy")
		if fps==60:
			_check_reversals(saw,dt)
			_check_toggling(saw,dt)
			_check_hidden_audio(saw,dt)
			_check_api(saw)
			_check_transport_envelope(saw)
		saw.free()
	for i in range(1,stowed_poses.size()):
		var same:=true
		for k in stowed_poses[0].size():same=same and (stowed_poses[i][k] as Vector3).distance_to(stowed_poses[0][k])<1e-4
		check(same,"stowed pose identical at every fps")
	check(p_at_5.size()==3 and absf(p_at_5[0]-p_at_5[1])<1e-9 and absf(p_at_5[0]-p_at_5[2])<1e-9,"stow clock identical at 30/60/120 fps %s"%str(p_at_5))
	_check_fallback()
	report.checks=checks
	report.failures=failures
	print("SAW_STOW_UNIT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

class _Track:
	var prev: Array[Vector3]=[]
	var velocity: Array[Vector3]=[]
	var max_speed:=0.0
	var max_jump:=0.0
	var jump_at:=-1.0 # stow clock p of the largest jump
	func _init(saw: SawChaseController) -> void:
		prev=_hubs(saw)
	func step(saw: SawChaseController,dt: float) -> void:
		var now:=_hubs(saw)
		var v: Array[Vector3]=[]
		for i in now.size():
			v.append((now[i]-prev[i])/dt)
			max_speed=maxf(max_speed,v[i].length())
			if not velocity.is_empty() and (v[i]-velocity[i]).length()>max_jump:
				max_jump=(v[i]-velocity[i]).length();jump_at=saw.stow_time()
		velocity=v
		prev=now
	static func _hubs(saw: SawChaseController) -> Array[Vector3]:
		var out: Array[Vector3]=[]
		for bone in saw.spin_bones:out.append(saw.skeleton.get_bone_global_pose(bone).origin)
		return out

func _check_clips(saw: SawChaseController) -> void:
	var data:=saw._stow_data
	check(saw._stow_anims.size()==2,"Stow and Deploy clips imported")
	check(not bool(data.fallback) and int(FileAccess.file_exists(SawChaseController.STOW_DATA_PATH))==1,"sidecar JSON loaded")
	for anim in saw._stow_anims:
		check(absf(anim.length-saw.stow_length())<=1.0/30.0+.001,"clip length %.3f matches the sidecar %.3f"%[anim.length,saw.stow_length()])
	check(saw.spin_bones.size()==8 and saw._stow_bones.size()>=100,"stow tracks bound to %d bones"%saw._stow_bones.size())
	for key in ["stow","deploy"]:
		var events: Array=data.events.get(key,[])
		check(not events.is_empty() and str(events[0].kind)=="horn" and float(events[0].t)<.2,"%s opens with the horn"%key)
		check(events.any(func(e):return str(e.kind)=="latch"),"%s has latch events"%key)
	check(not (data.wall_block as Array).is_empty() and float(data.wall_block[0].reach_y)>1.5,"wall block interval with reach")
	check((data.station_airspace as Array).size()==2 and (data.chair_column as Array).size()==2,"station and chair intervals")
	check((data.speed_env as PackedFloat32Array).size()>=int(saw.stow_length()*30.0),"30 Hz speed curve")
	report.length=snappedf(saw.stow_length(),.0001)
	report.wall_block=data.wall_block
	report.chair_column=data.chair_column
	# Towers, beams and jaws move rigidly: stages slide, nothing scales (only the hidden ram tubes do).
	var scaled:=[]
	for anim in saw._stow_anims:
		for t in anim.get_track_count():
			var bone:=str(anim.track_get_path(t).get_concatenated_subnames())
			if anim.track_get_type(t)==Animation.TYPE_SCALE_3D and bone.get_slice("_",0) in ["Davit","DavitS2","DavitS3","DavitS4","DavitS5","DavitS6","Knuckle","BeamFlyP","BeamFlyN","Jaw"]:scaled.append(bone)
	check(scaled.is_empty(),"no scale tracks on tower, beam or jaw bones %s"%str(scaled))
	var skinned:=saw.model.find_child("SAW_StowSkinned",true,false) as MeshInstance3D
	check(skinned!=null and skinned.mesh.get_surface_count()<=8,"stow machine is one skinned mesh with few surfaces")
	var total:=0
	for node in saw.model.find_children("*","MeshInstance3D",true,false):total+=(node as MeshInstance3D).mesh.get_surface_count()
	# v1 carried 294 surfaces, 44 of them its stow parts: the carriage alone is 250, the v2 machine adds <= 8.
	check(total<=258,"model surface budget (%d of 258)"%total)
	report.surfaces=total

func _check_reversals(saw: SawChaseController,dt: float) -> void:
	var worst:=[0.0,0.0]
	for p_rev in REVERSALS:
		saw.stow_target=true
		var guard:=0
		while saw.stow_time()<p_rev and guard<2000:
			saw.advance_stow(dt);guard+=1
		saw.stow_target=false
		var track:=_Track.new(saw)
		var turned:=-1.0
		var frames:=0
		while not saw.is_stow_clear() and frames<int((saw.stow_length()+4.0)/dt):
			saw.advance_stow(dt)
			track.step(saw,dt)
			frames+=1
			if turned<0.0 and saw._stow_rate<0.0:turned=frames*dt
		check(track.max_speed<=HUB_SPEED and track.max_jump<=VELOCITY_JUMP,"reversal at p=%.1f continuous (%.2f m/s, %.3f jump at p=%.3f)"%[p_rev,track.max_speed,track.max_jump,track.jump_at])
		check(turned>=0.0 and turned<=1.6,"reversal at p=%.1f slows down before turning (%.2f s)"%[p_rev,turned])
		check(saw.is_stow_clear() and _at_rest(saw),"reversal at p=%.1f returns to rest"%p_rev)
		worst=[maxf(worst[0],track.max_speed),maxf(worst[1],track.max_jump)]
	report.reversal_worst=[snappedf(worst[0],.001),snappedf(worst[1],.001)]

func _check_toggling(saw: SawChaseController,dt: float) -> void:
	var track:=_Track.new(saw)
	var time:=0.0
	var peak_p:=0.0
	for i in int(8.0/dt):
		if fmod(time,.4)<.2:saw.stow_target=true
		else:saw.stow_target=false
		if i<int(3.0/dt):saw.stow_target=true # get well into the move first
		saw.advance_stow(dt)
		track.step(saw,dt)
		peak_p=maxf(peak_p,saw.stow_time())
		time+=dt
	saw.stow_target=false
	var frames:=0
	while not saw.is_stow_clear() and frames<int((saw.stow_length()+4.0)/dt):
		saw.advance_stow(dt);track.step(saw,dt);frames+=1
	check(peak_p>2.0 and track.max_speed<=HUB_SPEED and track.max_jump<=VELOCITY_JUMP,"toggling every 0.2 s stays continuous (%.2f m/s, %.3f jump)"%[track.max_speed,track.max_jump])
	check(saw.is_stow_clear() and _at_rest(saw),"toggling ends at rest")
	report.toggle=[snappedf(track.max_speed,.001),snappedf(track.max_jump,.001)]

func _check_hidden_audio(saw: SawChaseController,dt: float) -> void:
	saw.stow_target=true
	for i in int(3.5/dt):saw.advance_stow(dt)
	var p:=saw.stow_time()
	check(saw._stow_servo.playing,"servo audible in the wall speed tab")
	for i in 10:saw.advance_stow(dt,false)
	check(saw.stow_time()>p and not saw._stow_servo.playing and not saw._stow_horn.playing,"hidden tab: stow advances silently")
	saw.advance_stow(0.0)
	check(not saw._stow_servo.playing,"dt = 0 silences the stow")
	saw.stow_target=false
	var frames:=0
	while not saw.is_stow_clear() and frames<int((saw.stow_length()+4.0)/dt):
		saw.advance_stow(dt);frames+=1

func _check_api(saw: SawChaseController) -> void:
	var data:=saw._stow_data
	var block: Dictionary=data.wall_block[0]
	var station: Array=data.station_airspace
	var chair: Array=data.chair_column
	var length:=saw.stow_length()
	var cases:=[
		# [p, target, rate, blocks walls, over station, chair clear(1.5)]
		[0.0,false,0.0,false,false,true],
		[(float(block.from)+float(block.to))/2.0,true,1.0,true,false,true],
		[(float(station[0])+float(station[1]))/2.0,true,1.0,false,true,false],
		[float(chair[0])-1.0,true,1.0,false,false,false],
		[float(chair[0])-1.5*SawChaseController.STOW_SPEED-.3,true,1.0,false,false,true],
		[float(chair[1])+.2,true,1.0,false,false,true],
		[float(chair[1])+1.0,false,-1.0,false,false,false],
		[length,true,0.0,false,false,true],
	]
	for c in cases:
		saw._stow_p=c[0];saw.stow_target=c[1];saw._stow_rate=c[2]
		var blocks:=saw.stow_blocks_walls()
		# The wall block covers the whole over-belt span, which may include the station interval.
		var expect_blocks: bool=c[3] or (float(c[0])>float(block.from) and float(c[0])<float(block.to))
		check(blocks==expect_blocks,"stow_blocks_walls at p=%.2f"%c[0])
		check(not blocks or absf(saw.wall_reach_y()-float(block.reach_y))<1e-6,"wall_reach_y at p=%.2f"%c[0])
		check(saw.rack_over_station()==c[4],"rack_over_station at p=%.2f"%c[0])
		check(saw.chair_launch_clear(1.5)==c[5],"chair_launch_clear(1.5) at p=%.2f target=%s"%[c[0],str(c[1])])
	saw._stow_p=0.0;saw._stow_rate=0.0;saw.stow_target=false

func _check_transport_envelope(saw: SawChaseController) -> void:
	# Rest (bind) pose of the stow mesh, Blender carriage axes: glTF (x, z, -y) back to (x, y, z).
	var skinned:=saw.model.find_child("SAW_StowSkinned",true,false) as MeshInstance3D
	var skin:=skinned.skin
	var tower_binds:={}
	for b in skin.get_bind_count():
		var name:=str(skin.get_bind_name(b))
		if name.get_slice("_",0) in ["Carriage","Davit","DavitS2","DavitS3","DavitS4","DavitS5","DavitS6","Knuckle","BeamFlyP","BeamFlyN","Jaw"]:tower_binds[b]=true
	var inner:=INF
	var worst_post:=-INF
	for s in skinned.mesh.get_surface_count():
		var arrays:=skinned.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var per:=bones.size()/maxi(vertices.size(),1)
		for i in vertices.size():
			if not tower_binds.has(bones[i*per]):continue
			var v:=vertices[i]
			var x:=absf(v.x)
			var y:=absf(-v.z)
			var z:=v.y
			inner=minf(inner,x)
			var in_post_band:=y>=POST_Y.x and y<=POST_Y.y
			var swept:=z<=POST_TOP and y<=POST_Y.y
			if in_post_band or swept:worst_post=maxf(worst_post,x)
	check(inner>WALL_HALF_WIDTH+.03,"stowed towers clear of the walls (inner |x| %.3f)"%inner)
	check(worst_post<POST_X,"stowed towers clear of the vessel's lift posts (|x| %.3f)"%worst_post)
	report.tower_envelope=[snappedf(inner,.001),snappedf(worst_post,.001)]

func _check_fallback() -> void:
	var data:=SawChaseController.load_stow_data("res://assets/hazards/missing_stow_sidecar.json",12.0)
	check(bool(data.fallback) and is_equal_approx(float(data.length),12.0),"missing sidecar falls back to the clip length")
	var saw:=SawChaseController.new()
	add_child(saw)
	saw.update_preview(1.0)
	saw._stow_data=data
	saw._stow_p=6.0;saw.stow_target=false;saw._stow_rate=-1.0
	check(saw.stow_blocks_walls() and not saw.chair_launch_clear(1.5),"fallback: walls break and the chair waits mid-stow")
	saw._stow_p=0.0;saw._stow_rate=0.0
	check(not saw.stow_blocks_walls() and saw.chair_launch_clear(1.5),"fallback: nothing blocks at rest")
	saw.free()

func _centers(saw: SawChaseController) -> Array[Vector3]:
	var out: Array[Vector3]=[]
	for bone in saw.spin_bones:out.append(saw.skeleton.get_bone_global_pose(bone).origin)
	return out

func _pose(saw: SawChaseController) -> Array:
	var out:=[]
	for bone in saw.skeleton.get_bone_count():
		out.append(saw.skeleton.get_bone_global_pose(bone).origin)
		out.append(saw.skeleton.get_bone_global_pose(bone).basis.y)
	return out

func _at_rest(saw: SawChaseController) -> bool:
	var sk:=saw.skeleton
	for bone in sk.get_bone_count():
		var prefix:=sk.get_bone_name(bone).get_slice("_",0)
		if prefix in ["Carriage","Roll"]:continue
		# Davit roots lie down about their luff hinge at rest; the rest of each tower stays at rest locally.
		if saw._tower_bones.has(bone):
			if sk.get_bone_pose_position(bone).distance_to(sk.get_bone_rest(bone).origin)>1e-4:return false
			continue
		if prefix!="Spin":
			if not sk.get_bone_pose(bone).is_equal_approx(sk.get_bone_rest(bone)):return false
		else:
			if sk.get_bone_pose_position(bone).distance_to(sk.get_bone_rest(bone).origin)>1e-4:return false
			# Spin keeps its own angle about the upright axis only.
			if absf(sk.get_bone_pose(bone).basis.y.normalized().dot(Vector3.UP)-1.0)>1e-4:return false
	return true
