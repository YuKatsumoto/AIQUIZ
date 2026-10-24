# タイトルのロゴと登場演出（2D のベルトコンベア）

ゲームのタイトルは **TESTOPIA**（2026-10-17〜。それまでは AIQUIZ）。
起動するとすぐにメニューのモード選択が出る（タイトル画面は無い）。ロゴの大きさはいつも同じ（高さ 56 論理ピクセル。AIQUIZ のころと同じ。
2026-10-18 まではモード選択のあいだだけ 1.55 倍に大きくしていたが、やめた）。
起動して最初のメニューでは、ロゴをベルトコンベアで組み立てて見せる。ロゴはメニューのどの手順でも、紺の厚みのある文字が立体のベルトの上に立った姿のまま
（2026-10-18〜19 に一時、モードを選ぶと 2D（厚みをたたみ、線を細くして間を詰める）にしていたが、やめた）。
**動き（時間・キー・イージング）は After Effects で作り**（`tools/title_logo_ae/TESTOPIA_TitleLogo.aep`）、Godot は AE から書き出した動きを再生する。

## ロゴの形

- 厚みの色：紺（`DEPTH_COLOR`、一番手前の 1 枚は `DEPTH_EDGE_COLOR`）
  （2026-10-19 に一時、P1・P2 の色や問題の壁の灰色にしていたが、紺に戻した）
- 見た目（2026-10-17〜）：白い文字に**紺の厚み**（立体のブロック。`TitleLogoIntro.DEPTH_OFFSET` だけ右下へずらした同じ形を細かく重ねる）。
  2026-10-18〜：明るい空やビルに溶けないよう、面＋厚みのブロックのまわりを濃い紺の縁（1.5 論理ピクセル）で囲む（`LETTER_OUTLINE_*`、`shaders/title_logo_outline.gdshader`）。
  2026-10-19〜：Godot 4 の Polygon2D は縁をなめらかに描かない（`antialiased` も Line2D も効かず、CanvasGroup の中には画面の MSAA も届かない）ので、
  文字の面と厚みは CanvasGroup にまとめて `shaders/title_logo_smooth.gdshader` で縁を 1 画素ぶんならし、縁取りのシェーダーも外の縁を 2 段にならす。
  さらに**スーパーサンプリング**：文字（縁取り・厚み・面）と扉のブロック・爆散の煙は、画面の 4 倍（`SUPERSAMPLE`。一辺が 4096 画素を超えるときは 3 倍・2 倍）の
  解像度の SubViewport に描き、`shaders/title_logo_downsample.gdshader` で 4×4 画素の平均にして縮めて見せる（`SupersampleView`）。
  描く範囲はロゴのまわりの余白（`SUPERSAMPLE_PAD_*`：左右 48・上 300・下 72）。遠くまで飛ぶ爆散の破片と、ベルト・土ぼこりは画面に直接描く。
  演出のあいだは毎フレーム、止まっているときは変わったときだけ描き直す（`_refresh_supersample_mode`）
  厚みは薄めで、**奥（右上）へ**伸びる（`DEPTH_OFFSET` = 3.0, -3.8）。ベルトの上の面が奥へ伸びる向きと同じなので、文字はベルトの上に立って見える。
  **2026-10-19〜 Godot は平らなベルトを描く**（`FLAT_BELT` = true、`_draw_flat_belt`）。書体を選んだ比較ページの見本（Stereofunk の A 案）と同じ形と寸法：
  影・紺の棒・下の暗い帯・止まった目盛り・両端のローラー、上の縁は黄色い板の並び（すき間が左へ流れる）。文字の縁の下の端がベルトの黄色い縁に少し重なって立つ
  （`BELT_DROP` = 0.84、高さ `BELT_HEIGHT` = 11.84。寸法は見本の em の比率をそのまま論理ピクセルにした）。接地影は描かない。
  AE（`build_title_logo.jsx`）の `BELT` はいまも下の立体のベルトのまま（Godot は AE のベルトの絵を読まないので、動きだけが使われる）。
  `FLAT_BELT` を false にすると、下の立体のベルトに戻る。
  立体のベルト（`TitleLogoIntro._draw`）：
  - 前の面：鉄の枠（黄色い手前の縁・その下の光・止まっているリベット・下の暗い縁・両端の回るローラー）
  - 上の面：奥へ斜めに伸びる帯（`BELT_TOP_*`・`BELT_SKEW`）。板の溝と板の角の光が左へ流れ（2026-10-19 までは右へ）、奥の縁が明るい
  - 側面：前の面を奥へずらした形とのあいだ（右の端と、ローラーに巻き付く所。`_belt_body` が凸包で作る）。影も同じ形
  - 文字の足もとの接地影（`CONTACT_SHADOW_*`）：上の面に落ち、文字が高く上がるほど薄い
  文字の前の面の下の端（縁の外側）は、上の面の手前の縁から `BELT_STAND_MARGIN` だけ奥（`BELT_DROP`。`build_layout` の `belt_rect` に入っているので AE も同じ）。
  AE（`build_title_logo.jsx`）も `layout.json` の `depth`・`outline`・`belt`・`contact_shadow` から同じ厚み・縁・ベルト・接地影（`CS_<文字>`。Godot は読まない）を描く
  文字は**書体 Stereofunk**（2026-10-19〜）。**O の穴は紺の奥に P1 の頭（オレンジの立方体）、A の穴は P2 の頭（青の立方体）が見える**。
  頭は文字の紺の厚み（`DEPTH_OFFSET`）と同じ向き・長さで右上へ伸び、前の面と上の面が見える（右の面は穴の外で隠れる。2026-10-19 の途中までは左上へ伸びる前・上・左の面だった）
  （頭の前の面は穴の右と下の縁まで届かせ、右と下に紺のすき間を作らない。頭の面は穴の形で切り抜くので穴の外へは出ない）
  （P1・P2 の色は `player_health_hud.gd` の `PLAYER_COLORS`）。I は書体のままの I
  （2026-10-17〜19 は AIQUIZ のロゴの部品で組み、I を「!」（点は P2 の青）にしていた。その形は `assets/branding/logo/history/testopia_logo_20261019_parts.*` と
  `tools/logo_editor/build_testopia_logo_parts.mjs` に残してある）
