# チュートリアル

## 2026-10-20 全面リニューアル（V7）

不満点（長さ・文章の多さ・見た目・ゲームらしさ）への対応。設計案と決定事項（Q1 B、Q2 B、Q3 A、Q4 B、Q5 A）は設計案のページにまとめた。ステップID・3Dキーキャップ・床のガイド・本編と同じ判定はV6のまま。

### コース

- 1P・2Pの2コースのまま。ステップは章にまとめた（1P: 操作・キケン・クイズ・ボス、2P: さらにゴール）。ステップ数は1P 8・2P 11のまま（ジャンプとエモートは別ステップのまま）。
- 誘導なしの本番の2択を2問から1問にし、壁を5枚から4枚にした（`BOSS_QUIZ_INDEX` は3）。
- 同じ章の中では中立入力待ちを挟まず、世界を止めずに次のステップへ移る（`_enter_current_step(continues_chapter)`）。タスクがそろってから次へ移るまでの間は0.55秒から0.3秒にした。
- 章・ルール表示・バナーの共通部分は `scripts/core/tutorial/tutorial_flow_base.gd`（`TutorialFlowBase`）に置き、1P・2Pのフローが継承する。

### 文章

- 説明の段落（`body`）をなくし、各ステップは12字以内の `mission` だけを持つ。順番のあるのこぎり体験は `mission_by_task` で「少し下がってみよう」→「前進で逃げよう」に切り替える。
- ルールは体験した直後に `toast`（見出し10字以内・補足16字以内）で出す。きっかけは `enter`（演出の後）か `done`（タスクがそろった瞬間）。同じ表示は1コースで1回だけ。例: 海に落ちた直後「海は即アウト／ハートが残っていても脱落」、ハート体験「ハート −1／0になると脱落」、のこぎり「遅れると即アウト」、先着「早い者勝ち／先に正解した人に1点」、ボス壁「BOSS 4択／10問チャレンジの最終問題」。
- ミスのヒントは game_state.gd 側の文を短くし（例「光るドアは左」「今回はわざと「5」へ」「ハート−1　正解は右」）、ミッションの行を最大3.2秒だけ置き換える。成功の知らせ（「P1が1点！」など）は緑で出す。
- 2PでP2が左Ctrlを押したときだけ「P2は右のCtrlを使おう」と出す（`QuizGameState.hint_tutorial_left_ctrl()`）。

### 画面

- コーチバーを細いミッションバーに作り直した（`scripts/ui/tutorial_coach_bar.gd`）。章アイコン・章名・ミッション・キー（3Dキーと同じ色の決まり。移動は W A S D／↑ ← ↓ → の順）。クイズ中はアイコンとミッションだけの小さなピル。バーの外側に章ごとの進行の線を引き、「STEP 3 / 10」の文字は出さない。2Pは操作中は画面上、クイズ中は下。
- ルール表示は画面上部（2Pでバーが上のときはその下）。クイズ中は壁の問題文を隠さないよう左上に出す。章を終えると「◯◯ CLEAR」のバナー（約1秒、`door_correct` を高めの音程で）。キーを達成すると `ui_click`。
- アイコンは画像を持たず `scripts/ui/tutorial_glyph.gd` で描く。キーキャップは `scripts/ui/tutorial_key_chip.gd`、色と文字は `scripts/ui/tutorial_ui_style.gd`。
- クリア画面（`scripts/ui/tutorial_completion_card.gd`）は「TUTORIAL CLEAR」とクリアタイム・残りハート（2Pはスコアタワーの結果1行）。成績の評価（メダル）は付けない。1秒見せた後は Enter で次へ進める（`game_world.gd` の `TUTORIAL_CLEAR_MIN_SECONDS`）。
- 開始前の全画面キーボード説明（`tutorial_keyboard_intro.gd`）を廃止し、コース選択と1画面にまとめた（`scripts/ui/tutorial_course_selector.gd`）。左でコースを選ぶと右のキーボードと説明が切り替わる。説明のキーは実際の配列どおり（W の下に A S D、横長の Space、1 2 3 の横並び、矢印の逆T字）。エモートの説明は「相手を煽ろう!!」。
- カスタマイズ紹介は画像3枚・戻る／次へ の形式のまま、画像を大きくし該当箇所を枠で囲み、説明を見出しと1行にした。ボタンはメニュー側の一括スタイルに上書きされないよう `tutorial_own_style` の印を持つ。
- カスタマイズ紹介の後の大きな完了カードはやめ、メニュー上端の小さな通知（「チュートリアル完了」）にした。
- `GameManager.CURRENT_TUTORIAL_VERSION` を7へ。

