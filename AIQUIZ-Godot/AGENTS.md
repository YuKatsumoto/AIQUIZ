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

# Blender（3D制作）

3Dモデル・シーンを制作／修正するときは、ユーザーが開いているライブのBlenderで作業する。

- 作業前に Higgsfield プラグインの `get_host_status` で Blender（`blr`）が接続済みか確認する。
- 未接続なら作業を始めず、ユーザーに Higgsfield のBlender連携を接続するよう依頼して待つ。
  `blender --background` など別プロセスのヘッドレスBlenderで代替しない。
- 接続済みなら `bl_*` ツールでライブのBlenderを操作し、途中経過がユーザーの画面に見えるようにする。
- ビルドスクリプト（`build_*.py` など）を使う場合も、ヘッドレス起動ではなくライブのBlender上で実行する。
- Blenderで作業したら、最後に必ず作業した `.blend` を上書き保存する（ユーザーの確認は不要）。
  保存しないと、次にBlenderから書き出し直したときに変更が失われる。