- 要素の `color`（無ければ白）で塗り、`flat` の要素（O と A の穴の中）には厚みを付けない（`TitleLogoGeometry` が多角形ごとに渡す）
- 演出のあいだだけ、T（1つ目）と E は**問題の壁の扉のブロック**に入っている（下の「扉のブロック」）

- `assets/branding/logo/testopia_logo.json`（と `.svg`・`.png`）。`tools/logo_editor/build_testopia_logo.mjs` が作る（ロゴエディタと同じ書式）
- 書体 Stereofunk（`tools/logo_editor/fonts/Stereofunk.ttf`。入手先とライセンスは同じフォルダの `README.md`）の字形で組む。
  `extract_font_glyphs.py`（fontTools）が字形を直線だけの多角形にして `tools/logo_editor/testopia_font_glyphs.json` に書き出し、
  `build_testopia_logo.mjs` が 1 字ずつ 1 つの多角形（`kind: "poly"`）にする。穴（O・A・P）は外周へ幅 0 のすき間でつなぐ。
  字の高さは部品で組んでいたころと同じ（T の高さ 132.8、1024 の画用紙）、字間は 0.05 em（T（1つ目）と E、S と T（2つ目）は 0.03 em 詰める。`KERNING`）。
  A の穴は書体では下の切れ込みと幅 2 単位（0.4 px）のすき間でつながっているので、組むときに閉じる（`snapToEdges`）
- 形の要素は、線（中心線と太さ）・輪・多角形（`kind: "poly"`。頂点を順に結ぶ）が使える（`logo_geometry.js`・`TitleLogoGeometry` の両方）
- 部品の名前は要素 id の「_」より前：`t1`・`e`・`s`・`t2`・`o`・`p`・`i`・`a`
- `assets/ui/branding/testopia_logo.png` は演出が作れないときの予備の画像（`tools/logo_editor/render_logo_png.gd`）

```powershell
python tools/logo_editor/extract_font_glyphs.py   # 書体を替えたときだけ（fontTools が要る）
node tools/logo_editor/build_testopia_logo.mjs
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/logo_editor/render_logo_png.gd
```

## 扉のブロック（T と E）

- 灰色の枠（問題の壁の色）に、同じ幅の青と赤の扉（`quiz_wall.gd` の `DOOR_COLORS_2`）がはまった 1 つのブロック（`TitleLogoIntro.DOOR_KEY` = `door`）。
  T（1つ目）と E を左右 6・上に少しはみ出して囲み、下の辺はベースライン。扉は下の辺まで届く（寸法は文字の高さに比例。`_door_layout`）
- ブロックにも文字と同じ向き・長さの厚み（灰色の陰 `WALL_DEPTH_*`）と濃い紺の縁が付く。ベルトの上では 1 つの部品として運ばれる
- 全部そろったあと、震えてふくらみ（0.3 秒）、爆散する：6×4 の破片（`shard0`〜`shard23`。厚み・縁なし）が回りながら飛び散って落ち、
  煙（`FX_PUFF_<n>`）が広がり、中から T と E が 55％→110％→100％ に飛び出す
