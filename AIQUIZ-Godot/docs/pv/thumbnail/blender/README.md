# サムネイルの描き直し（Blender / Cycles、2026-10-23）

応募用サムネイルの t2（真横の並走）と t5（壁を突き破る瞬間の明暗）を、ゲームのそのフレームそのままの形・位置・色・カメラで
Blender（Cycles）に描き直したもの。ゲームの描画（ラスタライズ）では出せない、光の回り込み・柔らかい影・角の光・滑らかな輪郭を足した。
t5 では、吹っ飛ぶ P2 に動きの尾（モーションブラー）を付けた。

| | できあがり（1920×1080） | 比べる絵 | Blender のファイル |
|---|---|---|---|
| t2 | `../final/t2_blender.png`（1.6 MB）・`.jpg` | `../final/_compare_t2.jpg`、小さく表示：`_small_check_t2.jpg` | `t2_thumbnail.blend`（手で組んだ） |
| t5 | `../final/t5_blender.png`（1.7 MB）・`.jpg`（0.4 MB） | `../final/_compare_t5.jpg`、小さく表示：`_small_check_t5.jpg` | `t5_thumbnail.blend`（`build_scene.py` で組んだ） |
| t7 | `../final/t7_blender.png`（1.8 MB）・`.jpg`（0.45 MB） | `../final/_compare_t7.jpg`（絵コンテ `gen/t2_side.png` と並べたもの） | `t7_thumbnail.blend`（`build_scene.py` で組んだ） |

テクスチャはどれもプロジェクトからの相対パス。

## 流れ

| 段 | どこで | 中身 |
|---|---|---|
| 1. 書き出し | Godot（`tests/pv_capture/pv_thumb_runtime.gd` の `export=<f>`） | そのフレームの最後の刻みでゲームを止め、前景（2 人・帽子・壁・扉・破片・看板・床・枠・レール）を glTF に、カメラ・光・環境・文字・剛体の速度を `scene.json` に。前景を隠した背景だけの絵（`plate_dof.png`・`plate_nodof.png`）、全体の絵（`full_*.png`）、粒だけの絵（`fx_nodof.png`）と粒を隠した全体の絵（`full_nofx_nodof.png`）も撮る |
| 2. 文字の板 | `make_label_textures.py <shot>` | 壁の文字（Label3D）を縁取りつきの透過 PNG に（`tex/<shot>_label_NN.png` と `tex/<shot>_labels.json`） |
| 3. 組み直し | Blender（`build_scene.py` の `build("<shot>")`） | glTF を読み込み、材質をゲームの値で組み直す（下）。カメラ・太陽・環境光は `scene.json` から。文字の板、動きのキー、view layer も |
| 4. 描画 | Blender（`render_layers.py`。`.blend` の Text「thumb_render.py」と同じ） | view layer を 4K・1024 サンプル（ノイズ除去 OIDN 高品質）で描き、.npy に |
| 5. 合成と仕上げ | `compose.py <shot>` | 背景の絵に層を重ねる。ゲームと同じ色の変換（ACES）、床と壁は奥行きでぼかす、粒を重ねる。最後に `../finish.py` と同じ仕上げとロゴ |

