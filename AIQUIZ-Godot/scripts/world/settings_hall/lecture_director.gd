extends Node

## 地下神殿の講義室の進行役（docs/lecture_hall_plan.md の第 3 段階）。LectureSet の子。
## 授業の台本（lessons/lesson_03.json）を上から順に流し、先生が黒板の前を歩いて、右手（IK）で文字の線を
## なぞって本当に書き（ChalkCanvas に線が積もる）、黒板消しで拭いて消す。生徒は先生の様子（cue）に合わせて
## 写す・見る・手を挙げる・居眠りする。ときどき小さな出来事（くしゃみ・チョーク投げ・転校生・参観など）を挟む。
## 体の動きは Blender のクリップ（plush_actor.gd）。位置・向き・手先・チョークの線・粉はここで動かす。
## 座標はすべてセット（LectureSet）のローカル。黒板の面の座標 uv（m）は u = 見る人の左端から右へ、v = 下端から上へ。

const PlushActorScript := preload("res://scripts/world/settings_hall/plush_actor.gd")
const GlyphBookScript := preload("res://scripts/world/settings_hall/glyph_book.gd")
const LessonBuilderScript := preload("res://scripts/world/settings_hall/lesson_builder.gd")
const LESSON_PATH := "res://scripts/world/settings_hall/lessons/lesson_03.json"

# ------------------------------------------------------------------ layout（lsb_board.py / lsb_lectern.py と同じ）
## 黒板の面（PRP_BoardSurface_F / _B）の左下の角。u は -X へ、v は +Y へ。教室側は -Z。
const BOARD_ORIGIN := {"F": Vector3(3.765, 0.655, 8.551), "B": Vector3(3.765, 2.355, 8.626)}
const BOARD_SIZE := Vector2(7.53, 1.71)
const BOARD_U := Vector3(-1.0, 0.0, 0.0)
const BOARD_V := Vector3(0.0, 1.0, 0.0)
const BOARD_IN := Vector3(0.0, 0.0, -1.0)
## 教卓の後ろ（生徒を向いて話す場所）。教卓は x 1.47〜2.53、z 5.96〜6.64。
const LECTERN_SPOT := Vector3(2.15, 0.0, 7.15)
const DRINK_SPOT := Vector3(1.62, 0.0, 7.0)
const CLOCK_POINT := Vector3(0.0, 5.02, 8.55)
const STOOL_SPOT := Vector3(-3.3, 0.0, 7.95)
const CLASS_YAW := 180.0

## チョーク受け（トレイ）の上面の高さと奥行きの中心（セットのローカル、lsb_board.py の TRAY_*）。
const TRAY_TOP := 0.556
const TRAY_Z := 8.455

# ------------------------------------------------------------------ writing
## 書く構え: 体を黒板に 45° 向け（右半身が黒板側）、右肩から手先まで約 0.6 m（手首まで 0.29 m + 手 0.3 m）。
const WRITE_YAW := 45.0
const SHOULDER_OFF := Vector3(-0.52, 0.0, 0.0)
const SHOULDER_Y := 0.82
const REACH_PLAN := 0.5
## 構えのとき、肩は書き始めの点より u で LEAD だけ右。画の u が肩の u から WINDOW の外なら横歩きで構え直す。
const LEAD := 0.06
## これより上（v、m）の画は背伸びで書く（T_WriteTiptoe は 6 cm 上がる）。
const TIPTOE_V := 0.56
const WINDOW := Vector2(-0.2, 0.34)
const PEN_SPEED := 0.8
const TRAVEL_SPEED := 1.6
const LIFT := 0.03
const CHALK_WIDTH := 0.0125
const ERASER_SIZE := Vector2(0.22, 0.1)
const ERASE_SPEED := 1.5
## 黒板消しの縦の往復の間隔（m）と、跡を付ける間隔（m、フレームの速さによらず同じ消え方にする）。
const ERASE_COLUMN := 0.16
const ERASE_STEP := 0.02
const ERASE_STRENGTH := 0.42
const ERASE_SIDE_SPEED := 0.65
const CHALK_COLORS := {
	"white": Color(0.93, 0.93, 0.89), "yellow": Color(0.96, 0.86, 0.42),
	"red": Color(0.94, 0.52, 0.55), "blue": Color(0.55, 0.74, 0.95),
}

const STUDENTS := ["student_notes", "student_hand", "student_doze"]
## 生徒の席（丸椅子の中心、lsb_props.py の STOOL_Z）と、照明が点く前に遊んでいる場所・動き。
const SEATS := {"student_notes": Vector3(-2.3, 0.0, 0.74), "student_hand": Vector3(0.0, 0.0, 0.74),
	"student_doze": Vector3(2.3, 0.0, 0.74)}
const PLAY := {
	"student_notes": {"at": Vector3(-1.05, 0.0, 2.75), "yaw": 70.0, "clip": "G_Chat"},
	"student_hand": {"at": Vector3(-0.2, 0.0, 2.95), "yaw": -110.0, "clip": "G_Chat"},
	"student_doze": {"at": Vector3(2.9, 0.0, 2.6), "yaw": 160.0, "clip": "G_Stretch"},
}
## 一日の流れ（項目 86〜92）: 開いた時刻と曜日で最初の場面が変わる。どの場面も終わると授業（補習）が始まる。
##   lesson（平日の昼）/ lunch（平日 12 時台: お弁当）/ after_school（平日 16〜20 時台: 掃除）/
##   night（21〜5 時台: 先生がひとり電気スタンドで採点）/ weekend（土日: 居眠りの生徒だけの補習）
## 環境変数 AIQUIZ_LECTURE_MODE で決め打ちできる（確認用）。
const NIGHT_FROM := 21
const NIGHT_TO := 6
const AFTER_SCHOOL_FROM := 16
## 掃除の道具と場所（lsb_room.py / lsb_board.py）
const SWEEP_ROUTE := [Vector3(-5.2, 0.0, 3.3), Vector3(3.6, 0.0, 3.3), Vector3(3.6, 0.0, -0.6), Vector3(-5.2, 0.0, -0.6)]
const CLEANER_SPOT := Vector3(-4.15, 0.0, 7.05)
const BUCKET_SPOT := Vector3(-5.6, 0.0, 0.25)
## 夜: 踏み台を教卓の脇へ運んで腰かける
const NIGHT_STOOL := Vector3(2.95, 0.0, 6.75)
## 日直が号令をかける場所（教室の前の脇、生徒のほうを向く）。
const DUTY_CALL := Vector3(3.6, 0.0, 3.1)
## 漫符の種類 -> lecture_fx.glb のオブジェクト。大きさは実物の約 2.6 倍（遠いカメラから読める大きさ）。
const EMOTES := {"!": "FX_Exclaim", "?": "FX_Question", "anger": "FX_Anger", "sweat": "FX_Sweat",
	"dots": "FX_Dots", "note": "FX_Note", "bulb": "FX_Bulb"}
const EMOTE_SCALE := 3.4
## 居眠り役の眠気（話を聞いている間は 1 秒に 1.6、ほかは 0.6 たまる）: うとうと → 突っ伏して眠る。
const DOZE_DRIFT := 45.0
const DOZE_SLEEP := 65.0
## ふだん隠しているキャラの出入り口と立ち位置。
const EXTRAS := {
	"parent": {"from": Vector3(-6.4, 0.0, -2.2), "spot": Vector3(-1.1, 0.0, -1.0), "yaw": 0.0},
	"transfer": {"from": Vector3(5.2, 0.0, 4.6), "spot": Vector3(1.0, 0.0, 7.0), "yaw": 180.0},
	"vice": {"from": Vector3(5.0, 0.0, 9.6), "spot": Vector3(4.55, 0.0, 7.0), "yaw": 215.0},
	"janitor": {"from": Vector3(-6.4, 0.0, -1.2), "spot": Vector3(-5.7, 0.0, 3.0), "yaw": 60.0},
	"duty": {"from": Vector3(5.2, 0.0, 2.2), "spot": Vector3(3.0, 0.0, 7.6), "yaw": 0.0},
}

var actors: Dictionary = {}        # key -> PlushActor
## 漫符の GLB（lecture_fx.glb、LectureSet が渡す。ないときは漫符を出さない）
var fx_scene: PackedScene = null
var boards: Dictionary = {}        # "F"/"B" -> ChalkCanvas
var lesson: Dictionary = {}
## 今回の講義（lesson_builder.gd の lecture()）: {kind, subject, grade, number, title, subtitle}
var lecture: Dictionary = {}
var _papers: Array = []             # 小テストの答案（机の上の紙）
var _art_queue: Array = []          # 黒板アートの段（特別な日）
var cycle_index := 0
var step_index := -1
var step: Dictionary = {}
var last_event := ""
var paused := false

var _set: Node3D = null
var _props: Node3D = null
var _glyphs = null
var _rng := RandomNumberGenerator.new()
var _t := 0.0                       # 今の段の経過秒
var _phase := ""
var _wait := 0.0
var _pens: Dictionary = {}          # actor key -> 書く・消す仕事
var _stroke_id := 1
var _students: Dictionary = {}      # key -> 生徒の頭の中
var _cue := "listen"
var _fx: Array = []                 # 飛ぶチョーク・粉
var _dust: CPUParticles3D = null
var _dust_texture: Texture2D = null
var _tray: Dictionary = {}          # "chalk_white" / "eraser" -> 小道具（トレイの上の MeshInstance3D）
var _held_color := ""
## 手に持っているチョークの元（チョーク受けの上の実物。箱から出したなら null）。置くとそこへ戻る。
var _held_from: Node3D = null
## チョーク受けの上のチョーク（色 -> 実物の列）。取ると隠れ、置くと手元のトレイの上に現れる（本数が実際に変わる）。
var _tray_chalks: Dictionary = {}
var _seated: Dictionary = {}        # 生徒 key -> 座っているか
var _gag_last := []
var _extras_visible: Dictionary = {}
var _pick: Dictionary = {}          # チョークを取る・持ち替える仕事
var _swap: Dictionary = {}          # 手を伸ばして持ち物を替える仕事
var _eraser_holder := ""            # 黒板消しを持っている actor key
var _cue_left := 0.0
var _done_once: Dictionary = {}
var _duty_rects: Array = []
## 上下スライド黒板: 面ごとの上下のずれ（m）。下の板 F を押し上げると、裏の B が下りてくる（項目 30）。
var _board_shift := {"F": 0.0, "B": 0.0}
var _panels: Dictionary = {}        # "F"/"B" -> パネルの Node3D
var _panel_home: Dictionary = {}    # "F"/"B" -> Vector3（元の位置）
var _high: Dictionary = {}          # 高いところに書く段の状態
## 照明が点く前の休み時間から始めたか（そのときは授業の最初のお辞儀を号令の礼で済ませる）。
var prelude := false
var day_mode := "lesson"
var _seats: Dictionary = {}
var _desk_groups: Dictionary = {}   # 机の番号 -> [{node, home: Transform3D}]
var _stool_node: Node3D = null      # 踏み台（PRP_StepStool）
var _stool_home := Transform3D.IDENTITY
var _stool_carry := ""              # 運んでいる actor key
var _lamp: OmniLight3D = null
var _held_tool: Dictionary = {}     # actor key -> Node3D（ほうき・雑巾）
var _tool_home: Dictionary = {}     # Node3D -> Transform3D
var _cycles_done := 0
## 日直が黒板消しクリーナーをかけているか（掃除の場面）。
var _cleaner_running := false
var _farewell := false
var _roll: Array = []
var _prelude_key := "prelude"
var _roll_key := ""
var _route: Array = []
var _slept := 0
## 設定画面にいる時間（長居すると先生が採点を始め、さらに居眠りする: 項目 101）。
var stay := 0.0
var _long_stay_stage := 0
## BGM の音量（0..1、AudioManager）。小さいと居眠りが深く、大きいとそわそわ起きる（項目 98）。
var _bgm := 0.5
var _audio_manager: Node = null
var _glint_texture: Texture2D = null
var _trainee := {}
## 最後に書いた字（書き直し・手でこするとき用）: {"origin": Vector2, "h": float, "rect": Rect2}
var _last_glyph: Dictionary = {}
var _clap_props: Array = []
var _emote_meshes: Dictionary = {}  # 種類 -> MeshInstance3D のひな形
var _emotes: Array = []             # [{node, actor, kind, t, secs}]
var _cue_after := "listen"


func setup(set_root: Node3D, props: Node3D, cast: Dictionary, canvases: Dictionary, seed_value := 0x1EC7) -> bool:
	_set = set_root
	_props = props
	boards = canvases
	_rng.seed = seed_value
	_glyphs = GlyphBookScript.new()
	if FileAccess.file_exists(LESSON_PATH):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LESSON_PATH))
		if data is Dictionary:
			lesson = data
	if lesson.get("cycles", []).is_empty() or not cast.has("lecturer") or not boards.has("F"):
		return false
	_choose_lecture()
	var k := 0
	for key: String in cast:
		var actor = PlushActorScript.new(key, cast[key], _set, seed_value + 17 * k)
		actors[key] = actor
		k += 1
	(actors.lecturer).setup_pointer()
	for key: String in actors:
		(actors[key]).setup_look()
		(actors[key]).setup_springs()
		if key != "trainee":
			(actors[key]).setup_hand_ik()
	for key: String in EXTRAS:
		if actors.has(key):
			_hide_extra(key)
	for key: String in STUDENTS:
		if actors.has(key):
			_students[key] = {"mode": "", "next": _rng.randf_range(2.0, 6.0), "drowsy": 0.0, "asleep": false,
				"until": 0.0}
			_seated[key] = true
	_find_tray()
	_make_dust()
	_load_emotes()
	_restore_boards()
	_make_tray_dust()
	_audio_manager = get_node_or_null("/root/AudioManager")
	if actors.has("trainee"):
		_trainee = {"next": _rng.randf_range(6.0, 12.0), "mode": "rest", "clip": ""}
		(actors.trainee).loop("P_Clipboard", 0.0)
	(actors.lecturer).root.position = LECTERN_SPOT
	(actors.lecturer).face(CLASS_YAW)
	(actors.lecturer).root.rotation.y = deg_to_rad(CLASS_YAW)
	(actors.lecturer).loop("T_Idle", 0.0)
	_set_cue("listen")
	day_mode = _pick_day_mode()
	_setup_seats()
	_find_room_props()
	if day_mode == "weekend":
		# 補習: 居眠りの生徒だけ
		for key in ["student_notes", "student_hand"]:
			if actors.has(key):
				(actors[key]).root.visible = false
				(actors[key]).root.process_mode = Node.PROCESS_MODE_DISABLED
				_students.erase(key)
	var mode_prelude: Array = lesson.get("prelude_" + day_mode, [])
	if not mode_prelude.is_empty():
		prelude = true
		cycle_index = -1
		_prelude_key = "prelude_" + day_mode
		_begin_mode_scene()
	else:
		prelude = _set.has_method("lit") and float(_set.call("lit")) < 0.5 and not (lesson.get("prelude", []) as Array).is_empty()
		if prelude:
			_begin_prelude()
	_next_step()
	return true


## 踏み台の今の場所（夜に教卓の脇へ運ぶことがある）。
func _stool_pos() -> Vector3:
	if _stool_node != null:
		var p := _stool_node.position
		return Vector3(p.x, 0.0, p.z)
	return STOOL_SPOT


## 今回の講義を決め、教科・テスト・卒業式なら台本の周を組み立てる。上の黒板（B）に題を書く。
func _choose_lecture() -> void:
	var visit: int = LessonBuilderScript.next_visit()
	lecture = LessonBuilderScript.lecture(visit)
	var builder = LessonBuilderScript.new(_glyphs)
	var cycles: Array = []
	match str(lecture.kind):
		"subject":
			cycles = builder.build_subject(str(lecture.subject), int(lecture.grade), 1000 + visit)
		"quiz":
			cycles = builder.build_test(false, 2000 + visit)
		"exam":
			cycles = builder.build_test(true, 3000 + visit)
		"graduation":
			cycles = builder.build_graduation()
	if not cycles.is_empty():
		lesson = lesson.duplicate()
		lesson.cycles = cycles
	elif str(lecture.kind) != "hazard":
		lecture = LessonBuilderScript.lecture(0)
	if boards.has("B"):
		# 黒板の下地と前回の板書が描き終わってから書く
		var b = boards.B
		var title := str(lecture.title)
		var subtitle := str(lecture.subtitle)
		_fx.append({"kind": "call", "t": 0.0, "secs": 0.25, "fn": func() -> void:
			b.stamp_text(title, Vector2(0.45, 1.05), 0.34, "yellow", 0.9)
			b.stamp_text(subtitle, Vector2(0.5, 0.45), 0.2, "white", 0.8)})


## 今日が特別な日なら、その名前（halloween / christmas / newyear / tanabata / valentine）。AIQUIZ_LECTURE_DATE（MM-DD）で決め打ち。
func _special_day() -> String:
	var forced := OS.get_environment("AIQUIZ_LECTURE_DATE")
	var month: int
	var day: int
	if forced != "" and forced.contains("-"):
		month = int(forced.get_slice("-", 0))
		day = int(forced.get_slice("-", 1))
	else:
		var d := Time.get_date_dict_from_system()
		month = int(d.month)
		day = int(d.day)
	if month == 10 and day >= 25:
		return "halloween"
	if month == 12 and day >= 18 and day <= 25:
		return "christmas"
	if month == 1 and day <= 7:
		return "newyear"
	if month == 7 and day <= 7:
		return "tanabata"
	if month == 2 and day >= 10 and day <= 14:
		return "valentine"
	return ""


## 黒板アートの段（黒板 F の右寄り u 4.2〜6.3）。more = 長居のときに描き足す飾り。
func _art_steps(kind: String, more: bool) -> Array:
	var steps: Array = []
	var c := Vector2(5.2, 0.3)
	match kind:
		"halloween":
			if not more:
				steps.append({"do": "poly", "strokes": [_ring(c, 0.19, 0.15, 36)], "color": "yellow"})
				steps.append({"do": "poly", "strokes": [[c + Vector2(-0.06, 0.14), c + Vector2(-0.07, 0.0), c + Vector2(-0.06, -0.14)],
					[c + Vector2(0.06, 0.14), c + Vector2(0.07, 0.0), c + Vector2(0.06, -0.14)],
					[c + Vector2(0.0, 0.15), c + Vector2(0.02, 0.21), c + Vector2(0.05, 0.22)]], "color": "yellow"})
				steps.append({"do": "poly", "strokes": [[c + Vector2(-0.1, 0.05), c + Vector2(-0.05, 0.09), c + Vector2(-0.03, 0.04), c + Vector2(-0.1, 0.05)],
					[c + Vector2(0.03, 0.04), c + Vector2(0.05, 0.09), c + Vector2(0.1, 0.05), c + Vector2(0.03, 0.04)],
					[c + Vector2(-0.11, -0.05), c + Vector2(-0.07, -0.09), c + Vector2(-0.03, -0.05), c + Vector2(0.01, -0.09), c + Vector2(0.05, -0.05), c + Vector2(0.09, -0.09), c + Vector2(0.11, -0.05)]], "color": "white"})
				steps.append({"do": "write", "text": "Happy Halloween", "at": [4.35, 0.03], "h": 0.11, "color": "white"})
			else:
				for k in range(2):
					var b := Vector2(4.55 + k * 1.25, 0.5 - k * 0.04)
					steps.append({"do": "poly", "strokes": [[b + Vector2(-0.12, 0.0), b + Vector2(-0.08, 0.04), b + Vector2(-0.04, 0.0), b,
						b + Vector2(0.04, 0.0), b + Vector2(0.08, 0.04), b + Vector2(0.12, 0.0), b + Vector2(0.06, -0.03), b, b + Vector2(-0.06, -0.03), b + Vector2(-0.12, 0.0)]], "color": "white"})
		"christmas":
			if not more:
				var tree: Array = []
				for k in range(3):
					var top := c + Vector2(0.0, 0.27 - k * 0.09)
					tree.append([top + Vector2(-0.12 - 0.05 * k, -0.12), top, top + Vector2(0.12 + 0.05 * k, -0.12), top + Vector2(-0.12 - 0.05 * k, -0.12)])
				tree.append([c + Vector2(-0.03, -0.12), c + Vector2(-0.03, -0.2), c + Vector2(0.03, -0.2), c + Vector2(0.03, -0.12)])
				steps.append({"do": "poly", "strokes": tree, "color": "white"})
				steps.append({"do": "write", "text": "☆", "at": [c.x - 0.06, c.y + 0.25], "h": 0.12, "color": "yellow"})
				steps.append({"do": "write", "text": "Merry Christmas", "at": [4.3, 0.03], "h": 0.11, "color": "red"})
			else:
				for k in range(5):
					var o := c + Vector2(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.08, 0.15))
					steps.append({"do": "circle", "at": [o.x, o.y], "r": 0.018, "color": ["red", "blue", "yellow"][k % 3]})
		"newyear":
			if not more:
				var sun := PackedVector2Array()
				for i in range(19):
					var a := PI * float(i) / 18.0
					sun.append(c + Vector2(cos(a), sin(a)) * 0.16 + Vector2(0.0, -0.18))
				steps.append({"do": "poly", "strokes": [sun, [c + Vector2(-0.3, -0.18), c + Vector2(0.3, -0.18)]], "color": "red"})
				steps.append({"do": "poly", "strokes": [[c + Vector2(-0.32, -0.12), c + Vector2(-0.1, 0.18), c + Vector2(0.1, 0.18), c + Vector2(0.32, -0.12)],
					[c + Vector2(-0.1, 0.18), c + Vector2(-0.06, 0.12), c + Vector2(-0.02, 0.16), c + Vector2(0.02, 0.11), c + Vector2(0.06, 0.16), c + Vector2(0.1, 0.18)]], "color": "white"})
				steps.append({"do": "write", "text": "謹賀新年", "at": [4.55, 0.03], "h": 0.14, "color": "yellow"})
			else:
				for k in range(8):
					var a := PI * float(k + 0.5) / 8.0
					var o := c + Vector2(0.0, -0.18)
					steps.append({"do": "line", "from": [o.x + cos(a) * 0.19, o.y + sin(a) * 0.19], "to": [o.x + cos(a) * 0.27, o.y + sin(a) * 0.27], "color": "red"})
		"tanabata":
			if not more:
				steps.append({"do": "poly", "strokes": [[c + Vector2(-0.2, -0.27), c + Vector2(-0.15, 0.28)],
					[c + Vector2(-0.17, 0.0), c + Vector2(-0.02, 0.06)], [c + Vector2(-0.18, 0.12), c + Vector2(0.0, 0.2)],
					[c + Vector2(-0.16, -0.12), c + Vector2(0.02, -0.08)]], "color": "white"})
				steps.append({"do": "write", "text": "七夕", "at": [5.45, 0.05], "h": 0.16, "color": "yellow"})
			else:
				for k in range(4):
					var t := c + Vector2(-0.05 + 0.06 * k, 0.12 - 0.07 * k)
					steps.append({"do": "poly", "strokes": [[t, t + Vector2(0.0, -0.09), t + Vector2(0.035, -0.09), t + Vector2(0.035, 0.0), t]], "color": ["red", "blue", "yellow", "white"][k]})
					steps.append({"do": "write", "text": "☆", "at": [c.x + 0.35 + 0.18 * k, c.y + 0.12 * ((k % 2) * 2 - 1)], "h": 0.08, "color": "yellow"})
		"valentine":
			if not more:
				var heart := PackedVector2Array()
				for i in range(41):
					var t := TAU * float(i) / 40.0
					var x := 16.0 * pow(sin(t), 3.0)
					var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
					heart.append(c + Vector2(x, y) * 0.011)
				steps.append({"do": "poly", "strokes": [heart], "color": "red"})
				steps.append({"do": "write", "text": "Happy Valentine", "at": [4.35, 0.03], "h": 0.1, "color": "white"})
			else:
				steps.append({"do": "arc_arrow", "at": [c.x, c.y], "r": 0.27, "color": "yellow"})
	if not steps.is_empty():
		steps.push_front({"do": "pick", "color": "white"})
		steps.append({"do": "admire", "at": [c.x, c.y]})
	return steps


