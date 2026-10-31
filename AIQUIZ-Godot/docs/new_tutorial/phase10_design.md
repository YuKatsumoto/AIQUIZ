# 段階10 コース③ 3-1「控え室のノートPC」の設計（v1）

2026-10-29。[コース③の台本](course3_script.md) v0.3 の 3-1 を作るための設計。流れと絵コンテは [laptop_keys/flow.md](laptop_keys/flow.md)・[laptop_keys/room/storyboard_v05.jpg](laptop_keys/room/storyboard_v05.jpg)。
土台は [phase6_design.md](phase6_design.md)（CPU とコース③）と [phase9_design.md](phase9_design.md)（ハテナの動き）。旧チュートリアルは参照しない（撤去済み）。

**進め方**：段階7〜9と同じく担当を同時に動かさない。監督役が順番に作る。3D の部屋とノートPCは、ユーザーが開いているライブの Blender で作る（Higgsfield の `get_host_status` で `blr` の接続を確かめてから。最後に `.blend` を上書き保存する。`AGENTS.md`）。

## 0. 段階10で「できた」と言える状態

1. 3-0 のあと暗転して暗い控え室になり、P1・P2 が机のノートPCの前まで歩く。ハテナは机の上で案内する
2. ノートPCの画面の図と本体のキーが、台本どおりの順にオレンジ（P1）・青（P2）で光る。押した本物のキーは、本体の同じキーが沈んで光る
3. R6 で画面が本物のステージに変わり、そのステージで動く練習ができる（クリア条件は今と同じ）
4. ✓ がそろうと、カメラが画面へまっすぐ寄り（ぶれ・光・粒などの演出なし）、継ぎ目が目立たずに本番の画面へ戻って 3-2 が始まる
5. CPU と・人どうし・スキップ・ポーズのどれでも、控え室を閉じたあと本番の画面（3D・下のカード・ハテナ）が元どおり
6. ③の通しテストが新しい 3-1 で通り、要所のスクリーンショットが絵コンテと見比べてある

## 1. 全体の作り

画面は 3 つの描画の組み合わせにする。控え室は本番のステージとは別の 3D の世界にして、照明（暗い部屋）と本番の太陽・空がまざらないようにする。

```text
root（本番のウィンドウ）
 ├─ 本番のステージ（World3D A）……R1〜R7 は root では描かない（root.disable_3d）
 ├─ GameplayHUD（層 5）……R1〜R7 は隠し、R8 で出す
 ├─ PracticeRoom（CanvasLayer 層 10）……控え室の絵を画面いっぱいに出す
 │    ├─ RoomView（SubViewport、own_world_3d = 控え室の World3D B）
 │    │    控え室・机・ノートPC・控え室の P1／P2・控え室のハテナ・RoomCamera
 │    ├─ StageView（SubViewport、world_3d = World3D A を共有）……StageCamera が本番のカメラをなぞる
 │    └─ ScreenView（SubViewport、2D だけ）……ノートPCの画面の中身（キーの図／StageView の絵＋✓の欄）
 └─ PracticeOverlay（層 20：吹き出し・進み具合）・ポーズ（層 100）……今のまま上に出る
```

- ノートPCの画面のマテリアルは ScreenView の絵を貼るだけ（unshaded）
- R6〜R7 は StageView が本番のステージを描き、ScreenView がそれを画面いっぱいに入れる。R8 で root の 3D を描きはじめてから控え室を消す
- 本番のゲームの進み（物理・入力・壁・CPU）は描くかどうかと関係なく今までどおり動く

## 2. ファイルと部品

