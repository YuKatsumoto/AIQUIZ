# スコアタワー・フィナーレ（勝敗演出）

ローカル2人・10問チャレンジで、2人とも生存してゴールしたときの勝敗演出。
旧版（ゴドーくんのバット演出 v3）を置き換える、一から作り直した演出。

二人の足元の「スコアタワー」が **1点で1段（1段 0.3 m）** ずつせり上がる。高さは相手の点に関係なく自分の得点だけで決まり
（満点35点＝35段≈10.9 m、28点≈8.8 m、0.5点の端数は段の途中まで）、点数は同じ速さで数え上がるので低い方のタワーが先に止まる。判定後、勝者は紙吹雪と王冠の中で
装備中のエモートを踊り、敗者のタワーは沈んで雨雲の下で膝をつく。引き分けは両方が頂上で踊る。

## タイムライン（実時間・秒）

| 秒 | 内容 |
| --- | --- |
| 0.0–0.4 | ゲームカメラから演出カメラへ移行。ゴールゲートを隠す |
| 0.4–2.0 | 二人がタワーの台座へ歩く。審判（マスコットのハテナ）は両手にチェッカーフラッグを持って（下げたまま）台座の奥で待機 |
| 2.0–2.45 | 振り向きジャンプで台に乗り、台が0.35 mポップ。タイトル「スコアタワー」 |
| 2.5 / 3.3 | 正解数 → ×残りHP をカードに表示 |
| 3.5 / 3.92 | 生存ボーナス「+0.5」がHP値に合体（脱落者は表示なし） |
| 4.1–6.3 | 合計点を同じ速さでカウントアップしながらタワーが上昇（1点ごとに柱の帯が1本せり出す）。低い方は途中で止まりリング演出 |
| 6.3–6.9 | 静止して祈る（審判は両方の旗を低く前に構えて震える） |
| 6.9 | 判定。「P1 WIN!」/「DRAW!」、AEバースト、紙吹雪砲、花火、スポットライト。審判は勝者側の旗を上げる（引き分けは両方） |
| 7.3–7.66 | 王冠が落ちて勝者の頭（帽子の本体）に着地 |
| 7.4–8.8 | 敗者のタワーが沈み、残念トロンボーン。7.55 雨雲、7.9 雨 |
| 7.6〜 | 勝者は装備エモート（1枠目、未設定はシリーダンス）を踊り続ける |
| 9.15–9.4 | 敗者がひざまずく（orz） |
| 11.2 | もう一度・履歴・メニューを操作可能。以後も演技は9.6–11.2秒をループ |

判定前のカメラは左右対称（P1左・P2右）で結果を先に見せない。判定後は勝者側へ回り込み、
P2勝利ではステージとカメラをX反転する。Blenderのカメラは旧最上段2.6 m前提なので、どちらかのタワーが2.6 mを超えると
3.6 mまでの間に次のショットへ移る（`result_finale_camera.gd`）。
審判は旗を両手に1本ずつ持ち、判定前（0–6.9秒）のキーは3つのアニメーション `FinaleWin`（勝者が審判の右手側＝P1のレーン）・
`FinaleWinP2`（勝者が左手側）・`FinaleDraw` で共通なので、どの手に旗があるか・どちらを向くかで結果が先に分からない。
判定で勝者側の旗だけを上げ、もう一方は下げたまま（引き分けは両方を上げる）。
審判は反転したまま描かない：反転した変換の下のスキンメッシュは影のある画質（高・最高）で光の当たり方が裏返り、体の正面が暗い青になるうえ、
旗を上げる手も入れ替わってしまう。P2 勝ちでは `ResultFinaleReferee.unmirror` が審判のルートでステージの反転を打ち消し、
P2 側へ旗を上げる `FinaleWinP2` を再生する。テストが全場面で本体の行列式が正であること、判定前は2本の旗が同じ高さで、
判定後は勝者側の旗が上がっていることを確かめる。
スコアタワー（床カラー・昇降台・段・紙吹雪砲）は影を落とさず、影も受けない（`ResultFinaleStage._disable_shadows`）。
- タワーが伸びている間（と引き分け全体）：**正面の低い位置から両者を収める2ショット**。両者の台から頭上2.4 mまでが
  タイトル帯（上20%）とスコアカード帯（下28%）を避けて収まる最短距離まで下がる（P1左・P2右のまま）。
- 勝敗あり：タワーが止まった後（先頭のロックと跳ねが収まる6.45秒）から7.25秒にかけて、
  **敗者のすぐ横（前・外側、腰の高さ）から勝者を見上げる**ショットへ移る。敗者の頭と肩、勝者の全身（王冠込み）が
  タイトル帯（上20%、6.2–6.5秒で消える）とスコアカード帯（下28%、7.55–8.2秒で右上へ移る）を避けて収まるよう、
  まず敗者から3 mのままレンズを広げ（55–76°）、足りないときだけ下がる。敗者のタワーが沈むとカメラも一緒に下り、
  膝をつく（9.15秒）と視点を0.4 mまで下げて伏せた頭も収める。勝者は画面の上、敗者は下の手前（P1勝ちで勝者が左）。

