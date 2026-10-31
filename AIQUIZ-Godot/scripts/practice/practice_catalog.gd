class_name PracticeCatalog
extends RefCounted

## 練習の5コースの一覧（docs/new_tutorial/foundation_design.md 6章、plan.md 4章）。番号は台本の番号と同じ。
## title はコース名（PracticeTexts の cN.title。先頭の丸数字も含む）、players は人数（③は人か CPU の2人）、
## minutes は目安の分（台本の合計の時間から）、course_script はコースの台本のスクリプト（PracticeCourse を継ぐ）。
## available = false のコースは、コース選択で「準備中」になって押せない（段階8で ①〜⑤が遊べる）。
## scene は、コースを始める画面（ないときはゲーム画面）。④はオンラインの画面（練習の形）から始まる。
## ⑤はメインメニューの上だけで遊ぶ（course_script はない。scripts/practice/menu/practice_customize_guide.gd）。
## round_players は、ゲーム画面の練習の回の人数（ないときは players）。④は1人で遊ぶが、試合は CPU との2人。

const COURSES: Array[Dictionary] = [
	{"id": "c1", "number": 1, "title": PracticeTexts.TEXTS["c1.title"], "players": 1, "minutes": 3,
		"course_script": "res://scripts/practice/courses/course_1.gd", "available": true},
	{"id": "c2", "number": 2, "title": PracticeTexts.TEXTS["c2.title"], "players": 1, "minutes": 3,
		"course_script": "res://scripts/practice/courses/course_2.gd", "available": true},
	{"id": "c3", "number": 3, "title": PracticeTexts.TEXTS["c3.title"], "players": 2, "minutes": 5,
		"course_script": "res://scripts/practice/courses/course_3.gd", "available": true},
	{"id": "c4", "number": 4, "title": PracticeTexts.TEXTS["c4.title"], "players": 1, "minutes": 3,
		"course_script": "res://scripts/practice/courses/course_4.gd", "available": true,
		"scene": "res://ui/online_menu.tscn", "round_players": 2},
	{"id": "c5", "number": 5, "title": PracticeTexts.TEXTS["c5.title"], "players": 1, "minutes": 3,
		"course_script": "", "available": true, "scene": "res://ui/main_menu.tscn"},
]


## id のコース。ない id は空の辞書。
static func find(id: String) -> Dictionary:
	for course: Dictionary in COURSES:
		if course.id == id:
			return course
	return {}


static func is_available(id: String) -> bool:
	return bool(find(id).get("available", false))


## スタンプのない最初のコース（全部そろっていれば ""）。
static func next_recommended() -> String:
	var manager := _game_manager()
	for course: Dictionary in COURSES:
		if manager == null or not bool(manager.call("has_practice_stamp", course.id)):
			return course.id
	return ""


## GameManager（自動読み込み）。名前を直接書かないのは、テストの --script で先に読まれても読み込めるようにするため。
static func _game_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameManager") if tree != null else null
