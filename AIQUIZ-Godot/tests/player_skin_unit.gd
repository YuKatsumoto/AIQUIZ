extends Node

## PlayerSkin（パーツごとの体の色）のデータ・保存・骨格への適用の単体テスト。
## Run: Godot --headless --path . --script res://tests/player_skin_bootstrap.gd -- --fresh-profile

const PlayerControllerRes = preload("res://scripts/world/player_controller.gd")
const ToonPresets = preload("res://scripts/cosmetics/character_toon_presets.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_test_defaults_match_legacy_colors()
	_test_canonicalize()
	_test_compact_round_trip()
	_test_editing()
	_test_skeleton_classification()
	_test_explosion_and_ghost_keep_skin()
	_test_store_round_trip()
	_test_net_cosmetics()
	_test_front_view_layout()
	_test_head_lock()
	print("PLAYER_SKIN_UNIT ", JSON.stringify({"passed": _failures.is_empty(), "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _close(a: Color, b: Color, tolerance: float = 1.0 / 255.0) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance


func _test_defaults_match_legacy_colors() -> void:
	var legacy := {
		1: {"head": PlayerController.P1_HEAD, "body": PlayerController.P1_BODY, "limb": PlayerController.P1_LIMB},
		2: {"head": PlayerController.P2_HEAD, "body": PlayerController.P2_BODY, "limb": PlayerController.P2_LIMB},
	}
	for slot: int in [1, 2]:
		var skin := PlayerSkin.default_skin(slot)
		for part_id: StringName in PlayerSkin.PART_IDS:
			var kind := "head" if part_id == &"head" else ("body" if part_id in [&"chest", &"waist"] else "limb")
			_check(_close(skin[part_id], legacy[slot][kind], 0.0001), "default %d %s color differs" % [slot, part_id])
		_check(PlayerSkin.is_slot_default({}, slot), "{} should be slot default")
		_check(PlayerSkin.is_slot_default(skin, slot), "default skin should be slot default")
		_check(PlayerSkin.to_code(skin, slot) == "", "default skin code should be empty")
	_check(not PlayerSkin.is_slot_default(PlayerSkin.default_skin(2), 1), "P2 colors are not P1 default")


func _test_canonicalize() -> void:
	var skin := PlayerSkin.canonicalize({"head": "#ff0000", "bogus": Color.RED, &"l_arm": 12, "legs": Color.BLUE}, 1)
	_check(skin.size() == PlayerSkin.PART_IDS.size(), "canonical skin must have every part")
	_check(not skin.has("bogus") and not skin.has(&"legs"), "unknown parts are dropped")
	_check(_close(skin[&"head"], Color(1, 0, 0)), "html color accepted")
	_check(_close(skin[&"l_arm"], PlayerController.P1_LIMB), "invalid color keeps default")
	_check(_close(skin[&"l_leg"], Color.BLUE) and _close(skin[&"r_leg"], Color.BLUE), "old both-sides key fills each side")


func _random_skin(rng: RandomNumberGenerator) -> Dictionary:
	var skin := {}
	for part_id: StringName in PlayerSkin.PART_IDS:
		skin[part_id] = Color8(rng.randi() % 256, rng.randi() % 256, rng.randi() % 256)
	return skin


func _test_compact_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	for index: int in range(200):
		var skin := _random_skin(rng)
		var code := PlayerSkin.encode_compact(skin)
		if code.length() != PlayerSkin.COMPACT_HEX_LENGTH or code != code.to_lower():
			_failures.append("code shape #%d" % index)
			continue
		var back := PlayerSkin.decode_compact(code)
		if PlayerSkin.encode_compact(back) != code:
			_failures.append("round trip #%d" % index)
	var valid := "03" + "ab".repeat(33)
	_check(not PlayerSkin.decode_compact(valid).is_empty(), "valid code rejected")
	for bad: String in ["", "00", valid.to_upper(), valid.substr(0, valid.length() - 2), valid + "00", "zz" + valid.substr(2), "02" + valid.substr(2), "03" + "ab".repeat(21)]:
		_check(PlayerSkin.decode_compact(bad).is_empty(), "invalid code accepted: %s" % bad.left(12))
	# 左右をまとめていた前の形式（version 2）も読める：うで・手・あし・くつは左右とも同じ色になる
	var old_code := "02" + "010203" + "040506" + "070809" + "0a0b0c" + "0d0e0f" + "101112" + "131415"
	var old_skin := PlayerSkin.decode_compact(old_code)
	_check(old_skin.size() == PlayerSkin.PART_IDS.size(), "legacy code has every part")
	_check(old_skin.get(&"l_arm") == Color8(10, 11, 12) and old_skin.get(&"r_arm") == Color8(10, 11, 12), "legacy arms split")
	_check(old_skin.get(&"r_foot") == Color8(19, 20, 21) and old_skin.get(&"waist") == Color8(7, 8, 9), "legacy order")
	_check(PlayerSkin.decode_compact("01" + old_code.substr(2)).is_empty(), "legacy wrong version rejected")
	_check(PlayerSkin.from_code(null).is_empty() and PlayerSkin.from_code(5).is_empty(), "from_code non-string")


func _test_editing() -> void:
	var skin := PlayerSkin.default_skin(1)
	var red := PlayerSkin.set_color(skin, PlayerSkin.ALL, Color.RED)
	for part_id: StringName in PlayerSkin.PART_IDS:
		_check(_close(red[part_id], Color.RED), "all color %s" % part_id)
	var chest_blue := PlayerSkin.set_color(red, &"chest", Color.BLUE)
	_check(_close(chest_blue[&"chest"], Color.BLUE) and _close(chest_blue[&"head"], Color.RED), "single part edit does not leak")
	_check(_close(PlayerSkin.target_color(chest_blue, PlayerSkin.ALL), Color.BLUE), "whole body shows the chest color")
	var reset := PlayerSkin.reset_target(chest_blue, &"chest", 1)
	_check(_close(reset[&"chest"], PlayerController.P1_BODY, 0.0001) and _close(reset[&"head"], Color.RED), "reset one part")
	_check(PlayerSkin.is_slot_default(PlayerSkin.reset_target(chest_blue, PlayerSkin.ALL, 1), 1), "reset all")
	_check(PlayerSkin.looks_similar(PlayerSkin.default_skin(1), PlayerSkin.default_skin(1)), "same skins are similar")
	_check(not PlayerSkin.looks_similar(PlayerSkin.default_skin(1), PlayerSkin.default_skin(2)), "standard P1/P2 are distinguishable")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for index: int in range(20):
		var random := PlayerSkin.random_skin(rng, PlayerSkin.default_skin(2))
		_check(random.size() == PlayerSkin.PART_IDS.size(), "random skin #%d complete" % index)
		_check(random[&"l_leg"] == random[&"r_leg"], "random skin #%d keeps sides matched" % index)
	for preset_id: StringName in PlayerSkin.PRESET_IDS:
		var preset := PlayerSkin.preset_skin(preset_id, 1)
		_check(preset.size() == PlayerSkin.PART_IDS.size(), "preset %s complete" % preset_id)
	var left_only := PlayerSkin.set_color(skin, &"l_arm", Color.GREEN)
	_check(_close(left_only[&"l_arm"], Color.GREEN) and not _close(left_only[&"r_arm"], Color.GREEN), "left arm alone")


func _test_skeleton_classification() -> void:
	var holder := Node3D.new()
	var controller: Node3D = PlayerControllerRes.new()
	var parts: Dictionary = controller._build_player_skeleton(true, holder)
	controller.free()
	_check(PlayerSkinRig.is_prepared(parts), "skeleton prepared")
	var groups: Dictionary = (parts.pelvis as Node3D).get_meta(PlayerSkinRig.GROUPS_META)
	var expected := {
		&"head": 1, &"chest": 1, &"waist": 1, &"l_arm": 2, &"r_arm": 2, &"l_hand": 15, &"r_hand": 15,
		&"l_leg": 2, &"r_leg": 2, &"l_foot": 2, &"r_foot": 2,
	}
	for part_id: StringName in expected:
		var total := 0
		for side: Array in groups.get(part_id, []):
			total += side.size()
		_check(total == int(expected[part_id]), "%s mesh count %d" % [part_id, total])
	# つま先は +Z 向き。キャラ自身の左は +X 側にある
	var pelvis := parts.pelvis as Node3D
	for part_id: StringName in [&"l_arm", &"l_hand", &"l_leg", &"l_foot"]:
		for side: Array in groups[part_id]:
			for mesh: MeshInstance3D in side:
				_check(PlayerSkinRig.rest_transform(mesh, pelvis).origin.x > 0.0, "%s is on the character's left (+X)" % part_id)
	var toe := PlayerSkinRig.rest_transform(parts.l_toe_mesh, pelvis).origin
	_check(toe.z > 0.0, "toes point to +Z")
	for mesh: MeshInstance3D in parts.meshes:
		_check(mesh.material_override is StandardMaterial3D, "mesh %s uses a standard material" % mesh.name)
	var head_material := (parts.head as MeshInstance3D).material_override as StandardMaterial3D
	_check(_close(head_material.albedo_color, PlayerController.P1_HEAD, 0.0001), "head starts with the slot color")
	_check(is_equal_approx(head_material.roughness, 0.7) and is_equal_approx(head_material.metallic, 0.1), "same surface as before")
	var skin := PlayerSkin.set_color(PlayerSkin.default_skin(1), &"chest", Color.GREEN)
	PlayerSkinRig.apply(parts, skin, 1)
	var chest_material := (parts.upper_torso as MeshInstance3D).material_override as StandardMaterial3D
	_check(_close(chest_material.albedo_color, Color.GREEN), "chest material updated")
	_check(_close(ToonPresets.get_base_color(parts.upper_torso), Color.GREEN), "base color meta follows skin")
	var arm_material := (parts.r_upp_arm as MeshInstance3D).material_override as StandardMaterial3D
	PlayerSkinRig.apply(parts, PlayerSkin.set_color(skin, &"l_arm", Color.YELLOW), 1)
	_check(_close(arm_material.albedo_color, Color.YELLOW), "left arm paints the +X arm")
	_check(not _close(((parts.l_upp_arm as MeshInstance3D).material_override as StandardMaterial3D).albedo_color, Color.YELLOW), "right arm untouched")
	PlayerSkinRig.apply(parts, skin, 1)
	PlayerSkinRig.set_highlight_map(parts, {&"chest": 0.5})
	_check(chest_material.emission.r > 0.0 and head_material.emission == Color.BLACK, "only the chest glows")
	# 手は EmoteBlockmanPreview でも塗られる（parts.meshes に入っていない）
	var preview_holder := Node3D.new()
	var preview_parts := EmoteBlockmanPreview.build_player_skeleton(false, preview_holder, HatData.HAT_NONE, 0, skin)
	var palm: MeshInstance3D = null
	for child: Node in (preview_parts.l_hand as Node).find_children("*", "MeshInstance3D", true, false):
		palm = child
		break
	_check(palm != null and _close((palm.material_override as StandardMaterial3D).albedo_color, PlayerController.P1_LIMB), "preview hands use the skin")
	_check(_close(((preview_parts.upper_torso as MeshInstance3D).material_override as StandardMaterial3D).albedo_color, Color.GREEN), "preview gets skin")
	preview_holder.free()
	holder.free()


func _test_explosion_and_ghost_keep_skin() -> void:
	var controller: Node3D = PlayerControllerRes.new()
	var holder := Node3D.new()
	var parts: Dictionary = controller._build_player_skeleton(true, holder)
	controller.p1_parts = parts
	controller.set_skin(1, PlayerSkin.set_color(PlayerSkin.default_skin(1), &"head", Color.MAGENTA))
	controller.set_toon_preset(1, 0)
	var head: MeshInstance3D = parts.head
	_check(_close((head.material_override as StandardMaterial3D).albedo_color, Color.MAGENTA), "set_toon_preset keeps the skin")
	var piece: RigidBody3D = controller._create_explosion_piece(head, true)
	var visual: MeshInstance3D = null
	for child: Node in piece.get_children():
		if child is MeshInstance3D:
			visual = child
	_check(visual != null and visual.material_override == head.material_override, "debris shares the colored material")
	piece.free()
	controller._apply_ghost_material(head)
	var ghost := head.material_override as StandardMaterial3D
	_check(ghost != null and _close(ghost.albedo_color, Color.MAGENTA), "ghost keeps the part color")
	holder.free()
	controller.free()


func _test_store_round_trip() -> void:
	var saved_path := PlayerSkinStore.path
	PlayerSkinStore.path = "user://player_skins_unit_test.json"
	PlayerSkinStore.reset_memory()
	var skin := PlayerSkin.preset_skin(&"panda", 1)
	PlayerSkinStore.set_skin(1, skin)
	PlayerSkinStore.set_hat(2, HatData.HAT_CROWN)
	PlayerSkinStore.set_hat(1, HatData.HAT_CAP)
	_check(PlayerSkinStore.get_hat(2) == HatData.HAT_NONE, "retired hat is rejected")
	if not PlayerSkinStore.is_fresh_profile():
		PlayerSkinStore.flush()
		PlayerSkinStore.load_from_disk()
		_check(PlayerSkinStore.get_skin_code(1) == PlayerSkin.to_code(skin, 1), "store round trip skin")
		_check(PlayerSkinStore.get_hat(1) == HatData.HAT_CAP, "store round trip hat")
		var file := FileAccess.open(PlayerSkinStore.path, FileAccess.WRITE)
		file.store_string("{not json")
		file.close()
		PlayerSkinStore.load_from_disk()
		_check(PlayerSkinStore.get_skin(1).is_empty(), "broken file falls back to default")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerSkinStore.path))
	var gs := QuizGameState.new(null)
	PlayerSkinStore.reset_memory()
	PlayerSkinStore.set_skin(2, skin)
	PlayerSkinStore.apply_to_state(gs)
	_check(gs.p2_skin_code == PlayerSkin.to_code(PlayerSkinStore.normalized(2, skin), 2) and gs.p1_skin_code == "", "apply_to_state")
	PlayerSkinStore.reset_memory()
	PlayerSkinStore.path = saved_path


func _test_net_cosmetics() -> void:
	var gs := QuizGameState.new(null)
	var mine := PlayerSkin.preset_skin(&"forest", 1)
	gs.set_player_skin(1, mine)
	var theirs := PlayerSkin.preset_skin(&"panda", 2)
	gs.apply_net_cosmetics({2: {"hat": 3, "skin": PlayerSkin.to_code(theirs, 2)}, 1: {"hat": 1, "skin": "zz"}})
	_check(gs.p2_skin_code == PlayerSkin.to_code(theirs, 2), "opponent skin applied")
	_check(gs.p1_skin_code == "", "invalid code becomes slot default")
	gs.reset_net_view()
	_check(gs.p1_skin_code == PlayerSkin.to_code(mine, 1) and gs.p2_skin_code == "", "net view restores menu skins")


func _test_front_view_layout() -> void:
	var layout := PlayerSkinRig.front_view_layout()
	var regions: Array = layout.regions
	_check(regions.size() == 11, "front view regions %d" % regions.size())
	var rects := {}
	for region: Dictionary in regions:
		rects[region.part] = region.rect
	# 正面図：キャラの左うでは画面の右側
	_check((rects[&"l_arm"] as Rect2).position.x > (rects[&"r_arm"] as Rect2).position.x, "left arm drawn on the right in the front view")
	var body: Rect2 = layout.body
	_check(body.size.y > 2.0 and body.size.x > 1.0, "body rect size %s" % body.size)
	for region: Dictionary in regions:
		_check(body.grow(0.001).encloses(region.rect), "region inside body %s" % region.part)


func _test_head_lock() -> void:
	var magenta_head := PlayerSkin.set_color(PlayerSkin.default_skin(2), &"head", Color.MAGENTA)
	magenta_head = PlayerSkin.set_color(magenta_head, &"chest", Color.GREEN)
	# プレイヤー2 は保存の時点で あたまが標準色になる（本物の保存ファイルには書かない）
	var saved_path := PlayerSkinStore.path
	PlayerSkinStore.path = "user://player_skins_unit_test.json"
	PlayerSkinStore.suspended = true
	PlayerSkinStore.reset_memory()
	PlayerSkinStore.set_skin(2, magenta_head)
	var stored := PlayerSkin.resolve(PlayerSkinStore.get_skin(2), 2)
	_check(_close(stored[&"head"], PlayerController.P2_HEAD) and _close(stored[&"chest"], Color.GREEN), "P2 head stays standard in the store")
	PlayerSkinStore.set_skin(1, PlayerSkin.set_color(PlayerSkin.default_skin(1), &"head", Color.MAGENTA))
	_check(_close(PlayerSkin.resolve(PlayerSkinStore.get_skin(1), 1)[&"head"], Color.MAGENTA), "P1 head can change")
	PlayerSkinStore.reset_memory()
	PlayerSkinStore.suspended = false
	PlayerSkinStore.path = saved_path
	# 体の色はオンライン対戦（とリプレイ）だけ。ソロ・ローカル2人対戦は標準色
	var gs := QuizGameState.new(null)
	gs.set_player_skin(1, PlayerSkin.set_color(PlayerSkin.set_color(PlayerSkin.default_skin(1), &"head", Color.MAGENTA), &"chest", Color.GREEN))
	for players: int in [1, 2]:
		gs.num_players = players
		_check(PlayerSkin.is_slot_default(gs.get_display_skin(1), 1), "offline %dP shows the slot default" % players)
		_check(gs.get_display_skin_key(1) == "", "offline %dP display key is default" % players)
	gs.net_online = true
	var online := PlayerSkin.resolve(gs.get_display_skin(1), 1)
	_check(_close(online[&"head"], Color.MAGENTA) and _close(online[&"chest"], Color.GREEN), "online shows the custom colors")
	_check(gs.get_display_skin_key(1) == gs.p1_skin_code, "online display key follows the skin")
	gs.net_online = false
	gs.is_replay = true
	_check(_close(PlayerSkin.resolve(gs.get_display_skin(1), 1)[&"head"], Color.MAGENTA), "replay shows the recorded colors")
	gs.is_replay = false
