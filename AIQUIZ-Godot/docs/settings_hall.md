# 設定画面「地下神殿の講義室」

> **2026-10-05: 使っていない。** メインメニューの「設定 / API状態」は、以前のメニュー内パネル（`ui/main_menu.tscn` の `SettingsPanel`、`scripts/ui/main_menu.gd` の `# --- Settings ---`）に戻した。
> サドンデスの行は `QuizGameState.sudden_death_available` の時だけ出す。このシーンと講義室・実習場のスクリプトや資産はそのまま残してあり、単体（`ui/settings_hall.tscn` を直接実行、`tests/lecture_director_capture.gd`）では今も動く。
> 戻すときは `main_menu.gd` の `_on_settings_btn_pressed()` を `_go_to_settings_hall()`（コミット `5e03ce7` の版）に、`menu_wall_background_preview.gd` に `begin_settings_dive()` を戻す。以下は使っていた時の説明。

メインメニューの「設定 / API状態」は、メニュー内のパネルではなく専用シーン `ui/settings_hall.tscn` へ移動する。
Godot 4.7 リリースページのヒーロー（右に斜め俯瞰の 3D セット、左に見出しと操作）の構図で、
サドンデス用に作った地下神殿（首都圏外郭放水路の調圧水槽、`docs/surge_tank_reproduction.md`）の中に
「連結チップソー概論」の講義コーナーを置き、左に設定 UI を重ねる。

## 流れ

| 段階 | 内容 |
| --- | --- |
| メニュー | `_go_to_settings_hall()`: メニューの要素が左へ退場し、ライブ背景のカメラが地面へ急降下（`MenuWallBackgroundPreview.begin_settings_dive()`、0.6 秒）。黒フェードの下で `change_scene_to_file` |
| SHAFT | 立坑（`ShaftDescent`）を降りる。模様を上へ流し、深度板「−20m…」が過ぎ、モーター音とランプの通過音（`SuddenDeathAudio`）。この間に地下神殿・審判と生徒のぬいぐるみ・チップソーの台車を別スレッドで読み込み、神殿は部分シーンを 1 フレームに 1 つずつ足す。最低 1.8 秒、資産がそろうまで（上限 6 秒） |
| BLACKOUT | 0.2 秒以上かつ 2 フレーム描くまで黒。ホールの初描画のパイプラインのコンパイルを隠す |
| ARRIVAL | 2 秒。天井近くから最終の構図へカメラが降り、照明の行がセットに近い順に点く（接触器の音と短いちらつき）。1.5 秒でセットのスポットが一気に点く |
| SETTLED | 左の設定 UI がスライドで入り、API 状態のチェックが始まる |
| 実習場を見る | 見出し「設定」の右のボタン。カメラが講義セットの上を弧を描いて越え（1.6 秒）、実習場の構図へ。もう一度押す（「◀ 講義室へ」）と戻る。副題も「実習場 ― 操作実習中」に変わる |
| 戻る | 「メニューへ戻る」か Esc。UI が左へ消え、照明が落ちながらカメラが 3 m 上がり、黒フェード → メニュー |

降下中は任意のキー・クリックで飛ばせる。時計は実時間（`SettingsHallDescent`）なので、読み込みで止まった分は先へ飛ぶ。

## 構成