| 部品 | ファイル | 役目 |
|---|---|---|
| 控え室とノートPCの 3D | `assets/practice_room/practice_room.glb`（原本 `source/practice_room.blend`、作り方 `source/build_practice_room.py`。ライブの Blender で実行） | 部屋・ロッカー・ベンチ・机・スタンド・ノートPC（本体・ふた・画面・キー1つずつ） |
| `PracticeRoom` | `scripts/practice/room/practice_room.gd`（CanvasLayer） | 3 つの SubViewport・RoomCamera・照明・控え室の P1／P2・控え室のハテナ・開く／閉じる・拡大 |
| `PracticeLaptop` | `scripts/practice/room/practice_laptop.gd`（Node3D） | ふたの開け閉め、キーの点灯・押し込み・点滅、画面のマテリアル |
| `PracticeLaptopScreen` | `scripts/practice/room/practice_laptop_screen.gd`（Control。ScreenView の中） | 画面の中身：起動・キーの図・ステージ＋✓の欄 |
| 3-1 のレッスン | `scripts/practice/courses/course_3.gd` の `KeysStep` を作り直す | 台本どおりに進める |
| 監督の道具 | `scripts/practice/practice_director.gd` | 控え室を開く・閉じる、吹き出しの付け根を控え室のハテナへ |
| 本番側 | `scripts/world/game_world.gd` | 下のカードを隠す・出す（`practice_set_hud_shown(on, seconds)`） |
| 文字 | `scripts/practice/practice_texts.gd` | `c3.pc.labels`・`c3.pc.checks` を足す。`c3.keys.sign` の出る所のコメントを「ノートPCの画面」に |

## 3. 控え室とノートPCの 3D（ライブの Blender）

### 3.1 作るもの（絵コンテ R1〜R7 に合わせる）

- 部屋：奥行き約 6 m・幅約 5 m・天井 2.8 m。暗い木の床、暗い暖色のグレーの壁、窓なし。左の壁にオレンジと青のロッカー 6 本とベンチ。入口は手前
- 机：高さ 0.85 m（P1・P2 の腰の高さ。実機で合わせる）、幅 1.8 m。右の端に小さなスタンド（電球は Godot の OmniLight にする）
- ノートPC：実物の約 2 倍（本体の幅約 0.65 m）。銀の本体、黒い縁、暗いキーボード、明るいグレーのキー。画面は **16:9**（拡大の終わりで画面いっぱいにするため）
- 見た目は本編と同じく、角を丸めたローポリ。テクスチャは使わず色だけ

### 3.2 名前の決まり（Godot がこの名前で探す）

| 名前 | 中身 |
|---|---|
| `Room_*` | 床・壁・天井・ロッカー・ベンチ（まとめてよい） |
| `Desk`・`Lamp` | 机・スタンド（電球の位置に空の `Lamp_Bulb`） |
| `Laptop_Base` | 本体（キーボードの面とタッチパッド） |
| `Laptop_Lid` | ふた。原点を蝶番の線に置き、X 回りに回すと開く（閉じた形で書き出す） |
| `Laptop_Screen` | 画面の板。UV は 0〜1 で画面全体（左上が (0,0)） |
| `Key_<名前>` | キー1つずつ。原点はキーの上の面の真ん中。名前は Godot の `Key` の名前に合わせる：`Key_W`・`Key_A`・`Key_S`・`Key_D`・`Key_Space`・`Key_1`〜`Key_3`・`Key_8`〜`Key_0`・`Key_Up`・`Key_Down`・`Key_Left`・`Key_Right`・`Key_CtrlR`・`Key_CtrlL`。ほかのキーは `Key_Other_<番号>` |
| `Spot_P1`・`Spot_P2`・`Spot_Door_P1`・`Spot_Door_P2`・`Spot_Hatena` | 空（Empty）。机の前の立ち位置・入口の立ち位置・ハテナの座る所 |
| `Cam_R1`・`Cam_R3`・`Cam_R6` | 空。カメラの位置と向き（絵コンテのコマの画角） |

- キーの並びは英語配列のノートPC（数字の列・文字の3列・スペースの列・右下に逆 T の矢印）。日本語配列でも W A S D・矢印・右 Ctrl・数字の位置は同じ
- キーの文字は Blender では描かない。Godot の Label3D で、関係のあるキー（W A S D・スペース・1 2 3・8 9 0・矢印・Ctrl）にだけ出す
- 書き出しの前に、Blender の画面でカメラの空（Cam_R1・R3・R6）から見た確認の絵を撮って、絵コンテと見比べる。最後に `.blend` を上書き保存する

### 3.3 GLB がないとき

`PracticeLaptop` は GLB を読めないとき、箱を並べた仮のノートPCを作る（ほかの練習の小物と同じく、テストと作業の途中で止まらないように）。部屋は床と壁の箱だけ。

## 4. `PracticeRoom`

### 4.1 開く・閉じる

