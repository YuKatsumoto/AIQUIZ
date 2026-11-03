@tool
extends RefCounted

func run(ctx) -> void:
	var root: Node3D = ctx.root as Node3D
	var camera := root.get_node("PreviewCamera") as Camera3D
	var player := root.get_node("AnimationPlayer") as AnimationPlayer
	var frames: Array[Image] = []
	var labels: Array[String] = []
	# Initialize the detached scene before AnimationPlayer writes PathFollow3D ratios.
	await ctx.capture(root, {"camera": camera})
	var samples: Dictionary = {
		"intro_arrival": [0.0, 4.4, 5.3, 8.3, 10.95],
		"start_pickup": [0.0, 0.82, 1.4, 2.37, 2.76],
	}
	for animation_name: String in samples:
		player.assigned_animation = animation_name
		player.pause()
		for time_value: float in samples[animation_name]:
			player.seek(time_value, true, true)
			frames.append(await ctx.capture(root, {"camera": camera}))
			labels.append("%s %.2fs" % [animation_name, time_value])
	var pages: Array[Image] = ctx.sheet(frames, {
		"columns": 5,
		"cell_size": Vector2i(384, 216),
		"labels": labels,
	})
	for page_index: int in range(pages.size()):
		ctx.output(pages[page_index], "Editable helicopter timelines page %d" % (page_index + 1))
