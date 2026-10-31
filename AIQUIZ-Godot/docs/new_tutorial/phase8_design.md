# 段階8 コース⑤ の設計（v1）

2026-10-26。[計画書](plan.md) の段階8（コース⑤「カスタマイズ」）の設計。
台本は [course5_script.md](course5_script.md)（v0.2）。土台は [foundation_design.md](foundation_design.md)・[phase5_design.md](phase5_design.md)（画面のコーチ・メニューのガイド・ハテナの小窓）・[phase7_design.md](phase7_design.md)（カメラが動く画面でハテナを浮かべる・Esc でレッスンをとばす）。旧チュートリアルは参照しない（撤去済み）。

**進め方**：段階7と同じく担当を同時に動かさない。監督役が本編側と台本側を順番に作る。

## 0. 段階8で「できた」と言える状態

1. コース選択で⑤が遊べる。選ぶとコース選択が閉じ、画面を移らずにメインメニューの上で⑤が始まる
2. 5-1〜5-6：メインメニュー・カスタマイズの画面・設定パネルの上で、画面のコーチ（`PracticeCoach`）が台本どおりに案内する
3. ハテナ：メニューでは、のこぎりの操縦席のハテナが雲で出てきて右側に浮かぶ（②の 2-6 と同じ）。カスタマイズの間は左上に浮かび、カメラが動いても画面の同じ所にいる。設定パネルの間は右下の小窓。終わったら操縦席へ戻る
4. 帽子とエモートの枠は、選んだものが本番の設定に残る。壁の速さは 5-4 の前の設定に戻る
5. クリア：メニューの上でクリアカードとスタンプ（★なし）。5つそろったときだけ「スタンプが全部そろったね！」。［メニューに戻る］でモード選択へ
6. Esc でいまのレッスンをとばせる。とばしても、次のレッスンに要る画面は練習が開く・閉じる
7. 本編（メニュー・カスタマイズ・設定パネル）とコース①〜④の動きは変わらない

## 1. 作るもの

### 1.1 始め方（`practice_catalog.gd`・`practice_session.gd`・`main_menu.gd`）

- `PracticeCatalog` の c5：`available = true`、`scene = "res://ui/main_menu.tscn"`（メニューの上で遊ぶ）
- `PracticeSession.launch`：コースの `scene` が、いまのメニューの画面と同じなら、画面を移らずに `menu.practice_start_here(id, first_run)` を呼ぶ
- `main_menu.gd`：
  - `practice_start_here(id, first_run)`：コース選択を閉じ、`resume_in_menu` と同じ形（`{"course": "c5", "step": "", "first_run": …}`）でメニューの上のレッスンを始める
  - `_start_practice_menu_guide(resume)`：`c2`/`2-6` は今までどおり `PracticeMenuGuide`、`c5` は新しい `PracticeCustomizeGuide`
  - `_can_open_practice_panel`：⑤の案内の間も開かない

### 1.2 光らせる部品と道具

`main_menu.practice_coach_target(id)` に足す（設定パネル。1つの部品を返す。まとまりは案内が並べて光らせる）：

| id | 部品 |
|---|---|
| `&"set_bgm"`・`&"set_sfx"` | 『BGM音量』『効果音量』の行 |
| `&"set_resolution"`・`&"set_fps"`・`&"set_quality"` | 『解像度』『FPS上限』『画質』の行 |
| `&"set_sudden"` | 『サドンデス（2P 10問の引き分け）』の行（出ていなければ null） |
| `&"set_connection"` | 接続状態（3つの行・オフライン問題数・『再チェック』） |
| `&"set_back"` | 設定パネルの『戻る』 |

`customize_settings.gd` に足す：`practice_coach_target(id)`

| id | 部品 |
|---|---|
| `&"tab_wall"`・`&"tab_skin"`・`&"tab_emote"` | タブ『壁速度』『スキン』『エモート』 |
| `&"skin_players"` | 『プレイヤー１』『プレイヤー２』の行 |
| `&"skin_hat"` | 帽子の ◀ 名前 ▶ の行 |
| `&"preview"` | 左のプレビュー（右ドラッグ・ホイールを受ける見えない部品） |
| `&"emote_slots"`・`&"emote_slot1"` | エモートの枠（1・2・3）の行・1番の枠 |
| `&"emote_grid"` | 踊りの一覧 |
| `&"wall_mode"`・`&"wall_slider"`・`&"wall_reset"` | 「自動モード／手動モード」の表示・スライダー・『自動モードに戻す』 |
| `&"done"` | 『✓ 決定して戻る』 |

ほかの道具：

- `customize_settings.gd`：`practice_section() -> StringName`（`&"wall"`・`&"skin"`・`&"emote"`）、`practice_set_wall_speed(override)`（0 以下は『自動モードに戻す』と同じ、正ならその速さ）
- `main_menu.gd`：`practice_customize()`（カスタマイズの画面）、`practice_customize_ready()`（開ききって押せる）、`practice_customize_open()`、`practice_open_customize()`・`practice_close_customize()`（とばしたとき用）、`practice_settings_open()`・`practice_open_settings()`・`practice_close_settings()`

