extends Node

var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for path in ["res://scripts/world/helicopter_arrival_director.gd", "res://scripts/world/player_controller.gd", "res://scripts/world/physical_rope_ladder.gd", "res://scripts/ui/menu_helicopter_sequence_profile.gd"]:
		var script := load(path) as Script
		check(script != null and script.can_instantiate(), "script loads: " + path)
	var profile := load("res://scenes/menu_helicopter_sequence.tscn").instantiate() as MenuHelicopterSequenceProfile
	profile.prepare_runtime()
	get_tree().root.add_child(profile)
	var player := profile.get_node("AnimationPlayer") as AnimationPlayer
	for animation_name in player.get_animation_list():
		var animation := player.get_animation(animation_name)
		for track in range(animation.get_track_count()):
			var target := animation.track_get_path(track)
			check(profile.get_node_or_null(NodePath(target.get_concatenated_names())) != null, "track resolves: %s %s" % [animation_name, target])
	var director := HelicopterArrivalDirector.new()
	get_tree().root.add_child(director)
	var direction := Vector3(1.0, 0.0, 0.16).normalized()
	var pass_origin := Vector3(-16.5, 10.2, 0.0)
	var info := {"start": pass_origin - direction * 20.0 + Vector3.UP * 3.5, "hover_ocean": pass_origin, "direction": direction}
	var worst_velocity_join := 0.0
	for fps: int in [30, 60, 120]:
		var dt := 1.0 / fps
		var t := director.GP_APPROACH_DURATION
		var before: Vector3 = director._sample_gameplay_approach(info, t - dt)["position"]
		var at: Vector3 = director._sample_gameplay_approach(info, t)["position"]
		var after: Vector3 = director._sample_gameplay_approach(info, t + dt)["position"]
		var join_error := ((at - before) / dt).distance_to((after - at) / dt)
		worst_velocity_join = maxf(worst_velocity_join, join_error)
		check(join_error < 0.005, "continuous approach/pass velocity at %dfps" % fps)
		for i in range(fps * 5):
			var first: Vector3 = director._sample_gameplay_approach(info, i * dt)["position"]
			var second: Vector3 = director._sample_gameplay_approach(info, (i + 1) * dt)["position"]
			check((second - first).dot(direction) / dt > 1.49, "approach never reverses/stops at %dfps" % fps)
	profile.queue_free()
	director.queue_free()
	await get_tree().process_frame
	var result := {"passed": failures.is_empty(), "failures": failures, "join_velocity_error": worst_velocity_join}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/helicopter_crossing"))
	FileAccess.open("res://artifacts/helicopter_crossing/resources.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("HELICOPTER_CROSSING_RESOURCES ", JSON.stringify(result))
	get_tree().quit.call_deferred(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