- 定位置の測り方：ブロックは消える `REST_BEFORE_OUT`（0.34）秒前（震える前）、破片は出た瞬間、文字は最後の姿
- 2026-10-17 に T（2つ目）と O で作り、10-18 にいったんやめた。10-18 に T（1つ目）と E で戻した

## 流れ（秒は演出の始まりから。全部で 6.15 秒）

| 時間 | できごと |
| --- | --- |
| 0.35〜1.34 | ロゴの左下の黄色い線が右へ伸び、太くなって持ち上がり、ベルトコンベアになる（紺のベルト・黄色の上の縁・動く桟・両端の回るローラー） |
| 0.95〜1.55 | ベルトが一定の加速で動き出し、秒速 150 論理ピクセルになる |
| 1.65〜4.01 | 部品がベルトの**右の端**へ、**画面の外（上）から** 1 つずつ速く（0.5 秒で）落ちてくる（扉のブロック → S → T → O → P → I → A）。重力のとおりだんだん速く、傾いて落ち、着くとつぶれて 2 回小さく弾み、土ぼこりが出る。どの部品も右の端が A の右の端の所に落ち、ベルトが**左へ**定位置まで運び、全部が同時に「カチッ」とそろう（A は最後なので、落ちた所がそのまま定位置）。2026-10-19 までは左の端に落として右へ流していた |
| 4.01〜4.76 | そろうとベルトがゆっくり止まる |
| 4.55〜4.85 | 扉のブロックが震えて少しふくらむ（マーカー SHAKE） |
| 4.85 | ブロックが爆散し（マーカー BURST）、破片と煙が飛び、中から T と E が飛び出す |
| 6.15 | 終わり。ベルトの上の白い TESTOPIA のまま止まる |

- 演出の途中でキーやクリックをすると 5 倍速で終わる（押したボタンはそのまま効く。演出の途中でモードを選んでも、そのまま続きが流れる）
- 2 回目以降のメニュー（ゲームから戻ったときなど）と、カスタマイズの案内から始まるときは演出しない（`QuizManager` のメタ `title_logo_intro_seen`）。
- 本物の黄色い線（`TitleAccentBar`）はいつも透明（VBox の並びのために残す）
- 動きのファイルが読めないときは演出せず、予備の画像のロゴと黄色い線になる
- AE のマーカーは `title_logo_motion.json` の `markers` に入る（`TitleLogoIntro.marker_time`・`marker_passed`）

## 作り

| ファイル | 役目 |
| --- | --- |
| `scripts/ui/title_logo/title_logo_intro.gd` | 再生（`TitleLogoIntro`）。`build_layout()` が文字の定位置・形・色とベルトの場所を決める（AE に渡すのも同じ値）。`setup(logo_size, view_scale)`：大きく見せるときは形を view_scale 倍で作る（今のメニューは等倍）。`start()`・`show_final()`・`finish_now()` |
| `assets/ui/title_logo/title_logo_motion.json` | AE から書き出した動き（`sample_title_logo.jsx` が作る。手で直さない） |
| `scripts/ui/title_logo/title_logo_geometry.gd` | ロゴの JSON から、文字ごとの多角形を作る。形の計算は `tools/logo_editor/logo_geometry.js` と同じ |
| `scripts/ui/main_menu.gd` | `_setup_title_logo_intro`（作る・画像のロゴと黄色い線を隠す）、`_start_title_logo_intro`（最初のメニューだけ流す）、`_input`（早送り） |

### Godot が AE から読むもの

- `CTRL` のスライダー：`Form`（0 = 黄色い線、1 = ベルト）、`Travel`（ベルトが送った距離、論理ピクセル）。ベルトの絵は `TitleLogoIntro._draw` が描く（AE の `BELT` レイヤーの式と同じ計算）
- `L_<文字>` と親の `M_<文字>`（ヌル）の位置・回転・拡大・不透明度・アンカーとイン点
- `DUST_<n>`：着地の土ぼこり（文字の下）。`FX_PUFF_<n>`：爆散の煙（文字の上）
- `L_door`（扉のブロック。爆散で消える）、`L_shard<n>`（破片。式で飛ぶ）、`L_t1`・`L_e`（爆散のときに出る。親のヌルなし）
- 部品（文字・ブロック・破片）の形と色は AE からは読まず、いつも `build_layout()` から作る。定位置も今のロゴから求め、AE の止まった位置との差だけずらす
  （文字の最後の位置で測る）

