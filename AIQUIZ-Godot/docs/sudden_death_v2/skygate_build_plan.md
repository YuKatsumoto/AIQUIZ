# サドンデス「つきやぶれ！スカイゲート」制作計画（並行で作るための分け方と受け渡しの約束）

2026-10-18作成。ここまでユーザーと決めたことを1つにまとめ、並行して作るための作業の分け方と、作業どうしの受け渡しの約束（ファイル・座標・関数・名前）を決める。

**この文書が正**：作業中に決めた数字や名前を変えるときは、この文書の第4章を先に直してから、それぞれの作業へ伝える。設計の詳しい中身と絵は次の4つの文書にある。

| 文書 | 中身 |
| --- | --- |
| `sky_gate.md` | 種目のルール・絵コンテ（ゲートの絵 11 コマ）・カメラの案・決めてほしいこと |
| `heli_drop.md` | 降り方（基本の降り方と 15% の特別な 8 種類・帰還の着地 3 通り）・降下の時刻・飛ばし方（Space）。機体の形の部分は使わない |
| `c130_float.md` | 水上機 C-130 の形と寸法・台座の横の水路（跳ね橋）と昇降台・機内・乗り込みの時刻表とカメラ |
| `sky_fx.md` | 本戦の空の演出（高さで移り変わる雲・風切り・下の島・マフラー・鳥・飛行機雲） |
| `common.md` | サドンデス共通の流れ（分岐・種目発表・雲・空のセット・帰還・敗者の幽霊）。乗り込みと帰還は第3章のとおり書き直す |

## 1. 決めたことのまとめ

### 1.1 種目「つきやぶれ！スカイゲート」（`sky_gate.md`）

| 項目 | 決定・案 |
| --- | --- |
| 遊び方 | 落ちながら、ドローン4機で吊った問題のボード（上に問題文、下に 2×2 の4択の紙のパネル）の正しいパネルをつき破って進む（決定） |
| カメラ | 2人の上・少し後ろから見下ろす。P1 は常に画面の左（決定） |
| まちがい | まちがったパネルに入った時点で爆散してアウト（決定）。体がブロックにばらける漫画の爆発 |
| 2人とも地上へ | 次のラウンドへ（決定）。水上機が着地台へ迎えに来て、もう一度落とす |
| 動かし方 | P1 は W・A・S・D、P2 は ↑・←・↓・→ で空中を前後左右に動く。ボードの外へは出られない（案） |
| 1 ラウンド | ゲート 4 枚。1 枚 8 秒（ROUND 2：6.5 秒・ボードが横へ動く、ROUND 3 以降：5 秒・ボードが小さい）（案） |
| 終わらないとき | ROUND 5 のあとは着地せずにゲートが1枚ずつ（5→4→3 秒）。3 秒のゲートで2人とも正解なら早い者勝ち（正解のパネルに入ってそのまま通過した時刻が早い方）（決定、2026-10-19） |
| 同じパネル | 2人とも選べる。体は軽く押し合う（決定） |
| 問題文 | **ボードだけ**（HUD には出さない）。問題文の帯はボードより大きな看板にして、ドローンを足して吊る（決定） |
| アウト | ばらけたブロックが集まって幽霊になり、勝者についていく → 共通の幽霊で帰る（決定） |
| 2人とも同じゲートでアウト | その場で復活（1.0 秒）して次のゲートから。そのゲートは2人とも「なし」。最後のゲートなら2人とも着地台へ降りて次のラウンド（決定） |

### 1.2 水上機 C-130（`c130_float.md`）

| 項目 | 決定 |
| --- | --- |
| 機体 | C-130 をモデルにした水上機。全長 18.0m・翼の幅 24.0m・エンジン 4 つ・大きな尾翼・スロープは尾の下。白と濃紺に、オレンジと青の細い線 |
| 舞台での乗り込み | 台座の横（+X、画面の左）のスタンド 40m が跳ね橋のように 14m 上がり、水上機がその下を後ろ向きに入る。床の端の昇降台が 6.1m 下り 4.1m 伸びてスロープとつながる。2人が駆け込む |
| 機内 | 実機ふう（赤い布の座席・網・むき出しの骨組み）。貨物室 8.0×4.04×3.72m。2人は左右のベンチで向かい合う。後ろを向いた画で P1 が左（P1 は機体の右の壁）。操縦席は一段高い床の真ん中の1席にハテナ |
| 乗り込みの長さ | 「乗りこめー！」から離水まで約 12 秒（8 コマ）。カットは着水と機内の 2 回 |

