extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message): failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var samples := 0
	for fps in [24, 30, 60, 120]:
		var previous_travel := 0.0
		var previous_lift := 0.0
		var previous_ship := -10.0
		for frame in range(fps * 18 + 1):
			var time: float = float(frame) / fps
			var p := SawDockPresentation.pose_at(time)
			check(float(p.cover)==1.0 and float(p.shutter_speed)==0.0, "no shutter motion throughout lift sequence")
			if float(p.travel) > 0.0001 and float(p.travel) < 4.7999:
				check(float(p.lift) >= .9999 and float(p.lock) >= .9999, "transfer before rail lock")
				check(absf(float(p.ship_offset)) < .0001 and absf(float(p.speed)) < .0001, "ship moves during transfer")
				check(float(p.rock) < .0001, "ship rocks during transfer")
			if absf(float(p.lift)-previous_lift) > .000001:
				check(absf(float(p.ship_offset)-previous_ship)<.000001 and absf(float(p.speed))<.000001 and float(p.rock)<.000001,"vessel must be completely stopped throughout raising AND lowering")
			if time >= SawDockPresentation.TRANSFER_START and float(p.travel) < 4.7999:
				check(float(p.lift) >= .9999, "lowering under rear wheel")
			if time < 2.25:
				check(float(p.bridge) < .0001, "bridge extends before docking")
			if time >= SawDockPresentation.DEPARTURE_START:
				check(float(p.bridge) < .0001, "departure while connected")
				check(float(p.travel) - 1.45 >= 3.15, "rear wheel not on conveyor")
				check(float(p.lift)<.0001 and float(p.cover)>.9999,"departure requires lowered lift and open shutter")
			check(float(p.travel) >= previous_travel, "carriage reversed")
			check(float(p.travel) >= -.0001 and float(p.travel) <= 4.8001, "travel overshoot")
			check(float(p.ship_offset) <= .0001, "hull crossed dock stop")
			for i in 24:
				var slat := SawDockPresentation.shutter_pose(i, p.cover)
				check(slat.z <= 0.0 or slat.x <= -2.15, "coil intersects well")
			previous_travel = float(p.travel)
			previous_lift = float(p.lift)
			previous_ship = float(p.ship_offset)
			samples += 1
	var dock := SawDockPresentation.new()
	dock.begin()
	dock.advance(1.0)
	check(dock.wheel_distance() == 0.0, "ship motion turned carriage wheels")
	var hold := dock.elapsed
	dock.advance(-1.0)
	check(dock.elapsed == hold, "negative dt")
	dock.advance(SawDockPresentation.READY_TIME - 1.0)
	check(dock.is_deployed() and dock.carriage_position().is_equal_approx(Vector3(0,-1.2,-10.85)), "game handoff")
	check(not dock.has_departed(), "handoff waited for departure")
	dock.advance(3.0)
	check(dock.carriage_position().is_equal_approx(Vector3(0,-1.2,-10.85)), "departing vessel carried saw")
	dock.direction = -1.0
	dock.final_z = 6.35
	check(dock.carriage_position().is_equal_approx(Vector3(0,-1.2,6.35)), "menu handoff")
	dock.restore_deployed()
	check(dock.has_departed() and dock.wheel_distance() == 0.0 and dock.framing_weight() == 0.0, "retry restoration")
	dock.advance(1.0)
	check(dock.elapsed == dock.FINISH_TIME and not dock.animated, "restoration replayed")
	dock.begin()
	dock.advance(SawDockPresentation.DEPARTURE_START)
	check(not dock.has_departed() and dock.menu_framing_weight()==1.0,"menu camera moves before departure starts")
	dock.advance(3.0)
	check(not dock.has_departed() and is_equal_approx(dock.menu_framing_weight(),0.5),"menu camera must return together with departing ship")
	dock.advance(3.0)
	check(dock.menu_framing_weight()==0.0,"menu camera never returns to original")
	dock.advance(100.0)
	check(dock.has_departed() and dock.elapsed == dock.FINISH_TIME and dock.wheel_distance() == 4.8, "large dt")
	dock.free()
	var result := {"passed":failures.is_empty(),"checks":checks,"pose_samples":samples,"fps":[24,30,60,120],"failures":failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/saw_vessel"))
	FileAccess.open("res://artifacts/saw_vessel/revision2/unit.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SAW_VESSEL_UNIT ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