func _ring(c: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n + 1):
		var a := TAU * float(i) / float(n) + PI * 0.5
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _pick_day_mode() -> String:
	var forced := OS.get_environment("AIQUIZ_LECTURE_MODE")
	if forced != "":
		return forced
	var now := Time.get_datetime_dict_from_system()
	var hour := int(now.hour)
	var weekday := int(now.weekday)    # 0 = 日曜
	if hour >= NIGHT_FROM or hour < NIGHT_TO:
		return "night"
	if weekday == 0 or weekday == 6:
		return "weekend"
	if hour == 12:
		return "lunch"
	if hour >= AFTER_SCHOOL_FROM:
		return "after_school"
	return "lesson"


## 席替え（項目 88）: 日付で、ノートの生徒と挙手の生徒の席が入れ替わる日がある。
func _setup_seats() -> void:
	_seats = SEATS.duplicate()
	var day := int(Time.get_date_dict_from_system().day)
	if day % 2 == 1 and actors.has("student_notes") and actors.has("student_hand"):
		_seats.student_notes = SEATS.student_hand
		_seats.student_hand = SEATS.student_notes
	for key: String in _seats:
		if actors.has(key):
			(actors[key]).root.position = _seats[key]


func _find_room_props() -> void:
	if _props == null:
		return
	for k in range(3):
		var group: Array = []
		for name in ["PRP_Desk_%d" % k, "PRP_Stool_%d" % k, "PRP_Notebook_%d_L" % k, "PRP_Notebook_%d_R" % k,
				"PRP_DeskItems_%d" % k, "PRP_StudentBook_%d" % k, "PRP_Bento_%d" % k] + (["PRP_SawModel"] if k == 2 else []):
			var node := _props.find_child(name, true, false) as Node3D
			if node != null:
				group.append({"node": node, "home": node.transform, "stool": name.begins_with("PRP_Stool")})
		_desk_groups[k] = group
	_stool_node = _props.find_child("PRP_StepStool", true, false) as Node3D
	if _stool_node != null:
		_stool_home = _stool_node.transform
	for name in ["PRP_Broom", "PRP_Rag", "PRP_Eraser_1"]:
		var node := _props.find_child(name, true, false) as Node3D
		if node != null:
			_tool_home[name] = node.transform
			_tray[name] = node
	var lamp := _props.find_child("PRP_DeskLamp", true, false) as MeshInstance3D
	if lamp != null:
		# 電気スタンドの灯り（夜だけ点ける）: 笠の下、教卓の天板を照らす
		_lamp = OmniLight3D.new()
		_lamp.name = "DeskLampLight"
		var top := _set.to_local(lamp.global_transform * (lamp.mesh.get_aabb().get_center() + Vector3(0.0, lamp.mesh.get_aabb().size.y * 0.3, 0.0)))
		_lamp.position = top
		_lamp.light_color = Color(1.0, 0.82, 0.58)
		_lamp.light_energy = 0.0
		_lamp.omni_range = 3.2
		_lamp.shadow_enabled = true
		_lamp.visible = false
		_set.add_child(_lamp)


## 照明が点く前: 生徒は席を離れて遊び、先生は黒板に落書きしている（項目 94）。
func _begin_prelude() -> void:
	cycle_index = -1
	for key: String in PLAY:
		if not actors.has(key):
			continue
		var actor = actors[key]
		var spot: Dictionary = PLAY[key]
		actor.root.position = spot.at
		actor.root.rotation.y = deg_to_rad(float(spot.yaw))
		actor.face(float(spot.yaw))
		actor.loop(str(spot.clip), 0.0)
		_seated[key] = false
		_set_student(key, "away")


## 板書を保存する（次に開いたとき「先週の続き」として薄く残る: 項目 25）。
const SAVED_BOARD := "user://lecture_board_%s.png"
const SAVED_META := "user://lecture_board.json"


func save_boards() -> void:
	for tag: String in boards:
		var canvas: SubViewport = boards[tag]
		if canvas == null or not is_instance_valid(canvas):
			continue
		var image := canvas.get_texture().get_image()
		if image != null and not image.is_empty():
			image.save_png(SAVED_BOARD % tag)
	var file := FileAccess.open(SAVED_META, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"saved": Time.get_unix_time_from_system()}))


func _restore_boards() -> void:
	if not FileAccess.file_exists(SAVED_META):
		return
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVED_META))
	if not (meta is Dictionary):
		return
	var age := Time.get_unix_time_from_system() - float((meta as Dictionary).get("saved", 0.0))
	# 古いほど薄い（1 時間以内 0.5、1 日以内 0.32、それより前 0.18）
	var alpha := 0.5 if age < 3600.0 else (0.32 if age < 86400.0 else 0.18)
	for tag: String in ["F"]:
		# 上の板（題）は講義ごとに書き直すので、下の板だけ前回の板書を残す
		if not boards.has(tag):
			continue
		var path := SAVED_BOARD % tag
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty():
				(boards[tag] as Node).call("overlay_previous", image, alpha)


func _exit_tree() -> void:
	for node: Node in _emote_meshes.values():
		if is_instance_valid(node):
			node.free()
	_emote_meshes.clear()
	PlushActorScript.clear_material_cache()


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if paused or actors.is_empty():
		return
	update(delta)


func update(delta: float) -> void:
	_t += delta
	stay += delta
	if _farewell:
		# さようなら: 授業は止めて、手を振る動きだけ続ける
		_tick_fx(delta)
		_tick_emotes(delta)
		for key: String in actors:
			(actors[key]).update(delta)
		return
	if _audio_manager != null:
		_bgm = float(_audio_manager.get("bgm_volume"))
	if _wait > 0.0:
		_wait -= delta
	elif _tick_step(delta):
		_next_step()
	for key: String in _pens.keys():
		if _tick_pen(_pens[key], delta):
			_pens.erase(key)
	_tick_students(delta)
	_tick_trainee(delta)
	_tick_fx(delta)
	_tick_emotes(delta)
	for key: String in actors:
		(actors[key]).update(delta)
	_place_held_props()


## テスト用: 段を飛ばして指定の段から始める。
func jump_to(cycle: int, index: int) -> void:
	cycle_index = clampi(cycle, 0, (lesson.cycles as Array).size() - 1)
	step_index = index - 1
	_pens.clear()
	# 到着の場面の途中なら、生徒をすぐ席に着かせる
	for key: String in STUDENTS:
		if actors.has(key) and (not _seated.get(key, true) or str(_students[key].mode) in ["away", "go_seat"]):
			var student = actors[key]
			student.root.position = _seats.get(key, SEATS[key])
			student.root.rotation.y = 0.0
			student.face(0.0)
			student.loop("S_SitIdle", 0.0)
			_seated[key] = true
			_set_student(key, "")
	if actors.has("duty"):
		_hide_extra("duty")
	_next_step()


func status() -> Dictionary:
	return {"lecture": str(lecture.get("title", "")), "cycle": cycle_index, "step": step_index, "do": str(step.get("do", "")), "phase": _phase,
		"pens": _pens.keys(), "cue": _cue, "event": last_event}


# ------------------------------------------------------------------ steps

func _steps() -> Array:
	if cycle_index < 0:
		return lesson.get(_prelude_key, [])
	return ((lesson.cycles as Array)[cycle_index] as Dictionary).get("steps", [])


func _next_step() -> void:
	step_index += 1
	# "once" の段（日付と日直）は、その日（この場面を開いている間）最初の 1 回だけ
	while step_index < _steps().size() and bool((_steps()[step_index] as Dictionary).get("once", false)) 			and _done_once.has("%d:%d" % [cycle_index, step_index]):
		step_index += 1
	if step_index >= _steps().size() and cycle_index >= 0 and _long_stay_stage < 2 and stay > (600.0 if _long_stay_stage == 1 else 300.0):
		# 長居: 5 分で採点（踏み台に腰かけて赤ペン）、10 分で先生まで居眠り
		_long_stay_stage += 1
		if _long_stay_stage == 1 and _special_day() != "":
			# 特別な日は、長くいると黒板アートを少しずつ描き足す
			_art_queue = _art_steps(_special_day(), true)
			step = _art_queue.pop_front()
			step_index = _steps().size() - 1
			_t = 0.0
			_phase = "begin"
			return
		step = {"do": "long_stay", "stage": _long_stay_stage}
		step_index = _steps().size() - 1
		_t = 0.0
		_phase = "begin"
		return
	if step_index >= _steps().size() and cycle_index >= 0 and not _done_once.has("break_%d" % _cycles_done):
		# 2 周ごとに休み時間（項目 87）
		_cycles_done += 1
		_done_once["break_%d" % _cycles_done] = true
		if _cycles_done % 2 == 1:
			step = {"do": "break", "secs": 32.0}
			step_index = _steps().size() - 1
			_t = 0.0
			_phase = "begin"
			return
	if step_index >= _steps().size() and cycle_index >= 0 and _special_day() != "" and not _done_once.has("art"):
		# 特別な日: 1 周目の終わりに黒板アートを描く（項目 58）
		_done_once["art"] = true
		_art_queue = _art_steps(_special_day(), false)
	if not _art_queue.is_empty():
		step = _art_queue.pop_front()
		step_index = _steps().size() - 1
		_t = 0.0
		_phase = "begin"
		return
	if step_index >= _steps().size():
		cycle_index = (cycle_index + 1) % (lesson.cycles as Array).size()
		step_index = 0
		if prelude and cycle_index == 0 and str((_steps()[1] as Dictionary).get("do", "")) == "bow":
			# 号令の礼をしたばかりなので、最初の周のお辞儀は飛ばす
			_done_once["prelude_bow"] = true
		# 投げたり落としたりしたチョークは、休み時間のうちに箱から補充される
		for color: String in _tray_chalks:
			for node: Node3D in _tray_chalks[color]:
				if node != _held_from:
					node.visible = true
	step = _steps()[step_index]
	if _done_once.has("prelude_bow") and cycle_index == 0 and str(step.get("do", "")) == "bow":
		_done_once.erase("prelude_bow")
		step_index += 1
		step = _steps()[step_index]
	if bool(step.get("once", false)):
		_done_once["%d:%d" % [cycle_index, step_index]] = true
	_t = 0.0
	_phase = "begin"
	if step.has("cue"):
		_set_cue(str(step.cue))


## 今の段を 1 フレーム進める。終わったら true。
func _tick_step(_delta: float) -> bool:
	var teacher = actors.lecturer
	match str(step.get("do", "")):
		"walk":
			if _phase == "begin":
				var at := _place(step.get("to", "lectern"))
				teacher.walk_to(at, float(step.get("face", CLASS_YAW)), "T_Idle")
				_phase = "walking"
				return false
			return not teacher.is_busy()
		"bow":
			if _phase == "begin":
				_wait = teacher.once("T_Bow", "T_Idle") + 0.2
				_phase = "done"
				return false
			return true
		"explain":
			if _phase == "begin":
				if absf(angle_difference(teacher.root.rotation.y, deg_to_rad(CLASS_YAW))) > 0.3:
					teacher.walk_to(LECTERN_SPOT, CLASS_YAW, "T_Explain")
				else:
					teacher.loop("T_Explain")
				_phase = "talk"
				return false
			if teacher.is_moving():
				_t = 0.0
				return false
			teacher.loop("T_Explain")
			_update_pointer_hand(teacher, true)
			if _t >= float(step.get("secs", 3.0)):
				_update_pointer_hand(teacher, false)
				return true
			return false
		"pick":
			if _phase == "begin":
				_pick = {"color": str(step.get("color", "white")), "phase": "begin"}
				_phase = "pick"
			return _tick_pick(teacher)
		"write", "write_v", "write_cursive", "circle", "line", "underline", "wavy", "double", "arc_arrow", "arc_jump", "blade_row", "trace", "hanamaru", "poly":
			if _phase == "begin":
				var color := str(step.get("color", "white"))
				if _held_color != color:
					# 色を替える: チョーク箱へ手を伸ばして持ち替える
					_pick = {"color": color, "phase": "begin"}
					_phase = "pick"
					return false
				_phase = "pen"
				_start_write(teacher, step)
				return false
			if _phase == "pick":
				if _tick_pick(teacher):
					_phase = "pen"
					_start_write(teacher, step)
				return false
			return not _pens.has(teacher.key)
		"admire":
			return _tick_admire(teacher)
		"doodle":
			return _tick_doodle(teacher)
		"freeze":
			return _tick_freeze(teacher)
		"to_seats":
			for key: String in STUDENTS:
				if actors.has(key) and not _seated.get(key, true):
					_go_seat(key)
			return true
		"long_stay":
			return _tick_long_stay(teacher)
		"handout", "collect":
			return _tick_papers(teacher, str(step.do) == "handout")
		"solve":
			return _tick_solve(teacher)
		"grade_papers":
			return _tick_grade_papers(teacher)
		"diplomas":
			return _tick_diplomas(teacher)
		"cheer_all":
			return _tick_cheer_all(teacher)
		"write_high":
			return _tick_write_high(teacher)
		"slide":
			return _tick_slide(teacher)
		"compass", "set_square":
			return _tick_drafting(teacher)
		"chime":
			# 区切りの間（授業・テストの始めと終わり）
			if _phase == "begin":
				_wait = float(step.get("secs", 2.5))
				_phase = "done"
				return false
			return true
		"lunch":
			return _tick_lunch(teacher)
		"cleaning":
			return _tick_cleaning(teacher)
		"night":
			return _tick_night(teacher)
		"break":
			return _tick_break(teacher)
		"read":
			if _phase == "begin":
				# 指し棒を伸ばし、書いた行を左から右へなぞって読む（項目 41）
				_put_down(teacher)
				teacher.pointer_to("R", true)
				teacher.tip_length = 0.85
				var a := _vec2(step.from)
				var b := _vec2(step.to)
				_pens[teacher.key] = {"kind": "point", "actor": teacher, "board": "F", "strokes": [_wobbly_line(a, b)],
					"si": 0, "pi": 0, "phase": "approach", "pos": Vector2.ZERO, "lift": 0.15, "color": "", "id": 0,
					"shoulder_u": -99.0, "top_v": maxf(a.y, b.y), "pressure": 1.0, "drawn": 0.0, "break_at": -1}
				_set_cue("listen")
				_phase = "pen"
				return false
			if _pens.has(teacher.key):
				return false
			_update_pointer_hand(teacher, false)
			return true
		"roll_call":
			return _tick_roll_call(teacher)
		"patrol":
			return _tick_patrol(teacher)
		"talk_board":
			return _tick_talk_board(teacher)
		"camera_nod":
			if _phase == "begin":
				var camera := get_viewport().get_camera_3d()
				if camera != null:
					teacher.face_point(_set.to_local(camera.global_position))
				_phase = "turn"
				return false
			if _phase == "turn":
				if teacher.is_busy():
					return false
				_wait = teacher.once("T_Nod", "T_Idle") + 0.2
				_phase = "done"
				return false
			return true
		"point":
			var done := _tick_point(teacher)
			if done:
				_update_pointer_hand(teacher, false)
			return done
		"ask":
			return _tick_ask(teacher)
		"gag":
			return _tick_gag(teacher)
		"erase":
			return _tick_erase(teacher)
		"clip":
			if _phase == "begin":
				teacher.ik_off()
				_wait = teacher.once(str(step.get("name", "T_Nod")), "T_Idle") + 0.1
				_phase = "done"
				return false
			return true
		"clap_erasers":
			return _tick_clap_erasers(teacher)
		"event":
			return _tick_event(str(step.get("name", "")))
		"wait":
			return _t >= float(step.get("secs", 1.0))
	return true


func _place(where: Variant) -> Vector3:
	if where is Array:
		return Vector3(float(where[0]), 0.0, float(where[1]))
	match str(where):
		"lectern":
			return LECTERN_SPOT
		"stool":
			return _stool_pos()
	return LECTERN_SPOT


# ------------------------------------------------------------------ board geometry

func board_point(board: String, uv: Vector2, lift := 0.0) -> Vector3:
	return _board_origin(board) + BOARD_U * uv.x + BOARD_V * uv.y + BOARD_IN * lift


## 黒板の面の左下の角（上下スライドで動く）。
func _board_origin(board: String) -> Vector3:
	return (BOARD_ORIGIN[board] as Vector3) + Vector3(0.0, float(_board_shift.get(board, 0.0)), 0.0)


func board_uv(board: String, point: Vector3) -> Vector2:
	var d := point - _board_origin(board)
	return Vector2(d.dot(BOARD_U), d.dot(BOARD_V))


## 点が黒板の面から教室側へどれだけ離れているか（m）。
func board_uv_lift(board: String, point: Vector3) -> float:
	return (point - _board_origin(board)).dot(BOARD_IN)


## 黒板の uv（肩の u）に対する書く構えの足元。dn は肩と黒板の距離（手の届く高さで決める）。
func stance_root(board: String, shoulder_u: float, top_v: float, reach := REACH_PLAN, lift := 0.0) -> Vector3:
	var top := board_point(board, Vector2(shoulder_u, top_v))
	var dy := top.y - SHOULDER_Y - lift - (0.06 if top_v > TIPTOE_V and lift <= 0.0 else 0.0)
	var dn := clampf(sqrt(maxf(0.0, reach * reach - dy * dy)) * 0.8, 0.18, maxf(0.4, reach * 0.8))
	var shoulder := board_point(board, Vector2(shoulder_u, 0.0), dn)
	var off := SHOULDER_OFF.rotated(Vector3.UP, deg_to_rad(WRITE_YAW))
	return Vector3(shoulder.x - off.x, 0.0, shoulder.z - off.z)


# ------------------------------------------------------------------ pen (writing / erasing)

## 書く仕事を始める: 段（write / circle / line ...）から線の列を作り、構えへ歩く。
func _start_write(actor, s: Dictionary) -> void:
	var board := str(s.get("board", "F"))
	var strokes: Array = []
	var color := str(s.get("color", "white"))
	match str(s.get("do", "")):
		"write_v":
			# 縦書き（国語）: 字を上から下へ、列は右から左へ（台本が列ごとに分けて渡す）
			var at := _vec2(s.get("at", [6.9, 0.45]))
			var h := float(s.get("h", 0.13))
			var k := 0
			for ch in str(s.get("text", "")):
				var glyph_v: Array = _glyphs.layout(ch, Vector2(at.x, at.y - k * h * 1.04), h, 0.5, _rng.randi())
				for glyph: Dictionary in glyph_v:
					for stroke: PackedVector2Array in glyph.strokes:
						if ch in ["ー", "－", "〜"]:
							# 長音は縦にする
							var c: Vector2 = glyph.center
							var turned := PackedVector2Array()
							for p in stroke:
								turned.append(c + (p - c).rotated(-PI * 0.5))
							strokes.append(turned)
						else:
							strokes.append(stroke)
				k += 1
		"write_cursive":
			# 英語の筆記体らしく: 傾けて、字と字を細い線でつなぐ
			var at := _vec2(s.get("at", [4.0, 0.1]))
			var glyphs_c: Array = _glyphs.layout(str(s.get("text", "")), at, float(s.get("h", 0.13)), 0.3, _rng.randi())
			var last_end := Vector2.INF
			for glyph: Dictionary in glyphs_c:
				var slanted: Array = []
				for stroke: PackedVector2Array in glyph.strokes:
					var sl := PackedVector2Array()
					for p in stroke:
						sl.append(Vector2(p.x + (p.y - at.y) * 0.28, p.y))
					slanted.append(sl)
				if not slanted.is_empty() and last_end != Vector2.INF:
					var first: PackedVector2Array = slanted[0]
					strokes.append(PackedVector2Array([last_end, (last_end + first[0]) * 0.5 + Vector2(0.0, -0.015), first[0]]))
				strokes.append_array(slanted)
				if not slanted.is_empty():
					var tail: PackedVector2Array = slanted[slanted.size() - 1]
					last_end = tail[tail.size() - 1]
		"write", "write_high":
			var at := _vec2(s.get("at", [0.4, 0.3]))
			if str(s.get("at", "")) == "last" and not _last_glyph.is_empty():
				at = _last_glyph.origin
			elif str(s.get("at", "")) == "next" and not _last_glyph.is_empty():
				at = _last_glyph.next
			var style := {}
			for k in ["drift", "grow", "limit"]:
				if s.has(k):
					style[k] = float(s[k])
			var text := str(s.get("text", ""))
			if text == "{date}":
				# 黒板の右端の日付（PC の今日の日付）
				var d := Time.get_date_dict_from_system()
				text = "%d月%d日(%s)" % [d.month, d.day, ["日", "月", "火", "水", "木", "金", "土"][int(d.weekday)]]
			var glyphs: Array = _glyphs.layout(text, at, float(s.get("h", 0.2)), 0.6, _rng.randi(), style)
			for glyph: Dictionary in glyphs:
				strokes.append_array(glyph.strokes)
			if not glyphs.is_empty():
				var last: Dictionary = glyphs[glyphs.size() - 1]
				var gh := float(last.get("h", s.get("h", 0.2)))
				var c: Vector2 = last.center
				_last_glyph = {"origin": Vector2(c.x - gh * 0.5, c.y - gh * 0.5), "h": gh,
					"next": Vector2(c.x + gh * 0.48, c.y - gh * 0.5),
					"rect": Rect2(c.x - gh * 0.55, c.y - gh * 0.55, gh * 1.1, gh * 1.1)}
		"circle":
			var circle := _circle(_vec2(s.at), float(s.get("r", 0.2)), 0.0, TAU * 1.04, 40)
			var wobble := float(s.get("wobble", 0.0))
			if wobble > 0.0:
				# 歪んだ円（一筆描きの失敗）: 半径が場所によって大きくずれ、最後が閉じない
				var c := _vec2(s.at)
				var phase := _rng.randf_range(0.0, TAU)
				for i in range(circle.size()):
					var d := circle[i] - c
					var t := float(i) / float(circle.size() - 1)
					circle[i] = c + d * (1.0 + wobble * sin(t * TAU * 1.5 + phase) + wobble * 0.6 * t)
			strokes.append(circle)
		"arc_arrow":
			var c := _vec2(s.at)
			var r := float(s.get("r", 0.25))
			var arc := _circle(c, r, PI * 0.15, PI * 1.35, 24)
			strokes.append(arc)
			strokes.append_array(_arrow_head(arc[arc.size() - 2], arc[arc.size() - 1], 0.06))
		"line", "underline":
			var a := _vec2(s.from)
			var b := _vec2(s.to)
			strokes.append(_wobbly_line(a, b))
		"double":
			# 二重線（大事な語の下）
			var a := _vec2(s.from)
			var b := _vec2(s.to)
			strokes.append(_wobbly_line(a, b))
			strokes.append(_wobbly_line(a + Vector2(0.01, -0.025), b + Vector2(0.0, -0.025)))
		"wavy":
			# 波線
			var a := _vec2(s.from)
			var b := _vec2(s.to)
			var wave := PackedVector2Array()
			var n := maxi(8, int(a.distance_to(b) / 0.015))
			for i in range(n + 1):
				var t := float(i) / float(n)
				wave.append(a.lerp(b, t) + Vector2(0.0, 0.012 * sin(t * a.distance_to(b) / 0.05 * TAU)))
			strokes.append(wave)
		"hanamaru":
			# 花丸: 内側のぐるぐる 2 周と、外側の花びら 8 枚
			var c := _vec2(s.at)
			var r := float(s.get("r", 0.2))
			var spiral := PackedVector2Array()
			for i in range(49):
				var t := float(i) / 48.0
				var a := PI * 0.5 + t * TAU * 2.0
				spiral.append(c + Vector2(cos(a), sin(a)) * r * lerpf(0.25, 0.7, t))
			strokes.append(spiral)
			var petals := PackedVector2Array()
			for i in range(97):
				var t := float(i) / 96.0
				var a := PI * 0.5 + t * TAU
				petals.append(c + Vector2(cos(a), sin(a)) * r * (0.92 + 0.12 * absf(sin(t * PI * 8.0))))
			strokes.append(petals)
		"poly":
			# 台本が線を直接渡す（黒板アートの部品）
			for raw: Array in s.get("strokes", []):
				var line := PackedVector2Array()
				for p: Variant in raw:
					line.append(_vec2(p) if p is Array else (p as Vector2))
				if line.size() >= 2:
					strokes.append(line)
		"blade_row":
			# 刃の列（右端の図）: 地面の線と、小さな丸鋸の列（丸の中に軸の点）
			var at := _vec2(s.at)
			var n := int(s.get("n", 6))
			var r := float(s.get("r", 0.06))
			strokes.append(_wobbly_line(at + Vector2(-r * 1.4, -r * 1.1), at + Vector2(r * (2.3 * (n - 1) + 1.4), -r * 1.1)))
			for k in range(n):
				var c := at + Vector2(2.3 * r * k, 0.0)
				strokes.append(_circle(c, r, 0.0, TAU * 1.03, 18))
				strokes.append(PackedVector2Array([c + Vector2(-0.004, 0.0), c + Vector2(0.004, 0.002)]))
		"trace":
			# 描いた放物線を手でなぞる（書かない）
			var a := _vec2(s.from)
			var b := _vec2(s.to)
			var h := float(s.get("height", 0.3))
			var path := PackedVector2Array()
			for i in range(31):
				var t := i / 30.0
				path.append(a.lerp(b, t) + Vector2(0.0, 4.0 * h * t * (1.0 - t)))
			strokes.append(path)
		"arc_jump":
			var a := _vec2(s.from)
			var b := _vec2(s.to)
			var h := float(s.get("height", 0.3))
			var arc := PackedVector2Array()
			for i in range(25):
				var t := i / 24.0
				arc.append(a.lerp(b, t) + Vector2(0.0, 4.0 * h * t * (1.0 - t)))
			strokes.append(arc)
			strokes.append_array(_arrow_head(arc[23], arc[24], 0.05))
	var break_at := -1
	if bool(s.get("break", false)) and strokes.size() > 3:
		break_at = _rng.randi_range(2, strokes.size() - 2)
	_pens[actor.key] = {"kind": "trace" if str(s.get("do", "")) == "trace" else "write", "actor": actor, "board": board, "strokes": strokes, "si": 0, "pi": 0,
		"break_at": break_at, "rub": bool(s.get("rub_last", false)),
		"phase": "approach", "pos": Vector2.ZERO, "lift": 0.12, "color": color, "id": 0, "shoulder_u": -99.0,
		"top_v": 0.0, "pressure": 1.0, "drawn": 0.0}


