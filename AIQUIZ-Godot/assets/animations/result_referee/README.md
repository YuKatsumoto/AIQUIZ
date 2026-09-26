> 旧版（v3）。現在の勝敗演出は [スコアタワー・フィナーレ](../../result_finale/README.md)。この審判・バット演出はゲームから外し、スクリプトは `artifacts/result_ceremony/pre_finale_20260925/` に退避した。以下は記録として保持。

# ゴドーくんの審判フィニッシュ v3

ローカル2人・10問チャレンジで、2人とも生存してゴールした場合の勝敗演出。
勝者が設定エモートの1枠目を踊りながら手前へ出てカメラを向く。その奥でゴドーくんが敗者へ向き直り、フルスイングで後方上空へ打ち出す。カメラは床上16cmまで下がり、X軸の見上げを約28度にする。

## 時間と動作

| 実時間 | 内容 |
| --- | --- |
| ゴール前〜2秒 | ゴドーくんはゴールの奥ですでに待機。2人がそこへ歩いて整列する |
| 2〜3.08秒 | 歩行姿勢から0.18秒で演出用姿勢へ接続。審判は握ったバットを前へ出す |
| 2〜6秒 | 正解数→残りHP→合計点を表示 |
| 7.06〜7.43秒 | 審判が小刻みに踏み込み、敗者へ体と顔を向ける |
| 6.05秒〜 | 勝者が装備中の実際のFBXエモートを開始し、1.65m手前へ出る |
| 6.68〜7.22秒 | カメラが下がって強く見上げる。得点カードは空いている上隅へ移動 |
| 7.43〜7.88秒 | カメラが止まった後に振りかぶり、腰を回してフルスイング |
| 7.88 / 7.96秒 | 打撃 / 短いヒットストップ後の発射。バットの接線と同じ後方へ飛ぶ |
| 8.78秒 | 勝者の奥で敗者が玩具のパーツへ分かれ、炎・衝撃波・薄い煙が出る |
| 9.15〜10.3秒 | 勝者のエモートが徐々に減速し、敗者と同時に静止する |
| 11.2秒〜 | もう一度・履歴・メニューを操作可能にする。引き分けは従来どおり10秒 |

P2勝利は構図と表示位置を反転する。引き分けでは3人の画角を保ち、打撃・飛行・爆散・勝者のダンスを行わない。得点は正解数×到着時HP。表示上の爆散でHP・生死・他モードの挙動は変更しない。

## 編集可能な制作データ

- `source/AIQUIZ_RefereeFinish_WinnerStrokes_20260924.aep`: P1/P2の `Final winner` を一画ごとの編集可能なテキスト＋マスクに分けたAE版。9.40〜10.53秒に画面外から順番に飛び込み、10.67秒で元の文字へつなぎ、既存の11.47秒の勝利パルスを保持する。元のAEレイヤーは非表示で残している。
- `source/build_winner_strokes.mjs`: 上記のマスク、飛来方向、キーの生成記録。元のAE文字の実レンダーを測定して作成した。
- `source/checkpoints/hero_finish_verified_20260924.blend`: 検証済みv3の復旧用コピー。Blender 5.1、既存の`AIQUIZ_RefereeFinish_v2`シーン名を維持。旧アクションも保持。
- `source/build_hero_finish.py`: 既存リグ、手・足のIK、バット、プレイヤーの移動軌道、カメラを編集可能なキーとして再構成する。
- `source/hero_rest_pose.json`: 改修前に記録したプレイヤーの基準姿勢。
- `source/export_hero_finish.py`: 評価済みGLBとJSONを出力する。開いているblendの保存先は変更しない。
- `source/audit_hero_finish.py`: 全601フレームの接触・向き・カメラ角度を検査し、主要ポーズと照明分離画像を出力。
- `source/hero_low_angle_reference_20260924.png`: 制作前に生成した構図参考画像。プロンプトは同名の`.prompt.json`。
- `referee.glb`: 実際の審判とバット、握り手、足のIKをベイクした動作。
- `motion.json`: 44本のプレイヤー関節・移動軌道と透視投影カメラ。60Hz、0〜546フレーム。得点・打撃・発射・爆散の時刻も格納。

Godot実行時はカメラを元の時計で再生し、人物とバットの動作を6.0秒で1.2秒保留してから続ける。上表の打撃時刻は実機の時刻であり、`motion.json`内の制作時刻より1.2秒遅い。元のBlenderキーやGLBは変更していない。