```gdscript
## 3-1 の始めに監督が作る。開くと暗転（0.3 秒）してから控え室を出す。
func open(game_state: QuizGameState, root_camera: Camera3D, with_cpu: bool) -> Signal
## 本番の画面へ戻す。zoom なら R7・R8（画面へ寄る → 控え室を 0.2 秒で消す）、そうでなければすぐ（スキップ・コースをやめる）。
func close(zoom: bool) -> Signal
```

- `open`：RoomView を作り、root の 3D を止め（`get_viewport().disable_3d = true`）、本番の下のカードを隠す（`practice_set_hud_shown(false, 0.0)`）
- `close`：root の 3D を戻し、**1 フレーム描いてから** 控え室を消す（黒い 1 フレームを出さない）。下のカードは 0.4 秒で出す
- 控え室のノードは、コースが終わる（監督が消える）まで残し、閉じたら隠して SubViewport の更新を止める。`world_3d` を null に戻さない（`death_wipe.gd` の注意と同じ。描いている途中に外すと落ちることがある）

### 4.2 カメラ

- RoomCamera は GLB の空 `Cam_R1`・`Cam_R3`・`Cam_R6` の間を動く（R2 は R1 → R3 へ 2.5 秒、R6 は R3 → R6 へ 0.6 秒。どちらも smoothstep）
- **R7 の拡大**：画面の板の真正面で、画面がちょうど画面いっぱいになる位置へ 1.2 秒でまっすぐ寄る。距離は `(画面の高さ / 2) / tan(縦の画角 / 2)`。画角は変えない。ぶれ・光・粒は付けない。ウィンドウが 16:9 でないときは、はみ出す側に合わせる（覆うように）
- StageCamera は毎フレーム、本番のカメラ（`get_viewport().get_camera_3d()` を 3D を止める前に覚えておく）の位置・向き・画角・near/far・environment・attributes をなぞる。StageView の大きさは root と同じ

### 4.3 色（R8 のつなぎ目）

- 本番のステージは ACES のトーンマップ（`stage_environment.gd`）。StageView の絵はトーンマップ済みなので、控え室でもう一度かけると暗く・くすんで、R8 で色が跳ぶ
- 控え室の Environment は **トーンマップ Linear・露出 1.0**、グローは画面の明るさ（1.0 以下）では光らない閾値にする。画面のマテリアルは unshaded
- それでも残る差は、R8 の 0.2 秒の重ね（控え室を薄くしていく）で隠す。テストで R7 の終わりと R8 の始めの画面の平均の色を比べる（差が大きければ控え室の Environment を直す）

### 4.4 照明（暗い部屋）

- 天井の明かりはなし。Environment の環境光はごく弱い青みのグレー、空は黒
- スタンドの電球（OmniLight、暖色、影あり。品質「低」では影なし）
- 画面の明かり（画面の前に OmniLight。色と強さは画面の中身で変える：起動とキーの図は青白く弱め、ステージは明るい空色）。キーが光るときは、光っているキーの少し上に小さな OmniLight を1つ（P1 のオレンジ・P2 の青。手が下から照らされる）

### 4.5 控え室の P1・P2

- 体は本番と同じ作り方（`EmoteBlockmanPreview.build_player_skeleton`。`loading_character_3d.gd` と同じく、帽子・色・トゥーンの設定を game_state から）。CPU のときは P2 の頭の上に「CPU」の名札（本番と同じ見た目）
- R2 の歩き：入口の空から机の前の空まで 2.5 秒。腕と脚を振るだけの簡単な歩きを `PracticeRoom` に書く（本編の `player_controller.gd` は変えない）
- R3〜R7 の手を置く姿勢：肩を前へ約 70°・ひじを約 40° 曲げる形を、骨を回して作る（新しいアニメは作らない）。キーが押されたら、その側の手を 0.08 秒だけ少し下げる
- 控え室の P1・P2 は、ステージの P1・P2 の動きとは連動しない（画面の中で動くのはステージの 2人）

### 4.6 控え室のハテナ

- `HatenaGuide` をもう1つ RoomView に置く（机の上の空 `Spot_Hatena` に合わせた親の下。大きさは控え室で P1・P2 の半分くらいに見えるよう親で縮める）
- 使う動き：`sit_here`（R1）・`step_to`（R2 で立って机の上を歩く）・`play(&"wave" / &"point" / &"open_arms" / &"clap")`
- ステージのハテナ（監督の `hatena`）は 3-1 のあいだ隠したまま。3-2 の始め（`show_hatena`）で今までどおり空から降りる

