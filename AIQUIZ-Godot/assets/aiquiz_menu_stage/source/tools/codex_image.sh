#!/usr/bin/env bash
# Codex CLI（ChatGPT のプラン、組み込みの image_gen）で画像を 1 枚作る。Git Bash 用。
#   bash codex_image.sh <出力.png> <プロンプト.txt> [参照画像 ...]
# 参照画像は添付の順に Image 1, Image 2 ... としてプロンプトから呼ぶ。
# Codex はリポジトリに触れない（一時フォルダで --ephemeral、生成物だけを出力へ写す）。
# このアセットの画像（../concepts）はすべてこの手順で作った（../PROMPTS.md、../generation_record.json）。
set -u
OUT="$1"; shift
PROMPT_FILE="$1"; shift
# 相対パスは呼び出した場所から（下で一時フォルダへ cd するので先に絶対パスにする）
case "$OUT" in /*|?:*) ;; *) OUT="$PWD/$OUT" ;; esac
case "$PROMPT_FILE" in /*|?:*) ;; *) PROMPT_FILE="$PWD/$PROMPT_FILE" ;; esac
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
# Codex デスクトップ同梱の CLI（PATH に無い）。更新でフォルダ名が変わるので毎回探す
CX="${CODEX_CLI:-$(ls -t "$LOCALAPPDATA"/OpenAI/Codex/bin/*/codex.exe 2>/dev/null | head -1)}"
if [ -z "$CX" ]; then echo "codex.exe が見つかりません（CODEX_CLI で指定）"; exit 2; fi
WORK=$(mktemp -d)
IMG_ARGS=()
for ref in "$@"; do case "$ref" in /*|?:*) ;; *) ref="$PWD/$ref" ;; esac; IMG_ARGS+=(-i "$ref"); done
BODY=$(cat "$PROMPT_FILE")
INSTR="You are producing concept art for a game asset pipeline. Use your built-in image generation tool (image_gen) exactly ONCE with the prompt below, passing it through verbatim (you may not shorten it). The attached images are REFERENCE images, numbered in attachment order (Image 1, Image 2, ...). Generate at the largest landscape size available and the highest quality. Do NOT run any shell command before generating, and never search the file system. After generation, copy the generated PNG (the file under the Codex generated_images folder that the tool reports) into the current working directory as result.png without modifying pixels, then reply only with the absolute path of result.png.

=== IMAGE PROMPT (verbatim) ===
${BODY}"
cd "$WORK"
# プロンプトは標準入力で渡す（-i は複数の値を取るので、位置引数のプロンプトを画像と取り違えないように）
printf '%s' "$INSTR" | "$CX" exec --skip-git-repo-check --ephemeral -s workspace-write \
  -c model_reasoning_effort='"low"' -o last.txt "${IMG_ARGS[@]}" > codex.log 2>&1
if [ ! -f result.png ]; then
  # Codex が保存先を返さないことがある：このセッションの generated_images/<session id>/ から取る
  SID=$(grep -m1 -o 'session id: [0-9a-f-]*' codex.log | awk '{print $3}')
  if [ -n "$SID" ] && [ -d "$CODEX_HOME_DIR/generated_images/$SID" ]; then
    NEWEST=$(ls -t "$CODEX_HOME_DIR/generated_images/$SID"/*.png 2>/dev/null | head -1)
    [ -n "$NEWEST" ] && cp "$NEWEST" result.png && echo "(session $SID: $NEWEST)" >> codex.log
  fi
fi
if [ -f result.png ]; then
  mkdir -p "$(dirname "$OUT")"
  cp result.png "$OUT"
  echo "OK $OUT"
else
  echo "FAIL (see $WORK/codex.log)"; tail -20 codex.log; exit 1
fi
