# Scene Passport — AIQUIZ ONLINE HELIPORT（オンライン対戦メニューの 3D 背景、v2：パッド 1 つ）

v1（パッド 2 つ＋管制塔＋ハブ＋渡り廊下）から、マッチング演出（`docs/online_match_staging/spec.md`）に合わせて
パッド 1 つに作り直した（2026-10-11、計画書 M1）。

SCENE
- intent: オンライン対戦の専用メニュー（`ui/online_menu.tscn`）の背景。港の沖に立つ海上ヘリポート。
  パッドの上に乗り込めるヘリ（`assets/vehicles/helicopter_boarding/`）が止まり、プレイヤーが左のドアから乗り込んで飛び立つ
- deliverable: `online_heliport.blend`（このフォルダ）、`assets/online_heliport/online_heliport.glb`（書き出し部品）、
  `online_heliport_layout.json`（パッド・ヘリの置き場所と向き・待つ位置・吹き流しと旗の軸・街・確認用のカメラ）、
  確認レンダー（`source/previews`、`artifacts/online_heliport/blender`）、`source/build_report.json`
- units: metres; axes: right-handed Z-up。Blender (x, y, z) = g2b(Godot x, y, z) = (x, -z, y)
- ヘリの座標（H）：原点＝ヘリの接地点、+x＝機体の右、+y＝上、-z＝機首。`h2g` でワールドへ（ヘリの向き -90°：機首が +X）
- render（確認用）: EEVEE, 1600x900, Standard の色変換
- dynamic: yes — 確認用に吹き流しの揺れ。ゲームでは Godot の演出の監督（`OnlineStagingDirector`）が動かす
- build: ユーザーのライブ Blender で `build_online_heliport.py` を runpy で実行（Higgsfield の `bl_execute`）。ヘッドレスで代替しない。
  終わったら `.blend` を保存する（AGENTS.md）
- construction_mode: 手続きの作り込み（すべてローカル。3D 生成・クレジットは使わない）

HIERARCHY
- 書き出し: コレクション `OHP_EXPORT`
  - `OHP_Pad`（床・縁・桁・中央の柱・斜めの支柱・安全ネット）、`OHP_Pad_Lamps`（縁の灯 16 個、UV2.x = 灯の番号/16）
  - `OHP_Props`（吹き流しの柱・旗の竿 2 本・投光器・消火砲 2・機器箱 2・救命浮輪の掛け台 4）
  - `OHP_Windsock`（原点＝支点、Godot が揺らす）、`OHP_FlagA` / `OHP_FlagB`（UV2.x = 揺れの重み）
- 確認用（書き出さない）: `REF_Sea`、`REF_Heli`（乗り込めるヘリ）、`REF_PlayerMe`（待つ位置）、`REF_City`、`CAM_*`、`LGT_Sun`

ASSETS（Godot 座標。デッキ上面 y = -1.2、海面 y = -9.2、パッドの中心が原点）
- A01 パッド | 八角形 対辺 18.0m（ローターの直径 10.6m の 1.7 倍）、板厚 0.30 | 桁 8 本＋外周・内周の輪、中央の柱（半径 1.6、
  海の下 8m まで）、斜めの支柱 8 本、外周に 1.5m の安全ネット棚、縁の灯 16 個 | hero
- A02 床の標示 | 画像 `ohp_pad_deck.png`（2048²） | 外周の白線、黄色の接地円（半径 4.4、幅 0.6）、白い H（足は機体の前後にそろえる）
- A03 小物 | 位置はヘリの座標（`ohp_common.H_*`）で決める。どれもローターの円（中心から 5.8m）の外、縁の内側
- 風下：Blender の Z 回り -60°（吹き流しはパッドの外へ流れる）

SHOT（演出の定数 `online_staging_timeline.gd` の `CAMERAS` を、パッドの上のヘリの座標で置いたもの）
- CAM_Idle（待機）・CAM_Board（乗り込み）・CAM_Cockpit（操縦席の正面）・CAM_PadLow（パッドのふちから見上げる）・CAM_Overview（確認用）

LIGHTING（確認用）
- key: ゲームの太陽（WeatherCycle の向き：Godot で (0.285, 0.866, -0.411) の方、仰角 60°）。待機のカメラの後ろから当たる
- world: 青い空のグラデーション、露出 0、Standard

ACCEPTANCE（`build_report.json` の checks）
- structural: 名前が一意。床の上面が y = -1.2。背の高い物（吹き流し・旗・投光器、先端まで）がローターの円と尾のフェネストロンに当たらない
  （ローターの半径と尾の位置・大きさは `ohp_common.py` がヘリの layout の `main_rotor.radius`・`tail_rotor.pivot`・`shroud_radius` から読む。
  2026-10-11 にヘリの尾をフェネストロンにしたあと、式だけで確かめた。このヘリポートは作り直していない）。
  低い小物がデッキの上でローターの円の外。待つ位置がデッキの上。三角形の合計 ≤ 30k（実測 5,488）。材質は表のものだけ。画像はすべて解決。縁の灯 16
- visual: CAM_Idle の確認レンダーで、パッド（八角形・接地円・H・ネット・灯）とヘリ・小物が読める
- game: `tests/net/online_staging_runtime.gd` のスクリーンショット（`artifacts/online_staging/shots/`）