### 1.3 降り方（`heli_drop.md` 第2章）

| 項目 | 決定 |
| --- | --- |
| 降下 | 機内（赤いランプ）→ スロープが開く → 緑 → 2人がスロープを駆け出して飛ぶ（0.4 秒ずらす、先はランダム）。カメラは機内から背中を追って機外へ出て、切らずに本戦の見下ろしへ |
| 降り方 | ふだんは基本の降り方（2 通り）。1 人ごとに 15% で特別な 8 種類（スーパーマン・後ろ宙返り・スピンダイブ・大の字・つまずき・ドボン・敬礼・ためらい） |
| ROUND 2 以降 | 短い版（約 3 秒、スロープが開いたところから） |
| 帰還 | 水上機がゴールの床の上を低く通り、勝者がスロープから飛び降りて自分の台へ。着地はヒーロー着地・前転・ピタッの 3 通りからランダム |
| 飛ばす | 乗り込みも降下も **Space** で飛ばせる（ルールカードを閉じるのは Enter のまま） |

## 2. 全体の流れ（新）

```
（今のまま）0〜14.4 秒：DRAW! → 審判の笛 → SUDDEN DEATH! → タワーが沈む → 大型ビジョンで種目発表
→ 14.4 秒「乗りこめー！」→ 乗り込み（約 12 秒、c130_float.md 第6章）→ 離水 → 雲の覆い → 空のセット（機内の巡航）
→ 降下（約 6 秒）→ 図解ルールカード（Enter）→ 3・2・1 → ROUND 1：ゲート 4 枚
   ├ 1 人だけアウト → 決着：勝者はパラシュートで着地台へ → ダンス → 水上機が着地台の横に着水して迎え → 帰還
   ├ 2 人とも同じゲートでアウト → その場で復活して次のゲートから
   ├ ROUND 5 のあと → 着地せずにゲートが1枚ずつ（5→4→3 秒）、3 秒のゲートで2人とも正解なら早い者勝ち
   └ 2 人とも 4 枚突破 → 2 人ともパラシュートで着地台へ → 「ROUND 2」→ 水上機が着地台の横に着水して迎え → 短い降下
→ 帰還：水上機がゴールの床の上を低く通り、勝者がスロープから飛び降りて台へ。敗者は幽霊で帰る → 判定から勝者の演出
```

今のヘリ 2 機の迎え・縄ばしご・2 機の巡航（common.md 第5・6章）は使わない。空のセット・雲の覆い・帰還の幽霊・決着演出への戻り方は使う。

## 3. 作業の分け方

7 つに分ける。W1〜W5 と W7 は互いの結果を待たずに並行で進められる（足りないものは仮の形で置き、第4章の約束どおりの口だけそろえる）。W6 は W1〜W5 がそろってから、それらをつなぐ。

