extends Node

## オンライン対戦の SWAP で、ゲーム画面を組み立てるのにかかる時間の内訳（読み込み・instantiate・_ready・その後の長いフレーム）。
##   Godot --path . --resolution 1920x1080 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/perf/game_world_build_probe.gd

const GAME_WORLD_PATH := "res://scenes/game_world.tscn"
const LONG_FRAME_MS := 25.0

var _last_us := 0
var _long_frames: Array = []
var _t0_us := 0


func _ready() -> void:
	call_deferred("run")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0 and _t0_us > 0:
		var ms := float(now - _last_us) / 1000.0
		if ms > LONG_FRAME_MS:
			_long_frames.append({"at_ms": snappedf(float(now - _t0_us) / 1000.0, 0.1), "ms": snappedf(ms, 0.1)})
	_last_us = now


func run() -> void:
	var gs := QuizManager.game_state
	QuizManager.provider.set_llm_mode("OFFLINE")
	gs.num_players = 2
	gs.select_mode_and_continue(Constants.MODE_TEN)
	gs.subject = "算数"
	gs.grade = 3
	await get_tree().process_frame
	var t := Time.get_ticks_usec()
	var packed := load(GAME_WORLD_PATH) as PackedScene
	var load_ms := float(Time.get_ticks_usec() - t) / 1000.0
	gs.start_game(true)
	t = Time.get_ticks_usec()
	var world := packed.instantiate()
	var instantiate_ms := float(Time.get_ticks_usec() - t) / 1000.0
	SceneTransition.hold_versus_split(ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8)), OnlineStagingTimeline.SEAM_POINTS, 3.2)
	# 各ノードの ready（子が先、親があと）の時刻。前の ready からの差を、そのノードの _ready の重さとみなす
	var ready_events: Array = []
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		node.ready.connect(func() -> void: ready_events.append([Time.get_ticks_usec(), str(world.get_path_to(node)) if node.is_inside_tree() else node.name]), CONNECT_ONE_SHOT)
		for child in node.get_children(true):
			stack.append(child)
	_t0_us = Time.get_ticks_usec()
	t = _t0_us
	get_tree().root.add_child(world)
	var heavy: Array = []
	var prev := _t0_us
	for e: Array in ready_events:
		var ms := float(int(e[0]) - prev) / 1000.0
		if ms > 20.0:
			heavy.append([e[1], snappedf(ms, 0.1)])
		prev = int(e[0])
	heavy.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	print("GAME_WORLD_READY_HEAVY " + JSON.stringify(heavy.slice(0, 25)))
	get_tree().current_scene = world
	var ready_ms := float(Time.get_ticks_usec() - t) / 1000.0
	var end := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
	var report := {"load_ms": snappedf(load_ms, 0.1), "instantiate_ms": snappedf(instantiate_ms, 0.1),
		"add_child_ready_ms": snappedf(ready_ms, 0.1), "long_frames": _long_frames}
	print("GAME_WORLD_BUILD " + JSON.stringify(report))
	get_tree().quit(0)
