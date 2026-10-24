class_name FloatplaneSound
extends Node

## 水上機 C-130 のエンジンの音（docs/sound_effects.md「サドンデス」）。機体の子に置き、FloatplaneStaging が鳴らす間だけ有効にする。
## 2 つのループを機体の回転（SuddenDeathFloatplane.prop_speed）・逆推力・推力（thrust）で音量と音程を変えて重ねる：
##   エンジン（fp_engine_loop：飛んでいる機体の低いうなりと甲高い音）、プロペラ（fp_prop_loop：羽根のブーンという音、回転で音程が上がる）。
## カメラが機内（貨物室・操縦席）にいるときはこもった音にし、外では距離で小さく・高域を落とし・左右に振り、近づく／遠ざかるドップラー。
## 専用のバス（SFX へ送る）なので効果音量の設定が効く。メニュー（menu_sfx_muted）・ポーズ・画面の暗転では鳴らない。

const ENGINE_LOOP := "res://assets/audio/sfx/se_lab/fp_engine_loop.ogg"
const PROP_LOOP := "res://assets/audio/sfx/se_lab/fp_prop_loop.ogg"
const SILENCE_DB := -80.0
## 外で聞こえる大きさ：この距離までは同じ大きさ、そこから先は距離で下がり、FADE_FROM〜FADE_TO で消える。
const NEAR_DISTANCE := 30.0
const FADE_FROM := 140.0
const FADE_TO := 300.0
## 機内とみなす範囲（機体のローカル。貨物室・操縦席の段・スロープの付け根まで）。
const CABIN_MIN := Vector3(-2.15, 1.6, -6.9)
const CABIN_MAX := Vector3(2.15, 5.9, 4.7)
## 機内のこもり：後ろのスロープと上のふたが閉じているとき／開いているときの高域の上限（Hz）。
const CABIN_CUTOFF_CLOSED := 1500.0
const CABIN_CUTOFF_OPEN := 5200.0
## 通過の録音（fp_flyby）を鳴らす間、ループをこれだけ下げる（同じ機体の音が二重にならない）。
const FLYBY_DUCK_DB := -9.0
## 回転いっぱい・すぐ近く（NEAR_DISTANCE 以内）での大きさ（dB）。機内ではエンジンを 1 dB、プロペラを 7 dB 下げる。
## 降下でカメラが機外へ出た瞬間（全開の機体のすぐ横）に、ほかの音を埋めない大きさ（2026-10-20 の録音で決めた）。
const ENGINE_DB := -7.0
const PROP_DB := -7.0

var enabled := false
## 推力（0〜1）。FloatplaneStaging が場面ごとに入れる（離水で 1、巡航で 0.55、待つ間は 0）。
var thrust := 0.0
var mix_gain := 0.0
var _plane: SuddenDeathFloatplane
var _bus := ""
var _panner: AudioEffectPanner
var _filter: AudioEffectLowPassFilter
var _engine: AudioStreamPlayer
var _prop: AudioStreamPlayer
var _inside := 0.0
var _last_distance := -1.0
var _doppler := 1.0
var _duck_until := -1.0
var _duck := 1.0


func setup(plane: SuddenDeathFloatplane) -> void:
	_plane = plane
	name = "FloatplaneSound"
	_bus = "Floatplane_%d" % get_instance_id()
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, _bus)
	AudioServer.set_bus_send(index, "SFX")
	_panner = AudioEffectPanner.new()
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = 10000.0
	AudioServer.add_bus_effect(index, _panner)
	AudioServer.add_bus_effect(index, _filter)
	AudioServer.set_bus_volume_db(index, SILENCE_DB)
	_engine = _make_player("Engine", ENGINE_LOOP)
	_prop = _make_player("Prop", PROP_LOOP)
	set_process(false)


