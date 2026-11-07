extends Node

## Per-frame recorder of the performance harness (also runs while the tree is paused).
##
## Godot's Performance.TIME_PROCESS is the max over the last second (updated once a second),
## so the frame is split with timestamps instead:
##   A  first node _process of the frame (EarlyMarker, lowest process_priority)
##   B  last node _process of the frame (this node, highest process_priority)
##   C  RenderingServer.frame_pre_draw,  D  RenderingServer.frame_post_draw
## Record i spans [A_i, A_i+1):
##   dt      = A_i+1 - A_i                       (the frame interval the player sees)
##   process = B_i - A_i                         (every node's _process, e.g. GameWorld)
##   post    = C_i - B_i                         (call_deferred flush, queue_free deletes,
##                                                timers, tweens, idle callbacks)
##   draw    = D_i - C_i                         (main-thread render + present / vsync wait)
##   physics = node _physics_process time of the steps before A_i+1
##   idle    = dt - process - post - draw - physics (frame limiter sleep, input, the
##                                                process_frame signal and coroutines)
## State (walls, wall index, quiz list, scene) is read at A, so a record's events are what
## changed during that frame, including queue_free deletions.

const Util := preload("res://tests/perf_util.gd")

const EV_QUIZ_LOADED := 1
const EV_STATE_SIGNAL := 2
const EV_CORRECT := 4
const EV_QUESTION_DONE := 8
const EV_WALL_INDEX := 16
const EV_WALL_SPAWN := 32
const EV_WALL_FREE := 64
const EV_QUIZ_LIST := 128
const EV_PIPELINE := 256
const EV_NODE_BURST := 512
const EV_STATE_CHANGE := 1024
const EV_HEALTH := 2048
const EV_SCENE := 4096
const EV_WRONG := 8192
const EV_NODE_FREE_BURST := 16384
const EV_PROVIDER_FETCH := 32768
const EV_PROVIDER_BUFFER := 65536
const EV_HTTP_REQUEST := 131072
const EV_NAMES := {
	EV_QUIZ_LOADED: "quiz_loaded_signal",
	EV_STATE_SIGNAL: "state_changed_signal",
	EV_CORRECT: "correct_answer_signal",
	EV_QUESTION_DONE: "question_completed_signal",
	EV_WALL_INDEX: "current_wall_index_changed",
	EV_WALL_SPAWN: "wall_container_child_added",
	EV_WALL_FREE: "wall_container_child_removed",
	EV_QUIZ_LIST: "quiz_list_size_changed",
	EV_PIPELINE: "pipeline_compilation",
	EV_NODE_BURST: "nodes_added_ge_20",
	EV_STATE_CHANGE: "game_state_value_changed",
	EV_HEALTH: "health_changed_signal",
	EV_SCENE: "current_scene_changed",
	EV_WRONG: "wrong_answer_signal",
	EV_NODE_FREE_BURST: "nodes_removed_ge_20",
	EV_PROVIDER_FETCH: "provider_refill_ran",
	EV_PROVIDER_BUFFER: "provider_buffer_size_changed",
	EV_HTTP_REQUEST: "http_request_node_added",
}
const STATE_CODES := {
	"MENU": 0, "PRELOADING": 1, "WAITING_START": 2, "FLYOVER": 3, "COUNTDOWN": 4,
	"PLAYING": 5, "CORRECT": 6, "GAME_OVER": 7, "CLEAR": 8, "GOAL_RACE": 9,
	"RESULT_CEREMONY": 10, "SUDDEN_DEATH": 11,
}
const PHASE_NAMES := ["idle", "boot", "menu", "to_match", "play", "leave"]
const NODE_BURST := 20
const SLOW_INTERVAL_SEC := 0.5


class EarlyMarker extends Node:
	var sampler: Node

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -(1 << 30)
		process_physics_priority = -(1 << 30)

	func _process(_delta: float) -> void:
		sampler.call("_on_frame_start")

	func _physics_process(_delta: float) -> void:
		sampler.call("_on_physics_start")


