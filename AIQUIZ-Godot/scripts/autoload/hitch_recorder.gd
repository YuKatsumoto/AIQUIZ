extends Node

## 固まり記録。GameManager が起動時に子として作る。
## ・1 フレームが HITCH_MS を超えたら、そのとき何が起きていたか（場面・試合の状態・壁の番号・
##   描画の部品（パイプライン）を作った数・増えたノード数）を user://logs/hitches.log に 1 行ずつ書く。
##   提出先などほかの PC で止まったときに、何が原因だったかをあとから確かめるため（製品版でも書く）。
## ・試合中に描画の部品を作ったら、開発中の実行（デバッグビルド）では警告を出す。この PC ではすぐ作れても、
##   新しい PC ではそこで止まる。試合の準備（GameWorld._prepare_world_visuals_under_cover）で描いておくこと。

const PipelineWatch = preload("res://scripts/core/pipeline_watch.gd")

const HITCH_MS := 100.0
const LOG_PATH := "user://logs/hitches.log"
const OLD_LOG_PATH := "user://logs/hitches.old.log"
const MAX_LOG_BYTES := 256 * 1024
const MAX_WARNINGS := 30
## 覆いが開いたあとの試合の状態（ここで部品を作ると、プレイ中に止まる）。
const MATCH_STATES: Array[String] = [
	"FLYOVER", "COUNTDOWN", "PLAYING", "CORRECT", "GOAL_RACE", "SUDDEN_DEATH", "GAME_OVER",
	"RESULT_CEREMONY", "CLEAR",
]

## 試合中に作った部品の数（止まりの元になる種類だけ）。テストが読む。
var match_stall_compiles := 0
## 試合中に部品を作ったときの記録（直近 MAX_WARNINGS 件）。テストが読む。
var match_compile_events: Array[Dictionary] = []

var _last_usec := 0
var _last_counts: Array[int] = []
var _last_nodes := 0
var _warnings := 0
var _session_written := false
## 調べるとき（計測の --trace_visuals）だけ：部品を作ったフレームで、初めて見えた物・見た目（材質・半透明）が
## 変わった物を記録に付ける。毎フレーム木全体を調べるので重い。
var trace_new_visuals := false:
	set(value):
		trace_new_visuals = value
		if value and not get_tree().node_added.is_connected(_on_node_added):
			get_tree().node_added.connect(_on_node_added)
var _visual_signatures := {}
## trace_new_visuals のとき、前のフレームから木に入った 3D の描画物・光・ビューポート。
var _added_visuals: Array[String] = []
var _added_history: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ほかのノードの処理がすべて終わったあとで測る。
	process_priority = 1 << 30
	_last_usec = Time.get_ticks_usec()
	_last_counts = PipelineWatch.counts()
	_last_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt_ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	var counts := PipelineWatch.counts()
	var compiled := PipelineWatch.delta(_last_counts, counts)
	var stalls := PipelineWatch.delta(_last_counts, counts, true)
	_last_counts = counts
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var nodes_added := nodes - _last_nodes
	_last_nodes = nodes
	var context := _context()
	var changed_visuals: Array[String] = []
	if trace_new_visuals:
		changed_visuals = _changed_visuals()
	if bool(context.in_match) and not stalls.is_empty():
		_note_match_compile(stalls, context, changed_visuals)
	if trace_new_visuals:
		# 部品作りは足した数フレームあとに終わることがあるので、最近 8 フレームぶんを残す。
		_added_history.append(_added_visuals.duplicate())
		if _added_history.size() > 8:
			_added_history.pop_front()
		_added_visuals.clear()
	if dt_ms > HITCH_MS:
		var entry := {
			"at": Time.get_datetime_string_from_system(false, true),
			"frame_ms": snappedf(dt_ms, 0.1),
			"pipelines": compiled,
			"nodes_added": nodes_added,
		}
		entry.merge(context)
		_write(entry)