得点は生存者が `正解数 × (到着時HP + 0.5)`（0.5単位のまま）、脱落者（幽霊として参加）は `正解数`。
どちらかの合計に0.5があるときは、カウントアップ中も両方を小数1桁（12.0, 12.5…）で表示し、最終値の右端に数字をそろえて揺れを防ぐ。演出はHP・生死を変更しない。

## 素材

| ファイル | 内容 |
| --- | --- |
| `score_tower.glb` | タワー1基（床カラー・昇降台・柱・紙吹雪砲。`TowerLift` を上下させる。`FIN_TowerAccent` はGodotでプレイヤー色に着色）。GLBの柱（0.5 m帯・3.2 m）は非表示にし、Godotが下の `tower_tiers.glb` を36段積んだ `TierColumn` を昇降台の下に付ける |
| `tower_tiers.glb` | 1点＝1段の段モジュール（高さ0.3 m、上端0）。`TWR_Tier`：角を丸めた白いドラム＋細く奥まった発光リング（`FIN_TowerAccent`、プレイヤー色）。`TWR_TierMilestone`：5段ごとのリングを張り出した金帯（`FIN_TierGold`、Godotでトイゴールド）に替えたもの |
| `crown.glb` / `rain_cloud.glb` | 王冠、しょんぼり雨雲（`PRP_CloudRain` が雨の発生位置） |
| `referee_finale.glb` | 審判の骨格（16ボーン）＋両手の旗（`PRP_Flag` 右手・`PRP_FlagL` 左手）。アニメーション `FinaleWin` / `FinaleWinP2` / `FinaleDraw` |
| `finale_motion.json` | Blenderの評価済みデータ60fps：人物16関節＋握り、タワー曲線、王冠・雲、勝敗/引き分けカメラ |
| `hud_motion.json` | AEのHUDレイアウトと全キーの60fpsサンプル |
| `fx/burst`, `fx/lock_ring` | AEで描画した白い発光エフェクトの連番（Godotで色付け・加算合成） |

審判の体はマスコット（`assets/characters/aiquiz_mascot/`）で、GLB内の旧プラシュ本体は取り込まず（`skip_import`）、実行時に `MascotDresser` が同じ骨格へ着せる。体は頭と胴が一体のメッシュで、顔も `DEF-head` / `DEF-hips` に乗っている。
これらのボーンを曲げたりリグを非一様スケールすると顔が歪むため、体の向き・傾き・ジャンプは
リグ全体を剛体として動かし、曲げるのは腕だけにしている（傾きは最大8°）。実機テストで
本体ボーンが休止姿勢から動かないことを検査している。

## 編集可能な制作データ（`source/`、Godotの読み込み対象外）

- `AIQUIZ_ScoreTowerFinale.blend` — Blender 5.1。シーン `AIQUIZ_ScoreTowerFinale`（0–672フレーム、60fps）。
  人物・審判は旧チェックポイントから複製したリグ。`checkpoints/` に工程ごとの復旧用コピー。
- `build_set.py` — タワー・王冠・雨雲・旗（右手の旗と、それをリグ空間でX反転した左手の旗 `mirror_flag`）・プレビュー床と照明を生成（再実行で作り直し）。
- `build_tower_tiers.py` / `AIQUIZ_TowerTiers.blend` — 段モジュール（`tower_tiers.glb`）の生成・書き出しと確認レンダー
  （`artifacts/result_finale/tower_tiers_preview.png`）。開いているBlenderを使わず、プロジェクトルートから
  `& "C:\Program Files\Blender Foundation\Blender 5.1lender.exe" -b --factory-startup --python assets/result_finale/source/build_tower_tiers.py`
  で作り直せる。旧来の柱は細かい紺枠パネルが30段以上並ぶと網目状に見えて気味が悪かったため置き換えた。
- `poses.py` / `rig.py` — ブロック人形のポーズ集と適用。
- `animate_finale.py` — 振付・タワー昇降・王冠・雨雲・審判・カメラのキー（時刻表はここ）。
- `export_finale.py` — GLB 4種と `finale_motion.json` を書き出す（開いている.blendのパスは変えない）。
- `render_sheet.py` / `contact_sheet.py` — 確認用レンダーとコンタクトシート。
- `AIQUIZ_ScoreTowerFinale.aep` — After Effects 2026。`FINALE_HUD_Win` / `FINALE_HUD_Draw`（1280×720、60fps）と
  `HUD_*` プリコンポ（ネイティブの文字とシェイプ）、`FX_Burst` / `FX_LockRing`。
