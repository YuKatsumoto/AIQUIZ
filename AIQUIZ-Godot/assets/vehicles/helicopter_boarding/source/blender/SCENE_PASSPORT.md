# Scene Passport — 乗り込めるヘリ（helicopter_boarding、v2：作り込み）

SCENE
- intent: オンライン対戦のマッチング演出で、プレイヤーが歩いて乗り込み、操縦士ハテナ（等倍）と並んで座るヘリ。
  設計図 `artifacts/heli_blueprint/`（図 1〜9）の形に、かわいい比率のまま機械の作り込みとデカールを足す（v2、2026-10-11）
- deliverable: `helicopter_boarding.blend`（このフォルダ）、`assets/vehicles/helicopter_boarding/helicopter_boarding.glb`、
  `helicopter_boarding_layout.json`（マーカー・回る部品の軸・ドアのヒンジ・ガラスの帯・塗装と機体番号）、
  アトラス（`source/textures/hb_decals.png`、GLB に入る）、確認レンダー（`source/previews/hb_01〜24.png`）、`source/build_report.json`
- units: metres; axes: right-handed Z-up。形は Godot の座標で書き、Blender (x, y, z) = (x, -z, y - 1.75) に置く
  （GLB の原点＝メインローターの軸 × 地面から 1.75 m。原点から SKID_DROP 下がスキッドの下面）
- render（確認用）: EEVEE, 1600x900, 24fps, frames 1–150, Standard の色変換。確認レンダーでは焼いた AO を基本色に掛ける（書き出しの後だけ）
- dynamic: yes — 確認用に左のドアの開け閉め（1→16→64→79）、ローターの回り始め（84→150）、ジェットを広げる（90→114）。GLB には動きを入れない
- build: ユーザーのライブ Blender で `build_helicopter_boarding.py` を runpy で実行（Higgsfield の `bl_execute`）。ヘッドレスで代替しない。
  別の .blend を開いたままでは止まる（`--allow-other-file`）。終わったら `.blend` を保存する（AGENTS.md）
- construction_mode: 手続きの作り込み（すべて `[BLOCK]` 経路＝ローカルで作る。3D 生成・クレジットは使わない）

HIERARCHY
- 書き出し: コレクション `HB_EXPORT`。根 `HelicopterRoot`（空、原点）の子に部品。動かす部品は原点を軸に置く
  - `Body`：外板・内張り・ゴムの縁、屋根のカバー・吸気口・排気・アンテナ・ビーコンの台、マストとローターの止まった部品、
    尾の筒・ストレーキ・水平尾翼と端板・フェネストロンの囲いとダクト・ステーター・上下の尾翼、機首の機器（ワイヤーカッター・ピトー管・
    サーチライト・ミラー・ワイパー）、ヒンジの関節とカバー、ホイスト、側面の通気口・給油口、腹のアンテナ・カーゴフック、
    床下ハッチの井戸と枠、ジェットのパイロン、灯の覆い、デカール
  - `Windows`（前の風防と灯のレンズ）
  - `Door_L` / `Door_R`（原点＝ヒンジの前端、ローカル +Z（Godot）＝ヒンジの線。開くのは左 -90°、右 +90°）。ガラスの枠・取っ手・紋章・細い線
  - `Interior`（床・仕切り・計器盤・コンソール・天井のパネル・壁とドアの内側・座席 2 つ・操縦かん 2 本・ヘッドセット・銘板）、
    `DashScreens`（発光する画面）、`Booster_R`、`Belt_L` / `Belt_R`、`FrameAndSkids`（スキッド・十字の管・金具・左のステップ）
  - `MainRotor`（原点＝ハブ、Y 軸。ハブ・羽根の付け根）、その子の `MainRotorBlades`（羽根 3 枚）
  - `TailRotor`（フェネストロンのファンの羽根 10 枚。原点＝ファンの中心、X 軸）
  - `DropHatchLeft` / `DropHatchRight`（原点＝外側のふち、Z 軸で ±78°）
  - `NavLight_L` / `NavLight_R` / `Beacon` / `LandingLight` / `StrobeLights`（どれも面が 1 つ）
  - `JetPod_L` / `JetPod_R`（原点＝肩のヒンジ、Godot の +Z 軸。ふだんは 38° 下へたたむ）、子に `JetNozzle_*`（噴射口の羽根）と `JetGlow_*`（奥の光）
  - `Markers` の下に `MK_*`（設計図の 12 個）
- 確認用（書き出さない）: `REF_Review`（座ったハテナ・手を振るハテナ・座る／ステップの上／待つプレイヤー・地面）、`CAMERAS`、`LIGHTING`
- protected existing objects: このファイルだけを作り直す（`HB_EXPORT`・`REF_Review`・`CAMERAS`・`LIGHTING` の中身）。ヘリポートは別のファイルで作る

ASSETS（地面基準の高さ。数値は `heli_pilot_spec.json` と各モジュールの表）
- A01 胴体 | BLOCK | detailed | 全長 10.19（機首 -3.14〜尾 7.05）、幅 3.64、屋根 3.56 | 超楕円の断面を 51 か所に並べ、輪は 42 点。
  ガラスの線・帯・敷居・屋根の梁・ハッチのふちを輪の同じ番号に置くので、境目がギザギザにならない（目印の高さは前後でなめらかにつなぐ）| hero
