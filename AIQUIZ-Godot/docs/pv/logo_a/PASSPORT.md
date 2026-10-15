# ロゴ案 A（破片が集まってロゴに）— A2 の 1 枚テスト

絵コンテ `docs/pv/storyboard_s01_s03_v2/`（コマ A2）を、本物の素材でどこまで再現できるかを確かめる 1 枚。
背景は Godot の実機（PV 撮影 `tests/pv_capture` をロゴ用の低いカメラ `logo_cam=0,-0.7,8.5,0,3.2,-10.0,58` で撮ったフレーム 430）、ロゴと床の破片は Blender、光は After Effects。

改訂 2：ロゴを大小のブロック（3×3・2×2 マスをまとめた大きな立方体＋輪郭の小さい粒）に、閃光を強く（芯・光線 48 本・光の筋 54 本・輪）、背景を見上げる構図に撮り直し、床に小さな破片を置いた（床は影だけを受ける面。光は床を照らさないのでロゴの影は落ちない）。
AE の注意：この PC の AE 2026 は 1 回書き出すと次の書き出しが失敗する。書き出し直すときは AE を再起動してから。

```text
SCENE
- intent: PV 冒頭のロゴ案 A の完成の瞬間（A2）を、実機の背景に Blender の立体ロゴを重ねて作り、イメージ画像と質を比べる
- deliverable: docs/pv/logo_a/render/logo_a2_rgba.png（ロゴだけ・透過）→ AE で合成した 1 枚
- units: metres; axes: right-handed Z-up（Godot (x, y, z) → Blender (x, -z, y)）
- render: Cycles, 1920x1080, 24 fps, frame 1（破片の動きのブレのためにフレーム 0〜2 にキー）
- dynamic: 今回は静止画のテスト（ユーザーが「A2 の 1 枚」を指定）。飛び込む破片だけ動きのブレ用に動かす

HIERARCHY
- collection PV_LogoA: LOGO_shards（ロゴの立方体を 1 つのメッシュに）、FRAG_arrive_*（飛び込む途中の破片）、
  FRAG_float_*（宙の破片）、FRAG_near_*（カメラの近くのぼけた破片）、CAM_godot_match、LGT_sun、LGT_key_front、LGT_flash_back
- protected existing objects: なし（新しいファイル）

ASSETS
- A01 LOGO_shards | BLOCK | detailed | 13.1 x 0.33 x 3.1 m（横 120 マス・3 層、1 マス 0.109 m） | center Godot (3.53, 4.02, 21.0) | 立てて横だけカメラへ向け、上を 6° 奥へ倒す | hero
- A02 FRAG_arrive_* (14) | BLOCK | detailed | 一辺 0.15 m | ロゴの空きマスへ向かう途中 | secondary
- A03 FRAG_float_* (30) | BLOCK | stylized | 0.12–0.35 m | ロゴのまわりの空 | support
- A04 FRAG_near_* (5) | BLOCK | stylized | 0.35–0.6 m | カメラから 1.5–3 m の画面の端（ぼける） | foreground

SHOT
- active camera: CAM_godot_match（PV 撮影のフレーム 450 と同じ）
- eye Godot (3.53, 0.9, 31.773) / target (3.53, 1.2, 26.0) / 縦の画角 53.702°（ゲームのカメラは縦で合わせる）
- 確かめた値: ドアの上端（y=2.38、z≈16.63）が画面の y≈491 px、P1 の足元（床 −1.2、z=26）が y≈992 px に来る（実機の画とも一致）
- ロゴは画面の上寄り（横 68%、中心 y≈290 px）。P1 の頭（y≈540）より上

LOOK
- LOGO_shards: 艶のある青（ドアの青に合わせる）、コートで強い映り込み、立方体ごとに少し明るさを変える（ゲームの破片と同じく白へ 0〜20%）
- 角の面取りと、縁が光る弱い発光（斜めの面ほど光る）
- world: 青空のグラデーション（映り込みとまわりの光だけ。背景は透過）

LIGHTING
- 主役: ロゴ。次: 踊る P1（背景の実機の画）
- 太陽 LGT_sun: 実機と同じく壁の向こう・右上から（P1 の影がカメラ側・少し左に落ちている）
- LGT_key_front: カメラの上の大きな面光源。ロゴの正面を読ませる（スタジアムの照明のつもり）
- LGT_flash_back: ロゴの真ん中の後ろの強い点光源。完成の閃光（AE の白い光と同じ位置）が立方体の縁と隙間を照らす
- world: 上は青空、下（床）は暗い灰色。立方体の底の面を濃くして立体に見せる
- 色の管理: Standard（AgX だと青が淡くなり、実機の画の鮮やかさに届かなかった）、露出は固定

MOTION
- FRAG_arrive_* だけフレーム 0→2 で空きマスへ 1.6 m 進む（フレーム 1 を動きのブレ付きで描く）

ACCEPTANCE
- 構図: 背景の実機の画（カメラの位置・画角）とロゴの遠近が合う。ロゴが P1 の頭にかからない
- 見た目: 「AIQUIZ」が読める（I の斜めの線と Q の尾）。立方体の粒が見え、艶と縁の光がある
- 比較: AE で合成した 1 枚を、絵コンテの A2 と並べて見る
```