### 検証

- `tests/tutorial_flow_accessibility_unit.gd`（527項目。章・ミッションの長さ・ルール表示・同じ章の中で止めないこと・バナーを含む）。
- `tests/tutorial_rules_bootstrap.gd`（83項目。本番1問・ボス壁でのハート0・ルール表示の順番・左右のヒント）。
- `tests/tutorial_course_selector_unit.gd`（29項目。キー配列どおりの並び・練習キーで開始しない・960×540）。画面は `-- --capture` で `artifacts/tutorial_v7/course_select/`。
- `tests/tutorial_renewal_bootstrap.gd`（実キーだけで通しプレイ。1P 66項目・2P 86項目）。画面は `artifacts/tutorial_v7/solo|duo/`。ボットの操作でカウントダウン明けからカスタマイズ紹介へ移るまで、ゲーム内時間で1P 45.5秒・2P 88.5秒（人が文字を読んで迷う時間は含まない）。
- `tests/tutorial_revision_bootstrap.gd`（25項目。メニューの開始画面・カスタマイズ紹介・完了通知、設定ファイルを書き換えないこと）。画面は `artifacts/tutorial_v7/menu/`。
- 既存: キーボード47、HP 197、押し合い286、結果演出5000、左右移動の各テストが成功。

```powershell
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tutorial_flow_accessibility_unit.gd
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tutorial_rules_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_course_selector_unit.gd -- --capture
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_renewal_bootstrap.gd --fixed-fps 60 -- course=solo
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_renewal_bootstrap.gd --fixed-fps 60 -- course=duo
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_revision_bootstrap.gd --fixed-fps 60
```

---

## 2026-10-12 移動の統合・ジャンプの独立・エモート3つ・2Pの勝敗判定（V6）

V5のコースを次のように変えた。ステップ数は1P 10・2P 13のまま（2ステップを2ステップに置き換え）。

### 操作のステップ（1P・2P共通）

- 「左右の移動」と「ジャンプと前後の移動」の前後部分を、前後左右の4方向を練習する1つのステップにまとめた（1P `move_lane`、2P `duo_move`。P1 A/D/W/S、P2 ←/→/↑/↓、1Pは矢印キーでも可）。
- ジャンプは独立したステップにした（1P `jump_lesson`：Space、2P `duo_jump`：P1 Space・P2 右Ctrl。左Ctrlは使えないことを本文で説明）。ガイドは `GUIDE_JUMP`（足元のリングのみ、進む方向のシェブロンは出さない）。
- エモートはどれか1つではなく、3つのキーをすべて押したら完了（タスク `emote_1`〜`emote_3`、P1 1/2/3、P2 8/9/0 とテンキー7/8/9）。
  - 判定はエモートIDではなく押されたキーで行う。`GameWorld._emote_key_mask()` が押下キーのビット（bit0〜2）を作り、`QuizGameState.set_tutorial_emote_keys()` を経て `update_input_practice()` の最後の2引数に渡す。IDだとスロットの重複や空き（0）を区別できず、空きスロットで完了できなくなるため。
  - 本編へ渡すエモートIDは `_emote_for_keys()` で従来どおり（1 → 2 → 3 の優先）に導出する。

### 2Pのゴール → スコアタワー → 得点の説明 → 勝敗発表

ゴールで即終了せず、本編のローカル2Pと同じスコアタワー（勝敗判定）まで進む。

