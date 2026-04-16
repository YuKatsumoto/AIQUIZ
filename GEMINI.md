ターミナルUTF-8強制: run_commandツール使用時、以下を必ず適用すること。
これを怠ると日本語の文字化けが原因で、無限ループやクラッシュが起きる。

- PowerShell: コマンド冒頭に [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; を付与
- CMD: コマンド冒頭に chcp 65001 > nul && を付与
- Python実行時: $env:PYTHONUTF8=1; を前置
- ファイル書き込み(Set-Content等): -Encoding UTF8 を必ず明示
# AIQUIZ Project Knowledge

## アーキテクチャ構成
- Godot 4.3 3Dプロジェクト (元々はPython製アプリからの移植)
- データベース: Firebase (Realtime Databaseでクイズの評価などを蓄積)
- クイズシステム: 
  - オンライン (LLM動的生成) モード
  - オフライン (`offline_bank.json`) モード。tools内のPythonエージェントによって問題が高品質化・注入されている。
- ゲームサイクル: 前方に迫ってくるクイズの壁（ドア）に対し、正解のドアを選択し通り抜けるトレッドミル型ランナー。

## 開発上の注意点・ベストプラクティス (Gotchas)
- **Godot 4 の SubViewport クラッシュ**:
  カメラの映像をUIに表示するワイプ（Pic-in-Pic）機能において、非表示化のために `sub_viewport.world_3d = null` を行うとレンダリング側の依存解決で強制終了（クラッシュ）する場合がある。非表示にする際は `visible = false` および `render_target_update_mode = UPDATE_WHEN_PARENT_VISIBLE` を用いて、参照を維持したまま描画のみを止めるのが安全。
- **2P（マルチプレイ）の状態管理とタイマー**:
  `game_state.gd` の `update` サイクルにおいて、片方のプレイヤーが死亡していても、もう片方が生存していれば `STATE_PLAYING` が維持される。死亡したプレイヤーの爆発演出（タイマー進行）を進めるため、死亡者用のタイマー更新処理を `else` や `elif` で独立して回し続ける必要がある。また、次の問題（次の壁）へ進んだ際（`advance_after_correct`）に、進行途中の死亡演出を中断させないため、生きているプレイヤーのタイマーのみをリセットするように設計されている。
- **マグマの座標と判定**:
  マグマの表面はおおよそ `Y = -10.0`。キャラクターの死亡時の落下限界を `Y = -8.0` 付近にClampすることで、キャラクターがマグマに「完全に沈みきらず」視認可能な状態で爆発エフェクト（Yオフセット +2.0 付近で再生）を発生させることができる。- **正解時のノーストップ進行**:
  正解ドアを通過した際、`STATE_CORRECT` への遷移（約1秒停止）は行わない。`STATE_PLAYING` のまま即座に `advance_after_correct()` を呼び、プレイヤーが停止せずに次の問題へ走り続ける設計。正解メッセージ（"正解！"）は `correct_flash`（0.7秒で減衰）と連動した短時間表示で視覚フィードバックを維持する。
- **正解ドアの物理崩壊**:
  `quiz_wall.gd` の `break_door()` では、元のドアを非表示にして代わりに4つの `RigidBody3D` 破片を生成し、前方（-Z）+ 上方に `apply_impulse()` で吹き飛ばす。破片は `collision_layer = 0` でプレイヤーに干渉せず、3秒後に `queue_free()` で自動クリーンアップされる。
- **ハイスコアシステム**:
  `HighscoreManager` (Autoload) が `user://highscores.json` にローカル保存。キーは `{学年}_{教科}_{難易度}_{モード}` で各カテゴリ上位5件を保持。`game_state.gd` の `_game_over()` と `clear_game()` から `_submit_highscore()` が呼ばれ、`is_new_record` フラグでHUDに `NEW RECORD!` を表示する。メインメニューの `🏆 ランキング` ボタンで全カテゴリのベストスコアを一覧表示。