## 消す仕事: rect（u0, v0, u1, v1）を、縦のジグザグ（上から斜めに下ろして隣の列へ上げる）で左から右へ拭く。
## 3 列（約 0.5 m）ごとに 1 本の線にして、線ごとに構え直す。messy: 小さな円を描きながらぐるぐる拭く。
func _start_erase(actor, board: String, rect: Array, messy := false) -> void:
	var u0 := float(rect[0]) + ERASER_SIZE.x * 0.5
	var u1 := float(rect[2]) - ERASER_SIZE.x * 0.3
	var top := float(rect[3]) - ERASER_SIZE.y * 0.45
	var bottom := float(rect[1]) + ERASER_SIZE.y * 0.45
	var strokes: Array = []
	var u := u0
	while u < u1:
		var seg := PackedVector2Array()
		var end := minf(u1, u + ERASE_COLUMN * 3.0)
		if messy:
			var n := 36
			for i in range(n + 1):
				var t := float(i) / float(n)
				var ang := t * TAU * 3.0
				var cu := lerpf(u, end, t)
				var cv := lerpf(top, bottom, 0.5) + (top - bottom) * 0.42 * sin(t * PI * 3.0)
				seg.append(Vector2(cu + 0.07 * cos(ang), cv + 0.07 * sin(ang)))
		else:
			var c := u
			seg.append(Vector2(c, top))
			while c < end - 0.001:
				seg.append(Vector2(c + 0.025, bottom))
				c = minf(end, c + ERASE_COLUMN)
				seg.append(Vector2(c, top))
		strokes.append(seg)
		u = end + 0.001
	_pens[actor.key] = {"kind": "erase", "actor": actor, "board": board, "strokes": strokes, "si": 0, "pi": 0,
		"phase": "approach", "pos": Vector2.ZERO, "lift": 0.12, "color": "", "id": 0, "shoulder_u": -99.0,
		"top_v": float(rect[3]), "pressure": 1.0, "drawn": 0.0, "messy": messy, "stamp_left": 0.0}


func _tick_pen(pen: Dictionary, delta: float) -> bool:
	var actor = pen.actor
	var board: String = pen.board
	var strokes: Array = pen.strokes
	if int(pen.si) >= strokes.size() and pen.get("rub", false) and not pen.get("rubbed", false) and not _last_glyph.is_empty():
		# 書き間違い: 手でこすって消す（黒板消しを使わず、ミトンで）
		pen.rubbed = true
		var r: Rect2 = _last_glyph.rect
		var path := PackedVector2Array()
		for k in range(9):
			var t := float(k) / 8.0
			path.append(Vector2(r.position.x + (r.size.x if k % 2 else 0.0), r.end.y - r.size.y * t))
		pen.strokes = strokes + [path]
		pen.kind = "rub"
		pen.phase = "restance"
		return false
	if int(pen.si) >= strokes.size():
		if pen.kind == "rub" and not pen.get("clapped", false):
			pen.clapped = true
			actor.ik_off(0.2)
			pen.t = 0.0
			pen.phase = "finish"
			pen.clap = actor.once("T_ClapDust", actor.idle_clip)
			_puff_later(0.35, actor, 1, 0.2)
			_puff_later(0.8, actor, 1, 0.2)
			_dust.emitting = false
		if pen.phase != "finish":
			pen.phase = "finish"
			pen.t = 0.0
			actor.ik_off(0.35)
			actor.tip_length = 0.36
			actor.loop(actor.idle_clip, 0.3)
			_dust.emitting = false
		pen.t = float(pen.get("t", 0.0)) + delta
		return float(pen.t) > maxf(0.35, float(pen.get("clap", 0.0)))
	var stroke: PackedVector2Array = strokes[int(pen.si)]
	var stance_clip := "T_WriteStance" if pen.kind != "erase" else ("T_WipeMessy" if pen.get("messy", false) else "T_WipeLoop")
	if pen.kind == "point":
		stance_clip = "T_Explain" if actor.has_clip("T_Explain") else actor.idle_clip
	elif pen.kind == "wet":
		stance_clip = "T_WipeLoop" if actor.has_clip("T_WipeLoop") else actor.idle_clip
	if pen.kind != "erase" and float(pen.top_v) > TIPTOE_V:
		# 上の段は背伸び（つま先立ちでぷるぷる）
		stance_clip = "T_WriteTiptoe"
	if not actor.has_clip(stance_clip):
		stance_clip = actor.idle_clip
	match str(pen.phase):
		"approach", "restance":
			# この画が今の構えの窓に入らなければ構え直す（遠ければ歩く、近ければ横歩き）
			var lo := INF
			var hi := -INF
			var top := -INF
			for p in stroke:
				lo = minf(lo, p.x)
				hi = maxf(hi, p.x)
				top = maxf(top, p.y)
			var su: float = pen.shoulder_u
			var win: Vector2 = pen.get("window", WINDOW)
			var need: bool = pen.phase == "approach" or lo - su < win.x or hi - su > win.y or absf(top - float(pen.top_v)) > 0.25
			if pen.get("fixed", false):
				# 踏み台・肩車の上: 歩けないので、今の構えのまま手を伸ばす
				if pen.phase == "approach":
					pen.pos = board_uv(board, actor.hand_tip_point())
					pen.lift = clampf(board_uv_lift(board, actor.hand_tip_point()), 0.03, 0.2)
					actor.ik_on(0.25)
					actor.loop(stance_clip, 0.2)
				pen.phase = "travel"
				return false
			if need and not pen.get("moving", false):
				var shoulder_u := clampf(lo + LEAD + maxf(0.0, (hi - lo) - (WINDOW.y - LEAD)) * 0.5, 0.15, BOARD_SIZE.x - 0.1)
				var target := stance_root(board, shoulder_u, maxf(top, float(pen.top_v) if pen.kind == "erase" else top),
					float(pen.get("reach", 1.05 if pen.kind == "point" else REACH_PLAN)), float(pen.get("lift_y", 0.0)))
				var in_stance: bool = absf(angle_difference(actor.root.rotation.y, deg_to_rad(WRITE_YAW))) < 0.2
				var far: bool = actor.root.position.distance_to(target) > 0.75 or not in_stance
				if pen.phase == "approach" and not far:
					# 前の仕事の構えのまま続ける: 今の手の位置から
					pen.pos = board_uv(board, actor.hand_tip_point())
					pen.lift = clampf(board_uv_lift(board, actor.hand_tip_point()), 0.03, 0.15)
					actor.ik_on(0.2)
					_set_pen_tip(pen)
				pen.shoulder_u = shoulder_u
				pen.top_v = top
				pen.moving = true
				pen.root_from = actor.root.position
				if far:
					actor.ik_off(0.2)
					actor.walk_to(target, WRITE_YAW, stance_clip)
					pen.walked = true
				else:
					actor.side_to(target, stance_clip, ERASE_SIDE_SPEED if pen.kind == "erase" else 0.0)
					pen.walked = false
				return false
			if pen.get("moving", false):
				if not pen.walked:
					# 横歩きの間も手先は体についていく
					var moved := board_uv(board, actor.root.position) - board_uv(board, pen.root_from)
					pen.pos = Vector2(pen.pos) + Vector2(moved.x, 0.0)
					pen.root_from = actor.root.position
					_set_pen_tip(pen)
				if actor.is_busy():
					return false
				pen.moving = false
				actor.loop(stance_clip, 0.2)
				if pen.walked:
					# 歩いて来たら、今の手の位置から手先を上げ始める
					pen.pos = board_uv(board, actor.hand_tip_point())
					pen.lift = 0.15
					actor.set_tip(board_point(board, pen.pos, pen.lift))
					actor.ik_on(0.3)
			pen.phase = "travel"
		"break":
			# 書いている途中でチョークが折れる → 先が床へ落ちて転がる → しゃがんで拾う → 短くなったチョークで続ける
			pen.t = float(pen.get("t", 0.0)) + delta
			if not pen.has("piece"):
				var piece := _make_chalk(_held_color if _held_color != "" else "white")
				piece.scale = Vector3(1.0, 0.45, 1.0)
				_set.add_child(piece)
				var tip: Vector3 = actor.hand_tip_point()
				var floor_at := Vector3(tip.x + _rng.randf_range(-0.2, 0.2), 0.012, tip.z - _rng.randf_range(0.25, 0.45))
				_throw_prop(piece, tip, floor_at, 0.45, 0.05, false)
				pen.piece = piece
				_puff(tip, 0, 0.1)
				emote(actor, "!", 1.0)
				actor.ik_off(0.12)
				actor.blink()
				var held: Node3D = actor.holding("R")
				if held != null:
					held.scale = Vector3(1.0, 0.6, 1.0)
				pen.crouch = -1.0
			elif float(pen.t) > 0.55 and float(pen.crouch) < 0.0:
				actor.face(CLASS_YAW - 30.0)
				pen.crouch = actor.once("T_CrouchPickup", actor.idle_clip)
				pen.t = 0.0
				pen.phase = "crouch"
		"crouch":
			pen.t = float(pen.t) + delta
			if float(pen.t) > float(pen.crouch) * 0.5 and is_instance_valid(pen.piece):
				(pen.piece as Node).queue_free()
			if float(pen.t) >= float(pen.crouch):
				pen.phase = "approach"
				pen.shoulder_u = -99.0
				pen.erase("moving")
		"travel":
			if int(pen.si) == int(pen.get("break_at", -1)) and not pen.get("broke", false):
				pen.broke = true
				pen.phase = "break"
				pen.t = 0.0
				return false
			# 手先を浮かせたまま画の始点へ
			var target: Vector2 = stroke[0]
			var pos: Vector2 = pen.pos
			var d := target - pos
			var step_len := TRAVEL_SPEED * delta
			pen.lift = move_toward(float(pen.lift), LIFT if pen.kind == "write" else 0.05, delta * 0.6)
			if d.length() <= step_len and float(pen.lift) <= (LIFT if pen.kind == "write" else 0.05) + 0.001:
				pen.pos = target
				pen.phase = "down"
				pen.t = 0.0
			else:
				pen.pos = pos + d.limit_length(step_len)
			_set_pen_tip(pen)
		"down":
			pen.t = float(pen.get("t", 0.0)) + delta
			pen.lift = lerpf(LIFT, 0.0, clampf(float(pen.t) / 0.045, 0.0, 1.0)) if pen.kind == "write" else lerpf(0.05, 0.0, clampf(float(pen.t) / 0.1, 0.0, 1.0))
			if pen.kind == "trace":
				pen.lift = 0.06
			elif pen.kind == "point":
				pen.lift = 0.0
			_set_pen_tip(pen)
			if pen.get("how", "") == "jump" and not pen.get("jumping", false):
				# 1 画ごとに跳ぶ（届かない）: しゃがんで跳び、いちばん高いところで書く
				pen.jumping = true
				var jump_clip := "T_JumpWrite" if actor.has_clip("T_JumpWrite") else "G_JumpWrite"
				pen.jump_len = actor.once(jump_clip, actor.base_clip if actor.base_clip != "" else actor.idle_clip, 0.05)
				pen.jump_t = 0.0
				pen.phase = "jumpwait"
				return false
			if float(pen.t) >= (0.045 if pen.kind == "write" else 0.1):
				pen.phase = "draw"
				pen.pi = 1
				pen.drawn = 0.0
				pen.length = _polyline_length(stroke)
				_stroke_id += 1
				pen.id = _stroke_id
				pen.dot = pen.kind == "write" and float(pen.length) < 0.025
				if pen.kind == "write":
					# 1 画ごとに体が小さく沈む（読み上げながら書く拍子）。点はカツッと強く打つ
					actor.kick(0.22 if pen.dot else 0.09)
					_canvas(board).stroke_to(int(pen.id), pen.pos, pen.color, CHALK_WIDTH * (1.25 if pen.dot else 1.0), 1.0 if pen.dot else 0.7)
					if pen.dot:
						_puff(board_point(board, pen.pos, 0.02), 0, 0.0)
					elif float(pen.length) > 0.45 and _rng.randf() < 0.45:
						_squeak()
				_dust.emitting = pen.kind == "write"
		"jumpwait":
			pen.jump_t = float(pen.jump_t) + delta
			_set_pen_tip(pen)
			if float(pen.jump_t) >= 0.3:
				pen.lift = 0.0
				pen.phase = "draw"
				pen.pi = 1
				pen.drawn = 0.0
				pen.length = _polyline_length(stroke)
				_stroke_id += 1
				pen.id = _stroke_id
				_canvas(board).stroke_to(int(pen.id), pen.pos, pen.color, CHALK_WIDTH, 0.8)
			return false
		"draw":
			var speed := PEN_SPEED if pen.kind == "write" else (0.5 if pen.kind == "trace" else (0.9 if pen.kind in ["rub", "wet"] else (0.32 if pen.kind == "point" else ERASE_SPEED)))
			if pen.get("how", "") == "jump":
				# 宙にいる 0.2 秒で 1 画を書き切る
				speed = maxf(PEN_SPEED, float(pen.length) / 0.2)
			elif pen.get("how", "") == "pointer":
				speed = 0.3
			var remaining := speed * delta
			var canvas = _canvas(board)
			while remaining > 0.0 and int(pen.pi) < stroke.size():
				if pen.kind == "erase" or pen.kind == "rub" or pen.kind == "wet":
					# 黒板消しは ERASE_STEP ごとに跡を付ける（細かく進む）。手でこするときは小さく弱く
					var before: Vector2 = pen.pos
					var hop := minf(remaining, ERASE_STEP)
					var aim: Vector2 = stroke[int(pen.pi)]
					var gap := aim - before
					if gap.length() <= hop:
						pen.pos = aim
						pen.pi = int(pen.pi) + 1
						remaining -= gap.length()
					else:
						pen.pos = before + gap / gap.length() * hop
						remaining -= hop
					if pen.kind == "rub":
						canvas.erase_at(pen.pos, Vector2(0.09, 0.07), 0.28)
					elif pen.kind == "wet":
						canvas.erase_at(pen.pos, Vector2(0.3, 0.2), 0.6)
						canvas.wet_at(pen.pos, Vector2(0.34, 0.24), 0.85)
					else:
						canvas.erase_at(pen.pos, ERASER_SIZE, ERASE_STRENGTH)
					continue
				var target: Vector2 = stroke[int(pen.pi)]
				var pos: Vector2 = pen.pos
				var d := target - pos
				if pen.kind == "point":
					# 1 字ごとに指し棒の先でトンと叩きながら読む
					var before := float(pen.drawn)
					if int((before + minf(remaining, d.length())) / 0.2) > int(before / 0.2):
						actor.kick(0.12)
				var dist := d.length()
				if dist <= remaining:
					pen.pos = target
					pen.pi = int(pen.pi) + 1
					remaining -= dist
					pen.drawn = float(pen.drawn) + dist
				else:
					pen.pos = pos + d / dist * remaining
					pen.drawn = float(pen.drawn) + remaining
					remaining = 0.0
				if pen.kind == "write":
					var f := clampf(float(pen.drawn) / maxf(0.001, float(pen.length)), 0.0, 1.0)
					# 書き始めは押し付けて強く、終わりはすっと抜く。少しだけ揺らぐ
					var pressure := clampf(0.82 + 0.18 * sin(f * PI * 0.8 + 0.4) - 0.25 * smoothstep(0.85, 1.0, f) + _rng.randf_range(-0.05, 0.05), 0.35, 1.0)
					canvas.stroke_to(int(pen.id), pen.pos, pen.color, CHALK_WIDTH, pressure)
			_set_pen_tip(pen)
			if int(pen.pi) >= stroke.size():
				if pen.kind == "write":
					canvas.end_stroke(int(pen.id))
				pen.phase = "up"
				pen.t = 0.0
				_dust.emitting = false
				if pen.kind == "write" and not pen.get("dot", false):
					# 止めに粉が少したまる
					if _rng.randf() < 0.35:
						_puff(board_point(board, pen.pos, 0.015), 0, -0.4)
		"up":
			pen.t = float(pen.get("t", 0.0)) + delta
			pen.lift = lerpf(0.0, LIFT, clampf(float(pen.t) / 0.04, 0.0, 1.0))
			_set_pen_tip(pen)
			if pen.get("jumping", false):
				# 着地まで待つ
				pen.jump_t = float(pen.jump_t) + delta
				if float(pen.jump_t) < float(pen.jump_len):
					return false
				pen.jumping = false
			if float(pen.t) >= 0.04 + _rng.randf_range(0.0, 0.03):
				pen.si = int(pen.si) + 1
				pen.phase = "restance"
	return false


func _set_pen_tip(pen: Dictionary) -> void:
	var actor = pen.actor
	var lift := float(pen.lift)
	if pen.kind == "erase":
		lift += 0.055      # 手先は黒板消しの背中
	actor.set_tip(board_point(pen.board, pen.pos, lift))
	if pen.kind == "write":
		_dust.position = board_point(pen.board, pen.pos, 0.01)
	pen.tip_world = board_point(pen.board, pen.pos, float(pen.lift))


func _canvas(board: String):
	return boards.get(board, boards.F)


