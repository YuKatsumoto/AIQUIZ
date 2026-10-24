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
