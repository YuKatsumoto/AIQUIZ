# AIQUIZ STADIUM 参照画像のプロンプト記録

原本 v1（`master/aiquiz_stadium_master_v1.png`、job `b34835af-abae-42bc-babe-dcac08d266ec`）から、
Blender 精密制作用の参照画像をそろえた記録。各画像の採否・sha256・画素寸法は `generation_record.json`。

- モデル: `nano_banana_pro`（ジョブ上の表記 `nano_banana_2`）、2K、1枚 2 クレジット。Starter プランは同時実行 2 件まで
- 参照画像の順序ルール（CP1 で確認）: **位置ガイド／下敷きを1枚目、デザイン参照を2枚目以降** にするとカメラと寸法がほぼ固定される。原本を1枚目にすると原本の構図に引っぱられる
- 位置ガイド・下敷きは `guides/make_guides.py` と `guides/make_underlays.py` がゲーム定数から描く（Higgsfield media id は下表）

| 下絵 | media id |
| --- | --- |
| guides/guide_2p_clean.png | `920af245-9877-4e57-bacb-0c1583eebde6` |
| guides/guide_1p_clean.png | `6b694132-a9b0-4d23-a9f8-17aadc3b2a37` |
| guides/guide_preload_clean.png | `969720fe-7bc2-4b41-b343-351ebb16e12c` |
| guides/underlay_P01_stand_anchor.png | `a0da3474-9269-431e-9ed6-796f1b40c125` |
| guides/underlay_P04_runway_anchor.png | `1047e8c0-cb80-4d45-bd4c-614c487e504e` |
| guides/underlay_P06_gate_anchor.png | `7aa43c78-74fb-4f92-bff9-c27caba93ff9` |
| guides/underlay_P07_goal_stand_anchor.png | `07ee08c9-163f-45d0-8da2-e484faedd4df` |

## CP1 カメラ固定ビュー

### V01a（1P カメラ、原本→ガイドの順）／ V01b（2P カメラ、同）

```
Image 1 is the design master of AIQUIZ STADIUM: copy its architecture, materials, colors and mood exactly (white planked pier runway on slim square white piles, white pier grandstands on piles with stepped seating, white rounded booths with blue panels, wooden masts with white triangular sail canopies, turquoise tropical sea, green islands, a faint hazy futuristic skyline on the left horizon, a white lighthouse carrying the AIQUIZ STADIUM sign).

Image 2 is a camera and layout guide rendered from the real game camera (<1P: third-person camera 3 m above the runway / 2P: two-player camera 5.7 m above the runway>, 50 degree vertical field of view). Keep its exact camera position, lens, horizon height and perspective, and keep every position and width exactly: ... Replace the flat guide shapes with the finished stylized 3D design from image 1. ...

Follow these changes from image 1: the grandstand on the LEFT side of the picture holds the orange team crowd (orange shirts), the grandstand on the RIGHT holds the blue team crowd; the runway edge has only a very low blue curb, no tall handrail; each 20 m grandstand block has one aisle staircase, one booth and one mast with one sail; the grey slab in image 2 is the colorful quiz wall with four doorways as in image 1, with blank panels and no text; the lighthouse stands on a small rocky islet far out at sea at the end of the axis.

Style: stylized 3D video game render, clean chunky low-poly shapes, bright midday sun, same palette as image 1. No UI, no watermark.
```

### V01b ガイド先行版（ガイド→原本の順）

```
Image 1 is an exact camera-and-layout render from the game engine (two-player camera 5.7 m above a 24 m wide runway, 50 degree vertical field of view). Edit image 1: keep its camera, horizon height, perspective and every edge, position and width exactly — ... Only replace the flat untextured shapes with finished surfaces, materials and details copied from image 2, the AIQUIZ STADIUM design master: ...
Exactly one lighthouse, the small one on the horizon at the center, carrying a navy sign; do not add a second lighthouse. ...
```

## CP2 部位アンカー（下敷き→V01a→原本 の順）

共通の末尾:

