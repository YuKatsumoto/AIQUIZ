extends Node

## After Effects 版の VS カットイン（tools/online_cutin_ae/）で使うキャラの画像を撮る。
## ゲームのカットインと同じ CutinActors（scripts/ui/online/cutin/cutin_actor.gd）で、
## CUTIN_POSES の 4 種類を、オレンジ（スロット 1）とブルー（スロット 2）、左向き・右向きで撮り、背景が透明な PNG にする。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/online_cutin_ae/capture_cutin_chars.gd [out=res://artifacts/online_cutin_ae/chars] [scale=2] [wide=1.3]
## ファイル名：slot{1|2}_pose{0..3}_{L|R}.png
##   L＝左のパネルに置く絵（体は右＝画面の真ん中を向く）、R＝右のパネルに置く絵（左を向く）。
## 高さはゲームの SubViewport（900×1000）の scale 倍（既定 2 倍＝2000 px）。幅は wide 倍だけ広げる（既定 1.3 倍＝2340 px）。
## Godot のカメラは縦の画角を保つので、幅を広げても体の大きさと位置はゲームと同じで、横に伸ばした腕が切れなくなるだけ。
## 帽子はかぶせない（HAT_NONE）。肌はスロットの標準色。

const OUT_DEFAULT := "res://artifacts/online_cutin_ae/chars"
const SAMPLE_NAMES := ["ご機嫌な鉛筆", "テストの あいて"]

var out_dir := OUT_DEFAULT
var scale_factor := 2.0
var wide := 1.3


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.trim_prefix("out=")
		elif arg.begins_with("scale="):
			scale_factor = maxf(0.5, float(arg.trim_prefix("scale=")))
		elif arg.begins_with("wide="):
			wide = clampf(float(arg.trim_prefix("wide=")), 1.0, 2.0)
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var actors := CutinActors.new()
	actors.name = "CaptureActors"
	add_child(actors)
	await get_tree().process_frame
	var size := Vector2i(Vector2(CutinActors.VIEW_SIZE) * scale_factor * Vector2(wide, 1.0))
	actors.view_left.size = size
	actors.view_right.size = size
	var manifest := {
		"view_size": [size.x, size.y],
		"game_view_size": [CutinActors.VIEW_SIZE.x, CutinActors.VIEW_SIZE.y],
		"scale": scale_factor,
		"wide": wide,
		"poses": [],
		"files": [],
		"sample_pose_index": {},
	}
	for pose_i in range(OnlineStagingTimeline.CUTIN_POSES.size()):
		manifest["poses"].append(OnlineStagingTimeline.CUTIN_POSES[pose_i])
	for n: String in SAMPLE_NAMES:
		manifest["sample_pose_index"][n] = OnlineStagingTimeline.cutin_pose_index(n)
	var ok := true
	for my_slot: int in [1, 2]:
		for pose_i in range(OnlineStagingTimeline.CUTIN_POSES.size()):
			# 左＝自分（my_slot）、右＝相手（3 - my_slot）。同じポーズを両方に当てる。
			actors.prepare(my_slot, HatData.HAT_NONE, HatData.HAT_NONE, pose_i, pose_i)
			# 1 回目の描画でシェーダーがそろわないことがあるので、もう 1 回描いてから読む
			for _i in range(3):
				await get_tree().process_frame
			actors.view_left.render_target_update_mode = SubViewport.UPDATE_ONCE
			actors.view_right.render_target_update_mode = SubViewport.UPDATE_ONCE
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var left_img := actors.left_texture().get_image()
			var right_img := actors.right_texture().get_image()
			var other_slot: int = 3 - my_slot
			var left_path := "%s/slot%d_pose%d_L.png" % [out_dir, my_slot, pose_i]
			var right_path := "%s/slot%d_pose%d_R.png" % [out_dir, other_slot, pose_i]
			for pair in [[left_img, left_path], [right_img, right_path]]:
				var img: Image = pair[0]
				var path: String = pair[1]
				if img == null or img.is_empty():
					push_error("CAPTURE empty image for %s" % path)
					ok = false
					continue
				img.convert(Image.FORMAT_RGBA8)
				var err := img.save_png(path)
				if err != OK:
					push_error("CAPTURE save failed %s (%d)" % [path, err])
					ok = false
				else:
					manifest["files"].append(path.get_file())
					print("CAPTURE ", path, " ", img.get_size())
	var f := FileAccess.open("%s/manifest.json" % out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "\t"))
		f.close()
	print("CAPTURE_DONE ok=", ok, " files=", manifest["files"].size())
	get_tree().quit(0 if ok else 1)
