# PV：1 問目を AI が書く演出

PV 冒頭（S01〜S03 v3 のカット 02）で、空から落ちてきた最初の問題壁の問題文と選択肢を、「AI がいま書いている」ように
1〜3 文字のかたまり（トークン）ずつ出す（2026-10-22）。**PV だけの演出で、ゲームのプレイ画面では出さない**（10/22 に決定）。
考えている表示（「AIが問題を作成中…」）は出さず、すぐに書き始める。動きのイメージは `docs/ai_question_typing_mock.html`（案 A）。

## いつ出すか

`tests/pv_capture/pv_v3_runtime.gd` の `_apply_wall()`：壁が落ち始めたフレームで `QuizWall.begin_ai_text_reveal()` を呼び、
落ちてくるあいだは文字を隠したまま、着地の 0.5 秒後（土ぼこりの衝撃のトゲが消えるころ。`AI_TEXT_AFTER_LAND`）から書く。
いまの撮影では PV フレーム 142 で着地、170 から書き始め、210 で書き終える。

## 動き（`scripts/world/wall_ai_text_reveal.gd` の定数）

| 項目 | 値 |
|---|---|
| トークン | 1〜3 文字。間隔 0.04〜0.075 秒、6% の確率で 0.12 秒つかえる。行が変わるときは 0.05 秒置く |
| 順番 | 問題文 → 0.12 秒あけて選択肢（扉ごとに 0.16 秒ずらす。扉どうしは並行して書く） |
| 文字の出方 | 0.06 秒で不透明に。1.38 倍から 0.26 秒で縮んで少し縮みすぎて戻る（イーズアウト・バック）。0.16 文字ぶん下から 0.22 秒でせり上がる。光る水色（HDR。ステージの glow でにじむ）から 0.45 秒で白へ冷める。輪郭も濃い水色から元の色へ |
| カーソル | 水色の細い縦線（幅 0.08 文字・高さ 0.9 文字）。最初の文字の 0.12 秒前に出て、最後に出た文字の右を追う。書き終えて 0.12 秒で 0.15 秒かけて消える。最後に書き終えたカーソルだけ 2 回点滅してから消える |
| 問題文の枠 | 書いているあいだは水色に寄せ、書き終えたら 0.3 秒で元の鋼色へ戻す。書き終えたときの光（枠の発光・左から右へ抜ける光の筋）は出さない（10/22 に外した） |
| 音 | トークンごとに `ai_type_tick`、書き終えたら `ai_type_done`（`docs/sound_effects.md`） |

## 仕組み

- `QuizWall.begin_ai_text_reveal(delay)` が `WallAiTextReveal` を壁の子に作る。問題文と選択肢を入れてから呼ぶ。壁ごとに 1 回だけ。
- 元の Label3D は消さずに、カメラから外す（`layers = 0`）。かわりに 1 文字ずつの Label3D を元のラベルの子として同じ位置に並べて動かす。
  元のラベルの大きさ（`get_aabb()`）は変わらないので、問題文の枠・カメラの枠取り・2P の拡大・退場はそのまま動く。
- 文字の位置は Label3D と同じ規則で求める（`WallAiTextReveal.layout_clusters()`）：TextServer の行分け（`autowrap_mode` と
  `autowrap_trim_flags`）、行ごとの水平の揃え、全体の縦の揃え。折り返しの切れ目に入る見えないグリフ（`GRAPHEME_IS_VIRTUAL`）は描かない。
  書き終えたラベルは元のラベルへ戻すので、ずれていると戻った瞬間に文字が動く。`tests/ai_typing_capture/layout_check.gd` で
  元のラベルと 1 文字ずつのラベルを撮り比べ、同じ絵になることを確かめた（違うのは、隣の文字と輪郭が重なる所の数ピクセル。
  例えば「Q1」の Q のしっぽ。ラベルが別々だと、輪郭とふちの描かれる順が 1 つのラベルの中とわずかに違う）。
- 書いている途中で文字やサイズが変わった・壁が退場した・壊れた・扉を作り直したときは、すぐに元のラベルへ戻す。

## 撮影

カット 01〜03 だけを撮って確かめる（撮り方の全体は `docs/pv/capture.md`）：

```
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_v3_bootstrap.gd -- quality=ultra frames=338 tag=ai_typing_v3
python tools/pv/mix_audio.py artifacts/pv_capture/ai_typing_v3 artifacts/ai_typing_capture/ai_typing_pv_audio.wav 338
ffmpeg -framerate 60 -i artifacts/pv_capture/ai_typing_v3/pv_%04d.jpg -i artifacts/ai_typing_capture/ai_typing_pv_audio.wav -c:v libx264 -crf 16 -pix_fmt yuv420p -c:a aac -b:a 256k -shortest artifacts/ai_typing_capture/ai_typing_pv.mp4
```

338 フレームで打ち切るので、report.json の `failures` には後半（P2 の激突・P1 の突破・爆散）が起きていないことが出る（これは問題ない）。

### 全編（v6）への差し替え（10/22）

全編の S01・S02 は `artifacts/pv_capture/v3_frames`（動きのブレ付き、PV 1〜1522）を使う。演出が映るのはカット 03 の終わり（338）までなので、
その範囲だけを本番画質で撮り直し、連番の頭 338 枚と `cues.json` の 338 までを差し替えた（339 から先と `report.json` は前のまま）。

```
（artifacts/pv_capture/GPU_LOCK を作ってから。83 秒）
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_v3_bootstrap.gd -- quality=ultra sub=8 frames=338 tag=v3_ai_sub8
python tools/pv/merge_subframes.py artifacts/pv_capture/v3_ai_sub8 artifacts/pv_capture/v3_ai_frames
（v3_ai_frames の pv_0001〜0338 を v3_frames へ写し、cues.json は 338 までを v3_ai_sub8 のものに替える）
python tools/pv/pv_master.py
```

- 新旧のコマを比べると、落ちてくる前（〜140）は同じ絵、書き終えたあと（260〜338）も JPEG の誤差だけなので、338/339 の切れ目で絵は飛ばない。
- 差し替える前の連番（1〜338）と `cues.json`・`report.json` は `artifacts/pv_capture/v3_frames_pre_ai/` に残してある。戻すときはそこから写して `pv_master.py` を流す。
- v3 を 1522 フレームまで通しで撮り直すときは、台本に演出が入っているので、そのまま撮れば同じ絵になる。
