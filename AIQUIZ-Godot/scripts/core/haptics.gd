extends RefCounted

## Short vibrations that give touch controls the feedback a key press has.
## Silent on desktop and when the player turned haptics off in the settings.
##
## Use: const Haptics = preload("res://scripts/core/haptics.gd")
##      Haptics.pulse(Haptics.TAP)

const QualityRules = preload("res://scripts/core/graphics_quality.gd")

## Duration (ms) and amplitude (0..1) per kind of event.
const TAP := "tap"            ## a virtual button went down
const SUCCESS := "success"    ## correct door, sudden-death win
const BUMP := "bump"          ## shoulder clash in a push duel
const HIT := "hit"            ## damage, elimination
const CHARGE := "charge"      ## ghost-shark charge became PERFECT
const COUNTDOWN := "countdown"

const PATTERNS := {
	TAP: [12, 0.35],
	SUCCESS: [28, 0.6],
	BUMP: [22, 0.8],
	HIT: [60, 1.0],
	CHARGE: [18, 0.5],
	COUNTDOWN: [16, 0.45],
}

## Real vibration only happens on a handheld; previews just log nothing.
static var _last_pulse_msec: int = -1000


static func enabled() -> bool:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var manager := tree.root.get_node_or_null("/root/GameManager")
	return manager == null or bool(manager.get("haptics_enabled"))


static func pulse(kind: String) -> void:
	if not enabled():
		return
	# Back-to-back events (several walls in one frame) collapse into one buzz.
	var now := Time.get_ticks_msec()
	if now - _last_pulse_msec < 40:
		return
	_last_pulse_msec = now
	var pattern: Array = PATTERNS.get(kind, PATTERNS[TAP])
	Input.vibrate_handheld(int(pattern[0]), float(pattern[1]))