- A02 ドア 2 枚 | BLOCK | detailed | 開口 z -2.25〜-0.55、敷居 0.76 | ガルウィング（上へ 90°）。屋根の上ではヒンジの線より内側
  （|x| 0.22 まで）を通るので、屋根の部品は `door_keepout(z)` の表（`build_report.json` の `shell.door_keepout`）より内へ置く | hero
- A03 内装 | BLOCK | detailed | 床 0.70、座席 ×2（ヘッドレスト・ベルト・レール）、計器盤（画面 4・計器 4・無線 3）、コンソール（ジェットのレバー）、
  天井のパネル（警告灯）、後ろの仕切り（「?」の紋章・消火器）、ヘッドセット
- A04 ローター | BLOCK | detailed | 直径 10.6、3 枚（翼型、先の赤白の帯は頂点色）、止めると 1 枚が機首の上。ハブ・スウォッシュプレート・ピッチリンク
- A05 フェネストロンの尾 | BLOCK | detailed | 直径 0.90、羽根 10 枚、ステーター 9 本。囲いは濃紺に白い縁、上の尾翼に機体番号とストロボ
- A06 スキッド・ステップ | BLOCK | detailed | 間隔 3.12、すり板と金具、ステップ上面 0.35（左だけ、黄黒の縁は形）
- A07 床下ハッチ | BLOCK | stylized | 1.30 × 1.20、2 枚。まわりの腹に黄黒の帯（デカール）
- A08 ジェットブースト | BLOCK | detailed | 左右のポッド（半径 0.27）、短い翼、噴射口の羽根、奥の光、外側にシェブロン 3 つ（形）。数値は `hb_parts.JET`

LOOK
- 材質は 19。名前で役割を持つ（Godot のコードが名前で探す）：BodyPaint（色替え）、BodyAccent（濃紺 #1D2F5C、色替えしない）、Trim、
  Windows（ガラス）、Charcoal、Rubber、Metal、Decal / DecalNumber（アトラス、アルファ）、Interior、Floor、SeatFabric、DashDark、
  ScreenGlow（アトラスで光る）、NavRed / NavGreen / LampWhite（発光）、JetGlow（発光。Godot が強さを変える）、DropHatchInterior
- 塗り分け：帯より下（輪のセグメント 4〜6）・尾翼・ハッチは濃紺。上はプレイヤーの色。白い帯（y 1.30〜1.44）の上に濃紺の細い線、下に白い細い線。
  機首で 3 本が V に集まる
- テクスチャは 1 枚（`hb_decals`、2048²、ストレートのアルファ）。外の領域は 2 のべき乗にそろえたマスに 32 px の透明なふち。黄黒・細い線は
  横いっぱいに続けたタイル。下半分はコックピットの画面。毎回描き直して .blend に詰め、ディスクの PNG と MD5 を比べる
- デカール（`hb_decals.py`）：外板の三角形をデカールの形で切り抜き、なめらかな法線の向きに 3〜5 mm 浮かせる。
  尾の筒のロゴ（字の高さ 0.22、左右）・腹のロゴ・尾翼の機体番号（左右）・ドアの紋章（直径 0.40）・細い線 4 本・ハッチの黄黒の帯・
  吊り上げの印（形）・計器盤の銘板。注意書きの文字は入れない
- 頂点色 `Col` に AO を焼く（`aqs_wear.bake_wear`。ジェットはたたんだ形で焼く）。材質ごとに倍率を仕上げ（濃紺・警告色を薄めない）、
  GLB の COLOR_0 として出す。Godot は「頂点色を基本色に掛ける」で読む

ACCEPTANCE（ビルダーの checks 61 行、Godot の静的チェック 108 項目と実行チェック 16 項目）
- structural: 必要なノード・マーカーがそろい、`.001` がない。原点が設計どおり。三角形 ≤ 40,000（今 35,558）、面 78（Godot の上限 82）
- mesh: なめらかな面はすべて溶接、溶接の頂点の数が予定どおり、`me.validate()` が何も直さない、灯は面が 1 つ
- clearance: 開いていくドア（3° ごと）が部品に当たらない・天井より下に入らない、ドアとローターの隙間 ≥ 0.08、
  ポッドを広げる途中で当たらない、たたんだポッドと胴体 ≥ 0.035、乗り込みの通り道が空いている、床下ハッチの下が空いている、
  スキッドのほかは地面から 0.05 より上、メインローターの先と尾 ≥ 0.30、ファンがダクトの中
- cockpit: 計器盤の上端（ハテナの口の前 ≤ 1.835）、壁の出っ張り ≤ 0.02、天井の部品の下面 ≥ 3.12、足の床 ≤ 0.704、
  正面とコックピットのカメラから顔と「?」が見える
- decals: アトラス 2048² を詰めてあり MD5 が一致、全部のデカールを外板で覆える（97 % 以上）、すき間 1.5〜15 mm で外側、
  UV を渡し忘れた面がない、ほかの部品に当たらない、細い線とゴム枠 ≥ 6 mm
- GLB: 画像 1 枚、Decal / DecalNumber に色のテクスチャと alphaMode BLEND、ScreenGlow に光るテクスチャ、BodyAccent がある。
  落ちたら前の GLB に戻し、layout を書かない
- Godot: 色替え（オレンジ／ブルー）・濃紺は色替えしない・ガラス・クリアコート・ローターと尾のファンのぼかし・ストロボ・
  デカールの描き方（アルファ・-8・頂点色）・機体番号（オレンジ AQ-01、ブルー AQ-02）。26 m・LOD 1.5 でデカールが沈まない

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-animation, blender-lighting-camera, blender-audit-finalize
