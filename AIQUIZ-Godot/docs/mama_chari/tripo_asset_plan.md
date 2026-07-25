# ママチャリ競争 Tripo素材計画

- ステータス: `READY FOR GENERATION`
- 版: `1.0`
- 方針: 必要な新規3D素材はTripoを第一生成元とする

## 1. 生成と実装の分担

Tripoは、ママチャリ本体、道路脇の立体物、ゲート、観客など、見た目を担う新規3D素材の生成に使う。Godotは、当たり判定、道路面、チェックポイント判定、パーティクル、ライン、簡単なデカール、動的な色替えを担当する。

この「Tripo中心」は新規3Dモデルに対する方針である。UI、シェーダー、判定用形状、パーティクルはGodotで作り、チェーン音やタイヤ音などの音声はTripoの対象外として別途制作する。フェーズ1では既存の手続き生成音を仮音に使い、音声制作待ちで乗り味検証を止めない。

自転車の車輪やハンドルは骨アニメーションではなく、分離した剛体パーツをGodotで回転させる。これにより、速度と車輪回転を正確に同期できる。

Tripoのメッシュ編集、分割、低ポリ化はリグ情報を保持しないため、必ず次の順序にする。

`生成 → パーツ分割/補完 → 低ポリ化/UV/テクスチャ → 書き出し → 必要なキャラクターだけリグ/リターゲット`

## 2. 保存先と命名

完成したGodot用素材は次へ置く。

```text
assets/mama_chari/
  vehicles/
  course/
  props/
  spectators/
  textures/
  source_notes/
```

命名規則は `mch_<用途>_<名前>_vNN.glb` とする。

例:

- `mch_vehicle_city_bike_v01.glb`
- `mch_course_checkpoint_arch_v01.glb`
- `mch_prop_soft_cone_v01.glb`
- `mch_spectator_cheer_a_v01.glb`

各生成物について `source_notes/` に次を記録する。

- TripoのタスクID
- 使用モデル/モード
- プロンプト全文
- 参照画像の相対パス
- 生成日
- 分割、低ポリ化、テクスチャ、リグの処理順
- 採用した出力ファイル名
- 既知の修正点

`assets/tripo_references/` にある既存のゴールゲート参照画像は削除・上書きせず、ゲート生成に再利用する。

## 3. 最優先素材

| ID | 素材 | 数 | 優先度 | Tripo出力 | 実装条件 |
|---|---|---:|---|---|---|
| `VEH-001` | 日本のママチャリ本体 | 1 | 最優先 | GLB | 可動部を分離、P1/P2色替え可能 |
| `CRS-001` | 開始/乗車ゲート | 1 | 最優先 | GLB | 旧ゴール位置へ設置、文字はGodotで表示 |
| `CRS-002` | チェックポイントアーチ | 1 | 高 | GLB | 色替えして反復使用 |
| `CRS-003` | 次競技への降車ゲート | 1 | 高 | GLB | 自転車からランへ接続 |
| `PRP-001` | 柔らかいスラロームコーン | 1 | 高 | GLB | 複製前提、既存帽子用コーンとは別用途 |
| `PRP-002` | コース用安全柵1区画 | 1 | 高 | GLB | 継ぎ目なく反復配置できる |
| `PRP-003` | 低い路面バンプ | 2 | 高 | GLB | 小/大の2種 |
| `PRP-004` | 二択ルート標識 | 2 | 高 | GLB | 矢印と文字はGodot側 |
| `PRP-005` | 自転車置場/整備小物セット | 1 | 中 | GLB | 背景演出用 |
| `SPC-001` | 低ポリ観客 | 4 | 中 | GLB | 体格と姿勢を変えた4種 |
| `SPC-002` | 応援旗/のぼり | 3 | 中 | GLB | ロゴと文章なし |

水たまりはTripoで縁の立体物を作ってもよいが、水面、濡れ表現、滑り判定はGodot側で作る。道路本体もゲームプレイ寸法を優先するため、Tripoの一枚物モデルにはしない。

### ライダー用アニメーション

既存プレイヤーの見た目と65ボーンのリターゲット経路を維持し、新しいライダーモデルへ置き換えない。必要なクリップは次の7種とする。

```text
bike_pedal_loop
bike_stand_pedal_loop
bike_wobble_left
bike_wobble_right
bike_fall
bike_mount
bike_dismount
```

Tripoでアニメーション元を作る場合は、編集・低ポリ化を終えてからリグ/リターゲットし、最終的に既存プレイヤーの骨名へ変換する。走行速度とペダル位相はゲーム状態が正であり、アニメーション側のルートモーションで前進させない。フェーズ1は簡易姿勢と手続き的な足回転で開始し、完成クリップはフェーズ4で差し替える。

### 3D以外で必要な素材

次はTripoではなく、フェーズ6の音声/VFX制作対象として管理する。

- チェーン、ペダル、タイヤ路面、ベル、ブレーキ
- 水たまり、段差、コーン接触、転倒、復帰
- 立ち漕ぎ、スリップストリーム、チェックポイント
- 観客歓声、写真判定、区間終了

## 4. ママチャリ本体の必須構造

### 外観

- 日本の実用シティサイクル
- 低いステップスルーフレーム
- 前かご
- 後部荷台
- チェーンカバー
- ベル
- 泥よけ
- スタンド
- 少しコミカルだが玩具すぎない、現在のゲームに合う明るいスタイル
- ブランド、ロゴ、文字、ナンバープレートなし
- ライダーを一体生成しない

### 寸法

