# 連続正解の炎バッジ

2P 対戦カード（`scripts/ui/duo_player_status_card.gd`）の正解数の右に、炎のループと連続正解数を出す。
右上にあった「🔥 N連続正解!」ラベルはこれに置き換えて廃止した。

## ファイル

- `flame_sheet.png`: 炎の 1 秒ループ。30 fps × 30 コマを 128 x 160 のセル 6 x 5 枚に詰めたもの（ストレートアルファ）。
- `motion.json`: 点火・カウントアップ・消火の動き。AE のキーを 60 Hz でサンプリングした曲線。
- `source/AIQUIZ_Streak_Flame.aep`: 編集用の After Effects 2026 プロジェクト。
- `scripts/ui/streak_flame_badge.gd`: 上の 2 つを再生するバッジ本体。

## 表示ルール

- 2 連続から点火する（リングが広がり、炎が 1.22 倍まで伸びて落ち着く）。数字の横に「連続」（英語 UI では `streak`）。
- 連続が伸びるたびに炎と数字がポップする。5 連続・10 連続で炎がそれぞれ一回り大きくなる。
- 不正解、または先着で取られる・海に落ちているなどでその問題を正解できなかったら、そのプレイヤーの連続は 0 に戻り、炎が縮んで消える。
- 正解数が長くて幅が足りないときは「連続」を省き、それでも足りなければ「正解」を隠して正解数の直後に詰める。
- 連続正解は `QuizGameState.current_streak`（P1）と `player2_streak`（P2）。オンライン同期（`st2`）とリプレイ（問題ごとの正解者から再構成）にも対応。

## AE ソースの構成

`Streak_Flame_Loop`（256 x 320, 30 fps, ちょうど 1.0 秒, 根元 (128, 282)）

- `CTRL` のスライダー `Turbulence` / `Wave Height` / `Glow` で揺らぎと光り方をまとめて調整できる。
- `Outer Shape` / `Mid Shape` / `Core Shape`: 主先端と左右の副先端を持つ炎のパス。4 ポーズを 0.25 秒おきにキーし、-0.25 秒と 1.25 秒にも折り返しのキーを置いて、ループの継ぎ目で速度が途切れないようにしている。
- 各シェイプに Turbulent Displace（展開 = time×360、サイクル展開 1 周）と Wave Warp（速度 1、下端固定）。どちらも 1 秒で一周するので継ぎ目が出ない。
- `Outer Color` / `Mid Color`: グラデーション（下が黄、上が朱）の平面を、シェイプのアルファでトラックマット。
- `Tongue A/B`（0.5 秒周期で先端から離れる炎）、`Ember 1-3`（1 秒周期の火の粉）、`Heat Halo`、調整レイヤー `Bloom`（グロー）。

`Streak_Badge_Events`（400 x 200, 60 fps）は対戦カード上段の 2 倍サイズのモック。点火 0.30–0.78 秒、カウントアップ 1.40–1.74 秒、消火 3.00–3.40 秒。

## 作り直し

開いている AE で実行する（未保存の変更があるプロジェクトが開いていると止まる）。

```
node tools/title_logo_ae/ae_run.mjs tools/streak_flame_ae/build_streak_flame.jsx
node tools/title_logo_ae/ae_run.mjs tools/streak_flame_ae/render_streak_flame.jsx
python tools/streak_flame_ae/pack_streak_flame.py
```

`render_streak_flame.jsx` は `artifacts/streak_flame/frames/` に TIFF（アルファ付き）連番、`artifacts/streak_flame/ae_badge_preview.mp4`、`motion.json` を書き出す。
`pack_streak_flame.py` は乗算済みアルファの縮小で縁の黒ずみを防ぎ、`flame_sheet.png` と確認用の `artifacts/streak_flame/loop_contact.png` を作る。

注意: スクリプトで作ったテキストレイヤーが選択されたまま残ると、AE が「内部確認に失敗しました (no current context)」を出して以降のスクリプトを受け付けなくなる。ビルドの最後で全レイヤーの選択を外しているのはそのため。

## 検証

```
Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/streak_flame_bootstrap.gd --fixed-fps 60
```

実際の壁通過で 1 連続（消灯のまま）→ 2 連続（2 人とも点火）→ P1 正解・P2 不正解（P1 ポップ、P2 消火）→ P1 5 連続・P2 再点火、を確認し、
長い正解数でのレイアウト、旧右上ラベルの撤去、リセットを確かめる。画面は `artifacts/streak_flame/runtime/`、動画は `artifacts/streak_flame/gameplay_streak_preview.mp4`。
