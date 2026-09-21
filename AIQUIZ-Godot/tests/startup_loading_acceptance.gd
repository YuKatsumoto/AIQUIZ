extends Node

var _failures: Array[String] = []
var _checks := 0
var _output := "res://artifacts/startup_loading/"

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("STARTUP_TEST " + message)

func capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_output + name + ".png")
	return image

func image_has_loading_ui(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	var width: int = image.get_width()
	var height: int = image.get_height()
	var hits := 0
	for y: int in range(maxi(0, height - 160), height):
		for x: int in range(0, mini(width, 380)):
			var color: Color = image.get_pixel(x, y)
			if color.r > 0.22 or color.g > 0.22 or color.b > 0.30:
				hits += 1
				if hits >= 24:
					return true
	return false

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	GameManager.tutorial_prompt_seen_version = GameManager.CURRENT_TUTORIAL_VERSION
	var gs := QuizManager.game_state
	var before := [gs.num_players, gs.mode, gs.p1_alive, gs.p2_alive, gs.quiz_list.size()]
	get_tree().change_scene_to_file("res://ui/startup_loading.tscn")
	var started := Time.get_ticks_msec()
	var poses: Array[float] = []
	var captures := 0
	var two_d_checked := false
	while Time.get_ticks_msec() - started < 90000:
		await get_tree().process_frame
		var loader := GameManager.get_node_or_null("StartupLoading")
		if loader != null:
			var status: Label = loader.get("_status")
			var bar: ProgressBar = loader.get("_progress")
			if not two_d_checked and status != null and bar != null and bar.size.y >= 8.0:
				check(status.visible and status.text.begins_with("LOADING"), "LOADING label stays visible on the boot cover")
				check(bar.visible and bar.global_position.x < 60 and bar.global_position.y > 640, "Progress stays bottom-left")
				check(bar.size.y >= 8.0, "Progress bar is tall enough to see")
				var boot_image := await capture("boot_2d")
				check(image_has_loading_ui(boot_image), "First boot capture contains lettering or bar")
				two_d_checked = true
			var character: Node = loader.get("_character")
			if character != null:
				var animation: AnimationPlayer = character.get("_animation_player")
				if animation != null and poses.size() < 300:
					poses.append(animation.current_animation_position)
			if captures < 2 and Time.get_ticks_msec() - started > 400 + captures * 650:
				if character != null:
					check(character.get("emote_id") == EmoteData.EMOTE_FLAIR, "Startup must play Flair")
				if bar != null:
					check(bar.visible and bar.global_position.x < 60 and bar.global_position.y > 640, "Progress stays bottom-left")
				var flair_image := await capture("flair_%d" % captures)
				check(image_has_loading_ui(flair_image), "Flair capture contains lettering or bar")
				captures += 1
		if not GameManager.startup_report.is_empty() and not GameManager.startup_loading:
			break
	check(two_d_checked, "Boot 2D cover was observed")
	check(GameManager.startup_report.get("ready", false), "Boot must finish")
	check(get_tree().current_scene.scene_file_path == "res://ui/main_menu.tscn", "Boot reaches main menu")
	check(before == [gs.num_players, gs.mode, gs.p1_alive, gs.p2_alive, gs.quiz_list.size()], "Warmup must not mutate live round")
	check(poses.size() > 5 and poses.max() - poses.min() > 0.1, "Flair must advance across rendered frames")
	check(GameManager.get_node_or_null("StartupLoading") == null, "Boot overlay freed")
	check(get_tree().root.find_children("StartupRehearsalViewport", "", true, false).is_empty(), "Rehearsal viewport freed")
	await capture("menu_ready")
	var boot_report := GameManager.startup_report.duplicate(true)
	var menu := get_tree().current_scene
	gs.num_players = 2
	gs.mode = Constants.MODE_TEN
	gs.llm_mode = "OFFLINE"
	QuizManager.provider.llm_mode = "OFFLINE"
	menu._menu_wall_preview.sync_menu_player_count(2)
	menu._on_start_pressed()
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 90000:
		await get_tree().process_frame
		if gs.game_state == Constants.STATE_WAITING_START and not SceneTransition.is_transitioning():
			var active_world := get_tree().current_scene
			if active_world.has_method("is_start_presentation_locked") and not active_world.is_start_presentation_locked():
				var enter := InputEventKey.new()
				enter.keycode = KEY_ENTER
				enter.pressed = true
				active_world._unhandled_input(enter)
		if gs.game_state == Constants.STATE_PLAYING and not SceneTransition.is_transitioning():
			break
	check(gs.game_state == Constants.STATE_PLAYING, "Real Start reaches PLAYING")
	var world := get_tree().current_scene
	check(world.scene_file_path == "res://scenes/game_world.tscn", "Start reaches gameplay scene")
	if world.scene_file_path == "res://scenes/game_world.tscn":
		var prep: Dictionary = world.get("_world_visual_prep_report")
		check(prep.get("death_effects_prewarmed", false), "Selected-character death effects warmed under cover")
		var wipe := world.get_node("DeathWipeLayer/DeathWipe")
		check(wipe.get("_world_set") and not wipe.visible and not wipe.get("_active"), "Death viewport ready but inactive")
		check(gs.p1_alive and gs.p2_alive, "Both players alive after preparation")
		await capture("playing")
		# Let the start barrier debris settle before measuring death in isolation.
		await get_tree().create_timer(0.7).timeout
		var pc := world.get_node("Player") as PlayerController
		var before_draw := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
		var death_start := Time.get_ticks_usec()
		# Actual death handler: keep P2 alive so the small viewport is displayed.
		gs.p1_alive = false
		pc.begin_ocean_shark_explosion(1)
		wipe._start_wipe(1)
		await RenderingServer.frame_post_draw
		var death_ms := (Time.get_ticks_usec() - death_start) / 1000.0
		check(wipe.visible and wipe.get("_active"), "First death opens prepared viewport")
		check(wipe.wipe_camera.current, "First death camera is current")
		check(not pc._p1_explosion_bodies.is_empty(), "First death creates real debris")
		boot_report["first_death_frame_ms"] = death_ms
		boot_report["first_death_draw_compilations"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW) - before_draw
		await get_tree().create_timer(0.5).timeout
		await capture("first_death")
	# Return/retry must use the existing transition, without another boot pass.
	var retained_count := GameManager.startup_resources.size()
	await SceneTransition.fade_to_color_and_wait(Color.BLACK, true)
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().scene_changed
	await get_tree().create_timer(1.0).timeout
	check(not GameManager.startup_loading and GameManager.get_node_or_null("StartupLoading") == null, "Returning to menu does not repeat boot")
	check(GameManager.startup_resources.size() == retained_count, "Loaded resources retained without duplicate loads")
	check(SceneTransition._loading_character.emote_id == EmoteData.EMOTE_HEAD_SPINNING, "Ordinary stage transition retains head spin")
	await SceneTransition.fade_to_color_and_wait(Color.BLACK, true)
	gs.num_players = 1
	gs.start_game()
	gs.skip_start_helicopter_arrival = true
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
	await get_tree().scene_changed
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 60000:
		await get_tree().process_frame
		if get_tree().current_scene.get("_world_visual_prepared") and not SceneTransition.is_transitioning():
			break
	world = get_tree().current_scene
	var solo_prep: Dictionary = world.get("_world_visual_prep_report")
	check(solo_prep.get("players", 0) == 1 and solo_prep.get("death_effects_prewarmed", false), "Solo retry prepares only the active player")
	check(gs.p1_alive and not world.get_node("DeathWipeLayer/DeathWipe").visible, "Solo preparation preserves live player and hidden wipe")
	await capture("solo_ready")
	var result := {"checks": _checks, "failures": _failures, "boot": boot_report}
	FileAccess.open(_output + "acceptance.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("STARTUP_ACCEPTANCE " + JSON.stringify(result))
	get_tree().quit(0 if _failures.is_empty() else 1)
