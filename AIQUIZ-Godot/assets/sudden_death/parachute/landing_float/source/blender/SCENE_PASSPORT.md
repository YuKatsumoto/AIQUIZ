# Scene Passport — 着地台（landing_float）

SCENE
- intent: サドンデス「ひらけ！パラシュート」（`docs/sudden_death_v2/parachute.md`）で、勝者がパラシュートで降りて踊る、海に浮かぶ着地台。
  遠く（高度 260 m の真上）からオレンジの輪が目印として読め、近く（勝者が踊る 3〜8 m）では作り込みが見えること。
  色と柄はシンプルに（2026-10-18、ユーザーの指示：明るいグレーにオレンジの輪 1 本。派手な柄・旗・クッションはなし）
- deliverable: `landing_float.blend`（このフォルダ）、`assets/sudden_death/parachute/landing_float/landing_float.glb`、
  `landing_float_layout.json`（マーカー）、確認レンダー（`source/previews/lf_*.png`）、`source/build_report.json`
- units: metres; axes: right-handed Z-up。原点＝浮き台の中心 × 喫水線（水面 z = 0）。Godot では (x, z, -y)
- render（確認用）: EEVEE, 1600x900, Standard の色変換、空は Nishita
- dynamic: 浮き台そのものは GLB に動きを入れない（波に浮く上下・傾き、旗のはためき、灯の点滅、着地の沈み込みは Godot で付ける）。確認用の静止画のみ（ユーザーの「作り込み」の依頼に対する見た目の確認）
- build: ユーザーのライブ Blender で `build_landing_float.py` を runpy で実行（Higgsfield の `bl_execute`）。ヘッドレスで代替しない。
  終わったら `.blend` を保存する（AGENTS.md）
- construction_mode: 手続きの作り込み（すべて `[BLOCK]` 経路＝ローカルで作る。3D 生成・クレジットは使わない）

HIERARCHY
- 部品: コレクション `LF_PARTS`（部品ごとの編集用オブジェクト。書き出さない）
- 書き出し: コレクション `LF_EXPORT`。根 `LandingFloatRoot`（空、原点）の子に、材質ごとにまとめたメッシュ（描く回数を減らす）。
  光らせるものは別のオブジェクト：`Lamps`（点滅）、`Tally`（中継カメラの赤い灯）
- マーカー: `Markers` の下に `MK_*`（着地点・着地面のふち・はしごの上・中継カメラ）
- 確認用（書き出さない）: `REF_Review`（海面・大きさの比較用のプレイヤーの箱）、`CAMERAS`、`LIGHTING`
- protected existing objects: このファイルだけを作り直す（上のコレクションの中身）

ASSETS（z は喫水線から）
- A01 浮き輪 | BLOCK | detailed | 輪の中心の半径 3.55、管の半径 0.52、管の中心 z 0.28（外径 8.14、上面 0.80）| 12 部屋。部屋の境目で 3% くびれる。
  テクスチャ `lf_tube`（明るいグレー 1 色、溶着の継ぎ目、しわ、喫水線の汚れ、日焼け）| hero
- A02 着地面 | BLOCK | detailed | 半径 3.15、上面 z 0.57（ほぼ平ら。中心が 1 cm 高い）| テクスチャ `lf_pad`（グレーのマット・オレンジの輪 1 本と中心の丸・
  すべり止めの菱形の溝・縫い目・すり傷・足あと・水たまり）| hero
- A03 底 | BLOCK | stylized | 半径 3.5、z −0.18 | ほぼ水の中
- A04 こすれ止めの帯 | BLOCK | detailed | 外側の赤道の少し下（phi −16°〜0°）、厚さ 1.8 cm、溝 3 本
- A05 溶着テープ | BLOCK | detailed | 部屋の境目 12 か所、幅 5 cm、管をひと回り
- A06 Dリングとロープ | BLOCK | detailed | 外側 phi 18° に 24 か所の当て布と D リング、間を垂れたロープ（たるみ 0.10）
- A07 空気弁 | BLOCK | detailed | 3 か所（つば・ふた・ひも）
- A08 取っ手 | BLOCK | detailed | 内側の上に 8 か所（帯の輪）
- A10 標識灯 | BLOCK | detailed | 4 か所（斜め 45°。台・黄色く光るドーム・ガード）
- A11 はしご | BLOCK | detailed | 2 本（±X）。管の上を越えて水の中へ。ステンレスの手すり・踏み板・当て物
- A12 中継カメラ | BLOCK | detailed | +Y の管の上。クランプ・柱・雲台・本体・レンズとフード・赤い灯・ケーブル。中心へ向いて 20° 下を見る
- A13 縁取り | BLOCK | detailed | 着地面のふち（r 3.10）の濃いグレーのパイピング、水抜きのはとめ 12 個
- A14 大きさの比較 | BLOCK | blockout | 確認用のプレイヤーの箱（高さ 2.05）。書き出さない

SHOT（確認用）
- `CAM_Hero`：-Y の斜め前、低め（ゲームの着地のショット C9 に近い）。`CAM_Top`：真上（高度の画の的の読め方）。
  `CAM_Ladder` / `CAM_TvCam` / `CAM_Side` / `CAM_Cleat` / `CAM_Deck`：作り込みの寄り

LOOK
- 材質は役割ごとに 1 つ（`LF_*`）。テクスチャは `lf_tube` / `lf_pad`（それぞれ ORM の G を粗さに）。
  ステンレスは金属 1・粗さ 0.28、ゴムは 0.7。ロープ・取っ手・パイピングは濃いグレー
- 光るもの：標識灯（黄、強さ 3）、中継カメラの赤い灯（強さ 4）

LIGHTING（確認用）
- Nishita の空と太陽 1 つ（斜め横から。浮き輪の丸みに明るい面と影の面が出る向き）。補助の光は足さない

ACCEPTANCE
- structural: 原点・喫水線・大きさが上の表のとおり。書き出しのメッシュは材質ごとにまとまり、法線が外を向く。三角形 8 万以下
- visual: 真上からオレンジの輪が読める。派手すぎない。斜め前から、部屋のくびれ・継ぎ目・ロープの垂れ・はしご・カメラが見分けられる。
  浮いた部品・めり込みがない。プレイヤーの箱との比べで大きさがおかしくない
- Godot: 取り込んで海に浮かべた画で、テクスチャ・粗さ・発光が出ていること