| # | 作業 | 中身 | 主に触るところ | Blender |
| --- | --- | --- | --- | --- |
| W1 | 水上機 C-130 | 機体（外・機内・操縦席）を作る。スロープ・上のふた・プロペラ・フラップ・ランプ・灯の動く部品。Godot のクラス | `assets/vehicles/floatplane_c130/`（新規）、`scripts/world/sudden_death/floatplane/`（新規） | 使う |
| W2 | 舞台の仕掛け | 台座の横のスタンド 2 ブロックを跳ね橋のように持ち上げる（塔の素材と動き、観客ごと）。床の端の昇降台 | `assets/sudden_death/stage_gate/`（新規）、`scripts/world/sudden_death/stage_gate/`（新規）、`aiquiz_stadium_stand.gd` と `grandstand_crowd.gd` に小さな口を足すだけ | 使う（塔・昇降台） |
| W3 | 人の動き | 降り方（基本 2・特別 8）、帰還の着地 3、機内の座り・ベルト・立つ・歩く、スロープを駆け上がる・駆け下りる、空中の腹ばいと動く向きの傾き。再生の部品 | `assets/animations/sudden_death/`（新規）、`scripts/world/sudden_death/drop/`（新規）、`animation_rig.gd` にスロットを 1 つ足す | 使う |
| W4 | スカイゲート本体 | ルール（ラウンド・ゲート・アウト）、見せ方（見下ろしのカメラ・空中で動く・ゲートが近づく・決着）、HUD、図解ルールカード、空中で動く入力 | `scripts/core/sudden_death/sky_gate_game.gd`（新規）、`scripts/world/sudden_death/games/sky_gate_*.gd`（新規）、`scripts/ui/sudden_death/sky_gate_hud.gd`（新規）、入力は `game_world.gd`・`game_state.gd` に口を足すだけ | 使わない |
| W5 | ゲートの素材と効果 | 問題のボード（枠・紙のパネル・問題文の帯）とドローン 4 機・吊りケーブル。紙が破れる効果、パネルの爆発、体がブロックにばらける効果 | `assets/sudden_death/sky_gate/`（新規）、`scripts/world/sudden_death/games/sky_gate_board.gd`・`sky_gate_effects.gd`（新規） | 使う |
| W7 | 空の演出 | `sky_fx.md`：高さで移り変わる雲（雲海・雲を抜ける・3 層の雲）、風切り（速さの線・風の筋・雲のかけら）、マフラー、見下ろしの島、海鳥・飛行機雲。今の `FallClouds` を作り直す | `assets/sudden_death/sky_fx/`（新規）、`scripts/world/sudden_death/sky_fx/`（新規）、`shaders/sky_fx_*.gdshader`（新規） | 使う（雲の塊・島・マフラー） |
| W6 | つなぐ | 監督の流れを新しくする（乗り込み・離水・機内の巡航・降下・ラウンドのやり直し・迎え・帰還）、種目の入れ替え（`parachute` → `sky_gate`）、Space で飛ばす、通しの実ゲームテスト | `heli_sudden_death_director.gd`、`sudden_death_presenter.gd`、`game_state.gd`、`game_world.gd`、`common.md` | 使わない |

### 3.1 進め方の決まり

- W1〜W5 はそれぞれ別のセッションで進める。設計の文書と絵（`docs/sudden_death_v2/`・`artifacts/sudden_death_v2/`）はまだコミットしていないので、**この作業フォルダ（C:\AIQUIZ\AIQUIZ-Godot）をそのまま共有**する。ブランチは切り替えず、コミットもしない。同じファイルを 2 つの作業が書かない（上の表の「主に触るところ」を守る。共有のファイルに足すときは第4章に書いた口だけ、短い追記で）。
- **Blender は 1 台**：ライブの Blender は 1 つなので、W1・W2・W3・W5 は同時に使えない。使う前に `artifacts/sudden_death_v2/BLENDER_IN_USE.txt` を見て、無い（または空）ならセッション名と時刻を書いてから使い、`.blend` を上書き保存したら消す。使われている間は Godot 側（クラス・テスト・仮の形）を進める。ヘッドレスの Blender で代わりに作らない（AGENTS.md）。
- 各作業は、終わったら自分の README（素材のフォルダ）か仕様書の該当の章に「できたこと・決めた数字・確かめ方」を書く。第4章の約束を変えたくなったら、勝手に変えずにユーザーに相談する。
- 絵の参考は `artifacts/sudden_death_v2/`（`sky_gate/`・`c130_float/`・`heli_drop/`）。絵の中の寸法より、この文書と `c130_design.py` の数字が正。
- コミットはユーザーに頼まれたときだけ。関係のない作業中の変更を壊さない。

### 3.2 各作業の「できた」の基準