func _context() -> Dictionary:
	var scene := get_tree().current_scene
	var scene_name := String(scene.name) if scene != null else ""
	var transition := SceneTransition.is_transitioning() if SceneTransition.has_method("is_transitioning") else false
	var gs: QuizGameState = QuizManager.game_state if QuizManager != null else null
	var state := String(gs.game_state) if gs != null else ""
	# 本物の始まり方（覆いの下の準備）を通った試合だけを見る。準備を飛ばして試合の途中から始めるテストは見ない。
	var prepared: bool = scene != null and scene.get("_world_visual_prepared") == true
	var in_match := scene_name == "GameWorld" and prepared and not transition and state in MATCH_STATES
	return {
		"scene": scene_name,
		"state": state,
		"wall": gs.current_wall_index if gs != null else -1,
		"players": gs.num_players if gs != null else 0,
		"mode": String(gs.mode) if gs != null else "",
		"in_match": in_match,
		"transition": transition,
		"loading": GameManager.startup_loading,
		"paused": get_tree().paused,
		"focused": DisplayServer.window_is_focused(),
	}


func _note_match_compile(stalls: Dictionary, context: Dictionary, changed_visuals: Array[String] = []) -> void:
	var count := 0
	for kind: String in stalls:
		count += int(stalls[kind])
	match_stall_compiles += count
	var event := {"pipelines": stalls, "state": context.state, "wall": context.wall, "mode": context.mode}
	if not changed_visuals.is_empty():
		event["new_visuals"] = changed_visuals.slice(0, 16)
	if trace_new_visuals:
		event["cameras"] = _active_cameras()
		var recent: Array[String] = []
		for frame_added: Array in _added_history:
			for item in frame_added:
				recent.append("(prev) " + str(item))
		recent.append_array(_added_visuals)
		if not recent.is_empty():
			event["added"] = recent.slice(maxi(0, recent.size() - 16), recent.size())
	match_compile_events.append(event)
	if match_compile_events.size() > MAX_WARNINGS:
		match_compile_events.pop_front()
	if OS.is_debug_build() and _warnings < MAX_WARNINGS:
		_warnings += 1
		push_warning(
			"[HitchRecorder] 試合中に描画の部品（パイプライン）を作りました。新しい PC ではここで止まります。"
			+ " 試合の準備（GameWorld._prepare_world_visuals_under_cover）で描いておいてください: %s"
			% JSON.stringify(event)
		)


func _on_node_added(node: Node) -> void:
	if _added_visuals.size() >= 64:
		return
	if node is VisualInstance3D:
		_added_visuals.append("%s %s%s" % [_visual_signature(node as VisualInstance3D), str(node.get_path()).trim_prefix("/root/"),
			"" if (node as VisualInstance3D).visible else " (hidden)"])
	elif node is SubViewport or node is WorldEnvironment:
		_added_visuals.append("%s %s" % [node.get_class(), str(node.get_path()).trim_prefix("/root/")])


