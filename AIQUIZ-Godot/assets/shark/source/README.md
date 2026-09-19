# サメのアニメーション

`shark_swim_with_jaw.blend` を開き、右上のシーン選択から切り替えて Space で再生します。

- `01_SharkSwim`: 尾へ順に伝わる左右の泳ぎ。30 fps、1–48 フレームのループ。
- `02_SharkBite`: 口を閉じたままの突進動作。30 fps、1–13 フレーム。

口の開閉は無効です。元のメッシュ、口の形、UV、テクスチャを保っています。
10 本のボーンを備え、リグを選んで Pose Mode で編集できます。
保存した各シーンでは一つの Action だけが動きます。

再生成する場合は、この blend の `01_SharkSwim` シーンで
`rebuild_shark_animation.py`、`setup_shark_preview.py` の順に実行します。
前者がゲーム用 `../shark_swim.glb` を書き出し、後者がプレビューと blend を保存します。
旧 `build_shark_jaw.py` は以前の開閉用スクリプトです。今回の再生成には使用しません。

ゲーム用 GLB の泳ぎは 1.6 秒、突進は 0.4 秒です。
2026-09-15: 通常遊泳の尾振りを抑え、前半身を安定させました。
旋回は Godot の `shark_locomotion_modifier.gd` が進行方向に合わせて胴体と胸びれへ加えます。
参考映像、測定値、検証手順は `docs/shark_locomotion.md` に記録しています。
既存の GhostRendezvousIdle、GhostMountReceive、GhostDeparture と、鞍・搭乗位置を維持しています。

Godot の接触検証は `tests/shark_contact_bootstrap.gd` を `--script` で起動します。
`--fixed-fps 60 -- tag=check player=1` で右側落水、`player=2` で左側落水、
`case=close` で至近距離、`case=portal` でポータル復帰を検証できます。
`-- asset` は GLB の全クリップを描画・検査します。
記録は `artifacts/shark_rig_rebuild/` に保存します。
