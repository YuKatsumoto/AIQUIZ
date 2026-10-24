class_name WaterSplash
extends Node3D

## 敗者が海へ落ちたときの水柱（docs/sudden_death_v2/parachute.md 4.4節・6.5節）。素材は
## assets/sudden_death/parachute/chute/splash.glb（柱・クラウン・水滴・泡の輪・波紋。原点＝水面の中心）。
## play() から LENGTH 秒、時間に沿って広げて消す：柱はすぐ伸びて崩れ落ち、クラウンは開いて沈み、水滴は外へ飛んで落ち、
## 泡と波紋は広がって薄くなる。pose_at(t) でその時刻の形に置く（撮影用）。

const GLB := "res://assets/sudden_death/parachute/chute/splash.glb"
const LENGTH := 2.4

var _parts := {}
var _materials: Array[StandardMaterial3D] = []
var _t := INF


func build() -> void:
	var scene := load(GLB) as PackedScene
	if scene == null:
		push_warning("[Parachute] %s not found" % GLB)
		return
	var model := scene.instantiate() as Node3D
	add_child(model)
	for node: Node in model.find_children("Splash*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 薄くしていけるよう、材質を自分用に写す
		for s in range(mi.mesh.get_surface_count()):
			var source := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if source == null:
				continue
			var copy := source.duplicate() as StandardMaterial3D
			copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(s, copy)
			_materials.append(copy)
			mi.set_meta("base_alpha_%d" % s, source.albedo_color.a)
		_parts[String(mi.name)] = mi
	visible = false


func play() -> void:
	_t = 0.0
	visible = true
	_pose()


func advance(delta: float) -> void:
	if not is_finite(_t):
		return
	_t += delta
	_pose()
	if _t >= LENGTH:
		visible = false
		_t = INF


func pose_at(t: float) -> void:
	_t = t
	visible = true
	_pose()


func is_playing() -> bool:
	return is_finite(_t)


func _ease_out(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _pose() -> void:
	var t := _t
	# 柱：0.25 秒で伸び、0.7 秒から崩れ落ちる（太くなりながら低く）
	var rise := _ease_out(t / 0.25)
	var fall := clampf((t - 0.7) / 1.2, 0.0, 1.0)
	_pose_part("SplashColumn", Vector3(1.0 + 0.5 * fall, maxf(rise * (1.0 - fall * fall), 0.01), 1.0 + 0.5 * fall), Vector3.ZERO, 1.0 - fall)
	# クラウン：開いて、沈む
	var open := _ease_out(t / 0.45)
	var sink := clampf((t - 0.5) / 1.0, 0.0, 1.0)
	_pose_part("SplashCrown", Vector3(lerpf(0.4, 1.25, open), maxf(open * (1.0 - sink), 0.01), lerpf(0.4, 1.25, open)), Vector3.ZERO, 1.0 - sink)
	# 水滴：外へ広がって、落ちる
	var spread := _ease_out(t / 0.6)
	var drop := maxf(t - 0.4, 0.0)
	_pose_part("SplashDroplets", Vector3.ONE * lerpf(0.3, 1.4, spread), Vector3(0.0, -4.9 * drop * drop, 0.0), 1.0 - clampf((t - 1.1) / 0.6, 0.0, 1.0))
	# 泡の輪と波紋：広がって薄くなる
	var grow := _ease_out(t / LENGTH)
	_pose_part("SplashFoam", Vector3(lerpf(0.3, 1.25, grow), 1.0, lerpf(0.3, 1.25, grow)), Vector3.ZERO, 1.0 - clampf((t - 1.2) / 1.2, 0.0, 1.0))
	_pose_part("SplashRipple", Vector3(lerpf(1.0, 7.0, grow), 1.0, lerpf(1.0, 7.0, grow)), Vector3.ZERO, 1.0 - grow)


func _pose_part(name: String, scale_value: Vector3, offset: Vector3, alpha: float) -> void:
	var mi := _parts.get(name) as MeshInstance3D
	if mi == null:
		return
	mi.visible = alpha > 0.01
	mi.transform = Transform3D(Basis.from_scale(scale_value), offset)
	for s in range(mi.mesh.get_surface_count()):
		var mat := mi.get_surface_override_material(s) as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = float(mi.get_meta("base_alpha_%d" % s, 1.0)) * clampf(alpha, 0.0, 1.0)