t5 の手順（t2 は下の「t2」）:

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t5 quality=ultra sub=8 png tag=thumb_t5_export only=63 export=63
python docs/pv/thumbnail/blender/make_label_textures.py t5
（開いている Blender で）ns = {}; exec(open(r"...\build_scene.py", encoding="utf-8").read(), ns); ns["build"]("t5")
（開いている Blender で）ns2 = {}; exec(bpy.data.texts["thumb_render.py"].as_string(), ns2); ns2["render_all_later"]()
python docs/pv/thumbnail/blender/compose.py t5 calibrate                      # 背景のぼけの半径（作り直すときだけ。今は 11.5 px）
python docs/pv/thumbnail/blender/compose.py t5 final4k t5_composite final
```

- 書き出しと Blender の本番の描画は、本番画質の撮影と同じく `artifacts/pv_capture/GPU_LOCK` を作ってから。書き出しは 30 秒ほど。
- `render_all_later` は Blender 連携の呼び出しが返ってから順に描く（4K・1024 サンプルの層を続けて描くと連携の待ち時間を超えるため）。
  出力は `artifacts/pv_capture/thumb_<shot>_blender/final4k_<層>.npy`。書き出されるファイルを見て終わりを待つ。

## 書き出し（Godot）で気をつけたこと

- **世界ごと止める**：GameWorld は自分を `PROCESS_MODE_ALWAYS` にしているので、ツリーを止めても物理のほか（粒・プロペラ）が動き続ける。
  書き出しのあいだは GameWorld を `PROCESS_MODE_PAUSABLE` にし、粒の速さも 0 にする（`_freeze_world`）。これで全体の絵は、
  選んだコマ（`thumb_t5_sub8/pv_0063_3.png`）と 54 画素（プロペラの羽根の先）を除いて同じになった。
- **粒**：glTF に入らないので、粒だけの絵（`fx_nodof.png`、アルファつき）を撮る。粒のほかの形は「影だけ」にして撮る（太陽は残すので、
  粒の色と粒に落ちる影は全体の絵と同じ）。前景の後ろに隠れた粒は、`full_nodof` と `full_nofx_nodof` の差が出ない所なので合成で外す。
- **剛体の速度**：脱落した P2 のラグドールの部位と扉の破片は、体の原点の位置・速度と角速度を `scene.json` の `motion` に書く（Blender のモーションブラー用）。

## Blender での組み直し（ゲームの値。`build_scene.py`）

- **カメラ**：ゲームの Camera3D そのまま（縦の画角。Godot の座標 (x, y, z) → Blender (x, −z, y)）。
  ゲームの全体の絵と前景の輪郭を重ねて、ずれ 0 px を確かめた（t2・t5）。
- **2 人と帽子**：色はゲームの値（sRGB → 線形）。Cycles 向けに粗さ 0.55（帽子 0.72）・金属 0、角に半径 12 mm（帽子 6 mm）の丸みの陰影
  （Bevel ノード。形は変えない）。形はゲームの法線のまま（箱は角が立ち、帽子は丸い）。
- **壁と扉**：ゲームと同じ、物体の座標で 3 方向から貼る模様（`wall_panel_*`、9 m × 4.4 m、扉ごとの横のずらしは `scene.json` の値）。法線と粗さ（ORM の G）も。
- **扉の破片**（t5）：ゲームの `_shatter_mesh` と同じ、扉の色を少し白へずらした箱。粗さ 0.55、角に丸みの陰影。
- **看板**：ゲームでは光の当たらない一色（unshaded）なので、光る板にした。影は落とさない（ゲームも cast_shadow オフ）。
- **床**：`conveyor_belt_floor.gdshader` をノードに移した（縞・溝・継ぎ目の線、織り目の画像、汚れ、端の帯。ベルトの送り量は書き出しの `world_scroll_z`）。
  枠とレールは遠くてぼけるので、色と粗さだけ合わせた。
- **文字**：ゲームと同じ書体（Noto Sans JP Regular）。Blender の文字の太らせは角がとがるので、角の丸い縁取りの画像を板に貼る。
  形はゲームの絵を板の正面に直して一字ずつ測った（`make_label_textures.py` の頭）：字の並びは公称のまま、各字は左下を動かさずに
  1.073 倍、縁は 0.1 em、折り返しは Label3D の幅で。t5 の問題文と「54」はゲームの絵とずれ 0〜1 px。
  t2 の「56」はこの前の版（`make_label_texture.py`：並びごと 1.08 倍）で、ゲームより横に 2 px ほど広い。
- **光**：太陽はゲームの向き・色。強さと環境光は、太陽だけ・環境光だけ・空の映り込みだけを描いた絵をゲームの絵に最小二乗で合わせ、
  そこから太陽を少し強めた（太陽 π×1.05×0.70、環境光 ×1.85、空の映り込み 0.98×1.359）。
  ゲームと同じく、拡散光は一様な環境光（0.66, 0.74, 0.92）、映り込みは空のグラデーション（真上 0.08, 0.48, 0.98、地平線 0.64, 0.88, 1.0）。
- **太陽は 1 枚目の壁を通す**（t5）：ゲームの絵では、突き破った扉の奥（P1・破片・床）に壁の影が落ちていない（理由は分からなかった）。
  同じ見え方にするため、太陽の光だけ 1 枚目の壁を通す（影のリンク `LL_sun_blockers`。空の光の遮りと照り返しはそのまま）。
- **吹っ飛ぶ P2 の動き**（t5）：書き出しの速度と角速度で、各部位を 0.1 秒（ゲームの時間）前までさかのぼらせたキーを打つ（回転は 0.4 倍に弱める）。
  P2 の本体はブラーなしでくっきり描き（`VL_chars`）、尾だけを長いモーションブラーで別の層（`VL_p2trail`、シャッターはいまで閉じ、
  開き方はほぼ均一）に描いて、本体の下に重ねる。体ごとぶらすと、ぼやけた写真のようになって形が読めなくなったため。
  P2 の影は本体と同じくくっきり。扉の破片はぶらさない（奥へ飛ぶので、ぶらすと「ピンぼけ」に見えた）。
- **外したもの**（t2）：問題の看板（右上の角が 1 cm ほど切れて写るだけ）と画面の外の「54」。

view layer（`render_layers.py`）:

| 層 | 見えるもの | 穴（holdout） | 影と照り返しだけ |
|---|---|---|---|
| VL_chars | 2 人 | 壁・床 | |
| VL_p2trail（t5） | P2（長いモーションブラー） | P1・壁・床 | |
| VL_wall | 壁・扉・破片・看板・文字の板 | 床 | 2 人 |
| VL_deck | 床・枠・レール | | 2 人・壁 |
| VL_depth | 壁と床の奥行き（材質を差し替え、1 サンプル） | | （2 人は無し） |

## 合成（`compose.py`）

- 色の変換はゲームの Environment と同じ：Godot 4 の ACES（white 6.0、露出 1.0）→ sRGB → コントラスト 1.04。
- 床と壁は奥行きでぼかす：ゲームの被写界深度と同じ決め方（奥行き × 半径の直線）。ぼけきる半径は背景の絵のぼけあり・なしから求めた。
  - t2：14.5 px。扉の「56」（奥行き 12.4 m）をくっきり見せるため、ぼけ始めはゲームの 11.65 m ではなく 12.9 m（幅 10 m）
  - t5：11.5 px（空の雲で求めた）。ぼけ始めはゲームのまま 18.05 m（幅 12 m）
  - どちらも、手前の床（4.5 m より近い所）を最大 3 px だけぼかす（レンズらしさ。ゲームには無い）
- 重ねる順：背景の絵 → 床 → 壁 → P2 の尾（アルファ a を 1 − (1 − a)² に強める）→ 2 人 → 粒。
- 粒（t5）：ゲームの粒だけの絵のアルファと、全体の絵から粒の後ろの色を引いた色（ゲームの見え方のまま）で重ねる。
  全体の絵と粒を隠した絵の差が 1.5 段以下の所（前景の後ろ）は重ねない。粒のまわりの、ゲームの画面上の陰影（SSAO）の変化は使わない。
- 2 人はぼかさない（4K で描いて 1920 に縮めた）。
- 仕上げは `../finish.py` のそのショットの設定と同じ（コントラスト 1.07・彩度 1.12・明るい所を少し暖かく・四隅を 14% 落とす・
  ロゴの下を少しぼかして暗くする・ロゴ。t5 のロゴは幅 740 px・左から 56 px）。輪郭の強調は弱め（4K から縮めたので）、
  8 bit にするとき ±0.5 段のディザ。

## t2

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t2 quality=ultra sub=8 png tag=thumb_t2_export only=65 export=65
（開いている Blender で t2_thumbnail.blend を開き、Text「thumb_render.py」の render_one(0)〜render_one(3) を 1 つずつ）
python docs/pv/thumbnail/blender/make_label_texture.py           # 「56」の板の画像（作り直すときだけ）
python docs/pv/thumbnail/blender/compose.py t2 calibrate         # 背景のぼけの半径（作り直すときだけ。今は 14.5 px）
python docs/pv/thumbnail/blender/compose.py t2 final4k t2_composite final
```

