# オンライン対戦 マッチング演出 計画書 v1.1

| 項目 | 内容 |
|---|---|
| 目的 | 仕様書 `docs/online_match_staging/spec.md` の演出を、ゲームに組み込んで仕上げる |
| 版 | v1.1（2026-10-11。M1〜M8 を実施した。結果は「9. 実施の記録」） |
| 前提 | 仕様の未決事項は仕様書の「3. 決めたこと」で決定済み。この計画は質問なしで進められるようにしてある |
| 入力 | 絵コンテ v2（`artifacts/storyboard/online_matching_storyboard_v2.png`）、ヘリの設計図（`artifacts/heli_blueprint/`）、ヘリの素材（`assets/vehicles/helicopter_boarding/`、作成済み） |

---

## 1. 今の状態

| もの | 状態 |
|---|---|
| 絵コンテ | v2（11 コマ）。実際の画面と並べた表：`artifacts/online_staging/compare_storyboard.png` |
| ヘリポート | パッド 1 つに作り直した（`assets/online_heliport/`、ビルダー v2、三角形 5,488） |
| 乗り込めるヘリ | オンラインの画面と本編のヘリ登場（M9）の両方で使っている（`OnlineHeliportHelicopter`）。左右の肩にジェットのポッド（たたむ／広げる）を足した |
| ハテナ | 操縦の動き 4 つ・ヘッドセット・軽い版を Blender で作った（`mascot_pilot.glb`・`pilot_headset.glb`・`mascot_model_lod.glb`）。`mascot_model.glb` は変えていない |
| 演出 | 監督 `OnlineStagingDirector` が待機〜SWAP の全部の状態を動かす。カットイン `OnlineCutin`、中央の線が開く遷移 `SceneTransition.hold_versus_split` |
| 通信 | プロトコル v2 のまま。ゲストの `ready{phase:"loaded"}` とホストの `evt{event:"reveal"}` で開く時刻をそろえる。リレーは変えていない |
| 試験 | `online_staging_runtime`（73 項目）、`online_menu_runtime`（32 項目）、`run_pair.py` の演出つき・回線の遅れ・カットイン中の消失、`online_staging_perf`、動画 |

## 2. 使う道具（MCP・ツール）の割り当て

作業の種類ごとに、使うものを 1 つに決める。「予備」は、主が使えないときだけ使う。

| 作業 | 主に使うもの | 予備 | 決まりごと |
|---|---|---|---|
| Godot のシーン・リソース（`.tscn` / `.tres`）の作成と変更 | **godot-ai MCP**（`mcp__godot-ai__*`：`session_activate` / `editor_state` で `C:/AIQUIZ/AIQUIZ-Godot/` を確認 → `scene_open`、`node_create`、`node_set_property`、`script_attach`、`scene_save`） | エディターがゲームを実行中で MCP の変更が止まるときは、ヘッドレスの Godot で PackedScene を書き出す | AGENTS.md：シーンとリソースは Godot を通して変える。変えたら必ず保存する |
| GDScript の作成と変更 | ファイル編集（Write / Edit） | — | 新しいスクリプトは `scripts/world/online_staging/` と `scripts/ui/online/cutin/` に置く |
| Godot の確認（構造） | **godot-ai MCP** の `script_manage`（検証）、`logs_read` | ヘッドレス Godot `--check-only` | `--check-only` は autoload がなく誤検知が出る。最終判断は実行時のテストで行う |
| Godot の確認（実行・画面） | **ヘッドレス／画面付きの Godot**（`net_match_bootstrap.gd -- runtime=...`）、**godot-ai MCP** の `project_run`・`editor_screenshot`・`game_manage` | — | 構造のチェックと実行時の証拠は分けて報告する。ユーザーがエディターで動かしているゲームは止めない |
| 取り込み（GLB・画像） | **ヘッドレスの `--import`** | エディターのファイルシステムの再スキャン（godot-ai MCP の `filesystem_manage`） | エディターがゲームを実行中は取り込みが止まるので、ヘッドレスで行う |
| 3D の制作（ヘリポートの作り直し、ハテナの動きとヘッドセット、ハテナの軽い版） | **Higgsfield の Blender 連携**（`get_host_status` で `blr` を確認 → `bl_get_skill`（blender-scene ほか）→ `bl_execute` で runpy、`bl_screenshot`・`bl_render` で確認） | なし（ヘッドレスの Blender では代替しない） | AGENTS.md：ライブの Blender で作業し、最後に `.blend` を上書き保存する。つながっていなければ作業を止め、接続を頼む |
| 絵（絵コンテの差し替え、カットインの背景の参考） | **Codex CLI の画像生成**（`codex exec -i 参照画像 ...`、image_generation は有効） | Higgsfield `generate_image`（`gpt_image_2_5`、1 枚 1.5 クレジット） | 画像は参考と絵コンテだけに使う。ゲームの UI はフォントとシェーダーで作る（文字のある画像を作らない） |
| 音楽（`sting_versus`） | **Suno**（ユーザーのアカウント。プロンプトは付録 B） | 素材ができるまでは無音のまま進める | Higgsfield の音の道具は音声合成だけで、音楽・効果音は作れない |
| 声 | 使わない | — | ユーザーの決定で、演出に声は入れない（仕様書 D8） |
| 効果音（任意） | CC0 の素材（Kenney・Freesound の CC0） | なし | `assets/audio/sfx/CREDITS.md` に出典を書く。既定では鳴らさない（仕様書 D8） |
| 通しの動画（アニマティック） | **Godot の Movie Maker**（`--write-movie`、`--fixed-fps 60`）＋ **ffmpeg**（`C:\ffmpeg\bin\ffmpeg`）で MP4 | 画面付きテストのスクリーンショットを ffmpeg でつなぐ | `artifacts/online_staging/animatic.mp4` |
| 2 人の通しテスト | **`tests/net/run_pair.py`**（本物のリレーをローカルで起動） | デプロイ済みのリレー（`--relay wss://...`） | リレーは作り直さない（仕様書 D10） |
| 資料の確認・共有 | 組み込みブラウザ（`mcp__Claude_Browser__*`）で HTML を見る。PNG は Edge のヘッドレスで書き出す | — | — |
| 使わないもの | After Effects・Premiere（つながっていない。動きの本物は Godot で作る）、Higgsfield の動画生成（実際の素材と合わない）、コンピューター操作 | — | — |

