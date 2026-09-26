# ゴドーくんのバットスイング参考

- 参考動画: MLB, [Play Ball: Josh Donaldson Demo](https://www.mlb.com/video/play-ball-josh-donaldson-demo-c872829783) (2016-06-29)。構えと実打の映像を参照した。
- 動作順の補助資料: MLB, [Early lesson helps Rockies' Ryan McMahon get on track](https://www.mlb.com/news/early-lesson-helps-rockies-ryan-mcmahon-get-on-track)。足を着け、腰が先に回り、手が後から進む順序を採用した。
- 動画から取り込んだのは動作の考え方だけ。映像や音声はゲーム素材に含めていない。

## ゴドーくんへの適用

| Blender 時刻 | 動き |
| --- | --- |
| 7.33〜8.18 秒 | バットを体の奥側へ引き、腰と頭を逆向きにひねって溜める |
| 8.28 秒 | 腰が先に打撃方向へ戻り、手元とバットは後ろに残る |
| 8.35〜8.45 秒 | 手元を加速し、顔の前を避けた軌道でバットを右へ振る |
| 8.45〜8.55 秒 | 既存の打撃位置とヒットストップを維持する |
| 8.55〜9.55 秒 | バットを上へ振り抜いてから構えへ戻す |

腕が短く、両手を同じグリップへ無理に集めるとリグが伸びるため、左手の IK をグリップへ固定し、右腕は回転に合わせてバランスを取る。`rebuild_bat_swing.py` は審判とバットのアクションだけを更新する。`animate_stage.py` も同じ処理を呼ぶ。

打撃時刻 8.45 秒、敗者の飛行、カメラ、得点、VFX の時計は変更していない。Blender 原本と `referee.glb` を更新し、Godot の実描画から P1/P2 の AE 用ステージ映像を再書き出した。