static func _vec2(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


func _circle(c: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var wob := _rng.randf_range(0.0, TAU)
	for i in range(n + 1):
		var t := float(i) / float(n)
		var a := lerpf(a0, a1, t) + PI * 0.5
		var rr := r * (1.0 + 0.035 * sin(a * 2.0 + wob))
		out.append(c + Vector2(cos(a), sin(a)) * rr)
	return out


func _wobbly_line(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(2, int(a.distance_to(b) / 0.06))
	var normal := (b - a).orthogonal().normalized()
	var wob := _rng.randf_range(0.0, TAU)
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(a.lerp(b, t) + normal * 0.006 * sin(t * 5.0 + wob))
	return out


func _arrow_head(a: Vector2, b: Vector2, size: float) -> Array:
	var d := (b - a).normalized()
	var left := b - d.rotated(0.5) * size
	var right := b - d.rotated(-0.5) * size
	return [PackedVector2Array([left, b]), PackedVector2Array([right, b])]


static func _polyline_length(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(line.size() - 1):
		total += line[i].distance_to(line[i + 1])
	return total


# ------------------------------------------------------------------ chalk & eraser

func _find_tray() -> void:
	if _props == null:
		return
	for color: String in CHALK_COLORS:
		var list: Array = []
		for k in range(4):
			var node := _props.find_child("PRP_Chalk_%s_%d" % [color.capitalize(), k], true, false) as Node3D
			if node != null:
				list.append(node)
		_tray_chalks[color] = list
	for tag in ["F", "B"]:
		var panel := _props.find_child("PRP_BoardPanel_" + tag, true, false) as Node3D
		if panel != null:
			_panels[tag] = panel
			_panel_home[tag] = panel.position
	for name in ["PRP_Compass", "PRP_SetSquare_60", "PRP_SetSquare_45"]:
		var tool := _props.find_child(name, true, false) as Node3D
		if tool != null:
			_tray[name] = tool
			_tool_home[name] = tool.transform
	var box := _props.find_child("PRP_ChalkBox", true, false) as Node3D
	if box != null:
		_tray["box"] = box
	var eraser := _props.find_child("PRP_Eraser_0", true, false) as Node3D
	if eraser != null:
		_tray["eraser"] = eraser
		_tray["eraser_home"] = eraser.transform


## 小道具（Node3D、または "box" / "eraser"）の中心（セットのローカル）。
func _tray_point(item: Variant) -> Vector3:
	var node: Node3D = item if item is Node3D else _tray.get(str(item))
	if node == null:
		return board_point("F", Vector2(1.0, -0.08), 0.06)
	var mesh_instance := node as MeshInstance3D
	var centre := node.global_position
	if mesh_instance != null and mesh_instance.mesh != null:
		centre = node.global_transform * mesh_instance.mesh.get_aabb().get_center()
	return _set.to_local(centre)


## チョーク受けの上、黒板の u の位置に置くときの点（中心）。
func _tray_spot(u: float, height: float) -> Vector3:
	var p := board_point("F", Vector2(u, 0.0))
	return Vector3(p.x, TRAY_TOP + height * 0.5, TRAY_Z)


## 取るチョーク: その色のトレイの上の実物（見えているもの）のうち、u に近いもの。なければ箱（null）。
func _pick_source(color: String, near_u: float) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node: Node3D in _tray_chalks.get(color, []):
		if not node.visible:
			continue
		var d := absf(board_uv("F", _tray_point(node)).x - near_u)
		if d < best_d:
			best = node
			best_d = d
	return best


func _make_chalk(color: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0095
	mesh.bottom_radius = 0.0099
	mesh.height = 0.075
	mesh.radial_segments = 10
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = CHALK_COLORS.get(color, CHALK_COLORS.white)
	material.roughness = 0.97
	var chalk := MeshInstance3D.new()
	chalk.name = "HeldChalk"
	chalk.mesh = mesh
	chalk.material_override = material
	chalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return chalk


## チョークを取る・持ち替える: その色のチョークの前（なければチョーク箱）で構え、持っているものを手元の
## トレイに置いてから、手を伸ばして取る。
func _tick_pick(teacher) -> bool:
	match str(_pick.get("phase", "begin")):
		"begin":
			if _held_color == str(_pick.color) and _eraser_holder == "":
				return true
			var near_u := board_uv("F", teacher.hand_tip_point()).x
			var source: Node3D = _pick_source(str(_pick.color), near_u)
			_pick.source = source
			var at := _tray_point(source if source != null else "box")
			var target := stance_root("F", board_uv("F", at).x + LEAD, 0.0)
			_pick.phase = "walk"
			if teacher.root.position.distance_to(target) > 0.25 or absf(angle_difference(teacher.root.rotation.y, deg_to_rad(WRITE_YAW))) > 0.2:
				teacher.ik_off(0.2)
				teacher.walk_to(target, WRITE_YAW, "T_Idle")
		"walk":
			if teacher.is_busy():
				return false
			var source: Node3D = _pick.source
			var where: Variant = source if source != null else "box"
			var steps: Array = []
			if _held_color != "" or _eraser_holder == teacher.key:
				# 持っているものは、取るものの少し左のトレイの上へ置く
				var u := board_uv("F", _tray_point(where)).x - 0.14
				steps.append({"where": _tray_spot(u, 0.02), "do": "put"})
			steps.append({"where": where, "do": "take", "item": "chalk", "color": str(_pick.color), "node": source})
			_start_swap(teacher, steps)
			_pick.phase = "swap"
		"swap":
			return _tick_swap(teacher)
	return false


## 手を順に伸ばして、置く・取る。steps: [{"where": Node3D / "box" / Vector3, "do": "put" | "take", "item", "color", "node"}]
func _start_swap(teacher, steps: Array) -> void:
	var from: Vector3 = teacher.hand_tip_point()
	_swap = {"steps": steps, "i": 0, "t": 0.0, "from": from, "start": from}
	teacher.ik_on(0.25)
	teacher.set_tip(from)


## 手を伸ばし（0.4 秒）、置く・取る、を steps の数だけ。最後に手を戻す（0.35 秒）。
func _tick_swap(teacher) -> bool:
	_swap.t = float(_swap.t) + get_process_delta_time()
	var steps: Array = _swap.steps
	var i := int(_swap.i)
	var t := float(_swap.t)
	if i < steps.size():
		var where: Variant = steps[i].where
		var at: Vector3 = (where if where is Vector3 else _tray_point(where)) + Vector3(0.0, 0.035, -0.03)
		if t < 0.4:
			teacher.set_tip((_swap.from as Vector3).lerp(at, smoothstep(0.0, 1.0, t / 0.4)))
		else:
			_swap_act(teacher, steps[i], at)
			_swap.from = at
			_swap.i = i + 1
			_swap.t = 0.0
		return false
	var back: Vector3 = (_swap.start as Vector3) + Vector3(0.0, 0.08, 0.0)
	if t < 0.35:
		teacher.set_tip((_swap.from as Vector3).lerp(back, smoothstep(0.0, 1.0, t / 0.35)))
		return false
	return true


func _swap_act(teacher, act: Dictionary, at: Vector3) -> void:
	if str(act.do) == "put":
		var spot: Vector3 = act.where if act.where is Vector3 else at
		_put_down(teacher, board_uv("F", spot).x)
		return
	if (_held_color != "" or _eraser_holder == teacher.key) and str(act.get("item", "")) != "tool":
		_put_down(teacher, board_uv("F", at).x - 0.14)
	if str(act.get("item", "")) == "eraser":
		_eraser_holder = teacher.key
	elif str(act.get("item", "")) == "tool":
		pass
	else:
		_held_color = str(act.get("color", "white"))
		_held_from = act.get("node") as Node3D
		if _held_from != null:
			_held_from.visible = false
		teacher.hold("R", _make_chalk(_held_color))
	_update_pointer_hand(teacher)


## 指し棒: 右手がチョークか黒板消しでふさがっていれば縮めて左手、空いていれば右手（縮めたまま）。
func _update_pointer_hand(teacher, extended := false) -> void:
	if teacher.key != "lecturer":
		return
	var busy: bool = _held_color != "" or _eraser_holder == teacher.key
	teacher.pointer_to("L" if busy else "R", extended and not busy)


## 持っているもの（チョーク・黒板消し）をチョーク受けの u の位置に置く（u < 0 なら元の場所）。
## チョーク受けの上の実物はそこへ動いて現れ、箱から出したチョークは箱へ戻す。
func _put_down(actor, u := -1.0) -> void:
	if actor.key == "lecturer" and _held_color != "":
		var chalk: Node3D = actor.drop("R")
		if chalk != null:
			chalk.queue_free()
		if _held_from != null:
			if u >= 0.0:
				var spot := _tray_spot(u, 0.02)
				_held_from.position = Vector3(spot.x, _held_from.position.y, spot.z + _rng.randf_range(-0.012, 0.012))
				_held_from.rotate_y(_rng.randf_range(-0.25, 0.25))
			_held_from.visible = true
		_held_from = null
		_held_color = ""
	if _eraser_holder == actor.key:
		_eraser_holder = ""
		var eraser: Node3D = _tray.get("eraser")
		if eraser != null:
			var home: Transform3D = _tray.eraser_home
			if u >= 0.0:
				var spot := _tray_spot(u, 0.06)
				eraser.transform = Transform3D(home.basis, spot) * Transform3D(Basis.IDENTITY, -_eraser_centre(eraser))
			else:
				eraser.transform = home
	_update_pointer_hand(actor)


## 黒板消し: 持っている人の手先に付いていき、黒板に当てている間は面に沿わせる（手は IK で背中に届く）。
func _place_held_props() -> void:
	if _stool_carry != "" and _stool_node != null and actors.has(_stool_carry):
		var carrier = actors[_stool_carry]
		var front: Vector3 = carrier.root.position + carrier.root.basis.z.normalized() * 0.42
		_stool_node.transform = Transform3D(_stool_home.basis.rotated(Vector3.UP, carrier.root.rotation.y),
			Vector3(front.x, 0.12 + 0.02 * absf(sin(_t * 12.0)), front.z))
	if _eraser_holder == "" or not _tray.has("eraser"):
		return
	var eraser: Node3D = _tray.eraser
	var actor = actors.get(_eraser_holder)
	if actor == null:
		return
	var pen: Dictionary = _pens.get(_eraser_holder, {})
	var basis := Basis.IDENTITY
	var at: Vector3 = actor.hand_tip_point()
	if not pen.is_empty() and pen.kind == "erase" and str(pen.phase) in ["down", "draw", "up", "travel"]:
		at = pen.get("tip_world", at)
		var wobble := 0.06 * sin(_t * 9.0) if pen.phase == "draw" else 0.0
		basis = Basis(Vector3.FORWARD, wobble)
		at += BOARD_IN * 0.026
	eraser.transform = Transform3D(basis, at) * Transform3D(Basis.IDENTITY, -_eraser_centre(eraser))


func _eraser_centre(eraser: Node3D) -> Vector3:
	var mesh_instance := eraser as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return Vector3.ZERO
	return mesh_instance.mesh.get_aabb().get_center()


## 消す段: 黒板消しの前へ行き、持っているチョークを手元に置いて黒板消しを取り、拭いて、拭き終えた手元に置く。
func _tick_erase(teacher) -> bool:
	match _phase:
		"begin":
			var at := _tray_point("eraser")
			var target := stance_root("F", board_uv("F", at).x + LEAD, 0.0)
			teacher.ik_off(0.2)
			teacher.walk_to(target, WRITE_YAW, "T_Idle")
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			var steps: Array = []
			if _held_color != "":
				steps.append({"where": _tray_spot(board_uv("F", _tray_point("eraser")).x - 0.2, 0.02), "do": "put"})
			steps.append({"where": "eraser", "do": "take", "item": "eraser"})
			_start_swap(teacher, steps)
			_phase = "take"
		"take":
			if not _tick_swap(teacher):
				return false
			if bool(step.get("wait_copy", false)) and actors.has("student_notes"):
				# 「まだ写してない！」: ノートの生徒が手を挙げる → 先生が振り向いてうなずき、写し終わるまで待つ
				_set_student("student_notes", "answer")
				(actors.student_notes).loop("S_RaiseHandEager")
				emote(actors.student_notes, "!", 1.4)
				teacher.face(CLASS_YAW - 20.0)
				_t = 0.0
				_phase = "waitcopy"
				return false
			_start_erase(teacher, "F", step.get("rect", [0.3, 0.0, 3.4, 0.6]), bool(step.get("messy", false)))
			var rect: Array = step.get("rect", [0.3, 0.0, 3.4, 0.6])
			_add_tray_dust(float(rect[0]), float(rect[2]))
			_phase = "wipe"
		"waitcopy":
			var notes = actors.student_notes
			if _t > 1.2 and _t - get_process_delta_time() <= 1.2:
				teacher.once("T_Nod", "T_Idle")
				notes.loop("S_FastWrite")
				_set_cue("frenzy", 3.0, "listen")
			if _t < 4.6:
				return false
			_set_student("student_notes", "")
			teacher.face(WRITE_YAW)
			_start_erase(teacher, "F", step.get("rect", [0.3, 0.0, 3.4, 0.6]), bool(step.get("messy", false)))
			var rect: Array = step.get("rect", [0.3, 0.0, 3.4, 0.6])
			_add_tray_dust(float(rect[0]), float(rect[2]))
			_phase = "wipe"
		"wipe":
			if _pens.has(teacher.key):
				return false
			var steps := _steps()
			if step_index + 1 < steps.size() and str((steps[step_index + 1] as Dictionary).get("do", "")) == "clap_erasers":
				return true
			_start_swap(teacher, [{"where": _tray_spot(board_uv("F", teacher.hand_tip_point()).x, 0.06), "do": "put"}])
			_phase = "put"
		"put":
			return _tick_swap(teacher)
	return false


## チョークがきしむ: 起きている生徒はびくっとし、寝ている生徒は飛び起きる。
func _squeak() -> void:
	last_event = "squeak"
	for key: String in _students:
		var brain: Dictionary = _students[key]
		if brain.mode != "" or not _seated.get(key, true):
			continue
		if brain.asleep:
			_wake_student(key)
		else:
			var student = actors[key]
			student.blink()
			student.kick(0.3)
			emote(student, "!", 1.1)
			student.once("S_WakeJolt", "S_SitIdle", 0.08)
			brain.until = student.clip_length("S_WakeJolt") * 0.8


## 一歩下がって板書を眺める: 書いたところの前 1.3 m に下がって黒板を向き、満足ならうなずき、
## 気に入らなければ首をかしげる（unhappy）。
func _tick_admire(teacher) -> bool:
	match _phase:
		"begin":
			var uv := _vec2(step.get("at", [1.2, 0.3]))
			var p := board_point("F", uv, 1.35)
			teacher.ik_off()
			teacher.walk_to(Vector3(p.x, 0.0, p.z), 0.0, "T_Idle")
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			_wait = teacher.once("T_HeadTilt" if step.get("unhappy", false) else "T_Nod", "T_Idle") + 0.3
			emote(teacher, "sweat" if step.get("unhappy", false) else "note", 1.5)
			_phase = "done"
		"done":
			return true
	return false


## 黒板消しを 2 つ打ち合わせる（頭の上で 3 回、粉の雲）→ ときどきその粉でくしゃみ → 黒板消しを置く。
func _tick_clap_erasers(teacher) -> bool:
	match _phase:
		"begin":
			teacher.ik_off()
			teacher.face(CLASS_YAW - 40.0)
			var eraser: Node3D = _tray.get("eraser")
			if eraser != null and eraser is MeshInstance3D:
				# 両手に 1 つずつ（右は今使ったもの、左はトレイのもう 1 つの代わり）
				_eraser_holder = ""
				eraser.visible = false
				teacher.pointer_visible(false)
				for side in ["R", "L"]:
					var copy := MeshInstance3D.new()
					copy.mesh = (eraser as MeshInstance3D).mesh
					copy.material_override = (eraser as MeshInstance3D).get_active_material(0)
					var centre := copy.mesh.get_aabb().get_center()
					teacher.hold(side, copy, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 0.2, 0.0) - centre))
					_clap_props.append(copy)
			var length: float = teacher.once("T_ClapErasers", "T_Idle")
			for k in range(3):
				_puff_later(0.54 + 0.42 * k, teacher, 2 + (1 if k == 2 else 0), 0.45, true)
			_wait = length + 0.1
			_phase = "sneeze" if _rng.randf() < 0.55 else "put"
		"sneeze":
			# 粉を吸ってくしゃみ（体ごとビクン）
			last_event = "dust_sneeze"
			_wait = teacher.once("T_Sneeze", "T_Idle")
			_puff_later(0.95, teacher, 1, 0.3)
			for key: String in STUDENTS:
				if actors.has(key):
					(actors[key]).blink()
			_phase = "put"
		"put":
			for side in ["R", "L"]:
				var item: Node3D = teacher.drop(side)
				if item != null:
					item.queue_free()
			_clap_props.clear()
			teacher.pointer_visible(true)
			var eraser: Node3D = _tray.get("eraser")
			if eraser != null:
				_eraser_holder = teacher.key
				eraser.visible = true
				_start_swap(teacher, [{"where": _tray_spot(board_uv("F", teacher.hand_tip_point()).x, 0.06), "do": "put"}])
				_phase = "putting"
			else:
				return true
		"putting":
			return _tick_swap(teacher)
	return false


## 落書き（照明が点く前、暗い中で先生が黒板にゴドーくんの顔を描いている）。照明が点いたら止める。
func _tick_doodle(teacher) -> bool:
	var lit := float(_set.call("lit")) if _set.has_method("lit") else 1.0
	match _phase:
		"begin":
			_held_color = "white"
			teacher.hold("R", _make_chalk("white"))
			_update_pointer_hand(teacher)
			var c := _vec2(step.get("at", [2.2, 0.3]))
			var r := 0.16
			var strokes: Array = []
			strokes.append(_circle(c, r, 0.0, TAU * 1.02, 30))
			for k in [-1, 0, 1]:
				# 頭の上の 3 本の歯
				var base := c + Vector2(0.075 * k, r * 0.97)
				strokes.append(PackedVector2Array([base + Vector2(-0.03, -0.01), base + Vector2(-0.025, 0.05),
					base + Vector2(0.025, 0.05), base + Vector2(0.03, -0.01)]))
			for side in [-1.0, 1.0]:
				strokes.append(_circle(c + Vector2(0.065 * side, 0.03), 0.042, 0.0, TAU * 1.02, 14))
				strokes.append(PackedVector2Array([c + Vector2(0.065 * side - 0.004, 0.03), c + Vector2(0.065 * side + 0.004, 0.032)]))
			strokes.append(PackedVector2Array([c + Vector2(-0.12, -0.06), c + Vector2(-0.07, -0.06), c + Vector2(-0.05, -0.09),
				c + Vector2(-0.02, -0.09), c + Vector2(0.0, -0.06), c + Vector2(0.02, -0.09), c + Vector2(0.05, -0.09),
				c + Vector2(0.07, -0.06), c + Vector2(0.12, -0.06)]))
			_pens[teacher.key] = {"kind": "write", "actor": teacher, "board": "F", "strokes": strokes, "si": 0, "pi": 0,
				"phase": "approach", "pos": Vector2.ZERO, "lift": 0.12, "color": "white", "id": 0, "shoulder_u": -99.0,
				"top_v": c.y + r, "pressure": 1.0, "drawn": 0.0, "break_at": -1}
			_phase = "draw"
		"draw":
			if lit >= 0.5:
				# 点いた！ 書きかけで止める
				var pen: Dictionary = _pens.get(teacher.key, {})
				if not pen.is_empty() and int(pen.id) > 0:
					_canvas("F").end_stroke(int(pen.id))
				_pens.erase(teacher.key)
				_dust.emitting = false
				return true
			if not _pens.has(teacher.key):
				teacher.loop("T_Idle")
	return false


## 照明が点いた瞬間: 全員がその場で固まる（だるまさんがころんだ）→ ！
func _tick_freeze(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "freeze"
			teacher.ik_off(0.1)
			teacher.once("T_Startle", "T_Idle", 0.08)
			_fx.append({"kind": "emote", "t": 0.0, "secs": 0.3, "actor": teacher, "emote": "!", "len": 1.3})
			var k := 0
			for key: String in STUDENTS:
				if actors.has(key) and not _seated.get(key, true):
					(actors[key]).once("G_Freeze", "G_Idle", 0.06)
					_fx.append({"kind": "emote", "t": 0.0, "secs": 0.45 + 0.15 * k, "actor": actors[key], "emote": "!", "len": 1.1})
					k += 1
			_wait = 1.6
			_phase = "done"
		"done":
			return true
	return false


## 席へ戻る（走る）。着いたら座る。
func _go_seat(key: String) -> void:
	var actor = actors[key]
	var seat: Vector3 = _seats.get(key, SEATS[key])
	_set_student(key, "go_seat")
	actor.walk_to(seat + Vector3(0.55, 0.0, 0.0), 0.0, "G_Idle", "G_Run", 1.9)


## 日直の号令: 起立 → 礼（先生も生徒も日直も）→ 着席（項目 85・95）。
func _tick_rei() -> bool:
	var teacher = actors.lecturer
	var duty = actors.get("duty")
	match _phase:
		"begin":
			last_event = "rei"
			for key: String in STUDENTS:
				if actors.has(key) and _seated.get(key, true) and str(_students[key].mode) != "go_seat":
					_set_student(key, "answer")
			if duty != null:
				_show_extra("duty")
				duty.walk_to(DUTY_CALL, rad_to_deg(atan2(-DUTY_CALL.x, 0.74 - DUTY_CALL.z)), "G_Idle")
			teacher.face(CLASS_YAW)
			_phase = "walk"
		"walk":
			for key: String in STUDENTS:
				if actors.has(key) and str(_students[key].mode) == "go_seat":
					return false
			if duty != null and duty.is_busy():
				return false
			# 起立！
			if duty != null:
				duty.kick(0.25)
				emote(duty, "!", 1.0)
			var stand := 0.0
			for key: String in STUDENTS:
				if actors.has(key):
					_set_student(key, "answer")
					var student = actors[key]
					stand = maxf(stand, student.once("S_StandUp", "G_Idle", 0.15))
			_wait = maxf(0.0, stand - 0.04)
			_phase = "stood"
		"stood":
			for key: String in STUDENTS:
				if actors.has(key):
					_stand_offset(key, true)
					(actors[key]).loop("G_Idle", 0.0)
			_wait = 0.6
			_phase = "bow"
		"bow":
			# 礼！
			if duty != null:
				emote(duty, "!", 0.9)
				duty.once("G_Bow", "G_Idle")
			_wait = teacher.once("T_Bow", "T_Idle")
			for key: String in STUDENTS:
				if actors.has(key):
					(actors[key]).once("G_Bow", "G_Idle")
			_phase = "sit"
		"sit":
			# 着席
			var sit := 0.0
			for key: String in STUDENTS:
				if actors.has(key):
					_stand_offset(key, false)
					sit = maxf(sit, (actors[key]).once("S_SitDown", "S_SitIdle", 0.0))
			_wait = sit + 0.2
			_phase = "seated"
		"seated":
			for key: String in STUDENTS:
				_set_student(key, "")
			if duty != null:
				duty.walk_to(EXTRAS.duty.from, NAN, "G_Idle")
				_leave_when_arrived("duty")
			return true
	return false


## 長居: 1 段目 = 踏み台に腰かけて採点（40 秒）、2 段目 = 採点しながら居眠り → はっと起きて時計を見る。
func _tick_long_stay(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "long_stay_%d" % int(step.stage)
			_put_down(teacher)
			teacher.ik_off()
			teacher.walk_to(_stool_pos() + Vector3(0.0, 0.0, -0.55), 160.0, "T_Idle")
			_set_cue("notes")
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			teacher.root.position = _stool_pos()
			teacher.loop("T_SitGrade", 0.3)
			_t = 0.0
			_phase = "grade"
		"grade":
			if int(step.stage) == 2 and _t > 8.0 and teacher.eyes_mode == "open":
				# だんだんまぶたが重く……
				teacher.set_eyes("half")
			if int(step.stage) == 2 and _t > 14.0 and teacher.eyes_mode == "half":
				teacher.set_eyes("closed")
				teacher.loop("T_DozeStand", 0.6)
				_fx.append({"kind": "emote", "t": 0.0, "secs": 0.5, "actor": teacher, "emote": "dots", "len": 4.0})
			if _t < (40.0 if int(step.stage) == 1 else 34.0):
				return false
			if int(step.stage) == 2:
				teacher.set_eyes("open")
				teacher.blink()
				teacher.once("T_Startle", "T_Idle", 0.1)
				emote(teacher, "!", 1.2)
			teacher.root.position = _stool_pos() + Vector3(0.0, 0.0, -0.55)
			teacher.loop("T_Idle", 0.3)
			_wait = 1.2
			_phase = "clock"
		"clock":
			teacher.face_point(CLOCK_POINT)
			_wait = teacher.once("T_LookClock", "T_Idle")
			_phase = "done"
		"done":
			_set_cue("listen")
			return true
	return false


# ------------------------------------------------------------------ settings screen hooks（項目 96〜102）

## 効果音の試し鳴らし: 起きている生徒が音のほう（カメラの側）へ振り向き、先生は首をかしげる。
func on_sfx_test() -> void:
	last_event = "sfx_test"
	for key: String in STUDENTS:
		if not actors.has(key):
			continue
		var brain: Dictionary = _students[key]
		if brain.mode != "" or brain.asleep or not _seated.get(key, true):
			continue
		var student = actors[key]
		student.once("S_TurnLeft", "S_SitIdle", 0.12)
		brain.until = student.clip_length("S_TurnLeft")
		_fx.append({"kind": "emote", "t": 0.0, "secs": 0.25 + 0.15 * _rng.randf(), "actor": student, "emote": "?", "len": 1.2})
	var teacher = actors.lecturer
	if not _pens.has(teacher.key) and not teacher.is_moving():
		teacher.once("T_HeadTilt", teacher.base_clip if teacher.base_clip != "" else "T_Idle")


## 画質を変えた: 先生の眼鏡がキラーンと光り、頭の上に「！」。
func on_quality_changed() -> void:
	last_event = "quality"
	var teacher = actors.lecturer
	emote(teacher, "!", 1.2)
	var glasses: Vector3 = teacher.head_point() + Vector3(0.0, -0.57, 0.0) + teacher.root.basis.z.normalized() * 0.55
	_glint(glasses)


## 戻る: 全員がこちらを向いて手を振る（座っている生徒は手を挙げて振る）。
func goodbye() -> void:
	last_event = "goodbye"
	_farewell = true
	save_boards()
	var teacher = actors.lecturer
	var camera := get_viewport().get_camera_3d()
	paused = false
	_pens.clear()
	teacher.ik_off(0.15)
	if camera != null:
		teacher.face_point(_set.to_local(camera.global_position))
	teacher.once("T_Wave", "T_Idle", 0.15)
	emote(teacher, "note", 1.5)
	for key: String in STUDENTS:
		if not actors.has(key):
			continue
		var student = actors[key]
		_students[key].mode = "answer"
		if key == "student_doze" and bool(_students[key].asleep):
			continue
		student.loop("S_RaiseHandEager" if _seated.get(key, true) else "G_WaveBoth", 0.15)
	if actors.has("trainee"):
		(actors.trainee).once("G_Wave", "P_Clipboard", 0.2)
	for key: String in EXTRAS:
		if _extras_visible.get(key, false):
			(actors[key]).once("G_Wave", "G_Idle", 0.2)


## 3D の人物をクリックした（項目 102）: 先生は指し返し、居眠りは起き、生徒はびくっと振り向き、練習生は跳ぶ。
func on_click(key: String) -> void:
	var actor = actors.get(key)
	if actor == null:
		return
	last_event = "click_" + key
	match key:
		"lecturer":
			var camera := get_viewport().get_camera_3d()
			if not _pens.has(key) and camera != null:
				actor.face_point(_set.to_local(camera.global_position))
				actor.once("T_PointTap", actor.base_clip if actor.base_clip != "" else "T_Idle", 0.15)
			emote(actor, "!", 1.2)
		"student_doze":
			if bool(_students[key].asleep) or float(_students[key].drowsy) > DOZE_DRIFT:
				_wake_student(key)
			else:
				emote(actor, "?", 1.2)
		"trainee":
			_trainee_jump(["P_Fast", "P_Double", "P_JumpEarly"][_rng.randi() % 3])
		_:
			if _students.has(key):
				var brain: Dictionary = _students[key]
				if brain.mode == "" and _seated.get(key, true):
					actor.once("S_TurnLeft", "S_SitIdle", 0.1)
					brain.until = actor.clip_length("S_TurnLeft")
				emote(actor, "!", 1.1)
			else:
				actor.once("G_Wave", "G_Idle", 0.15)
				emote(actor, "note", 1.2)


## 画面上の点（ビューポートの座標）にいちばん近い人物の key（いなければ ""）。体を球で近似する。
func pick_actor(screen_pos: Vector2) -> String:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return ""
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best := ""
	var best_t := INF
	for key: String in actors:
		var actor = actors[key]
		if not actor.root.is_visible_in_tree():
			continue
		var centre: Vector3 = actor.root.global_position + Vector3.UP * (0.95 if key.begins_with("student") else 0.85)
		var radius := 0.62
		var oc := origin - centre
		var b := oc.dot(dir)
		var c := oc.dot(oc) - radius * radius
		var disc := b * b - c
		if disc < 0.0:
			continue
		var t := -b - sqrt(disc)
		if t > 0.0 and t < best_t:
			best_t = t
			best = key
	return best


func _glint(at: Vector3) -> void:
	if _glint_texture == null:
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in range(64):
			for x in range(64):
				var p := Vector2(x - 31.5, y - 31.5) / 31.5
				var star := maxf(0.0, 1.0 - absf(p.x) * 9.0 - absf(p.y) * 1.0) + maxf(0.0, 1.0 - absf(p.y) * 9.0 - absf(p.x) * 1.0)
				var core := maxf(0.0, 1.0 - p.length() * 3.0)
				image.set_pixel(x, y, Color(1, 1, 1, clampf(star + core, 0.0, 1.0)))
		_glint_texture = ImageTexture.create_from_image(image)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = _glint_texture
	material.albedo_color = Color(1.0, 0.97, 0.85)
	material.no_depth_test = true
	quad.material = material
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.position = at
	node.scale = Vector3.ONE * 0.001
	_set.add_child(node)
	_fx.append({"kind": "glint", "node": node, "t": 0.0, "secs": 0.6})


# ------------------------------------------------------------------ trainee（練習生: 項目 79〜84）

## 練習生: クリップボードに記録 → 跳び越え（成功・早すぎ・遅すぎ・上級）→ 成功なら生徒が拍手してお辞儀、
## 失敗なら汗をかいて顔をあおぐ。先生の説明（放物線を描いた直後）では実演する。
func _tick_trainee(delta: float) -> void:
	if _trainee.is_empty():
		return
	var trainee = actors.trainee
	_trainee.next = float(_trainee.next) - delta
	if float(_trainee.next) > 0.0:
		return
	match str(_trainee.mode):
		"rest":
			var pool := ["Practice", "Practice", "P_JumpEarly", "P_JumpLate", "P_Double", "P_Fast", "P_Reverse"]
			_trainee_jump(pool[_rng.randi() % pool.size()])
		"jump":
			var clip := str(_trainee.clip)
			if clip in ["P_JumpEarly", "P_JumpLate"]:
				# 失敗: 汗 → ヘルメットであおぐ
				emote(trainee, "sweat", 1.8)
				trainee.loop("P_FanSelf", 0.25)
				_trainee.next = _rng.randf_range(4.0, 6.0)
				_trainee.mode = "fan"
			else:
				# 成功: 生徒が拍手、練習生がお辞儀
				emote(trainee, "note", 1.4)
				_trainee.next = trainee.once("G_Bow", "P_Clipboard") + 0.2
				_trainee.mode = "bow"
				if _cue in ["listen", "notes", "look_up"]:
					_set_cue("clap", 2.2, _cue)
		"fan", "bow":
			trainee.loop("P_Clipboard", 0.3)
			_trainee.next = _rng.randf_range(8.0, 16.0)
			_trainee.mode = "rest"


func _trainee_jump(clip: String) -> void:
	if _trainee.is_empty():
		return
	var trainee = actors.trainee
	if not trainee.has_clip(clip):
		clip = "Practice"
	var length: float = trainee.once(clip, "P_Clipboard", 0.25) if clip != "Practice" else trainee.clip_length("Practice")
	if clip == "Practice":
		trainee.loop("Practice", 0.25)
	_trainee.clip = clip
	_trainee.mode = "jump"
	_trainee.next = length + 0.1


## 先生が笛を吹き、練習生が実演する（放物線を描いた直後: 項目 80・84）。
func _tick_trainee_demo() -> bool:
	var teacher = actors.lecturer
	match _phase:
		"begin":
			if _trainee.is_empty():
				return true
			teacher.ik_off()
			teacher.face_point((actors.trainee).root.position)
			_set_cue("look_up")
			_phase = "turn"
		"turn":
			if teacher.is_busy():
				return false
			_wait = teacher.once("T_Whistle", "T_Idle") * 0.7
			_phase = "jump"
		"jump":
			_trainee_jump("P_Fast")
			_wait = float(_trainee.next) + 0.4
			_phase = "done"
		"done":
			_set_cue("listen")
			return true
	return false


## 出席（項目 43）: 教卓で出席簿を開き、1 人ずつ名前を呼ぶ → 手が挙がる → うなずく。居眠り役は返事がなく、
## 隣が振り向いてから飛び起きて遅れて手を挙げる。
func _tick_roll_call(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "roll_call"
			teacher.ik_off()
			teacher.walk_to(LECTERN_SPOT, CLASS_YAW, "T_Idle")
			_roll = STUDENTS.filter(func(k: String) -> bool: return actors.has(k))
			if _students.has("student_doze") and not bool(_students.student_doze.asleep):
				_students.student_doze.drowsy = DOZE_DRIFT + 2.0
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			_phase = "call"
		"call":
			if _roll.is_empty():
				return true
			var key: String = _roll.pop_front()
			var student = actors[key]
			teacher.kick(0.12)
			teacher.look_toward(student.head_point(), 1.0)
			_roll_key = key
			if key == "student_doze" and (bool(_students[key].asleep) or float(_students[key].drowsy) > DOZE_DRIFT):
				_wait = 1.6
				_phase = "no_answer"
			else:
				_wait = 0.5
				_phase = "answer"
		"answer":
			var student = actors[_roll_key]
			_set_student(_roll_key, "answer")
			student.loop_for("S_RaiseHand", 1.3, "S_SitIdle")
			emote(student, "!", 1.0)
			_wait = 1.4
			_phase = "nod"
		"no_answer":
			emote(teacher, "?", 1.4)
			if actors.has("student_notes"):
				(actors.student_notes).once("S_TurnLeft", "S_SitIdle")
			_wait = 1.3
			_phase = "late"
		"late":
			_wake_student("student_doze")
			_wait = 0.9
			_phase = "answer"
		"nod":
			_set_student(_roll_key, "")
			teacher.once("T_Nod", "T_Idle")
			_wait = 0.6
			_phase = "call"
	return false


## 机の間を回る（項目 44）: 通路を歩いてノートの生徒の脇へ行き、覗き込む → 慌てて隠す → うなずいて戻る。
func _tick_patrol(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "patrol"
			_put_down(teacher)
			teacher.ik_off()
			_route = [Vector3(1.15, 0.0, 2.45), Vector3(1.15, 0.0, 0.0), Vector3(-1.2, 0.0, -0.05), Vector3(-1.65, 0.0, 0.25)]
			_phase = "go"
		"go":
			if teacher.is_busy():
				return false
			if not _route.is_empty():
				teacher.walk_to(_route.pop_front(), NAN, "T_Idle")
				return false
			var notes = actors.get("student_notes")
			if notes == null:
				_phase = "back"
				return false
			teacher.face_point(Vector3(-2.3, 0.0, 1.6))
			_phase = "peek"
		"peek":
			if teacher.is_busy():
				return false
			var notes = actors.student_notes
			teacher.kick(0.2)
			teacher.once("T_HeadTilt", "T_Idle")
			_set_student("student_notes", "answer")
			notes.once("S_HideNotes", "S_CopyNotes")
			emote(notes, "sweat", 1.8)
			_wait = 1.8
			_phase = "nod"
		"nod":
			teacher.once("T_Nod", "T_Idle")
			emote(teacher, "note", 1.3)
			_set_student("student_notes", "")
			_wait = 1.0
			_route = [Vector3(-1.2, 0.0, -0.05), Vector3(1.15, 0.0, 0.0), Vector3(1.15, 0.0, 2.45), LECTERN_SPOT]
			_phase = "back"
		"back":
			if teacher.is_busy():
				return false
			if not _route.is_empty():
				teacher.walk_to(_route.pop_front(), CLASS_YAW if _route.is_empty() else NAN, "T_Idle")
				return false
			return true
	return false


## 黒板を向いたまま夢中で話す → 生徒がひとりずつ眠る → 振り向くと全員寝ている（眼鏡がキラーン）→ びっくり、
## 全員飛び起きる（項目 46・47）。
func _tick_talk_board(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "talk_board"
			_put_down(teacher)
			teacher.ik_off()
			var p := board_point("F", Vector2(1.6, 0.3), 1.0)
			teacher.walk_to(Vector3(p.x, 0.0, p.z), 0.0, "T_Explain")
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			teacher.loop("T_Explain")
			_t = 0.0
			_slept = 0
			_phase = "talk"
		"talk":
			# 3 秒ごとにひとりずつ眠る
			var order := ["student_doze", "student_hand", "student_notes"]
			if _slept < order.size() and _t > 1.5 + 2.6 * _slept:
				var key: String = order[_slept]
				if actors.has(key):
					var student = actors[key]
					_set_student(key, "answer")
					student.set_eyes("closed")
					student.once("S_Faceplant", "S_SleepSlumped")
					if key == "student_doze":
						_students[key].asleep = true
				_slept += 1
			if _t < 10.0:
				return false
			teacher.face(CLASS_YAW)
			_phase = "turn"
		"turn":
			if teacher.is_busy():
				return false
			var glasses: Vector3 = teacher.head_point() + Vector3(0.0, -0.57, 0.0) + teacher.root.basis.z.normalized() * 0.55
			_glint(glasses)
			teacher.once("T_Startle", "T_Idle", 0.08)
			emote(teacher, "!", 1.4)
			_wait = 1.0
			_phase = "wake"
		"wake":
			for key: String in STUDENTS:
				if actors.has(key):
					_wake_student(key)
					_set_student(key, "")
			emote(teacher, "anger", 1.6)
			_wait = 1.8
			_phase = "done"
		"done":
			return true
	return false


# ------------------------------------------------------------------ day scenes（項目 86〜92）

## 時間帯の場面の始まり: 生徒の居場所と小道具をそろえる。
func _begin_mode_scene() -> void:
	match day_mode:
		"night":
			for key: String in STUDENTS:
				if actors.has(key):
					(actors[key]).root.visible = false
					(actors[key]).root.process_mode = Node.PROCESS_MODE_DISABLED
					_set_student(key, "away")
			if actors.has("trainee"):
				(actors.trainee).root.visible = false
				(actors.trainee).root.process_mode = Node.PROCESS_MODE_DISABLED
				_trainee = {}
		"lunch":
			for k: int in _desk_groups:
				for item: Dictionary in _desk_groups[k]:
					if str((item.node as Node).name).begins_with("PRP_Bento"):
						(item.node as Node3D).visible = true
			for key: String in STUDENTS:
				_set_student(key, "lunch")
				if actors.has(key):
					(actors[key]).loop("S_Eat", 0.0)


## お弁当（項目 89）: 生徒は弁当へ体ごと倒れてパクッ、ときどき隣としゃべる。先生は教卓で湯呑み。
## 時間になったら弁当をしまう。
func _tick_lunch(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "lunch"
			teacher.walk_to(DRINK_SPOT, CLASS_YAW, "T_Idle")
			_t = 0.0
			_phase = "eat"
		"eat":
			if not teacher.is_busy() and fmod(_t, 12.0) < get_process_delta_time():
				teacher.once("T_Drink", "T_Idle")
				_fx.append({"kind": "emote", "t": 0.0, "secs": 1.4, "actor": teacher, "emote": "note", "len": 1.2})
			for key: String in STUDENTS:
				if not actors.has(key) or not _students.has(key):
					continue
				var brain: Dictionary = _students[key]
				brain.next = float(brain.next) - get_process_delta_time()
				if float(brain.next) <= 0.0:
					brain.next = _rng.randf_range(3.0, 7.0)
					var student = actors[key]
					var roll := _rng.randf()
					if roll < 0.2:
						student.once("S_TurnLeft" if _rng.randf() < 0.5 else "S_TurnRight", "S_Eat")
						emote(student, "note", 1.0)
					elif roll < 0.3:
						student.once("S_LookBoard", "S_Eat")
			if _t < float(step.get("secs", 45.0)):
				return false
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					(actors[key]).loop("S_SitIdle", 0.3)
					_set_student(key, "")
			_wait = 1.8
			_phase = "put_away"
		"put_away":
			for k: int in _desk_groups:
				for item: Dictionary in _desk_groups[k]:
					if str((item.node as Node).name).begins_with("PRP_Bento"):
						(item.node as Node3D).visible = false
			_wait = 1.0
			_phase = "done"
		"done":
			return true
	return false


## 放課後の掃除（項目 90・37・38）: 用務員がほうきで掃き、生徒は椅子を机に上げて机を後ろへ押し、日直は
## 黒板消しクリーナー、先生は濡れ雑巾で黒板を拭く（濃い緑 → 乾いて戻る）。最後に元へ戻す。
func _tick_cleaning(teacher) -> bool:
	var janitor = actors.get("janitor")
	var duty = actors.get("duty")
	match _phase:
		"begin":
			last_event = "cleaning"
			_t = 0.0
			if janitor != null:
				_show_extra("janitor")
				_give_tool(janitor, "PRP_Broom")
				janitor.walk_to(SWEEP_ROUTE[0], NAN, "G_Sweep", "G_Walk")
				_route = SWEEP_ROUTE.duplicate()
			if duty != null:
				_show_extra("duty")
				duty.walk_to(CLEANER_SPOT, -90.0, "G_Idle")
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					_set_student(key, "answer")
			_phase = "stand"
			_wait = 0.5
		"stand":
			# 立って、椅子を机の上へ逆さに載せる
			var stand := 0.0
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					stand = maxf(stand, (actors[key]).once("S_StandUp", "G_Idle", 0.15))
			_wait = maxf(0.0, stand - 0.04)
			_phase = "stools"
		"stools":
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					_stand_offset(key, true)
					(actors[key]).loop("G_Idle", 0.0)
			for k: int in _desk_groups:
				var desk_centre := _mesh_centre(_desk_groups[k][0].node, _desk_groups[k][0].home)
				for item: Dictionary in _desk_groups[k]:
					if item.stool:
						# 机の天板（0.725 m）の上に逆さに（丸椅子の高さ 0.45 m）
						var node := item.node as MeshInstance3D
						var home: Transform3D = item.home
						var c := node.mesh.get_aabb().get_center() if node != null and node.mesh != null else Vector3.ZERO
						var target := Vector3(desk_centre.x, 0.725 + 0.23, desk_centre.z)
						(item.node as Node3D).transform = Transform3D(Basis(Vector3.RIGHT, PI) * home.basis, target) 							* Transform3D(Basis.IDENTITY, -c)
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					var seat: Vector3 = _seats.get(key, SEATS[key])
					(actors[key]).walk_to(Vector3(seat.x, 0.0, 2.42), 180.0, "G_Idle")
			_phase = "to_desks"
		"to_desks":
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key) and (actors[key]).is_busy():
					return false
			_phase = "push"
			_t = 0.0
		"push":
			# 机を後ろ（カメラ側、-Z）へ 0.8 m 押す
			var u := clampf(_t / 4.0, 0.0, 1.0)
			if _t < get_process_delta_time() * 1.5:
				for key: String in STUDENTS:
					if actors.has(key) and _students.has(key):
						var student = actors[key]
						student.root.rotation.y = PI
						student.face(180.0)
						student.loop("G_PushDesk", 0.2)
			for k: int in _desk_groups:
				for item: Dictionary in _desk_groups[k]:
					var node: Node3D = item.node
					if not item.has("lifted"):
						item.lifted = node.transform
					var base: Transform3D = item.lifted
					node.transform = Transform3D(base.basis, base.origin + Vector3(0.0, 0.0, -0.8 * smoothstep(0.0, 1.0, u)))
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					var seat: Vector3 = _seats.get(key, SEATS[key])
					(actors[key]).root.position = Vector3(seat.x, 0.0, 2.42 - 0.8 * smoothstep(0.0, 1.0, u))
			if u < 1.0:
				return false
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					(actors[key]).loop("G_Idle", 0.3)
			_phase = "rag"
		"rag":
			# 先生: バケツの雑巾を取りに行く
			_put_down(teacher)
			teacher.ik_off()
			teacher.walk_to(BUCKET_SPOT, -120.0, "T_Idle")
			_phase = "to_bucket"
		"to_bucket":
			_tick_sweeper(janitor)
			_tick_cleaner(duty)
			if teacher.is_busy():
				return false
			teacher.once("T_CrouchPickup", "T_Idle")
			_wait = 1.1
			_phase = "got_rag"
		"got_rag":
			_give_tool(teacher, "PRP_Rag")
			teacher.walk_to(stance_root("F", 0.45, 0.4), WRITE_YAW, "T_Idle")
			_phase = "to_board"
		"to_board":
			_tick_sweeper(janitor)
			_tick_cleaner(duty)
			if teacher.is_busy():
				return false
			var strokes: Array = []
			var u := 0.35
			while u < 3.8:
				strokes.append(PackedVector2Array([Vector2(u, 0.55), Vector2(u + 0.05, 0.08), Vector2(u + 0.16, 0.55)]))
				u += 0.32
			_pens[teacher.key] = {"kind": "wet", "actor": teacher, "board": "F", "strokes": strokes, "si": 0, "pi": 0,
				"phase": "approach", "pos": Vector2.ZERO, "lift": 0.12, "color": "", "id": 0, "shoulder_u": -99.0,
				"top_v": 0.55, "pressure": 1.0, "drawn": 0.0, "break_at": -1}
			_phase = "wiping"
		"wiping":
			_tick_sweeper(janitor)
			_tick_cleaner(duty)
			if _pens.has(teacher.key):
				return false
			_take_tool(teacher)
			_clear_tray_dust()
			_phase = "restore"
			_t = 0.0
		"restore":
			_tick_sweeper(janitor)
			_tick_cleaner(duty)
			if _t < 2.0:
				return false
			# 机を戻し、椅子を下ろし、道具を片づける
			for k: int in _desk_groups:
				for item: Dictionary in _desk_groups[k]:
					(item.node as Node3D).transform = item.home
					item.erase("lifted")
			if janitor != null:
				_take_tool(janitor)
				janitor.walk_to(EXTRAS.janitor.from, NAN, "G_Idle")
				_leave_when_arrived("janitor")
			if duty != null:
				_stop_cleaner()
				duty.walk_to(EXTRAS.duty.from, NAN, "G_Idle")
				_leave_when_arrived("duty")
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					var seat: Vector3 = _seats.get(key, SEATS[key])
					(actors[key]).root.position = seat + Vector3(0.55, 0.0, 0.0)
					(actors[key]).root.rotation.y = 0.0
					(actors[key]).face(0.0)
					_seated[key] = false
					_go_seat(key)
			return true
	return false


func _tick_sweeper(janitor) -> void:
	if janitor == null or janitor.is_moving():
		return
	if _route.is_empty():
		_route = SWEEP_ROUTE.duplicate()
	janitor.walk_to(_route.pop_front(), NAN, "G_Sweep", "G_Sweep", 0.4)
	if _rng.randf() < 0.5:
		_puff(janitor.root.position + janitor.root.basis.z * 0.4, 0, -0.5)


func _tick_cleaner(duty) -> void:
	if duty == null or duty.is_moving():
		return
	if not _cleaner_running:
		_cleaner_running = true
		duty.loop("G_Idle")
	var eraser: Node3D = _tray.get("PRP_Eraser_1")
	if eraser != null:
		var home: Transform3D = _tool_home["PRP_Eraser_1"]
		eraser.transform = Transform3D(home.basis, home.origin + Vector3(_rng.randf_range(-0.004, 0.004), 0.0, _rng.randf_range(-0.004, 0.004)))
	if _rng.randf() < 0.02:
		_puff(CLEANER_SPOT + Vector3(-0.6, 1.0, 0.4), 0, -0.6)


func _stop_cleaner() -> void:
	_cleaner_running = false
	var eraser: Node3D = _tray.get("PRP_Eraser_1")
	if eraser != null:
		eraser.transform = _tool_home["PRP_Eraser_1"]


## メッシュの中心（セットのローカル、home の置き方のとき）。
func _mesh_centre(node: Node3D, home: Transform3D) -> Vector3:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return home.origin
	return home * mesh_instance.mesh.get_aabb().get_center()


## 道具（ほうき・雑巾）を手に持たせる（元の場所の実物は隠し、同じメッシュの写しを持つ）。
func _give_tool(actor, name: String) -> void:
	var node: MeshInstance3D = _tray.get(name) as MeshInstance3D
	if node == null:
		return
	node.visible = false
	var copy := MeshInstance3D.new()
	copy.mesh = node.mesh
	for i in range(node.mesh.get_surface_count()):
		copy.set_surface_override_material(i, node.get_active_material(i))
	var centre := node.mesh.get_aabb().get_center()
	var offset := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) if name == "PRP_Broom" else Basis.IDENTITY,
		Vector3(0.0, 0.26, 0.0)) * Transform3D(Basis.IDENTITY, -centre)
	actor.hold("R", copy, offset)
	_held_tool[actor.key] = name


func _take_tool(actor) -> void:
	if not _held_tool.has(actor.key):
		return
	var name: String = _held_tool[actor.key]
	_held_tool.erase(actor.key)
	var item: Node3D = actor.drop("R")
	if item != null:
		item.queue_free()
	var node: Node3D = _tray.get(name)
	if node != null:
		node.visible = true


## 夜（項目 91）: 生徒はいない。先生は踏み台を教卓の脇へ運び（項目 28 の運び方）、腰かけて電気スタンドの下で採点。
## 部屋の照明は落ちている。しばらくして時計を見て、照明が戻り、夜間補講の生徒が入ってくる。
func _tick_night(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "night"
			if _set.has_method("set_mood"):
				_set.call("set_mood", 1.0)
			if _lamp != null:
				_lamp.visible = true
				_lamp.light_energy = 3.0
			teacher.ik_off()
			teacher.root.position = Vector3(-2.6, 0.0, 7.2)
			if _stool_node != null:
				teacher.walk_to(_stool_home.origin + Vector3(0.55, 0.0, -0.45), -90.0, "T_Idle")
			_phase = "to_stool"
		"to_stool":
			if teacher.is_busy():
				return false
			teacher.once("T_CrouchPickup", "T_Carry")
			_wait = 1.0
			_phase = "carry"
		"carry":
			_stool_carry = teacher.key
			teacher.walk_to(NIGHT_STOOL + Vector3(0.0, 0.0, -0.6), 180.0, "T_Idle", "T_Carry", 0.6)
			_phase = "carrying"
		"carrying":
			if teacher.is_busy():
				return false
			_stool_carry = ""
			if _stool_node != null:
				_stool_node.transform = Transform3D(_stool_home.basis, NIGHT_STOOL + Vector3(0.0, _stool_home.origin.y, 0.0))
			teacher.root.position = NIGHT_STOOL
			teacher.root.rotation.y = deg_to_rad(200.0)
			teacher.face(200.0)
			teacher.loop("T_SitGrade", 0.3)
			_t = 0.0
			_phase = "grade"
		"grade":
			if fmod(_t, 14.0) < get_process_delta_time() and _t > 1.0:
				teacher.kick(0.1)
				_fx.append({"kind": "emote", "t": 0.0, "secs": 0.2, "actor": teacher, "emote": "note", "len": 1.0})
			if _t < float(step.get("secs", 40.0)):
				return false
			teacher.root.position = NIGHT_STOOL + Vector3(0.0, 0.0, -0.6)
			teacher.loop("T_Idle", 0.2)
			teacher.face_point(CLOCK_POINT)
			_phase = "clock"
		"clock":
			if teacher.is_busy():
				return false
			_wait = teacher.once("T_LookClock", "T_Idle")
			emote(teacher, "!", 1.2)
			_phase = "lights"
		"lights":
			if _set.has_method("set_mood"):
				_set.call("set_mood", 0.0)
			if _lamp != null:
				_lamp.visible = false
			# 夜間補講の生徒が入ってくる
			for key: String in STUDENTS:
				if actors.has(key):
					var student = actors[key]
					student.root.visible = true
					student.root.process_mode = Node.PROCESS_MODE_INHERIT
					student.root.position = Vector3(5.2, 0.0, 2.4 + 0.6 * STUDENTS.find(key))
					_seated[key] = false
					_set_student(key, "")
					_go_seat(key)
			_wait = 1.0
			_phase = "done"
		"done":
			return true
	return false


## 休み時間（項目 87）: 生徒は立って伸び・おしゃべり・展示台の模型を見に行く。先生は湯呑み。
## 時間になったら席へ戻る。
func _tick_break(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "break"
			_put_down(teacher)
			teacher.ik_off()
			teacher.walk_to(DRINK_SPOT, CLASS_YAW, "T_Idle")
			var stand := 0.0
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key):
					if bool(_students[key].asleep):
						continue
					_set_student(key, "answer")
					stand = maxf(stand, (actors[key]).once("S_StandUp", "G_Idle", 0.15))
			_wait = maxf(0.0, stand - 0.04)
			_phase = "free"
		"free":
			var spots := [Vector3(-3.3, 0.0, 4.25), Vector3(-2.2, 0.0, 4.3), Vector3(0.9, 0.0, 2.7)]
			var k := 0
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key) and str(_students[key].mode) == "answer":
					_stand_offset(key, true)
					var student = actors[key]
					student.loop("G_Idle", 0.0)
					if k < 2:
						# 展示台の模型を見に行く
						student.walk_to(spots[k], 0.0, "G_LookUp")
					else:
						student.loop_for("G_Stretch", 3.0, "G_Chat")
					k += 1
			_t = 0.0
			_phase = "rest"
		"rest":
			if fmod(_t, 10.0) < get_process_delta_time() and not teacher.is_busy():
				teacher.once("T_Drink", "T_Idle")
			if _t < float(step.get("secs", 30.0)):
				return false
			for key: String in STUDENTS:
				if actors.has(key) and _students.has(key) and str(_students[key].mode) == "answer":
					_go_seat(key)
			_wait = 2.0
			_phase = "done"
		"done":
			for key: String in STUDENTS:
				if _students.has(key) and str(_students[key].mode) == "go_seat":
					return false
			return true
	return false


# ------------------------------------------------------------------ high writing（項目 27〜31）

## 書く仕事（_start_write と同じ）を、高いところ用の設定で始める。
func _start_high_pen(actor, how: String, lift_y: float, fixed: bool) -> void:
	_start_write(actor, step)
	var pen: Dictionary = _pens[actor.key]
	pen.how = how
	pen.lift_y = lift_y
	pen.fixed = fixed
	if how == "pointer":
		pen.reach = 1.05
		# テープで留めたチョークは揺れて、字がふにゃふにゃになる
		var wobbly: Array = []
		for stroke: PackedVector2Array in pen.strokes:
			var w := PackedVector2Array()
			var phase := _rng.randf_range(0.0, TAU)
			for i in range(stroke.size()):
				w.append(stroke[i] + Vector2(0.008 * sin(i * 1.7 + phase), 0.01 * sin(i * 2.3 + phase * 1.3)))
			wobbly.append(w)
		pen.strokes = wobbly
	elif how == "jump":
		var jagged: Array = []
		for stroke: PackedVector2Array in pen.strokes:
			var off := Vector2(_rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.025, 0.025))
			var j := PackedVector2Array()
			for p in stroke:
				j.append(p + off)
			jagged.append(j)
		pen.strokes = jagged


## 高いところに書く: how = jump（1 画ごとに跳ぶ）/ stool（踏み台を運んで乗る）/ pointer（指し棒の先にチョークを
## テープで留めて）/ ride（挙手の生徒に肩車してもらう）。
func _tick_write_high(teacher) -> bool:
	var how := str(step.get("how", "jump"))
	var at := _vec2(step.get("at", [1.0, 0.7]))
	var text_w: float = _glyphs.measure(str(step.get("text", "")), float(step.get("h", 0.15)))
	var centre_u := at.x + text_w * 0.5
	var top_v := at.y + float(step.get("h", 0.15))
	match how:
		"jump":
			if _phase == "begin":
				last_event = "jump_write"
				if _held_color == "":
					_pick = {"color": str(step.get("color", "white")), "phase": "begin"}
					_phase = "pick"
					return false
				_phase = "pen"
				_start_high_pen(teacher, "jump", 0.3, false)
				return false
			if _phase == "pick":
				if _tick_pick(teacher):
					_phase = "pen"
					_start_high_pen(teacher, "jump", 0.3, false)
				return false
			if not _pens.has(teacher.key):
				emote(teacher, "sweat", 1.4)
				return true
			return false
		"pointer":
			match _phase:
				"begin":
					last_event = "pointer_chalk"
					_put_down(teacher, board_uv("F", teacher.hand_tip_point()).x)
					teacher.pointer_to("R", true)
					teacher.pointer_chalk(true, CHALK_COLORS.get(str(step.get("color", "white")), CHALK_COLORS.white))
					teacher.tip_length = 0.9
					emote(teacher, "bulb", 1.3)
					_wait = 0.8
					_phase = "pen"
				"pen":
					_start_high_pen(teacher, "pointer", 0.0, false)
					_held_color = str(step.get("color", "white"))
					_phase = "writing"
				"writing":
					if _pens.has(teacher.key):
						return false
					# テープがはがれて、チョークがぽろっと落ちる
					var tip: Vector3 = teacher.hand_tip_point()
					teacher.pointer_chalk(false)
					var piece := _make_chalk(_held_color)
					_set.add_child(piece)
					_throw_prop(piece, tip, Vector3(tip.x - 0.2, 0.012, tip.z - 0.4), 0.6, 0.05, false)
					_held_color = ""
					teacher.tip_length = 0.36
					_update_pointer_hand(teacher, false)
					emote(teacher, "sweat", 1.2)
					return true
		"stool":
			return _tick_stool_write(teacher, centre_u, top_v)
		"ride":
			return _tick_ride_write(teacher, centre_u, top_v)
	return false


## 踏み台: 取りに行く → 抱えて運ぶ → 置いて乗る（ぴょん）→ 書く → 降りる → 元へ運んで戻す（項目 28）。
func _tick_stool_write(teacher, centre_u: float, top_v: float) -> bool:
	var stool_top := 0.4725
	match _phase:
		"begin":
			last_event = "stool"
			if _stool_node == null:
				return true
			_high = {"spot": stance_root("F", centre_u + LEAD, top_v, REACH_PLAN, stool_top), "home": _stool_node.transform}
			teacher.ik_off()
			var p := _stool_pos()
			teacher.walk_to(p + Vector3(0.0, 0.0, -0.62), 0.0, "T_Idle")
			_phase = "to_stool"
		"to_stool":
			if teacher.is_busy():
				return false
			_wait = teacher.once("T_CrouchPickup", "T_Carry") * 0.55
			_phase = "lift"
		"lift":
			_stool_carry = teacher.key
			var spot: Vector3 = _high.spot
			teacher.walk_to(spot + Vector3(0.0, 0.0, -0.55), 0.0, "T_Idle", "T_Carry", 0.6)
			_phase = "carry"
		"carry":
			if teacher.is_busy():
				return false
			_stool_carry = ""
			var spot: Vector3 = _high.spot
			_stool_node.transform = Transform3D((_high.home as Transform3D).basis, Vector3(spot.x, 0.0, spot.z))
			_wait = 0.3
			_phase = "climb"
		"climb":
			# ぴょんと乗る
			var spot: Vector3 = _high.spot
			teacher.root.position = Vector3(spot.x, teacher.root.position.y, spot.z)
			teacher.stand_y = stool_top
			teacher.kick(-0.6)
			teacher.face(WRITE_YAW)
			_wait = 0.5
			_phase = "chalk"
		"chalk":
			if _held_color == "":
				# 箱まで届かないので、ポケットの予備のチョーク
				_held_color = str(step.get("color", "white"))
				teacher.hold("R", _make_chalk(_held_color))
				_update_pointer_hand(teacher)
			_start_high_pen(teacher, "stool", stool_top, true)
			_phase = "writing"
		"writing":
			if _pens.has(teacher.key):
				return false
			teacher.loop("T_Nod", 0.2)
			emote(teacher, "note", 1.2)
			_wait = 0.8
			_phase = "down"
		"down":
			teacher.stand_y = 0.0
			teacher.kick(0.4)
			teacher.root.position += Vector3(0.0, 0.0, -0.55)
			teacher.loop("T_Idle", 0.2)
			_wait = 0.5
			_phase = "pick_again"
		"pick_again":
			_wait = teacher.once("T_CrouchPickup", "T_Carry") * 0.55
			_phase = "carry_back"
		"carry_back":
			_stool_carry = teacher.key
			var home: Transform3D = _high.home
			teacher.walk_to(Vector3(home.origin.x, 0.0, home.origin.z - 0.55), 0.0, "T_Idle", "T_Carry", 0.6)
			_phase = "put_back"
		"put_back":
			if teacher.is_busy():
				return false
			_stool_carry = ""
			_stool_node.transform = _high.home
			teacher.loop("T_Idle", 0.2)
			return true
	return false


## 肩車: 挙手の生徒を呼び、黒板の前でしゃがんでもらって肩（頭）の上に乗り、ぐらぐらしながら書く（項目 31）。
func _tick_ride_write(teacher, centre_u: float, top_v: float) -> bool:
	var who := "student_hand"
	var student = actors.get(who)
	if student == null:
		return true
	var head_lift := 1.42
	match _phase:
		"begin":
			last_event = "shoulder_ride"
			teacher.ik_off()
			_high = {"spot": stance_root("F", centre_u + LEAD, top_v, REACH_PLAN, head_lift)}
			teacher.face_point(student.root.position)
			_set_student(who, "answer")
			emote(student, "!", 1.2)
			_wait = maxf(0.0, student.once("S_StandUp", "G_Idle", 0.15) - 0.04)
			_phase = "stood"
		"stood":
			_stand_offset(who, true)
			student.loop("G_Idle", 0.0)
			var spot: Vector3 = _high.spot
			student.walk_to(spot, WRITE_YAW, "G_Carry")
			teacher.walk_to(spot + Vector3(0.65, 0.0, -0.35), WRITE_YAW, "T_Idle")
			_phase = "gather"
		"gather":
			if student.is_busy() or teacher.is_busy():
				return false
			student.loop("G_Carry", 0.2)
			_wait = 0.4
			_phase = "climb"
		"climb":
			teacher.kick(-0.9)
			_phase = "ride"
			_t = 0.0
			_high.riding = true
		"ride":
			# 乗っている間は生徒の頭のてっぺんについていく（ぐらぐら）
			var head: Vector3 = student.head_point()
			teacher.root.position = Vector3(head.x, teacher.root.position.y, head.z)
			teacher.stand_y = head.y - 0.06
			if _t > 0.5 and not _pens.has(teacher.key) and not _high.has("pen"):
				_high.pen = true
				if _held_color == "":
					_held_color = str(step.get("color", "white"))
					teacher.hold("R", _make_chalk(_held_color))
					_update_pointer_hand(teacher)
				_start_high_pen(teacher, "ride", head_lift, true)
				emote(student, "sweat", 3.0)
				return false
			if _high.has("pen") and not _pens.has(teacher.key):
				_phase = "off"
			return false
		"off":
			teacher.stand_y = 0.0
			teacher.root.position = student.root.position + Vector3(0.6, 0.0, -0.4)
			teacher.kick(0.5)
			teacher.loop("T_Idle", 0.2)
			student.once("G_Cheer", "G_Idle")
			emote(teacher, "note", 1.2)
			_wait = 1.6
			_phase = "back"
		"back":
			_seated[who] = false
			_go_seat(who)
			return true
	return false


## 上下スライド黒板: dir = up（下の板 F を押し上げる → 裏の B が下りてくる）/ down（跳んで指し棒で F を引き下ろす）。
func _tick_slide(teacher) -> bool:
	var up := str(step.get("dir", "up")) == "up"
	match _phase:
		"begin":
			last_event = "slide_" + ("up" if up else "down")
			if _panels.is_empty():
				return true
			_put_down(teacher, board_uv("F", teacher.hand_tip_point()).x)
			teacher.ik_off()
			var edge_u := 1.6
			teacher.walk_to(stance_root("F", edge_u + LEAD, 0.0), WRITE_YAW, "T_Idle")
			_high = {"edge_u": edge_u, "from": float(_board_shift.F)}
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			if up:
				teacher.set_tip(board_point("F", Vector2(float(_high.edge_u), -0.03), 0.02))
				teacher.ik_on(0.25)
				_wait = 0.4
			else:
				teacher.pointer_to("R", true)
				teacher.tip_length = 0.85
				_wait = teacher.once("T_JumpWrite", "T_Idle") * 0.4
			_phase = "move"
			_t = 0.0
		"move":
			if not up and _t < get_process_delta_time() * 1.5:
				teacher.set_tip(board_point("F", Vector2(float(_high.edge_u), -0.03), 0.04))
				teacher.ik_on(0.1)
			var travel := 1.7
			var u := clampf(_t / 2.2, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0) if up else u * u * (3.0 - 2.0 * u)
			var shift := lerpf(float(_high.from), travel if up else 0.0, e)
			_apply_board_shift(shift)
			if _t < 0.45:
				teacher.set_tip(board_point("F", Vector2(float(_high.edge_u), -0.03), 0.02 if up else 0.04))
			elif _t < 0.5:
				teacher.ik_off(0.3)
				teacher.tip_length = 0.36
				_update_pointer_hand(teacher, false)
			if u < 1.0:
				return false
			teacher.loop("T_Idle", 0.2)
			return true
	return false


## 上下の板を動かす: F が shift 上がり、B が shift 下がる。
func _apply_board_shift(shift: float) -> void:
	_board_shift.F = shift
	_board_shift.B = -shift
	if _panels.has("F"):
		(_panels.F as Node3D).position = (_panel_home.F as Vector3) + Vector3(0.0, shift, 0.0)
	if _panels.has("B"):
		(_panels.B as Node3D).position = (_panel_home.B as Vector3) + Vector3(0.0, -shift, 0.0)


## 大きなコンパスで円を描く（左手で中心を押さえ、体ごと回る）/ 三角定規を押さえて直線を引く（項目 22）。
func _tick_drafting(teacher) -> bool:
	var compass := str(step.get("do", "")) == "compass"
	var tool_name := "PRP_Compass" if compass else "PRP_SetSquare_60"
	var tool: Node3D = _tray.get(tool_name)
	match _phase:
		"begin":
			last_event = str(step.get("do", ""))
			if tool == null:
				return true
			_put_down(teacher, board_uv("F", teacher.hand_tip_point()).x)
			teacher.ik_off()
			var rack := _tray_point(tool)
			teacher.walk_to(Vector3(rack.x - 0.1, 0.0, rack.z - 0.75), 10.0, "T_Idle")
			_phase = "to_rack"
		"to_rack":
			if teacher.is_busy():
				return false
			_start_swap(teacher, [{"where": tool, "do": "take", "item": "tool", "name": tool_name}])
			_phase = "take"
		"take":
			if not _tick_swap(teacher):
				return false
			tool.visible = false
			var copy := MeshInstance3D.new()
			copy.mesh = (tool as MeshInstance3D).mesh
			for i in range(copy.mesh.get_surface_count()):
				copy.set_surface_override_material(i, (tool as MeshInstance3D).get_active_material(i))
			var centre := copy.mesh.get_aabb().get_center()
			_high = {"copy": copy}
			if compass:
				teacher.hold("R", copy, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.3, 0.0)) * Transform3D(Basis.IDENTITY, -centre))
			else:
				teacher.hold("L", copy, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, 0.0)) * Transform3D(Basis.IDENTITY, -centre))
				if _held_color == "":
					_held_color = str(step.get("color", "white"))
					teacher.hold("R", _make_chalk(_held_color))
			teacher.pointer_visible(false)
			_phase = "pen"
		"pen":
			var color := str(step.get("color", "white"))
			if compass:
				var c := _vec2(step.at)
				_start_write(teacher, {"do": "circle", "at": step.at, "r": float(step.get("r", 0.25)), "color": color})
				var pen: Dictionary = _pens[teacher.key]
				pen.window = Vector2(-0.45, 0.5)
				pen.compass = c
			else:
				_start_write(teacher, {"do": "line", "from": step.from, "to": step.to, "color": color})
				var pen: Dictionary = _pens[teacher.key]
				pen.square = [_vec2(step.from), _vec2(step.to)]
			_phase = "drawing"
		"drawing":
			var pen: Dictionary = _pens.get(teacher.key, {})
			if not pen.is_empty():
				if compass and pen.has("compass"):
					# 左手で中心を押さえ、円を描くにつれて体ごと少し回る
					var c: Vector2 = pen.compass
					teacher.set_tip_left(board_point("F", c, 0.03))
					teacher.ik_left_on(0.2)
					var d: Vector2 = Vector2(pen.pos) - c
					teacher.face(WRITE_YAW + 22.0 * sin(atan2(d.y, d.x)))
				elif pen.has("square"):
					# 三角定規を線に沿わせて黒板に当て、左手で押さえる
					var a: Vector2 = pen.square[0]
					var b: Vector2 = pen.square[1]
					var mid := (a + b) * 0.5 + Vector2(0.0, 0.1)
					teacher.set_tip_left(board_point("F", mid, 0.03))
					teacher.ik_left_on(0.2)
				return false
			teacher.ik_left_off(0.3)
			teacher.face(WRITE_YAW)
			var rack := _tray_point(tool)
			teacher.walk_to(Vector3(rack.x - 0.1, 0.0, rack.z - 0.75), 10.0, "T_Idle")
			_phase = "return"
		"return":
			if teacher.is_busy():
				return false
			var copy: Node3D = _high.get("copy")
			for side in ["R", "L"]:
				if teacher.holding(side) == copy:
					teacher.drop(side)
			if copy != null:
				copy.queue_free()
			tool.visible = true
			teacher.pointer_visible(true)
			_update_pointer_hand(teacher)
			return true
	return false


# ------------------------------------------------------------------ tests & graduation（項目 57・56）

## プリントを配る（handout）/ 集める（collect）: 教卓のプリントの束を持って、机を 1 つずつ回る。
func _tick_papers(teacher, handout: bool) -> bool:
	match _phase:
		"begin":
			last_event = "handout" if handout else "collect"
			_put_down(teacher, board_uv("F", teacher.hand_tip_point()).x)
			teacher.ik_off()
			_route = []
			for key: String in STUDENTS:
				if _students.has(key):
					var seat: Vector3 = _seats.get(key, SEATS[key])
					_route.append({"key": key, "at": Vector3(seat.x + 0.62, 0.0, seat.z + 1.15)})
			_route.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.at.x > b.at.x)
			teacher.walk_to(Vector3(1.15, 0.0, 2.5), NAN, "T_Idle")
			_phase = "go"
		"go":
			if teacher.is_busy():
				return false
			if _route.is_empty():
				teacher.walk_to(LECTERN_SPOT, CLASS_YAW, "T_Idle")
				_phase = "home"
				return false
			var stop: Dictionary = _route.pop_front()
			_high = {"key": stop.key}
			teacher.walk_to(stop.at, -90.0 + 180.0, "T_Idle")
			_phase = "give"
		"give":
			if teacher.is_busy():
				return false
			var key: String = _high.key
			var seat: Vector3 = _seats.get(key, SEATS[key])
			var desk := Vector3(seat.x, 0.73, seat.z + 0.85)
			teacher.set_tip(desk + Vector3(0.0, 0.05, 0.0))
			teacher.ik_on(0.2)
			if handout:
				_papers.append(_make_paper(desk))
				(actors[key]).once("S_PageFlip", "S_SitIdle")
			else:
				var keep: Array = []
				for paper in _papers:
					if not is_instance_valid(paper):
						continue
					if (paper as Node3D).position.distance_to(desk) < 0.5:
						(paper as Node).queue_free()
					else:
						keep.append(paper)
				_papers = keep
			_wait = 0.7
			_phase = "back"
		"back":
			teacher.ik_off(0.2)
			_phase = "go"
		"home":
			if teacher.is_busy():
				return false
			return true
	return false