| ファイル | 役割 |
| --- | --- |
| `scripts/ui/settings_hall.gd` | 進行役。カメラ、読み込み、フェーズの受け渡し、音、画質変更、帰還 |
| `scripts/world/settings_hall/settings_hall_descent.gd` | フェーズの実時間時計と深度板 |
| `scripts/world/settings_hall/lecture_set.gd` | 講義セット: Blender 製の小道具 GLB と 5 体のゴドーくん GLB を置き、各自のループを位相をずらして再生。スポットライト・状態ランプ・黒板の文字（API 連動）はここで作る |
| `assets/settings_hall/*.glb` | `lecture_set_props.glb`（小道具一式）、`godotkun_lecturer / student_notes / student_hand / student_doze / trainee.glb`（各 1 体＝ぬいぐるみ＋小道具のメッシュ、ループ 1 本: Teach 12 秒 / TakeNotes 8 秒 / RaiseHand 10 秒 / Doze 9 秒 / Practice 5 秒）。読み込み時にぬいぐるみのテクスチャが `godotkun_*_GK_PlushAlbedo.png` として隣に取り出される |
| `assets/settings_hall/source/blender/` | ビルダー `build_lecture_set.py`（`lsb_common` / `lsb_godotkun` / `lsb_props` / `lsb_anim`）、`SCENE_PASSPORT.md`、書き出した編集用 `lecture_set.blend`。ユーザーのライブ Blender（Higgsfield 連携の `bl_execute`）で `runpy.run_path(...)` して GLB を書き出す。確認レンダーは `source/previews/` |
| `scripts/world/settings_hall/practice_yard.gd` | 実習場（下の節）。本編の台車・操作盤・レールを実寸で置き、操作実習のループを時計から計算して回す |
| `scripts/ui/settings_hall_panel.gd` | 左カラムの UI。3D 無しで単体に作れる（テストが使う）。「実習場を見る」は `view_toggled(practice)` で進行役へ。効果音の試し鳴らしは `sfx_tested` |
| `scripts/world/settings_hall/lecture_director.gd` | 講義室の授業の進行役（下の節）。小道具と人物の GLB がそろうと `LectureSet` が作る |
| `scripts/world/settings_hall/plush_actor.gd` | ゴドーくん 1 体: クリップのつなぎ、歩き・横歩き、両手の IK（TwoBoneIK3D + LookAtModifier3D）、体ごと向く、まばたき（目のテクスチャの差し替え）、揺れもの、伸縮式の指し棒、足音 |
| `scripts/world/settings_hall/chalk_canvas.gd` / `glyph_book.gd` | 黒板の絵（チョーク・消し・濡れ拭き・前回の板書）と、字の線データ `assets/settings_hall/glyph_strokes.json`（`tools/settings_hall/glyph_strokes.py`） |
| `scripts/world/settings_hall/lesson_builder.gd` / `lessons/lesson_03.json` | 講義の時間割（開くたびに次の講義）と台本。教科の授業は `offline_bank.json` から出題 |
| `scripts/world/settings_hall/yard_director.gd` | 実習場の人物（教官・次の操縦者・見学 2 人）と周ごとの出来事 |
| `assets/audio/sfx/lecture/*.wav` | 講義室の効果音（`tools/settings_hall/lecture_sounds.py` で合成） |

設定項目は旧パネルからそのまま引き継ぐ: API 状態（インターネット / AI Gateway / Firebase / オフライン問題数）と再チェック、
BGM・効果音（効果音はスライダーを離すと試し音）、解像度、画質、サドンデス（`QuizGameState.sudden_death_available` の時だけ）、
ダッシュボード、戻る。API は `ApiStatusAutoload` の状態フラグとメッセージだけを見せ、`get_env()` の中身は出さない。
`check_completed` は固定 3 秒で鳴るので、状態が決まるまで 0.25 秒ごとに見に行く（上限 10 秒）。

黒板の下 4 行と教壇横のランプは API の状態に連動する（緑 = 接続OK、黄の明滅 = チェック中、赤 = 失敗。
「自習プリント」はオフライン問題数）。

## 授業（進行役）

先生は本当に黒板に書いて消す。台本の段（write / circle / erase / ask / gag / event …）を上から流し、先生は黒板の前を
歩いて半身に構え、右手の IK で字の線（Noto Sans JP の細線化、記号は手書きの書き順）をなぞり、`ChalkCanvas` に線が
積もる。チョークはチョーク受けの実物を取って持ち替え（本数も変わる）、黒板消しで縦のジグザグに拭き（消し跡が残る、
粉がトレイに積もる）、濡れ雑巾で拭くと暗く光って乾く。高いところは背伸び・ジャンプ・踏み台・指し棒にテープ・肩車、
上下スライド黒板も動く。生徒は合図（cue）で写す・見る・手を挙げる・居眠りし、漫符（！？怒り・汗・…・♪・電球）が出る。

