# 段階4 コース① の設計（v1）

2026-10-25。[計画書](plan.md) の段階4（コース① の 1-3〜1-7 と、そのための仕組み）の設計。
台本は [course1_script.md](course1_script.md)、土台は [foundation_design.md](foundation_design.md)（段階3）。旧チュートリアルは参照しない（撤去済み）。

## 0. 段階4で「できた」と言える状態

1. コース① が 1-1 から 1-7、クリアまで台本どおりに通る（1人）
2. 看板の壁（ドアの代わりにパネル2枚）が 1-1・1-2・1-6・1-7 の始めに出る。空から落ちて、用が済むと空へ戻る
3. クイズ壁は空から落ちてくる。1-3・1-4 はミスでまきもどし、1-5 はハートが減る（1より減らない）、1-7 は本番どおり
4. まきもどしで、体・サメ・壁の見た目が元に戻る。2回失敗で床の矢印、3回失敗で壁が半分の速さ（1-7 は自動の速さを一番遅く）
5. 1-6 のハテナの実演（端まで歩く → 海に落ちる → サメが近づく → 雲で戻る）と、端の赤い光・黄色のゾーン
6. 1-7 のカウントダウン・「しあげ 1/3」・ボス壁・負けたときのやり直し（ゲームオーバーの画面は出さない）
7. クリアの花火・歓声・ウェーブ。しあげでハートが減らなければ★
8. 本編（10問・エンドレス・2人・オンライン・リプレイ）の動きは変わらない

## 1. 担当とファイル

| 担当 | 触るファイル |
|---|---|
| A（本編側） | `scripts/core/game_state.gd`・`scripts/core/match_rules.gd`・`scripts/world/game_world.gd`・`scripts/world/player_controller.gd`・`scripts/world/camera_controller.gd`・`scripts/ui/gameplay_hud.gd`・`scripts/ui/player_health_hud.gd`・`scripts/ui/death_wipe.gd`・`scripts/world/crowd/crowd_cues.gd`・`scripts/core/wall_speed_planner.gd`・`tests/practice_unit.gd`・`tests/practice_unit_bootstrap.gd` |
| B（台本側） | `scripts/practice/` の下の全部（`courses/course_1.gd`・`practice_director.gd`・`ui/practice_overlay.gd` など）・`tests/practice_smoke_runtime.gd`・`tests/practice_smoke_bootstrap.gd` |
| C（舞台の小物） | `scripts/world/practice/` の下の全部（`hatena_guide.gd` と新しいファイル）・新しいテスト `tests/practice_props_preview*.gd` |

- 担当どうしで同じファイルを触らない。ほかの担当の道具が要るときは、この文書の約束（名前・引数・動き）どおりに呼ぶ。約束と違うことが必要になったら、自分で相手のファイルを直さず、報告に書く
- 座標はゲーム画面のもの（`WallContainer` と同じ。原点で回転なし）：x は +が画面の左、y は高さ、z はコンベア上の前。プレイヤーの立つ所は `game_state.player_x`・`player_local_z`。いまの壁の z は `game_state.wall_z - game_state.world_scroll_z`
- 2択のドア：番号 0 が青（x = +3.5、画面の左）、1 が赤（x = −3.5）。4択：番号 0 青（x = −5.8、画面のいちばん右）・1 緑（−1.95）・2 オレンジ（+1.95）・3 赤（+5.8、いちばん左）
- 床：左右の端は x = ±12、うしろの端はコンベア上の z = −12.5（`QuizGameState.FLOOR_BACK_Z` を確かめて使う）

## 2. 担当 A：本編側の約束

### 2.1 `MatchRules` に足す

```gdscript
## 自動の速さ（world_speed < 0）のとき、壁の速さの自動計算の「調子」を一番遅い値で計算する。保存されている調子は変えない。
var slow_auto_speed := false
```

`duplicate_rules()` にも足す。

### 2.2 壁が空から落ちる

- 練習のときだけ、新しく作った壁（`_update_walls` で足した壁）は空から落ちてくる。本番の空撮の壁の落ち方（`PREVIEW_WALL_DROP_*`）と同じ見た目・音（`wall_land`）・土ぼこり・小さな揺れ。何枚か同時に作ったときは少しずつずらす
- 着地したら `game_state.practice_wall_landed(wall_index: int)` を出す（game_state の signal。ゲーム画面が `game_state.notify_practice_wall_landed(index)` を呼んで出す）
- `game_state.practice_drop_current_wall(distance: float)`：いまの壁を P1 から distance m 先へ置き直し、空から落とし直す（着地で `practice_wall_landed`）
- `practice_place_current_wall(distance)` は今までどおり（落とさずに置き直す。まきもどしで使う）
- `set_practice_quizzes` で、いまある壁の問題が変わったときは、その壁の選択肢の数（2・4）とボスの見た目も作り直す