func _make_player(label: String, path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = label
	player.bus = _bus
	player.volume_db = SILENCE_DB
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStreamOggVorbis
		if stream != null:
			stream = stream.duplicate() as AudioStreamOggVorbis
			stream.loop = true
			player.stream = stream
	add_child(player)
	return player


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	set_process(value)
	if not value:
		stop()


func stop() -> void:
	mix_gain = 0.0
	_last_distance = -1.0
	for player: AudioStreamPlayer in [_engine, _prop]:
		if player != null:
			player.stop()
			player.volume_db = SILENCE_DB
	var index := AudioServer.get_bus_index(_bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, SILENCE_DB)


## 通過の録音を鳴らす間（seconds 秒）、ループを FLYBY_DUCK_DB 下げる。
func duck_for(seconds: float) -> void:
	_duck_until = maxf(_duck_until, Time.get_ticks_msec() / 1000.0 + seconds)


## カメラが機内にいる度合い（0＝外、1＝機内）。テストの記録用。
func inside_amount() -> float:
	return _inside


func _audible() -> bool:
	return enabled and is_instance_valid(_plane) and _plane.is_visible_in_tree() and not AudioManager.menu_sfx_muted \
		and not get_tree().paused and not SceneTransition.is_fully_covered()


func _process(delta: float) -> void:
	if not _audible():
		# 機体が隠れた（遠くへ飛び去った・場面が替わった）ときは 0.25 秒で消す（ぷつっと切らない）。ポーズ・暗転・メニューはすぐ止める。
		var hidden_only := enabled and is_instance_valid(_plane) and not _plane.is_visible_in_tree() and not AudioManager.menu_sfx_muted \
			and not SceneTransition.is_fully_covered()
		if hidden_only and mix_gain > 0.002:
			mix_gain = move_toward(mix_gain, 0.0, delta * 4.0)
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index(_bus), linear_to_db(maxf(mix_gain, 0.0001)))
			return
		if mix_gain > 0.0 or _engine.playing or _prop.playing:
			stop()
		return
	var camera := _plane.get_viewport().get_camera_3d()
	if camera == null:
		stop()
		return
	var local := _plane.global_transform.affine_inverse() * camera.global_position
	var in_cabin := local.x > CABIN_MIN.x and local.x < CABIN_MAX.x and local.y > CABIN_MIN.y and local.y < CABIN_MAX.y \
		and local.z > CABIN_MIN.z and local.z < CABIN_MAX.z
	# 機内と外の切り替えはなめらかに（カメラが窓や開口を通り抜ける）
	_inside = move_toward(_inside, 1.0 if in_cabin else 0.0, delta * 4.0)
	var offset := _plane.global_position - camera.global_position
	var distance := offset.length()
	var outside_gain := pow(NEAR_DISTANCE / maxf(NEAR_DISTANCE, distance), 1.25) * (1.0 - smoothstep(FADE_FROM, FADE_TO, distance))
	var target_gain := lerpf(outside_gain, 1.0, _inside)
	target_gain *= pow(1.0 - SceneTransition.get_cover_factor(), 1.5)
	var now := Time.get_ticks_msec() / 1000.0
	_duck = lerpf(_duck, db_to_linear(FLYBY_DUCK_DB) if now < _duck_until else 1.0, 1.0 - exp(-delta * 3.0))
	target_gain *= _duck
	mix_gain = lerpf(mix_gain, target_gain, 1.0 - exp(-delta * 8.0))
	var index := AudioServer.get_bus_index(_bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(mix_gain, 0.0001)))
	var pan := clampf(offset.dot(camera.global_basis.x) / maxf(distance * 0.6, 1.0), -0.7, 0.7) * (1.0 - _inside)
	_panner.pan = lerpf(_panner.pan, pan, 1.0 - exp(-delta * 8.0))
	var open := maxf(_plane.ramp_t, _plane.upper_door_t)
	var cabin_cut := lerpf(CABIN_CUTOFF_CLOSED, CABIN_CUTOFF_OPEN, clampf(open, 0.0, 1.0))
	var outside_cut := lerpf(10000.0, 2200.0, smoothstep(40.0, 220.0, distance))
	_filter.cutoff_hz = lerpf(outside_cut, cabin_cut, _inside)
	# ドップラー（機内では機体と一緒に動くので無し）。急なカメラの動きで極端にならないよう 0.86〜1.16 倍に。
	# カメラのカット（1 フレームで 25 m 以上）は近づく／遠ざかる動きに数えない
	var jumped := _last_distance < 0.0 or absf(distance - _last_distance) > 25.0
	var radial := 0.0 if jumped else clampf((distance - _last_distance) / maxf(delta, 0.001), -80.0, 80.0)
	_last_distance = distance
	var doppler := lerpf(clampf(343.0 / (343.0 + radial), 0.86, 1.16), 1.0, _inside)
	_doppler = lerpf(_doppler, doppler, 1.0 - exp(-delta * 5.0))
	var spin := clampf(_plane.prop_speed, 0.0, 1.0)
	var reverse := _plane.reverse_mix()
	var push := clampf(thrust, 0.0, 1.0)
	# エンジン：回っていれば常にうなる。推力で少し大きく・高く
	_bed(_engine, 0.32 + 0.5 * spin + 0.18 * push, ENGINE_DB - 1.0 * _inside, (0.8 + 0.2 * spin + 0.05 * push) * _doppler, delta)
	# プロペラ：回転で大きく・高く（いっぱいで 68 Hz の羽根の音）。逆推力で羽根が空気を強く叩く
	var prop_amount := pow(spin, 1.5) * (0.55 + 0.45 * push) + 0.35 * reverse * spin
	_bed(_prop, prop_amount, PROP_DB - 7.0 * _inside, (0.55 + 0.45 * spin) * (1.0 + 0.05 * reverse) * _doppler, delta)


func _bed(player: AudioStreamPlayer, amount: float, level: float, pitch: float, delta: float) -> void:
	if player == null or player.stream == null:
		return
	var gain := db_to_linear(player.volume_db)
	gain = lerpf(gain, db_to_linear(level) * maxf(amount, 0.0), 1.0 - exp(-delta * 10.0))
	player.volume_db = linear_to_db(maxf(gain, 0.0001))
	player.pitch_scale = clampf(lerpf(player.pitch_scale, pitch, 1.0 - exp(-delta * 8.0)), 0.3, 2.0)
	if gain > 0.00015 and mix_gain > 0.00015:
		if not player.playing:
			player.play(randf() * player.stream.get_length())
	elif player.playing:
		player.stop()


func _exit_tree() -> void:
	stop()
	var index := AudioServer.get_bus_index(_bus)
	if index >= 0:
		AudioServer.remove_bus(index)
