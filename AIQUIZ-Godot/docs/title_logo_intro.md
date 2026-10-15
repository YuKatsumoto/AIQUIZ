# タイトルの登場演出（2D のベルトコンベア）

起動して最初のメインメニューで、タイトル「AIQUIZ」をベルトコンベアで組み立てて見せる（2026-10-12〜）。
演出が終わると、いつもの 2D のロゴ（画像）とその下の黄色い線に戻る。
**動き（時間・キー・イージング）は After Effects で作り**（`tools/title_logo_ae/AIQUIZ_TitleLogo.aep`）、Godot は AE から書き出した動きを再生する（LED 番組の `AeMotion` と同じ作り方）。

## 流れ（秒はメニューが見えてから。全部で 6.15 秒）

| 時間 | できごと |
| --- | --- |
| 0.35〜1.34 | タイトルの下の黄色い線が右へ伸び、太くなって持ち上がり、ベルトコンベアになる（紺のベルト・黄色の上の縁・動く桟・両端の回るローラー。少しだけ行き過ぎて戻る） |
| 0.95〜1.55 | ベルトが一定の加速で動き出し、秒速 125 論理ピクセルになる |
| 1.35〜3.57 | ロゴの文字がベルトの左端（A の定位置）へ、上から 1 文字ずつ落ちてくる（Z → I → U → Q → I → A）。重力のとおりだんだん速く、傾いて落ち、着くとつぶれて 2 回小さく弾み、土ぼこりが出る |
| 3.52〜3.57 | ベルトが右の定位置まで運び、定位置で「カチッ」と止まる（少し行き過ぎて戻り、縦につぶれる。どの文字もほぼ同時にそろう） |
| 3.57〜4.32 | 全部そろうと、ベルトがゆっくり止まる |
| 4.12〜4.62 | A→Q の斜め線が Q の切れ目からすぐに出て、なめらかに加速しながら A の足もとへ伸びる（I のすき間を通り抜ける。出だしは平均の 0.45 倍、着くときは 1.9 倍の速さ）。着いても揺れや火花はない |
| 5.07〜6.02 | ベルトコンベアが細く縮んで元の黄色い線に戻る（文字は動かない） |
| 6.15 | 2D のロゴの画像に入れ替わる（定位置の文字と画像はぴったり重なるので見た目は変わらない） |

- 2026-10-12 の作り直し：AE で作り直し、全体を前の版（3.5 秒）よりゆっくりにした。最後に文字が順に跳ねる動き・ロゴ全体のふくらみはなくした。
  斜め線は「なめらかに勢いよく」（0.5 秒で加速して着く）。いったん付けた着地の揺れ・光・輪・火花は、やっぱりなしにした。
  文字をまっすぐ・弾ませずに落とす版も試したが、落ち方は元の「傾いて落ちて弾む」に戻した
- ベルトは右へ流れるので、文字は右の Z から順に落とす。前の文字と重ならないよう、落とす時刻は文字の幅と間（8 px）とベルトの速さから決める
- 演出中にキーやクリックをすると 5 倍速で終わる（押したボタンはそのまま効く）
- 2 回目以降のメニュー（ゲームから戻ったときなど）と、カスタマイズの案内から始まるときは演出しない（`QuizManager` のメタ `title_logo_intro_seen`）
- 演出のあいだは 2D のロゴの画像を隠し、黄色い線（`TitleAccentBar`）は `self_modulate` で透明にする（VBox の並びは変えない）。ロゴの画像はメニューが見える前から隠すので、ロード画面が消えるときにロゴが一瞬見えることはない
- 動きのファイルが読めないときは演出せず、2D のロゴのまま

## 作り

| ファイル | 役目 |
| --- | --- |
| `scripts/ui/title_logo/title_logo_intro.gd` | 再生（`TitleLogoIntro`）。`TitleLogo`（2D のロゴの画像を載せた入れ物）の子に置くので、メニューの入退場の横すべり・透明度をそのまま受け継ぐ。`build_layout()` が文字の定位置・形とベルトの場所を決める（AE に渡すのも同じ値） |
| `assets/ui/title_logo/title_logo_motion.json` | AE から書き出した動き（`sample_title_logo.jsx` が作る。手で直さない） |
| `scripts/ui/title_logo/title_logo_geometry.gd` | ロゴの JSON（`assets/branding/logo/aiquiz_logo.json`）から、文字ごとの多角形を作る。形の計算は `tools/logo_editor/logo_geometry.js` と同じ |
| `scripts/ui/main_menu.gd` | `_setup_title_logo_intro`（作る・ロゴを隠す）、`_start_title_logo_intro`（ロードが終わったら始める）、`_input`（早送り） |

### Godot が AE から読むもの

- `CTRL` のスライダー：`Form`（0 = 黄色い線、1 = ベルト）、`Travel`（ベルトが送った距離、論理ピクセル）、`Reveal`（斜め線の伸び 0〜1）。ベルトの絵は `TitleLogoIntro._draw` が `Form`・`Travel` から描く（AE の `BELT` レイヤーの式と同じ計算）
- `L_<文字>`（文字の形）と親の `M_<文字>`（ヌル）の位置・回転・拡大・不透明度・アンカーとイン点。親までの変形を合わせて文字の `Polygon2D` に載せる。AE のピクセルは論理ピクセルの 4 倍（`scale`）、AE の (0, 0) は `TitleLogo` の中の (−30, −140)（`origin`）
- `L_d1`：A→Q の斜め線。`Reveal` で、線の向きに測って Q の側から見えている長さだけを `Geometry2D.intersect_polygons` で切り取って描く（AE では同じ形のマスクを式で動かしている）
- `DUST_<n>`：文字の着地の土ぼこり（文字の下に描く）。`FX_<名前>` のレイヤーがあれば文字の上に描く（`Effects`。今の AE には無い）。
  どちらも形（円の塗り・円の線・両端の丸い長方形）と、位置・回転・拡大・不透明度を読む
