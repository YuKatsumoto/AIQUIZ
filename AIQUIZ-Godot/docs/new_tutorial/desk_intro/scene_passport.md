# 机のセット（段階2）Scene Passport

ローカル2Pの説明画面の始めを実写にする計画（[plan.md](plan.md)）の段階2。夜の部屋・机・モニター・キーボード・椅子・デスクライト・ハテナのフィギュアを、
ライブの Blender で実寸・実写の材質で作る。人物は段階3なので、ここでは構図を確かめるための仮の体（PROXY）だけ置く。
絵コンテは [storyboard_v01.jpg](storyboard_v01.jpg)。カメラは生成画像の見え方から決め直した値（プロンプトの数字はそのまま再現できる見え方ではなかったため）。

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-lighting-camera, blender-audit-finalize, blender-volatile

```text
SCENE
- intent: photoreal night gaming room for the opening of the local 2P tutorial; two players seen from behind sit and put their hands on one shared keyboard (storyboard v0.1, D1-D8).
- deliverable: editable Blender source assets/tutorial_desk/source/tutorial_desk.blend built by assets/tutorial_desk/source/blender/build_tutorial_desk.py in the live Blender; Cycles review renders of D1, D3, D5 under artifacts/tutorial_desk/blender/. Godot export comes in phase 5.
- units: metres; axes: right-handed Z-up. Origin = floor point under the centre of the desk's front edge; +Y toward the back wall (desk), camera side is -Y, +X is the viewer's right.
- render: Cycles (GPU), 1920x1080 (reviews at 1280x720), 24 fps, frames 1-150 reserved for phase 4.
- dynamic: yes (camera dolly D1->D4, sitting, hands - authored in phase 4). Phase 2 builds the static set with cameras at the storyboard key frames. explicit static request: none.

HIERARCHY
- collection/object naming: TD_Room (ENV_), TD_Desk (PRP_ desk, monitor, lamp, figure, shelf), TD_Keyboard (HERO_Keyboard root, KEY_<Name> caps, LEG_<Name> legends, GLOW_<Name> under-glow), TD_Chairs (PRP_Chair_P1/P2), TD_Proxy (PROXY_P1/P2 bodies, replaced in phase 3), TD_Cameras (CAM_D1, CAM_D2, CAM_D3, CAM_D5, CAM_D7, CAM_D8), TD_Lights (LGT_).
- parent/child relationships: every keycap, legend and glow is a child of HERO_Keyboard; each chair's parts are children of PRP_Chair_Px (origin at the floor under the gas lift); the monitor's screen and bias LED are children of PRP_Monitor.
- key ids: each KEY_ object carries custom property key_id = the TutorialKeyboard id ("A", "Space", "CtrlR", "←" ...). Object names use ASCII (Left, Up, Backslash, Semicolon ...) so Godot node names stay valid.
- protected existing objects: none in the new file. The previously open t8_thumbnail.blend was saved by user request before switching.

ASSETS
- A01 ENV_Floor | BLOCK | detailed | [4.2, 5.0, 0.0] | [0, -1.7, 0] | dark oak planks
- A02 ENV_Walls (back, left, right, front, ceiling) | BLOCK | stylized | room inner width 4.2, back wall at y=+0.80, height 2.5 | navy paint
- A03 ENV_Baseboard | BLOCK | stylized | 0.08 high | along walls
- A04 PRP_Desk (top + frame) | BLOCK | detailed | [1.60, 0.75, 0.72] top thickness 0.025 | top centre [0, 0.375, 0.7075] | walnut top, black steel legs
- A05 PRP_Monitor (bezel, screen, stand, back) | BLOCK | detailed | 27 in, screen 0.5977 x 0.3362 | screen centre [0, 0.40, 1.03] (low stand, set forward so D5 sees screen and keyboard close together) | thin black bezel, emissive screen
- A06 PRP_BiasLED | BLOCK | stylized | strip behind the monitor | blue glow on the back wall
- A07 HERO_Keyboard | BLOCK | detailed | case [0.392, 0.119, 0.018] tilted 3 deg | centre y 0.20 | game layout (64 keys, 19.05 mm pitch) + knob above the arrows; black caps with shine-through legends and per-key RGB
- A08 PRP_DeskLamp | BLOCK | detailed | arm reach ~0.55 | base [-0.68, 0.55, 0.72] | black architect lamp, warm bulb
- A09 PRP_Figure_Hatena | EXISTING (assets/characters/aiquiz_mascot/mascot_model.glb) | detailed | 0.12 tall | [0.52, 0.42, 0.72] | glossy vinyl toy
- A10 PRP_Shelf (+ books, plant) | BLOCK | stylized | shelf [0.70, 0.22, 0.02] | right wall, z 1.55 | background
- A11 PRP_Chair_P1 / PRP_Chair_P2 | BLOCK | detailed | seat top 0.48, back top 1.20 (the seated heads show above it), width 0.56 | seated position [-+0.34, -0.50, 0]; D1 position y = -0.70 | black PU gaming chairs
- A12 PROXY_P1 / PROXY_P2 | BLOCK | blockout | seated, leaning in to share the keyboard, head centre [-+0.236, -0.26, 1.22] | camera-gate stand-ins for phase 3 (P1 orange, P2 sky blue); hidden since phase 3
- A13 PEO_P1_Rig + PEO_P1_Block | BLOCK on an MPFB2 rig (built by build_tutorial_people.py) | detailed | ~1.65 m life-size blockman, no clothes, seated at the P1 chair | rig `mixamo` (52 bones incl. fingers); one mesh of rounded boxes per bone (weight 1), 4896 vertices | painted-resin orange (PlayerSkin.SLOT_COLORS head/body/limb), black eyes and mouth; left hand: index D, middle S, ring A, pinky Caps, thumb Space; right hand on the lap
- A14 PEO_P2_Rig + PEO_P2_Block | BLOCK on an MPFB2 rig | detailed | ~1.65 m life-size blockman, no clothes, seated at the P2 chair | rig `mixamo` | painted-resin sky blue; right hand: index ←, middle ↓, ring →, pinky and thumb hovering; left hand on the lap (reaches 8 9 0 in Godot)
- (superseded) the clothed MPFB2 humans of the first phase-3 pass (hoodies, cap, hood, hair) were replaced by the blockmen at the user's request
- chairs moved in phase 3: CHAIR_X 0.30, CHAIR_Y -0.40 (the arms could not reach the keys from -0.50)
- generation estimate/submission state: none. No credits are spent in phase 2.
- fidelity defaults: keyboard, desk, chairs, monitor = detailed (closest to camera in D5 / most visible in D1); walls, shelf = stylized; proxies = blockout.

SHOT
- active camera: CAM_D5 (the tutorial's base composition); review set CAM_D1, CAM_D3, CAM_D5.
- framing/lens/target (after the camera gate against the storyboard):
  CAM_D1 30 mm (0, -3.1, 1.72) -> (0, 0.15, 0.82);
  CAM_D2 35 mm (0, -2.6, 1.62) -> (0, 0.18, 0.84);
  CAM_D3 40 mm (0, -1.65, 1.58) -> (0, 0.25, 0.88);
  CAM_D5 45 mm (0, -0.98, 1.74) -> (0, 0.27, 0.82), f/4 focused on the keyboard (just above and behind the two heads; the heads and shoulders frame the left/right edges; moved back and up from (0, -0.80, 1.62) once the blockman heads were in);
  CAM_Intro (TD_Motion, exported) animates D1 -> D2 -> D3 -> D5 in one move;
  CAM_D7 40 mm (0, -0.45, 1.36) -> screen centre;
  CAM_D8 35 mm (0, -0.02, 1.03) square to the screen.
  Review-only: CAM_CheckKeyboard, CAM_CheckFigure.
- foreground, subject, background depth: D5 = out-of-focus heads/shoulders at the left/right edges, keyboard and hands (subject), monitor and wall glow behind; D1 = players and chairs, desk, monitor, back wall.

LOOK
- material roles and palette: walnut desk (warm brown), dark oak floor, navy wall paint (0.020, 0.032, 0.075), matte black plastics, black anodized keyboard case, near-black PBT caps, emissive legends/glow (P1 orange 1.0/0.42/0.08, P2 sky blue 0.25/0.72/1.0, idle cool white), black PU leather chairs, glossy vinyl figure (white/orange/navy).
- material route: NONE (procedural Principled node materials; baked for Godot in phase 5). The monitor screen uses refs/game_screen.jpg for look-dev only (Godot shows the live menu stage).
- texture scale in metres / coordinates: wood grain ~0.004 m features along X (desk) and along Y planks 1.2 x 0.19 m (floor); leather grain 0.002 m; Object/Generated coordinates in phase 2, UVs before baking.
- relief polarity / bump-only or true displacement: bump only.
- dielectric/metallic / roughness: wood 0.35-0.55 varying, wall 0.85, plastics 0.45-0.6, aluminium metallic 1 roughness 0.35, leather 0.4, vinyl 0.2.
- world/background: near-black navy world (no HDRI).

LIGHTING
- focal subject / secondary focal point / intended darkest region: D5 = keyboard glow and hands / monitor / floor and room corners behind the chairs. D1 = monitor and lamp pool on the desk / players' rim light / ceiling and corners.
- reference mood and time of day: night interior, ceiling light off (storyboard v0.1).
- environment route [EXISTING|GENERATE|NONE] / true HDR-EXR required: NONE / no.
- world-only and zero-world baseline: render both at reduced size.
- key direction / camera relation / softness: LGT_key_lamp - warm 3000 K spot from the lamp shade at the desk's left end, pointing down-right onto the desk; side key relative to all cameras; small source (radius ~0.03) for crisp but soft-edged pools.
- fill target and intended contrast: LGT_practical_screen - the monitor itself, a 0.60 x 0.34 cool 6500 K area light facing -Y; it rim-lights the players and fills the keyboard from the front; about 1-2 stops under the lamp pool on the desk.
- practical or implied source motivation: lamp bulb (emissive), monitor screen (emissive + area), bias LED behind the monitor (blue, on the wall), key legends and under-glow (emissive), no hidden fills except a very weak room bounce if shadows crush.
- reflection strategy for glossy/product assets: the screen and lamp give the highlights on keycaps, case and vinyl figure; no cards.
- gobos / flags / negative fill / atmosphere: none in phase 2; atmosphere off.
- color management and locked exposure: AgX, look "Medium High Contrast", exposure fixed after the first D5 render.

MOTION
- fps/frame range: 24 / 1-132 (5.5 s), built by build_tutorial_motion.py.
- object/camera/light beats: stand 1 -> sit start 20 -> mid-sit 38 -> seated 56 -> scooted in with the chair 84 -> hands on the keys 114 -> settle 132.
  Camera beats (CAM_Intro): D1 at 1-20, D2 at 52, D3 at 84, D5 at 118-132; lens 30 -> 35 -> 40 -> 45 mm (Godot drives the lens from the same beats).
  Keys: hips location, spine/neck/head lean, ankle and toe IK targets, wrist/aim/elbow-pole IK targets, hand roll and finger curls, chairs.
- rest poses and loops: frame 132 = the ready pose (D5); in Godot it is held with breathing and key presses on top.

ACCEPTANCE
- structural: every asset above exists once under its name; 64 KEY_ objects with key_id matching TutorialKeyboard; real dimensions match the table (desk top at 0.72, monitor 27 in, key pitch 19.05 mm); no stray default objects.
- motion: n/a in phase 2 (cameras only).
- visual: CAM_D1 and CAM_D5 solid renders read like storyboard D1/D5 before detailing; final Cycles renders show believable wood, plastic, leather and paint, no pink materials, legends readable at 1280x720 in D5.
- lighting: world-only / zero-world / key-only / grayscale renders viewed; lamp pool and screen rim clearly motivated; no clipped screen except the image itself; room falls off to dark navy.
```

