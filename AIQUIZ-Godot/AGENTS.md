# 回答の言語

ユーザーへの回答は必ず日本語で書く。説明・報告・質問・作業途中の短い経過報告もすべて日本語にする。
コード、識別子、コマンド、ファイルパス、エラーメッセージの引用など、原文のままにすべきものはそのままでよい。

# Godot AI MCP

This project uses Godot AI (`godot-ai`) with the addon at `addons/godot_ai/`.
Read `addons/godot_ai/README.md` for setup. The connected MCP tool schemas
define the available operations and their exact arguments.

Before Godot-aware operations, confirm the active editor session targets
`C:/AIQUIZ/AIQUIZ-Godot/`. Use Godot-aware scene and resource operations for
`.tscn`, `.tres`, and `.res` edits, and save editor mutations explicitly.
Use ordinary repository tools for source searches and diffs.

Validate affected scripts and resources after edits. For gameplay or visual
changes, verify the actual running game and relevant screenshots; distinguish
structural checks from runtime evidence. Preserve unrelated worktree changes.

# バージョン更新の公開（Windows 版）

ユーザーから「更新を出して」「バージョンを上げて公開して」などと頼まれたら、必ず次の手順で行う。
ファイルを手でアップロードしたり、手順を飛ばしたりしない。しくみと背景は `docs/game_update.md`。

1. 出す内容を確かめる。パッチには、いまの作業フォルダの中身がそのまま入る（コミット済みかどうかは関係ない）。
   作りかけの変更が混じっていそうなら、先にユーザーに確かめる。
2. `project.godot` の `config/version` を上げる。番号の指定がなければ、末尾を 1 上げる。
   エディターが開いているときは Godot AI の `project_manage`（`settings_set`、key は `application/config/version`）で変える。
3. パッチを作る。`--notes` は、プレイヤーの画面に出る短い説明。

   ```
   python tools/release/make_patch.py --notes "直した内容"
   ```

4. 配ったフル版にパッチを当てて、自動で起動して確かめる（ゲームのウィンドウが 1 分ほど開く）。

   ```
   python tools/release/verify_patch.py
   ```

5. 公開する。ユーザーが公開まで頼んでいるときは、そのまま実行する。頼まれたのが「作るところまで」なら、公開の前に確かめる。

   ```
   python tools/release/deploy_update.py
   ```

6. https://testopia-updates.web.app/windows.json が新しい版になったことを確かめて、版・パッチの大きさ・検証の結果を報告する。

守ること:

- スクリプトが止まったら、出た理由をそのままユーザーに伝える。`--skip-verify` や `--allow-settings-change` で
  先へ進めるのは、ユーザーがそう指示したときだけ。
- `make_patch.py` が「設定が変わっている」「patch_boot.gd が変わっている」で止まったら、その更新はパッチでは届かない。
  フル版の配り直しが要ると伝え、`docs/game_update.md` の「フル版を配り直すとき」に従う。
- `tools/release/base.json`、`tools/release/base_project_settings.txt`、配ったフル版のフォルダ
  （`build/TESTOPIA_v<版>_Windows/`）は、消さない・手で書き換えない。パッチはこのフル版との差分で作る。
- 公開した更新は、起動した人にすぐ届き、取り消せない（もう更新した人は元に戻らない）。
  公開後に問題が見つかったら、版を上げて直したパッチを同じ手順で出す。
- `PatchBoot` は `[autoload]` の先頭のままにする。

# Blender（3D制作）

3Dモデル・シーンを制作／修正するときは、ユーザーが開いているライブのBlenderで作業する。

- 作業前に Higgsfield プラグインの `get_host_status` で Blender（`blr`）が接続済みか確認する。
- 未接続なら作業を始めず、ユーザーに Higgsfield のBlender連携を接続するよう依頼して待つ。
  `blender --background` など別プロセスのヘッドレスBlenderで代替しない。
- 接続済みなら `bl_*` ツールでライブのBlenderを操作し、途中経過がユーザーの画面に見えるようにする。
- ビルドスクリプト（`build_*.py` など）を使う場合も、ヘッドレス起動ではなくライブのBlender上で実行する。
- Blenderで作業したら、最後に必ず作業した `.blend` を上書き保存する（ユーザーの確認は不要）。
  保存しないと、次にBlenderから書き出し直したときに変更が失われる。
