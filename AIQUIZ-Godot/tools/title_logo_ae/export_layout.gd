extends SceneTree

## タイトルのロゴの形と場所を tools/title_logo_ae/layout.json に書き出す（build_title_logo.jsx が読む）。
## 大きさは main_menu の TITLE_LOGO_HEIGHT（高さ。横はロゴの画像の縦横比）。部品（文字・扉のブロック・破片）の形・色は
## TitleLogoIntro.build_layout() と同じ。
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/title_logo_ae/export_layout.gd

const OUT := "res://tools/title_logo_ae/layout.json"
const LOGO_IMAGE := "res://assets/ui/branding/testopia_logo.png"
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
		var colors: Array = []
		for c: Color in record.colors:
			colors.append(_c(c))
		var depth_colors: Array = record.depth_colors
		pieces.append({"key": record.key, "slot": _v(record.slot), "size": _v(record.size), "outlines": outlines, "colors": colors,
			"flat": record.flat, "depth": record.depth, "outline": record.outline,
			"depth_color": _c(depth_colors[0]), "depth_edge_color": _c(depth_colors[1])})
	var door: Dictionary = layout.door
	var door_rect: Rect2 = door.rect
	var bar := TitleLogoIntro.DEFAULT_BAR_RECT
	var belt: Rect2 = layout.belt_rect
	var data := {
		"logo_size": _v(logo_size), "logo_center": _v(layout.logo_center),
		"landing_right": layout.landing_right, "baseline": layout.baseline, "order": layout.order,
		"bar_rect": [bar.position.x, bar.position.y, bar.size.x, bar.size.y],
		"belt_rect": [belt.position.x, belt.position.y, belt.size.x, belt.size.y],
		"belt": {
			"height": TitleLogoIntro.BELT_HEIGHT, "rib_spacing": TitleLogoIntro.RIB_SPACING,
			"bar_color": _c(TitleLogoIntro.BAR_COLOR), "belt_color": _c(TitleLogoIntro.BELT_COLOR),
			"bottom_color": _c(TitleLogoIntro.BELT_BOTTOM_COLOR), "roller_color": _c(TitleLogoIntro.ROLLER_COLOR),
			"side_color": _c(TitleLogoIntro.BELT_SIDE_COLOR),
			"top_depth": TitleLogoIntro.BELT_TOP_DEPTH, "skew": TitleLogoIntro.BELT_SKEW,
			"stand_margin": TitleLogoIntro.BELT_STAND_MARGIN,
			"top_color": _c(TitleLogoIntro.BELT_TOP_COLOR), "top_edge_color": _c(TitleLogoIntro.BELT_TOP_EDGE_COLOR),
			"slat_color": _c(TitleLogoIntro.BELT_SLAT_COLOR), "slat_light_color": _c(TitleLogoIntro.BELT_SLAT_LIGHT_COLOR),
			"frame_highlight_color": _c(TitleLogoIntro.FRAME_HIGHLIGHT_COLOR),
			"rivet_color": _c(TitleLogoIntro.RIVET_COLOR), "rivet_spacing": TitleLogoIntro.RIVET_SPACING,
		},
		"shadow": {"offset": _v(TitleLogoIntro.SHADOW_OFFSET), "alpha": 0.75},
		# 文字の紺の厚みと、まわりの濃い紺の縁（TitleLogoIntro と同じ値。AE でも同じ形に描く）
		"depth": {
			"offset": _v(TitleLogoIntro.DEPTH_OFFSET), "color": _c(TitleLogoIntro.DEPTH_COLOR),
			"edge_color": _c(TitleLogoIntro.DEPTH_EDGE_COLOR),
		},
		"outline": {"width": TitleLogoIntro.LETTER_OUTLINE_WIDTH, "color": _c(TitleLogoIntro.LETTER_OUTLINE_COLOR)},
		"contact_shadow": {"alpha": TitleLogoIntro.CONTACT_SHADOW_ALPHA, "fade": TitleLogoIntro.CONTACT_SHADOW_FADE},
		"pieces": pieces,
		# T（1つ目）と E を運ぶ扉のブロックと、爆散の破片（TitleLogoIntro._door_layout）
		"door": {
			"key": door.key, "letters": door.letters, "cols": door.cols, "rows": door.rows,
			"rect": [door_rect.position.x, door_rect.position.y, door_rect.size.x, door_rect.size.y],
			"shard_prefix": TitleLogoIntro.SHARD_KEY,
		},
	}
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	print("wrote ", OUT, " pieces=", pieces.size(), " logo=", logo_size)
	quit()


static func _v(v: Vector2) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)]


static func _c(c: Color) -> Array:
	return [c.r, c.g, c.b]