### 2.3 見た目を戻す

- `practice_revive(player_index)` と `start_practice_round(...)` のあと、次のフレームにはプレイヤーが普通に立って見える：爆散した体の破片・隠した体・ラグドール・のけぞり・サメの襲撃（`_ocean_attack_sharks`）・サメの画面の光（HUD と `DeathWipe`）・海に浮いた見た目を全部戻す
- `practice_place_player` も、海で待っている人を床へ戻したときは同じく戻す
- やり方は A に任せる（例：game_state に `signal practice_player_reset(player_index)` を足し、ゲーム画面が受けて `PlayerController` に戻させる）

### 2.4 練習の負け（1-7）

- 練習で、本番どおりのルール（`hp_enabled`・`mistakes = NORMAL`・`ocean = NORMAL`）のときに全員がアウトになったら、`game_state.practice_round_lost(reason: StringName)` を1回出す（`&"hp"` か `&"ocean"`）
- 体が崩れる・サメにかまれる演出と観客の反応は本番どおりに出す。**ゲームオーバーの画面・結果のカード・投げ縄（雲で運ぶ演出）・リトライの案内・曲の切り替え・画面の移動は出さない**
- そのあと監督が `start_practice_round(...)` でやり直す（2.3 で見た目も戻る）。ゲームオーバーの状態のままでも、`start_practice_round` を呼べばやり直せること

### 2.5 ハートの表示（1-5）

- ハートは今までどおり `uses_hp()`（= `hp_enabled`）のときだけ出る
- `game_world.practice_hearts_intro(player_index := 1) -> void`：ハートがポンと出て光り、そのあと1つずつ順に光る（合わせて約2秒）
- 練習でハートが減ったとき、減ったハートの枠が赤く点滅する（約1.5秒）。増えるときは本編の増える動き（なければキラッと光る動きを足す）

### 2.6 ゲーム画面の道具（`game_world.gd` に足す。監督は `d.world` から呼ぶ）

| 道具 | 動き | 使う所 |
|---|---|---|
| `practice_celebrate()` | 本番のクリアの花火（`spawn_fireworks`）と歓声 | クリア |
| `practice_crowd_wave()` | 観客のウェーブを起こす | クリア |
| `practice_camera_look(point: Vector3, seconds: float)` | 遊ぶときのカメラのまま、point のほうへなめらかに向ける（少し右を向く程度） | 1-6 の実演 |
| `practice_camera_release(seconds: float)` | 元の向きへなめらかに戻す | 1-6 |
| `practice_camera_intro(seconds := 2.0)` | 少し高い所から舞台全体を見せ、seconds かけてプレイヤーの後ろ（いつもの位置）へ下りる | 1-1 |
| `practice_splash(point: Vector3)` | 海に落ちたときの水しぶき（`spawn_ocean_splash` と音） | 1-6 のハテナ |
| `practice_shark_approach(target: Vector3) -> Node3D` | 海のサメを1匹、target（海面の点）へ向かって泳がせる。ひれが見える。**かみつかない**（近くまで来たら、その場でうろうろする） | 1-6 の実演 |
| `practice_shark_cancel()` | そのサメを海の中へ帰す | 1-6 |
| `practice_wall_node(wall_index: int) -> Node3D` | その番号の壁のノード（なければ null）。的のマークを子に付けるのに使う | 1-5 |

### 2.7 テスト

- `tests/practice_unit.gd` に足す：`slow_auto_speed` の写し、`practice_drop_current_wall` の置き直し、練習の負けで `practice_round_lost` が1回出てゲームオーバーの画面へ進まないこと（ヘッドレスで見られる範囲）、`practice_revive` のあとの状態
- 本編の既存テスト（HP・押し合い・結果の演出・横移動・ドアの選択肢・オンラインメニュー）が今までどおり通ること

## 3. 担当 C：舞台の小物の約束

### 3.1 看板の壁 `PracticeSignWall`（新しいファイル `scripts/world/practice/sign_wall.gd`、Node3D）

- 見た目：本番のクイズ壁（`scripts/world/quiz_wall.gd`・`wall_materials.gd`）と同じ灰色の壁と、上の紺色の問題パネル。ドアの代わりに、大きなパネルを2枚（ドアの位置 x = ±3.5 あたり、ドアより大きめ）。14m 先から読める大きさの文字
- このノードの位置は壁の足もとの真ん中（ゲーム画面の座標）。監督が `world` の子にして置く