## 3. マイルストーン

各マイルストーンは、終わった時点でゲームが動き、テストが通る状態にする。目安は作業 1 回（1 セッション）の量で書く。

### M1 ヘリポートを 1 つに作り直し、新しいヘリを置く（1 回）

| 項目 | 内容 |
|---|---|
| 作るもの | ・Blender：`assets/online_heliport/source/blender/` のビルダーを直し、パッド 1 つにする（管制塔・パッド B・渡り廊下を外す）。左のドアが待機のカメラを向く配置とカメラ 7 本（`CAM_Idle`、`CAM_Board`、`CAM_Cockpit`、`CAM_PadLow`、`CAM_Climb` の基準、`CAM_JoinFront`、`CAM_FormationFront` の基準）を配置 JSON に書く<br>・Godot：`OnlineHeliportHelicopter` を `helicopter_boarding.glb` に替える（目印・ドア・ローター・ベルト・灯）<br>・`OnlineHeliportStage` からパッド B・管制塔に関わる部分を外す |
| 道具 | Higgsfield の Blender 連携（ビルダーは runpy、最後に `.blend` を保存）。godot-ai MCP（シーン）。ヘッドレスの `--import` |
| 終わりの条件 | 待機（S0）が仕様の構図で出る。`tests/net/online_menu_runtime.gd` を新しい段階に合わせて直し、通る。`tests/helicopter_boarding_check.gd` が通る |

### M2 ハテナの操縦と、プレイヤーの乗り込み（1.5 回）

| 項目 | 内容 |
|---|---|
| 作るもの | ・Blender（`aiquiz_mascot.blend`）：`Pilot_SitIdle`、`Pilot_Steer`、`Pilot_Wave`、`Pilot_Point` の動きを作る（`Pilot_Sit` は `Pilot_SitIdle` の頭のフレームで足りるので作らない）。骨の向きは設計図の図 7 の表。あわせて、ヘッドセット `Pilot_Headset` と、軽い版（8,000 三角形の LOD）を作る。<br>審判・ノコギリの役に影響しないよう、`mascot_model.glb` は書き出し直さず、動き（`mascot_pilot.glb`）・ヘッドセット（`pilot_headset.glb`）・軽い版（`mascot_model_lod.glb`）を別の GLB にする（`source/build_pilot.py`）<br>・Godot：`_pose_pilot_seated` と、ハテナの骨を直接回すコードをやめ、`AnimationPlayer` で動かす（オンラインのヘリと、本編のヘリの両方）<br>・`scripts/world/online_staging/staging_puppet.gd`：プレイヤー 1 人を UAL のクリップで動かし、目印の間を移し、足の裏の実測で高さを合わせる<br>・S1（乗り込み）と S2（操縦席）を組む |
| 道具 | Higgsfield の Blender 連携。ファイル編集。画面付きの Godot（スクリーンショット） |
| 終わりの条件 | 乗り込みの 7 つの場面（設計図の図 6）がスクリーンショットで確認できる。足が床・ステップに沈まず浮かない（±3 cm）。審判・ノコギリの役が今のまま動く（`tests/mascot_rig_check.gd`） |

### M3 離陸・上昇・検索中の飛行（1.5 回）

| 項目 | 内容 |
|---|---|
| 作るもの | ・`scripts/world/online_staging/online_staging_director.gd`：状態（仕様書「4. 流れ」）と時刻表を管理する<br>・`online_staging_timeline.gd`：時刻・カメラ・速さをまとめた定数<br>・`staging_camera_rig.gd`：カメラの位置・注視点のつなぎ（3 次の加減速）、追いかけの遅れ、ゆっくりした揺れ<br>・`staging_flight.gd`：原点を動かさない飛行（海・雲の流し）、揺れ・傾き<br>・`shaders/online_staging_cloud.gdshader`：雲の層<br>・水しぶきの輪（`GPUParticles3D`＋リングのメッシュ）<br>・S3〜S5、やめる（暗転で戻す）、時間切れ<br>・検索のページを下の帯（`wide_layout`）にする |
| 道具 | ファイル編集。godot-ai MCP（シーンを足す場合）。画面付きの Godot |
| 終わりの条件 | 仕様書の受け入れ基準 A1（S0〜S5 の部分）、A3、A4 が通る。検索中に「高」で 60 fps |

### M4 合流と並走、早めのマッチ、探し直し（1 回）

| 項目 | 内容 |
|---|---|
| 作るもの | ・S6（合流）と S7（並走）：相手のヘリの道すじ、カメラの回り込み、文字の帯、ゲストの塗り替え<br>・早めのマッチの近道（仕様書の表）<br>・相手がいなくなったときの探し直し（D12）：相手のヘリが離れる動き（1.2 秒）、帯の文言、`find_match` をもう一度 |
| 道具 | ファイル編集。画面付きの Godot |
| 終わりの条件 | A1（S6〜S7）、A2 が通る。並走の正面で、左に自分・右に相手が来る |

### M5 VS カットインと読み込み（1.5 回）

| 項目 | 内容 |
|---|---|
| 作るもの | ・`scripts/ui/online/cutin/online_cutin.gd`（`Control`）：パネル・稲妻・VS・名前の帯・ルールの行・ゲージ・待ちの文言<br>・`cutin_actor.gd`：`SubViewport` の中のキャラ（ポーズ 4 種）<br>・シェーダー：`online_cutin_panel.gdshader`（グラデーション・網点・集中線）、`online_cutin_seam.gdshader`（稲妻の光と流れる粒）<br>・ゲーム画面のスレッド読み込み（D9）<br>・旧 `OnlineVersusPage` は、3D の背景が作れないときの予備として残す |
| 道具 | ファイル編集。godot-ai MCP（`theme_manage` を使う場合）。画面付きの Godot。参考の絵は Codex CLI |
| 終わりの条件 | A1（S8〜S9）が通る。名前が 9 文字をこえても帯に収まる。ポーズ 4 種のスクリーンショットを見て、クリップの位置を決め直す |

### M6 中央の線が開く遷移と、開始のそろえ（1 回）