### 4.7 吹き出しの付け根

- 監督の `_bubble_anchor` は、控え室が開いているあいだ `PracticeRoom.bubble_anchor()` を使う
- `bubble_anchor()`：RoomCamera で控え室のハテナの頭の上を `unproject_position` し、RoomView の大きさから画面の大きさへ直す。画面の外なら `Vector2.INF`（しっぽのない吹き出しを上に出す。今の決まりと同じ）

## 5. `PracticeLaptop` と画面

### 5.1 キー

```gdscript
const P1_KEYS := {move: [W, A, S, D], jump: [Space], emote: [1, 2, 3]}
const P2_KEYS := {move: [Up, Down, Left, Right], jump: [CtrlR], emote: [8, 9, 0]}  # テンキーの 7 8 9 は 8 9 0 を光らせる
func light_group(player: int, group: StringName, level: float)  # 0 = 消す、0.35 = 薄く、1 = 明るく
func blink_group(player: int, group: StringName, seconds := 1.2)
func set_pressed(key_name: String, down: bool)                  # 沈む（6 mm）＋明るく。離すと元の明るさへ
```

- 押した本物のキーは `PracticeLaptop._process` で `Input.is_physical_key_pressed` を読んで映す（本番の入力の決まりと同じ物理キー）。右 Ctrl は `KEY_CTRL` の右（`Input.is_physical_key_pressed` で右左を分けられないときは、本番の P2 のジャンプと同じ判定を使う）
- CPU のとき：P2 のキーボードは読まない。代わりに `game_state.practice_cpu_frame_input()` の axis・jump から矢印・右 Ctrl を押し込む（R3 の「CPU の手がひとりでに矢印を押す」も、CPU にゆっくり左右へ動いてもらってこれで見せる）。P1 が矢印を押しても、矢印は沈むだけで光らない
- 光らせ方：キーのマテリアルの emission を上げる（P1 オレンジ `#F28C33`・P2 青 `#2F8FFF`。本編の P1・P2 の色に合わせる）

### 5.2 画面の中身（`PracticeLaptopScreen`、ScreenView 1280×720）

| モード | 中身 |
|---|---|
| `&"off"` | 黒 |
| `&"boot"` | 0.5 秒だけ明るい青白（ロゴは出さない） |
| `&"keys"` | 見出し `c3.keys.sign`、キーボードの図（本体と同じ並び。左半分にうすいオレンジ・右半分にうすい青の地）。光らせたキーは本体と同じ色。グループのそばに `c3.pc.labels`（移動／ジャンプ／エモート） |
| `&"stage"` | StageView の絵を画面いっぱい。左上に P1、右上に P2 の欄（`c3.pc.checks`：左右／前後／ジャンプ。できたら ✓）。CPU のときは P1 の欄だけ |

- 文字はゲームのフォント（NotoSansJP）。図はコードで描く（Control の `_draw`）。画像は使わない
- ✓ は今の看板の ✓ と同じく「ピコン」を鳴らす（`d.play_pico()`）

## 6. 3-1 のレッスン（`course_3.gd` の `KeysStep` を作り直す）

| 段 | すること |
|---|---|
| `&"room"` | `enter`：今と同じルール（コンベア停止・見えないさく）に **input_locked = true** を足す。2人をスタートの位置へ。ステージのハテナは隠す。`d.open_room()` → R1（ハテナは座って手をふる） |
| `&"walk"` | 1.5 秒後、控え室の 2人が歩く（R2）。着く 0.4 秒前にふたを開け、画面を `boot` → `keys` |
| `&"explain"` | 台本の R3〜R5（人どうし／CPU と）。キーは押せば光る（操作は止めたまま） |
| `&"play"` | R6：画面を `stage` に、カメラを Cam_R6 へ。input_locked を外す。動いた量とジャンプの数え方・✓・矢印の注意（CPU と）は今の `KeysStep` と同じ。✓ は画面の欄に付ける（`tick_sign` の代わりに `d.room.tick(player, part)`） |
| `&"zoom"` | 「NICE!」のあと、`await d.close_room(true)`（R7・R8）。下のカードを出して `complete_step()` |

