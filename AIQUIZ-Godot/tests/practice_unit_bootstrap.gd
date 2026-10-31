extends SceneTree

## 新しいチュートリアルの土台（docs/new_tutorial/foundation_design.md 12章）の単体テスト（本編側）。
## テストの本体（tests/practice_unit.gd）は QuizManager などのオートロードを使うので、オートロードが
## できてから読み込む（--script のスクリプトはオートロードより先にコンパイルされるため）。
## 結果：res://artifacts/practice_unit/unit.json と、標準出力の PRACTICE_UNIT {...}
## 実行：Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/practice_unit_bootstrap.gd

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var script := load("res://tests/practice_unit.gd") as Script
	if script == null or not script.can_instantiate():
		push_error("tests/practice_unit.gd could not be loaded")
		quit(1)
		return
	root.add_child(script.new())