var recording := false
var phase := 0
var match_index := -1
## Time.get_ticks_usec() of this match's first PLAYING frame, -1 before.
var play_origin_us := -1

# One entry per finished frame record.
var t_s := PackedFloat32Array()
var dt_ms := PackedFloat32Array()
var process_ms := PackedFloat32Array()
var post_ms := PackedFloat32Array()
var draw_ms := PackedFloat32Array()
var physics_ms := PackedFloat32Array()
var idle_ms := PackedFloat32Array()
var render_cpu_ms := PackedFloat32Array()
var render_gpu_ms := PackedFloat32Array()
var play_t := PackedFloat32Array()
var draw_calls := PackedInt32Array()
var objects_in_frame := PackedInt32Array()
var node_count := PackedInt32Array()
var nodes_added := PackedInt32Array()
var nodes_removed := PackedInt32Array()
var walls := PackedInt32Array()
var wall_index := PackedInt32Array()
var state_code := PackedInt32Array()
var quiz_list_size := PackedInt32Array()
var events := PackedInt32Array()
var pipelines := PackedInt32Array()
var phase_code := PackedInt32Array()
var match_code := PackedInt32Array()

var slow: Array[Dictionary] = []
var state_log: Array = []

var _origin_us := 0
var _slow_next_us := 0
var _gs: QuizGameState
var _vp_rid: RID
var _early: EarlyMarker

# Timestamps of the frame being measured (A..D) and the counters since its A.
var _a := 0
var _b := 0
var _c := 0
var _d := 0
var _phys_start := 0
var _phys_acc := 0
var _added := 0
var _removed := 0
var _http := 0
var _sig := 0
var _prov: Node
var _st_refetch := -1
var _st_buffer := -1
# State read at the frame's A.
var _st_state := ""
var _st_walls := -1
var _st_wall_index := -1
var _st_qlist := -1
var _st_scene: Node = null
var _st_pipe := 0
var _st_phase := 0
var _st_match := -1
var _st_play_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1 << 30
	process_physics_priority = 1 << 30
	_early = EarlyMarker.new()
	_early.name = "PerfEarlyMarker"
	_early.sampler = self
	add_child(_early)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_gs = QuizManager.game_state
	_prov = QuizManager.provider
	if _gs != null:
		_gs.quiz_loaded.connect(_on_quiz_loaded)
		_gs.state_changed.connect(_on_state_signal)
		_gs.correct_answer.connect(_on_correct)
		_gs.question_completed.connect(_on_question_completed)
		_gs.health_changed.connect(_on_health_changed)
		_gs.wrong_answer.connect(_on_wrong)
	_origin_us = Time.get_ticks_usec()


func _on_node_added(n: Node) -> void:
	_added += 1
	if n is HTTPRequest:
		_http += 1


func _on_node_removed(_n: Node) -> void:
	_removed += 1


func _on_quiz_loaded(_q: Variant) -> void:
	_sig |= EV_QUIZ_LOADED


func _on_state_signal(_s: String) -> void:
	_sig |= EV_STATE_SIGNAL


func _on_correct() -> void:
	_sig |= EV_CORRECT


func _on_question_completed(_i: int, _c2: bool) -> void:
	_sig |= EV_QUESTION_DONE


func _on_health_changed(_p: int, _a2: int, _b2: int) -> void:
	_sig |= EV_HEALTH


func _on_wrong(_m: String) -> void:
	_sig |= EV_WRONG


func _on_pre_draw() -> void:
	_c = Time.get_ticks_usec()


func _on_post_draw() -> void:
	_d = Time.get_ticks_usec()


func _on_physics_start() -> void:
	_phys_start = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	if _phys_start > 0:
		_phys_acc += Time.get_ticks_usec() - _phys_start
		_phys_start = 0


func _process(_delta: float) -> void:
	_b = Time.get_ticks_usec()


func world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.name == "GameWorld" else null


