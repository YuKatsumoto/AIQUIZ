extends RefCounted

## PV shot: the first wall of four more subjects (理科・国語・社会・英語), each written by the
## AI for its grade. A low camera ahead of the runner watches the wall come in, so the
## question and the door answers read. Segments: wall_<set>.

const SETS := ["science34", "japanese4", "social4", "english3"]

var kit  # tests/pv/pv_runtime.gd


func run(runner) -> void:
	kit = runner
	for set_name: String in SETS:
		var world = await kit.build_world(1, set_name)
		var gs := QuizManager.game_state
		gs.player_x = 0.0
		# The world is drawn relative to the belt (local z = z - world_scroll_z); the wall comes in
		# along +z. The camera sits just ahead of the runner, low, facing the wall.
		var local_z := gs.player_z - gs.world_scroll_z
		kit.pose(Vector3(0.0, 1.9, local_z + 2.5), Vector3(0.0, 2.2, local_z + 20.0), 46.0)
		await kit.seconds(0.5)
		kit.record("wall_" + set_name)
		await kit.seconds(3.2)
		kit.stop_record()
		kit.note("wall_" + set_name, {"question": gs.current_quiz.q if gs.current_quiz != null else "", "wall_z": gs.wall_z})
