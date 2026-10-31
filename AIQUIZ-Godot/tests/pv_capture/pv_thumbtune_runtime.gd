extends "res://tests/pv_capture/pv_thumb_runtime.gd"

## サムネイルの画角を自分で決める道具。pv_thumb_runtime.gd の撮影をそのまま走らせ、at= のフレームでゲームの世界ごと止めて、
## カメラをマウスとキーで動かせるようにする。決めた画角は cam=…・dof=… の引数として出す（撮影の台本にそのまま渡せる）。
## 起動は ThumbnailCameraTuner.cmd（引数：ショット・フレーム）か:
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumbtune shot=t5 quality=ultra sub=8 at=63
## 撮影の本番と同じ quality・sub で起動すると、止めた瞬間は本番の撮影のそのコマと同じになる（物理の結果は quality と sub で変わる）。
## 引数（撮影の台本の引数 cam=・dof=・lanes= なども使える）:
##   at=<f>     止める PV フレーム（既定は finish.py のそのショットのコマ）
## 操作（止めているあいだ）:
##   右ドラッグ 見回す（目の位置はそのまま）  左ドラッグ 注視点のまわりを回る  中ドラッグ 平行移動
##   W/A/S/D 前後左右  Q/E 下/上  Shift 速く  Alt ゆっくり
##   ホイール 画角（ズーム）  Ctrl+ホイール 注視点へ寄る/離れる（遠近感が変わる）
##   [ / ] 背景のぼけの量  R 起動したときの画角に戻す  G ガイド（ロゴと三分割）  H 説明を隠す
##   T 小さく表示したときの見え方（ロゴ入り）  N / B 1 フレーム進める / 戻す（Shift で 5。戻すときは物理を逆に進められないので、
##   いまの画角を引き継いで最初から走らせ直す。ultra で 1 分ほど）
##   Enter 引数をクリップボードへ  P 絵を保存（引数も tune.txt に）  Esc 終わる
## 出力：artifacts/pv_capture/thumb_<shot>_tune/ の tune_NNN_fNNNN.png と tune.txt。

const LOGO_PATH := "res://docs/pv/frames/logo_testopia.png"
const FONT := preload("res://resources/fonts/NotoSansJP-Bold.otf")
## finish.py の SHOTS と同じ：仕上げで使うコマと、ロゴの左端・幅（px）
const FINISH := {
	"t2": {"frame": 65, "logo_x": 70, "logo_w": 820},
	"t3": {"frame": 48, "logo_x": 70, "logo_w": 820},
	"t5": {"frame": 63, "logo_x": 56, "logo_w": 740},
	"t7": {"frame": 71, "logo_x": 60, "logo_w": 700},
	"t8": {"frame": 76, "logo_x": 56, "logo_w": 740},
}
const LOOK_DEG_PER_PX := 0.15
const MOVE_SPEED := 2.0                 # m/s（Shift で 4 倍、Alt で 1/4）
const PREVIEW_W := 384
const RELAUNCH_PATH := "res://artifacts/pv_capture/thumbtune_relaunch.txt"   # ThumbnailCameraTuner.cmd が読む

var _tune_at := 0
var _tune_pending := false
var _tuning := false
var _start_cam: Array = []
var _start_dof: Array = []
var _world_mode := Node.PROCESS_MODE_INHERIT
var _particle_speeds := {}
var _last_us := 0
var _saved_count := 0
var _status := ""

var _hud: CanvasLayer
var _guides: Control
var _logo: TextureRect
var _info: Label
var _help: Label
var _preview: TextureRect
var _show_guides := true
var _show_help := true
var _selftest := false
var _selftest_started := false
var _selftest_done := false             # 戻したあとの起動（selftest=done）：止まったら値を出して終わる
var _watch := false                     # watch=1：止めているあいだ stage.json を見張り、変わったら当て直して絵を保存する
var _watch_mtime := 0
var _watch_next_us := 0
var _watch_count := 0
var _watch_busy := false


func _init() -> void:
	take_name = "thumbtune"


func run() -> void:
	# ランチャー（ThumbnailCameraTuner.cmd）からは「t5 63 low」のような名前なしの引数も来る（ショット・フレーム・画質）
	shot = "t5"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shot = arg.trim_prefix("shot=")
		elif _is_bare_shot(arg):
			shot = arg
	tag = "thumb_%s_tune" % shot.validate_filename()
	await super.run()