1. `duo_goal`: 生き残った全員がゴールすると、本編と同じ `_update_local_result_goal` が得点を記録する（`正解数 ×（残りハート＋0.5）`、ゴール前に脱落した人はゴーストとして表彰台へ向かい、正解数だけ）。2人ともゴール前に倒れたときは従来どおりレースをやり直す。
2. スコアタワーの演出（ASSEMBLE → WALK → SCORE_ROLL）。`uses_local_result_ceremony()` は2Pチュートリアルでも true（`uses_tutorial_result_ceremony()`）。サドンデスとF9の引き分けデバッグはチュートリアルでは使わず、引き分けはそのまま引き分けを見せる。
3. 得点が出そろった瞬間（6.3秒、VERDICT の入り口、勝敗はまだ伏せた状態）で時計を止め、結果画面の中央上に「得点の計算」パネルを出す（`ResultFinaleHud._update_tutorial_note`）。式、脱落者の扱い、2人の実際の計算（`get_result_formula_text()`、例「P1: 3 × 2.5 = 7.5」）を表示し、下部の得点カードとは重ならない。
4. 1秒以上表示した後、Enter・Space・右Ctrlのどれかで勝敗発表へ進む（`GameWorld._input` → `resume_tutorial_score_pause()`。1秒未満の押下は飲み込む）。
5. VERDICT → EFFECT → WINNER の後、結果ボタン（INTERACTIVE）は出さずに `duo_complete` へ。完了カードは表彰台の画のまま重ね（状態は RESULT_CEREMONY のまま、演出カメラも動かさない）、カードの計算例は確定した結果と勝敗から作る。その後は従来どおりカスタマイズ紹介へ。

進行は `QuizGameState.TutorialCeremonyStage`（NONE → ROLLING → SCORE_PAUSE → VERDICT → DONE）が持つ。演出を使えないとき（`result_ceremony_enabled = false`）は従来の `_update_tutorial_goal` で完了ステップへ進む。スコアタワー中はコーチバーと2Pのチュートリアルガイドを隠す。1問ごとの勝者（スコアボードの10列）はチュートリアルでは記録しない。

### そのほか

- `GameManager.CURRENT_TUTORIAL_VERSION` を6へ（完了済みの人にも「★ 内容を更新しました」と起動時のコース選択を一度出す）。
- コース選択の説明を更新し、2Pの所要時間を約6分にした。

### 検証

- `tests/tutorial_flow_accessibility_unit.gd`（369項目）、`tests/tutorial_rules_bootstrap.gd`（68項目。得点説明での停止・最短表示時間・再開・勝敗後の完了ステップ、引き分け、ゴーストの完走、演出なしの従来経路）。
- `tools/test_lateral_movement.gd`、`tests/local_push_unit.gd`（286項目）、`tests/result_ceremony_bootstrap.gd`（本編スコアタワー5000項目）。
- `tests/tutorial_renewal_bootstrap.gd`（実キーのみで通しプレイ）。画面は `artifacts/tutorial_v6/`。

---

## 2026-10-04 現行版に合わせた刷新（V5）と3D操作キー

ゲーム中のチュートリアルを、いまの本編（3ハート、2択／4択の壁、ローカル2Pの回転のこぎり・先着の得点・スコアタワー）に合わせて作り直した。操作を練習するステップでは、使うキーを3D空間（キャラクターの頭上など）に実物のキーキャップとして表示する。開始前の全画面キーボード説明（静止画面）と、画像によるカスタマイズ紹介の形式は以前のまま。サドンデスは本編で無効（`sudden_death_available = false`）のため扱わない。

### コース

1P（10ステップ、約3分）: 左右の移動 → ジャンプと前後の移動 → エモート（新） → コース外は海 → クイズの答え方（誘導あり） → ハート（HP）のしくみ（新、わざと不正解へ） → 誘導なしで回答（本番と同じハート判定） → 4択のボス壁（新） → 完了 → カスタマイズ紹介。

2P（13ステップ、約5分）: 基本操作 → ジャンプと前後 → エモート → 海 → ゴーストシャーク → 回転のこぎり（新） → クイズの答え方 → ハートのしくみ（新） → 誘導なしで回答 → 4択のボス壁（新） → ゴールとスコアタワー → 完了 → カスタマイズ紹介。

本編と食い違っていた説明を直した。

