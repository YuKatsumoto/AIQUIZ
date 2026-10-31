# 新しいチュートリアル 引き継ぎ（2026-10-26。段階9の実装まで）

> **2026-10-30 追記：チュートリアルは旧版に戻した**（ユーザーの指示「やっぱりチュートリアルを前のバージョンに戻してください。カスタマイズの紹介だけいまのでお願いします」）。
> - メニューの「チュートリアル」は旧版（コミット 4d0f69b の 1P／ローカル2P 実践コース。`scripts/core/tutorial/`・`scripts/ui/tutorial_*.gd`）に戻した。
> - 新版から使っているのは、実践コースのあとのカスタマイズ紹介として出すコース⑤（`PracticeCustomizeGuide`。`scripts/ui/main_menu.gd` の `_begin_pending_customize_tutorial`）だけ。
> - ほかの新版のコード（①〜④、`scripts/practice/` など）は消さずに残してあるが、メニューからは開かない。`tests/practice_*` の通しテストは『PracticeBtn』がないので、いまは通らない。
> - 戻す直前の作業ツリーの全体は git の参照 `refs/backup/before-old-tutorial-restore-20261030` に保存してある（`git show refs/backup/before-old-tutorial-restore-20261030:AIQUIZ-Godot/<path>` で読める）。

新しいセッションで続きを始めるための引き継ぎ。最初にこの文書と [plan.md](plan.md) を読む。
細かい決まりと経緯は、各段階の設計書（[foundation_design.md](foundation_design.md)・[phase4_design.md](phase4_design.md)〜[phase9_design.md](phase9_design.md)）の最後の「作りながら決めたこと」にある。

## 1. ユーザーとの約束（必ず守る）

- **返事は日本語**（`~/.claude/CLAUDE.md` と `AGENTS.md`）
- **旧チュートリアルは絶対に参照しない**。撤去済み。git の履歴から掘り出さない。完全新規で作る
- **台詞と内容は大人向け**（2026-10-25 の指示「セリフと内容が幼稚すぎるので、もっと大人向けに」）
  - 文字は漢字かな交じりの普通の文。分かち書きはしない
  - ハテナはくだけた口調（だ・よ）。「やったー」「すごい！」のような幼い言い回し・はしゃいだ感嘆符は使わない。ほめるときも短く（「いいね」「OK」）
  - 子どもっぽい演出（寸劇・わざと間違える課題など）は入れない。短く
  - 練習の問題は一般常識くらい
  - オンラインの画面など、本番の画面のボタン名は画面の文字のまま『』で囲む（本番の画面の文字は変えない）
- **担当（サブエージェント）を同時に動かさない**（2026-10-25「節約のため並列で作業するのをやめて」）。段階7からは1人ずつ順番に。実装はユーザーの指示で Opus（「実装はopusを使って」）。撤去のような削除作業は Sonnet（「削除作業はクレジット節約のためsonnetで」）
- **コミット・プッシュはユーザーに言われたときだけ**。まだ何もコミットしていない
- **作業ツリーにはほかのセッションの未コミットの変更が大量に混ざっている**。ほかの人の変更を戻さない・整形しない。`git checkout`・`stash`・`reset`・`restore` はしない。コミットするときは、ステージ済みとまだのものの両方を含める（ユーザーの以前の指示）
- **台詞はユーザーが Godot エディタの下パネル「セリフ」でも直す**（`addons/practice_text_editor`。別のセッション「チュートリアル台詞編集ツール」が作った）。保存すると `scripts/practice/practice_texts.gd` と台本の表（`courseN_script.md` の4章）の両方が直る。2026-10-26 1時ごろに、この道具で台本①〜⑤と `practice_texts.gd` が直されている。**ユーザーが直した台詞を上書きしない**（文字を変えるときは今のファイルを読んでから）
- **Blender（段階9のハテナの動き）**：`AGENTS.md` のとおり、ユーザーが開いているライブの Blender で作る。始める前に Higgsfield の `get_host_status` で Blender（`blr`）の接続を確かめ、つながっていなければユーザーに頼んで待つ。`blender --background` などの別プロセスで代わりにしない。作業した `.blend` は最後に必ず上書き保存する
- Godot の変更は、実際のゲームを動かしてスクリーンショットで確かめる（ウィンドウありのテストで撮って、自分で開いて見る）

## 2. 進み具合

