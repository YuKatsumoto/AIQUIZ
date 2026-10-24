# Scene Passport — パラシュート・ハンカチ・水柱（chute / splash）

SCENE
- intent: サドンデス「ひらけ！パラシュート」（`docs/sudden_death_v2/parachute.md` 6.4節）のパラシュート一式と、敗者が海へ落ちる水柱。
  段ごとの形（1 段：袋とパイロットシュート、2 段：半分ふくらんだしわの形、3 段：全開）と、開く・しぼむ・着地でつぶれる動きを
  Godot で付けられるように、形の切り替え（シェイプキー＝glTF のモーフターゲット）で持つ
- deliverable: `parachute.blend`（このフォルダ）、`assets/sudden_death/parachute/chute/chute.glb`・`splash.glb`・`chute_layout.json`、
  確認レンダー（`source/previews/pc_*.png`）、`source/build_report.json`
- units: metres; axes: right-handed Z-up。パラシュートの原点＝肩のライザーのつけ根（両肩の真ん中）。+Z が体の上、+X が体の横、
  −Y が前（Godot では +Y 上、+Z 前）。水柱の原点＝水面の中心
- render（確認用）: EEVEE, 1600x900, Standard の色変換、空は物理的な空
- dynamic: GLB に動きは入れない（形の切り替えの重みと、パイロットシュート・袋・ブライドルの置き場所は Godot が毎フレーム決める）。
  確認用は段ごとの静止画
- build: ユーザーのライブ Blender で `build_parachute.py` を runpy で実行（Higgsfield の `bl_execute`）。ヘッドレスで代替しない。
  終わったら `.blend` を保存する（AGENTS.md）
- construction_mode: 手続きの作り込み（すべて `[BLOCK]` 経路。3D 生成・クレジットは使わない）

HIERARCHY
- 書き出し（chute.glb）: 根 `ChuteRoot`（空、原点）の子に `Canopy`（布：上下の面・リブ・安定板）、`Lines`（つり索・カスケード・ブレーク索）、
  `Slider`、`Risers`（ライザー・リンク・トグル）、`PilotChute`（原点＝ブライドルのつけ根）、`Bridle`（原点から +Z へ 1 m。Godot が長さに合わせて伸ばす）、
  `DeployBag`（原点＝中心）、`Container`（背中のコンテナ。原点＝背中に当たる面の中心）、`Hanky`（原点＝ひものつけ根）
- 書き出し（splash.glb）: 根 `SplashRoot` の子に `SplashColumn`・`SplashCrown`・`SplashDroplets`・`SplashFoam`・`SplashRipple`
- 形の切り替え（`Canopy`・`Lines`・`Slider` に同じ名前で）: `Packed`（袋の中）、`Half`（半分ふくらんだしわの形）、`Collapsed`（着地で後ろへつぶれる）、
  `Breath`（ふくらみが少し抜ける。はためき用）。基本形が全開
- 確認用（書き出さない）: `REF_Review`（肩の高さの目安の人形の箱、海面）、`CAMERAS`、`LIGHTING`

ASSETS
- A01 布 | BLOCK | detailed | 幅 7.2 m（弧 70°）、翼弦 2.6 m、厚さ 0.52 m、中心の高さ 6.3 m | 9 セル。翼形の断面（下面は平ら寄り）、前縁の取り込み口、
  セルの間のふくらみ、リブ 10 枚、両端の安定板、つり索のつけ根のタブ | hero
- A02 つり索 | BLOCK | detailed | A〜D の 4 列 × リブ 10 枚、カスケードでまとめて 4 本のリンクへ。ブレーク索は後縁からトグルへ
- A03 スライダー | BLOCK | detailed | 0.95 × 0.75 m、はとめ 4 つ。開くと肩の上 0.62 m まで下りる（基本形）
- A04 ライザー | BLOCK | detailed | 4 本の帯、リンク（金属の輪）、後ろのライザーにトグル
- A05 パイロットシュート | BLOCK | detailed | 直径 1.1 m、12 枚のゴア、網のすそ、頂点のキャップ、中心の索
- A06 収納袋 | BLOCK | detailed | 0.34 × 0.18 × 0.5 m、フタとはとめ、ゴムの留め 4 つ
- A07 コンテナ | BLOCK | detailed | 0.36 × 0.16 × 0.46 m、予備のフタ、横のフタ、縫い目、肩のヨーク、引き手（プレイヤーの色の玉）
- A08 ハンカチ | BLOCK | detailed | 0.45 m 四方、波打つ折り目、赤い縁取り、レースのふち、小さな輪とひも
- A09 水柱 | BLOCK | stylized | 柱（高さ 11 m）、クラウン（半径 1.2〜2.4 m、とげ 14 本と先の水滴）、飛び散る水滴、泡の輪（半径 3.5 m）、波紋

LOOK
- 材質（名前で探す）: `PC_Accent`（プレイヤーの色。Godot が塗り替える）、`PC_White`（布の白）、`PC_Rib`、`PC_Line`、`PC_Webbing`、`PC_Metal`、
  `PC_Mesh`（網）、`PC_Bag`、`PC_Container`、`PC_HankyWhite`・`PC_HankyRed`、`SP_Water`・`SP_Foam`（半透明）
- 布は両面（裏からも見える）。セルは色と白の交互（中央のセルは色）

ACCEPTANCE
- structural: 形の切り替え 4 つが `Canopy`・`Lines`・`Slider` にあり、glTF に書き出される。三角形は chute 3 万以下、splash 1 万以下
- visual: 全開で翼の形・取り込み口・つり索のまとまりが読める。半分は、しわがよって幅が狭い。袋の中では布が見えない。着地は後ろへ平らに
- Godot: 取り込んで、重みを変えると形が変わること・色の塗り替えができること