| 項目 | 内容 |
|---|---|
| 作るもの | ・`SceneTransition.hold_versus_split(texture, seam, colors)` と、開くスタイル `versus_split`<br>・`shaders/versus_split_mask.gdshader`（稲妻の多角形で左右を切る）<br>・`OnlineMenu._transition_to_game` をスレッド読み込み＋割れる覆いに置き換え、ホストの `start` を CUTIN_IN の終わりに送る<br>・`ready` に `phase` を足し、`NetGameState` は `start` だけを開始の合図に数える<br>・追加分：`evt reveal_at` で両者の開く時刻をそろえる（来なければ 4 秒で自分だけ開く） |
| 道具 | ファイル編集。`run_pair.py` |
| 終わりの条件 | A5、A6、A7、A10 が通る。SWAP のまわりで 50 ms をこえるフレームがない |

### M7 音・みじかい演出・仕上げ（1 回）

| 項目 | 内容 |
|---|---|
| 作るもの | ・`sting_versus` を組み込む（Suno の素材ができたら。それまでは無音）<br>・効果音のつなぎ（`SFX_ENABLED` は false）<br>・設定に「オンラインの えんしゅつ：ふつう／みじかい」<br>・ローターをぼかした円盤に替える処理、航空灯の点滅、雲の数の品質ごとの切り替え、ハテナの軽い版の切り替え<br>・F7 のデバッグ表示 |
| 道具 | Suno（ユーザー）。ファイル編集 |
| 終わりの条件 | A8 が通る。「みじかい」で各状態の長さが仕様どおり |

### M8 検証・動画・資料（1 回、最後にまとめて）

| 項目 | 内容 |
|---|---|
| 作るもの | ・`tests/net/online_staging_runtime.gd`（時間を固定して状態と長さを確かめ、ショットごとにスクリーンショット）<br>・`run_pair.py --scenario staging`（2 プロセス、名前とポーズの一致、時間の上限、`--quit-at-cutin`）<br>・`tests/perf/online_staging_perf.gd`（フレーム時間）<br>・アニマティック `artifacts/online_staging/animatic.mp4`<br>・`docs/online_menu.md`・`docs/online_versus.md` を更新 |
| 道具 | ヘッドレス／画面付きの Godot、Movie Maker、ffmpeg、`run_pair.py` |
| 終わりの条件 | 受け入れ基準 A1〜A11 がすべて通る。絵コンテ v2 とスクリーンショットを並べた確認の表ができる |

### M9 本編のヘリを新しい機体に替える（段階 2、2 回）

| 項目 | 内容 |
|---|---|
| 作るもの | `HelicopterArrivalDirector` の定数（`PILOT_*`、`GP_PASSENGER_SEAT_LOCAL`、`CABIN_WAIT_PELVIS_HEIGHT` など）を目印に置き換える。高さ・カメラ・画面に収める処理を、2 倍近い大きさに合わせる。オンラインでもヘリ登場を同期して、中央の線が開いたら新しいヘリが 2 人を運んでくるようにする |
| 終わりの条件 | 本編の登場演出のテスト（`.fennara/scripts/runtime/helicopter_*` 系と `tests/` の該当テスト）が通る。オフラインの見た目の確認 |

## 4. 順番と、並べて進められるもの

```
M1 ──▶ M2 ──▶ M3 ──▶ M4 ──┐
  └──▶ M5 ──▶ M6 ─────────┴──▶ M7 ──▶ M8 ──▶（M9）
```

- M5（カットイン）は 3D の飛行とは独立しているので、M1 のあと M2〜M4 と並べて進められる。
- M6 は M5 のカットインを覆いに使うので、M5 のあと。
- M8 のテストは、各マイルストーンで少しずつ足し、最後にまとめて通す。
- 合計の目安：M1〜M8 で 9.5 回、M9 で 2 回。

## 5. ファイルの一覧

| 新しく作るもの | 中身 |
|---|---|
| `scripts/world/online_staging/online_staging_director.gd` | 状態と時刻表、早めのマッチ、探し直し |
| `scripts/world/online_staging/online_staging_timeline.gd` | 調整できる値（時刻・カメラ・速さ） |
| `scripts/world/online_staging/staging_camera_rig.gd` | カメラ |
| `scripts/world/online_staging/staging_flight.gd` | 飛行・流し・揺れ |
| `scripts/world/online_staging/staging_puppet.gd` | プレイヤーの乗り込み |
| `scripts/ui/online/cutin/online_cutin.gd`、`cutin_actor.gd` | カットイン |
| `shaders/online_staging_cloud.gdshader`、`online_cutin_panel.gdshader`、`online_cutin_seam.gdshader`、`versus_split_mask.gdshader` | 雲・カットイン・割れる遷移 |
| `tests/net/online_staging_runtime.gd`、`tests/perf/online_staging_perf.gd` | テスト |

| 変えるもの | 変えるところ |
|---|---|
| `scripts/ui/online/online_menu.gd` | 演出の監督を持つ、`start` の時刻、スレッド読み込み、ゲーム画面への切り替え、探し直し |
| `scripts/ui/online/pages/online_search_page.gd` | 下の帯にする、ともだちコードを大きく出す |
| `scripts/world/online_heliport/online_heliport_stage.gd`、`online_heliport_helicopter.gd` | ヘリポート 1 つ、新しいヘリ、段階の作り直し |
| `scripts/autoload/scene_transition.gd` | `hold_versus_split` と `versus_split` |
| `scripts/core/net_game_state.gd`、`scripts/world/game_world.gd` | `ready` の `phase`、`reveal_at` |
| `scripts/world/helicopter_arrival_director.gd` | ハテナを `AnimationPlayer` で動かす（M2）、目印への置き換え（M9） |
| `scripts/autoload/audio_manager.gd` | `sting_versus`、効果音（切り替えつき） |
| `assets/online_heliport/`（ビルダー・GLB・配置 JSON） | パッド 1 つ |
| `assets/characters/aiquiz_mascot/`（`.blend`・GLB） | 操縦の動き・ヘッドセット・軽い版 |
| `tests/net/online_menu_runtime.gd`、`tests/net/run_pair.py` | 新しい段階、`--scenario staging`、`--quit-at-cutin` |

## 6. テストのコマンド

