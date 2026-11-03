extends RefCounted


func run(ctx: Variant) -> void:
	var preview := _find_preview(ctx.get_scene_root())
	if preview == null:
		ctx.error("MenuWallBackgroundPreview was not found")
		return

	var player_ready: Dictionary = await ctx.until(
		func() -> bool:
			var current := _find_preview(ctx.get_scene_root())
			return (
				current != null
				and current.get("_preview_player") is PlayerController
			),
		{"timeout": 4.0, "interval": 0.05}
	)
	if not bool(player_ready.get("success", false)):
		ctx.error("Preview player did not become ready")
		return

	preview = _find_preview(ctx.get_scene_root())
	var started := bool(preview.call("begin_game_start_departure", 1))
	ctx.log("departure started", {"started": started})
	if not started:
		ctx.error("begin_game_start_departure returned false")
		return

	await ctx.capture("departure_started")
	var finished: Dictionary = await ctx.until(
		func() -> bool:
			var current := _find_preview(ctx.get_scene_root())
			return (
				current != null
				and not bool(current.call("is_game_start_departure_active"))
			),
		{"timeout": 6.0, "interval": 0.05}
	)
	if not bool(finished.get("success", false)):
		ctx.error("Menu departure did not finish")
		ctx.release_all_inputs()
		return

	preview = _find_preview(ctx.get_scene_root())
	var player := preview.get("_preview_player") as PlayerController
	var visible_after_finish := _visible_runner_mesh_count(player)
	ctx.log("after departure finish", {
		"player_visible": player.visible if player != null else false,
		"intro_arrival": player.has_intro_arrival() if player != null else false,
		"extracted": bool(player.get("_intro_extracted")) if player != null else false,
		"hold": bool(preview.get("_menu_departure_hold")),
		"visible_meshes": visible_after_finish,
	})

	var visible_frames := 0
	var sampled_frames := 0
	var max_visible := visible_after_finish
	for _frame_index: int in range(24):
		await ctx.wait(0.0)
		preview = _find_preview(ctx.get_scene_root())
		if preview == null:
			break
		player = preview.get("_preview_player") as PlayerController
		if player == null:
			break
		if player.has_method("update_from_state") and preview.get("_preview_gs") != null:
			player.update_from_state(preview.get("_preview_gs"))
		var visible_now := _visible_runner_mesh_count(player)
		sampled_frames += 1
		max_visible = maxi(max_visible, visible_now)
		if visible_now > 0 and player.visible:
			visible_frames += 1

	await ctx.capture("after_departure_hold")
	ctx.log("post-finish visibility sample", {
		"sampled_frames": sampled_frames,
		"visible_frames": visible_frames,
		"max_visible_meshes": max_visible,
		"hold": bool(preview.get("_menu_departure_hold")) if preview != null else false,
	})
	if visible_frames > 0:
		ctx.error("Standing runner became visible after helicopter extraction")
	ctx.release_all_inputs()


func _find_preview(root: Node) -> Node:
	if root == null:
		return null
	if root is MenuWallBackgroundPreview:
		return root
	for child: Node in root.get_children():
		var found := _find_preview(child)
		if found != null:
			return found
	return null


func _visible_runner_mesh_count(player: PlayerController) -> int:
	if player == null:
		return 0
	var count := 0
	for parts: Dictionary in [player.p1_parts, player.p2_parts]:
		if parts.is_empty() or not parts.has("meshes"):
			continue
		for mesh: MeshInstance3D in parts["meshes"]:
			if mesh != null and is_instance_valid(mesh) and mesh.visible and mesh.is_visible_in_tree():
				count += 1
	return count
