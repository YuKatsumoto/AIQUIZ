extends SceneTree

## メインメニューのタイトルの形と場所を tools/title_logo_ae/layout.json に書き出す（build_title_logo.jsx が読む）。
## 大きさは main_menu._apply_title_logo と同じ（高さ TITLE_LOGO_HEIGHT、横はロゴの画像の縦横比）。
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/title_logo_ae/export_layout.gd

const OUT := "res://tools/title_logo_ae/layout.json"
const LOGO_IMAGE := "res://assets/ui/branding/aiquiz_logo.png"
const LOGO_HEIGHT := 56.0


func _init() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(LOGO_IMAGE))
	var logo_size := Vector2(LOGO_HEIGHT * image.get_width() / image.get_height(), LOGO_HEIGHT)
	var layout := TitleLogoIntro.build_layout(logo_size)
	if layout.is_empty():
		push_error("title logo layout failed")
		quit(1)
		return
	var pieces: Array = []
	for record: Dictionary in layout.pieces:
		var outlines: Array = []
		for outline: PackedVector2Array in record.outlines:
			var points: Array = []
			for p: Vector2 in outline:
				points.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001)])
			outlines.append(points)
		pieces.append({"key": record.key, "slot": _v(record.slot), "size": _v(record.size), "outlines": outlines})
	var bar := TitleLogoIntro.DEFAULT_BAR_RECT
	var belt: Rect2 = layout.belt_rect
	var data := {
		"logo_size": _v(logo_size), "logo_center": _v(layout.logo_center),
		"landing_x": layout.landing_x, "baseline": layout.baseline, "order": layout.order,
		"bar_rect": [bar.position.x, bar.position.y, bar.size.x, bar.size.y],
		"belt_rect": [belt.position.x, belt.position.y, belt.size.x, belt.size.y],
		"belt": {
			"height": TitleLogoIntro.BELT_HEIGHT, "rib_spacing": TitleLogoIntro.RIB_SPACING,
			"bar_color": _c(TitleLogoIntro.BAR_COLOR), "belt_color": _c(TitleLogoIntro.BELT_COLOR),
			"bottom_color": _c(TitleLogoIntro.BELT_BOTTOM_COLOR), "rib_color": _c(TitleLogoIntro.RIB_COLOR),
			"roller_color": _c(TitleLogoIntro.ROLLER_COLOR),
		},
		"shadow": {"offset": _v(TitleLogoIntro.SHADOW_OFFSET), "alpha": TitleLogoIntro.SHADOW_ALPHA},
		"pieces": pieces,
	}
	if layout.has("bridge"):
		var bridge: Dictionary = layout.bridge
		data.bridge = {"key": TitleLogoIntro.BRIDGE_KEY, "axis": _v(bridge.axis), "min": bridge.min, "max": bridge.max}
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("wrote ", OUT, " pieces=", pieces.size(), " logo=", logo_size)
	quit()


static func _v(v: Vector2) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)]


static func _c(c: Color) -> Array:
	return [c.r, c.g, c.b]