t2 の書き出しは、世界ごと止める前の版（止めたあともプロペラ帽子の羽根だけが少し回る）。`compose.py` は t2 の合成を前と同じ値で出す（差 0）。

## t7（絵コンテ `gen/t2_side.png` の再現、2026-10-23）

絵コンテ（Codex の案。真横の並走、右の端に壁）を、ゲームの寸法のまま再現した版。カメラは線路に真横（2 人の 62 m 横・床から 2.1 m・
縦の画角 7.7° の超望遠）で、位置・高さ・画角は絵コンテの 2 人の足と頭・地平線・床の奥の縁・壁の端と扉の位置から求めた。
壁は回さない（ゲームの向きのまま。真横から見えるとおりに扉が細く写る）。

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t7 quality=ultra sub=8 png tag=thumb_t7_export only=71 export=71
（開いている Blender で）ns = {}; exec(open(r"...uild_scene.py", encoding="utf-8").read(), ns); ns["build"]("t7")
（開いている Blender で）ns2 = {}; exec(bpy.data.texts["thumb_render.py"].as_string(), ns2); ns2["render_all_later"]()
python docs/pv/thumbnail/blender/compose.py t7 final4k t7_composite final
```

撮影（`pv_thumb_runtime.gd` の `SHOTS["t7"]`）で絵コンテに寄せたこと:

- 背景の置き直し：手前の観客席（カメラの後ろ）とサメを隠す。奥の観客席は 130 m 遠ざけ、z が 35 より手前のブロックを観客ごと隠す
  （左は海、右に観客）。高層ビル（`AQS_BG_City`）と岩の島（`AQS_BG_IslandRocky`）を真横から見える所へ回して置く。壁の文字は透明に
  （絵コンテは文字なし。問題の看板の板は残す）。
- 雲（`clouds`）：ゲームの空（ProceduralSky）は雲なし。オンライン演出の積雲の板（`online_staging_cloud.gdshader`）を、画面の位置で決めて
  カメラから 4.4〜4.9 km 先（カメラの描画の限り 5 km の手前、高層ビルより奥）に 46 枚並べる。
- 走りの姿（`sprint`）：ゲームの走り（Run.fbx）は上体がまっすぐで歩幅も小さい。ゲームのリザルトの歩きと同じしくみ
  （`AnimationRig.seek_ual_clip` と `PlayerController._apply_skeleton_pose`）で、UAL の全力疾走 `Sprint_Loop` の、後ろ足をまっすぐ
  後ろへ伸ばし前の膝を前へ出した瞬間（P1 は位相 0.33、P2 は反対の足の 0.83）に置き換える。位相は `sprint=Sprint_Loop,0,0.5,0.0303`
  （フレームごとに位相を進める）で総なめして選んだ。
- 71 フレーム目（P2 は 2.84 m 前、壁は P1 の 5.75 m 先）を書き出す。

Blender（`build_scene.py` の `ART["t7"]`）で足した演出:

| 名前 | 中身 |
|---|---|
| `deck_widen` 12 m | 真横から遠くで撮ると床（幅 24 m）は細い帯になり、下にコンベアの側面が大きく写る。床を手前へ 12 m 広げ、手前の側面とレールをその分外へ（床の模様は伸ばして端の帯を新しい端へ） |
| `pose` | 2 人をカメラのほうへ 30° 振り向かせ（3/4 の向きで胸と両腕が見える。足の運びの縮みは 0.87 倍）、全力疾走の強い前のめり（約 30°）を 10° 起こし、1.13 倍に（絵コンテの人の背丈は扉の 0.68 倍、ゲームは 0.60 倍）。いちばん低い所はもとの高さに合わせ直す |
| `hat_tilt` P2 18° | 魔法使いの帽子を走る勢いでうしろへ傾ける |
| `dust` | うしろ足の下から後ろへ 1.1〜1.2 m、角ばった白い土ぼこり（low-poly の球）を小山に盛る（足もとが高さ 0.64〜0.72 m でいちばん高い）。細かい粒も上へ |

合成（`compose.py` の `SHOTS["t7"]`）：背景はゲームの背景だけの絵（`plate_nodof`）を円で 6.5 px ぼかし（絵コンテの強いぼけに寄せる）、流し撮りのように横へ 24 px
流す（55 %）。色（`plate_look`）は彩度 1.35、空は地平線より上ほど深い青へ（青みの強い所だけ。雲や建物はそのまま）、海（`sea`）は
地平線の明るい水色から手前の深い青へ塗り直し、波の明暗を 2.2 乗で強める。最後に 2 人のうしろへスピード線。
ロゴは幅 700 px・左から 60 px（P1 のうしろの土ぼこりが画面の 0.42 から始まるので、その手前で止める）。

## t8（絵コンテ `gen_v2/a_shoulder.png` の肩タックル、2026-10-31）

ゲーム内撮影版（`final/t8.jpg`）はポーズが弱かったので、Blender でポーズを付け直し、絵コンテどおりに仕上げた版。
できあがり：`../final/t8_blender.png`・`.jpg`。Blender のファイル：`t8_thumbnail.blend`（`build_scene.py` の build("t8") ＋ `t8_art.py`）。

- 画角：絵コンテの目立つ点（帽子のてっぺん・腰・足もと・奥の赤い扉・壁の線の消える所）の画面の位置に合うカメラを計算で求めた
  （壁の中心・床から目 (3.48, 1.0, 2.73)、注視点 (−6.04, 2.23, −0.06)、縦 101.8°）。ゲームの壁は短いので、赤い扉を遠く小さく見せる
  絵コンテの遠近感は広角でしか出ない。Blender では縦 90° にズームし（`blender_art.json` の fov）、背景のゲームの絵も合成で同じ倍率
  （tan(101.8°/2) / tan(90°/2) = 1.23）に拡大する（背景は遠いので、位置を変えずにズームしたのと同じになる）。
- 書き出し（Godot）：`pv_thumb_runtime.gd` の `export=76`。`stage=res://docs/pv/thumbnail/t8/stage_export.json`（ゲームの破片を隠し、
  演出用の破片を出さず、P1 は全力疾走 Sprint_Loop 0.33 の姿）と、上の `cam=`。書き出しに **関節**（`scene.json` の `joints`：
  PlayerController の parts のノードの位置と向き・道筋・親）を足した。`apply_pose` は `lib: "ual2"` で UAL2 のクリップも使える。