- `exit`（スキップ・コースをやめる・次のレッスン）：控え室が開いていれば `d.close_room(false)` ですぐ戻す。input_locked は次のレッスンのルールで外れる
- 看板の壁（`open_sign`）は 3-1 では使わない。`sign_wall.gd` の P1・P2 のキーのパネルが 3-1 だけのものなら、実装のときに grep で確かめて使い道がなければ消す

## 7. 監督と本番側に足すもの

| 所 | 足すもの |
|---|---|
| `practice_director.gd` | `var room: PracticeRoom`、`open_room() -> Signal`、`close_room(zoom: bool) -> Signal`、`room_open() -> bool`。`_bubble_anchor` の先頭で `room_open()` なら `room.bubble_anchor()`。`_exit_tree` で控え室を消す（root の 3D を必ず戻す） |
| `game_world.gd` | `practice_set_hud_shown(on: bool, seconds: float)`：GameplayHUD の下のカード（PlayerHealthHUD など）を出す・隠す |
| `practice_texts.gd` | `c3.pc.labels`「移動／ジャンプ／エモート」・`c3.pc.checks`「左右／前後／ジャンプ」（どちらも「ノートPCの画面」） |

## 8. 確かめ方

- 単体（ヘッドレス）：`PracticeLaptop` のキーの名前の対応（P1・P2 の組、テンキーの 7 8 9 → 8 9 0、GLB がないときの仮のノートPC）、`PracticeLaptopScreen` のモードの切り替え、R7 の終わりの位置の計算（16:9 と 21:9）
- ③の通し（ウィンドウ。`tests/practice_course3_smoke_runtime.gd` の 3-1 を書き直す）：CPU と・人どうしの両方で、控え室が開く → W を押すと `Key_W` が光る → R6 で画面が `stage` → 動いて ✓ → 拡大 → root の 3D が戻る・下のカードが出る・控え室が隠れる → 3-2 の壁1。スキップの道も通す
- スクリーンショット：`artifacts/practice_course3/` に R1・R3・R4・R5・R6・R7 の途中・R8 を撮り、`contact_sheet.jpg` にまとめて絵コンテ v0.5 と見比べる
- つなぎ目：R7 の最後のフレームと R8 の最初のフレームの平均の色の差を数字で残す
- 本編が壊れていないか：練習の単体・①〜⑤の通し・HP（[handoff.md](handoff.md) 4章の表）

## 9. 作る順番

1. ライブの Blender で控え室とノートPC（`build_practice_room.py`。確認の絵を撮る → `.blend` を上書き保存 → GLB を書き出す）
2. `PracticeLaptop`・`PracticeLaptopScreen` と単体テスト
3. `PracticeRoom`（SubViewport・カメラ・照明・控え室の P1／P2・ハテナ・吹き出しの付け根・開く／閉じる）
4. `KeysStep` の作り直し・監督と本番側の道具・文字
5. ③の通しテスト・スクリーンショット・絵コンテとの見比べ
6. 台本・この設計書の「作りながら決めたこと」・[handoff.md](handoff.md)・[plan.md](plan.md) を直す

## 10. 気をつけること

| こと | 対策 |
|---|---|
| R8 で色・明るさが跳ぶ | 4.3（控え室は Linear、0.2 秒の重ね、数字で確かめる） |
| root の 3D を止める・戻すときの引っかかり | 戻すのは R7 の終わりの 1 フレーム前。引っかかるなら、止めずに本番のカメラを残したまま控え室で覆う形に変える（そのときは R6〜R7 だけ 2 回描く重さを測る） |
| StageView が初めて描くときのシェーダーの読み込みで止まる | R3〜R5 のあいだに 1 回だけ描いておく（`UPDATE_ONCE`。`death_wipe.gd` の begin_render_prewarm と同じ考え） |
| 共有した World3D を外すと落ちる | 外さない。閉じたら更新を止めて隠すだけ |
| 吹き出しが控え室のハテナに付かない | 4.7。控え室が開いているあいだは監督の付け根を控え室へ |
| ほかのセッションの Godot が動いていると通しテストの間合いがずれる | 今までどおり、止まってから流し直す |