```powershell
# 構造
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/helicopter_boarding_check.gd
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/mascot_rig_check.gd
# 演出（リレーなし。時間を固定）
./Godot_v4.7.2-stable_win64_console.exe --path . --fixed-fps 60 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_staging_runtime.gd shots=artifacts/online_staging/shots
# 今の画面の導線
./Godot_v4.7.2-stable_win64_console.exe --path . --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_menu_runtime.gd
# 2 人の通し
python tests/net/run_pair.py --headless --scenario staging
python tests/net/run_pair.py --headless --scenario staging --netsim "lat=120,jit=40,stall_p=0.005,stall_ms=200"
python tests/net/run_pair.py --headless --quit-at-cutin   # ホストがカットインで消え、ゲストが探し直す
python tests/net/run_pair.py --headless                 # 今の通し（回帰）
# 重さ
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/perf/online_staging_perf.gd quality=high
# 動画（中央の線が開いてステージになるところまで）
./Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --fixed-fps 30 --write-movie artifacts/online_staging/animatic.avi --script tests/net/net_match_bootstrap.gd -- runtime=res://tests/net/online_staging_runtime.gd movie=1
C:/ffmpeg/bin/ffmpeg -y -i artifacts/online_staging/animatic.avi -c:v libx264 -crf 20 -pix_fmt yuv420p -an artifacts/online_staging/animatic.mp4
# 絵コンテと画面を並べる（A9）
python artifacts/online_staging/make_compare.py
```

## 7. 危ないところと対策

| 危ないところ | 起きること | 対策 |
|---|---|---|
| ハテナが重い（1 体 3.4 万三角形 × 2） | 「低」で 30 fps を割る | M2 で軽い版（8,000）を作り、「低」と遠い所で使う |
| `SubViewport` が重なる | メニューの 3D（`SubViewport`）にカットインの 2 つが加わる | カットインのキャラは、ポーズを当てたあと 1 枚だけ描いて止める（`UPDATE_ONCE`）。息の動きは 2D の縮尺で出す |
| ゲーム画面の読み込みで止まる | SWAP で引っかかる | 検索中からのスレッド読み込み（D9）。覆いの下で準備の描画をする（今のしくみ） |
| `start` の時刻を変えると今のテストが崩れる | `run_pair.py` の通しが失敗する | M6 で `run_pair.py` を新しい時刻に合わせ、今のシナリオも全部通す（A10） |
| ゲストの塗り替えが見える | 色がパッと変わるのが目に入る | 合流のカットの瞬間（同じフレーム）に替える。テストで、替える前後が別のカメラであることを確かめる |
| エディターがゲームを実行中 | godot-ai MCP のシーンの変更・取り込みが止まる | ヘッドレスで取り込み、PackedScene を書き出す（これまでと同じ対処）。ユーザーのゲームは止めない |
| Blender がつながっていない | 3D の作業ができない | 作業を止めて接続を頼む（AGENTS.md）。そのあいだは Godot 側（M3〜M6）を進める |
| Codex のログインが切れる | 絵が作れない | ユーザーに `codex` を起動してもらう。急ぐときは Higgsfield の画像（費用を先に確認） |
| Suno の素材がない | スティングが鳴らない | 無音のまま全部を進め、素材ができたら差し込む（コードの変更は 1 行） |
| 2 倍の大きさのヘリ | 本編（M9）の画面に収まらない | M9 で対処した：ハッチを前のヘリと同じ位置に置き（`HATCH_ANCHOR`）、2P の通り道を奥へずらした（9.4） |
| ゲーム画面の組み立てが重い | SWAP で約 2.2 秒＋2.3 秒止まる（`game_world` の `_ready` と最初のフレーム。読み込み済みでも同じ） | 止まるあいだはカットインの静止画で覆う（今は対策済みの見せ方）。なくすには `game_world` の組み立てを数フレームに分ける（別の作業。9 を参照） |

## 8. 完了の定義

- 仕様書の受け入れ基準 A1〜A11 がすべて通り、その結果（数値・スクリーンショット・動画）が `artifacts/online_staging/` にある。
- 変えた `.tscn` / `.tres` は Godot を通して保存してある。変えた `.blend` は上書き保存してある。
- `docs/online_menu.md`・`docs/online_versus.md`・この計画書の「1. 今の状態」を更新してある。
- 関係のない作業中の変更を壊していない。コミットはユーザーに頼まれたときだけ。

---

## 付録 A 絵（Codex CLI）の頼み方

```text
codex exec -s workspace-write -C <保存先> -i <参照1> -i <参照2> ... - < prompt.txt
```

- 参照には、ヘリの完成イメージ（`artifacts/heli_blueprint/concept/`）、Godot で撮ったヘリ（`assets/vehicles/helicopter_boarding/source/previews/godot_*.png`）、キャラ（`artifacts/storyboard/refs/ref_characters_vs.png`）、ハテナ（`artifacts/mascot/hatena_v1_front.png`）を必ず入れる。
- 毎回入れる決まり：ヘリポートは 1 つだけ。ヘリはオレンジ・白い帯・丸い風防・上に開くドア・左のステップ。ハテナは右の席。絵の中に文字を入れない。
- 絵コンテ v2 のプロンプトは、この計画と同じ日に使ったもの（11 コマ）を基準にする。

## 付録 B 音楽（Suno）のプロンプト：`sting_versus`

BGM リニューアルの「Suno 用シンプル版」に合わせる（`docs/bgm_renewal.md`）。

```text
[Style] bright kids game jingle, playful, punchy, orchestral hits with light synth, F major resolving to B-flat, 120 BPM, 3.5 seconds, big drum hit at 0.3 s, rising brass stab, ends on a clean sustained chord with a short tail, no vocals
[Title] Versus Sting
```

- 長さ 3.5 秒前後の単発。頭の 0.3 秒で大きな一打（カットインの「VS」が落ちる 0.42 秒に合わせて、再生を 0.12 秒早く始める）。
- 書き出しは OGG Vorbis 48 kHz、-14 LUFS。`assets/audio/bgm/sting_versus.ogg`。

## 9. 実施の記録（2026-10-11）

M1〜M8 を実施した。M9（本編のヘリを替える）は、あとからジェットブーストの仕組みと合わせて実施した（9.4）。

### 9.1 マイルストーンごとの結果

