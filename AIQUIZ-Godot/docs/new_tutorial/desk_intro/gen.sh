#!/usr/bin/env bash
# ローカル2Pの説明画面の始め（2人が座る → 手を添える → 準備完了 → モニターの中へ）の、実写の絵コンテのコマを
# Codex CLI の画像生成で作る（1 コマずつ順番に）。
#   bash docs/new_tutorial/desk_intro/gen.sh d2 d3 ...
# 参照：Image 1 = メニューの背景（モニターに映すゲームの画面）、Image 2 = ハテナ（机の上のフィギュアにする）、
#       Image 3 = 部屋の基準コマ d1（d1・d8 には付けない）
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/panels"
for id in "$@"; do
  refs=(-i "$HERE/refs/game_screen.jpg" -i "$HERE/refs/hatena.png")
  case "$id" in d1|d8) ;; *) refs+=(-i "$HERE/panels/panel_d1.png") ;; esac
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