func _make_paper(at: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.21, 0.297)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.94, 0.9)
	material.roughness = 0.9
	quad.material = material
	var paper := MeshInstance3D.new()
	paper.mesh = quad
	paper.position = at + Vector3(_rng.randf_range(-0.05, 0.05), 0.004, _rng.randf_range(-0.03, 0.03))
	paper.rotation = Vector3(-PI * 0.5, _rng.randf_range(-0.25, 0.25), 0.0)
	_set.add_child(paper)
	return paper


## 解く: 生徒は猛烈に書き、ときどき「…」や汗や電球。居眠りの生徒は答案の上で寝てしまう（期末テストは先生が見回る）。
func _tick_solve(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "solve"
			_set_cue("notes")
			teacher.walk_to(LECTERN_SPOT, CLASS_YAW, "T_IdleLook")
			_t = 0.0
			_phase = "work"
		"work":
			if fmod(_t, 3.3) < get_process_delta_time():
				var keys: Array = _students.keys()
				if not keys.is_empty():
					var key: String = keys[_rng.randi() % keys.size()]
					emote(actors[key], ["dots", "sweat", "bulb", "note"][_rng.randi() % 4], 1.3)
			if _t < float(step.get("secs", 18.0)):
				return false
			_set_cue("listen")
			return true
	return false


## 教壇で赤ペン採点（踏み台に腰かけて）: ときどき〇の漫符と首かしげ。
func _tick_grade_papers(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "grade_papers"
			teacher.walk_to(_stool_pos() + Vector3(0.0, 0.0, -0.55), 160.0, "T_Idle")
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			teacher.root.position = _stool_pos()
			teacher.loop("T_SitGrade", 0.3)
			_t = 0.0
			_phase = "grade"
		"grade":
			if fmod(_t, 3.0) < get_process_delta_time() and _t > 0.5:
				emote(teacher, "note" if _rng.randf() < 0.7 else "sweat", 1.1)
			if _t < float(step.get("secs", 14.0)):
				return false
			teacher.root.position = _stool_pos() + Vector3(0.0, 0.0, -0.55)
			teacher.loop("T_Idle", 0.3)
			for paper in _papers:
				if is_instance_valid(paper):
					(paper as Node).queue_free()
			_papers.clear()
			return true
	return false


## 卒業証書の授与: ひとりずつ立って教卓の前へ → 先生が証書を手渡す → 礼 → 席へ。保護者は拍手（項目 56 の卒業式）。
func _tick_diplomas(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "diplomas"
			_roll = STUDENTS.filter(func(k: String) -> bool: return _students.has(k))
			teacher.walk_to(LECTERN_SPOT, CLASS_YAW, "T_Idle")
			_phase = "next"
		"next":
			if teacher.is_busy():
				return false
			if _roll.is_empty():
				return true
			_roll_key = _roll.pop_front()
			_set_student(_roll_key, "answer")
			var student = actors[_roll_key]
			_wait = maxf(0.0, student.once("S_StandUp", "G_Idle", 0.15) - 0.04)
			_phase = "stood"
		"stood":
			_stand_offset(_roll_key, true)
			var student = actors[_roll_key]
			student.loop("G_Idle", 0.0)
			student.walk_to(LECTERN_SPOT + Vector3(0.0, 0.0, -1.55), 0.0, "G_Idle")
			_phase = "come"
		"come":
			if (actors[_roll_key]).is_busy():
				return false
			var diploma := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.3, 0.004, 0.21)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.96, 0.95, 0.9)
			mesh.material = mat
			diploma.mesh = mesh
			teacher.hold("R", diploma, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
			teacher.set_tip(LECTERN_SPOT + Vector3(0.0, 1.15, -0.75))
			teacher.ik_on(0.3)
			_wait = 1.0
			_phase = "give"
		"give":
			var student = actors[_roll_key]
			var item: Node3D = teacher.drop("R")
			if item != null:
				student.hold("R", item, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)))
			teacher.ik_off(0.3)
			teacher.once("T_Bow", "T_Idle")
			student.once("G_Bow", "G_Idle")
			emote(student, "note", 1.3)
			if actors.has("parent") and _extras_visible.get("parent", false):
				(actors.parent).loop_for("G_Clap", 2.5, "G_Idle")
				emote(actors.parent, "sweat", 1.6)
			_wait = 2.2
			_phase = "back"
		"back":
			var seat: Vector3 = _seats.get(_roll_key, SEATS[_roll_key])
			(actors[_roll_key]).walk_to(seat + Vector3(0.55, 0.0, 0.0), 0.0, "G_Idle")
			_phase = "sit"
		"sit":
			if (actors[_roll_key]).is_busy():
				return false
			_stand_offset(_roll_key, false)
			(actors[_roll_key]).once("S_SitDown", "S_SitIdle", 0.0)
			_set_student(_roll_key, "")
			_wait = 0.8
			_phase = "next"
	return false