func _is_bare_shot(arg: String) -> bool:
	return arg.length() >= 2 and arg[0] == "t" and arg.substr(1).is_valid_int()


func _parse_arg(arg: String) -> void:
	if arg.begins_with("at="):
		_tune_at = int(arg.trim_prefix("at="))
	elif arg.is_valid_int():
		_tune_at = int(arg)
	elif arg in ["low", "balanced", "high", "ultra"]:
		quality = GraphicsQualityRules.normalize(arg)
	elif _is_bare_shot(arg):
		pass
	elif arg == "selftest=1":
		_selftest = true
	elif arg == "selftest=done":
		_selftest_done = true
	elif arg == "watch=1":
		_watch = true
	else:
		super(arg)


func _setup() -> void:
	# 止めてからはこちらが終わりを決める。撮った絵は保存しない（P で保存する）
	frame_count = 1 << 30
	if only_frames.is_empty():
		only_frames[-1] = true
	if _tune_at <= 0:
		_tune_at = int((FINISH.get(shot, {}) as Dictionary).get("frame", 60))
	await super()
	_start_cam = (cfg["cam"] as Array).duplicate()
	_start_dof = (cfg["dof"] as Array).duplicate()
	_build_hud()
	_status = "フレーム %d まで進めています…" % _tune_at
	_refresh_hud()


func _update(n: int, t: float, dt: float) -> void:
	super(n, t, dt)
	if not _tune_pending and not _tuning and n >= _tune_at and (_step % sub) == 0:
		# この刻みの絵が描かれたあと、次のフレームの頭で世界ごと止める（export と同じ止め方）
		_tune_pending = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
	elif not _tuning:
		_status = "フレーム %d まで進めています…（いま %d）" % [_tune_at, n]
		_refresh_hud()


func _process(dt: float) -> void:
	if _tune_pending:
		_tune_pending = false
		_freeze()
		return
	if _tuning:
		_tune_tick()
		return
	super(dt)


# ------------------------------------------------------------------ 止める・進める

func _freeze() -> void:
	for key: Variant in _held.keys():
		send_key(key, false)
	_world_mode = world.process_mode
	_particle_speeds.clear()
	for node: Node in world.find_children("*", "GPUParticles3D", true, false) + world.find_children("*", "CPUParticles3D", true, false):
		_particle_speeds[node] = node.get("speed_scale")
	_freeze_world()
	Engine.max_fps = 60                     # 止めているあいだは GPU を回しすぎない
	_tuning = true
	_last_us = Time.get_ticks_usec()
	_status = "フレーム %d で止めました" % frame_of(_step)
	_refresh_hud()
	print("[thumbtune] frozen at frame %d  %s" % [frame_of(_step), _args_text()])
	if _selftest and not _selftest_started:
		_selftest_started = true
		_run_selftest.call_deferred()
	elif _selftest_done:
		_st_log("after rewind")
		_quit.call_deferred()


func _advance(frames: int) -> void:
	_tuning = false
	_tune_at = frame_of(_step) + frames
	world.process_mode = _world_mode
	for node: Variant in _particle_speeds:
		if is_instance_valid(node):
			(node as Node).set("speed_scale", _particle_speeds[node])
	Engine.max_fps = 0
	hold_keys(_keys_at(frame_of(_step + 1)))
	get_tree().paused = false


