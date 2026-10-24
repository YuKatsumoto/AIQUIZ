extends SceneTree

## 読み込めるかだけを見る（スクリプトの文法と型）。オートロードのあとで読む。
##   Godot --headless --path . --script res://tests/sudden_death_v2/parse_check.gd
func _initialize() -> void:
	call_deferred("check")


func check() -> void:
	var paths := [
		"res://scripts/world/sudden_death/heli_sudden_death_director.gd",
		"res://scripts/world/sudden_death/floatplane/floatplane_staging.gd",
		"res://scripts/world/sudden_death/floatplane/floatplane_flight.gd",
		"res://scripts/world/sudden_death/floatplane/floatplane_wake.gd",
		"res://scripts/world/sudden_death/floatplane/sudden_death_floatplane.gd",
		"res://scripts/world/sudden_death/floatplane/floatplane_sound.gd",
		"res://scripts/world/sudden_death/cloud_cover.gd",
		"res://scripts/autoload/audio_manager.gd",
		"res://scripts/world/sudden_death/stage_gate/stand_gate.gd",
		"res://tests/sudden_death_v2/floatplane_flight_check.gd",
		"res://scripts/core/game_state.gd",
		"res://scripts/world/game_world.gd",
		"res://scripts/world/sudden_death/games/sky_gate_presenter.gd",
		"res://scripts/world/sudden_death/games/sky_gate_board.gd",
		"res://scripts/world/sudden_death/games/sky_gate_impact.gd",
		"res://scripts/world/sudden_death/games/sky_gate_limp.gd",
		"res://scripts/world/sudden_death/games/sky_gate_rule_demo.gd",
		"res://scripts/ui/sudden_death/sky_gate_hud.gd",
		"res://scripts/core/sudden_death/sky_gate_game.gd",
		"res://scripts/world/sudden_death/sky_fx/sky_fall_scarf.gd",
		"res://tests/sudden_death_v2/skygate_runtime.gd",
		"res://tests/sudden_death_v2/skygate_audio_runtime.gd",
		"res://tests/sudden_death_v2/parachute_runtime.gd",
		"res://scripts/world/sudden_death/ghost_revival.gd",
		"res://scripts/world/result_finale/result_finale_stage.gd",
		"res://scripts/world/player_controller.gd",
		"res://tests/sudden_death_v2/ghost_revive_runtime.gd",
	]
	var bad := 0
	for path: String in paths:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			bad += 1
			print("PARSE_FAIL ", path)
	print("PARSE_CHECK bad=", bad)
	quit(bad)