| # | できたの基準 |
| --- | --- |
| W1 | `floatplane_c130.glb` を Godot で読み、第4.2節の関数でスロープ・ふた・プロペラ・ランプが動く。マーカーがすべてある。外と機内と操縦席の確認の画（Godot の実画面）と、`c130_design.py` の寸法との差が 5cm 以内の表 |
| W2 | 引き分けの台座が出た状態で、`StandGate.set_lift(t)` で 2 ブロック（観客ごと）が上がり下がりし、元に戻すと前と同じ。昇降台がスロープの端の位置まで下りて伸びる。持ち上げたスタンドの柱の下端と尾翼の上のすき間が 2m 以上 |
| W3 | 第4.4節のクリップがすべてあり、`DropMotion` で本物のアバター（`StagingPuppet`）と人形（`build_player_skeleton`）の両方に当てられる。どの降り方も端を離れて 1.2 秒以内に腹ばいに落ち着く。仮のスロープ（箱）で 2 人が飛び出す確認の画 |
| W4 | ユニットテスト（30／60／120fps で同じ結果・正解・まちがい・同じゲートで 2 人アウト・ラウンドのやり直し・時間切れの位置で判定）。見せ方はデバッグの入口（監督なし）で、仮のボードで 1 ラウンド通して遊べる |
| W5 | ボードの 4 枚のパネルと問題文の帯、ドローン 4 機（ローターが回る）。破れる・爆発・ブロックにばらける効果を時刻で再生でき、画質「低」でも重くない。確認の画 |
| W7 | 見下ろしの画で 4 つの帯（雲海・雲を抜ける・点々の雲と島々・近い島と着地台）と風切り・マフラー・海鳥・飛行機雲を、デバッグの入口で高さを動かして撮れる。画質「低」でも重くない（描く回数・粒の数を README に書く） |
| W6 | 実ゲームの通しテスト：引き分け → 乗り込み → 離水 → 降下 → ROUND 1 → 決着（1 人アウト）／ROUND 2（2 人とも突破）→ 迎え → 帰還 → 操作可能。Space で乗り込みと降下を飛ばせる。打ち切り（読み込みの失敗）で従来の引き分けに戻る |

## 4. 受け渡しの約束

### 4.1 座標と向き

- ゲームのワールドの座標。高さは `StageConstants`：床の上面 y=−1.2、海面 y=−9.2（床は海面から 8.0m 上）、床の幅 24m（x=±12）、横のスタンドは x=±27.2〜42.5。
- 台座の中心は `ResultCeremonyDirector.podium_center(state)`。z は試合で変わるので、**固定の z を書かない**。
- 水路は台座の **+X の側**（画面の左、P1 の側）だけ開ける。−X の側は開けない。
- 持ち上げるのは、+X のスタンドの 20m ブロックのうち、**台座の z をはさむ 2 ブロック**（境目が台座の z に一番近い 2 つ）。水上機の中心線の z ＝ その 2 ブロックの境目の z（`StandGate.gap_center_z()`）。
- 水上機は止まるとき、機首を +X（外の海）へ、尾を床へ向ける。尾の端は床の壁から 0.5m（x=12.5）。

### 4.2 W1 → W6・W2・W3：水上機（`SuddenDeathFloatplane`）

素材：`assets/vehicles/floatplane_c130/floatplane_c130.glb` と `floatplane_c130_layout.json`（マーカーと寸法）。寸法の元は `artifacts/sudden_death_v2/c130_float/c130_design.py`（W1 が素材のフォルダの `source/` に写して使う）。

- 原点：海面の高さ（浮いているときの水面）× 機体の中心線 × 主翼の翼弦の中央（機首から 6.6m）。+Y が上、**機首が −Z**（今のヘリと同じ）。`c130_design.py` の u（機首から後ろ）は z = u − 6.6、v（海面から）は y = v。
- 材質は名前で探す（今のヘリと同じやり方）：`FP_Paint`（白）・`FP_Navy`・`FP_StripeOrange`・`FP_StripeBlue`・`FP_Glass`・`FP_Interior*`・`FP_SeatWebbing`・`FP_LightRed`・`FP_LightGreen`。
- クラス `SuddenDeathFloatplane extends Node3D`（`scripts/world/sudden_death/floatplane/sudden_death_floatplane.gd`）：