## フレームを戻す。物理は逆に進められないので、いまの画角（cam・dof）を引き継いで最初から走らせ直し、target で止める。
## ランチャーから起動したとき（THUMBTUNE_LAUNCHER）は、次の引数を RELAUNCH_PATH に書いて終わり、ランチャーが起動し直す
## （コンソールの窓をそのまま使う）。直接起動したときは、同じ実行ファイルを同じ引数で起こしてから終わる
func _rewind(frames: int) -> void:
	var target := maxi(1, frame_of(_step) - frames)
	var args: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("at=") or arg.is_valid_int() or arg.begins_with("cam=") or arg.begins_with("dof=") or arg.begins_with("selftest="):
			continue
		args.append(arg)
	args.append_array(["at=%d" % target, "cam=" + _fmt(cfg["cam"], 3), "dof=" + _fmt(cfg["dof"], 3)])
	if _selftest:
		args.append("selftest=done")
	_log_args("rewind -> %d" % target)
	if OS.get_environment("THUMBTUNE_LAUNCHER") != "":
		var file := FileAccess.open(RELAUNCH_PATH, FileAccess.WRITE)
		file.store_string(" ".join(args))
		file.close()
	else:
		var engine_args := Array(OS.get_cmdline_args())
		var i := engine_args.find("--path")
		if i >= 0 and i + 1 < engine_args.size():
			engine_args[i + 1] = ProjectSettings.globalize_path("res://")
		OS.create_process(OS.get_executable_path(), PackedStringArray(engine_args + ["--"] + args))
	_status = "フレーム %d へ戻すため、起動し直します…" % target
	_refresh_hud()
	await _st_wait(2)
	_quit()


# ------------------------------------------------------------------ カメラ（cfg["cam"] を直接いじる。値は anchor からの相対）

func _eye() -> Vector3:
	var c: Array = cfg["cam"]
	return Vector3(c[0], c[1], c[2])


func _target() -> Vector3:
	var c: Array = cfg["cam"]
	return Vector3(c[3], c[4], c[5])


func _fov() -> float:
	return float((cfg["cam"] as Array)[6])


func _set_cam(eye: Vector3, target: Vector3, fov: float) -> void:
	cfg["cam"] = [eye.x, eye.y, eye.z, target.x, target.y, target.z, clampf(fov, 3.0, 120.0)]
	_apply_camera()
	if cfg.has("clouds"):
		_place_clouds(cfg["clouds"])
	_refresh_hud()


## 向き f を、横 dx・縦 dy（画面の px）だけ回す（右へ動かすと右を向く、下へ動かすと下を向く）
func _turn(f: Vector3, dx: float, dy: float) -> Vector3:
	var yaw := atan2(f.x, f.z) - deg_to_rad(dx * LOOK_DEG_PER_PX)
	var pitch := clampf(asin(clampf(f.y, -1.0, 1.0)) - deg_to_rad(dy * LOOK_DEG_PER_PX), deg_to_rad(-85.0), deg_to_rad(85.0))
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))


func _look(dx: float, dy: float) -> void:
	var e := _eye()
	var d := _target() - e
	_set_cam(e, e + _turn(d.normalized(), dx, dy) * d.length(), _fov())


func _orbit(dx: float, dy: float) -> void:
	var t := _target()
	var d := t - _eye()
	_set_cam(t - _turn(d.normalized(), dx, dy) * d.length(), t, _fov())


func _pan(dx: float, dy: float) -> void:
	var e := _eye()
	var t := _target()
	var f := (t - e).normalized()
	var r := f.cross(Vector3.UP).normalized()
	var u := r.cross(f)
	var s := 2.0 * e.distance_to(t) * tan(deg_to_rad(_fov()) * 0.5) / float(VIEW.y)
	var move := -r * dx * s + u * dy * s
	_set_cam(e + move, t + move, _fov())


func _dolly(scale: float) -> void:
	var t := _target()
	var d := _eye() - t
	_set_cam(t + d.normalized() * maxf(d.length() * scale, 0.3), t, _fov())


