extends Node
## Wall speed tab stow v3 (side gantries): Blender "Stow"/"Deploy" clips on one stow clock p, and the
## folded gantries' transport pose (Gantry_Upright) and fold-down (SawChaseController).
var failures: Array[String]=[]
var checks:=0
var report:={}
const PARK_HUB_X:=[-16.6075,-15.7575,-14.9075,-14.0575,14.0575,14.9075,15.7575,16.6075]
const PARK_HUB_Y:=-1.90
const WALL_HALF_WIDTH:=11.9 # QuizWall spans the floor minus 0.1 m per side
const SHAFT_STUB:=.1075 # spindle stub pointing back toward the belt from the parked hub
const STATION_OUTER_X:=13.85 # operator deck, outboard edge
const HUB_SPEED:=7.5*SawChaseController.STOW_SPEED # m/s: gather and hoist peaks about 6.7 m/s
# m/s^2 between consecutive frames (velocity change / dt). The design peak is the lift-off of the bunch
# (about 32 m/s^2, ~47 once sampled at 24 fps and interpolated cubically); a pose jump would read far higher.
const HUB_ACCEL:=60.0
const REVERSALS:=[0.6,1.8,2.9,3.6,4.6,6.0]
# Service-vessel lift-bay posts (carriage frame, Blender axes): |x| >= 12.275, |y| 1.14..1.66, top z 0.605.
const POST_X:=12.265
const POST_Y:=Vector2(1.13,1.67)
const POST_TOP:=.615
const GANTRY_PREFIXES:=["Gantry","GantryS2","GantryS3","Hook","Spreader","GJaw","Rope"]

func check(value: bool,label: String) -> void:
	checks+=1
	if not value and not failures.has(label):failures.append(label)