| 関数 | 中身 |
| --- | --- |
| `build(quality: String)` | 読み込み・材質の作り替え・画質 |
| `set_ramp(t: float)` | 0＝閉じる、1＝床と水平（開いたまま飛んでも同じ 1） |
| `set_upper_door(t: float)` | 後ろの上のふた（0 閉じる〜1 尾の中へ上がる） |
| `set_props(speed: float, reverse := false)` | プロペラの回転（0〜1）。`reverse` は逆推力（後ろへ進むときの羽根の向き） |
| `set_flaps(t: float)` / `set_jump_light(state: String)` | フラップ（着水・離水）。ランプ "off"・"red"・"green" |
| `set_pontoon_spray(amount: float)` | フロートのしぶき（着水・離水・水上を走る） |
| `marker(name: String) -> Transform3D` | ワールドのマーカー（下の表） |
| `seat_transform(player: int) -> Transform3D` | ベンチに座る位置と向き（P1 は機体の右の壁） |
| `pilot_transform() -> Transform3D` | ハテナ（`HatenaPilot`）の座る位置 |

| マーカー | 位置 |
| --- | --- |
| `MK_SeatP1` / `MK_SeatP2` | ベンチの座る位置（pelvis）。向きは通路の向かいへ |
| `MK_StandP1` / `MK_StandP2` | ベルトを外して立つ位置 |
| `MK_RampHinge` / `MK_RampEdge` | スロープの付け根と端（開いたとき）。端の上面＝飛び出す位置 |
| `MK_DeckDoor` / `MK_PilotSeat` | 操縦席の出入り口（段の上）と、操縦席 |
| `MK_CamAft` / `MK_CamFwd` | 機内のカメラの初めの位置（段の上から後ろを見る／スロープの付け根から前を見る） |
| `MK_TailEnd` | 尾の一番後ろ（水路で床の壁から 0.5m に合わせる） |
| `MK_JumpLight` | 降下のランプ |

### 4.3 W2 → W6：舞台の仕掛け（`StandGate`・`FloorEdgeLift`）

- `StandGate`（`scripts/world/sudden_death/stage_gate/stand_gate.gd`）：`setup(stage_env, podium_center: Vector3)`、`set_lift(t: float)`（0〜1。1 で 14m。高さは W2 が柱の長さを測って決め、尾翼の上 9.5m＋2m 以上あける）、`gap_center_z() -> float`、`restore()`。2 ブロックと、その 2 ブロックの観客（スタンドの子の `Spectators`＝`grandstand_crowd.gd`。MultiMesh は 20m ブロックごと）と塔を一緒に動かす。
- `FloorEdgeLift`（同じフォルダ）：`setup(stage_env, gap_center_z: float)`、`set_t(t: float)`（0＝床と同じ高さ、1＝6.1m 下りて 4.1m 伸びた位置）、`top_point() -> Vector3`（乗った人の足の高さ）、`restore()`。
- 共有のファイル（`aiquiz_stadium_stand.gd`・`grandstand_crowd.gd`）には「ブロックのノードと観客の MultiMesh をブロックの番号で返す」関数を足すだけにする。並びや見た目は変えない。

### 4.4 W3 → W4・W6：人の動き（`DropMotion`）

素材：`assets/animations/sudden_death/drop_moves.glb`（骨は UAL と同じ名前・同じ骨。`AnimationRig` にスロット `SLOT_DROP` を 1 つ足し、`StagingPuppet.pose(clip, ratio, SLOT_DROP)` で再生できるようにする）と `drop_moves.json`（クリップごとの長さ・端を離れる時刻・腹ばいに落ち着く時刻・着地の時刻・根の動き）。