- 文字の形は AE からは読まず、いつもロゴの JSON から作る。定位置も今のロゴから求め、AE の止まった位置との差だけずらすので、ロゴエディタで形を少し直しても演出の終わりは画像とぴったり重なる（動きの大きさを合わせ直すときは下の手順で作り直す）

### 文字の形

- ロゴの要素は id の「_」より前でまとめる（`a_left`・`a_right`・`a_bar` → 文字「A」、`q_ring`・`q_tail` → 「Q」）。cut（すき間）は、それより前に塗った要素だけから引く（ロゴエディタの描く順と同じ）
- 多角形は `Polygon2D`（なめらかな縁）で描き、定位置にそろうと 2D のロゴの画像とぴったり重なる（大きさは `TextureRect` と同じく、`TitleLogo` の中で縦横比を保ってまん中ぞろえ）
- 影は 2D のロゴと同じ右下 3 px・黒 75％。影と白い面はそれぞれ `CanvasGroup` にまとめて描くので、A の脚と横棒の重なりのような部分でも影が濃くならない（AE のプレビューはレイヤーごとのドロップシャドウ）

## After Effects の制作データ（`tools/title_logo_ae/`）

| ファイル | 中身 |
| --- | --- |
| `AIQUIZ_TitleLogo.aep` | After Effects 2026（26.5）。フォルダ `AIQUIZ_TitleLogo` のコンポ `TitleLogo_Intro`（1240×960・60 fps・6.15 秒）。マーカー DEPLOY・LAND <文字>・ALL SEATED・A-Q BAR・BAR DONE・COLLAPSE・LOGO |
| `export_layout.gd` | 文字の形・定位置・ベルトと黄色い線の場所を `layout.json` に書き出す（Godot、ヘッドレス） |
| `build_title_logo.jsx` | `layout.json` からコンポをいちから組み立てて保存する（開いているプロジェクトは保存せずに閉じる。AE で手で直したところは、先にこのスクリプトへ写す） |
| `sample_title_logo.jsx` | `assets/ui/title_logo/title_logo_motion.json` を書き出す（スライダーと各レイヤーの変形を 60 fps で） |
| `render_review.py`（`render_review.jsx`） | 指定の秒をフレームにしてコンタクトシートを作る（`artifacts/title_logo_ae/`） |
| `render_movie.jsx` | 確認用の動画 `artifacts/title_logo_ae/TitleLogo_Intro.mp4`（H.264） |
| `ae_run.mjs` | Higgsfield のローカル AE ブリッジ経由で .jsx を実行 |

コンポの中（上から）：`CTRL`（スライダー）、`DUST_<n>`、`L_<文字>`（形・ドロップシャドウ・つぶれと伸び。`M_<文字>` の子）と `M_<文字>`（X・Y を分けた位置と回転）、`L_d1`（マスク `Reveal`）、`BELT`（式で描くベルト）、`BG_Preview`（確認用の背景。Godot は読まない）。

動きの約束：落下は重力どおり（止まった所から高さ 105 を 0.60 秒、速さが一定の割合で増える）で傾いて落ち、着くとつぶれて 2 回弾む、ベルトの上は一定の速さ（文字の X はベルトと同じ速さ）、止まるところだけ小さく行き過ぎて戻る、斜め線は止まらずに加速して着く（Reveal のキーの速さ：出だし 0.45 倍・着き 1.9 倍、影響 33.33％でなめらかな速さの曲線）。Godot はモーションブラーを描かないので AE でも切っている。

```powershell
# ロゴの形や大きさを変えたとき
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/title_logo_ae/export_layout.gd
node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/build_title_logo.jsx
# AE でキーを直したあとは、これだけで Godot に反映される
node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/sample_title_logo.jsx
# 確認
python tools/title_logo_ae/render_review.py artifacts/title_logo_ae/sheet.jpg 1.0,2.0,3.0,4.5,6.0
node tools/title_logo_ae/ae_run.mjs tools/title_logo_ae/render_movie.jsx
```

デバッグビルドでは、メニューで次のキーが使える（F7・F8 はエディタの実行の操作と重なるので使わない）。

| キー | はたらき |
| --- | --- |
| PageUp | 演出をもう一度 |
| PageDown | 0.25 倍速と等倍の切り替え |
| End | 次の演出から、0.05 秒ごとの画面を `user://title_logo_frames/` に保存する（もう一度押すと止める） |

## 確かめ方

- 形と動き：`tests/title_logo_geometry_check.gd`（部品の分かれ方・すき間・向き・縦横比が 2D のロゴの画像と同じか。AE の動きが読めて、始まりは黄色い線だけ、終わりは全部の文字が定位置・傾きなし・等倍で黄色い線に戻り、斜め線が全部見えているか。2026-10-12 時点で 43 項目）
  `./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/title_logo_geometry_check.gd`
- Godot での絵：`tests/title_logo_intro_capture.gd`（演出だけを窓で再生し、指定の秒を `artifacts/title_logo_intro/` に保存する。メニューの 3D は作らない）
  `./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/title_logo_intro_capture.gd -- 1.0,2.0,4.5`
- メニューの中：デバッグキー（上の表）で撮った画面

## 効果音

2026-10-09 から、効果音は壁の衝突とカウントダウンだけにしている（`docs/sound_effects.md`）ので、この演出にも音は付けていない。
付けるなら、ベルトの起動（ガコン）・文字の着地（トン）・定位置で止まる（カチッ）・斜め線が伸びる（シュッ）が合う。
