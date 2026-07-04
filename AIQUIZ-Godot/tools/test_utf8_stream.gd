extends SceneTree

## UTF-8ストリーミングデコード回帰テスト（文字化け防止）
## マルチバイト文字がチャンク境界で分割されても � にならないことを検証する
func _initialize() -> void:
	await process_frame
	var failures := 0

	# 「1.2よりちいさくて、1より大きい数はどれですか。」を UTF-8 バイト列にする
	var full_text := "1.2よりちいさくて、1より大きい数はどれですか。"
	var full_bytes := full_text.to_utf8_buffer()

	# ── ケース1: 全バイトを1バイトずつ流し込む（最悪の分割） ──
	var client = load("res://scripts/core/gemini_stream_client.gd").new()
	get_root().add_child(client)
	client._byte_buffer = PackedByteArray()
	var out1 := ""
	for i in range(full_bytes.size()):
		var one := PackedByteArray([full_bytes[i]])
		out1 += client._decode_utf8_streaming(one)
	# 末尾フラッシュ
	if client._byte_buffer.size() > 0:
		out1 += client._byte_buffer.get_string_from_utf8()
		client._byte_buffer = PackedByteArray()
	failures += _assert_eq(out1, full_text, "1バイトずつ分割しても完全復元")
	failures += _assert_false(out1.contains("�"), "1バイト分割: 置換文字を含まない")

	# ── ケース2: 「で」(E3 81 A7) の途中で分割 ──
	# "どれで" までのバイトを、"で" の1バイト目直後で切る
	client._byte_buffer = PackedByteArray()
	var prefix := "1.2よりちいさくて、1より大きい数はどれ".to_utf8_buffer()
	var de := "で".to_utf8_buffer()  # 3バイト
	var rest := "すか。".to_utf8_buffer()
	# チャンクA: prefix + "で"の最初の1バイト
	var chunk_a := PackedByteArray(prefix)
	chunk_a.append(de[0])
	# チャンクB: "で"の残り2バイト + rest
	var chunk_b := PackedByteArray([de[1], de[2]])
	chunk_b.append_array(rest)
	var out2: String = client._decode_utf8_streaming(chunk_a)
	failures += _assert_false(out2.contains("�"), "境界分割チャンクA: 置換文字を含まない")
	out2 += client._decode_utf8_streaming(chunk_b)
	if client._byte_buffer.size() > 0:
		out2 += client._byte_buffer.get_string_from_utf8()
	failures += _assert_eq(out2, full_text, "「で」境界分割でも完全復元")

	# ── ケース3: 4バイト絵文字が分割されても復元 ──
	client._byte_buffer = PackedByteArray()
	var emoji_text := "答えは😀です"
	var eb := emoji_text.to_utf8_buffer()
	var out3 := ""
	# 3バイトずつ分割
	var idx := 0
	while idx < eb.size():
		var seg := eb.slice(idx, mini(idx + 3, eb.size()))
		out3 += client._decode_utf8_streaming(seg)
		idx += 3
	if client._byte_buffer.size() > 0:
		out3 += client._byte_buffer.get_string_from_utf8()
	failures += _assert_eq(out3, emoji_text, "4バイト絵文字の分割復元")

	if failures == 0:
		print("[Utf8StreamTest] ALL PASSED")
		quit(0)
	else:
		print("[Utf8StreamTest] FAILED: %d assertion(s)" % failures)
		quit(1)


func _assert_eq(actual: String, expected: String, label: String) -> int:
	if actual != expected:
		push_error("FAIL: %s\n  expected: %s\n  actual:   %s" % [label, expected, actual])
		return 1
	print("OK: %s" % label)
	return 0


func _assert_false(cond: bool, label: String) -> int:
	if cond:
		push_error("FAIL (expected false): %s" % label)
		return 1
	print("OK: %s" % label)
	return 0