## みんなでばんざい（紙吹雪）。先生はうれし泣き。
func _tick_cheer_all(teacher) -> bool:
	match _phase:
		"begin":
			last_event = "cheer_all"
			var stand := 0.0
			for key: String in STUDENTS:
				if _students.has(key):
					_set_student(key, "answer")
					stand = maxf(stand, (actors[key]).once("S_StandUp", "G_Idle", 0.15))
			_wait = maxf(0.0, stand - 0.04)
			_phase = "cheer"
		"cheer":
			for key: String in STUDENTS:
				if _students.has(key):
					_stand_offset(key, true)
					(actors[key]).loop_for("G_Cheer", 4.0, "G_Idle")
			if actors.has("trainee"):
				(actors.trainee).once("G_Cheer", "P_Clipboard")
			teacher.once("T_HappyHop", "T_Sad")
			emote(teacher, "sweat", 3.0)
			_confetti(Vector3(0.0, 3.2, 3.0))
			_wait = 4.5
			_phase = "sit"
		"sit":
			for key: String in STUDENTS:
				if _students.has(key):
					_stand_offset(key, false)
					(actors[key]).once("S_SitDown", "S_SitIdle", 0.0)
					_set_student(key, "")
			teacher.loop("T_Idle", 0.3)
			_wait = 1.5
			_phase = "done"
		"done":
			return true
	return false