| # | 結果 | 計画から変えたこと |
|---|---|---|
| M1 | ヘリポートをパッド 1 つ（対辺 18 m）に作り直した。ヘリは Y 回り -90°（太陽の向きに合わせて待機の画面を順光に）。カメラはビルダーが演出の定数（`online_staging_timeline.gd` の `CAMERAS`）を読んで確認レンダーを作る。`OnlineHeliportHelicopter` を乗り込めるヘリに替え、ドア・ベルト・ブースター・灯・ローターの円盤を動かす | パッドの大きさ（15 → 18 m）。配置 JSON は v2（`helicopter`・`spots.idle`・カメラは確認用） |
| M2 | ハテナの操縦の動き 4 つ・ヘッドセット・軽い版（8,000 三角形）を Blender で作り、`HatenaPilot` が AnimationPlayer で 0.25 秒つないで再生する。乗り込みの足の高さは床・ステップ・敷居で 1 cm 以内（基準 ±3 cm） | `mascot_model.glb` は書き出し直さず別の GLB にした。本編のハテナ（`_pose_pilot_seated`）は M9 で替える |
| M3 | 監督・カメラ・飛び方・雲（MultiMesh の板＋陰影のシェーダー）・水しぶき・やめる（0.35 秒の暗転、実測 0.167 秒で待機へ）・時間切れ | 上昇 45 → 24 m、検索中の高さ 70 m（仕様書 20） |
| M4 | 合流（4 乗の減速、傾きを戻す）・並走（揺れを 0.7 秒ずらす）・早めのマッチ 3 種・探し直し（相手のヘリが去る） | 早めのマッチの速さと長さ（仕様書 20） |
| M5 | カットイン（パネル・稲妻・白い光 1 回・キャラ・VS・名前の帯・札・ルール・ゲージ・待ちの文言）。キャラは 2 つの SubViewport が 1 つの 3D の世界を共有し、1 回だけ描く | ポーズを撮り比べて 2 つ替えた（仕様書 20）。キャラの向きの取り違え（後ろ向き）を直したあと、正面から撮り直して選んだ |
| M6 | `SceneTransition.hold_versus_split` と開くシェーダー。ホストは CUTIN_IN の終わりに `start`。ゲストの `ready{phase:"loaded"}` → ホストの `evt{event:"reveal", at}` で開く時刻をそろえる（4 秒で待つのをやめる）。相手の通信が止まっているあいだは CUTIN_HOLD で待つ | `evt` の形を今のゲームに合わせた |
| M7 | VS のスティングの差し込み口（`AudioManager.play_sting`、素材がなければ鳴らさない）、効果音の時刻表（既定は鳴らさない）、設定「オンラインの えんしゅつ：ふつう／みじかい」、品質「低」の軽い版・ローター・雲の数、F7 のデバッグ表示 | Suno の素材はまだない（付録 B のプロンプトで作る） |
| M8 | 試験・重さ・動画・絵コンテとの比べ・資料 | — |
| M9 | 本編・メニューの迎え・オンラインのヘリ登場を新しいヘリに替えた。ジェットブースト（左右のポッド）を足した | 9.4 |

### 9.2 受け入れ基準の結果

| # | 結果 | 証拠 |
|---|---|---|
| A1 | 通る。BOARDING 3.317・COCKPIT 0.90・TAKEOFF 1.617・CLIMB 2.217・JOIN 1.817・FORMATION 1.40・CUTIN_IN 0.90・CUTIN_HOLD 1.40（60 fps で 1 フレームのずれ） | `online_staging_runtime.gd` |
| A2 | 通る。乗り込み・離陸・上昇の途中のマッチで、決めた近道を通る | 同上 |
| A3 | 通る。乗り込み中・検索中とも 0.167 秒で待機へ | 同上 |
| A4 | 通る。閉じたポートのリレーでホームへ戻り、理由が出る | `online_menu_runtime.gd` |
| A5 | 通る。両者がゲーム画面に入り、カットインの名前とポーズが左右で一致 | `run_pair.py --scenario staging`（`artifacts/online_staging/pair_results/`） |
| A6 | 通る。回線の遅れ（120±40 ms＋停止）でも、マッチからゲーム画面まで 9 秒以内（ホスト 5.3 秒・ゲスト 7.7 秒。遅れなしでも 5.4 秒・7.8 秒） | `--netsim` |
| A7 | 通る。先にカットインに入ったホストが消えると、ゲストは CUTIN_HOLD で待ち、猶予が切れたら空のまま探し直す（2 回目はホームへ） | `--quit-at-cutin`、`online_staging_runtime.gd` の requeue |
| A8 | 一部。演出のあいだは「高」で 99% 点 4.9 ms（約 240 fps）、50 ms を超えるフレームなし（合流のカットで最大 40 ms）。SWAP ではゲーム画面の組み立てで 1 フレームが約 3.9 秒止まる（覆いの下） | `artifacts/online_staging/perf.json` |
| A9 | 見て確かめた。構図・左右・大きさは絵コンテに沿う。並走と合流はカメラを寄せた | `artifacts/online_staging/compare_storyboard.png` |
| A10 | 今の通し（回帰）・押し合い・切断と復帰（3 問目）・試合中の消失（3 問目）がすべて通る | `artifacts/online_staging/pair_results/summary.txt` |
| A11 | ある（約 29 秒、中央の線が開いてステージになるまで） | `artifacts/online_staging/animatic.mp4` |

### 9.3 残したこと

- **SWAP の止まり（A8）**：`game_world` の `_ready`（約 2.2 秒）と最初のフレーム（約 2.3 秒）が重い。キャラの動きのファイルを先に読み込んでも変わらなかった（2.27 → 2.21 秒）。カットインの静止画で覆っているので画面は崩れないが、なくすには `game_world` の組み立てを数フレームに分ける作業が要る。
- **細かいところ**：離陸のときの砂ぼこり（品質「高」だけ）は作っていない。座ったプレイヤーの手を操縦かんの握りに合わせる処理はしていない（`Driving_Loop` のまま）。上昇のときに遠くの港町は映らない（ヘリの向きを太陽に合わせたため、街はうしろになる）。
- **素材**：VS のスティング（Suno、付録 B）。効果音（CC0、既定は鳴らさない）。

### 9.4 M9 とジェットブーストの記録（2026-10-11）

**ジェットブーストの仕組み（Blender、`helicopter_boarding.blend`）**