## 状態

- 2026-11-02：パスポートを書いた（段階2の始め）。
- 2026-11-02：段階2を作った。ライブの Blender 5.1.2（Higgsfield の Blender 連携）で、`build_tutorial_desk.py` の `build("blockout")` → 構図の確認 → `build("detail")`。
  それまで開いていた `docs/pv/thumbnail/blender/t8_thumbnail.blend` は、ユーザーの指示で上書き保存してから新しいファイルに切り替えた。

### 構図の確認（色だけの描画）

- 1 回目：D5 はカメラが背もたれより後ろで低く、背もたれが左右の下をふさいだ。D1 は椅子が座った位置のままで比べられなかった。部屋の幅 3.6m は壁が見えすぎた。
- 2〜3 回目：D5 を 2 人の頭のすぐ上・少し後ろ（45mm）に寄せ、モニターを低く手前に（画面の中心 1.10 → 1.03、y 0.44 → 0.40）、キーボードを奥に（中心 0.16 → 0.20）した。
  背もたれの上端を 1.36 → 1.20 にして、座った人の頭が上に出るようにした。部屋の幅を 4.2m にした。D5・D3 が絵コンテと同じ並び（D5：上にモニター、真ん中の下にキーボード、左右の端に頭と肩）になったので作り込みへ進んだ。