- 不正解は即脱落ではなくハート−1（0で脱落）。海とのこぎりはハートに関係なく脱落。
- 2Pは先に正解した人だけに1点、壁は2人とも通れる。不正解の人は相手が答えるまで壁の前で止まる。2人とも不正解ならハートが1つずつ減って次へ。
- 2Pの置き去り脱落の説明を、回転のこぎり（先頭から約14m遅れると巻き込まれる）に置き換えた。のこぎり体験では後退して赤い警告を確かめ、前進で離れる。体験以降のクイズでも本編と同じ刃が後ろを走る（ゴール前に止まる）。
- 2Pのゴールは先着で終わらず、生き残った全員のゴールで終わる。完了カードに「正解数 ×（残りハート＋0.5）」の式と、そのコースでの2人の計算例を出す。
- ゴーストシャークは、どちらのプレイヤーもなり得ること、黄色のPERFECTで離すと最大パワー、相手を海やのこぎりへ弾けることを説明する。
- 1Pのコース選択カードの「ゴール」表記を削除（1Pの本編はゴールなしで終わる）。

途中で脱落した人は、本編どおりゴーストシャークのままボス壁へ進む。ゴールの前だけ、体験のためにハート1つで復帰させる（スコアタワーの計算例が実際より有利に見えないようにする）。2人とも倒れたとき・1Pでハートが尽きたときは、演出を見せた後にハートを戻して同じ問題からやり直す。

### 3D操作キー

- `scripts/world/tutorial_keycap_3d.gd`: キー1個。台形に絞った角丸キャップ・皿状の天面・台座を手続き生成（幅ごとにメッシュをキャッシュ）し、刻印は Label3D。色は開始前のキーボード説明と同じ（通常はアイボリー、押すキーはP1オレンジ／P2水色、達成は緑＋チェック）。実際の入力でだけ沈み、白っぽく光る。チュートリアルが勝手に押す演出は持たない。
- `scripts/world/tutorial_key_guides_3d.gd`: 並べ方。各タスクの `slots` とステップの `key_layout` から決める。
  - `cluster`: 頭上に実配列のキーボード片（P1 = W / A S D + Space + 1 2 3、P2 = ↑ / ← ↓ → + 右Ctrl（← の左隣）+ 8 9 0）。移動キーは4個そろえて並びを見せ、押すキーだけを光らせる。
  - `sides`: クイズ・海のステップでは、肩の左右に左右移動のキー。誘導中の正解ドア・ハート体験の不正解ドアの方向のキーだけを光らせる。
  - `ghost`: ゴーストシャークの上に照準の矢印と突進キー。
  - 順番があるステップ（踏ん張り→押す、後退→前進）は、今やる分だけを光らせる（`ordered_tasks`）。
  - 1Pで矢印キーを使うと刻印が ← ↑ ↓ → に切り替わる。
  - 2人のキーボード片が重なるときは左右へ押し広げ、画面外へはみ出す分は内側へ寄せる。演出中・死亡演出中は隠す。
- 2Dのコーチバーのキーチップは従来どおり。クイズ中はバーを畳み（進行ドットを隠して本文2行）、2Pでハートのカードが下隅に出ている間はカードの間に収める。
- キーキャップはBlender資産ではなくスクリプトで生成している（`.blend` の作成・変更なし）。単体の見た目は `tests/tutorial_keycap_preview.gd` で確認できる。

### そのほか

- `GameManager.CURRENT_TUTORIAL_VERSION` を5へ。コースごとに完了した版を保存し、前の版だけを完了したコースはコース選択で「★ 内容を更新しました」と表示する。起動時のコース選択も一度だけ再表示される。
- コース選択の説明・所要時間、ステージ完了カード、読み込み画面の説明文を更新。
- カスタマイズ紹介の3枚の画像を現在の画面から撮り直した（`tests/customize_tour_capture_bootstrap.gd`）。紹介文にプロペラ帽の効果と、1番のエモートが2人対戦の勝利ダンスになることを追記。
- 既知（本編側、未変更）: 4択の壁はドアが画面左から D・C・B・A の順に並ぶ（`door4_xs` が −X から並ぶため。2択は左が先頭）。

### 検証

- `tests/tutorial_flow_accessibility_unit.gd`（コース・キー情報・入力・ハート・のこぎりの契約、367項目）と `tests/tutorial_rules_bootstrap.gd`（QuizGameState での実際の判定、32項目）: 成功。
- `tests/tutorial_renewal_bootstrap.gd`: 実ゲームを実キー入力だけで最初から最後まで遊ぶ。1P 39項目・2P 54項目成功。各ステップの画面と3Dキーの状態を `artifacts/tutorial_v5/` に保存。
- 既存: HP 197、のこぎり 890、押し合い 290、左右移動 29、キーボード説明 47・31項目が成功。

