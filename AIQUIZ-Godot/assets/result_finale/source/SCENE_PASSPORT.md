# Scene Passport — スコアタワー・フィナーレ

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-lighting-camera, blender-animation, blender-audit-finalize

## SCENE
- intent: ローカル2人・10問モードの勝敗演出を一から作り直す。二人の足元のタワーが得点に比例してせり上がり、勝者は王冠と紙吹雪、敗者は沈むタワーと雨雲。
- deliverable: Godot用GLB（タワー・王冠・雨雲・審判+旗）、`finale_motion.json`（人物関節・カメラ・王冠・雨雲・タワー曲線）、編集可能な`.blend`コピー
- units: metres; axes: right-handed Z-up
- render: EEVEE, 1280×720, 60fps, frame 0–672（0–11.2秒）
- dynamic: yes

## HIERARCHY
- collection: `FINALE_Cast`（WIN_/LOSE_ブロック人形、RIG_Referee+HERO_GodotPlush）, `FINALE_Set`（TWR_*, PRP_*）, `FINALE_Camera`, `FINALE_Light`
- parent: `TWR_<W|L>_Root → TWR_<W|L>_Lift → 天板/柱/砲`、`PRP_Crown → WIN_hat_mount`基準、`PRP_Cloud → LOSE_Actor`基準、`PRP_Flag → DEF-hand.R`
- protected: 既存 `Scene`（Cube/Light/Camera）と旧チェックポイントblendは変更しない。キャラクターは旧checkpointから複製して取り込み、旧アニメーションは新シーン上で消去済み

## ASSETS
- A01 WIN_/LOSE_ ブロック人形 | [EXISTING] | detailed | 約0.9×0.4×2.2 m | x=∓2.2, y=0, z=1.32+h | ルート=Actor | 勝者/敗者
- A02 RIG_Referee + HERO_GodotPlush | [EXISTING] | detailed | 1.8×1.0×1.63 m | (0, 1.0, 0) | 審判
- A03 TWR スコアタワー ×2 | [BLOCK] | stylized | 天板φ1.7×0.2、柱φ1.25×3.2、床カラーφ2.1×0.1 | x=∓2.2 | Root=床面 | 得点で昇降
- A04 PRP_Crown | [BLOCK] | stylized | φ0.46×0.30 m | 勝者頭上 | 王冠
- A05 PRP_Cloud | [BLOCK] | stylized | 1.2×0.7×0.55 m | 敗者頭上 | 雨雲
- A06 PRP_Flag | [BLOCK] | stylized | 棒0.85 m、旗0.46×0.32 m | 審判右手 | チェッカーフラッグ
- 生成(GEN)は使用しない（クレジット消費なし）

## SHOT
- active camera: `CAM_FinaleWin`（P2勝利はGodot側でX反転）, `CAM_FinaleDraw`
- 6.9秒までは左右対称（x=0）でP1左・P2右。判定後に勝者側へ回り込み、低い位置から見上げる
- foreground: 勝者タワー / subject: 勝者 / background: 観客席・空・敗者

## LOOK
- タワー: 白い本体、紺のトリム、プレイヤー色の発光帯（Godotで着色）、黄黒ハザード
- 王冠: 金(metal 0.9, rough 0.25)＋赤・青の宝石 / 雨雲: 青灰 / 旗: 白黒市松＋銀の棒
- glTFで失われない単色＋emissiveのみ

## LIGHTING
- Blenderはプレビュー用。実機の照明はGodotの既存ステージ＋演出用スポット（勝者）
- key: 右前上方のエリアライト / fill: 左 / rim: 後方

## MOTION（秒・60fps）
- 0–2.0 歩行（ゲーム側）。2.0–2.45 振り向きジャンプで台へ、台が0.35 mポップ
- 2.5 正解数、3.3 残りHP、4.1–6.3 同じ点数速度で上昇（勝者は2.6 mまで、敗者は途中で停止）
- 6.3–6.9 静止・祈り。6.9 判定：勝者ジャンプV字、敗者ショック
- 7.3–7.7 王冠落下→7.95着地バウンド。7.4–8.9 敗者の台が沈む。7.6 雨雲。7.5〜 勝者は装備エモート
- 8.9–9.5 敗者がひざまずく。10.4 カメラ静止。11.2 操作可能（引き分け10.6）
- 引き分け: 両者WIN系の動き、両タワー最上段、王冠・雨雲なし

## ACCEPTANCE
- structural: 名前重複なし、GLBのマテリアルが解決、タワーのRootが床面z=0
- motion: 足が天板に接地（誤差<3 cm）、王冠が頭上で着地、雨雲が敗者頭上、カメラが被写体を失わない
- visual: 判定前は左右対称、判定後は勝者が最大・敗者も画面内、ハザード・発光帯が読める