func wall_child_count() -> int:
	var w := world()
	if w == null:
		return -1
	var wc: Variant = w.get("wall_container")
	return (wc as Node).get_child_count() if wc is Node and is_instance_valid(wc) else -1


func _pipeline_total() -> int:
	return (
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS)
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE)
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW)
	)


## EarlyMarker, at A of a new frame: close the previous record, then start a new one.
func _on_frame_start() -> void:
	var now := Time.get_ticks_usec()
	var state := String(_gs.game_state) if _gs != null else ""
	var walls_now := wall_child_count()
	var wall_idx := _gs.current_wall_index if _gs != null else -1
	var qlist := _gs.quiz_list.size() if _gs != null else -1
	var scene := get_tree().current_scene
	var pipe := _pipeline_total()
	var refetch := int(_prov.get("_last_refetch_ms")) if _prov != null and _prov.get("_last_refetch_ms") != null else -1
	var buffer_size := (_prov.get("buffer") as Array).size() if _prov != null and _prov.get("buffer") is Array else -1
	if _a > 0 and recording:
		_close_record(now, state, walls_now, wall_idx, qlist, scene, pipe, refetch, buffer_size)
	if recording and _st_state != "" and state != _st_state:
		state_log.append([Util.r3(float(now - _origin_us) / 1e6), _st_state, state, match_index])
	if recording and now >= _slow_next_us:
		_slow_next_us = now + int(SLOW_INTERVAL_SEC * 1e6)
		slow.append(slow_sample(now, state, walls_now, wall_idx, qlist))
	# Start the new record.
	_a = now
	_b = 0
	_c = 0
	_d = 0
	_phys_acc = 0
	_added = 0
	_removed = 0
	_http = 0
	_sig = 0
	_st_refetch = refetch
	_st_buffer = buffer_size
	_st_state = state
	_st_walls = walls_now
	_st_wall_index = wall_idx
	_st_qlist = qlist
	_st_scene = scene
	_st_pipe = pipe
	_st_phase = phase
	_st_match = match_index
	_st_play_t = float(now - play_origin_us) / 1e6 if play_origin_us > 0 else -1.0


func _close_record(now: int, state: String, walls_now: int, wall_idx: int, qlist: int, scene: Node, pipe: int, refetch: int, buffer_size: int) -> void:
	var ev := _sig
	if refetch != _st_refetch:
		ev |= EV_PROVIDER_FETCH
	if buffer_size != _st_buffer:
		ev |= EV_PROVIDER_BUFFER
	if _http > 0:
		ev |= EV_HTTP_REQUEST
	if wall_idx != _st_wall_index:
		ev |= EV_WALL_INDEX
	if _st_walls >= 0 and walls_now >= 0:
		if walls_now > _st_walls:
			ev |= EV_WALL_SPAWN
		elif walls_now < _st_walls:
			ev |= EV_WALL_FREE
	if qlist != _st_qlist:
		ev |= EV_QUIZ_LIST
	var pipe_delta := maxi(0, pipe - _st_pipe)
	if pipe_delta > 0:
		ev |= EV_PIPELINE
	if _added >= NODE_BURST:
		ev |= EV_NODE_BURST
	if _removed >= NODE_BURST:
		ev |= EV_NODE_FREE_BURST
	if state != _st_state:
		ev |= EV_STATE_CHANGE
	if scene != _st_scene:
		ev |= EV_SCENE
	var dt := float(now - _a) / 1000.0
	var b := _b if _b >= _a else _a
	var c := _c if _c >= b else b
	var d := _d if _d >= c else c
	var proc := float(b - _a) / 1000.0
	var post := float(c - b) / 1000.0
	var draw := float(d - c) / 1000.0
	var phys := float(_phys_acc) / 1000.0
	t_s.append(float(_a - _origin_us) / 1e6)
	dt_ms.append(dt)
	process_ms.append(proc)
	post_ms.append(post)
	draw_ms.append(draw)
	physics_ms.append(phys)
	idle_ms.append(maxf(0.0, dt - proc - post - draw - phys))
	render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu())
	render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
	play_t.append(_st_play_t)
	draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	objects_in_frame.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	node_count.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	nodes_added.append(_added)
	nodes_removed.append(_removed)
	walls.append(_st_walls)
	wall_index.append(_st_wall_index)
	state_code.append(int(STATE_CODES.get(_st_state, -1)))
	quiz_list_size.append(_st_qlist)
	events.append(ev)
	pipelines.append(pipe_delta)
	phase_code.append(_st_phase)
	match_code.append(_st_match)