```powershell
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tutorial_flow_accessibility_unit.gd
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/tutorial_rules_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_renewal_bootstrap.gd --fixed-fps 60 -- course=solo
./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/tutorial_renewal_bootstrap.gd --fixed-fps 60 -- course=duo
```

---

## 2026-09-21 開始前のキーボード説明と旧カスタマイズ紹介（以前の経緯）

2026-09-21の再調整。ゲーム中のチュートリアルは全面刷新前へ戻した。

### 復元した部分

Solo / Duoの進行、ゲーム中の説明バー、コース選択、ゴーストシャークの操作紹介、完了カード、HUDは制作開始前のHEADへ復元。ゲームの入力・衝突・海からの復帰・押し合いは変更していない。旧フロー139項目、前後移動回帰、押し合い290項目を検証した。

### 開始前の説明

コース選択 → 全画面キーボード説明 → 以前のチュートリアル、の順。ソロはP1の全操作、2人用はP1とP2の全操作を1画面に同時表示する。実配置と実入力ハイライトを使用する。指・枠・キー押下の説明アニメーション（再生／停止ボタンを含む）と、小さな人形デモは廃止した。

左右移動・前後移動・ジャンプ・数字キーの説明は常時表示する静止画面で、自動で動く表示はない。ページ送りは不要。実キーを押して場所を確認でき、Spaceや矢印によって誤って開始しない。Escはコース選択へ戻る。「練習をはじめる」でのみ開始する。

- `scripts/ui/tutorial_keyboard_intro.gd`: 開始前説明。
- `scripts/ui/tutorial_keyboard.gd`: キー配置と入力表示。`show_demo = false` で説明アニメーションを出さない（開始前説明で使用）。
- `scripts/ui/main_menu.gd`: 開始と取消の接続。通常ゲームの開始経路は保持。

### カスタマイズ紹介の復元（2026-09-22）

ユーザーの追加指示により、カスタマイズ紹介も全面刷新前へ復元。壁速度・スキン・エモートの3枚の既存画像、説明文、キー表示、戻る／次へ／紹介を終えるボタンを使用する。実操作の達成チェックとライブ表示は撤去。

`customize_settings.gd` は制作開始前のバックアップとSHA-256が一致。以前から存在したスキンプレビューの姿勢修正は保持した。完了メッセージと紹介ボタンの既存スタイルも復元した。

全画面の1枚キーボード、以前のゲーム中チュートリアル、人形デモの廃止はそのまま維持。

- `scripts/ui/customize_settings.gd`: 以前の画像による紹介。
- `tests/tutorial_revision_runtime.gd`: 復元した紹介の表示・ページ送り・完了・中断とキーボード保持の実行確認。
- `tests/tutorial_keyboard_intro_unit.gd`: 説明と入力の独立性。
- `tests/tutorial_flow_accessibility_unit.gd`: 復元した旧フローの契約。

キーボード導入は変更前の30項目、旧ゲーム進行は139項目の検証結果を維持。今回の復元は実ゲームで24項目すべて成功し、3ページの画像を目視確認。実行結果・画像は `artifacts/customize_rollback/` に保存した。

キーボード画像は `artifacts/tutorial_keyboard_intro/`。今回以前の別機能の未コミット編集は保持し、コミットは作成していない。`artifacts/tutorial_rework/` のライブ表示の検証結果は撤去前の履歴として残す。既存のFennara autoload欠落、headless描画警告は今回の検証結果と区別する。

### 文言の調整（2026-09-22）

開始前のキーボード、コース選択、1P・2P各ステップ、再挑戦時のヒント、ゴーストシャークの操作説明、完了表示、カスタマイズ紹介を一般的な操作説明の文体に統一。「あそぶ準備」「できた！」などを「操作方法」「操作完了」に変更し、表記を「前進・後退」「エモート再生」などに揃えた。

この調整は表示文言のみ。変更直前のソースと比較し、文字列以外の一致を確認した。既存のキーボード45項目・導入30項目・進行139項目を確認。実行中のエンジンで全18ステップの説明バーと開始画面・カスタマイズ紹介を描画し、キーボードは1280×720／960×540で確認した。結果は `artifacts/tutorial_wording/` に保存。