| クリップ | 使うところ |
| --- | --- |
| `SD_Bench_Sit_Loop` / `SD_Bench_Belt_Click` / `SD_Bench_Unbuckle_Stand` | 機内（座る・ベルト・ベルトを外して立つ） |
| `SD_Ramp_Run_Up` / `SD_Ramp_Walk` / `SD_Ramp_Run_Out` | 乗り込みで駆け上がる・降下でスロープを歩く・駆け出す |
| `SD_Jump_Basic_A` / `SD_Jump_Basic_B` | 基本の降り方（ふだん） |
| `SD_Jump_Superman`・`SD_Jump_Backflip`・`SD_Jump_SpinDive`・`SD_Jump_Starfish`・`SD_Jump_Trip`・`SD_Jump_Cannonball`・`SD_Jump_Salute`・`SD_Jump_Hesitate` | 特別な降り方（1 人ごとに 15%）。`Hesitate` は 2 人目だけ |
| `SD_Box_Loop` | 空中の腹ばい（落ちている間ずっと） |
| `SD_Box_Lean_Left` / `_Right` / `_Forward` / `_Back` | 空中で動く向きの傾き（W4 が動く向きで混ぜる） |
| `SD_Land_Hero` / `SD_Land_Roll` / `SD_Land_Stick` | 帰還の飛び降りの着地 |

- クラス `DropMotion`（`scripts/world/sudden_death/drop/drop_motion.gd`）：`choose_jump(rng, player: int, last: Dictionary) -> String`（85% 基本・15% 特別、2 人は別の特別、前の回と同じ特別は避ける、`Hesitate` は 2 人目だけ）、`pose_puppet(puppet: StagingPuppet, clip: String, time: float)`、`pose_doll(parts: Dictionary, clip: String, time: float)`、`clip_info(clip: String) -> Dictionary`。
- W4 と W6 は、W3 ができるまで仮の動き（今のパラシュートの腹ばいの関節の表）で置き、名前だけこの表に合わせる。

### 4.5 W4 ↔ W6：スカイゲートのルールと見せ方

- ルール `SkyGateGame extends SuddenDeathGame`（`kind = "sky_gate"`）。判定は全部ここ（見せ方は判定しない）。
- 入力（1 フレーム）：今の辞書に **`"move": [Vector2, Vector2]`**（押しっぱなしの向き。x＝右、y＝前。長さ 0〜1）を足す。`QuizGameState.set_sudden_death_move(player: int, move: Vector2)` を新しく作り、`GameWorld` が WASD と矢印の押しっぱなしの状態から毎フレーム呼ぶ。Space（P1 のアクションキー）はルールに渡さない（演出を飛ばすのに使う）。
- 早い者勝ちのために、ルールは各プレイヤーが「今の真下のパネルに入った時刻」を持つ（同じパネルの上にいる間は変えない）。
- 2 人の空中の位置はルールが持つ（ボードの座標、m。ボードの中心が原点、x＝右、y＝前（ゴールの側））。動く速さ・止まり方・2 人の押し合い・ボードの外へ出ない、もルール。
- 出来事（`events`）：

| 出来事 | 中身 |
| --- | --- |
| `round_start` | `{"round", "gates", "gate_time", "board_size"}` |
| `gate` | `{"round", "index", "question", "choices", "correct", "time"}`（ゲートが遠くに見えた瞬間） |
| `gate_pass` | `{"index", "panels": [P1, P2]（真下のパネル、-1＝ボードの外）, "results": ["burst" / "boom", ...]}` |
| `out` | `{"player"}` |
| `round_clear` | 2 人ともそのラウンドを突破（2人とも着地台へ） |
| `both_out` / `revive` | 2 人とも同じゲートでアウト → 1.0 秒後にその場で復活（`{"index"}`） |
| `overtime` | ROUND 5 のあと、着地せずに1枚ずつ続くゲートに入った（`{"gate_time"}`、5→4→3 秒） |
| `decided` | `{"winner", "by", "round", "index"}`。`by` は `"out"`（相手がアウト）か `"speed"`（3 秒のゲートの早い者勝ち） |

