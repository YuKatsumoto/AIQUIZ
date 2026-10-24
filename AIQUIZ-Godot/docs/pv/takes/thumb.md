# 応募用サムネイルの撮影（2026-10-22）

応募の条件は 16:9・2MB 以下・JPG か PNG（1920×1080 推奨）。タイトルロゴだけを左の真ん中に置き、右側でコンベアの上の 2 人が
競り合う。絵コンテは `docs/pv/thumbnail/`（Codex CLI の画像生成で作った 6 案のうち t2・t3 を実機で撮った）。

- 台本：`tests/pv_capture/pv_thumb_runtime.gd`（`pv_take_base.gd` の上）。起動は `pv_take_bootstrap.gd -- take=thumb shot=t2|t3`。
- 仕上げ：`docs/pv/thumbnail/finish.py`（動きのブレの重ね・色・ロゴの下を落ち着かせる・ロゴ）。
- できあがり：`docs/pv/thumbnail/final/t2.jpg`・`t3.jpg`（1920×1080、約 0.4 MB）と同じ名前の PNG。並べたものは `_final.jpg`、
  小さく表示したときの確認は `_small_check.jpg`、撮れたコマの一覧は `_frames_t2.jpg`・`_frames_t3.jpg`。

## 中身

本物の GameWorld（ローカル 2P・10 問・PLAYING）を、本物のキーイベントで動かす。問題は PV と同じ「【かけ算】7 × 8 ＝ ？」
（青「56」が正解・+x、赤「54」・−x）。見た目は PV と同じ（P1 プロペラ帽子、P2 キツネ帽子）。昼の位相 0.25。HUD は出さない。
チップソーは 80 m 後ろに置いて追い始めの猶予の中に留め、ノードも隠す。2 人は撮る前の 30 フレームから走っていて、P2 は 7 フレーム
遅れて走り出す（2 人の足の位相をずらす）。

| | t2（真横の並走） | t3（背中越しに壁へ） |
|---|---|---|
| カメラ（中点から） | 目 (−8.5, 0.8, −1.6)・注視点 (1.47, 0.95, −0.87)・縦 30° | 目 (−0.7, 3.5, −4.3)・注視点 (4.9, −1.2, 8.6)・縦 58° |
| 背景のぼけ | 2 人より 3 m 奥から 10 m で、量 0.4（壁の「56」はぼかさない） | 14 m 奥から 40 m で、量 0.08 |
| レーン・前後 | P1 −0.6（手前）、P2 +0.6 が 1.5 m 前 | P1 +0.55、P2 −0.55 が 0.4 m 後ろ |
| 押し合い | しない | 8 フレームから相手のほうへ押して踏ん張る。44 で P2 が一押し（肩の線と土ぼこり） |
| 壁 | 撮り始めに 16 m 先（65 で約 4 m） | 30 m 先 |
| 使ったコマ | 65（2 人とも大きく足を開いたところ） | 48（肩がぶつかる線がいちばんはっきり出たところ） |
| 重ねる回数 | 1（止めた絵） | 2 |

- sub=8 の 4 回を全部重ねると、カメラと逆向きに動く壁（t2 の「56」）が 4 重に見えた。t2 は 1 回、t3 は 2 回だけ重ねる。
- t3 の 46 は一押しの予備動作の途中で、重ねると二重写りになるので使わない。
- 仕上げ：コントラスト 1.07・彩度 1.12、明るいところを少し暖かく、四隅を 14% 落とす。ロゴの下（t2 は左 55%、t3 は 49% まで）を
  少しぼかして暗くする（t3 は観客席とガラスの柵が細かいので強め）。ロゴは幅 820 px、左から 70 px、上下の真ん中。