| 段階 | 内容 | 状態 |
|---|---|---|
| 0〜3 | 方針・台本①・旧版の撤去・土台 | ✓ |
| 4 | コース①「基本操作」 | ✓（ユーザー確認済み） |
| 5 | コース②「本番の流れ」（画面のコーチ・メニューの続き） | ✓（ユーザー確認済み） |
| 6 | CPU とコース③「2人対戦」 | ✓（ユーザー確認済み） |
| 7 | コース④「オンライン対戦」（練習では通信しない） | ✓（2026-10-26、ユーザーの「段階8に進んで」で確認） |
| 8 | コース⑤「カスタマイズ」（メインメニューの上だけ。画面を移らない） | ✓（2026-10-26、ユーザーの「段階9に進んで」で確認） |
| 9 | ハテナの新しい動き（ライブの Blender）・影・音・席へ戻る／離れる動き（操縦席・ヘリ）・仕上げ・README・全体テスト | **実装済み・ユーザー確認待ち**（[phase9_design.md](phase9_design.md)） |
| 10 | コース③ 3-1 を「暗い控え室のノートPC」に作り直す（P1・P2 がノートPCの前へ行き、画面と本体のキーで操作を知り、画面に映るステージで練習してから、画面へ拡大してステージに入る） | 台本（[course3_script.md](course3_script.md) v0.3）・流れと絵コンテ（[laptop_keys/flow.md](laptop_keys/flow.md)）・設計（[phase10_design.md](phase10_design.md)）まで（2026-10-29）。**実装はまだ** |

台本の版：①〜⑤すべて v0.2（大人向け）。⑤の台詞は「セリフ」パネルで直された c5.* をそのまま使い、本物の画面と合わない c5.set.2（『戻る』でモード選択へ）だけ外した。

## 3. ファイルの地図

- 計画と台本：`docs/new_tutorial/`（`plan.md`、`course1〜5_script.md`、各段階の設計書、`removal_inventory.md`、この文書）
- 練習の台本側：`scripts/practice/`
  - `practice_director.gd`（ゲーム画面の監督）・`practice_step.gd`・`practice_course.gd`・`practice_catalog.gd`（5コースの一覧。c1〜c5 が遊べる）・`practice_session.gd`（画面をまたぐ値）・`practice_texts.gd`（全部の台詞。ID → 文字）・`practice_cpu.gd`（CPU）
  - `courses/course_1.gd`〜`course_4.gd`
  - `ui/`：`practice_overlay.gd`（吹き出し・進み具合・クリアカード）・`practice_coach.gd`（画面のコーチ）・`practice_course_select.gd`・`practice_intro_prompt.gd`・`practice_pick_card.gd`（③の相手を選ぶ）
  - `menu/`：`practice_menu_guide.gd`（②の 2-6 とクリア。メインメニューの上）・`practice_online_guide.gd`（④。オンラインの画面の上）・`practice_customize_guide.gd`（⑤。メインメニュー・カスタマイズ・設定パネルの上）・`practice_seat_moves.gd`（段階9：案内のハテナが席へ戻る・席を離れる動き。のこぎりの操縦席・ヘリ）
- ハテナの動きと音（段階9）：`assets/characters/aiquiz_mascot/source/build_practice_mascot.py`（ライブの Blender で実行 → `mascot_practice.glb`、原本は `aiquiz_mascot.blend`）、`tools/audio/make_practice_sfx.py`（→ `assets/audio/sfx/practice/`）
- ⑤の本編側の道具：`scripts/ui/main_menu.gd` の `practice_start_here`・`practice_customize*`・`practice_*settings`・`practice_coach_target` の `set_*`、`scripts/ui/customize_settings.gd` の最後の `practice_coach_target`・`practice_section`・`practice_set_wall_speed`
- 舞台の小物：`scripts/world/practice/`（`hatena_guide.gd`・`hatena_portrait.gd`・`sign_wall.gd`・`practice_floor_marks.gd`・`practice_shapes.gd`）
- 本編側の練習の入口：`scripts/core/match_rules.gd`（練習のルール）、`scripts/core/game_state.gd` の `# ---------- Practice ----------` と `practice_rules` の分岐、`scripts/world/game_world.gd` の `_is_practice()` の所と `practice_*` の道具、HUD（`gameplay_hud.gd` など）、`scripts/ui/main_menu.gd`、`scripts/ui/online/`
- 台詞の編集の道具：`addons/practice_text_editor/`（別のセッションのもの）

## 4. テストの流し方（いま通っている数）

Godot は作業フォルダの `./Godot_v4.7.2-stable_win64_console.exe`。ウィンドウありは `--headless` を付けない。1つずつ順番に流す（同時に流さない）。

