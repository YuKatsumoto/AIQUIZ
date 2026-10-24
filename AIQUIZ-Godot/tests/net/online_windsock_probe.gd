extends Node

## 海上ヘリポートの吹き流し（OnlineHeliportWindsock）の確かめ：待機（そよ風）→ 乗り込み（ローターの空回し）→ 離陸 → 上昇。
## 0.1 秒ごとに、口の風・ふくらみ・尾の垂れ・向きを出し、横からの画とゲームのカメラの画を撮る。
##   Godot --path . --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_windsock_probe.gd [shots=DIR]
## 合格：待機で尾がそよ風に垂れて動き、離陸の吹き下ろしでほぼ水平に張り（垂れ 15° 未満）、上がりきると戻る。

const DEAD_RELAY := "ws://127.0.0.1:9"

var menu: OnlineMenu
var director: OnlineStagingDirector
var shots_dir := ""
var failures: Array[String] = []
var _sim := 0.0
var _next_log := 0.0
var _side: Camera3D = null
var _top: Camera3D = null
var _idle_droops: Array[float] = []
var _takeoff_min_droop := 90.0
var _takeoff_max_wind := 0.0
var _takeoff_side_min := 0.0
var _takeoff_side_max := 0.0


func _ready() -> void:
	call_deferred("run")


func _process(delta: float) -> void:
	_sim += delta
	if menu == null or not is_instance_valid(menu) or menu.stage == null or menu.stage.windsock == null:
		return
	var sock := menu.stage.windsock
	var droop := _droop(sock)
	var state := director.state_name()
	if state == "IDLE":
		_idle_droops.append(droop)
	if state in ["TAKEOFF"] or (state == "CLIMB" and director.state_time < 0.4):
		_takeoff_min_droop = minf(_takeoff_min_droop, droop)
		_takeoff_max_wind = maxf(_takeoff_max_wind, sock.mouth_wind.length())
		# 尾の左右の振れ（口の向きからの水平の角度）
		var axis := sock.mouth_axis()
		var tail := sock.tail_position() - sock.pivot_position()
		var side := rad_to_deg(atan2(axis.cross(Vector3(tail.x, 0.0, tail.z)).y, axis.dot(Vector3(tail.x, 0.0, tail.z))))
		_takeoff_side_min = minf(_takeoff_side_min, side)
		_takeoff_side_max = maxf(_takeoff_side_max, side)
	if _sim >= _next_log:
		_next_log = _sim + 0.1
		var heli := menu.stage.my_heli
		print("SOCK %-8s t=%5.2f hub_h=%5.2f power=%.2f wind=%5.2f infl=%.2f droop=%5.1f" % [state, director.state_time,
			heli.rotor_hub_global().y - menu.stage.pad_ground.origin.y, sock.rotor_power, sock.mouth_wind.length(), sock.inflation, droop])


## 支点から尾の先への、水平からの下がり（度）
func _droop(sock: OnlineHeliportWindsock) -> float:
	var d := sock.tail_position() - sock.pivot_position()
	return rad_to_deg(atan2(-d.y, Vector2(d.x, d.z).length()))


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shots="):
			shots_dir = arg.trim_prefix("shots=")
	NetworkManager.relay_url = DEAD_RELAY
	get_tree().change_scene_to_file(OnlineMenu.SCENE_PATH)
	await _frames(10)
	menu = get_tree().current_scene as OnlineMenu
	if menu == null or menu.stage == null or menu.stage.windsock == null:
		print("SOCK_PROBE no windsock")
		get_tree().quit(1)
		return
	await _wait(func() -> bool: return not SceneTransition.is_transitioning(), 6000)
	director = menu.director
	director.swap_ready.disconnect(menu._on_swap_ready)
	director.hold_started.disconnect(menu._on_hold_started)
	_side = Camera3D.new()
	_side.fov = 40.0
	menu.stage.add_child(_side)
	var pivot := menu.stage.windsock.pivot_position()
	var out := Vector3(pivot.x, 0.0, pivot.z).normalized()
	var across := out.cross(Vector3.UP)
	_side.global_position = pivot + out * 1.4 + across * 6.5 + Vector3.DOWN * 0.6
	_side.look_at(pivot + out * 1.4 + Vector3.DOWN * 0.5)
	# 真上から（左右のはためきを見る）
	_top = Camera3D.new()
	_top.fov = 40.0
	menu.stage.add_child(_top)
	_top.global_position = pivot + out * 1.4 + Vector3.UP * 6.5
	_top.look_at(pivot + out * 1.4, across)
	await _seconds(2.0)
	await _both("w0_idle_a")
	await _seconds(1.3)
	await _both("w0_idle_b")
	menu.set("_search_kind", &"random")
	menu.call("_begin_departure")
	await _wait(func() -> bool: return director.state_name() == "COCKPIT", 20000)
	await _seconds(1.0)
	await _both("w1_cockpit_spool")
	await _wait(func() -> bool: return director.state_name() == "TAKEOFF", 20000)
	for at: float in [0.4, 0.8, 1.2, 1.6]:
		await _wait(func() -> bool: return director.state_name() != "TAKEOFF" or director.state_time >= at, 10000)
		await _both("w2_takeoff_%02d" % int(at * 10.0))
	await _wait(func() -> bool: return director.state_name() == "CLIMB", 10000)
	await _seconds(0.6)
	await _both("w3_climb")
	# 上がりきったあとは吹き下ろしが抜ける（離陸の画のまま続きを見るため、ヘリポートを出したまま待つ）
	await _wait(func() -> bool: return director.state_name() != "CLIMB", 20000)
	var idle_spread := 0.0
	if not _idle_droops.is_empty():
		idle_spread = _idle_droops.max() - _idle_droops.min()
	var idle_mean := 0.0
	for d: float in _idle_droops:
		idle_mean += d / float(_idle_droops.size())
	if idle_mean < 10.0:
		failures.append("idle: the sock should droop in the breeze (mean %.1f°)" % idle_mean)
	if idle_spread < 4.0:
		failures.append("idle: the sock should move in the breeze (spread %.1f°)" % idle_spread)
	if _takeoff_min_droop > 15.0:
		failures.append("takeoff: the downwash should straighten the sock (min droop %.1f°)" % _takeoff_min_droop)
	print("SOCK_PROBE " + JSON.stringify({"idle_mean": snappedf(idle_mean, 0.1), "idle_spread": snappedf(idle_spread, 0.1),
		"takeoff_min_droop": snappedf(_takeoff_min_droop, 0.1), "takeoff_max_wind": snappedf(_takeoff_max_wind, 0.1),
		"takeoff_side_deg": [snappedf(_takeoff_side_min, 0.1), snappedf(_takeoff_side_max, 0.1)],
		"failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func _both(label: String) -> void:
	_side.current = true
	await _shot(label + "_side")
	_top.current = true
	await _shot(label + "_top")
	menu.stage.camera.current = true
	await _shot(label + "_game")


func _shot(label: String) -> void:
	if shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, label])


func _seconds(duration: float) -> void:
	var end := _sim + duration
	while _sim < end - 0.0001:
		await get_tree().process_frame


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _wait(condition: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false