- 機体の後ろ寄りの肩（高さ 3.08 m）に、前後の軸のヒンジで短い翼が付き、その先にジェットのポッド（半径 0.27 m）がある。左右に 1 つずつ。
- ふだんは翼を 38° 下へたたみ、ポッドを機体の横に沿わせる（胴体とのすき間 4.8 cm）。広げると翼が水平になり、噴射口が真後ろを向く（上端 3.35 m、ローターより 0.65 m 下）。
- 部品：`JetPod_L/R`（翼・ヒンジの筒・ポッド。原点＝ヒンジ）、子に `JetNozzle_L/R`（噴射口の羽根 10 枚。x・y に広げる）と `JetGlow_L/R`（奥の光、材質 `JetGlow`）。機体側の取り付け台は `FrameAndSkids`。三角形 10,012 → 11,244。あとで荷室の丸窓（左右 2 つずつ）をなくした（→ 11,036）。
- 配置 JSON の `jet_boost`：ポッドの軸・`deploy_deg`（左 -38°・右 +38°）・噴射口の出口（ポッドのローカル）・羽根の広げ方（1.35 倍）。
- ビルダーのチェックを足した（たたんだ形が胴体に入らない、広げた形がローターの下）。`tests/helicopter_boarding_check.gd` は 56 → 76 項目。

**Godot**

- `OnlineHeliportHelicopter`：`enable_jets()`（炎を用意）、`set_jet_charge(0〜1)`（0〜55% で翼を上げる、35〜90% で羽根を広げる、45% から奥が光る）、`ignite_jets()`、`set_jet_prewarm()`、`rotor_speed_factor`。メニューの背景のヘリは炎を作らない。
- `HelicopterBoostExhaust` に `size`（左右のポッドは 0.72）。
- `HelicopterArrivalDirector`：今のヘリ（`helicopter_drop.glb`）をやめ、`OnlineHeliportHelicopter` を使う（色替え・ガラス・等倍のハテナ `Pilot_Steer`・ローターの円盤・ジェット）。
  - ハッチ（左右のヒンジの真ん中）を、前のヘリのハッチと同じ位置（`HATCH_ANCHOR`）に置く。縄ばしご・飛び降り・ハッチの開け閉めの調整はそのまま使える。大きな機体はそのまわりに広がる。
  - 機内で待つ位置は目印 `MK_CabinWait`（ハッチの上 0.53 m）。乗ってくるときもここ（`GP_PASSENGER_SEAT_LOCAL` をやめた）。
  - 発進：降ろしたあと（1.8 秒の溜め）と迎えのあと（0.8 秒の溜め）に、ポッドを広げて光らせ、点火する。
  - 2 人のとき、2P の通り道を奥へ 8 → 11.5 m、上へ 1.2 → 1.6 m ずらした（ローターの直径 10.6 m）。試験の間隔の基準も 10 → 10.8 m。
  - 消した定数・関数：`PILOT_*`、`WINDOW_GLASS_COLOR`、`COCKPIT_LIGHT_ENERGY`、`MAIN/TAIL_ROTOR_SPEED`、`GP_PASSENGER_SEAT_LOCAL`、`_apply_body_tint` ほか小さいハテナの姿勢の関数。
- オンライン：`game_world.gd` でオンラインでもヘリ登場を作る。中央の線が開いたあと、両方の画面がそれぞれ 2 機を飛ばし、2 人とも着地してから開始の合図（ゲストの `ready` → ホストの `trigger_start`）が出る。
- メニューの台本 `menu_helicopter_sequence.tscn` の確認用のヘリ（エディタだけで見える）を新しいヘリに替えた（ハッチがそろう位置）。
- 起動時の予熱（`startup_visual_warmup.gd`）で新しいヘリ・ローターの円盤・ジェットの光と炎を 1 回描く。起動の読み込み一覧も新しい GLB に替えた。

**確かめたこと**

| 試験 | 結果 |
|---|---|
| `tests/helicopter_boarding_check.gd` | 76 項目すべて通る |
| `tests/helicopter_crossing_bootstrap.gd -- --resources` | 通る |
| `helicopter_crossing_runtime`（1 人・2 人、画面つき、スタートからゲーム画面の着地まで） | 迎え・手の位置・降ろし・着地・前へ進み続ける・画面の外へ消える、2 機の間隔 12.56 m（2 人）がすべて通る。1 つだけ落ちる：スタートを押した直後の 1 フレームの止まり（70〜150 ms、基準 50 ms）。元のヘリでも 71 ms で落ちるので、今回の変更の前からある（監督が動き出す前のフレーム） |
| `run_pair.py --scenario staging`（オンライン、画面つき） | 両方の画面でヘリ登場があり、2 人とも着地してから始まり、10 問目まで進む。名前とポーズも一致。マッチから中央の線が開くまで 10.7 秒で、基準 9 秒を超えた。同じ日にヘリ登場を止めて流しても 9.98 秒で超えていた（M8 のときは 7.76 秒）。ヘリ登場で増える分は約 0.7 秒（ゲーム画面の準備 2.85 → 3.6 秒） |
| `online_staging_runtime.gd`・`online_menu_runtime.gd` | 73 項目・32 項目すべて通る |

画面の証拠：`artifacts/helicopter_crossing/m9_p1_sheet.png`・`m9_p1_depart.png`・`m9_jet_zoom.png`・`m9_p2_sheet.png`、`artifacts/net/arrival_pair.png`、Blender の確認レンダー `assets/vehicles/helicopter_boarding/source/previews/hb_07〜09`。

**残したこと**

- スタート直後の止まり（上）と、A6 の 9 秒（マシンの状態で 2 秒以上ぶれる。ゲーム画面の組み立ての重さは 9.3 の SWAP と同じ）。
- メニューに入ったときのヘリ到着（`setup_menu_preview`）は今は呼ばれていない。新しいヘリでも動く形にしてあるが、画面では確かめていない。
- 前のヘリ（`assets/vehicles/helicopter/`）のファイルは消していない（どこからも読まれない）。


### 9.5 ヘリの作り込みの記録（2026-10-11）

かわいい形のまま、機械の作り込みとデカールを足した（素材の README と `source/blender/SCENE_PASSPORT.md` を書き直した）。

- **形**：屋根のカバー・吸気口・排気・アンテナ、ローターの頭（スワッシュプレート・ピッチリンク）と 3 枚の羽根、フェネストロンの尾（直径 0.90、羽根 10 枚）、
  機首の機器（ワイヤーカッター・ピトー管・サーチライト・ミラー・ワイパー）、ヒンジとホイスト、側面の通気口・給油口、腹のアンテナ・カーゴフック、
  スキッドの金具とすり板、ジェットのシェブロン、コックピット（画面 4・計器 4・無線 3・コンソール・天井のパネル・仕切りの紋章・消火器・ヘッドセット）