func _confetti(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 160
	p.lifetime = 4.0
	p.one_shot = true
	p.explosiveness = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.0, 0.2, 1.5)
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0.0, -0.9, 0.0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.05)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.3), Color(0.4, 0.75, 1.0), Color(0.5, 0.9, 0.5)])
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	p.color_initial_ramp = ramp
	p.position = at
	_set.add_child(p)
	p.emitting = true
	_fx.append({"kind": "free", "node": p, "t": 0.0, "secs": 6.0})


# ------------------------------------------------------------------ point / ask

func _tick_point(teacher) -> bool:
	match _phase:
		"begin":
			var uv := _vec2(step.get("at", [1.0, 0.3]))
			var target := board_point("F", uv, 0.0)
			var stand := Vector3(target.x + 0.75, 0.0, target.z - 1.05)
			# 指す点を向いてから、生徒の側へ 45° 開く（半身で指す）
			var yaw := rad_to_deg(atan2(target.x - stand.x, target.z - stand.z)) - 45.0
			teacher.ik_off()
			teacher.walk_to(stand, yaw, "T_Idle")
			_phase = "walk"
		"walk":
			if teacher.is_busy():
				return false
			_update_pointer_hand(teacher, true)
			_wait = teacher.once("T_PointTap", "T_Explain")
			_phase = "talk"
			_t = 0.0
		"talk":
			return true
	return false


## 質問: ？を書く → 生徒を向く → 手が挙がる → 指名 → 立って答える（ときどき忘れる）→ うなずき・拍手 → 座る。
func _tick_ask(teacher) -> bool:
	var who := str(step.get("call", "student_hand"))
	var student = actors.get(who)
	var eager = actors.get("student_hand") if who != "student_hand" else null
	match _phase:
		"begin":
			_phase = "write"
			_start_write(teacher, {"do": "write", "text": str(step.get("text", "？")), "at": step.get("at", [3.0, 0.1]),
				"h": 0.22, "color": _held_color if _held_color != "" else "white"})
		"write":
			if _pens.has(teacher.key):
				return false
			teacher.walk_to(LECTERN_SPOT + Vector3(0.5, 0.0, 0.0), CLASS_YAW, "T_Explain")
			_set_cue("ask")
			for key: String in STUDENTS:
				if actors.has(key) and not bool(_students[key].asleep):
					emote(actors[key], "?", 1.4 + _rng.randf_range(0.0, 0.5))
			if student != null:
				_fx.append({"kind": "emote", "t": 0.0, "secs": 1.2, "actor": student, "emote": "bulb", "len": 1.4})
			_phase = "hands"
			_t = 0.0
		"hands":
			if teacher.is_busy() or _t < 2.6:
				return false
			if student == null:
				_set_cue("listen")
				return true
			if bool(step.get("nobody", false)):
				# 誰も手を挙げない → しょんぼり（項目 45）
				_wait = teacher.once("T_Sad", "T_Idle")
				emote(teacher, "sweat", 2.0)
				_phase = "resign"
				return false
			teacher.face_point(student.root.position)
			_update_pointer_hand(teacher, true)
			_wait = teacher.once("T_PointTap", "T_Idle") * 0.6
			_phase = "stand"
			if eager != null:
				# 当てられなかった: 手を振る → 腰が浮く → 立ち上がって両手で振る（項目 67）
				_set_student("student_hand", "answer")
				eager.loop("S_RaiseHandEager", 0.1)
				emote(eager, "!", 1.0)
				_fx.append({"kind": "call", "t": 0.0, "secs": 1.2, "fn": _eager_stand})
		"stand":
			_update_pointer_hand(teacher, false)
			_set_student(who, "answer")
			_wait = maxf(0.0, student.once("S_StandUp", "G_Idle", 0.15) - 0.04)
			_phase = "stood"
		"stood":
			_stand_offset(who, true)
			student.loop("G_Idle", 0.0)
			if bool(step.get("board", false)):
				# 前に出て黒板に答えを書く（届かないので跳びながら）→ 先生が赤で花丸（項目 68）
				var at := _vec2(step.get("answer_at", [3.6, 0.42]))
				student.walk_to(stance_root("F", at.x + LEAD, at.y + 0.15, REACH_PLAN, 0.3), WRITE_YAW, "G_Idle")
				_phase = "to_board"
				return false
			var forgot := _rng.randf() < 0.3
			_phase = "forgot" if forgot else "answer"
			if forgot:
				_wait = student.once("S_Forget", "G_Idle", 0.2)
				student.set_eyes("half")
				_fx.append({"kind": "emote", "t": 0.0, "secs": 0.8, "actor": student, "emote": "dots", "len": 2.2})
			else:
				student.loop("G_Chat")
				_wait = 2.4
		"answer", "forgot":
			if _phase == "forgot":
				_wait = teacher.once("T_HeadTilt", "T_Idle")
				emote(teacher, "sweat", 1.6)
				student.set_eyes("open")
				_phase = "sit"
			else:
				student.loop("G_Idle")
				_wait = maxf(teacher.once("T_Nod", "T_Idle"), 0.8)
				_phase = "praise"
		"praise":
			_wait = teacher.once("T_HappyHop", "T_Idle")
			emote(teacher, "note", 1.5)
			student.once("G_Cheer", "G_Idle")
			student.set_eyes("closed")
			_set_cue("clap")
			if actors.has("parent") and _extras_visible.get("parent", false):
				(actors.parent).once("G_Clap", "G_Idle")
			_phase = "sit"
		"sit":
			student.set_eyes("open")
			_stand_offset(who, false)
			_wait = student.once("S_SitDown", "S_SitIdle", 0.0)
			_phase = "seated"
		"seated":
			_set_student(who, "")
			_set_cue("listen")
			return true
		"resign":
			teacher.once("T_Nod", "T_Idle")
			_set_cue("listen")
			_wait = 1.0
			_phase = "seated"
		"to_board":
			if student.is_busy():
				return false
			_set_cue("listen")
			var answer := {"do": "write", "text": str(step.get("answer", "〇")), "at": step.get("answer_at", [3.6, 0.42]),
				"h": 0.16, "color": "white"}
			_start_write(student, answer)
			var pen: Dictionary = _pens[student.key]
			pen.how = "jump"
			pen.lift_y = 0.3
			student.hold("R", _make_chalk("white"))
			_phase = "board_writing"
		"board_writing":
			if _pens.has(student.key):
				return false
			var chalk: Node3D = student.drop("R")
			if chalk != null:
				chalk.queue_free()
			student.walk_to(student.root.position + Vector3(0.6, 0.0, -0.9), 180.0, "G_Idle")
			_pick = {"color": "red", "phase": "begin"}
			_phase = "red_chalk"
		"red_chalk":
			# 花丸は赤で
			if not _tick_pick(teacher):
				return false
			var at := _vec2(step.get("answer_at", [3.6, 0.42]))
			_start_write(teacher, {"do": "hanamaru", "at": [at.x + 0.15, at.y + 0.08], "r": 0.22, "color": "red"})
			_phase = "hanamaru"
		"hanamaru":
			if _pens.has(teacher.key):
				return false
			emote(student, "note", 1.5)
			student.once("G_Cheer", "G_Idle")
			_set_cue("clap")
			_wait = 1.6
			_phase = "walk_back"
		"walk_back":
			var seat: Vector3 = _seats.get(who, SEATS.get(who, Vector3.ZERO))
			student.walk_to(seat + Vector3(0.55, 0.0, 0.0), 0.0, "G_Idle")
			_phase = "walk_back2"
		"walk_back2":
			if student.is_busy():
				return false
			_phase = "sit"
	return false


## 当てられなかった挙手の生徒が、立ち上がって両手で振る。答えが終わるとしょんぼり座る。
func _eager_stand() -> void:
	var eager = actors.get("student_hand")
	if eager == null:
		return
	var length: float = eager.once("S_StandUp", "G_WaveBoth", 0.15)
	_fx.append({"kind": "call", "t": 0.0, "secs": maxf(0.0, length - 0.04), "fn": func() -> void:
		_stand_offset("student_hand", true)
		eager.loop("G_WaveBoth", 0.0)
		_fx.append({"kind": "call", "t": 0.0, "secs": 4.0, "fn": func() -> void:
			eager.once("G_Sad", "G_Idle")
			emote(eager, "sweat", 1.5)
			_fx.append({"kind": "call", "t": 0.0, "secs": 2.6, "fn": func() -> void:
				_stand_offset("student_hand", false)
				eager.once("S_SitDown", "S_SitIdle", 0.0)
				_set_student("student_hand", "")
			})
		})
	})


## 立ち上がりのクリップは横 +X（本人の左）へ 0.55 m ずれて終わるので、立っている間は足元をそこへ置く。
func _stand_offset(who: String, standing: bool) -> void:
	var student = actors.get(who)
	if student == null or _seated.get(who, true) == not standing:
		return
	# 向きは席の向き（0°）にそろえてから
	student.root.rotation.y = 0.0
	student.face(0.0)
	var side: Vector3 = student.root.basis.x.normalized() * 0.55
	student.root.position += side if standing else -side
	_seated[who] = not standing


# ------------------------------------------------------------------ gags

func _tick_gag(teacher) -> bool:
	if _phase == "begin":
		var pool: Array = step.get("pool", ["clock"])
		var choices: Array = pool.filter(func(g: String) -> bool: return not (g in _gag_last))
		if choices.is_empty():
			choices = pool
		var gag: String = choices[_rng.randi() % choices.size()]
		_gag_last.append(gag)
		if _gag_last.size() > 3:
			_gag_last.pop_front()
		step = step.duplicate()
		step.gag = gag
		last_event = gag
		_phase = "start"
		teacher.ik_off()
	var gag := str(step.get("gag", ""))
	match gag:
		"clock":
			if _phase == "start":
				teacher.face_point(CLOCK_POINT)
				_phase = "look"
				return false
			if _phase == "look":
				if teacher.is_busy():
					return false
				_wait = teacher.once("T_LookClock", "T_Idle")
				_fx.append({"kind": "emote", "t": 0.0, "secs": 1.0, "actor": teacher, "emote": "!", "len": 1.0})
				_phase = "end"
				return false
			return true
		"sneeze":
			if _phase == "start":
				_wait = teacher.once("T_Sneeze", "T_Idle")
				_puff_later(0.95, teacher, 0, 0.25)
				for key: String in STUDENTS:
					if actors.has(key):
						(actors[key]).blink()
				_phase = "end"
				return false
			return true
		"snap_chalk":
			if _phase == "start":
				_wait = teacher.once("T_SnapChalk", "T_Idle")
				_puff_later(0.8, teacher, 1, 0.12)
				_phase = "end"
				return false
			return true
		"look_up":
			if _phase == "start":
				_wait = teacher.once("T_LookUp", "T_Idle")
				_set_cue("look_up")
				_phase = "end"
				return false
			_set_cue("listen")
			return true
		"pickup":
			if _phase == "start":
				var chalk: Node3D = teacher.drop("R")
				if chalk != null:
					_throw_prop(chalk, teacher.hand_tip_point(), teacher.root.position + teacher.root.basis.z * 0.35 + Vector3(0.0, 0.02, 0.0), 0.45, 0.25, false)
				_wait = 0.5
				_phase = "crouch"
				return false
			if _phase == "crouch":
				teacher.set_eyes("half")
				_wait = teacher.once("T_CrouchPickup", "T_Idle")
				_phase = "rehold"
				return false
			if _phase == "rehold":
				teacher.set_eyes("open")
				if _held_color != "":
					teacher.hold("R", _make_chalk(_held_color))
				return true
			return true
		"drink":
			if _phase == "start":
				teacher.walk_to(DRINK_SPOT, CLASS_YAW, "T_Idle")
				_phase = "walk"
				return false
			if _phase == "walk":
				if teacher.is_busy():
					return false
				_wait = teacher.once("T_Drink", "T_Idle")
				teacher.set_eyes("closed")
				_fx.append({"kind": "emote", "t": 0.0, "secs": 1.6, "actor": teacher, "emote": "note", "len": 1.3})
				_phase = "end"
				return false
			teacher.set_eyes("open")
			return true
		"whistle", "doze_throw":
			return _tick_wake(teacher, gag)
	return true


## 居眠りの生徒を起こす: 寝ていなければ寝かせてから（突っ伏す）、先生が気づいて首をかしげ、
## 笛を吹くかチョークを投げる → 飛び起きる。ほかの生徒は振り向く。
func _tick_wake(teacher, gag: String) -> bool:
	var who := "student_doze"
	var student = actors.get(who)
	if student == null:
		return true
	var brain: Dictionary = _students[who]
	match _phase:
		"start":
			if not brain.asleep:
				brain.drowsy = 99.0
			_phase = "sleeping"
			_t = 0.0
		"sleeping":
			if not brain.asleep and _t < 12.0:
				return false
			teacher.face_point(student.root.position)
			_phase = "notice"
		"notice":
			if teacher.is_busy():
				return false
			_wait = teacher.once("T_HeadTilt", "T_Idle")
			emote(teacher, "anger", 2.2)
			_phase = "act"
		"act":
			if gag == "whistle":
				_wait = teacher.once("T_Whistle", "T_Idle") * 0.55
			else:
				var length: float = teacher.once("T_Throw", "T_Idle")
				_phase = "throw"
				_wait = length * (17.0 / 38.0)
				return false
			_phase = "wake"
		"throw":
			var from: Vector3 = teacher.hand_tip_point()
			var to: Vector3 = student.head_point()
			var chalk: Node3D = teacher.drop("R")
			if chalk == null:
				chalk = _make_chalk("white")
			_held_color = ""
			_held_from = null
			_update_pointer_hand(teacher)
			_throw_prop(chalk, from, to, 0.55, 0.5, true)
			_wait = 0.55
			_phase = "wake"
		"wake":
			_wake_student(who)
			for key: String in ["student_notes", "student_hand"]:
				if actors.has(key):
					(actors[key]).once("S_TurnLeft", "S_SitIdle")
			_wait = 1.6
			_phase = "end"
		"end":
			return true
	return false


func _wake_student(who: String) -> void:
	var brain: Dictionary = _students[who]
	var student = actors[who]
	brain.asleep = false
	brain.drowsy = -_rng.randf_range(10.0, 35.0)
	student.zzz = 0.0
	brain.mode = ""
	student.set_eyes("open")
	student.blink()
	student.once("S_WakeJolt", "S_SitIdle", 0.1)
	brain.until = student.clip_length("S_WakeJolt")
	emote(student, "!", 1.2)
	_puff(student.head_point(), 1, 0.15)


# ------------------------------------------------------------------ events (extra cast)

func _tick_event(name: String) -> bool:
	match name:
		"parent":
			if _phase == "begin":
				_show_extra("parent")
				(actors.parent).walk_to(EXTRAS.parent.spot, EXTRAS.parent.yaw, "G_Idle")
				for key: String in STUDENTS:
					if actors.has(key):
						_fx.append({"kind": "emote", "t": 0.0, "secs": 2.5 + 0.2 * _rng.randf(), "actor": actors[key], "emote": "!", "len": 1.0})
				_phase = "end"
				last_event = name
			return true
		"parent_leave":
			if _extras_visible.get("parent", false):
				(actors.parent).once("G_Bow", "G_Idle")
				_leave_later("parent", 2.2)
			return true
		"transfer":
			return _tick_transfer()
		"vice":
			return _tick_vice()
		"duty_erase":
			return _tick_duty()
		"rei":
			return _tick_rei()
		"trainee_demo":
			return _tick_trainee_demo()
		"janitor":
			return _tick_janitor()
		"fix_light":
			return _tick_fix_light()
	return true


func _tick_transfer() -> bool:
	if not actors.has("transfer"):
		return true
	var transfer = actors.transfer
	var teacher = actors.lecturer
	match _phase:
		"begin":
			last_event = "transfer"
			_show_extra("transfer")
			transfer.walk_to(EXTRAS.transfer.spot, CLASS_YAW, "G_Idle")
			teacher.walk_to(LECTERN_SPOT + Vector3(0.6, 0.0, 0.0), CLASS_YAW - 25.0, "T_Explain")
			_set_cue("look_up")
			_phase = "walk"
		"walk":
			if transfer.is_busy():
				return false
			# 黒板に名前を書く（項目 117）
			transfer.walk_to(stance_root("F", 3.75 + LEAD, 0.45), WRITE_YAW, "G_Idle")
			_phase = "to_board"
		"to_board":
			if transfer.is_busy():
				return false
			transfer.hold("R", _make_chalk("white"))
			_start_write(transfer, {"do": "write", "text": "ゴドー", "at": [3.7, 0.3], "h": 0.2, "color": "white"})
			_phase = "name"
		"name":
			if _pens.has(transfer.key):
				return false
			var chalk: Node3D = transfer.drop("R")
			if chalk != null:
				chalk.queue_free()
			transfer.walk_to(EXTRAS.transfer.spot, CLASS_YAW, "G_Idle")
			_phase = "turn"
		"turn":
			if transfer.is_busy():
				return false
			_wait = transfer.once("G_Bow", "G_Idle")
			_phase = "wave"
		"wave":
			_set_cue("clap")
			_wait = transfer.once("G_Wave", "G_Idle") + 0.6
			_phase = "leave"
		"leave":
			_set_cue("listen")
			transfer.walk_to(EXTRAS.transfer.from, NAN, "G_Idle")
			_leave_when_arrived("transfer")
			return true
	return false


func _tick_vice() -> bool:
	if not actors.has("vice"):
		return true
	var vice = actors.vice
	match _phase:
		"begin":
			last_event = "vice"
			_show_extra("vice")
			vice.walk_to(EXTRAS.vice.spot, EXTRAS.vice.yaw, "G_Idle")
			_phase = "walk"
		"walk":
			if vice.is_busy():
				return false
			_wait = vice.once("G_Nod", "G_Idle") + vice.clip_length("G_HeadTilt") * 0.2
			emote(actors.lecturer, "sweat", 1.8)
			(actors.lecturer).kick(-0.25)
			_phase = "tilt"
		"tilt":
			_wait = vice.once("G_HeadTilt", "G_Idle") + 0.5
			_phase = "leave"
		"leave":
			vice.walk_to(EXTRAS.vice.from, NAN, "G_Idle")
			_leave_when_arrived("vice")
			return true
	return false


## 日直: 先生は踏み台に腰かけて採点、日直が黒板消しを取って黒板を消し（rects を順に）、手元に置いて帰る。
func _tick_duty() -> bool:
	var teacher = actors.lecturer
	if not actors.has("duty"):
		return true
	var duty = actors.duty
	match _phase:
		"begin":
			last_event = "duty_erase"
			_put_down(teacher)
			teacher.ik_off()
			teacher.walk_to(_stool_pos() + Vector3(0.0, 0.0, -0.55), 160.0, "T_Idle")
			_show_extra("duty")
			var at := _tray_point("eraser")
			duty.walk_to(stance_root("F", board_uv("F", at).x + LEAD, 0.0), WRITE_YAW, "G_Idle")
			_duty_rects = (step.get("rects", [[0.3, 0.0, 3.45, 0.62]]) as Array).duplicate()
			_phase = "walk"
		"walk":
			if teacher.is_busy() or duty.is_busy():
				return false
			# 踏み台に腰かける（T_SitGrade は座面の高さに合わせてある）
			teacher.root.position = _stool_pos()
			teacher.loop("T_SitGrade", 0.3)
			_start_swap(duty, [{"where": "eraser", "do": "take", "item": "eraser"}])
			_phase = "take"
		"take":
			if not _tick_swap(duty):
				return false
			_phase = "next"
		"next":
			if _duty_rects.is_empty():
				_start_swap(duty, [{"where": _tray_spot(board_uv("F", duty.hand_tip_point()).x, 0.06), "do": "put"}])
				_phase = "put"
				return false
			var rect: Array = _duty_rects.pop_front()
			_start_erase(duty, "F", rect)
			_add_tray_dust(float(rect[0]), float(rect[2]))
			_phase = "wipe"
		"wipe":
			if _pens.has(duty.key):
				return false
			_phase = "next"
		"put":
			if not _tick_swap(duty):
				return false
			duty.ik_off()
			duty.walk_to(EXTRAS.duty.from, NAN, "G_Idle")
			_leave_when_arrived("duty")
			teacher.root.position = _stool_pos() + Vector3(0.0, 0.0, -0.55)
			teacher.loop("T_Idle", 0.3)
			return true
	return false