## 撮り方

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t3 quality=low tag=chk_thumb_t3 only=40,48,50,63
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t2 quality=ultra sub=8 png tag=thumb_t2_sub8 only=56,58,60,62,63,64,65,66,68
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t3 quality=ultra sub=8 png tag=thumb_t3_sub8 only=40,44,47,48,49,50,51,52,58,63
python docs/pv/thumbnail/finish.py sheet      # コマ選び
python docs/pv/thumbnail/finish.py            # 仕上げ（コマを変えるときは t2=64 t3=50 のように渡す）
```

- 本番画質の撮影は `artifacts/pv_capture/GPU_LOCK` を作ってから走らせ、終わったら消す。かかった時間は t2 が 42 秒、t3 が 46 秒。
- 構図を試す引数：`cam=ex,ey,ez,tx,ty,tz,fov`・`dof=先,幅,量`・`wall=`・`lag=`・`lanes=`・`brace=`・`shove=`・`shover=`・`day=`（台本の頭に説明）。

## t2 の Blender 版（2026-10-23）

t2 は、65 フレーム目のゲームの状態（2 人のポーズ・帽子・壁・床・カメラ・光）を書き出して Blender（Cycles）で描き直し、
ゲームで撮った背景（前景を隠した絵）に重ねた版を作った：`docs/pv/thumbnail/final/t2_blender.png`（応募にはこれを使う）。
書き出しは `pv_thumb_runtime.gd` の `export=65`、組み直し・描画・合成の手順と値は `docs/pv/thumbnail/blender/README.md`。

## t5（壁を突き破る瞬間の明暗、2026-10-23）

P1 は青「56」（正解）を突き破り、P2（ハート 1）は赤「54」に激突して脱落し、後ろへ吹き飛ぶ。カメラは P1 の側のうしろ・低め。
左は壁の無地（ロゴの下）、上に空、中央に問題の看板。

- 構図：`shot=t5`（`SHOTS` の t5。壁といっしょに動くカメラ、突破の少し前の 34 フレームから時間を 0.35 倍、突破した壁を残す
  `keep_wall`、通過で消えた問題の看板と割れていない扉の答えを出したままにする `keep_labels`）。P2 の脱落は 40、P1 の通過は 45 フレーム目。
- ゲーム内撮影版：63 フレーム目（`thumb_t5_sub8`）、重ねる回数 1。ロゴは一回り小さく（幅 740 px、左から 56 px。青い扉の入り口の手前で止める）。
  → `docs/pv/thumbnail/final/t5.png`
- Blender 版：63 フレーム目を書き出して描き直した（`export=63`）。吹っ飛ぶ P2 には、本体はくっきりのまま、扉から跳ね返された
  道のりに残像の尾（モーションブラー）を付けた。→ `docs/pv/thumbnail/final/t5_blender.png`。手順と値は `docs/pv/thumbnail/blender/README.md`。

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t5 quality=ultra sub=8 png tag=thumb_t5_sub8 frames=74 only=56,58,60,62,63,64,65,66,68,70,72
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t5 quality=ultra sub=8 png tag=thumb_t5_export only=63 export=63
python docs/pv/thumbnail/finish.py t2=65 t3=48 t5=63
```

- 低画質（`quality=low`）と ultra では物理の結果が変わる（粒の数で乱数の消費が変わる）。構図は `quality=low sub=8` で探し、
  コマは ultra で選ぶ（ultra どうしなら同じ結果になる）。
- 書き出しでは、GameWorld が自分を `PROCESS_MODE_ALWAYS` にしているため、ツリーを止めても粒が動き続けた。書き出しのあいだは
  GameWorld ごと止める（`_freeze_world`）。

## t7（絵コンテ gen/t2_side.png の再現、2026-10-23）

Codex の絵コンテ `docs/pv/thumbnail/gen/t2_side.png`（真横の並走。P1 はキリン、P2 は魔法使いの帽子。右の端に壁）を、真横のカメラと
ゲームの向きのままの壁で再現した（はじめに斜めのカメラと壁を回して合わせた版は、構図が違い不自然なので作り直した）。
Blender 版だけ（ゲーム内撮影版はなし）：`docs/pv/thumbnail/final/t7_blender.png`。撮影で寄せたこと（背景の置き直し・雲・
全力疾走の姿）と Blender の演出・合成の値は `docs/pv/thumbnail/blender/README.md` の「t7」。

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumb shot=t7 quality=ultra sub=8 png tag=thumb_t7_export only=71 export=71
```