```
Composition: design-sheet product render, plain flat light-grey background #D8D8D8, no sky, no sea texture (the water is only the flat grey plane), no people except the single scale figure ...
Lighting: soft uniform overcast studio light, no cast shadows.
Constraints: no text, no numbers, no logos, no watermark; chunky low-poly game asset with flat-colored faces, nothing thinner than 8 cm; palette white #ECE9E2, cobalt #2F5FA8, ...
```

- P01 観客席 2ブロック: 「Image 1 is an exact blockout render of the part: two identical 20-metre grandstand blocks ... six stepped seating rows, one aisle staircase at the joint between the two blocks, and per block exactly one booth, one wooden mast and one triangular sail ...」座席は無人の白いバケットシート、ブースの青パネルは走路側
- P04 走路 1スパン: 「one 20-metre span of the 24-metre-wide runway pier ... a white deck made of slats running across the runway, a very low curb only about 25 cm high with a cobalt-blue top ... grey steel side frame ... piles grouped in cross-bents every 10 m」
- P02 マスト・帆・ブース（P01 アンカー r2 のみ参照）、P03 端部（同）、P05 灯台（下敷き＋原本の灯台の切り抜き＋P04 アンカー）、P06 ゲート（下敷き＋P04 アンカー）、P07 ゴール観客席 A 案「帆のパビリオン」／B 案「港の操舵室」（下敷き＋P01 r2＋P04）、P08 背景の帯 3 枚（原本の切り抜きシート＋合格済みアンカーを画風参照）
- 不採用と対策（詳細は generation_record.json）:
  - P01 1回目：座席 4 列・カメラが正面寄り → 「EXACTLY SIX rows (count them)」「keep the camera of image 1」で再生成
  - P06 1回目・P05 1回目・P08 ビル群 1回目：原本（全景）を参照に入れると背景ごと混入 → **原本は切り抜きにして渡し、画風は合格済みの無地背景の画像で渡す**

## CP3 正投影・追加ビュー

正投影の書き方（効いたもの）: 「Flat architectural orthographic ... Pure parallel projection at eye level: nothing is seen from above, no vanishing points, all verticals perfectly vertical」＋「drawn in exactly the same flat orthographic style as image 2（合格済みの正投影図）」

- **3/4 のアンカーを正投影の参照に入れない**。入れると斜め投影になる（X01 1回目）か、アンカーと下敷きが重なった合成画像になる（P06 1回目）
- 画像 1 に下敷き（make_underlays.py の ortho_views、縮尺 px/m は generation_record.json の refs に記載）、画像 2 に合格済みの正投影図
- 下敷きの縮尺がそのまま保たれたのは P01 走路側立面だけ（水線の誤差 0.07m）。他の図は縦横が歪むことがあるので、寸法は measure/ で検算してから使う

| ID | 内容 | 結果 |
| --- | --- | --- |
| X01 | 全幅の横断面 | r2 で正投影になったが段数が増えた（配置の比較用） |
| P01 | 走路側の立面 / 端面 / 真上 | 立面は寸法の実測に使用、端面は縦横の縮尺差 22.9% で形の参考のみ |
| P04 | 走路の断面 | 杭の組と X 筋交い |
| P05 | 灯台 正面 | 比率の実測に使用 |
| P06 | ゲート 正面 | r2 は意匠のみ（柱の位置・高さが下敷きと違う） |
| P07 | ゴール観客席 B 正面 | 左右対称・中央の掲示板 |
| P09 | 細部 6 種 | 縁石が 1m の壁に描かれた点は不採用 |
| V04 / V06 | ゴール手前 2P 視点 / 水路から | 見た目の参考（カメラは実機より高め）。V04 で軸上の灯台がゴール観客席に隠れると判明 |
| V01 夕暮れ / 夜 | V01a（1P 視点）を参照に時間帯だけ変更 | 光る部位の一覧に使用。V01b ではなく、見た目が合格した V01a を元にした |

合計 33 枚・実費 66 クレジット（残高の差 248.75 → 182.75）。