- ポーズ：Codex の画像生成で、絵コンテの P1 と同じ姿を 3 方向（絵コンテの斜め前・真横・真正面）から描いた参考図を作り
  （`../gen_v2/pose/pose_sheet.png`、プロンプトは同じフォルダ）、Blender の同じ 3 方向の絵と並べて合わせた。
  - 試してやめたもの：数値で関節を順に回す（全力疾走の前傾と重なって崩れる）、腕をカメラへ真っすぐ向ける（短い突起に見える）、
    UAL2 の Shield_Dash（肩から当たる横向きの姿で、正面寄りのカメラでは脚が横に開いて身構えた形に見える）。
  - P1 は扉の穴の中まで下げた（カメラから 2.1 m。近いと、カメラへ向く手足が大きく写って崩れる）。体はカメラへ 35° 向け（turn）、
    腰ごと 24° 前へ倒し（lean）、手前の右腕は前腕を斜めに立てて顔の前を守り、奥の左腕はこぶしをお腹の前へ、左ももを前へ、右脚は後ろへ。
- Blender（`t8_art.py`。値は `../t8/blender_art.json`。書き換えて `setup()` を呼び直すと当て直す）:
  - `rig()`：関節を空の物体 `RIG_P1_<名前>` にし、部位をいちばん近い関節の子にする（49 関節・47 部位）。部品名の l_ は体の右。
  - `pose()`：書き出しの姿に戻してから、体ごと向きを変え（turn）・倒し（lean）・動かし（move）、部分（関節 → 次の関節）を
    体の右・前・上で書いた向きへ向ける（aim。"cam" はカメラへ）。`fist()` で指を手のひら側へ曲げて握りこぶしに。
    `ground` で、いちばん低い所を床に合わせる。
  - `zoom()`：ズーム。`debris()`：扉の青（quiz_wall.gd の DOOR_COLORS_2[0]）の箱。画面の位置とカメラからの距離で置く（回転もカメラから見た
    向き）大きな板 7 枚・箱 9 個・欠片と、扉の穴の縁の割れ残り（壁基準）。扉の穴の真ん中から外へ飛ぶ速さで、1 フレーム前からのキー
    （モーションブラー。0.02 秒）。`dust()`：少し透ける白い煙。`lens()`：ピントは P1 の胸、絞り 2.0。
  - `layer()`：全部をいっしょに描く VL_t8（2 人目・文字の板は外す）。描画データの持ち越し（persistent data）は切る。
  - `preview()`・`preview_views()`：確かめ用の速い絵（正面・真横・本番の画角）。