| テスト | コマンドの `--script` | 数 |
|---|---|---|
| 練習の単体（ヘッドレス） | `tests/practice_unit_bootstrap.gd` | 424 |
| 台詞の道具（ヘッドレス） | `res://tests/practice_text_store_unit.gd` | 354 |
| ①の通し（ウィンドウ） | `tests/practice_smoke_bootstrap.gd` | 178 |
| ②の通し（ウィンドウ） | `tests/practice_course2_smoke_bootstrap.gd` | 125 |
| ②のメニューの続き（ウィンドウ） | `tests/practice_menu_coach_bootstrap.gd` | 84 |
| コーチ単体（ウィンドウ） | `tests/practice_menu_coach_bootstrap.gd -- runtime=res://tests/practice_menu_coach_unit.gd` | 45 |
| ③の通し（ウィンドウ） | `tests/practice_course3_smoke_bootstrap.gd` | 207 |
| CPU（ウィンドウ） | `tests/practice_cpu_bootstrap.gd` | 49 |
| 小物の見た目（ウィンドウ） | `tests/practice_props_preview_bootstrap.gd` | 78 |
| ④の通し（ウィンドウ） | `tests/practice_course4_smoke_bootstrap.gd` | 150 |
| ⑤の通し（ウィンドウ） | `tests/practice_course5_smoke_bootstrap.gd` | 134 |
| 席の乗り降り（ウィンドウ。段階9） | `tests/practice_seat_moves_bootstrap.gd` | 28 |
| オンラインメニュー（ウィンドウ） | `tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_menu_runtime.gd` | 37 |
| 本編 HP（ヘッドレス） | `tests/hp_bootstrap.gd` | 196 |

撮った画面は `artifacts/practice_smoke/`・`practice_course2/`・`practice_menu/`・`practice_course3/`・`practice_cpu/`・`practice_props/`・`practice_course4/`・`practice_course5/`・`practice_seat_moves/`（④⑤と席の乗り降りは要所をまとめた `contact_sheet.jpg` もある）。ハテナの動きの確認の絵は `artifacts/practice_mascot/`（Blender で撮る）。
ほかのセッションが同時に Godot を動かしていると、実時間で進む通しテスト（特に③の押し合い・3-7）が間合いのずれで落ちることがある。そのときは、ほかの Godot が止まってから流し直す。
新しい `class_name` を足したら、コマンドラインで流す前に `--headless --path . --import` でクラスの一覧を作り直す（エディタが開いていてもよい）。
もとから落ちているもの（今回の対象外）：のこぎりのテストの「retreats into saw during grace」8件、サドンデス関係。

## 5. 残っている問題（あとで直す候補）

段階9で直したもの：①「スタート」の文字のかぶり、仮の音（ぽこっ・ピコン・ポン・ぽよん・ひゅーん・パチン）とまきもどしの音、②の席を離れる最初に動く席へ付いていかない、③スコアタワーの見出しの重なり、④ハテナが2人映る、「Lambda capture at index 0 was freed」、ハテナの仮の動き・影、初回の案内の「？」の丸（詳しくは [phase9_design.md](phase9_design.md) 4章）。

- ②：作業の途中に一度、コーチの吹き出しが数秒止まった（対策後は再現なし。原因は不明）
- ③：3-5 の操縦席はカメラに入らない（吹き出しは画面の上）。3-5・3-6 の席の行き来は、今までどおり雲で飛んで入れ替わる。3-2 の壁2で P1 が画面の外に出るのは本番のカメラのふるまい。テストで通していない道：3-2 で2人とも間違えたときのまきもどし、CPU との 3-7 で海まで飛ばされたとき、人どうしの 3-5・3-8
- ④：Esc でレッスンをとばす流れは自動テストで通していない。ヘリへの乗り降りは約 10 秒かかる（4-1 の前・4-6 の前・クリアのあと）。機内はふだんのカメラからほとんど見えない
  - 「試合がいつも引き分けになる」は CPU のせいではなかった（2026-10-26）。テストが「やめますか？」の間に D を押しっぱなしにして、P1 が床の外（海）へ落ちていた。テストを直して、いまは P1 が 2対0 で勝つ
  - ④の通しテストで一度だけ、4-4 の『← もどる』のクリックが効かなかった（もう一度流すと通った。原因は不明）
- ⑤：エモートのタブでは、踊るキャラの腕が左上のハテナのうしろに重なることがある（ハテナが手前で読める）
- のこぎりの操縦席のハテナと入れ替わるとき、手（スティック）と足（ペダル）だけ少し動く（座った姿はヘリの操縦士の形）。ヘリの操縦士のヘッドセットは、入れ替わったときに出てくる
- 合成した効果音は、耳で聞いた確かめをしていない（大きさは数字でそろえた）。ユーザーに聞いてもらう

## 6. まだ決めていないこと（ユーザーに聞く）

1. メニューでの名前：いまは「チュートリアル」
2. スタンプを5つ集めたときのごほうび：あり（例：特別な帽子）／なし

## 7. 次にやること

1. 段階9のユーザーの確認をもらう（実際に遊んでもらう。ハテナの動き：`artifacts/practice_mascot/contact_sheet*.jpg`・`artifacts/practice_props/`、席の乗り降り：`artifacts/practice_seat_moves/`、音は耳で）。OK なら plan.md の段階9の行を ✓ にする
2. 6章のまだ決めていないことを聞く
3. ユーザーに言われたらコミット
