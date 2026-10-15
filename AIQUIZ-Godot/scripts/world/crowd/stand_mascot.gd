class_name StandMascot
extends Node3D

## The mascot Hatena in the stands, cheering with the crowd (docs/crowd_extras.md).
## One stands in the aisle of each side stand (the right one starts the stadium
## wave) and one at the front of the goal stand. Body: mascot_model.glb (the light
## mascot_model_lod.glb below the high quality), moves: mascot_stand.glb
## (assets/characters/aiquiz_mascot/source/build_stand_mascot.py), played with an
## AnimationPlayer the owner advances (`advance`), like the goal stand crowd.
##
##   play(&"idle") / play(&"cheer") / play(&"dance") / play(&"wave_lead") / play(&"clap")

const MASCOT_GLB := "res://assets/characters/aiquiz_mascot/mascot_model.glb"
const MASCOT_LOD_GLB := "res://assets/characters/aiquiz_mascot/mascot_model_lod.glb"
const STAND_ANIM_GLB := "res://assets/characters/aiquiz_mascot/mascot_stand.glb"
const QualityRules = preload("res://scripts/core/graphics_quality.gd")
const ACTIONS := {&"idle": "Stand_Idle", &"cheer": "Stand_Cheer", &"dance": "Stand_Dance",
	&"wave_lead": "Stand_WaveLead", &"clap": "Stand_Clap"}
const BLEND_SECONDS := 0.25
## Beyond this camera distance the mascot holds its pose (like the goal stand crowd).
const ACTIVE_DISTANCE := 170.0

static var _library: AnimationLibrary = null

var action := &"idle"
var player: AnimationPlayer = null
var _model: Node3D = null


func setup(quality: String) -> bool:
	var lod := not QualityRules.is_at_least(QualityRules.normalize(quality), QualityRules.HIGH)
	var path := MASCOT_LOD_GLB if lod and ResourceLoader.exists(MASCOT_LOD_GLB) else MASCOT_GLB
	if not ResourceLoader.exists(path):
		return false
	_model = (load(path) as PackedScene).instantiate() as Node3D
	if _model == null:
		return false
	_model.name = "Hatena"
	add_child(_model)
	for node: Node in _model.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mesh.visibility_range_end = 320.0
	var library := _stand_library()
	if library == null:
		return true
	player = AnimationPlayer.new()
	player.name = "StandAnimation"
	_model.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(ACTIONS[&"idle"])
	player.seek(randf() * 2.0, true)
	return true


static func _stand_library() -> AnimationLibrary:
	if _library != null:
		return _library
	if not ResourceLoader.exists(STAND_ANIM_GLB):
		return null
	var source := (load(STAND_ANIM_GLB) as PackedScene).instantiate()
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null:
		source.free()
		return null
	_library = AnimationLibrary.new()
	for clip_name: StringName in source_player.get_animation_list():
		var clip := source_player.get_animation(clip_name).duplicate(true) as Animation
		clip.loop_mode = Animation.LOOP_LINEAR
		_library.add_animation(clip_name, clip)
	source.free()
	return _library


func play(next: StringName, restart := false) -> void:
	if player == null or (next == action and not restart):
		return
	action = next
	var clip: String = ACTIONS.get(next, ACTIONS[&"idle"])
	if not player.has_animation(clip):
		return
	if restart:
		player.play(clip, 0.1)
		player.seek(0.0, true)
	else:
		player.play(clip, BLEND_SECONDS)


## Plays `next` at `time` seconds (beat-synced moves: the chant's clap).
func play_at(next: StringName, time: float) -> void:
	if player == null:
		return
	var clip: String = ACTIONS.get(next, ACTIONS[&"idle"])
	if not player.has_animation(clip):
		return
	if next != action:
		action = next
		player.play(clip, BLEND_SECONDS)
	var length := player.get_animation(clip).length
	player.seek(fposmod(time, maxf(length, 0.01)), true)


func advance(delta: float) -> void:
	if player != null:
		player.advance(delta)


## Picks a move from the crowd's cues: lead the wave as it leaves (or passes),
## clap with the chant, dance with the winner, cheer on goals and the start.
## `wave_since` is the seconds since the wave reached this mascot (or < 0).
func follow(cues: CrowdCues, delta: float, wave_since: float, camera_distance: float) -> void:
	if player == null or cues == null:
		return
	if camera_distance > ACTIVE_DISTANCE:
		return
	if wave_since >= -0.6 and wave_since < 1.2:
		play(&"wave_lead")
	elif cues.sync_weight > 0.3:
		play(&"dance")
	elif cues.cue_weight() > 0.3 and cues.cue in [CrowdCues.Cue.GOAL, CrowdCues.Cue.VERDICT, CrowdCues.Cue.START]:
		play(&"cheer")
	elif cues.chant_weight() > 0.3:
		play_at(&"clap", cues.chant_time())
		return
	elif cues.cue_weight() > 0.3 and cues.cue == CrowdCues.Cue.COUNTDOWN:
		play(&"clap")
	else:
		play(&"idle")
	advance(delta)