```gdscript
func setup(quality: String) -> void
func set_title(lines: PackedStringArray) -> void   # 問題パネル。2行まで
## パネル2枚。各 {"key": StringName, "glyph": "←", "sub": "A"} か {"key": StringName, "picture": &"question" / &"wave" / &"shark"}
func set_panels(panels: Array) -> void
func tick_panel(key: StringName) -> void   # 光って ✓ が付く
func is_panel_done(key: StringName) -> bool
func blink_panels() -> void                # 1秒ほど点滅（「キーを おして みて」）
func drop_in(seconds := 0.55) -> Signal    # 空から落ちて着地（土ぼこり・wall_land の音）。着地で返る
func fly_away(seconds := 0.6) -> Signal    # 空へ戻って見えなくなる。返ったら queue_free してよい
```

- 絵は手で描く（テクスチャを作らずに、メッシュ・Label3D・SubViewport の 2D 描画などで）：「？」、波（青い波線）、サメ（海と灰色のひれ）

### 3.2 床の印 `PracticeFloorMarks`（新しいファイル `scripts/world/practice/practice_floor_marks.gd`、Node3D）

- 監督が `world` の子にして1つ置く。床の少し上に描き、プレイヤーの体より下に見える

```gdscript
func show_edge_glow(sides: Array) -> void       # &"left" / &"right" / &"back"。床の端（左右のレール x = ±12、うしろ z = −12.5）が赤く脈打つ
func show_zones(zones: Array) -> void           # Rect2（x の範囲, z の範囲）の黄色い半透明の帯（ギリギリ ゾーン）
func flash_zone(index: int) -> void             # そのゾーンを一瞬明るく（ピコンのとき）
func show_arrow(from: Vector2, to_x: float) -> void   # from（x, z）の床から、x = to_x のドアのほうへ向く矢印。脈打つ
func hide_arrow() -> void
func flash_fence(point: Vector3) -> void        # 見えないさくにさわった所が、うっすら光って消える（0.5秒）
func clear_all() -> void
static func make_target_mark() -> Node3D         # 的のマーク（壁の前面に付ける。監督が壁のノードの子にする。中心が原点、前は −z）
```

### 3.3 ハテナ `HatenaGuide`（`scripts/world/practice/hatena_guide.gd`）に足す

本物の動き（ライブの Blender で作る）は段階9。いまは位置・回転・大きさの動きと、客席のハテナの動きの組み合わせで作る。

```gdscript
func walk_to(pos: Vector3, speed := 2.2) -> Signal    # 床の上を歩く（上下にはずむ）。着いたら返る
func fall_into_sea(pos: Vector3, seconds := 0.7) -> Signal   # 足をすべらせ、放物線で海面の pos へ落ちる。着水で返る
func set_flailing(on: bool) -> void                   # 海でじたばた（体をゆらし、腕の動き）
func ride_cloud_to(pos: Vector3, seconds := 1.4) -> Signal   # 雲が飛んできて足もとに入り、乗って pos へ飛ぶ。着いたら返る（雲は出たまま）
func tremble(seconds := 1.2) -> void                  # 雲の上でぶるぶる
func spin() -> void                                   # くるっと1回転（0.5秒）
func dodge(side: float) -> void                       # 横へひょいとよけて戻る（side は +1 左 / −1 右）
func play(action)                                     # 今までの名前に &"cross"（×のポーズ）・&"tilt"（首をかしげる）を足す。仮の動きでよい
```

- 海面の高さは `StageConstants.OCEAN_SURFACE_Y` を使う

### 3.4 テスト

- `tests/practice_props_preview_bootstrap.gd`（ウィンドウあり）：看板の壁（1-1・1-2・1-6 の中身）、床の印（端の光・ゾーン・矢印）、的のマーク、ハテナの新しい動きを並べて撮り、`artifacts/practice_props/` に保存する。カメラはゲームと同じ高さ・向き（プレイヤーの後ろ）から撮る

## 4. 担当 B：台本側

### 4.1 レッスン

[course1_script.md](course1_script.md) の 1-1〜1-7・クリアを台本どおりに作る。文字はすべて `PracticeTexts` の ID で出す（4章の一覧）。

