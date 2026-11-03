#!/usr/bin/env bash
# サムネイル t8 に、ゴーストライダー（幽霊のサメに乗った P2）が P1 を襲う姿を足したイメージ案を Codex CLI の画像生成で作る（案ごとに並行）。
#   bash docs/pv/thumbnail/gen_v3/gen.sh a_chase b_dive ...
# 参照：Image 1 = いまの t8 の Blender 版（ロゴなし、ref_t8.png）、Image 2・3 = 実機のゴーストライダー（ref_ghost_rider.png・ref_ghost_attack.png）。
# プロンプトは prompts/_style.txt + prompts/<id>.txt
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CODEX="${CODEX:-$(command -v codex || echo "$LOCALAPPDATA/Programs/OpenAI/Codex/bin/codex.exe")}"
one() {
  local id="$1" stamp="$HERE/.stamp_$1"
  touch "$stamp"
  cat "$HERE/prompts/_style.txt" "$HERE/prompts/$id.txt" \
    | "$CODEX" exec -s workspace-write -C "$HERE" -i "$HERE/ref_t8.png" "$HERE/ref_ghost_rider.png" "$HERE/ref_ghost_attack.png" -- - > "$HERE/$id.log" 2>&1
  local status=$?
  # Codex がコピーに失敗したとき（ログに生成画像のパスだけ残る）は、そのパスから写す
  if [ ! "$HERE/$id.png" -nt "$stamp" ]; then
    local src
    src="$(grep -oE '[A-Za-z]:[^` ]*generated_images[^` ]*\.png' "$HERE/$id.log" | tail -1)"
    if [ -n "$src" ]; then cp "$src" "$HERE/$id.png"; fi
  fi
  rm -f "$stamp"
  echo "$id exit=$status $(ls "$HERE/$id.png" 2>/dev/null || echo MISSING)"
}
for id in "$@"; do one "$id" & done
wait