- 描画：`render_layers.py` の **`render_async("VL_t8", tag="final1080", res=(1920, 1080), samples=384)`**。
  - **Blender が落ちないように**：`render_one`・`render_all_later` は描き終わるまで Blender の画面を止めるので、長い描画では Windows に
    「応答なし」として閉じられた（1080p・512 サンプル）。`render_async` は Blender のふつうのレンダリング（INVOKE）で裏で描き、
    描いているあいだも画面が動く。終わったらタイマーで EXR を .npy に直して `<tag>_VL_t8_done.txt` を書く。
  - また、描画データを持ち越したまま描いたあとに破片を作り直すと Blender が落ちたので、持ち越しは使わない。
- 合成：`compose.py t8 final1080 final`（`SHOTS["t8"]`：VL_t8 をゲームと同じ色の変換で、ズームに合わせて拡大したゲームの背景の絵
  plate_dof に重ねる）。仕上げとロゴは `../finish.py` の t8 の設定。

### ポーズを手で変える（骨とパネル）

- `t8_art.py` の `armature()` で、関節の空の物体を Blender のふつうのアーマチュア **ARM_P1**（骨 49 本）に置き換えた（`setup()` の中で
  aim のポーズを付けたあと）。骨の休みの姿は書き出しの姿（全力疾走）。部位は骨の子で、クリックで骨を選べるよう部位は選べないようにしてある。