## watch=1：out の stage.json（cfg に重ねる値。cam・dof・pose・hero_debris・hide_chunks など）が変わったら、止めたフレームのまま
## 当て直して watch_NNN.png に保存し、watch_done.txt に番号を書く（外から演出を詰めるため）
func _watch_tick() -> void:
	if _watch_busy or Time.get_ticks_usec() < _watch_next_us:
		return
	_watch_next_us = Time.get_ticks_usec() + 300000
	var path := ProjectSettings.globalize_path(out + "stage.json")
	if not FileAccess.file_exists(path):
		return
	var mtime := FileAccess.get_modified_time(path)
	if mtime == _watch_mtime:
		return
	_watch_mtime = mtime
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		_status = "stage.json を読めません"
		_refresh_hud()
		return
	_watch_busy = true
	for key: String in data:
		cfg[key] = data[key]
	_set_cam(_eye(), _target(), _fov())
	if cfg.has("pose"):
		apply_pose(cfg["pose"])
	stage_debris()
	var image := await _grab_clean()
	_watch_count += 1
	var file_name := "watch_%03d.png" % _watch_count
	image.save_png(ProjectSettings.globalize_path(out + file_name))
	var done := FileAccess.open(out + "watch_done.txt", FileAccess.WRITE)
	done.store_string(str(_watch_count))
	done.close()
	_status = "stage.json を当て直しました：%s" % file_name
	_refresh_hud()
	var pelvis := (player.get("p1_parts") as Dictionary).get("pelvis") as Node3D
	var rel := pelvis.global_position - _mid() if pelvis != null else Vector3.ZERO
	print("[thumbtune] watch %s  P1 pelvis (anchor 基準・床から) %s" % [file_name, rel])
	var wall := _wall0_node()
	if wall != null:
		for door: MeshInstance3D in wall.get("doors"):
			if is_instance_valid(door) and door.mesh is BoxMesh:
				print("[thumbtune]   door %s visible=%s center %s size %s" % [door.name, door.visible, door.global_position - _mid(), (door.mesh as BoxMesh).size])
	_watch_busy = false


func _tune_tick() -> void:
	if _watch:
		_watch_tick()
	var now := Time.get_ticks_usec()
	var dt := minf(float(now - _last_us) / 1000000.0, 0.1)
	_last_us = now
	var move := Vector3.ZERO
	var f := (_target() - _eye()).normalized()
	var r := f.cross(Vector3.UP).normalized()
	if Input.is_physical_key_pressed(KEY_W):
		move += f
	if Input.is_physical_key_pressed(KEY_S):
		move -= f
	if Input.is_physical_key_pressed(KEY_D):
		move += r
	if Input.is_physical_key_pressed(KEY_A):
		move -= r
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move == Vector3.ZERO:
		return
	var speed := MOVE_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 4.0
	if Input.is_key_pressed(KEY_ALT):
		speed *= 0.25
	move = move.normalized() * speed * dt
	_set_cam(_eye() + move, _target() + move, _fov())


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		_quit()
		return
	if not _tuning:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_look(motion.relative.x, motion.relative.y)
		elif motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_orbit(motion.relative.x, motion.relative.y)
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(motion.relative.x, motion.relative.y)
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		var step := 0
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = 1
		if step != 0:
			var amount := 1.0 + 0.04 * step * (3.0 if button.shift_pressed else 1.0)
			if button.ctrl_pressed:
				_dolly(amount)
			else:
				_set_cam(_eye(), _target(), _fov() * amount)
		return
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var d: Array = cfg["dof"]
			d[2] = clampf(snappedf(float(d[2]) + (0.05 if key.physical_keycode == KEY_BRACKETRIGHT else -0.05), 0.01), 0.0, 1.0)
			_set_cam(_eye(), _target(), _fov())
		KEY_R:
			cfg["dof"] = _start_dof.duplicate()
			var c := _start_cam
			_set_cam(Vector3(c[0], c[1], c[2]), Vector3(c[3], c[4], c[5]), c[6])
			_status = "起動したときの画角に戻しました"
		KEY_G:
			_show_guides = not _show_guides
		KEY_H:
			_show_help = not _show_help
		KEY_T:
			if _preview.visible:
				_preview.visible = false
			else:
				_update_preview()
		KEY_N:
			_advance(5 if key.shift_pressed else 1)
		KEY_B:
			_rewind(5 if key.shift_pressed else 1)
		KEY_ENTER, KEY_KP_ENTER:
			DisplayServer.clipboard_set(_args_text())
			_log_args("copy")
			_status = "クリップボードへコピーしました：%s" % _args_text()
		KEY_P:
			_save_shot()
	_refresh_hud()


# ------------------------------------------------------------------ 出力

func _fmt(values: Array, digits: int) -> String:
	return ",".join(values.map(func(v: Variant) -> String: return String.num(float(v), digits)))


func _args_text() -> String:
	return "shot=%s cam=%s dof=%s only=%d" % [shot, _fmt(cfg["cam"], 2), _fmt(cfg["dof"], 2), frame_of(_step)]


func _log_args(what: String) -> void:
	var path := ProjectSettings.globalize_path(out + "tune.txt")
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%s\t%s\t%s" % [Time.get_datetime_string_from_system(), what, _args_text()])
	file.close()
	print("[thumbtune] %s  %s" % [what, _args_text()])