- 開くたびに講義が進む（`user://lecture_visits.json`）: 連結チップソー → 算数 → 理科 → 国語（縦書き）→ 社会 → 英語 → 小テスト →
  連結チップソー → 期末テスト → 卒業式。前回の下の黒板は `user://lecture_board_F.png` から薄く残る。
- 時間帯（`_pick_day_mode`）: 平日 12 時台は給食、16〜20 時台は放課後の掃除、21〜5 時台は夜（先生がひとり電気スタンドで採点）、
  土日は居眠りの生徒だけの補習。どの場面のあとも授業が始まる。照明が点く前に読み込めたときは「遊ぶ → 固まる → 席へ」から。
- 設定画面との連動: 効果音の試し鳴らしで振り向く、BGM の音量で居眠りが深く・浅くなる、画質の変更で先生の眼鏡が光る、
  戻ると全員が手を振る（0.9 秒）、人物をクリックすると反応する、5 分で採点・10 分で先生も居眠り。
- 確認: `tests/lecture_director_capture.gd`（`jump=周:段`、`cam=`、`mode=`、`visit=`、`date=MM-DD`、`view=practice yard_cycle=N`、
  `calls=秒:メソッド`、`trace=1`、`canvas=1`）。環境変数 `AIQUIZ_LECTURE_MODE` / `AIQUIZ_LECTURE_VISIT` / `AIQUIZ_LECTURE_DATE` で決め打ち。

## 画面

- カメラの最終位置は `settings_hall.gd` の `FINAL_EYE` / `FINAL_AIM` / `FINAL_FOV`。狙いをセットの中心より +X へずらして、セットが画面の右 55〜60% に乗り、左 1/3 に柱列が霧の中へ続くようにしている。
- セットの配置は Blender のビルダー（`build_lecture_set.py` の CAST / `lsb_props.py`）と `lecture_set.gd` の CAST で同じ値を持つ。人物の GLB は足元原点・正面 +Z で書き出し、位置と向きは Godot 側が足す。
- ゴドーくんは結果演出の審判・操縦席と同じ Godot のロゴ形のぬいぐるみ（`assets/result_finale/referee_finale.glb` の本体と 16 本の DEF ボーンをビルダーが読み込む）。頭と胴は一体のメッシュなので曲げず、足した `Body` / `Root` ボーンで体ごと傾け・跳ばせ、腕と脚だけを曲げる。小道具は別メッシュ（同じリグでスキン。ぬいぐるみに結合すると読み込んだカスタム法線のせいで Godot で黒く写る）。講師は丸眼鏡・赤い蝶ネクタイ・指し棒、ノートの生徒は鉛筆、挙手の生徒は緑の帽子、居眠りの生徒は Zzz、練習生は黄色いヘルメットで実習レールの刃を跳び越える。
- ぬいぐるみの脚は短いので、座った生徒は胴の底を座面（0.45 m）に乗せて足が床から浮く。胴の正面が机に当たらないよう、椅子は z 0.74（机の手前の縁は z 1.3）。腕は体の正面より前へ届かないので、手は机の手前の縁に置く。
- Blender 5.1 の注意: ノード名は UI の言語でローカライズされるので型で探す（`mat()`）。アクションはスロット付きで、GLB は NLA トラック方式で書き出す（ACTIONS だと他キャラのアクションまで混ざる）。
- 照明の行の目標の明るさは `ROW_TARGETS`（セットからの距離で 0.60 / 0.45 / 0.18 / 0.08）。奥と左は暗いまま、UI の文字の背後に明かりを置かない。

## 実習場（連結チップソーの操作実習）