func slow_sample(now: int, state: String, walls_now: int, wall_idx: int, qlist: int) -> Dictionary:
	var w := world()
	var active := -1
	if w != null:
		var aw: Variant = w.get("_active_walls")
		if aw is Array:
			active = (aw as Array).size()
	var audio := get_tree().root.get_node_or_null("AudioManager")
	return {
		"t": Util.r3(float(now - _origin_us) / 1e6),
		"play_t": Util.r3(float(now - play_origin_us) / 1e6) if play_origin_us > 0 else -1.0,
		"phase": PHASE_NAMES[phase] if phase < PHASE_NAMES.size() else str(phase),
		"match": match_index,
		"state": state,
		"wall_index": wall_idx,
		"wall_container_children": walls_now,
		"active_walls": active,
		"quiz_list": qlist,
		"quiz_history": _gs.quiz_history.size() if _gs != null else -1,
		"fps": Engine.get_frames_per_second(),
		"time_process_max_1s_ms": Util.r2(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
		"time_physics_max_1s_ms": Util.r2(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"root_children": get_tree().root.get_child_count(),
		"audio_manager_children": audio.get_child_count() if audio != null else -1,
		"perf": Util.perf_numbers(),
	}


func frame_count() -> int:
	return dt_ms.size()


func export_frames() -> Dictionary:
	return {
		"columns_doc": {
			"t": "seconds since the sampler started (frame start A)",
			"dt": "frame interval in ms (A to next A, Time.get_ticks_usec)",
			"process": "all nodes' _process in ms (A to B)",
			"post": "deferred calls, queue_free deletes, timers, tweens in ms (B to frame_pre_draw)",
			"draw": "RenderingServer draw incl. present/vsync wait in ms (frame_pre_draw to frame_post_draw)",
			"physics": "node _physics_process time in ms of the steps before the next frame",
			"idle": "rest of dt: frame limiter sleep, input, process_frame signal, coroutines",
			"rcpu": "measured render CPU time (viewport + frame setup) in ms, lags 1-2 frames",
			"rgpu": "measured render GPU time in ms, lags 1-2 frames",
			"play_t": "seconds since the match's first PLAYING frame (-1 before)",
			"events": "bitmask, see events_legend (provider_refill_ran = BufferedQuizProvider._last_refetch_ms changed, i.e. its 0.25 s poll ran a fetch)",
		},
		"events_legend": EV_NAMES,
		"state_codes": STATE_CODES,
		"phase_names": PHASE_NAMES,
		"t": Util.packed_round(t_s, 0.001),
		"dt": Util.packed_round(dt_ms),
		"process": Util.packed_round(process_ms),
		"post": Util.packed_round(post_ms),
		"draw": Util.packed_round(draw_ms),
		"physics": Util.packed_round(physics_ms),
		"idle": Util.packed_round(idle_ms),
		"rcpu": Util.packed_round(render_cpu_ms),
		"rgpu": Util.packed_round(render_gpu_ms),
		"play_t": Util.packed_round(play_t),
		"draw_calls": Array(draw_calls),
		"objects_in_frame": Array(objects_in_frame),
		"node_count": Array(node_count),
		"nodes_added": Array(nodes_added),
		"nodes_removed": Array(nodes_removed),
		"walls": Array(walls),
		"wall_index": Array(wall_index),
		"state": Array(state_code),
		"quiz_list": Array(quiz_list_size),
		"events": Array(events),
		"pipelines": Array(pipelines),
		"phase": Array(phase_code),
		"match": Array(match_code),
	}