## HUD を隠した絵（描かれたあとのもの）を取る
func _grab_clean() -> Image:
	var was := _hud.visible
	_hud.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_hud.visible = was
	return image


func _save_shot() -> void:
	var image := await _grab_clean()
	_saved_count += 1
	var file_name := "tune_%03d_f%04d.png" % [_saved_count, frame_of(_step)]
	image.save_png(ProjectSettings.globalize_path(out + file_name))
	_log_args(file_name)
	_status = "保存しました：%s%s" % [out.trim_prefix("res://"), file_name]
	_set_preview(image)
	_refresh_hud()


func _update_preview() -> void:
	_set_preview(await _grab_clean())


## 小さく表示したときの見え方：ロゴを仕上げと同じ位置に重ねて、PREVIEW_W に縮める
func _set_preview(image: Image) -> void:
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGBA8)
	if _logo.texture != null:
		var g := FINISH.get(shot, FINISH["t5"]) as Dictionary
		var logo := (_logo.texture as ImageTexture).get_image()
		var w := int(g["logo_w"])
		var h := roundi(logo.get_height() * float(w) / logo.get_width())
		logo.resize(w, h, Image.INTERPOLATE_LANCZOS)
		small.blend_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), Vector2i(int(g["logo_x"]), (VIEW.y - h) / 2))
	small.resize(PREVIEW_W, PREVIEW_W * VIEW.y / VIEW.x, Image.INTERPOLATE_LANCZOS)
	_preview.texture = ImageTexture.create_from_image(small)
	_preview.visible = true


# ------------------------------------------------------------------ 画面の上の表示

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 120
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	# プロジェクトの画面の拡大（2D の座標は基準の大きさ）に合わせ、ここでは 1920×1080 の画素で置けるようにする
	_hud.scale = Vector2.ONE * (get_viewport().get_visible_rect().size.x / VIEW.x)
	add_child(_hud)
	_overlay_keep.append(_hud)
	_guides = Control.new()
	_guides.set_anchors_preset(Control.PRESET_FULL_RECT)
	_guides.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guides.draw.connect(_draw_guides)
	_hud.add_child(_guides)
	_logo = TextureRect.new()
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.modulate.a = 0.7
	var image := Image.load_from_file(ProjectSettings.globalize_path(LOGO_PATH))
	if image != null and not image.is_empty():
		var g := FINISH.get(shot, FINISH["t5"]) as Dictionary
		var w := float(g["logo_w"])
		var h := roundf(image.get_height() * w / image.get_width())
		_logo.texture = ImageTexture.create_from_image(image)
		_logo.position = Vector2(float(g["logo_x"]), roundf((VIEW.y - h) * 0.5))
		_logo.size = Vector2(w, h)
	_hud.add_child(_logo)
	_info = _make_label(26, Vector2(24, 18))
	_help = _make_label(20, Vector2(24, VIEW.y - 236))
	_help.text = "\n".join([
		"右ドラッグ：見回す　左ドラッグ：注視点のまわりを回る　中ドラッグ：平行移動",
		"W/A/S/D：前後左右　Q/E：下/上　Shift：速く　Alt：ゆっくり",
		"ホイール：画角（ズーム）　Ctrl+ホイール：注視点へ寄る/離れる（遠近感）　Shift で大きく",
		"[ / ]：背景のぼけ　R：元に戻す　G：ガイド　H：説明を隠す　T：小さく表示したときの見え方",
		"N / B：1 フレーム進める / 戻す（Shift で 5。戻すときは画角を引き継いで起動し直す）　Enter：引数をコピー　P：絵を保存　Esc：終わる",
	])
	_preview = TextureRect.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.position = Vector2(VIEW.x - PREVIEW_W - 24, 24)
	_preview.size = Vector2(PREVIEW_W, PREVIEW_W * VIEW.y / VIEW.x)
	_preview.visible = false
	_hud.add_child(_preview)