Higgsfield BridgeとBlender MCPが同じBlenderインスタンスを指すことを確認し、両方を使って制作・検証した。元の`AIQUIZ_RefereeFinish_v2.blend`は上書きせず、開いているシーンと上記復旧用コピーに編集を保持している。旧AEP、旧動画、`export_stage.py`などはv2資料として残す。v3の書き出しには`export_hero_finish.py`を使用する。

Blender上の勝者は移動と構図を確認するためのポーズ。ゲームでは`ResultWinnerDance`が設定中のFBXを評価し、その関節動作・跳躍をブロック人形へ転写する。全16種に対応し、スリラーは4本の連続クリップを使う。カメラへの顔の向きと床への接地を整える。エモート未設定時は既存の勝利用フォールバックであるシリーダンスを使用する。

## Godot実装

`result_hero_presentation.gd`が審判と2人を実際の`GameWorld`に配置する。背景・ベルト・観客席・天候・通常マテリアルをそのまま使う。`camera_controller.gd`はBlenderのカメラを同じ時刻で評価する。

`result_referee_effects.gd`は既存のExplosion / Impact / Smokeを専用コピーとして扱い、粒子とシェーダーの時間を結果時計で制御する。空中の爆散を隠す地面用DustとShadowCasterを抑制し、元のVFX素材は変更しない。短い腕を無理に伸ばさず、左手は登場時からバットを握り、右腕は動作の釣り合いを取る。

勝利表示の `P1  WIN` / `P2  WIN` は `result_winner_stroke_assembly.gd` が元のフォントをSubViewportで描き、文字の各画をPolygon2Dで切り出して6.68〜7.85秒に画面外から順番にはめ込む。結果確定後は既存のLabelへ戻るため、文字形・色・アウトラインと後半の強調動作を維持する。引き分け表示は従来のまま。

`result_loser_ragdoll.gd` は打撃時に敗者の姿勢から14個のRigidBody3Dと13個の受動関節を作成する。7.96秒の発射後は胴体・頭・両手足の回転を物理演算へ渡す。全身の重心には共通の並進補正を加え、元の背景への飛行軌道を維持する。関節姿勢をアニメーションで駆動しない。元の指・つま先・帽子を含む表示用関節へ物理姿勢を反映する。8.78秒に関節を解放して既存の玩具爆散へ続き、10.3秒で全物理体を静止させる。ゲーム本体のHP、生死、通常のラグドールは変更しない。

リトライ・メニュー復帰は既存の暗転が完了するまで結果を保持する。初期化時の追加は親シーンの準備後に行い、リトライでも演出用ノードを正しく構築する。

## 検証とプレビュー

勝者エモートは設定画面・通常プレイと同じFBXのX軸補正を使用する。2P勝利時のステージ反転は人物の手足へ継承せず、カメラへの向きと移動をワールド座標で計算する。`emote_orientation`テストは全16種・両プレイヤーの152ポーズを設定画面の17関節と照合する。実機の`all_emotes`にも同じ照合を追加済み。

ローカル2Pの10問モードでは、結果演出と同じゴドーくんのモデルをゴールから3.7m奥に待機させる。選手が到着すると待機モデルを隠し、同じ位置・同じポーズの結果用モデルへ引き継ぐ。選手が歩いている間は固定位置で迎え、2.15秒から既存のバット動作へ続く。

`artifacts/result_ceremony/hero_low_angle_20260924/`に実機動画、スクリーンショット、接触監査、実行ログを保存。`ACCEPTANCE.md`に検証範囲と既存警告を記載。

```powershell
& $GODOT --headless --path . --script tests/result_ceremony_bootstrap.gd
& $GODOT --headless --path . --script tests/result_ceremony_bootstrap.gd -- referee_unit
& $GODOT --headless --path . --script tests/result_ceremony_bootstrap.gd -- emote_orientation
& $GODOT --path . --script tests/result_ceremony_bootstrap.gd --fixed-fps 60 -- runtime hero case=p1 fps=60 quality=high record out=preview
```

検証オプション: `case=p2` / `case=draw`、`fps=30` / `fps=120`、`quality=low`、`emote=19`、`all_emotes`、`hats` / `all_hats`、`sizes`、`routes`。

## 素材と出典

- 既存Godotぬいぐるみ、ブロックプレイヤー、帽子、設定用ダンスFBX。
- Effects Collection Vol.1の既存`vfx_explosion_02` / `vfx_impact_01` / `smoke_vfx_01`。
- Kenney Impact Sounds / Interface Sounds (CC0)。ライセンスは`assets/audio/sfx/result_toon/Kenney_*_License.txt`。
- カウント・爆発低音・勝利音は既存AudioManagerの生成音。有料生成・新規購入は行っていない。