- **塗り分け**：帯より下と尾翼は濃紺 `BodyAccent`（色替えしない）。白い帯の上下に細い線。機首で 3 本が V に集まる
- **デカール**：1 枚のアトラス（2048²）。尾の筒のロゴ・腹のロゴ・尾翼の機体番号・ドアの紋章・細い線・ハッチの黄黒の帯・計器盤の銘板。
  機体番号は `set_livery_slot`（自分の機と相手の機で AQ-01 / AQ-02、ヘリ登場はプレイヤーの番号）
- **Godot**：`prepare_surface_material`（クリアコート・ガラスのシェーダー・デカール）、`apply_quality`、羽根と尾のファンのぼかし、尾のストロボ。
  座席・操縦かん・ステップ・床下ハッチの井戸と枠を親のメッシュにまとめ、面を 91 → 78 にした
- **数**：三角形 11,036 → 35,558、面 74 → 78、材質 15 → 19、テクスチャ 0 → 1

**確かめたこと**

| 試験 | 結果 |
|---|---|
| ビルダーの checks（ライブの Blender） | 61 行すべて通る（ドア・ポッドの通り道、ローターとの隙間、客室の決まり、デカールのすき間・覆い・UV、GLB の中身） |
| `tests/helicopter_boarding_check.gd` / `helicopter_boarding_bootstrap.gd` | 108 項目 / 16 項目すべて通る |
| `online_staging_runtime.gd` | 73 項目すべて通る（足の床・ステップ・デッキ 0.01） |
| `online_staging_perf.gd`（1920x1080） | 2 機の並走（S7）の描く回数：高 859 → 824（上限 945）、中 219 → 240、低 215 → 239（上限 400）。p99 はどの場面も 7 ms 以下 |
| `startup_loading_bootstrap.gd` | 30 項目すべて通る（`helicopter: true`） |
| `helicopter_crossing_bootstrap.gd`（2 人） | 前からある 1 つ（スタート直後の止まり）だけ落ちる：作業前 145.7 ms → 124.1 ms |
| デカールの遠景（26 m、`mesh_lod_threshold` 1.5） | ロゴ・紋章・細い線が沈まない（`source/previews/godot_lod26.png`） |

画面の証拠：Blender の確認レンダー `assets/vehicles/helicopter_boarding/source/previews/hb_01〜24`、Godot の `godot_pair`・`godot_number_a/b`・`godot_lod26`、
演出のスクリーンショット `artifacts/online_staging/shots_after/`。作業前の写しと計測は `source/blender/backups/20261011_194151_before_detail/`。

**残したこと**

- ドアの支柱（計画の 10b、任意）は作っていない。
- ヘリポート（`online_heliport.blend`）は作り直していない。`ohp_common.py` はローターの半径と尾の位置を layout から読むように直し、式だけで確かめた。

### 9.6 カメラワークの作り直しの記録（2026-10-11）

乗り込み〜検索中（S1〜S5）のカメラを、止まった画の切り替えから動き続けるカメラに作り直した（仕様書 v1.2「21. カメラワーク」）。状態・長さ・通信は変えていない。

- **作ったもの**：`staging_shots.gd`（`StagingShots`：状態の時刻からカメラの目標を作る。時刻で通る 3 次の曲線・被写体を画面の決めた位置に置く `compose`・検索中の球面の回り込み）。
  `staging_camera_rig.gd` を書き直した（臨界減衰のばね・画面の傾き・ただよい・ピント送りとぼけ・`cut_count`）。API（`cut`・`cut_to`・`blend_to`・`update`・`follow_lag`）は今のまま
- **ショット**：乗り込みは 1 本の長回し、操縦席はドリーイン、離陸はクレーン、上昇はフライバイ（港町とヘリポートを背に迫ってくる。9.3 の「上昇のときに遠くの港町は映らない」もこれで解消）、
  検索中は空撮の 6 本（追う・真横・正面の顔・高い 3/4・遠景・低い所。一巡り 54 秒）。カメラはずっと機体の左（太陽の側）
- **タイムライン**：`CAMERA_RIG`・`SUBJECTS`・`MOVE_*`・`CRUISE_SEQUENCE` などを足し、使わなくなった `CAM_Climb`・`CAM_Cruise1〜3`・`CRUISE_SHOTS`・`BOARD_CAMERA_*`・`FOLLOW_LAG` を消した。
  `CAM_Idle`・`CAM_Board`・`CAM_Cockpit`・`CAM_PadLow` はヘリポートのビルダーが読むので、値も書き方も変えていない
- **試験**：`online_staging_runtime.gd` にカメラの確かめ（仕様書 A12）と `cruise=秒` を足した

**確かめたこと**

| 試験 | 結果 |
|---|---|
| `online_staging_runtime.gd`（全シナリオ、`cruise=48`） | 111 項目すべて通る（作業前の通常のシナリオは 40 項目）。切り替えのほかの最大の速さ：通常 16.1 m/秒・62.9°/秒（検索中の高い 3/4 → 遠景のつなぎ）、探し直し 18.3 m/秒。飛んでいるヘリへの最短 12.9 m。被写体の画面の位置は決めた値と ±0.02 で合う |
| `online_staging_perf.gd`（高・ふつう） | 演出のあいだの 99% 点：高 4.94 → 5.07 ms、ふつう 4.79 ms。50 ms を超えるフレームなし（ぼけを足しても 240 fps の上限のまま） |

画面の証拠：`artifacts/online_staging/camera_pro/`（`before/` 作業前、`v3/` 作業後、`final/camera_pro.mp4` 通しの動画、`final/perf_*.json`）。

### 9.7 v1.3：長い場面・ジェットブーストの急発進・ジェットで来る合流（2026-10-12）

ユーザーの依頼（場面を長く／Helldivers 2 のような急発進 → 暗転してマッチング画面へ／相手は画面の外からジェットブーストで曲がりながら来る／合流のあと・待機中はジェットを切る）。仕様書 v1.3「22」。

- **長さ**：乗り込み 4.70・操縦席 2.40・離陸 2.60・急発進 4.40・合流 3.20・並走 1.80 秒（みじかい 2.94・なし・1.60・3.00・2.20・1.20）。検索中のショットは 12 秒（つなぎ 3 秒）。
  早めのマッチの乗り込みは 2.0 → 2.6 倍（歩く速さを前と同じくらいに。乗り込みが長くなった分で、ゲストのマッチから開くまでが 11 秒を超えたため）
