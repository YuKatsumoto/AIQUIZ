# 結果発表アリーナ（両者脱落の結果発表）

エンドレスの2人対戦（ローカル・オンライン）で2人とも脱落したとき、暗転のあとに結果発表（スコアタワー）を行う海上の専用アリーナ
（2026-11-04 のユーザー指示：「結果発表のスペースを別に用意してそこでする。観客とモニターを入れる。ステージは Blender で作る」）。
**10問チャレンジでは使わない**（2026-11-04 のユーザー指示：「カウボーイハテナの運ぶ演出は10問チャレンジでは残す。結果発表のステージは
エンドレスモードだけで使い、10問チャレンジは以前のようにする」）。10問の両者脱落は、雲に乗ったハテナが投げ縄で2人をコースのゴールへ
運ぶ演出（docs/elimination_lasso.md）のあと、ゴールした終わり方と同じくコースの先のゴール観客席で結果発表する。

## 中身

| ファイル | 中身 |
| --- | --- |
| `result_arena.glb` | 円形の舞台 `RA_Deck`（半径 12 m＝コースの床の半分の幅。サドンデスの水上機はコースと同じく x=12 に横付けする。上面は床の高さ）と中央のフタ `RA_Lid`（半径 7 m＝旧サドンデスの縦穴）、左右の座席スタンド `RA_WingR`（P1 の側）・`RA_WingL`（P2 の側）、照明塔 `RA_Masts` |
| `result_arena_stand.glb` | 正面スタンド `RA_Stand` と大型モニター `RA_Scoreboard`（LED 面 12.6 x 5.4、材質 `GS_ScoreboardScreen`）。ゴール観客席と同じ約束（段・通路は `assets/goal_stand/goal_stand_layout.json`） |
| `result_arena_layout.json` | 正面スタンドの位置（`stand_offset`）、フタの半径、左右のスタンドの座席 |
| `source/build_result_arena.py` | Blender のビルダー（AIQUIZ STADIUM のビルダーの部品と色をそのまま使う）。`source/result_arena.blend`・`source/previews/`・`source/SCENE_PASSPORT.md` |

## ゲームでの使われ方

- `scripts/world/result_arena/result_arena.gd`（`ResultArena`）：アリーナを組む。正面スタンドは `GoalStand` をアリーナの建物で組むので、
  観客の応援・卵・ボード・ダンスと LED の掲示板（AIQUIZ VISION の番組）はゴール観客席と同じに動く。左右のスタンドはコースの客席と同じ
  座った観客（`GrandstandCrowd`）。サドンデスの縦穴が開くあいだは中央のフタを外す
- `scripts/world/game_world.gd`：エンドレスの両者脱落の結果待ち（`RESULT_ELIMINATION_HOLD`）のあと暗転し、覆っているうちに
  `begin_elimination_result_ceremony()` → `_enter_result_arena()`（舞台の中心 `ResultCeremonyDirector.podium_center` に置き、
  コースの床・左右の客席・サメ・壁を隠し、観客を並べ終える）→ 明ける。次の試合の始まり（メニュー・読み込み・開始待ち）で `_exit_result_arena()`
- アリーナ空間の原点は舞台の中心の床の上面。結果発表のカメラ（Blender で振り付けた `ResultFinaleMotion`）はゴール観客席を背景に作ってあるので、
  正面スタンドはゴール観客席と同じ距離（舞台の中心から 22.1 m）に立てる

## 作り直し

ユーザーのライブ Blender（Higgsfield の Blender 連携）で実行し、`.blend` を上書き保存する（ヘッドレスでは動かさない）:

```python
path = r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/result_arena/source/build_result_arena.py"
ns = {"__file__": path, "__name__": "result_arena_builder"}
exec(compile(open(path, encoding="utf-8").read(), path, "exec"), ns)
ns["build"](wear=True); ns["preview"]()
bpy.ops.wm.save_as_mainfile(filepath=r"G:/AIQUIZ-Main/AIQUIZ-Godot/assets/result_arena/source/result_arena.blend")
```

確認：`tests/result_arena_bootstrap.gd`（本物の GameWorld でエンドレスの両者脱落 → 暗転 → アリーナの結果発表 → 次の試合でコースへ戻る）。