- 全長 `1.80m`
- 全幅 `0.60m` 前後
- ハンドル高 `1.10m` 前後
- 車輪直径 `0.66m` 前後
- 地面接点を `Y=0` に合わせる
- 前進方向はGodotシーンで `+Z` に統一する

### 必須パーツ名

TripoのDetailed分割後、最低でも次を独立パーツにする。書き出し後に名前を合わせる必要がある場合も、最終GLBではこの契約を守る。

```text
BikeBody
WheelFront
WheelRear
Handlebar
Crank
PedalL
PedalR
Basket
Bell
Kickstand
```

- `WheelFront` と `WheelRear` の原点は各車軸中心。
- `Handlebar` の原点はステアリング軸。
- `Crank` の原点はBB中心。
- ペダルはクランク回転に追従できる位置へ置く。
- `BikeBody` はフレーム色をP1/P2別に差し替えられる材質スロットを持つ。
- かご、タイヤ、金属部、サドルはフレーム色から分離する。

### 目標負荷

- 1台合計 `40,000 triangles` 以下を目安とする
- テクスチャは本体最大 `2048px`、小物は `1024px`
- 透明材質を乱用しない
- 同じ素材を2台同時表示しても材質複製を最小化できる構造にする

## 5. Tripo用プロンプト

### `VEH-001` ママチャリ

```text
A Japanese city utility bicycle, step-through frame, front wire basket, rear cargo rack, full chain guard, fenders, kickstand and a small bell. Slightly comedic friendly proportions but believable and functional, clean colorful arcade game style, game-ready PBR geometry, symmetrical wheels, mechanically clear frame and steering parts, no rider, no person, no logo, no brand, no text, isolated object, neutral studio lighting, full bicycle visible.
```

生成後はDetailedパーツ分割を使い、車輪、ハンドル、クランク、ペダルを優先して分ける。分割後に不足している裏面や接続部はPart Completionで補完する。

### `CRS-001` 開始ゲート

```text
A cheerful Japanese neighborhood bicycle race starting arch, colorful sports festival style, sturdy rounded frame, bicycle motifs, flags and small signal lights, readable silhouette from far away, modular game-ready PBR prop, no words, no letters, no logos, no people, isolated object.
```

`assets/tripo_references/goal_gate_reference-v2.png` を第一参照にする。ゲート上の「ママチャリ」やP1/P2表示は3D生成へ焼かず、Godotのラベルで表示する。

### `CRS-002` チェックポイント

```text
A compact modular checkpoint arch for a colorful arcade bicycle obstacle race, soft rounded safety design, lamps and flag mounts, clear center opening for two riders, game-ready PBR prop, no text, no logo, no people, isolated object.
```

### `PRP-002` 安全柵

```text
A modular roadside safety barrier segment for a cheerful Japanese bicycle race, padded rails, rounded corners, repeating connection ends, colorful arcade sports style, game-ready low-poly PBR prop, no text, no logo, isolated object.
```

### `SPC-001` 観客

```text
A friendly stylized low-poly spectator for a colorful Japanese sports festival, cheering pose, clear silhouette, casual clothing, game-ready character, no text, no logo, neutral background, full body visible.
```

観客は必要に応じてTripoでリグし、短い応援ループへリターゲットする。メッシュ分割や低ポリ化はリグ前に完了させる。

## 6. Tripo生成時の採用基準

各候補は次を満たすまで採用しない。

- 正面、側面、背面、斜めの4方向で破綻がない
- タイヤが真円に近く、左右で大きく非対称ではない
- かご、チェーンカバー、泥よけがフレームへ不自然に溶けていない
- 走行中に回すパーツを独立させられる
- ロゴ、意味不明な文字、ブランド風マークがない
- 極端に薄い面、浮遊パーツ、穴、法線反転がない
- P1/P2の色替えで見分けられる
- 上記の寸法へ合わせても破綻しない
- GodotのForward+でPBR材質が過度に金属化、発光、透明化しない

同じ素材は最低3候補を生成し、シルエット、分割しやすさ、材質、ゲーム画面での読みやすさの順に選ぶ。細密さだけで選ばない。

## 7. Godot取り込み手順

1. 元のTripo出力と採用版を分けて保存する。
2. 採用版を指定の `assets/mama_chari/` 配下へ置く。
3. Godotのインポート完了を待つ。
4. Fennaraのアセット検査でインポーター、生成リソース、アニメーション、材質、依存ファイルを確認する。
5. 全方向スクリーンショットで寸法、向き、欠損、材質を確認する。
6. 必要なインポート設定だけをFennara経由で変更する。`.import` は直接編集しない。
7. `mama_chari.tscn` に配置し、車輪とハンドルのピボットを実走行で確認する。

## 8. 素材が未完成でも止めない項目

フェーズ1の乗り味実装は、Tripo生成の完了を待たない。次はプリミティブ仮モデルで先に作る。

- 車体、2輪、ハンドル、クランクのノード契約
- 走行可能幅と230mの距離
- 操舵、加速、ブレーキ、立ち漕ぎ、ウォブル
- 障害物判定とチェックポイント復帰
- 2PカメラとHUD

Tripo素材はこのノード契約へ差し替え、ゲームルール側へ素材固有のノード探索や寸法補正を漏らさない。

## 9. 参照したTripo公式仕様

- [Generation API](https://platform.tripo3d.ai/docs/generation): パーツ生成、UV、低ポリ/quad出力の条件
- [Animation API](https://platform.tripo3d.ai/docs/animation): リグ、リターゲット、編集後のリグ情報の扱い
- [Post Process API](https://platform.tripo3d.ai/docs/post-process): GLB/FBX変換とアニメーション書き出し