### 1.3 案内 `PracticeCustomizeGuide`（新しい `scripts/practice/menu/practice_customize_guide.gd`）

②の `PracticeMenuGuide` と④の `PracticeOnlineGuide` と同じ作り（コーチ・上のコース名と点・背景のハテナ・クリアカード）。

- レッスンごとに `_begin_lesson(i)`：進み具合の点、Esc でとばせるようにする、そのレッスンに要る画面にする（5-1 はモード選択、5-2〜5-5 はカスタマイズ、5-6 は設定の画面）
- 待つ条件：『10問チャレンジ』（`menu_step`）、カスタマイズが開ききる、タブ（`practice_section`）、帽子（`p1_hat`・`p2_hat`）、踊りの一覧のボタンの `pressed`、スライダーの `value_changed`、カスタマイズが閉じる、設定パネルが開く・閉じる
- ハテナ：浮かんでいる間は `_hover_spot()` に付いていく。メニューでは右側（`(0.85, 0.47)`、奥行き 10 m）、カスタマイズの間は左上（`(0.1, 0.25)`、カメラの近く。近い分だけ小さく）。カスタマイズの開け閉めのときは雲で飛ぶ
- 設定パネルの間：背景のハテナはパネルに隠れるので、コーチの小窓（`show_portrait`）を出し、吹き出しは小窓の頭の上
- 壁の速さ：5-4 の始めに `tuning.wall_speed_override` を覚え、終わり（とばしたときも）に `practice_set_wall_speed` で戻す
- 文字は全部 `PracticeTexts` の `c5.*`

## 2. 確かめ方

- 新しい `tests/practice_course5_smoke_bootstrap.gd`（ウィンドウあり）：コース選択から⑤を始め、5-1〜5-6 とクリアの［メニューに戻る］まで、キー入力とクリックで通す。光っていない所は押せないこと、帽子が保存されること（テスト用の保存先）、壁の速さが元に戻ること、カスタマイズの間ハテナが左上にいること。もう1回、Esc でとばしながら通す。要所を `artifacts/practice_course5/` に撮って、自分で開いて見る
- 練習の単体テスト（c5 のカタログ）、台詞の道具のテスト（c5 の文字を使っている）、②のメニューの続き・コーチ、①〜④の通しテストが通ること

## 3. 作りながら決めたこと（2026-10-26）

- **本物の画面を撮って確かめた**：『設定 / API状態』は設定の画面の右下にもあるので、台本 v0.1 の「『戻る』でモード選択へ」（c5.set.2）は外した。カスタマイズは『壁速度』のタブで開き、設定のパネルは画面の右側。設定パネルは画面全体をふさぐ（3D の背景は見えない）
- **始め方**：⑤だけはコース選択から画面を移らない。`PracticeSession.launch` が、コースの `scene` がいまのメニューと同じときに `menu.practice_start_here` を呼ぶ（`resume_in_menu` は使わない）
- **ハテナの居場所**：メニューでは②と同じ右側。カスタマイズの間は左上（`(0.1, 0.3)`、カメラから 2.4 m）。スキン・エモートのタブはカメラの画角が狭くなるので、画角の分だけ小さくして、見た目の大きさをそろえる。エモートのタブでは、踊るキャラの腕がハテナのうしろに重なることがある
- **浮かぶ所を移る飛び方**：近い所（カスタマイズ）と遠い所（メニューの右側）を世界の中でまっすぐ結ぶと、途中で画面の外へはみ出したので、画面の上の位置と奥行きを別々に移す（`_glide`。画面の上では小さな弧）
- **設定パネルの間**：右下の小窓のハテナ。上のコース名の札はパネルの見出し「設定」に重なるので隠す（`overlay.set_header_visible`）。光らせる行が横に広く、吹き出しが小窓のハテナの顔にかぶったので、コーチに `portrait_avoid`（小窓に重なる広さの数え方。既定 0.5 のまま、⑤だけ 2.0）を足した
- **押せる・見せるだけ**：音量のスライダーは動かせる。『解像度』『FPS上限』『画質』・サドンデスの行・接続状態は見せるだけ（練習の間は選べない）。『管理ダッシュボードを開く』は押せない
- **壁の速さ**：5-4 の始めに `tuning.wall_speed_override` を覚え、終わり（とばしたとき・案内ごと消えたときも）に `practice_set_wall_speed` で戻す。壁の速さとエモートの枠は、本編でももとから保存しない（その起動の間だけ）。帽子は保存される
- **とばす**：5-2〜5-4 は、タブがもう開いていれば「押してみて」の一言をとばす。5-1 をとばすと練習が設定の画面にしてカスタマイズを開き、5-5 をとばすと閉じ、5-6 をとばすと設定パネルを閉じる
- **クリア**：設定の画面の上でカード（★なし）。スタンプが5つそろったときだけ「スタンプが全部そろったね！」。［メニューに戻る］（Esc でも）でモード選択へ
