#!/usr/bin/env bash
# サムネイル t5 の「突き破り」イメージ案を Codex CLI の画像生成で作る（案ごとに並行）。
#   bash docs/pv/thumbnail/gen_v2/gen.sh a_shoulder b_superman ...
# 参照：Image 1 = ユーザーが選んだ実機の画角（ref_chosen.png）。プロンプトは prompts/_style.txt + prompts/<id>.txt
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CODEX="${CODEX:-/c/Program Files/WindowsApps/OpenAI.Codex_26.1027.3384.0_x64__2p2nqsd0c76g0/app/resources/codex.exe}"
one() {
  local id="$1" stamp="$HERE/.stamp_$1"
  touch "$stamp"
  cat "$HERE/prompts/_style.txt" "$HERE/prompts/$id.txt" \
    | "$CODEX" exec - -s workspace-write -C "$HERE" -i "$HERE/ref_chosen.png" > "$HERE/$id.log" 2>&1
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
