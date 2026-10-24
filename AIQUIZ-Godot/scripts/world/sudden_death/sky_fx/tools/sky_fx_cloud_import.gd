extends SceneTree

## 体積雲の素（assets/sudden_death/sky_fx/source/clouds/ の .bin、bake_cloud_volumes.py が焼く）を
## Godot の 3D テクスチャ（ImageTexture3D）にして保存する。焼き直したら 1 回実行する。
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 320x200 --script res://scripts/world/sudden_death/sky_fx/tools/sky_fx_cloud_import.gd
## （--headless では描く装置がなく、3D テクスチャの中身が保存されないので、画面ありで動かす）
## 書くもの：assets/sudden_death/sky_fx/sky_fx_cloud_shapes.res（R8、幅＝x・高さ＝z・奥行き＝形ごとに y を積む）、
##          sky_fx_cloud_detail.res（RG8、くり返すノイズ 64³）。

const SRC := "res://assets/sudden_death/sky_fx/source/clouds/"
const OUT := "res://assets/sudden_death/sky_fx/"


func _initialize() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC + "cloud_volumes.json"))
	var size: Array = meta.shape_size
	var nx := int(size[0])
	var ny := int(size[1])
	var nz := int(size[2])
	var pad := int(meta.pad)
	var count := (meta.shapes as Array).size()
	var data := FileAccess.get_file_as_bytes(SRC + "cloud_shapes.bin")
	var slices := count * (ny + pad * 2)
	if data.size() != nx * nz * slices:
		push_error("cloud_shapes.bin の大きさがちがう：%d（期待 %d）" % [data.size(), nx * nz * slices])
		quit(1)
		return
	var images: Array[Image] = []
	for s in range(slices):
		images.append(Image.create_from_data(nx, nz, false, Image.FORMAT_R8, data.slice(s * nx * nz, (s + 1) * nx * nz)))
	var shapes := ImageTexture3D.new()
	var err := shapes.create(Image.FORMAT_R8, nx, nz, slices, false, images)
	if err != OK:
		push_error("形の 3D テクスチャを作れない：%d" % err)
		quit(1)
		return
	ResourceSaver.save(shapes, OUT + "sky_fx_cloud_shapes.res")
	var dn := int(meta.detail_size)
	var detail_data := FileAccess.get_file_as_bytes(SRC + "cloud_detail.bin")
	var dimages: Array[Image] = []
	for s in range(dn):
		dimages.append(Image.create_from_data(dn, dn, false, Image.FORMAT_RG8, detail_data.slice(s * dn * dn * 2, (s + 1) * dn * dn * 2)))
	var detail := ImageTexture3D.new()
	err = detail.create(Image.FORMAT_RG8, dn, dn, dn, false, dimages)
	if err != OK:
		push_error("ノイズの 3D テクスチャを作れない：%d" % err)
		quit(1)
		return
	ResourceSaver.save(detail, OUT + "sky_fx_cloud_detail.res")
	print("[SkyFxCloudImport] shapes %dx%dx%d, detail %d^3" % [nx, nz, slices, dn])
	quit(0)