### 作り込みで直したこと

- 画面の板に UV の層がなく、ゲームの絵が 1 色（空色）になっていた → UV の層を先に作る。
- キーボードの枠を中心で作ったまま手前の縁にそろえておらず、キーが枠から 6cm 奥にはみ出していた → 枠を奥へずらした。
- キーの文字が 1.3mm しかなかった（Noto Sans JP は同じ指定でも英字が小さく出る）→ 指定を約 2.6 倍にした（W の字の高さ 3.3mm）。
- 発光が強すぎて P1・P2 の色が AgX で白に寄った → キーの光を弱めて色を残した。
- ハテナの glb に材質のない多面体（ICO球）が入っていて体の下半分を隠していた → 読み込むときに外す。
- デスクライトのスポットライトが光る電球の球の内側にあり、光がふさがれていた → 電球は影を落とさない・ライトを電球の外へ。光の輪を D5 で見えるキーボードの左寄りへ向けた。
- ワールドのノード名が日本語（背景）で、名前で探すと見つからなかった → 種類で探す。

### 確かめたこと

- 物の数：キー 64（どの `key_id` もゲームの配列と一致）、キーの文字 63（Space は無地）、キーの下の光 64。TD_ のコレクションの外に物はなく、`.001` の重複もない。
- 寸法：机の天板の上面 0.72、画面 0.5977 × 0.3362、A と S のキーの間隔 0.01905。
- 光（D5、640×360）：デスクライトだけ・画面の光だけ・光る面だけ・ワールドだけ・ワールドなし・白黒を見た。デスクライトはキーボードと机に暖かい光の輪、画面の光は 2 人の頭と肩に冷たい輪郭、ワールドだけでは真っ暗（夜の部屋として正しい）。
- 見比べ：[phase2_review.jpg](phase2_review.jpg)（絵コンテ D1・D3・D5 と Blender の描画、キーボードとフィギュアの寄り）。描画は `artifacts/tutorial_desk/blender/`（git の対象外）。