- 見せ方 `SkyGatePresenter extends SuddenDeathPresenter`。`descent_mode()` は新しく **`"floatplane"`** を返す（W6 が監督に足す）。見せ方は「本戦（ルールカードから決着まで）」と「着地台への着地・ダンス」を受け持つ。乗り込み・離水・機内・降下・迎え・帰還は監督（W6）が W1・W2・W3 の部品で受け持つ。
- 監督への口（W6 が `SuddenDeathPresenter` に足す）：`round_cleared() -> bool`（2 人とも着地台に着いて「ROUND 2」を見せ終えた）、`begin_round(round: int)`（降下が終わって次のラウンドを始める）、`sky_spawn(player: int) -> Transform3D`（降下が終わったときに2人が落ちている位置。降下のカメラがここへつながる）。
- HUD `SkyGateHud`：上の真ん中に ROUND とゲートの数・残りの帯（**問題文は出さない**。ボードの看板だけ）、左上と右上に 2 人の札（「15 の上」「セーフ」「アウト」）、下に小さく動かし方のキー。図解ルールカードは 3 枚の絵（`sky_gate.md` 3.1）。

### 4.6 W5 → W4：ゲートの素材と効果

- 素材：`assets/sudden_death/sky_gate/gate_board.glb`（ボード 14×10m を基本、ROUND 3 以降は Godot で縮める）。パネルは `Panel_0`〜`Panel_3`（**0＝奥の左、1＝奥の右、2＝手前の左、3＝手前の右**。ルールの選択肢の番号と同じ）、問題文の看板 `QuestionSign`（**ボードより大きな看板**。遠くから読めること。吊るドローンを足してよい。前の版の `QuestionStrip` から変更、2026-10-19）、ドローン `Drone_0`〜`Drone_3`（子に回るローター `Rotor_*`）、ケーブル `Cable_*`。文字は素材に入れない（Godot の `Label3D` か SubViewport で書く）。
- クラス `SkyGateBoard`（`scripts/world/sudden_death/games/sky_gate_board.gd`）：`build(quality)`、`set_question(text, choices: Array[String])`、`set_highlight(panel: int, player: int, on: bool)`（自分の色の光る枠）、`burst(panel: int)`（紙が破れて紙吹雪と光の輪）、`boom(panel: int)`（パネルの爆発）、`advance(delta)`、`panel_center(panel: int) -> Vector3`、`size() -> Vector2`。
- 効果 `SkyGateEffects`（`sky_gate_effects.gd`）：`player_burst(parts: Dictionary, at: Vector3)`（人形の体がブロックにばらけて飛び散る）。

### 4.8 W7 → W4・W6：空の演出（`SkyFallScenery`）

- クラス `SkyFallScenery extends Node3D`（`scripts/world/sudden_death/sky_fx/sky_fall_scenery.gd`）：`build(quality: String, landing_point: Vector3)`（着地台の位置のまわりに島を置く）、`set_progress(p: float)`（ラウンドの落下の進み 0〜1。`sky_fx.md` 第2章の帯。ROUND 5 のあとは `set_overtime(true)` で「点々の雲と島々」をくり返す）、`advance(fall_distance: float, delta: float)`（落ちた分だけ雲と景色を流す）、`set_wind(strength: float)`（0〜1.4。W4 がゲートの近さで決める）、`gate_emerge(board: Node3D)`（雲海の穴からボードが現れる）、`set_camera(camera: Camera3D)`（画面のもやと速さの線）。
- マフラー：`SkyFallScarf`（同じフォルダ）`attach_doll(parts: Dictionary, player: int)`・`attach_puppet(puppet: StagingPuppet, player: int)`・`detach()`。色は P1 オレンジ（赤み）、P2 青。
- 2 人のすぐまわりは雲を空ける（今の `FallClouds` と同じ考え）。カメラの前を抜ける雲は、問題を選ぶ間は出さない。
- W4 は W7 ができるまで今の `FallClouds` で置き、関数の名前だけこの約束に合わせる。

### 4.7 W6：監督の新しい流れ