- `build_hud.jsx` — 上記AEコンポジションの構築。`sample_hud.jsx` — `hud_motion.json` の書き出し。
  `render_fx.jsx` — FX連番の書き出し。`ae_run.mjs` — HiggsfieldローカルAEブリッジ経由で .jsx を実行。
- `SCENE_PASSPORT.md` — Blenderシーンの仕様。

### 再書き出し

Blender（Higgsfield Blenderコネクタ等で開いたセッション）で：

```python
ns = {}; exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/result_finale/source/animate_finale.py", encoding="utf-8").read(), ns); ns["animate_all"]()
ex = {}; exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/result_finale/source/export_finale.py", encoding="utf-8").read(), ex); ex["export_all"]()
```

After Effects（AEを起動した状態でプロジェクトルートから）：

```powershell
node assets/result_finale/source/ae_run.mjs assets/result_finale/source/sample_hud.jsx
node assets/result_finale/source/ae_run.mjs assets/result_finale/source/render_fx.jsx
```

AEのキーやレイアウトを手で調整した場合は `sample_hud.jsx` だけ再実行すればGodotに反映される
（`build_hud.jsx` はコンポジションを作り直すので手作業の調整が消える）。

生存ボーナス「+0.5」（HP値の下から金色チップが上がり、3.92秒にHP値へ合体）は `build_hud.jsx` の
`buildHpBonus` に含まれる。既存のAEPへ後から入れるときは `add_hp_bonus.jsx` を実行してから `sample_hud.jsx`
を実行する（何度実行しても同じ結果）。Godotは `HpBonusText` の最後の不透明度キーを合体時刻として読み、
そこでHP表示を「2」→「2.5」に切り替える。脱落者のカードではボーナスのレイヤーを隠す。

## Godot実装

- `scripts/world/result_ceremony_director.gd` — ステージ・エフェクト・照明・効果音の拍を統括。
- `scripts/world/result_finale/result_finale_stage.gd` — タワー、人物（関節・握り・歩行からの受け渡し）、王冠、雨雲、審判。
  昇降台は常に `PAD_CLEARANCE`（2 cm）持ち上げる。台の天面と床リング（ハザード縞）の天面がどちらも
  `COLLAR_H`（0.05 m）で作られており、上昇前は同じ深度面でちらついていたため。
- `scripts/world/result_finale/result_finale_motion.gd` — モーション評価と得点→タワー高さ（`TIER_HEIGHT` / `TIER_POINTS_HALF`）・カウント・ロック時刻の規則。
- `scripts/world/result_finale/result_finale_camera.gd` — 高いタワー用のショット（敗者の横から見上げる／引き分けは正面2ショット。`camera_controller.gd` が焼き込みカメラと混ぜる）。
- `scripts/world/result_finale/result_finale_effects.gd` — 紙吹雪砲・紙吹雪の雨・花火・スポットライト・雨。
- `scripts/world/result_finale/result_finale_referee.gd` — 審判GLBの生成と再生（ゴール手前の待機にも使用）。
- `scripts/ui/result_finale_hud.gd` — AEレイヤーを1対1でControlにして再生（数字・色・日英の文言だけGodotで差し込む）。
- `scripts/ui/result_winner_dance.gd` — 装備エモートの転写（7.6秒開始、以後ループ）。
- 効果音は `AudioManager.play_result_cue()`（台のポップ、上昇ドラムロール、シンバル、紙吹雪、王冠、残念トロンボーン）と雨のループ。すべて手続き生成。

## 検証

```powershell
& $GODOT --headless --path . --script tests/result_ceremony_bootstrap.gd
& $GODOT --headless --path . --script tests/result_ceremony_bootstrap.gd -- emote_orientation
& $GODOT --path . --script tests/result_ceremony_bootstrap.gd --fixed-fps 60 -- runtime case=p1 fps=60 out=check
```

オプション: `case=p2` / `case=draw` / `case=landslide`（35対3、敗者の横からの見上げカメラ）、`fps=30` / `fps=120`、`quality=low`、`hats`、`sizes`、`routes`、
`record`（30fpsで連番保存）、`audible`、`all_emotes`、`emote=<id>`、
`reel`（メニューの LED のための試合の記録と録画 `MatchReel` を実際の試合と同じく動かす。保存先は `user://test_ceremony_reel`）。
実機スクリーンショット・動画は `artifacts/result_finale/`（`runtime/`、`video/`）。

旧演出（審判のバット・ラグドール・線で組む勝利文字）のスクリプトとテストは
`artifacts/result_ceremony/pre_finale_20260925/` に、置き換え前の状態のまま退避している。