func _tick_janitor() -> bool:
	if not actors.has("janitor"):
		return true
	var janitor = actors.janitor
	match _phase:
		"begin":
			last_event = "janitor"
			_show_extra("janitor")
			janitor.walk_to(EXTRAS.janitor.spot, EXTRAS.janitor.yaw, "G_Idle")
			_phase = "walk"
		"walk":
			if janitor.is_busy():
				return false
			_wait = janitor.once("G_Stretch", "G_Idle") + 0.4
			_phase = "leave"
		"leave":
			janitor.walk_to(EXTRAS.janitor.from, NAN, "G_Idle")
			_leave_when_arrived("janitor")
			return true
	return false


## 照明がちらつく → みんなで見上げる → 用務員が来て、ランプの柱をコンコンと叩くと直る（項目 118）。
func _tick_fix_light() -> bool:
	var teacher = actors.lecturer
	var janitor = actors.get("janitor")
	if janitor == null or not _set.has_method("set_lamp_flicker"):
		return true
	var lamp: Vector3 = _set.call("lamp_point")
	match _phase:
		"begin":
			last_event = "fix_light"
			_set.call("set_lamp_flicker", true)
			teacher.ik_off()
			teacher.face_point(lamp)
			_set_cue("look_up")
			_wait = 1.2
			_phase = "look"
		"look":
			teacher.once("T_LookUp", "T_Idle")
			emote(teacher, "?", 1.6)
			for key: String in STUDENTS:
				if _students.has(key) and not bool(_students[key].asleep):
					_fx.append({"kind": "emote", "t": 0.0, "secs": 0.3 + 0.2 * STUDENTS.find(key), "actor": actors[key], "emote": "?", "len": 1.2})
			_show_extra("janitor")
			janitor.walk_to(Vector3(lamp.x - 0.35, 0.0, lamp.z - 0.6), rad_to_deg(atan2(0.35, 0.6)), "G_Idle")
			_phase = "walk"
		"walk":
			if janitor.is_busy():
				return false
			_wait = janitor.once("G_LookUp", "G_Idle") * 0.6
			_phase = "tap"
		"tap":
			_wait = janitor.once("G_PointCheck", "G_Idle") * 0.7
			_phase = "fixed"
		"fixed":
			_set.call("set_lamp_flicker", false)
			emote(janitor, "note", 1.3)
			_set_cue("clap", 2.0, "listen")
			_wait = 1.0
			_phase = "leave"
		"leave":
			janitor.walk_to(EXTRAS.janitor.from, NAN, "G_Idle")
			_leave_when_arrived("janitor")
			teacher.face(CLASS_YAW)
			return true
	return false


func _show_extra(key: String) -> void:
	var actor = actors.get(key)
	if actor == null:
		return
	if not _extras_visible.get(key, false):
		actor.root.position = EXTRAS[key].from
		actor.root.visible = true
		actor.root.process_mode = Node.PROCESS_MODE_INHERIT
		actor.loop("G_Idle", 0.0)
	_extras_visible[key] = true


func _hide_extra(key: String) -> void:
	var actor = actors.get(key)
	if actor == null:
		return
	actor.root.visible = false
	actor.root.process_mode = Node.PROCESS_MODE_DISABLED
	_extras_visible[key] = false


func _leave_when_arrived(key: String) -> void:
	_fx.append({"kind": "leave", "key": key, "t": 0.0})


func _leave_later(key: String, secs: float) -> void:
	_fx.append({"kind": "leave_later", "key": key, "t": 0.0, "secs": secs})


# ------------------------------------------------------------------ students

## 生徒への合図。secs > 0 なら、その秒数のあと after に戻す（拍手・猛烈に写す）。
func _set_cue(cue: String, secs := 0.0, after := "") -> void:
	if cue == "frenzy" and _cue != "frenzy":
		_frenzy_extras()
	elif cue != "frenzy" and _cue == "frenzy":
		_highlighter(false)
	if cue == "frenzy" and secs <= 0.0:
		secs = 3.0
		after = "notes"
	elif cue == "clap" and secs <= 0.0:
		secs = 2.6
		after = "listen"
	_cue = cue
	_cue_left = secs
	_cue_after = after if after != "" else "listen"
	for key: String in _students:
		var brain: Dictionary = _students[key]
		if brain.mode != "answer":
			brain.next = minf(float(brain.next), _rng.randf_range(0.1, 0.7))


func _set_student(key: String, mode: String) -> void:
	if _students.has(key):
		_students[key].mode = mode


func _tick_students(delta: float) -> void:
	var teacher = actors.lecturer
	var pen: Dictionary = _pens.get("lecturer", {})
	var drawing := not pen.is_empty() and str(pen.kind) == "write" and str(pen.phase) == "draw"
	var tip: Vector3 = pen.get("tip_world", Vector3.ZERO) if not pen.is_empty() else Vector3.ZERO
	var talking := _cue in ["listen", "ask", "bow"] and not _pens.has("lecturer")
	var answering := ""
	for key: String in _students:
		if not _seated.get(key, true) and str(_students[key].mode) == "answer":
			answering = key
	for key: String in _students:
		var brain: Dictionary = _students[key]
		var student = actors[key]
		# 体ごと相手のほうへ: 立って答えている級友 > 話している先生 > 黒板（向かない）
		if brain.asleep or not _seated.get(key, true):
			student.look_clear()
		elif answering != "" and answering != key:
			student.look_toward(actors[answering].head_point(), 1.0)
		elif talking:
			student.look_toward(teacher.head_point(), 0.8)
		else:
			student.look_clear()
		if brain.mode == "go_seat":
			if not student.is_busy():
				# 着いた: 横から座る（立ち上がりの逆）
				_stand_offset(key, false)
				student.once("S_SitDown", "S_SitIdle", 0.0)
				brain.mode = ""
				brain.until = student.clip_length("S_SitDown")
			continue
		if brain.mode in ["answer", "away", "lunch"]:
			student.set_speed(1.0)
			continue
		# 先生が 1 画書くたびに鉛筆も動く（項目 59）
		if student.current in ["S_CopyNotes", "S_FastWrite"]:
			student.set_speed(1.0 if drawing or _cue != "notes" else 0.12)
		else:
			student.set_speed(1.0)
		# 先生の体で黒板が見えない → 体を傾けて覗き込む（項目 60）
		brain.peek = float(brain.get("peek", 0.0)) - delta
		if drawing and not brain.asleep and float(brain.peek) <= 0.0 and float(brain.until) <= 0.0 and _seated.get(key, true):
			var eye: Vector3 = student.head_point() + Vector3(0.0, -0.5, 0.0)
			var body: Vector3 = teacher.root.position + Vector3(0.0, 0.9, 0.0)
			var seg := tip - eye
			var t := clampf((body - eye).dot(seg) / maxf(0.001, seg.length_squared()), 0.0, 1.0)
			if (eye + seg * t).distance_to(body) < 0.55:
				var side_left := (body - eye).cross(seg).y > 0.0
				var clip := "S_PeekRight" if side_left else "S_PeekLeft"
				student.once(clip, student.base_clip)
				brain.until = student.clip_length(clip)
				brain.peek = 6.0
				continue
		if key == "student_doze":
			var dozing: bool = str(brain.mode) == "" and _seated.get(key, true)
			student.zzz = 0.0 if not dozing else ((1.0 + 0.4 * clampf((0.2 - _bgm) / 0.2, 0.0, 1.0)) if brain.asleep else (0.4 if float(brain.drowsy) > DOZE_DRIFT else 0.0))
		brain.until = float(brain.until) - delta
		if float(brain.until) > 0.0:
			continue
		# 居眠り（居眠り役だけ）: 話を聞いている間にだんだん眠くなる
		if key == "student_doze":
			# BGM が小さいほど眠くなり、大きいとそわそわして眠気が飛ぶ
			var lull := 1.0 + 2.5 * clampf((0.25 - _bgm) / 0.25, 0.0, 1.0) - 1.4 * clampf((_bgm - 0.75) / 0.25, 0.0, 1.0)
			brain.drowsy = float(brain.drowsy) + delta * (1.6 if _cue in ["listen", "notes"] else 0.6) * lull
			if brain.asleep and _bgm > 0.9 and float(brain.until) <= 0.0 and _rng.randf() < delta * 0.3:
				_wake_student(key)
				continue
			if brain.asleep:
				if student.current != "S_SleepSlumped" and not student.is_busy():
					student.loop("S_SleepSlumped")
				continue
			if float(brain.drowsy) > DOZE_SLEEP:
				brain.asleep = true
				student.set_eyes("closed")
				student.once("S_Faceplant", "S_SleepSlumped")
				brain.until = student.clip_length("S_Faceplant")
				continue
			if float(brain.drowsy) > DOZE_DRIFT:
				if student.current != "S_DozeDrift" and student.current != "S_Teeter":
					student.set_eyes("half")
					student.loop("S_DozeDrift")
				elif student.current == "S_DozeDrift" and _rng.randf() < delta * 0.06:
					# 椅子から落ちかけて足をばたばた（項目 76）
					student.once("S_Teeter", "S_DozeDrift")
					brain.until = student.clip_length("S_Teeter")
					emote(student, "!", 1.0)
					_fx.append({"kind": "emote", "t": 0.0, "secs": 1.1, "actor": student, "emote": "sweat", "len": 1.4})
				continue
		brain.next = float(brain.next) - delta
		if float(brain.next) > 0.0:
			continue
		brain.next = _rng.randf_range(2.5, 6.0)
		var base := "S_SitIdle"
		var extras: Array = []
		match _cue:
			"listen", "bow":
				base = "S_LookBoard"
				extras = ["S_PeekLeft", "S_PeekRight", "S_PageFlip"]
			"notes":
				base = "S_FastWrite" if key == "student_notes" and _rng.randf() < 0.35 else "S_CopyNotes"
				extras = ["S_Erase", "S_PageFlip", "S_Sharpen", "S_PeekLeft"]
			"frenzy":
				base = "S_Frenzy"
				brain.next = _rng.randf_range(2.0, 3.0)
			"ask":
				base = "S_RaiseHandEager" if key == "student_hand" else ("S_RaiseHand" if _rng.randf() < 0.6 else "S_LookBoard")
				if key == "student_doze" or bool(step.get("nobody", false)):
					base = "S_LookBoard"
				brain.next = 9.0
			"clap":
				base = "S_Clap"
				brain.next = _rng.randf_range(2.2, 3.0)
			"look_up":
				base = "S_LookBoard"
				extras = ["S_TurnLeft", "S_TurnRight"]
		if key == "student_hand":
			extras.append("S_FixCap")
		if key == "student_notes" and _cue == "notes":
			extras.append("S_HideNotes")
		student.set_eyes("open")
		if not extras.is_empty() and _rng.randf() < 0.3:
			var clip: String = extras[_rng.randi() % extras.size()]
			student.once(clip, base)
			brain.until = student.clip_length(clip)
			if clip == "S_Sharpen":
				# 芯が折れた → 鉛筆削り（項目 63）
				emote(student, "!", 0.9)
		else:
			student.loop(base, 0.35)
	if _cue_left > 0.0:
		_cue_left -= delta
		if _cue_left <= 0.0:
			_set_cue(_cue_after)


# ------------------------------------------------------------------ tray dust（項目 33）

## チョーク受けに積もる粉: 黒板の幅の細長い板に、消した場所ほど白くなる絵を貼る。掃除で消える。
const DUST_PX := 512
var _tray_dust: MeshInstance3D = null
var _tray_dust_image: Image = null
var _tray_dust_texture: ImageTexture = null


func _make_tray_dust() -> void:
	_tray_dust_image = Image.create(DUST_PX, 8, false, Image.FORMAT_RGBA8)
	_tray_dust_image.fill(Color(0.94, 0.94, 0.9, 0.0))
	_tray_dust_texture = ImageTexture.create_from_image(_tray_dust_image)
	var quad := QuadMesh.new()
	quad.size = Vector2(BOARD_SIZE.x, 0.11)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _tray_dust_texture
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = material
	_tray_dust = MeshInstance3D.new()
	_tray_dust.name = "TrayDust"
	_tray_dust.mesh = quad
	_tray_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 黒板の幅の中心、トレイの上面のすぐ上に寝かせる（u は -X へ: 板の +X 側が u = 0）
	_tray_dust.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).rotated(Vector3.UP, PI),
		Vector3(0.0, TRAY_TOP + 0.002, TRAY_Z))
	_set.add_child(_tray_dust)


## 黒板の u0..u1 を消した: その下のトレイに粉が少し積もる。
func _add_tray_dust(u0: float, u1: float, amount := 0.08) -> void:
	if _tray_dust_image == null:
		return
	var x0 := clampi(int(u0 / BOARD_SIZE.x * DUST_PX), 0, DUST_PX - 1)
	var x1 := clampi(int(u1 / BOARD_SIZE.x * DUST_PX), 0, DUST_PX - 1)
	for x in range(x0, x1 + 1):
		for y in range(8):
			var c := _tray_dust_image.get_pixel(x, y)
			var grain := _rng.randf_range(0.4, 1.0) * (1.0 - absf(y - 3.5) / 5.0)
			c.a = clampf(c.a + amount * grain, 0.0, 0.75)
			_tray_dust_image.set_pixel(x, y, c)
	_tray_dust_texture.update(_tray_dust_image)


func _clear_tray_dust() -> void:
	if _tray_dust_image != null:
		_tray_dust_image.fill(Color(0.94, 0.94, 0.9, 0.0))
		_tray_dust_texture.update(_tray_dust_image)


# ------------------------------------------------------------------ emotes (漫符)

func _load_emotes() -> void:
	if fx_scene == null:
		return
	var root := fx_scene.instantiate()
	for kind: String in EMOTES:
		var node := root.find_child(str(EMOTES[kind]), true, false) as MeshInstance3D
		if node != null:
			var copy := node.duplicate() as MeshInstance3D
			copy.transform = Transform3D.IDENTITY
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_emote_meshes[kind] = copy
	root.free()


## actor の頭の上に漫符を出す（ポンと出て、少し弾み、secs 秒で縮んで消える）。同じ人の前の漫符は消す。
func emote(actor, kind: String, secs := 1.6) -> void:
	if actor == null or not _emote_meshes.has(kind):
		return
	for item: Dictionary in _emotes:
		if item.actor == actor and is_instance_valid(item.node):
			item.secs = minf(float(item.secs), float(item.t) + 0.15)
	var node := (_emote_meshes[kind] as MeshInstance3D).duplicate() as MeshInstance3D
	node.scale = Vector3.ONE * 0.001
	_set.add_child(node)
	_emotes.append({"node": node, "actor": actor, "kind": kind, "t": 0.0, "secs": secs,
		"side": 1.0 if _rng.randf() < 0.5 else -1.0})


func _tick_emotes(delta: float) -> void:
	if _emotes.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	var keep: Array = []
	for item: Dictionary in _emotes:
		var node: MeshInstance3D = item.node
		item.t = float(item.t) + delta
		var t := float(item.t)
		var secs := float(item.secs)
		if not is_instance_valid(node) or t >= secs:
			if is_instance_valid(node):
				node.queue_free()
			continue
		var actor = item.actor
		var head: Vector3 = actor.head_point()
		var kind := str(item.kind)
		var at := head + Vector3(0.0, 0.12 + 0.025 * sin(t * 7.0), 0.0)
		if kind == "sweat":
			# 汗は頭の横を少し流れ落ちる
			at = head + actor.root.basis.x.normalized() * 0.42 * float(item.side) + Vector3(0.0, -0.12 - 0.08 * minf(t, 1.0), 0.0)
		elif kind == "anger":
			at = head + actor.root.basis.x.normalized() * 0.3 * float(item.side) + Vector3(0.0, 0.02, 0.0)
		node.position = at
		if camera != null:
			var cam_local := _set.to_local(camera.global_position)
			var flat := Vector3(cam_local.x, at.y, cam_local.z)
			if flat.distance_to(at) > 0.01:
				node.look_at(_set.to_global(flat), Vector3.UP)
		# ポン（はみ出してから戻る）→ 消える前に縮む
		var pop := 1.0
		if t < 0.28:
			pop = lerpf(0.0, 1.22, t / 0.18) if t < 0.18 else lerpf(1.22, 1.0, (t - 0.18) / 0.1)
		if t > secs - 0.2:
			pop *= clampf((secs - t) / 0.2, 0.0, 1.0)
		if kind == "anger":
			pop *= 1.0 + 0.12 * absf(sin(t * 9.0))
		node.scale = Vector3.ONE * maxf(0.001, pop * EMOTE_SCALE)
		keep.append(item)
	_emotes = keep


## 「テストに出る」: ひとりだけ蛍光ペンに持ち替え（項目 65）、居眠りの生徒は飛び起きて猛烈に写し、
## 少しするとまた寝る（項目 73）。
func _frenzy_extras() -> void:
	_highlighter(true)
	if _students.has("student_doze") and bool(_students.student_doze.asleep):
		var doze = actors.student_doze
		_wake_student("student_doze")
		_students.student_doze.mode = "answer"
		_fx.append({"kind": "call", "t": 0.0, "secs": doze.clip_length("S_WakeJolt") * 0.8, "fn": func() -> void:
			doze.loop("S_Frenzy", 0.1)
			_fx.append({"kind": "call", "t": 0.0, "secs": 3.0, "fn": func() -> void:
				_students.student_doze.mode = ""
				_students.student_doze.drowsy = DOZE_SLEEP - 4.0
			})
		})


var _marker: MeshInstance3D = null


func _highlighter(on: bool) -> void:
	var notes = actors.get("student_notes")
	if notes == null:
		return
	if on and _marker == null:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.016
		mesh.bottom_radius = 0.018
		mesh.height = 0.16
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.92, 0.1)
		material.emission_enabled = true
		material.emission = Color(0.9, 0.85, 0.05)
		material.emission_energy_multiplier = 0.4
		material.roughness = 0.4
		_marker = MeshInstance3D.new()
		_marker.mesh = mesh
		_marker.material_override = material
		notes.hold("L", _marker, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.26, 0.0)))
		emote(notes, "bulb", 1.0)
	elif not on and _marker != null:
		var item: Node3D = notes.drop("L")
		if item != null:
			item.queue_free()
		_marker = null


# ------------------------------------------------------------------ fx

func _make_dust() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			image.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
	_dust_texture = ImageTexture.create_from_image(image)
	_dust = _particles(10, 0.9, 0.006, 0.018)
	_dust.name = "ChalkDust"
	_dust.emitting = false
	_dust.one_shot = false
	_set.add_child(_dust)


## 粉の粒子。大きさは板ポリそのもので決める（ビルボードの粒子では scale_amount が効かず、1 m の板になって
## 白いもやに見えた）。size_min..size_max は粒の直径（m）。
func _particles(amount: int, lifetime: float, size_min: float, size_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size_max, size_max)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _dust_texture
	quad.material = material
	p.mesh = quad
	p.direction = Vector3(0.0, -0.3, -1.0)
	p.spread = 70.0
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.12
	p.gravity = Vector3(0.0, -0.25, 0.0)
	p.damping_min = 0.4
	p.damping_max = 0.8
	p.scale_amount_min = size_min / size_max
	p.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.95, 0.95, 0.92, 0.55))
	ramp.set_color(1, Color(0.95, 0.95, 0.92, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 粉の煙をひと吹き（size: 0 小 〜 3 大）。
func _puff(at: Vector3, size: int, strength: float) -> void:
	var p := _particles(10 + 10 * size, 1.1 + 0.3 * size, 0.03 + 0.02 * size, 0.08 + 0.05 * size)
	p.one_shot = true
	p.explosiveness = 0.85
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.1 * (1.0 + strength)
	p.initial_velocity_max = 0.35 * (1.0 + strength)
	p.gravity = Vector3(0.0, -0.08, 0.0)
	p.position = at
	_set.add_child(p)
	p.emitting = true
	_fx.append({"kind": "free", "node": p, "t": 0.0, "secs": p.lifetime + 0.5})


func _puff_later(delay: float, actor, size: int, strength: float, both_hands := false) -> void:
	_fx.append({"kind": "puff", "t": 0.0, "secs": delay, "actor": actor, "size": size, "strength": strength,
		"both": both_hands})


## 小道具を放物線で飛ばす（hit: 当たったら跳ね返って床へ落ちる）。
func _throw_prop(node: Node3D, from: Vector3, to: Vector3, secs: float, arc: float, hit: bool) -> void:
	if node.get_parent() != _set:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_set.add_child(node)
	node.position = from
	_fx.append({"kind": "fly", "node": node, "from": from, "to": to, "t": 0.0, "secs": secs, "arc": arc, "hit": hit,
		"spin": Vector3(_rng.randf_range(8, 14), _rng.randf_range(-4, 4), _rng.randf_range(6, 12))})


func _tick_fx(delta: float) -> void:
	var keep: Array = []
	for item: Dictionary in _fx:
		item.t = float(item.t) + delta
		var done := false
		match str(item.kind):
			"free":
				done = float(item.t) >= float(item.secs)
				if done and is_instance_valid(item.node):
					(item.node as Node).queue_free()
			"puff":
				if float(item.t) >= float(item.secs):
					var actor = item.actor
					var at: Vector3 = actor.hand_tip_point()
					if item.get("both", false):
						at = (at + actor.hand_tip_point("L")) * 0.5
					_puff(at + Vector3(0.0, 0.1, 0.0), int(item.size), float(item.strength))
					done = true
			"fly":
				var node: Node3D = item.node
				if not is_instance_valid(node):
					done = true
				else:
					var u := clampf(float(item.t) / float(item.secs), 0.0, 1.0)
					var p := (item.from as Vector3).lerp(item.to, u) + Vector3.UP * 4.0 * float(item.arc) * u * (1.0 - u)
					node.position = p
					node.rotation += (item.spin as Vector3) * delta
					if u >= 1.0:
						done = true
						if item.hit:
							# 跳ね返って床へ
							var bounce_to := (item.to as Vector3) + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, -0.6)
							bounce_to.y = 0.02
							keep.append({"kind": "fly", "node": node, "from": item.to, "to": bounce_to, "t": 0.0,
								"secs": 0.6, "arc": 0.25, "hit": false, "spin": item.spin})
						else:
							keep.append({"kind": "free", "node": node, "t": 0.0, "secs": 6.0})
			"call":
				if float(item.t) >= float(item.secs):
					(item.fn as Callable).call()
					done = true
			"glint":
				var node: Node3D = item.node
				var u := float(item.t) / float(item.secs)
				if u >= 1.0 or not is_instance_valid(node):
					if is_instance_valid(node):
						node.queue_free()
					done = true
				else:
					node.scale = Vector3.ONE * maxf(0.001, sin(u * PI) * 1.2)
					node.rotation.z = u * 1.2
			"emote":
				if float(item.t) >= float(item.secs):
					emote(item.actor, str(item.emote), float(item.len))
					done = true
			"leave":
				var actor = actors.get(item.key)
				done = actor == null or not actor.is_moving()
				if done and actor != null:
					_hide_extra(str(item.key))
			"leave_later":
				if float(item.t) >= float(item.secs):
					var actor = actors.get(item.key)
					if actor != null:
						actor.walk_to(EXTRAS[item.key].from, NAN, "G_Idle")
						keep.append({"kind": "leave", "key": item.key, "t": 0.0})
					done = true
		if not done:
			keep.append(item)
	_fx = keep