| 場面 | 中身 | 部品 |
| --- | --- | --- |
| BOARD（乗り込み） | `c130_float.md` 第6章の 8 コマ（約 12 秒） | W1・W2・W3 |
| TAKEOFF → 雲の覆い | 離水して雲へ（common.md 5.3） | W1 |
| CRUISE（機内） | 空のセットで機内の巡航（準備と問題の生成を待つ） | W1・W3 |
| DROP（降下） | `heli_drop.md` 3.1 の時刻（約 6 秒、ROUND 2 以降は約 3 秒） | W1・W3 |
| VENUE | 見せ方（W4）に渡す | W4 |
| REBOARD（ROUND 2 の迎え） | 着地台の横に着水してスロープを着地台の床に下ろし、2 人が駆け込む（時刻表は未決） | W1・W3 |
| EXTRACT（勝者の迎え） | 同じく着地台で勝者だけ（未決） | W1・W3 |
| HOME（帰還） | ゴールの床の上を低く通り、勝者がスロープから飛び降りて台へ（未決）。敗者は幽霊 | W1・W3 |

- Space で飛ばす：`GameWorld` が Space を監督へ渡し（`skip_presentation()`）、監督は乗り込み・降下の間だけ受ける。乗り込みを飛ばすと雲の覆いへ、降下を飛ばすと本戦の見下ろしへ（0.3 秒の白い閃光）。
- 種目の入れ替え：`QuizGameState.SUDDEN_DEATH_GAMES = ["sky_gate"]`、`_create_sudden_death_game` が `SkyGateGame` を返す、問題の数は 5 ラウンド × 4 問 ＝ 20 問。`parachute` のコードは消さずに残す（着地台・パラシュート一式・水柱・雲・ダンスは使う）。

## 5. 順番と見積もり

```
並行：W1 水上機 ─┐
      W2 舞台    ─┤
      W3 人の動き ─┼─→ W6 つなぐ → 通しで遊んで直す
      W4 本体    ─┤
      W5 ゲート  ─┘
Blender の順番（案）：W5 ゲート（小さい）→ W1 水上機（大きい）→ W2 塔と昇降台 → W3 動き（長い）
```

- W4 は Blender を使わないので最初から最後まで進められる。W3 は Blender を長く使うので、先に Godot 側（`DropMotion` と仮の動き）を作り、Blender が空いたらクリップを作る。
- W6 は W1〜W5 がそれぞれ「できた」になってから始める（同じ作業フォルダなので、まとめる手間はない）。

## 6. まだ決めていないこと

| 項目 | どこで決める |
| --- | --- |
| ~~ROUND 2 の迎え・勝者の迎え・帰還の時刻表とカメラ~~ | W6 で作って決めた（`c130_float.md` 第8章）。ユーザーの確認を待つ |
| 音（スタンドが上がる・水上機・プロペラの逆推力・紙が破れる・爆発） | 音の担当（今は今ある音で代用） |

## 7. 進み具合（2026-10-19）

| # | 状態 | できたことの書き場所 |
| --- | --- | --- |
| W1 水上機 | できた | `assets/vehicles/floatplane_c130/README.md`。W6 でスロープを床より下へ下げる `RAMP_GROUND`（1.8 ＝ 床から 20° 下）を足した |
| W2 舞台の仕掛け | できた | `assets/sudden_death/stage_gate/README.md`（`StandGate`・`FloorEdgeLift`、確認 `tests/sudden_death_v2/stage_gate_check.gd`） |
| W3 人の動き | できた | `assets/animations/sudden_death/`・`DropMotion` |
| W4 本体 | できた | `sky_gate_w4.md` |
| W5 ゲート | できた。問題文の帯を大きな看板 `QuestionSign`（17 × 6 m、ドローン 6 機）に替えた（W6 のセッションが作り直し） | `assets/sudden_death/sky_gate/README.md` |
| W7 空の演出 | できた。島の glb の作り直し（礁の外をなだらかに）は W6 のセッションがライブの Blender で行った | `assets/sudden_death/sky_fx/README.md`・`sky_fx.md` |
| W6 つなぐ | できた（通しの実ゲームテスト 4 通り） | `skygate_w6.md`・`c130_float.md` 第8章 |

