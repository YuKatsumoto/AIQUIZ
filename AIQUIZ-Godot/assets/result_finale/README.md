# スコアタワー・フィナーレ（勝敗演出）

ローカル2人・10問チャレンジで、2人とも生存してゴールしたときの勝敗演出。
旧版（ゴドーくんのバット演出 v3）を置き換える、一から作り直した演出。

二人の足元の「スコアタワー」が得点に比例してせり上がる。点数は同じ速さで数え上がるので、
低い方のタワーが先に止まり、高い方だけが最上段まで昇る。判定後、勝者は紙吹雪と王冠の中で
装備中のエモートを踊り、敗者のタワーは沈んで雨雲の下で膝をつく。引き分けは両方が頂上で踊る。

## タイムライン（実時間・秒）

| 秒 | 内容 |
| --- | --- |
| 0.0–0.4 | ゲームカメラから演出カメラへ移行。ゴールゲートを隠す |
| 0.4–2.0 | 二人がタワーの台座へ歩く。審判ゴドーくんはチェッカーフラッグを持って台座の奥で待機 |
| 2.0–2.45 | 振り向きジャンプで台に乗り、台が0.35 mポップ。タイトル「スコアタワー」 |
| 2.5 / 3.3 | 正解数 → ×残りHP をカードに表示 |
| 4.1–6.3 | 合計点を同じ速さでカウントアップしながらタワーが上昇（勝者2.6 mまで）。低い方は途中で止まりリング演出 |
| 6.3–6.9 | 静止して祈る（審判は旗を真上に） |
| 6.9 | 判定。「P1 WIN!」/「DRAW!」、AEバースト、紙吹雪砲、花火、スポットライト |
| 7.3–7.66 | 王冠が落ちて勝者の頭（帽子の本体）に着地 |
| 7.4–8.8 | 敗者のタワーが沈み、残念トロンボーン。7.55 雨雲、7.9 雨 |
| 7.6〜 | 勝者は装備エモート（1枠目、未設定はシリーダンス）を踊り続ける |
| 9.15–9.4 | 敗者がひざまずく（orz） |
| 11.2 | もう一度・履歴・メニューを操作可能。以後も演技は9.6–11.2秒をループ |

判定前のカメラは左右対称（P1左・P2右）で結果を先に見せない。判定後は勝者側へ回り込み、
P2勝利ではステージとカメラをX反転する。得点は `正解数 × 到着時HP`。演出はHP・生死を変更しない。

## 素材

| ファイル | 内容 |
| --- | --- |
| `score_tower.glb` | タワー1基（床カラー・昇降台・柱・紙吹雪砲。`TowerLift` を上下させる。`FIN_TowerAccent` はGodotでプレイヤー色に着色） |
| `crown.glb` / `rain_cloud.glb` | 王冠、しょんぼり雨雲（`PRP_CloudRain` が雨の発生位置） |
| `referee_finale.glb` | ゴドーくん＋旗。アニメーション `FinaleWin` / `FinaleDraw` |
| `finale_motion.json` | Blenderの評価済みデータ60fps：人物16関節＋握り、タワー曲線、王冠・雲、勝敗/引き分けカメラ |
| `hud_motion.json` | AEのHUDレイアウトと全キーの60fpsサンプル |
| `fx/burst`, `fx/lock_ring` | AEで描画した白い発光エフェクトの連番（Godotで色付け・加算合成） |

ゴドーくんはぬいぐるみの頭と胴が一体のメッシュで、顔も `DEF-head` / `DEF-hips` に乗っている。
これらのボーンを曲げたりリグを非一様スケールすると顔が歪むため、体の向き・傾き・ジャンプは
リグ全体を剛体として動かし、曲げるのは腕だけにしている（傾きは最大8°）。実機テストで
本体ボーンが休止姿勢から動かないことを検査している。

## 編集可能な制作データ（`source/`、Godotの読み込み対象外）

- `AIQUIZ_ScoreTowerFinale.blend` — Blender 5.1。シーン `AIQUIZ_ScoreTowerFinale`（0–672フレーム、60fps）。
  人物・審判は旧チェックポイントから複製したリグ。`checkpoints/` に工程ごとの復旧用コピー。
- `build_set.py` — タワー・王冠・雨雲・旗・プレビュー床と照明を生成（再実行で作り直し）。
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

## Godot実装

- `scripts/world/result_ceremony_director.gd` — ステージ・エフェクト・照明・効果音の拍を統括。
- `scripts/world/result_finale/result_finale_stage.gd` — タワー、人物（関節・握り・歩行からの受け渡し）、王冠、雨雲、審判。
  昇降台は常に `PAD_CLEARANCE`（2 cm）持ち上げる。台の天面と床リング（ハザード縞）の天面がどちらも
  `COLLAR_H`（0.05 m）で作られており、上昇前は同じ深度面でちらついていたため。
- `scripts/world/result_finale/result_finale_motion.gd` — モーション評価と得点→タワー高さ・カウント・ロック時刻の規則。
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

オプション: `case=p2` / `case=draw`、`fps=30` / `fps=120`、`quality=low`、`hats`、`sizes`、`routes`、
`record`（30fpsで連番保存）、`audible`、`all_emotes`、`emote=<id>`。
実機スクリーンショット・動画は `artifacts/result_finale/`（`runtime/`、`video/`）。

旧演出（審判のバット・ラグドール・線で組む勝利文字）のスクリプトとテストは
`artifacts/result_ceremony/pre_finale_20260925/` に、置き換え前の状態のまま退避している。
