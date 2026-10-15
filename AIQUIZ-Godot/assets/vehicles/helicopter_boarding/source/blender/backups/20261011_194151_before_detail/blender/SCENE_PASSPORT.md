# Scene Passport — 乗り込めるヘリ（helicopter_boarding、v1）

SCENE
- intent: オンライン対戦のマッチング演出で、プレイヤーが歩いて乗り込み、操縦士ハテナ（等倍）と並んで座るヘリ。
  設計図 `artifacts/heli_blueprint/`（図 1〜9）をそのまま形にする
- deliverable: `helicopter_boarding.blend`（このフォルダ）、`assets/vehicles/helicopter_boarding/helicopter_boarding.glb`、
  `helicopter_boarding_layout.json`（マーカー・回る部品の軸・ドアのヒンジ）、確認レンダー（`source/previews/hb_*.png`）、
  `source/build_report.json`。Godot への組み込み（オンラインのヘリポート）は別作業
- units: metres; axes: right-handed Z-up。形は Godot の座標で書き、Blender (x, y, z) = (x, -z, y - 1.75) に置く
  （GLB の原点＝メインローターの軸 × 地面から 1.75 m。今のヘリと同じく、原点から SKID_DROP 下がスキッドの下面）
- render（確認用）: EEVEE, 1600x900, 24fps, frames 1–150, Standard の色変換
- dynamic: yes — 確認用に左のドアの開け閉め（1→16→64→79）とローターの回り始め（84→150）。GLB には動きを入れない
  （ゲームでは Godot がドア・ローターを回す）
- build: ユーザーのライブ Blender で `build_helicopter_boarding.py` を runpy で実行（Higgsfield の `bl_execute`）。ヘッドレスで代替しない。
  終わったら `.blend` を保存する（AGENTS.md）
- construction_mode: 手続きの作り込み（すべて `[BLOCK]` 経路＝ローカルで作る。3D 生成・クレジットは使わない）

HIERARCHY
- 書き出し: コレクション `HB_EXPORT`。根 `HelicopterRoot`（空、原点）の子に部品。動かす部品は原点を軸に置く
  - `Body`（外板・内張り・ゴムの縁・マストのカバー・尾）、`Windows`（前の風防）。荷室の丸窓はなくした（2026-10-11）
  - `Door_L` / `Door_R`（原点＝ヒンジの前端、ローカル +Z（Godot）＝ヒンジの線。開くのは左 -90°、右 +90°）
  - `Interior`（床・仕切り・計器盤・コンソール）、`DashScreens`（発光）、`Seat_L` / `Seat_R`、`Booster_R`、`Yoke_L` / `Yoke_R`、
    `Belt_L` / `Belt_R`、`Step_L`、`FrameAndSkids`
  - `MainRotor`（原点＝ハブ、Y 軸）、`TailRotor`（原点＝ハブ、X 軸）
  - `DropBayFrame`、`DropBayInterior`、`DropHatchLeft` / `DropHatchRight`（原点＝外側のふち、Z 軸で ±78°）— 名前は今のヘリと同じ
  - `NavLight_L` / `NavLight_R` / `Beacon` / `LandingLight`
  - `JetPod_L` / `JetPod_R`（原点＝肩のヒンジ、Godot の +Z 軸。ふだんは 38° 下へたたむ）、子に `JetNozzle_*`（噴射口の羽根）と `JetGlow_*`（奥の光）
  - `Markers` の下に `MK_*`（設計図の 12 個）
- 確認用（書き出さない）: `REF_Review`（座ったハテナ・手を振るハテナ・座る／ステップの上／待つプレイヤー・地面）、`CAMERAS`、`LIGHTING`
- protected existing objects: 新しい空のファイルで作る。前に開いていた `online_heliport.blend` の未保存の状態は
  `assets/online_heliport/source/blender/backups/` に写しを残した（元のファイルは書き換えていない）

ASSETS（地面基準の高さ。数値はすべて `heli_pilot_spec.json`）
- A01 胴体 | BLOCK | detailed | 全長 10.09（機首 -3.14〜尾 6.98）、幅 3.64、屋根 3.56 | 超楕円の断面を 51 か所に並べ、輪は 42 点。
  ガラスの線・帯・敷居・屋根の梁・ハッチのふちを輪の同じ番号に置くので、境目がギザギザにならない | hero
- A02 ドア 2 枚 | BLOCK | detailed | 開口 z -2.25〜-0.55、敷居 0.76、ヒンジ x = ±0.35 | ガルウィング（上へ 90°）| hero
- A03 内装 | BLOCK | stylized | 床 0.70、座席（座面 1.18、背もたれ 10°）×2、計器盤（上端 1.75）、U 字の操縦かん ×2、ベルト、コンソール
- A04 ローター | BLOCK | stylized | 直径 10.6、2 枚、前後に止める。尾のローター 1.3（右側）
- A05 スキッド・ステップ | BLOCK | stylized | 間隔 3.12、ステップ上面 0.35（左だけ）
- A06 床下ハッチ | BLOCK | stylized | 1.30 × 1.20、2 枚。名前とヒンジは今のヘリと同じ
- A07 ジェットブースト | BLOCK | stylized | 左右のポッド（半径 0.27、長さ 2.4）、短い翼（腕 0.80）、噴射口の羽根 10 枚、奥の光。数値は `hb_parts.JET`（設計図の外の値）

LOOK
- 材質は名前で役割を持つ（Godot のコードが名前で探す）：BodyPaint（色替え）、Windows（ガラス）、Trim、Charcoal、Rubber、
  Interior、Floor、SeatFabric、DashDark、ScreenGlow（発光）、NavRed / NavGreen / LampWhite（発光）、DropHatchInterior、JetGlow（発光。Godot が強さを変える）
- テクスチャは使わない。頂点色 `Col` に AO を焼く（`aqs_wear.bake_wear`。水際の汚れなし）。GLB の COLOR_0 として出し、
  Godot は「頂点色を基本色に掛ける」で読む（BodyPaint の色替えにも AO が乗る）

ACCEPTANCE
- structural: 必要なノード・マーカーがそろい、`.001` がない。ドア・ローター・ハッチの原点が設計どおり。三角形 1 万前後
- motion: 確認用の動きでドアがヒンジのまわりに上へ開き、ローターがハブで回る。90 → 108 でジェットの翼が水平まで上がり、100 → 114 で羽根が広がる
- visual: 正面からハテナとプレイヤーの顔が計器盤の上に見える。白い帯がまっすぐ。ドアの縁にゴムの縁取り
- structural（ジェット）: たたんだポッドが胴体の外形に入らない、広げたポッドの上端がローターより 0.35 m 以上下（ビルダーの checks）
- Godot: `tests/helicopter_boarding_check.gd` が通る（76 項目）。色替え（オレンジ／ブルー）とドアを開けた状態を撮る

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-animation, blender-lighting-camera, blender-audit-finalize
