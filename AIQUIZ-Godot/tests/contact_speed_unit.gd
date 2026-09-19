extends SceneTree

const Duel = preload("res://scripts/core/local_push_duel.gd")
const OUT := "res://artifacts/contact_speed_fix/"
var failures: Array[String] = []
var metrics: Array[Dictionary] = []
var checks := 0

func _initialize() -> void:
	await process_frame
	for fps in [30, 60, 120]:
		for direction in [-1.0, 1.0]:
			for order in [-1.0, 1.0]:
				for z in [0.0, 0.4]:
					for center in [-2.3, 0.0, 2.3]:
						_case(fps, direction, order, z, center)
	var report := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics}
	FileAccess.open(OUT + "contact_unit.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CONTACT_SPEED_UNIT " + JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures.size(),"cases":metrics.size()}))
	quit(0 if failures.is_empty() else 1)

func _case(fps: int, direction: float, order: float, z: float, center: float) -> void:
	var duel = Duel.new()
	var width := sqrt(1.24 * 1.24 - z * z)
	var positions := Vector2(center - order * width * 0.5, center + order * width * 0.5)
	# Establish opposing contact before both players choose the same direction.
	positions = duel.advance(0.2, positions, z, [true,true], [true,true], Vector2(order,-order), 7.6)
	var start := positions
	var minimum_speed := 100.0
	var maximum_gap_error := 0.0
	for i in range(fps / 2):
		var before := positions
		positions = duel.advance(1.0 / fps, positions, z, [true,true], [true,true], Vector2.ONE * direction, 7.6)
		minimum_speed = minf(minimum_speed, ((positions.x + positions.y - before.x - before.y) * 0.5) * direction * fps)
		maximum_gap_error = maxf(maximum_gap_error, absf(absf(positions.y - positions.x) - width))
	var distance := (positions - start) * direction
	var label := str([fps,direction,order,z,center])
	check(absf(distance.x - 3.8) < 0.0001 and absf(distance.y - 3.8) < 0.0001, "both retain ordinary speed " + label)
	check(minimum_speed > 7.59, "no temporary slowdown frame " + label)
	check(maximum_gap_error < 0.00001, "contact spacing retained " + label)
	var hits := 0
	for event: Dictionary in duel.events:
		if event.kind in ["hit","clash"]: hits += 1
	check(hits == 0, "shared movement does not trigger strike " + label)
	metrics.append({"fps":fps,"direction":direction,"order":order,"z":z,"center":center,"distance":[distance.x,distance.y],"minimum_speed":minimum_speed,"gap_error":maximum_gap_error})

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