- **急発進（CLIMB）**：`StagingFlight.departure`（離陸から点火のあとまで止まらずに旋回しながら飛ぶ 1 本の道すじ。仕様書 24）・`boost_charge`・`boost_shudder`、監督の `_update_boost`。離陸からカメラを切らずに 1 本で撮る（投光器の柱を避けて左前から）。点火で `StagingCameraRig.kick`
- **暗転**：監督の `fade` を `OnlineMenu` の `StageFade`（3D の上・帯の下）に当てる。検索中に入ると 0.6 秒で明ける
- **合流（JOIN）**：`StagingFlight.join(u, 秒)`（流れを足した進む向き・横の加速度で傾く・減速で機首を上げる）、`StagingShots.join`（左前の斜め上）。`CAM_Join` は消した
- **ジェット**：`OnlineHeliportHelicopter.extinguish_jets`・`stow_jets`、`HelicopterBoostExhaust.extinguish` を足した。炎はヘリポートを組み立てるときに作り、画面を開いた最初の 3 フレームだけ 3D を黒く覆って 2 機の炎を描く

**確かめたこと**

| 試験 | 結果 |
|---|---|
| `online_staging_runtime.gd`（全シナリオ、`cruise=60`、画面つき） | 133 項目すべて通る。新しい長さ（A1）、溜め・点火・上昇の高さ 22.5 m・暗転 0.89 → 検索中は真っ黒から明ける・検索中と並走でジェットが切れている・相手が画面の外（4.0, 2.0）から入る・曲がるときの傾き 25.9°・合流の終わりで相手のジェットが切れている |
| `online_menu_runtime.gd` | 32 項目すべて通る |
| `online_staging_perf.gd`（高・ふつう） | 演出のあいだの 99% 点 6.2 ms・4.8 ms。急発進の最大 12.6 ms・4.9 ms、合流の最大 41.6 ms・45.4 ms（作業前 41 ms 前後）。予熱を入れる前は点火で 434 ms・合流で 421 ms 止まった。ふつうの 1 回目は合流で 104 ms が 1 回出て、2 回目は出なかった |
| `run_pair.py --scenario staging`（画面つき） | 2 人ともゲーム画面に入り、ヘリ登場（2 機・着地してから開始）、10 問目まで進む。マッチから開くまで 12.15 秒（After Effects の書き出しを同時に動かしていたとき）・12.58 秒（止めたあと）で、A6（11 秒）を超えた。演出の分はホスト 5.1 秒・ゲスト 7.7 秒（ゲストは乗り込みの途中でマッチ）で、残りの 4.5〜4.9 秒はゲーム画面の準備（9.3・9.4 の重さ）。ヘッドレスではヘリ登場が作られない（`helicopters: 0`）ので、ヘリ登場の判定は画面つきで見る |

画面の証拠：`artifacts/online_staging/camera_pro/v6/`（スクリーンショット）、`final_v13/staging_v13.mp4`（通しの動画）、`final_v13/perf_*.json`、`final_v13/pair_staging*.log`。

### 9.8 VS カットインの After Effects 版（2026-10-12）

ユーザーの依頼「マッチング時の対峙のアニメーションを AE で作り直す」。ゲームの中のカットイン（`scripts/ui/online/cutin/`）は変えず、AE で作り直した版を別に作った。中身と作り直し方は `tools/online_cutin_ae/README.md`。

- AE のプロジェクト `tools/online_cutin_ae/AIQUIZ_VS_Cutin.aep`（主のコンポ `VS_Cutin`、1920×1080・60 fps・4.6 秒、マーカー IN／HOLD／LOOP／REVEAL／END）。`build_vs_cutin.jsx` でいちから組み直せる（開いているプロジェクトは保存せずに閉じるので、手で直したところはスクリプトへ写してから）
- 書き出し：`artifacts/online_cutin_ae/VS_Cutin_host.mp4`・`VS_Cutin_guest.mp4`（H.264・60 fps・4.6 秒）と確認シート。キャラはゲームの箱のキャラを `tests/online_cutin_ae/capture_cutin_chars.gd` で撮った（4 ポーズ × 2 色 × 左右）
- 時刻は仕様書 S8〜S10 に合わせた（パネル 0.30、稲妻 0.24〜0.32、白い光 1 回 45%、キャラ 0.30〜0.60、VS 0.42〜0.68、名前 0.55〜0.85、ルール 0.70〜0.90、1.2〜3.6 秒がつなぎ目のないループ、3.6〜4.3 秒で割れて開く）。ループのため、息は 2.4 秒・VS の脈は 1.2 秒・星は毎秒 12.5° にした
- ゲームへの組み込みはしていない（名前・帽子・スキンが試合ごとに変わるため、書き出した動画をそのまま使うことはできない）

### 9.9 v1.4：稲妻が走って割れて開く（2026-10-12）

ユーザーの依頼：読み込みが終わったら、両陣営の色をまぜた稲妻が切れ目を上から下へ走り、そこから派手に・壮大に開く。仕様書 v1.4「23」。

- `shaders/versus_split_mask.gdshader` を書き直した（稲妻・溜め・割れて飛ぶ・光の壁・光の筋・衝撃の輪。太さは画面の高さに合わせる）
- `SceneTransition`：`hold_versus_split` に左右の色を足し、`_reveal_versus_split` は `_update_split_fx` で時刻ごとに動かす。火花は `CPUParticles2D` を 2 つ（左右の陣営の色）。2D の揺れは覆いの位置をずらす
- REVEAL の長さ 0.70 → 1.80 秒（みじかい 0.60 → 1.30）。開き始める時刻は変わらない（A6 は開き始めまでを測る）
- 見る道具：`tests/net/versus_split_probe.gd`（静止画 2 枚で、この遷移だけを決めた時刻で撮る）
- AE 版（9.8）も同じ設計で REVEAL を作り直した（`VS_Cutin` は 5.6 秒・60 fps、REVEAL は 3.60 秒から 1.80 秒。マーカー CHARGE・BURST を足した）。書き出した動画の明るさは REVEAL のあいだ平均 151 → 168 までで、画面全体を白く光らせていない
