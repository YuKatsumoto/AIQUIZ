extends RefCounted

## Debug: framings for the saw shot in a 2P PLAYING world. Segments: cam_<n>.

var kit

## eye, target, fov as offsets from (0, 0, saw local z); the floor top is y -1.2, the blade faces
## about y -0.84, the lead runners about 10.85 m ahead of the blades at x +-2.5.
const FRAMINGS := [
	[Vector3(6.5, 3.2, -2.5), Vector3(-1.5, -1.0, 7.0), 58.0],
	[Vector3(1.0, 4.0, 17.5), Vector3(0.0, -1.0, 3.0), 55.0],
	[Vector3(2.5, 3.0, 16.0), Vector3(0.0, -0.8, 5.0), 50.0],
	[Vector3(0.0, 5.5, 19.0), Vector3(0.0, -1.2, 4.0), 50.0],
]


func run(runner) -> void:
	kit = runner
	var world = await kit.build_world(2, "science34")
	var gs := QuizManager.game_state
	gs.player_x = 2.5
	gs.player2_x = -2.5
	await kit.seconds(2.5)
	var saw = world._saw_controller
	kit.note("saw_local_z", gs.saw.local_z)
	if saw != null:
		kit.note("saw_global", str((saw as Node3D).global_position))
	for i in range(FRAMINGS.size()):
		var f: Array = FRAMINGS[i]
		var base := Vector3(0.0, 0.0, gs.saw.local_z)
		kit.aim(base + f[0], base + f[1], f[2])
		kit.record("cam_%d" % i)
		await kit.seconds(0.6)
	kit.stop_record()
	kit.release_camera()