- パネル：`t8_panel_addon.py`（Blender のアドオン「AIQUIZ Thumbnail t8」。3D ビューで N → **Thumb** タブ）。
  1. **ポーズを編集**：ARM_P1 を選んでポーズモードに。骨をクリックして **R**（回す。R X / R Y / R Z で軸を決める。数字を打てばその角度）。
     **Alt+R** でその骨を書き出しの姿に戻す。Ctrl+Z で取り消し。
  2. **ポーズを保存**：いまの骨の姿を `../t8/blender_art.json` の `bone_pose` に書き、.blend も保存する（組み直したときも、この姿が当たる）。
  3. **保存した姿に戻す**：`bone_pose` を当て直す。
  4. **確認の絵**：1920×1080・24 サンプル（約 50 秒）で描いて合成し、`out/t8_prev_ui.png` を開く。
  5. **本番を描く**：1920×1080・384 サンプル（約 12 分）で描いて仕上げ、`../final/t8_blender.jpg` を開く。
  描画はどちらも `render_async`（Blender の画面は止まらない）。合成はこの PC の Python（numpy・Pillow）で `compose.py` を動かす。
- 注意：Higgsfield の Blender 連携は、Blender のメインの窓を最小化しているあいだ命令を受け付けない（2026-10-31。窓を戻すと動いた）。
- カメラ CAM_main は位置と回転をロックしてある（ポーズを付けているうちにカメラが動いてしまったため。戻すときは書き出しの scene.json の camera）。
- `blender_art.json` の `hide_fingers`（["l"]）：画面の左に構えた手（体の右）の指を描かず、手のひらの箱だけのこぶしにする（`hide_fingers()`）。

### ほかの PC で作業する（メインPC など）

- スクリプト（`build_scene.py`・`render_layers.py`・`t8_panel_addon.py`）は、開いている .blend から上へたどって `project.godot` のある
  フォルダをプロジェクトとする（無ければ環境変数 `AIQUIZ_ROOT`、`C:\AIQUIZ\AIQUIZ-Godot`、`G:\AIQUIZ-Main\AIQUIZ-Godot`、
  `~\Desktop\AIQUIZ\AIQUIZ-Godot` の順）。`compose.py` は自分の場所から。
- Godot の書き出し（`artifacts/` は git に入らない）は、t8 の分だけ `../t8/export/`（scene.json・plate_dof.png・foreground.glb）に写してあり、
  `artifacts` に無いときはそちらを使う。
- メインPC での手順：git で取り込んだあと、Blender で `docs/pv/thumbnail/blender/t8_thumbnail.blend` を開き、パネルのアドオン
  `t8_panel_addon.py` を入れる（編集 → プリファレンス → アドオン → ディスクからインストール、または Higgsfield 連携の bl_install_py_addon）。
  合成には、その PC の Python に numpy と Pillow が要る。