## いま描いているカメラ（各ビューポートの current）と、その環境で使っている機能。
func _active_cameras() -> Array[String]:
	var out: Array[String] = []
	for node: Node in get_tree().root.find_children("*", "Camera3D", true, false):
		var camera := node as Camera3D
		if not camera.current or not camera.is_inside_tree():
			continue
		var viewport := camera.get_viewport()
		if viewport is SubViewport and (viewport as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED:
			continue
		var env := camera.environment if camera.environment != null else (camera.get_world_3d().environment if camera.get_world_3d() != null else null)
		var features := ""
		if env != null:
			features = "fog%d vfog%d glow%d ssao%d ssr%d ssil%d sdfgi%d" % [
				int(env.fog_enabled), int(env.volumetric_fog_enabled), int(env.glow_enabled), int(env.ssao_enabled),
				int(env.ssr_enabled), int(env.ssil_enabled), int(env.sdfgi_enabled),
			]
		out.append("%s msaa%d %s" % [str(camera.get_path()).trim_prefix("/root/"), viewport.msaa_3d, features])
	return out


## 前のフレームから、初めて見えた物と見た目の変わった物（trace_new_visuals のときだけ）。
func _changed_visuals() -> Array[String]:
	var current := {}
	var changed: Array[String] = []
	for node: Node in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree():
			continue
		var signature := _visual_signature(visual)
		current[visual.get_instance_id()] = signature
		if _visual_signatures.get(visual.get_instance_id(), "") != signature:
			changed.append("%s %s" % [signature, str(visual.get_path()).trim_prefix("/root/")])
	for node: Node in get_tree().root.find_children("*", "CanvasItem", true, false):
		var item := node as CanvasItem
		if item.material == null or not item.is_visible_in_tree():
			continue
		var signature := "Canvas %s" % _material_signature(item.material)
		current[item.get_instance_id()] = signature
		if _visual_signatures.get(item.get_instance_id(), "") != signature:
			changed.append("%s %s" % [signature, str(item.get_path()).trim_prefix("/root/")])
	_visual_signatures = current
	return changed


func _visual_signature(visual: VisualInstance3D) -> String:
	if visual is Light3D:
		var light := visual as Light3D
		var mode := ""
		if light is OmniLight3D:
			mode = " omni%d" % (light as OmniLight3D).omni_shadow_mode
		elif light is DirectionalLight3D:
			mode = " dir%d" % (light as DirectionalLight3D).directional_shadow_mode
		return "%s[shadow%d%s proj%d]" % [light.get_class(), int(light.shadow_enabled), mode, int(light.light_projector != null)]
	if visual is Label3D:
		var label := visual as Label3D
		return "Label3D[ac%d sh%d ds%d ndt%d fs%d bb%d out%d a%d rp%d tr%.2f]" % [
			label.alpha_cut, int(label.shaded), int(label.double_sided), int(label.no_depth_test), int(label.fixed_size),
			label.billboard, int(label.outline_size > 0), int(label.modulate.a < 0.999), label.render_priority, label.transparency,
		]
	if not visual is GeometryInstance3D:
		return visual.get_class()
	var geometry := visual as GeometryInstance3D
	var material: Material = geometry.material_override
	if material == null and geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null 			and (geometry as MeshInstance3D).mesh.get_surface_count() > 0:
		material = (geometry as MeshInstance3D).get_active_material(0)
	if material == null and geometry is GPUParticles3D and (geometry as GPUParticles3D).draw_pass_1 != null 			and (geometry as GPUParticles3D).draw_pass_1.get_surface_count() > 0:
		material = (geometry as GPUParticles3D).draw_pass_1.surface_get_material(0)
	var material_id := material.get_instance_id() if material != null else 0
	var mesh_id := (geometry as MeshInstance3D).mesh.get_instance_id() if geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null else 0
	return "%s[%s tr%.2f cs%d m%d g%d]" % [geometry.get_class(), _material_signature(material), geometry.transparency, geometry.cast_shadow, material_id % 100000, mesh_id % 100000]


static func _material_signature(material: Material) -> String:
	if material is StandardMaterial3D or material is ORMMaterial3D:
		var base := material as BaseMaterial3D
		return "std t%d sh%d cull%d em%d bl%d dd%d" % [
			base.transparency, base.shading_mode, base.cull_mode, int(base.emission_enabled), base.blend_mode, base.depth_draw_mode,
		]
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		return "shader %s" % (shader.resource_path.get_file() if shader != null and not shader.resource_path.is_empty() else "inline")
	if material is ParticleProcessMaterial:
		return "particles"
	return material.get_class() if material != null else "none"


func _write(entry: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_PATH.get_base_dir()))
	if FileAccess.file_exists(LOG_PATH):
		var size_file := FileAccess.open(LOG_PATH, FileAccess.READ)
		if size_file != null and size_file.get_length() > MAX_LOG_BYTES:
			size_file.close()
			if FileAccess.file_exists(OLD_LOG_PATH):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_LOG_PATH))
			DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path(OLD_LOG_PATH))
		elif size_file != null:
			size_file.close()
	var file: FileAccess
	if FileAccess.file_exists(LOG_PATH):
		file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	if not _session_written:
		_session_written = true
		file.store_line(JSON.stringify({
			"session": Time.get_datetime_string_from_system(false, true),
			"game": ProjectSettings.get_setting("application/config/name", ""),
			"version": ProjectSettings.get_setting("application/config/version", ""),
			"gpu": RenderingServer.get_video_adapter_name(),
			"gpu_api": RenderingServer.get_video_adapter_api_version(),
			"cpu": OS.get_processor_name(),
			"quality": GameManager.graphics_quality,
			"window": str(DisplayServer.window_get_size()),
		}))
	file.store_line(JSON.stringify(entry))
	file.close()
