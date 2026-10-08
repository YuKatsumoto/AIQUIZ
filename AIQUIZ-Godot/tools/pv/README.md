# PV（ゲームクリエイター甲子園2026 応募用の紹介動画）

実際のゲームを自動で操作して撮影し、AEとffmpegで約60秒のPVに組み立てる手順。ゲーム本体の挙動は変えない。

## 流れ

1. **撮影**：`tools/pv/capture.ps1`（まとめて撮るときは `capture_all.ps1`）。
   - Godot が `tests/pv/pv_bootstrap.gd` → `tests/pv/pv_runtime.gd` → `tests/pv/shots/<shot>.gd` の順に動く。
   - 出力先は `G:/aiquiz_pv_raw/<shot>_t<take>/`。
2. **中間ファイル**：`python tools/pv/encode.py G:/aiquiz_pv_raw/<shot>_t<take> --preview`
   - 区間ごとに `artifacts/pv/mezz/<shot>_t<take>_<区間>.mov` を作る（ProRes 422 HQ、1920×1080、60fps、PCM 48kHz）。
   - 確認用に `artifacts/pv/review/` へ、0.5秒ごとのコンタクトシートと小さいmp4を作る。
3. **仮編集**：`python tools/pv/rough_cut.py [--bgm 曲.wav]`
   - `tools/pv/edit.json`（カット表）から、テロップ付きの `artifacts/pv/final/AIQUIZ3D_PV_rough.mp4` を作る。
4. **仕上げ**：After Effects 2026。AEを開いた状態で、ローカルのHiggsfield AEブリッジ経由で実行する。
   - `node assets/aiquiz_menu_stage/source/ae/ae_run.mjs tools/pv/ae/build_pv.jsx artifacts/pv/ae_build.json`
     - 同じ `edit.json` から `tools/pv/ae/AIQUIZ_PV.aep`（`PV_Master` と `PV_Thumb`）を組み立て直す。
     - 組み立て直すと、AE上の手直しは消える。
   - `node assets/aiquiz_menu_stage/source/ae/ae_run.mjs tools/pv/ae/queue_pv.jsx artifacts/pv/ae_queue.json`
     - `PV_Master` をレンダーキューに入れる（最良設定・高品質・音声あり）。
     - サムネイルを `artifacts/pv/final/AIQUIZ3D_thumbnail.png` に、確認用の静止画を `artifacts/pv/review/ae/` に書き出す。
   - `"G:/adobe/Adobe After Effects 2026/Support Files/aerender.exe" -project C:/AIQUIZ/AIQUIZ-Godot/tools/pv/ae/AIQUIZ_PV.aep`
     - `artifacts/pv/final/AIQUIZ3D_PV_master_ae.mov` を書き出す。
   - BGMの差し替えやテロップの手直しは、AE上で直接行ってもよい。
     - その場合は、`queue_pv.jsx` 以降だけをやり直す。
   - AEが応答しないときは、AEにダイアログ（ディスクキャッシュの警告など）が出ていないかを確かめる。ダイアログが出ている間、スクリプトは実行されない。
5. **提出ファイル**：`python tools/pv/finalize.py`
   - AEのマスターから `artifacts/pv/final/AIQUIZ3D_PV.mp4` を作る。
     - H.264 High、1920×1080、60fps、AAC 320k。
     - 2パスで −14 LUFS／−1 dBTP に揃える。
   - 同時に検査して、結果を `AIQUIZ3D_PV.check.json` に書く。
     - 検査項目：mp4、15〜90秒、全フレームのデコード、黒画面、静止区間、音量、サムネイルが16:9か。
     - 1秒ごとのコンタクトシート `AIQUIZ3D_PV.contact.jpg` も作る。
   - サムネイルのJPEG版も作る。

## BGMの差し替え

今は仮BGMとして `artifacts/pv/bgm_temp.wav` を使っている（`edit.json` の `"bgm"`、音量は `"bgm_db"`）。

仮BGMは応募作品に使わない。本番の曲を用意したら、次のどちらかで差し替える。

- **`edit.json` で差し替える場合**
  1. `"bgm"` に曲のパスを書く（約60秒以上、WAV 48kHz 推奨）。
  2. `build_pv.jsx` → `queue_pv.jsx` → `aerender` → `finalize.py` の順に実行する。
  - 曲は60秒で切れて、最後の1.5秒でフェードアウトする。
