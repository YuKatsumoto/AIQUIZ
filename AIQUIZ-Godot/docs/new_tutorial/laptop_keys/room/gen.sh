#!/usr/bin/env bash
# 部屋版の絵コンテのコマを Codex CLI の画像生成で作る（1 コマずつ順番に）。
#   bash docs/new_tutorial/laptop_keys/room/gen.sh r2 r3 ...
# 参照：Image 1 = コース③の実機の画面、Image 2 = ハテナ、Image 3 = 部屋の基準コマ r1（r1・r8・y2 は付けない）
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
for id in "$@"; do
  refs=(-i "$ROOT/artifacts/practice_course3/02_keys_sign.png" -i "$ROOT/artifacts/practice_mascot/Practice_Cross_0_front.png")
  case "$id" in r1|r8|y2) ;; *) refs+=(-i "$HERE/panels/panel_r1.png") ;; esac
  stamp="$HERE/panels/.stamp_$id"
  touch "$stamp"
  (cd "$HERE/panels" && cat "$HERE/prompts/_style.txt" "$HERE/prompts/panel_$id.txt" \
    | codex exec - -s workspace-write -C "$HERE/panels" "${refs[@]}" > "$HERE/panels/panel_$id.log" 2>&1)
  status=$?
  # Codex がコピーに失敗したとき（ログに生成画像のパスだけ残る）は、そのパスから写す
  if [ ! "$HERE/panels/panel_$id.png" -nt "$stamp" ]; then
    src="$(grep -oE '[A-Za-z]:[^` ]*generated_images[^` ]*\.png' "$HERE/panels/panel_$id.log" | tail -1)"
    if [ -n "$src" ]; then cp "$src" "$HERE/panels/panel_$id.png"; fi
  fi
  rm -f "$stamp"
  echo "$id exit=$status $(ls "$HERE/panels/panel_$id.png" 2>/dev/null || echo MISSING)"
done