### 段階3（人物の 1 回目）で直したこと

- 腕がキーに届かなかった（肩からキーまで 0.67m、腕は 0.5m）→ 椅子を机に寄せて内側へ、上半身を前に倒してキーボードへ少しひねる。
- P2 のフードを頭の形から作ると、口の中や耳までふくらんでとげになった → 頭を包む形を一から作る（顔の前と下をあけ、肩へ垂らす。真ん中の縫い目としわ）。
- MPFB2 の髪の補助の形は長い髪の大きさだった → 頭の後ろを斜めの平面で切った短い髪にする。
- 服の切り口が骨の重みでぎざぎざになった → 少し広めに選んでから平面で切り、首・袖口・裾にリブを付ける。
- しわを厚みの後にかけると、谷で布の内側が表へ突き抜けた → しわを先に、厚みを後に。
- パーカーの腰と背中に穴があいた → MPFB2 の骨の重みは合計が 1 にそろっていないので、割合に直して部位を決める。
- 手のひらが横を向いて指が上へ曲がった → 手のひらが下を向く向き（親指の側）を探してから指を曲げる。

### ブロックマン（段階3のやり直し）と動き・書き出し（段階4・5）で直したこと

- 人物を等身大のブロックマン（服なし）に作り替えた。上半身のひねりは箱だと大きく見えるので弱めた。D5 のカメラは頭が大きく入りすぎたので引いて上げた。
- P2 の左手を 8・9・0 の手前に置くと、前腕がキーボードの真ん中を隠した → 左手はふだん膝の上に置き、エモートのときだけ Godot で伸ばす。
- Godot で指先を測ると、指がキーの天面より 2〜4cm 下にもぐり、2 段奥のキーに乗っていた（手首をキーの 8.8cm 手前に置いたため、指の付け根がキーの真上に来ていた）
  → 手の置き方を作り直した。手のひらを下へ水平にし、中指の付け根をキーの 5.6cm 手前・4.2cm 上に置き、指ごとに指先の当たる所（指の箱のいちばん低い点）を
  キーの天面の真ん中へ合わせる（`place_typing_hand`）。MPFB2 の手は休みの姿勢で指が扇に開いているので、指は 1 本ずつキーの上の点へ向けてから曲げる。
- その計算が Blender との接続の待ち時間を超えた → 二分法の回数を減らし、手のひらを水平にする探し方を粗い → 細かいの 2 段にした（約 11 秒）。
- Blender の手続きの模様（木目・色のむら）は glb に入らず、白や粗さ 1 になる → Godot で名前ごとに作り直す（木目はシェーダー）。
- glb の動きは物ごとに分かれ、ほかの物の軌道も 1 コマずつ入る → Godot で、その物の経路に名前がある軌道だけを集めて 1 本にする。

### 確かめたこと（段階3〜7）

- Blender：最後のコマで、P1 の人差し指 D・中指 S・薬指 A・小指 Caps が天面から 0.4mm、真ん中から 0〜7mm。P2 の人差し指 ←・中指 ↓・薬指 → も同じ。
- Godot：同じ測り方で、取り込んだ後も同じ値（`tests/tutorial_keyboard_desk_unit.gd`）。キーを押すと指先が沈んだキーの天面に乗る。
- 本物のメインメニューから開いて、座る動き → 準備完了 → Space → モニターへ寄る → 本編、までを撮った（`artifacts/tutorial_keyboard_desk/menu_sheet.png`）。