func _ready() -> void:
	var stowed_poses:=[]
	var p_at_3:=[]
	for fps in [30,60,120]:
		var dt:=1.0/float(fps)
		var saw:=SawChaseController.new()
		add_child(saw)
		saw.update_preview(5.0)
		var sk:=saw.skeleton
		var length:=saw.stow_length()
		if fps==30:_check_clips(saw)
		check(saw.is_stow_clear() and _at_rest(saw),"deployed pose is rest (gantries folded beside the conveyor)")
		check(is_zero_approx(saw.gantry_upright_weight()),"no vessel: gantries hang folded")
		check(not saw.beacons_lit(),"beacons dark at rest")
		# Stow the way the menu does: preview clock frozen, stow advanced every frame.
		saw.stow_target=true
		var track:=_Track.new(saw)
		var spin_before:=saw._spin_extra
		var lit:=false
		var frames:=0
		while not saw.is_fully_stowed() and frames<int((length+3.0)*fps):
			saw.update_preview(0.0)
			saw.advance_stow(dt)
			track.step(saw,dt)
			lit=lit or saw.beacons_lit()
			frames+=1
			if frames==3*fps:p_at_3.append(saw.stow_time())
		var stow_seconds:=frames*dt
		var stow_expected:=length/SawChaseController.STOW_SPEED
		check(saw.is_fully_stowed() and absf(stow_seconds-stow_expected)<=dt+.08,"stow completes on the clip clock (%.3f s of %.3f)"%[stow_seconds,stow_expected])
		check(track.max_speed<=HUB_SPEED,"stow hub speed %.2f m/s"%track.max_speed)
		check(track.max_accel<=HUB_ACCEL,"stow hub motion continuous (%.1f m/s^2 at p=%.3f, %d fps)"%[track.max_accel,track.accel_at,fps])
		check(lit,"beacons flash while the machine works")
		var coast:=saw._spin_extra-spin_before
		check(coast>.05 and coast<saw.stow_brake_seconds(),"blades coast to a stop")
		var spin_q:=sk.get_bone_pose_rotation(saw.spin_bones[0])
		saw.advance_stow(dt)
		check(sk.get_bone_pose_rotation(saw.spin_bones[0]).is_equal_approx(spin_q),"parked blades stay still")
		check(not saw.beacons_lit(),"beacons go dark once parked")
		var centers:=_centers(saw)
		for i in 8:
			var side:=-1.0 if i<4 else 1.0
			var expected:=Vector3(PARK_HUB_X[i],PARK_HUB_Y,0.0)
			check(centers[i].distance_to(expected)<.003,"blade %d hung beside the conveyor at %s (%s)"%[i+1,expected,centers[i]])
			var axis:=(sk.get_bone_global_pose(saw.spin_bones[i]).basis.y).normalized()
			check(absf(axis.y)<.01 and axis.x*side>.99,"blade %d upright, print facing outward"%[i+1])
			check(absf(centers[i].x)-SHAFT_STUB-.03>STATION_OUTER_X,"blade %d outboard of the walls and the operator deck"%[i+1])
			check(centers[i].y+SawChaseState.BLADE_RADIUS<-.4,"blade %d below the belt surface"%[i+1])
			if i%4!=0:check(absf(centers[i].x-centers[i-1].x)>=.8,"bunch spacing %d"%[i+1])
		stowed_poses.append(_pose(saw))
		if fps==60:
			report.stowed_centers=centers.map(func(c:Vector3):return [snappedf(c.x,.001),snappedf(c.y,.001),snappedf(c.z,.001)])
			report.stow_hub_speed=snappedf(track.max_speed,.001)
			report.stow_hub_accel=snappedf(track.max_accel,.01)
		# Deploy back to the chase pose.
		saw.stow_target=false
		track=_Track.new(saw)
		frames=0
		while not saw.is_stow_clear() and frames<int((length+3.0)*fps):
			saw.update_preview(0.0)
			saw.advance_stow(dt)
			track.step(saw,dt)
			frames+=1
		check(saw.is_stow_clear() and _at_rest(saw),"deploy restores every bone to rest, gantries folded")
		check(absf(frames*dt-length/SawChaseController.STOW_SPEED)<=dt+.03,"deploy takes the clip length (%.3f s)"%(frames*dt))
		check(track.max_speed<=HUB_SPEED and track.max_accel<=HUB_ACCEL,"deploy motion continuous (%.2f m/s, %.1f m/s^2 at p=%.3f, %d fps)"%[track.max_speed,track.max_accel,track.accel_at,fps])
		check(not saw.beacons_lit(),"beacons dark after deploy")
		var before:=sk.get_bone_pose_rotation(saw.spin_bones[0])
		saw.update_preview(dt)
		check(not sk.get_bone_pose_rotation(saw.spin_bones[0]).is_equal_approx(before),"spin resumes after deploy")
		if fps==60:
			_check_reversals(saw,dt)
			_check_toggling(saw,dt)
			_check_api(saw)
			_check_envelopes(saw)
		saw.free()
	for i in range(1,stowed_poses.size()):
		var same:=true
		for k in stowed_poses[0].size():same=same and (stowed_poses[i][k] as Vector3).distance_to(stowed_poses[0][k])<1e-4
		check(same,"stowed pose identical at every fps")
	check(p_at_3.size()==3 and absf(p_at_3[0]-p_at_3[1])<1e-9 and absf(p_at_3[0]-p_at_3[2])<1e-9,"stow clock identical at 30/60/120 fps %s"%str(p_at_3))
	_check_vessel_fold()
	_check_fallback()
	_check_retreat()
	report.checks=checks
	report.failures=failures
	print("SAW_STOW_UNIT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

## On the vessel the folded gantries stand upright; once the carriage is on the belt they swing down
## beside the conveyor, and a stow requested meanwhile waits until they hang.
func _check_vessel_fold() -> void:
	var dt:=1.0/60.0
	var saw:=SawChaseController.new()
	add_child(saw)
	saw.configure_entrance(true,true)
	saw.update_preview(0.0)
	var sk:=saw.skeleton
	check(is_equal_approx(saw.gantry_upright_weight(),1.0),"gantries upright while the vessel carries the carriage")
	var upright_ok:=true
	for i in saw._gantry_bones.size():
		upright_ok=upright_ok and sk.get_bone_pose_rotation(saw._gantry_bones[i]).is_equal_approx(saw._gantry_upright[i])
	check(upright_ok and saw._gantry_bones.size()==2,"hinge roots take the Gantry_Upright pose")
	var folding_at:=-1.0
	var stow_waited:=true
	var held_upright:=true # the spin clip is seeked every frame; the hinge roots must stay upright through it
	var frames:=0
	while frames<int(20.0/dt):
		saw.update_preview(dt)
		if saw.dock.is_deployed():saw.stow_target=true
		saw.advance_stow(dt)
		if not saw.dock.is_deployed():
			for i in saw._gantry_bones.size():
				held_upright=held_upright and sk.get_bone_pose_rotation(saw._gantry_bones[i]).is_equal_approx(saw._gantry_upright[i])
		var up:=saw.gantry_upright_weight()
		if folding_at<0.0 and up<1.0:folding_at=saw.dock.elapsed
		if up>0.0 and saw.stow_time()>0.0:stow_waited=false
		frames+=1
		if saw.stow_time()>.5:break
	check(folding_at>=SawDockPresentation.READY_TIME and folding_at<SawDockPresentation.READY_TIME+.4,"gantries start folding once the carriage is on the belt (%.2f s)"%folding_at)
	check(stow_waited and saw.stow_time()>0.0,"a stow waits for the gantries to finish folding")
	check(held_upright,"gantries stay upright every frame the vessel carries the carriage")
	saw.free()
	# Skipped entrance / retry: folded at once.
	saw=SawChaseController.new()
	add_child(saw)
	saw.configure_entrance(true,false)
	saw.update_preview(0.0)
	check(is_zero_approx(saw.gantry_upright_weight()) and _at_rest(saw),"restored deployed: gantries already folded")
	saw.free()

## Racked, the carriage backs away to the end of the belt (the menu chase's home Z) and rolls forward
## again to where it stowed before the deploy starts.
func _check_retreat() -> void:
	var dt:=1.0/60.0
	var saw:=SawChaseController.new()
	add_child(saw)
	saw.update_preview(5.0)
	var from_z:=1.65
	saw.position.z=from_z
	saw.stow_target=true
	var frames:=0
	while saw.position.z<SawDockPresentation.MENU_Z-.0001 and frames<int(40.0/dt):
		saw.advance_stow(dt);frames+=1
	check(saw.is_fully_stowed() and is_equal_approx(saw.position.z,SawDockPresentation.MENU_Z),"stowed carriage backs away to the end of the belt (z %.3f)"%saw.position.z)
	for i in 120:saw.advance_stow(dt)
	check(is_zero_approx(saw._retreat_speed) and is_equal_approx(saw.position.z,SawDockPresentation.MENU_Z),"carriage stays put at the end of the belt")
	saw.stow_target=false
	var p_at_start:=saw.stow_time()
	var rolled_before_deploy:=true
	frames=0
	while not saw.is_stow_clear() and frames<int(40.0/dt):
		saw.advance_stow(dt)
		if saw._retreat>0.0 and saw.stow_time()<p_at_start-.0001:rolled_before_deploy=false
		frames+=1
	check(rolled_before_deploy,"deploy waits until the carriage is back where it stowed")
	check(saw.is_stow_clear() and is_equal_approx(saw.position.z,from_z),"carriage ends the deploy where it stowed (z %.3f)"%saw.position.z)
	saw.free()

class _Track:
	var prev: Array[Vector3]=[]
	var velocity: Array[Vector3]=[]
	var max_speed:=0.0
	var max_accel:=0.0
	var accel_at:=-1.0 # stow clock p of the largest velocity change
	func _init(saw: SawChaseController) -> void:
		prev=_hubs(saw)
	func step(saw: SawChaseController,dt: float) -> void:
		var now:=_hubs(saw)
		var v: Array[Vector3]=[]
		for i in now.size():
			v.append((now[i]-prev[i])/dt)
			max_speed=maxf(max_speed,v[i].length())
			if not velocity.is_empty() and (v[i]-velocity[i]).length()/dt>max_accel:
				max_accel=(v[i]-velocity[i]).length()/dt;accel_at=saw.stow_time()
		velocity=v
		prev=now
	static func _hubs(saw: SawChaseController) -> Array[Vector3]:
		var out: Array[Vector3]=[]
		for bone in saw.spin_bones:out.append(saw.skeleton.get_bone_global_pose(bone).origin)
		return out

func _check_clips(saw: SawChaseController) -> void:
	var data:=saw._stow_data
	check(saw._stow_anims.size()==2,"Stow and Deploy clips imported")
	check(saw.animation.has_animation(SawChaseController.UPRIGHT_CLIP),"Gantry_Upright clip imported")
	check(not bool(data.fallback) and int(FileAccess.file_exists(SawChaseController.STOW_DATA_PATH))==1,"sidecar JSON loaded")
	for anim in saw._stow_anims:
		check(absf(anim.length-saw.stow_length())<=1.0/24.0+.001,"clip length %.3f matches the sidecar %.3f"%[anim.length,saw.stow_length()])
	check(saw.spin_bones.size()==8 and saw._stow_bones.size()>=70,"stow tracks bound to %d bones"%saw._stow_bones.size())
	var gantry:=0
	for bone in saw._stow_bones:
		if saw.skeleton.get_bone_name(bone).get_slice("_",0) in GANTRY_PREFIXES:gantry+=1
	check(gantry==20,"all 20 gantry bones animated (%d)"%gantry)
	check(not (data.wall_block as Array).is_empty() and float(data.wall_block[0].reach_y)>1.5,"wall block interval with reach")
	check((data.station_airspace as Array).size()==2 and (data.chair_column as Array).size()==2,"station and chair intervals")
	check((data.speed_env as PackedFloat32Array).size()>=int(saw.stow_length()*30.0),"30 Hz speed curve")
	report.length=snappedf(saw.stow_length(),.0001)
	report.wall_block=data.wall_block
	report.station_airspace=data.station_airspace
	report.chair_column=data.chair_column
	# The gantry moves rigidly (stages slide); only the rope stretches (and the hidden ram tubes).
	var scaled:=[]
	for anim in saw._stow_anims:
		for t in anim.get_track_count():
			var bone:=str(anim.track_get_path(t).get_concatenated_subnames())
			if anim.track_get_type(t)==Animation.TYPE_SCALE_3D and bone.get_slice("_",0) in GANTRY_PREFIXES and not bone.begins_with("Rope_"):scaled.append(bone)
	check(scaled.is_empty(),"no scale tracks on gantry, hook, spreader or jaw bones %s"%str(scaled))
	var skinned:=saw.model.find_child("SAW_StowSkinned",true,false) as MeshInstance3D
	check(skinned!=null and skinned.mesh.get_surface_count()<=8,"stow machine is one skinned mesh with few surfaces")
	var total:=0
	for node in saw.model.find_children("*","MeshInstance3D",true,false):total+=(node as MeshInstance3D).mesh.get_surface_count()
	# The carriage alone is 250 surfaces; the stow machine adds <= 8.
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
		check(track.max_speed<=HUB_SPEED and track.max_accel<=HUB_ACCEL,"reversal at p=%.1f continuous (%.2f m/s, %.1f m/s^2 at p=%.3f)"%[p_rev,track.max_speed,track.max_accel,track.accel_at])
		check(turned>=0.0 and turned<=1.6,"reversal at p=%.1f slows down before turning (%.2f s)"%[p_rev,turned])
		check(saw.is_stow_clear() and _at_rest(saw),"reversal at p=%.1f returns to rest"%p_rev)
		worst=[maxf(worst[0],track.max_speed),maxf(worst[1],track.max_accel)]
	report.reversal_worst=[snappedf(worst[0],.001),snappedf(worst[1],.01)]

func _check_toggling(saw: SawChaseController,dt: float) -> void:
	var track:=_Track.new(saw)
	var time:=0.0
	var peak_p:=0.0
	for i in int(6.0/dt):
		if fmod(time,.4)<.2:saw.stow_target=true
		else:saw.stow_target=false
		if i<int(2.0/dt):saw.stow_target=true # get well into the move first
		saw.advance_stow(dt)
		track.step(saw,dt)
		peak_p=maxf(peak_p,saw.stow_time())
		time+=dt
	saw.stow_target=false
	var frames:=0
	while not saw.is_stow_clear() and frames<int((saw.stow_length()+4.0)/dt):
		saw.advance_stow(dt);track.step(saw,dt);frames+=1
	check(peak_p>1.5 and track.max_speed<=HUB_SPEED and track.max_accel<=HUB_ACCEL,"toggling every 0.2 s stays continuous (%.2f m/s, %.1f m/s^2)"%[track.max_speed,track.max_accel])
	check(saw.is_stow_clear() and _at_rest(saw),"toggling ends at rest")
	report.toggle=[snappedf(track.max_speed,.001),snappedf(track.max_accel,.01)]

func _check_api(saw: SawChaseController) -> void:
	var data:=saw._stow_data
	var block: Dictionary=data.wall_block[0]
	var station: Array=data.station_airspace
	var chair: Array=data.chair_column
	var length:=saw.stow_length()
	var span:=1.5*SawChaseController.STOW_SPEED
	var cases:=[
		# [p, target, rate, over station, chair clear(1.5)]
		[0.0,false,0.0,false,true],
		[(float(block.from)+float(block.to))/2.0,true,1.0,false,false],
		[(float(station[0])+float(station[1]))/2.0,true,1.0,true,false],
		[float(chair[0])-span+.3,true,1.0,false,false],
		[float(chair[1])+.2,true,1.0,false,true],
		[float(chair[1])+span-.3,false,-1.0,false,false],
		[length,true,0.0,false,true],
	]
	for c in cases:
		saw._stow_p=c[0];saw.stow_target=c[1];saw._stow_rate=c[2]
		var blocks:=saw.stow_blocks_walls()
		var expect_blocks: bool=float(c[0])>float(block.from) and float(c[0])<float(block.to)
		check(blocks==expect_blocks,"stow_blocks_walls at p=%.2f"%c[0])
		check(not blocks or absf(saw.wall_reach_y()-float(block.reach_y))<1e-6,"wall_reach_y at p=%.2f"%c[0])
		check(saw.rack_over_station()==c[3],"rack_over_station at p=%.2f"%c[0])
		check(saw.chair_launch_clear(1.5)==c[4],"chair_launch_clear(1.5) at p=%.2f target=%s"%[c[0],str(c[1])])
	saw._stow_p=0.0;saw._stow_rate=0.0;saw.stow_target=false

## Stow mesh vertices (Blender carriage axes) for the current skeleton pose: (|x|, |y|, z) per gantry vertex.
func _gantry_vertices(saw: SawChaseController) -> PackedVector3Array:
	var skinned:=saw.model.find_child("SAW_StowSkinned",true,false) as MeshInstance3D
	var skin:=skinned.skin
	var sk:=saw.skeleton
	var pose_of:={}
	for b in skin.get_bind_count():
		var name:=str(skin.get_bind_name(b))
		if not (name.get_slice("_",0) in GANTRY_PREFIXES or name=="Carriage"):continue
		pose_of[b]=sk.get_bone_global_pose(sk.find_bone(name))*skin.get_bind_pose(b)
	var out:=PackedVector3Array()
	for s in skinned.mesh.get_surface_count():
		var arrays:=skinned.mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var per:=bones.size()/maxi(vertices.size(),1)
		for i in vertices.size():
			var b:=bones[i*per]
			if not pose_of.has(b):continue
			var v: Vector3=pose_of[b]*vertices[i]
			out.append(Vector3(absf(v.x),absf(-v.z),v.y))
	return out

## Folded at rest the gantries hang outboard of the walls and the side frame; upright on the vessel they
## stay inside the lift-bay posts' reach.
func _check_envelopes(saw: SawChaseController) -> void:
	var inner:=INF
	var top:=-INF
	for v in _gantry_vertices(saw):
		if v.z>0.0:top=maxf(top,v.z)
		inner=minf(inner,v.x)
	check(inner>WALL_HALF_WIDTH+.03,"folded gantries clear of the walls (inner |x| %.3f)"%inner)
	check(top<.6,"folded gantries stay below the bogie tops (z %.3f)"%top)
	saw._gantry_fold=0.0
	saw._gantry_up=-1.0
	saw._apply_gantry_fold()
	saw.skeleton.force_update_all_bone_transforms()
	var worst_post:=-INF
	var height:=-INF
	for v in _gantry_vertices(saw):
		height=maxf(height,v.z)
		# Rising, the carriage passes between the posts (their y band, any height); rolling off the lift it
		# passes them lengthwise, so below their tops every y counts.
		var in_post_band:=v.y>=POST_Y.x and v.y<=POST_Y.y
		var swept:=v.z<=POST_TOP
		if in_post_band or swept:worst_post=maxf(worst_post,v.x)
	check(worst_post<POST_X,"upright gantries clear of the vessel's lift posts (|x| %.3f)"%worst_post)
	report.envelope={"folded_inner_x":snappedf(inner,.001),"folded_top_z":snappedf(top,.001),"upright_post_x":snappedf(worst_post,.001),"upright_height":snappedf(height,.001)}
	saw._gantry_fold=SawChaseController.GANTRY_FOLD_DELAY+SawChaseController.GANTRY_FOLD_SECONDS
	saw._gantry_up=-1.0
	saw._apply_gantry_fold()
	saw.skeleton.force_update_all_bone_transforms()

func _check_fallback() -> void:
	var data:=SawChaseController.load_stow_data("res://assets/hazards/missing_stow_sidecar.json",6.0)
	check(bool(data.fallback) and is_equal_approx(float(data.length),6.0),"missing sidecar falls back to the clip length")
	var saw:=SawChaseController.new()
	add_child(saw)
	saw.update_preview(1.0)
	saw._stow_data=data
	saw._stow_p=3.0;saw.stow_target=false;saw._stow_rate=-1.0
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
		if prefix!="Spin":
			if not sk.get_bone_pose(bone).is_equal_approx(sk.get_bone_rest(bone)):return false
		else:
			if sk.get_bone_pose_position(bone).distance_to(sk.get_bone_rest(bone).origin)>1e-4:return false
			# Spin keeps its own angle about the upright axis only.
			if absf(sk.get_bone_pose(bone).basis.y.normalized().dot(Vector3.UP)-1.0)>1e-4:return false
	return true
