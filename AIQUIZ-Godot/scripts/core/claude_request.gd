class_name ClaudeRequest
extends RefCounted

## プロキシの /claude・/claude-stream に送る本文と、返事の読み取り。
##
## ゲームはモデルを指定せず、用途（task）とプロンプトだけを送る。モデル・考える深さ・出力の上限・
## 子ども向けの安全指示はプロキシ（aiquiz-proxy/claude-live.js）が決める。
## /claude の返事は {"text": "...", "stop_reason": "...", "model": "..."}。
## validate・explain・evaluate の text は、プロキシが JSON 配列にそろえて返す。

const TASK_GENERATE: String = "generate"
const TASK_EXPLAIN: String = "explain"
const TASK_VALIDATE: String = "validate"
const TASK_EVALUATE: String = "evaluate"

## 設定の画面などに出す、問題をつくる AI の名前（Anthropic の利用条件で、AI であることを示す）
const PROVIDER_LABEL: String = "Claude（Anthropic）"

## 試合中に AI がつくった問題の出どころ。共有バンクへ候補として送り、評価の対象にする。
## GEMINI* と OPENAI は、Claude に切り替える前に端末へ保存された問題のために残す。
const ONLINE_SOURCES: Array[String] = [
	"CLAUDE", "CLAUDE_STREAM", "CLAUDE_POOL", "CLAUDE_HAIKU",
	"GEMINI", "GEMINI_STREAM", "GEMINI_POOL", "OPENAI",
]


static func body(task: String, prompt: String, system: String = "") -> String:
	var payload := {"task": task, "prompt": prompt}
	if not system.is_empty():
		payload["system"] = system
	return JSON.stringify(payload)


## /claude の返事（パース済み）から text を取り出す。形が違えば空文字。
static func response_text(response: Variant) -> String:
	if not response is Dictionary:
		return ""
	var text: Variant = response.get("text", "")
	if not text is String:
		return ""
	return (text as String).strip_edges()


static func is_online_source(src: String) -> bool:
	return src.strip_edges().to_upper() in ONLINE_SOURCES