- **AE上で差し替える場合**
  1. `PV_Master` の `BGM` レイヤーの素材を選び、「ファイル」→「フッテージの置き換え」で曲を選ぶ。
  2. 保存して、`queue_pv.jsx` 以降を実行する。

## 出力（`artifacts/pv/final/`）

| ファイル | 内容 |
|---|---|
| `AIQUIZ3D_PV.mp4` | 提出用。本番のBGMを入れてから `finalize.py` で作る |
| `AIQUIZ3D_PV_tempBGM.mp4` | 確認用。仮BGM入り。**提出しない** |
| `AIQUIZ3D_PV_noBGM.mp4` | 確認用。ゲームの効果音だけ |
| `AIQUIZ3D_PV_rough_v1.mp4` | ffmpegの仮編集（最初の版） |
| `AIQUIZ3D_thumbnail.png` / `.jpg` | サムネイル（1920×1080） |
| `*.check.json` / `*.contact.jpg` | 検査結果と、1秒ごとのコンタクトシート |

## 撮影のしくみ（`tests/pv/pv_runtime.gd`）

- **映像**：Movie Maker（`--write-movie`）はプロジェクトの基本サイズ1280×720でしか書かない。そこで、録画中は1920×1080のルートビューポートを毎フレームJPEG（品質0.95）で保存する。ファイル名は `Engine.get_frames_drawn()` の番号。
- **音声**：Movie MakerのAVIを使う。AVIのフレーム0は撮影開始時に出す白い1フレーム（`marks.json` の `sync_frame`）で、JPEGの番号と一致する。区間の音声は、AVIの `[first/60, (last+1)/60]` 秒。
- **待ち方**：撮影は実時間より遅く進む（37%前後）。そのため待ちはすべてフレーム数で数え、実時間の待ちは使わない。
  - メニューのヘリ出発には実時間12秒のガードがあるので、撮影スクリプトは `begin_game_start_departure()` を呼んで、出発の完了をフレームで待つ。
- **問題**：`tests/pv/pv_quizzes.json` に、Geminiが実際に作った問題を写してある。`GeneratingProvider` がそれを1問ずつ渡すので、「クイズ準備中 n/10」と壁の出現は本物の画面になる。問題が届き始めるのは画面が開いてから。
- **ユーザーデータの保護**：開始時に `user://` のファイルを控え、終了時に元へ戻す。控えは `<take>/user_backup/` にもあり、撮影が途中で止まったときは `tools/pv/restore_user.ps1 -Take <dir>` で戻せる。
  - 評価ボタンはスタブに差し替え、Firebaseへは送らない。
  - お知らせ欄（リモートの文言）は隠す。
- **音量**：撮影中は効果音0.8・BGM0に固定する（BGMはPVで別に付ける）。

## カット（`tests/pv/shots/`）

| shot | 内容 | 区間 |
|---|---|---|
| `intro_solo` | 1P・算数3年。設定行の切り替え → Start → ヘリのお迎え → クイズ準備中 n/10 → 準備完了 → カウントダウン → 10問（3問目だけ不正解）→ ゴール → クリア → 履歴（解説・評価） | menu_config, heli_pickup, generating, flyover, play, goal, history |
| `duo` | 2P・理科。ヘリ2機 → 生成 → カウントダウン → 押し合い → 不正解のあと、刃の列の右後ろ上からのカメラで、回転する刃と逃げる2人を撮る（捕まらない）→ ゴール → スコアタワー | heli_pickup, generating, countdown, push_n, saw, play, goal, finale |
| `cam_test` | 調整用。2Pのプレイ中に、刃を基準にした構図をいくつか0.6秒ずつ撮る（PVには使わない） | cam_n |
| `sea_solo` | 1Pが床の端から海に落ち、サメが来る | sea |
| `subject_walls` | 理科・国語・社会・英語の1枚目の壁を正面から | wall_<セット> |
| `menu_clean` | タイトル画面の3D背景だけ（UIなし）。エンドカード用 | menu_bg |

## 確認

```powershell
python tools/pv/encode.py G:/aiquiz_pv_raw/intro_solo_t2 --preview
& C:/ffmpeg/bin/ffmpeg.exe -v error -i artifacts/pv/final/AIQUIZ3D_PV_rough.mp4 -f null -
```