## After Effects の制作データ（`tools/title_logo_ae/`）

| ファイル | 中身 |
| --- | --- |
| `TESTOPIA_TitleLogo.aep` | After Effects 2026。フォルダ `TESTOPIA_TitleLogo` のコンポ `TitleLogo_Intro`（2080×1040・60 fps・6.15 秒）。マーカー DEPLOY・LAND <部品>・ALL SEATED・SHAKE・BURST・END |
| `AIQUIZ_TitleLogo.aep` | AIQUIZ のころの演出（もう使っていない） |
| `export_layout.gd` | 文字の形・色・定位置・ベルトと黄色い線の場所を `layout.json` に書き出す（Godot、ヘッドレス） |
| `build_title_logo.jsx` | `layout.json` からコンポをいちから組み立てて保存する（開いているプロジェクトは保存せずに閉じる。AE で手で直したところは、先にこのスクリプトへ写す）。時間は先頭の `T` |
| `sample_title_logo.jsx` | `assets/ui/title_logo/title_logo_motion.json` を書き出す（スライダーと各レイヤーの変形を 60 fps で。マーカーも） |
| `render_review.py`（`render_review.jsx`） | 指定の秒をフレームにしてコンタクトシートを作る（`artifacts/title_logo_ae/`） |
| `render_movie.jsx` | 確認用の動画 `artifacts/title_logo_ae/TitleLogo_Intro.mp4`（H.264） |
| `ae_run.mjs` | Higgsfield のローカル AE ブリッジ経由で .jsx を実行 |

動きの約束：落下は重力どおり（止まった所から高さ 270 を 0.5 秒。画面の上の外から入ってくるので、うすく出す動きはない）で傾いて落ち、着くとつぶれて 2 回弾む。ベルトの上は一定の速さ、止まるところだけ小さく行き過ぎて戻る。
Godot はモーションブラーを描かないので AE でも切っている。

```powershell
# ロゴの形や大きさを変えたとき
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/title_logo_ae/export_layout.gd
node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/build_title_logo.jsx
# AE でキーを直したあとは、これだけで Godot に反映される
node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/sample_title_logo.jsx
# 確認
python tools/title_logo_ae/render_review.py artifacts/title_logo_ae/testopia_sheet.jpg 2.3,2.9,3.5,4.1,4.9,6.16
node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/render_movie.jsx
```

デバッグビルドでは、ロゴが見えているあいだ次のキーが使える（F7・F8 はエディタの実行の操作と重なるので使わない）。

| キー | はたらき |
| --- | --- |
| PageUp | 演出をもう一度 |
| PageDown | 0.25 倍速と等倍の切り替え |
| End | 次の演出から、0.05 秒ごとの画面を `user://title_logo_frames/` に保存する（もう一度押すと止める） |

## 確かめ方

- 形と動き：`tests/title_logo_geometry_check.gd`（部品の分かれ方・向き・縦横比、どの文字も白一色か、扉のブロックが T と E を囲み最初に落ちるか、
  AE の動きが読めて、始まりは黄色い線だけ、落ちはじめが画面の外か、爆散の前はブロック・後は T と E と破片か、
  終わりは 8 文字だけが定位置・傾きなし・等倍で、ベルトのままか。文字の紺の厚み、マーカー ALL SEATED・BURST、O と A の頭が穴の右と下まで届くか、落とす場所がベルトの右の端か。2026-10-19 時点で 67 項目）
  `./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/title_logo_geometry_check.gd`
- Godot での絵：`tests/title_logo_intro_capture.gd`（演出だけを窓で 2.4 倍で再生し、指定の秒を `artifacts/title_logo_intro/` に保存する）
  `./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/title_logo_intro_capture.gd -- 2.3,2.9,3.5,4.1,4.6,4.95,6.16`

## ほかの場所のロゴ

ヘリコプターの機体の AIQUIZ のロゴ（外板の 2 か所と計器盤の銘板）は消した（`assets/vehicles/helicopter_boarding/README.md`）。
LED 番組・メニューのステージの看板・灯台とゴールスタンドの看板・スコアボードの見出しは、まだ AIQUIZ のロゴのまま（`tools/logo_editor/apply_logo.py`）。

## 効果音

効果音は壁の衝突とカウントダウンだけにしている（`docs/sound_effects.md`）ので、この演出にも音は付けていない。
付けるなら、ベルトの起動（ガコン）・部品の着地（トン）・定位置で止まる（カチッ）が合う。