func _make_label(size: int, pos: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = pos
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(label)
	return label


func _refresh_hud() -> void:
	if _hud == null:
		return
	var lines := ["画角調整　%s　フレーム %d%s" % [shot, frame_of(_step), "（止めています）" if _tuning else ""],
		"cam=%s　dof=%s" % [_fmt(cfg["cam"], 2), _fmt(cfg["dof"], 2)]]
	if _status != "":
		lines.append(_status)
	_info.text = "\n".join(lines)
	_help.visible = _show_help
	_logo.visible = _show_guides
	_guides.queue_redraw()


func _draw_guides() -> void:
	if not _show_guides:
		return
	var line := Color(1, 1, 1, 0.28)
	for i in [1, 2]:
		_guides.draw_line(Vector2(VIEW.x * i / 3.0, 0), Vector2(VIEW.x * i / 3.0, VIEW.y), line, 1.0)
		_guides.draw_line(Vector2(0, VIEW.y * i / 3.0), Vector2(VIEW.x, VIEW.y * i / 3.0), line, 1.0)
	_guides.draw_rect(Rect2(Vector2.ZERO, Vector2(VIEW)), Color(1, 1, 1, 0.35), false, 2.0)


# ------------------------------------------------------------------ 自己テスト（selftest=1）：本物の入力イベントを順に流す

func _st_wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _st_key(code: Key, shift := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		ev.shift_pressed = shift
		Input.parse_input_event(ev)
	await _st_wait(12)


func _st_drag(mask: MouseButtonMask, rel: Vector2) -> void:
	for i in range(10):
		var ev := InputEventMouseMotion.new()
		ev.position = Vector2(960, 540)
		ev.relative = rel / 10.0
		ev.button_mask = mask
		Input.parse_input_event(ev)
		await _st_wait(1)
	await _st_wait(4)


func _st_wheel(index: MouseButton, times: int, ctrl := false) -> void:
	for i in range(times):
		var ev := InputEventMouseButton.new()
		ev.position = Vector2(960, 540)
		ev.button_index = index
		ev.pressed = true
		ev.ctrl_pressed = ctrl
		Input.parse_input_event(ev)
		await _st_wait(1)
	await _st_wait(4)


func _st_log(what: String) -> void:
	print("[thumbtune selftest] %-14s %s" % [what, _args_text()])


func _run_selftest() -> void:
	await _st_wait(10)
	_st_log("start")
	await _st_key(KEY_P)
	await _st_wait(20)
	await _st_drag(MOUSE_BUTTON_MASK_RIGHT, Vector2(80, 0))
	_st_log("look right")
	await _st_drag(MOUSE_BUTTON_MASK_LEFT, Vector2(-120, -40))
	_st_log("orbit")
	await _st_drag(MOUSE_BUTTON_MASK_MIDDLE, Vector2(0, 60))
	_st_log("pan")
	await _st_wheel(MOUSE_BUTTON_WHEEL_UP, 4)
	_st_log("zoom in")
	await _st_wheel(MOUSE_BUTTON_WHEEL_DOWN, 3, true)
	_st_log("dolly out")
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	var until := Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < until:
		await _st_wait(1)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _st_wait(4)
	_st_log("W 0.4s")
	await _st_key(KEY_BRACKETRIGHT)
	_st_log("dof +")
	await _st_key(KEY_T)
	await _st_wait(20)
	if not _preview.visible:
		await _st_key(KEY_T)
		await _st_wait(20)
	print("[thumbtune selftest] preview       %s" % _preview.visible)
	await _st_key(KEY_ENTER)
	print("[thumbtune selftest] clipboard     %s" % DisplayServer.clipboard_get())
	await _st_wait(4)
	var hud_image := get_viewport().get_texture().get_image()
	hud_image.save_png(ProjectSettings.globalize_path(out + "selftest_hud.png"))
	await _st_key(KEY_P)
	await _st_wait(20)
	await _st_key(KEY_N)
	while not _tuning:
		await _st_wait(1)
	await _st_wait(10)
	_st_log("after N")
	await _st_key(KEY_R)
	_st_log("reset")
	await _st_drag(MOUSE_BUTTON_MASK_RIGHT, Vector2(40, 0))
	_st_log("before rewind")
	await _st_key(KEY_B)      # 1 フレーム戻す：起動し直した側（selftest=done）が止まったフレームと画角を出す


func _quit() -> void:
	if _tuning:
		_log_args("quit")
	_tuning = false
	_running = false
	if _hud != null:
		_hud.visible = false
	get_tree().paused = false
	_finish()
