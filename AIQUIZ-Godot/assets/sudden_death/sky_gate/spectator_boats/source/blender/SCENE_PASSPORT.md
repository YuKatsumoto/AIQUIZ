# Scene Passport — 観客船（spectator_boats）

SCENE
- intent: サドンデス「つきやぶれ！スカイゲート」（`docs/sudden_death_v2/sky_gate.md`）の着地台のまわりに浮かべる、観客を乗せた船。
  着地すると観客がクラッカーを鳴らし、船の舳先の筒から打ち上げ花火を上げる（2026-10-21、ユーザーの指示）。
  ゲームのカメラは着地台のまわり 9〜11 m を回るので、船は 10〜40 m 先に映る（2026-10-21「もっと近づけて」で、着地台から 20〜28 m に置いた）。遠目に「観客の乗った船」と読め、
  寄りの確認でも部品が浮いていないこと。着地台と同じく派手すぎない（白い船体と細い色帯、旗は小さく）
- deliverable: `spectator_boats.blend`（このフォルダ）、`assets/sudden_death/sky_gate/spectator_boats/spectator_boats.glb`、
  `spectator_boats_layout.json`（座席・打ち上げ筒・寸法。Godot の座標）、確認レンダー（`source/previews/sb_*.png`）、`source/build_report.json`
- units: metres; axes: right-handed Z-up。原点＝船の中心 × 喫水線（水面 z = 0）。船首は +X。観客は −Y（Godot の +Z）を向く。Godot では (x, z, -y)
- render（確認用）: EEVEE, 1600x900, Standard の色変換、空は物理の空（MULTIPLE_SCATTERING）
- dynamic: GLB に動きは入れない（波に浮く上下・傾き、旗のはためき、観客の動き、クラッカーと花火は Godot で付ける）。確認用の静止画のみ
- build: ユーザーのライブ Blender で `build_spectator_boats.py` を runpy で実行（Higgsfield の `bl_execute`）。ヘッドレスで代替しない。
  終わったら `.blend` を保存する（AGENTS.md）
- construction_mode: blockout 経路の手続きの作り込み（すべて `[BLOCK]`。3D 生成・クレジットは使わない）

HIERARCHY
- 部品: コレクション `SB_PARTS_Launch`・`SB_PARTS_Pontoon`（部品ごとの編集用。書き出さない）
- 書き出し: コレクション `SB_EXPORT`。根の空 `SB_Launch`・`SB_Pontoon`（それぞれ原点）の子に、材質ごとにまとめたメッシュ。
  船体（`Hull`）は色の帯ごとに材質を分けた 1 つのメッシュ。旗（`Flags`）ははためかせるので別（UV の v が付け根 0 → 先 1）
- マーカー: 座席・打ち上げ筒は layout の JSON に書く（GLB には入れない）
- 確認用（書き出さない）: `REF_Review`（海面・座った人の箱）、`CAMERAS`、`LIGHTING`
- protected existing objects: このファイルだけを作り直す（上のコレクションの中身）。起動時の Cube・Light・Camera は隠すだけ

ASSETS（z は喫水線から）
- A01 観覧船 SB_Launch | BLOCK | detailed | 全長 10.8（水線 10.0、船首の傾き 0.8）・幅 3.6・舷の高さ 1.0（船尾）〜1.32（船首）・甲板 0.80 |
  白い船体（ロフトした断面：キール・デッドライズ・チャイン・フレア）、舷の下に紺の色帯、喫水線の帯、船底は赤茶 | midground hero
  - ベンチ 2 列（前の列は甲板の上 0.50 の座面、後ろの列は 0.38 の台の上）。1 列 6 席・間隔 0.85 m。背もたれ・脚・クッション
  - 手すり（支柱 0.9 m おき・上 0.62・中 0.32）、舷の縁のこすれ止め、船尾の操舵台（風防・ハンドル・T トップの屋根）、
    船首のマスト、マストから船尾の柱へ旗の綱（三角の小旗 18 枚）、舳先の打ち上げ筒の箱（筒 6 本）、フェンダー 3、救命浮き輪、航海灯、クリート 4
- A02 パーティー船 SB_Pontoon | BLOCK | detailed | 全長 7.9・幅 2.6・甲板 0.56 | アルミの浮き筒 2 本（半径 0.32、船首は上へ反った円錐）、
  甲板、周りの柵（観客の前＝−Y は柵の板を使わず手すりだけ）、色帯、ベンチ 2 列（1 列 6 席）、船首の操舵台、船尾の打ち上げ筒の箱、旗の綱 | midground hero
- A03 座った人の箱 | BLOCK | blockout | 確認用（座面の上の胴・頭・ももの箱）。書き出さない

SHOT（確認用）
- `CAM_Hero`：観客の正面（−Y）の斜め前、低め（ゲームの着地の画から見える向き）。`CAM_Far`：35 m 先から（ゲームの背景の大きさ）。
  `CAM_Top`：真上（降りてくる画）。`CAM_Pontoon`：パーティー船の斜め前。`CAM_Detail`：打ち上げ筒と操舵台の寄り

LOOK
- 材質は役割ごとに 1 つ（`SB_*`）。白いゲルコート（粗さ 0.32）、色帯 `SB_Stripe`（紺。Godot で船ごとに塗り替える）、船底 `SB_Bottom`、
  甲板 `SB_Deck`（明るいグレー、粗さ 0.85）、チーク `SB_Teak`、クッション `SB_Cushion`、ステンレス `SB_Steel`（金属 1・粗さ 0.25）、
  アルミ `SB_Alu`、黒いゴム `SB_Trim`、風防 `SB_Glass`、屋根の布 `SB_Canvas`、筒 `SB_Tube`・箱 `SB_Crate`、救命浮き輪 `SB_Accent`、
  航海灯 `SB_LampRed`・`SB_LampGreen`（発光 2.5）、旗 `SB_Flags`（頂点の色）
- テクスチャは使わない（glTF で手続きの材質は運べない）

LIGHTING（確認用）
- 物理の空と太陽 1 つ（観客の側の斜め上から）。補助の光は足さない

ACCEPTANCE
- structural: 原点・喫水線・大きさが上の表のとおり。書き出しは材質ごとにまとまり、法線が外を向く。1 隻 2 万三角形以下
- visual: 白い船体の形（船首の反り・チャイン）が読める。ベンチの高さと間隔に座った人の箱が収まり、足が床に着く。
  手すりと旗の綱が観客の頭と腕（座面から 1.8 m まで）にかからない。浮いた部品・めり込みがない
- Godot: 取り込んで海に浮かべ、座った観客を座席に置いた画で、観客が着地台の方を向き、船の上に収まっていること