講義セットの右奥、柱のない区画（`TANK_SCALE` 2.0 でホールの x −26〜−2、z 7〜49）に、本編と同じ連結チップソーの台車
（`assets/hazards/linked_saw_carriage.glb`、全長 24.5 m）を実寸で縦に置き、走行レール（`ConveyorRails`）を 9 m だけ敷く。
台車の +X の端（ホールの奥）に本編の操作盤 v3 と操縦するゴドーくん（`SawOperatorPresentation`）が付き、手前を向いて座る。
新しい 3D モデルはなく、台車の見た目は本編の `SawChaseController`（状態を持たない見た目の部品）をそのまま使う。

- 置き方: `settings_hall.gd` の `YARD_ORIGIN`（−14, 床, 28）と `YARD_YAW`（−90°）。台車のローカル +X（操縦席の端）がホールの +Z、前進（ローカル +Z）がホールの −X。
- 読み込み: 台車・座席・操作盤の GLB を他と同じく別スレッドで読み、`PracticeYard.hold_asset()` で持っておく（キャッシュは参照が切れると消えるので）。そろったら `build()`。中の同期 `load()` はその資産に当たる。
- 明かり: 実習場用のスポット 3 つ（操縦席のキー、刃の列の上、奥）。講義セットと同じ時に点き、戻るときに落ちる。
- 音: 刃のモーター（`dock_spindle.wav`、回転数で音程）、走行と昇降の油圧（`dock_servo.wav`）、本編の操作盤のキー・START・クラクション。

1 周 50 秒の段取り（`PracticeYard.program(t)`、時計だけから決まる。姿勢は本編と同じ `SawOperatorPresentation.sample()`）:

| 秒 | 内容 |
| --- | --- |
| 0〜6、38.6〜50 | 待機。本編の待機しぐさ（見回し・手遊び・伸び・うたた寝・足ぶらぶら・手振り）が順に出る。停止後は 0.9 秒でもたれた体を戻す |
| 6〜8.3 | 始動: 左手でキーON（計器と表示灯の自己診断）→ 右手で保護カバーを開け、振りかぶって START → ガッツポーズ → 両手をスティックへ。刃が 4 秒かけて回り出す |
| 10.2〜12.6 | 発車の合図: クラクション 2 回とガッツポーズ（本編の捕獲のしぐさ） |
| 13〜19 | 前進 4.8 m（走行スティックを倒す。速度の LED バーと Fwd 灯、台車の回転灯） |
| 19.8〜23 / 25.4〜28.6 | 刃を上げる / 下げる（0.75 m、列の端から 0.11 秒ずつ遅れて波のように。昇降スティック、UP/DN 灯、伸びる支柱） |
| 29.6〜35.6 | 後退で元の位置へ（Rev 灯と WARN の点滅） |
| 36.4〜38.6 | 停止手順: スティックを戻す → キーOFF → 保護カバーを閉める → 背もたれでひと息。刃は 2.4 秒で止まる |

- 見学の構図: `PRACTICE_EYE` / `PRACTICE_AIM` / `PRACTICE_FOV`。刃の列の手前の脇の高い所から、列が奥の操縦席へ続くのを見下ろし、操縦者はほぼ正面で画面の右 6 割。台車は横へ ±2.4 m 走るので、カメラは `PRACTICE_FOLLOW`（0.85）の割合でついていく。
- 講義室の構図でも、黒板の右上の奥に操縦席と刃の列が小さく見える。

## 検証

- 設定シーン単体: エディターで `ui/settings_hall.tscn` を実行する（直接起動でも動く）。
- メニューから: 設定 → 立坑 → 到着 → Esc → メニュー。往復しても音のバスが増えず、環境音が残らないこと。
- 自動テスト: `Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/sudden_death_settings_reel_bootstrap.gd`
- 撮影: `Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/settings_hall_capture_bootstrap.gd -- view=practice times=3,8.2,11.2,16,23.5,33,37.4 tag=practice`
  （`view=practice` はパネルのボタンと同じ道筋で切り替え、`times` は実習の時計をショットごとにその秒へ合わせる。`artifacts/settings_hall/capture/`）
  （`SettingsHallPanel` を単体で立てて画質とサドンデスの行を確かめる。`artifacts/sudden_death/settings_reel/`）。