- 1-1・1-2：看板の壁（C）を使う。今の 2D の看板の文字とチェックのカード（`PracticeOverlay.set_sign`・`show_checks`）は使わない。1-1 でカメラの入り（A の `practice_camera_intro`）
- 1-3・1-4：`REPORT_ONLY`。違うドア・壁に当たったら、コンベアを止めてから言葉 → まきもどし（`fail_step`）。戻った後の壁は 12m 先（`practice_place_current_wall(12)`）
- 1-5：`hp_enabled`・`hp_floor = 1`・`mistakes = NORMAL`。始めに `practice_hearts_intro`。壁Bには的のマーク（C の `make_target_mark` を `practice_wall_node` の子に）。台本の「想定外のこと」も全部
- 1-6：コンベアを止める・さくを外す・`ocean = REPORT_AFTER_BITE`。ハテナの実演（C のハテナの動き・A のサメ・カメラ・水しぶき）。床の印（端の光・ゾーン）。落ちたら「おちちゃった！」→ まきもどし（そのタスクの始めへ）
- 1-7：本番どおり（`hp_enabled`・`NORMAL`・自動の速さ）。看板の壁が空へ戻る → 3秒のカウントダウン（オーバーレイ、本番の `countdown_beep`・`countdown_go`）→ 3枚（3枚目はボス、4択）。負けたら（A の `practice_round_lost`）「おしい！」→「もういちど！」→ `start_practice_round` でしあげの最初から。3回失敗で `slow_auto_speed`
- クリア：A の `practice_celebrate`・`practice_crowd_wave`。しあげでハートが1つも減らなければ★

### 4.2 監督 `PracticeDirector` に足す

- ハテナは**いまの壁の前**（x = +9.5、壁の z の 1.2m 手前）に立ち、壁といっしょに動く。壁が変わると次の壁へジャンプ（0.8秒）。次の壁がないときはプレイヤーの3m前。プレイヤーが近くで壁に当たりそうなら `dodge`
- 失敗の回数：2回で正解のドアへの床の矢印（C の `show_arrow`）と「やじるしの ほうへ！」、3回で練習の壁の速さを半分（1.6 → 0.8 m/s）。1-7 は 3回で `slow_auto_speed`
- 見えないさくにさわったら：さわった所が光る（C の `flash_fence`）と「ぽよん」の音（仮の音でよい）
- オーバーレイに足す：「しあげ 1/3」の表示、3秒のカウントダウン

### 4.3 テスト

- `tests/practice_smoke_runtime.gd`：コース① を 1-1 からクリアまで、キー入力で通す（各レッスンで正解・失敗・まきもどしの両方を少なくとも1回）。要所の画面を `artifacts/practice_smoke/` に撮る
- `tests/practice_unit.gd` は A の担当。B の確かめは実機の通しテストで行う

## 5. 作りながら決めたこと（2026-10-25）

- **1-6 の海**：端のすぐ外の海は床の土台に隠れて見えないので、ハテナが落ちる所を x = −15.5（端から 3.5m 外）にした。カメラは `practice_camera_frame` で床と観客席の間の海の上（目 (−13.8, −5, −1.5)、注視点 (−15.5, −9, 7)）へ移り、ハテナはカメラのほうを向いてじたばたする。サメは観客席の柱に隠れないよう、その海をまっすぐ前から泳いで来る
- **1-6 タスクB**：1人のカメラでは床のうしろの端は映らない。カメラは本番のままにして、本番の HUD の「うしろの端に近い」警告（画面の点滅）を合図にする。床の赤い光と黄色のゾーンは台本どおり出す
- **壁の問題文**：練習では本番の問題文の整形を通さず、台本の分かち書きと改行のまま出す。行の途中では折り返さない（`QuizWall.keep_question_lines`）
- **1-7 の始め**：言葉2つとカウントダウンの間（約7秒）は操作をロックする（壁が出る前に海に落ちないように）
- **1-6 の始め**：プレイヤーを x 0、z 0 へ戻す（1-5 で前へ走ったままだと、実演とうしろのゾーンが画面に入らない）
- **`slow_auto_speed`**：やさしい問題はもともと最短の速さ（約7.9秒）なので、1-7 の3回失敗で遅くなるのはボス壁だけ（8.4 → 10.0秒）。台本（自動計算の「調子」を一番遅くする）どおり

## 6. 進め方

1. A・B・C は並行して作る。B は A・C の道具がまだないうちは、この約束の名前で呼ぶ形にしておき、`has_method` で確かめてから呼ぶ（なければ何もしない）
2. それぞれ自分のテストを流して報告する
3. 最後に全部をそろえて、コース① の通しテスト（ウィンドウあり）とスクリーンショットで確かめる
