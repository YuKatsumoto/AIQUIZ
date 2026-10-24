class_name SuddenDeathPresenter
extends Node3D

## 新サドンデスの種目の見せ方の基底（docs/sudden_death_v2/common.md 8.3節）。監督（HeliSuddenDeathDirector）が
## 分岐・迎え・移動・舞台へ降りる・帰還を受け持ち、種目の舞台・人物の動き・HUD・種目のカメラはここが受け持つ。
## ルールは持たない（QuizGameState.sudden_death_game を読む）。

var director: HeliSuddenDeathDirector = null


func setup(owner_director: HeliSuddenDeathDirector) -> void:
	director = owner_director


## 種目のタイトル（大型ビジョンとカットイン）。
func title(_english: bool) -> String:
	return "SUDDEN DEATH"


## 空のセットの巡航のあとの渡し方："ladder"（地上の種目：雲の覆いの中で舞台へ替え、縄ばしごで降ろす）か
## "skydive"（空中の種目：覆いも縄ばしごもなく、そのまま begin_venue() へ。座席の人形とヘリも種目が動かす）。
func descent_mode() -> String:
	return "ladder"


## 決着のあと、共通の大きな「P1 WIN!」（SuddenDeathHud.show_winner）を出すか。種目が自分で小さく出すなら false。
func shows_winner_banner() -> bool:
	return true


## 決着のあと、迎えのヘリが近づき始めるまでの秒数（その間も pose_winner_waiting を呼ぶ。勝者のダンスなど）。
func extract_delay() -> float:
	return 0.0


## 舞台の組み立ての段（監督が1フレームに1つずつ呼ぶ）。
func preparation_steps() -> Array[Callable]:
	return []


## 描画の予熱（毎フレーム呼ばれ、終わったら true）。
func prewarm_tick() -> bool:
	return true


## 舞台の空と光（空のセットでも使う）。
func environment() -> Environment:
	return null


func set_sun(_active: bool) -> void:
	pass


func set_venue_active(_active: bool) -> void:
	pass


## ヘリから降ろす地点（ワールド、床の高さ）。
func drop_point(_player: int) -> Vector3:
	return Vector3.ZERO


## ヘリが入ってくる向き（ホバーの位置からの差）。
func approach_offset(player: int) -> Vector3:
	return Vector3(18.0, 6.0, 4.0 * (1.0 if player == 1 else -1.0))


## 縄ばしごで降りるとき体を寄せる向き。
func table_direction(_player: int) -> Vector3:
	return Vector3.ZERO


## {"transform", "fov", "cut"}
func descent_camera(_time: float) -> Dictionary:
	return {}


## 2人が着地した（ここから種目の導入・本戦・決着の見せ場）。
func begin_venue() -> void:
	pass


func update_venue(_delta: float) -> void:
	pass


func venue_camera() -> Dictionary:
	return {}


func on_event(_event: Dictionary) -> void:
	pass


func confirm_rules() -> bool:
	return false


## 決着の見せ場が終わった（監督が勝者の迎えへ進む）。
func finale_done() -> bool:
	return false


func winner() -> int:
	return 0


## 勝者を迎えるヘリの縄ばしごの下の地点（ワールド、床の高さ）。
func extract_point(_player: int) -> Vector3:
	return Vector3.ZERO


## 迎えのヘリが来るまでの勝者の姿。
func pose_winner_waiting(_player: int, _time: float) -> void:
	pass


## 監督が勝者の体を縄ばしごの関数へ渡す（種目の姿勢づけをやめる）。
func release_avatar(_player: int) -> void:
	pass


func extract_camera(_player: int, _heli_position: Vector3) -> Dictionary:
	return {}


## ラウンドのある空中の種目（descent_mode "floatplane"、skygate_build_plan.md 4.5）：2人とも着地台に着いて、次のラウンドを待っている。
func round_cleared() -> bool:
	return false


## 迎えの間、大きな見出しを after 秒で下げる。
func hide_banner(_after := 0.0) -> void:
	pass


## 降下が終わって次のラウンドを始める。
func begin_round(_round_number: int) -> void:
	pass


## 降下が終わったときに落ちている位置（腹ばいの体の中心。basis の +Z が頭、+Y が背中）。
func sky_spawn(_player: int) -> Transform3D:
	return Transform3D.IDENTITY


## 空中の落ちる点。
func fall_center() -> Vector3:
	return Vector3.ZERO


## 迎えの水上機を着ける着地台（無ければ null）。
func landing_float() -> LandingFloat:
	return null


## 着地台に立っている人の腰の位置。
func lander_point(_player: int) -> Vector3:
	return Vector3.ZERO


## 着地台に立っている人形を隠す（監督が本物のアバターを出す）。
func set_landers_hidden(_hidden: bool) -> void:
	pass


func teardown() -> void:
	pass


## Frame-time tests: HUD layers follow the director's clock instead of the wall clock.
func debug_step_clock(_seconds: float) -> void:
	pass


func get_debug_snapshot() -> Dictionary:
	return {}
