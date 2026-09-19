extends Node

const OUT := "res://artifacts/saw_landing/"
var elapsed := 0.0
var landed_at := -1.0
var spin_at := -1.0
var early_spin := false
var airborne_saved := false
var landed_saved := false
var start_rotation := Quaternion.IDENTITY
var initialized := false
var maximum_rotation_change := 0.0
var impacts: Array = []

func _ready() -> void:
	process_priority = 100
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func save_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + label + ".png")

func _process(dt: float) -> void:
	var world := get_tree().current_scene
	if world == null or world.scene_file_path != "res://scenes/game_world.tscn": return
	var saw: SawChaseController = world._saw_controller
	var director: HelicopterArrivalDirector = world._helicopter_arrival_director
	if saw == null or saw.skeleton == null or director == null: return
	var gs: QuizGameState = QuizManager.game_state
	elapsed += dt
	var landed := director.have_players_touched_down()
	if not initialized:
		initialized = true
		start_rotation = saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0])
	var angular_change := start_rotation.angle_to(saw.skeleton.get_bone_pose_rotation(saw.spin_bones[0]))
	if not landed:
		early_spin = early_spin or saw._landing_spin_elapsed > 0.0 or angular_change > 0.001
		if director._total_elapsed > 3.0 and not airborne_saved:
			airborne_saved = true
			save_frame("airborne_stopped")
	elif landed_at < 0.0:
		landed_at = elapsed
		for info: Dictionary in director._helicopters:
			impacts.append(bool(info.get("impact_played", false)))
	if saw._landing_spin_elapsed > 0.0 and spin_at < 0.0: spin_at = elapsed
	if landed_at >= 0.0:
		maximum_rotation_change = maxf(maximum_rotation_change, angular_change)
		if elapsed - landed_at > 1.2 and not landed_saved:
			landed_saved = true
			save_frame("landed_spinning")
		if elapsed - landed_at > 4.3:
			var passed: bool = not early_spin and impacts == [true, true] and absf(spin_at - landed_at) < 0.1 and maximum_rotation_change > 0.3 and gs.saw.elapsed == 0.0 and gs.saw.local_z == SawChaseState.INITIAL_Z
			var result := {"passed":passed,"early_spin":early_spin,"landing_at":landed_at,"spin_at":spin_at,"floor_contacts":impacts,"rotation_change":maximum_rotation_change,"state":gs.game_state,"pursuit_elapsed":gs.saw.elapsed,"position":gs.saw.local_z}
			FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
			print("SAW_LANDING ",JSON.stringify(result))
			queue_free()
	if elapsed > 35.0:
		FileAccess.open(OUT + "runtime.json", FileAccess.WRITE).store_string(JSON.stringify({"passed":false,"reason":"landing timeout"}))
		queue_free()
