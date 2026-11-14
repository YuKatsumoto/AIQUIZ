extends Node

## アップデートの確認とパッチPCKのダウンロード（Windows の書き出し版だけ）。
##
## 流れ:
##   1. check()    … マニフェスト（JSON）を取りに行き、新しい版があれば「お知らせ」を返す。
##   2. download() … パッチを user://updates に落とし、大きさと SHA-256 を確かめてから state.json に書く。
##   3. restart()  … ゲームを立ち上げ直す。次の起動で PatchBoot（scripts/autoload/patch_boot.gd）がパッチを読む。
##
## マニフェストの場所は .env の UPDATE_MANIFEST_URL。空なら何もしない。
## マニフェストの形（tools/release/make_patch.py が書き出す）:
##   {
##     "version": "1.0.4",            いちばん新しい版
##     "base": "1.0.3",               このパッチが当たるフル版
##     "patch": {"url": "patch_1.0.4_windows.pck", "size": 1843200, "sha256": "…"},
##     "required": false,             true なら「あとで」を出さない
##     "notes": "…",                  画面に出す短い説明（省略できる）
##     "page_url": "https://…"        フル版の配布ページ（パッチで済まないときに案内する）
##   }
## patch.url はマニフェストからの相対パスでもよい。

signal progress(downloaded: int, total: int)

const MANIFEST_ENV := "UPDATE_MANIFEST_URL"
const CHECK_TIMEOUT_SECONDS := 6.0
## ダウンロードが 1 バイトも進まないままこの秒数たったら、あきらめる。
const STALL_TIMEOUT_SECONDS := 20.0

const KIND_PATCH := "patch"
## パッチでは届けられない版（フル版の入れ直しが必要）。
const KIND_FULL := "full"


## PatchBoot.is_supported() と同じ条件。パッチを読めない環境では、確認もしない。
static func is_supported() -> bool:
	return OS.has_feature("windows") and not OS.has_feature("editor")


## PatchBoot は名前で探す。autoload の名前を直接書くと、autoload の無い実行（-s のテスト）で読み込めない。
func _patch_boot() -> Node:
	return get_node_or_null("/root/PatchBoot")


static func manifest_url() -> String:
	return OS.get_environment(MANIFEST_ENV).strip_edges()


## 新しい版があれば「お知らせ」を返す。無い・確かめられないときは {}。
## お知らせ: {kind, version, required, notes, page_url} と、kind が patch のとき {url, size, sha256}。
func check() -> Dictionary:
	var url := manifest_url()
	var boot := _patch_boot()
	if url.is_empty() or boot == null or not is_supported():
		return {}
	var http := HTTPRequest.new()
	http.timeout = CHECK_TIMEOUT_SECONDS
	add_child(http)
	if http.request(url, PackedStringArray(["Cache-Control: no-cache"])) != OK:
		http.queue_free()
		return {}
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		push_warning("[GameUpdater] manifest unavailable (result %d, http %d)" % [response[0], response[1]])
		return {}
	var body: PackedByteArray = response[3]
	var manifest: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not manifest is Dictionary:
		push_warning("[GameUpdater] manifest is not a JSON object")
		return {}
	var offer := offer_from_manifest(manifest, url, str(boot.get("version")), str(boot.get("base_version")),
		boot.call("rejected_hashes"))
	if not offer.is_empty():
		print("[GameUpdater] update available: %s (%s) for %s" % [offer["version"], offer["kind"], boot.get("version")])
	return offer


## マニフェストから「お知らせ」を作る。通信をしないので、そのままテストできる。
static func offer_from_manifest(manifest: Dictionary, manifest_location: String, current_version: String,
		base_version: String, rejected: Array) -> Dictionary:
	var latest := str(manifest.get("version", ""))
	if latest.is_empty() or compare_versions(latest, current_version) <= 0:
		return {}
	var offer := {
		"kind": KIND_FULL,
		"version": latest,
		"required": bool(manifest.get("required", false)),
		"notes": str(manifest.get("notes", "")),
		"page_url": str(manifest.get("page_url", "")),
	}
	var patch: Variant = manifest.get("patch")
	if str(manifest.get("base", "")) != base_version or not patch is Dictionary:
		return offer
	var sha := str(patch.get("sha256", "")).to_lower()
	var size := int(patch.get("size", 0))
	var patch_url := resolve_url(manifest_location, str(patch.get("url", "")))
	if patch_url.is_empty() or size <= 0 or not is_sha256(sha):
		push_warning("[GameUpdater] manifest patch entry is incomplete")
		return {}
	# このPCで起動に失敗して捨てたパッチは、もう勧めない（直した版は sha256 が変わるので出る）。
	if rejected.has(sha):
		return {}
	offer["kind"] = KIND_PATCH
	offer["url"] = patch_url
	offer["size"] = size
	offer["sha256"] = sha
	return offer


## "1.0.10" と "1.0.9" を数字として比べる。a が新しければ 1、同じなら 0、古ければ -1。
static func compare_versions(a: String, b: String) -> int:
	var left := a.split(".")
	var right := b.split(".")
	for index: int in range(maxi(left.size(), right.size())):
		var l := int(left[index]) if index < left.size() else 0
		var r := int(right[index]) if index < right.size() else 0
		if l != r:
			return 1 if l > r else -1
	return 0


static func is_sha256(text: String) -> bool:
	return text.length() == 64 and text.is_valid_hex_number()


## マニフェストからの相対パスを、絶対の URL にする。
static func resolve_url(manifest_location: String, target: String) -> String:
	if target.is_empty() or target.begins_with("http://") or target.begins_with("https://"):
		return target
	var base := manifest_location.get_slice("?", 0)
	return base.substr(0, base.rfind("/") + 1) + target


static func format_size(bytes: int) -> String:
	if bytes < 1024 * 1024:
		return "%d KB" % maxi(1, ceili(bytes / 1024.0))
	return "%.1f MB" % (bytes / 1048576.0)


## パッチを落として確かめ、次の起動で読まれるようにする。うまくいけば ""、だめなら画面に出す文。
func download(offer: Dictionary) -> String:
	if str(offer.get("kind", "")) != KIND_PATCH:
		return "このアップデートはダウンロードできません"
	var size := int(offer.get("size", 0))
	var sha := str(offer.get("sha256", ""))
	var version := str(offer.get("version", ""))
	var boot := _patch_boot()
	if boot == null:
		return "このアップデートはダウンロードできません"
	var updates_dir := str(boot.get("DIR"))
	if DirAccess.make_dir_recursive_absolute(updates_dir) != OK:
		return "保存先のフォルダを作れませんでした"
	# 名前に sha256 の頭を入れる。いま読み込み中のパッチと同じ名前にならない。
	var file_name := "patch_%s_%s.pck" % [version.validate_filename(), sha.left(8)]
	var final_path := updates_dir.path_join(file_name)
	var part_path := final_path + ".part"

	var http := HTTPRequest.new()
	http.timeout = 0.0  # 大きなファイルは全体の制限時間を付けない。止まったかどうかは下で見る。
	# 圧縮なしで受け取る。進みぐあい（受け取ったバイト数）がファイルの大きさとそのまま合う。
	http.accept_gzip = false
	http.download_file = part_path
	http.use_threads = true
	add_child(http)
	var finished: Array = []
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		finished.append([result, code]))
	if http.request(str(offer.get("url", ""))) != OK:
		http.queue_free()
		return "ダウンロードを始められませんでした"
	var last_bytes := -1
	var last_change_msec := Time.get_ticks_msec()
	while finished.is_empty():
		var downloaded := http.get_downloaded_bytes()
		if downloaded != last_bytes:
			last_bytes = downloaded
			last_change_msec = Time.get_ticks_msec()
			progress.emit(downloaded, size)
		elif Time.get_ticks_msec() - last_change_msec > STALL_TIMEOUT_SECONDS * 1000.0:
			http.cancel_request()
			break
		await get_tree().process_frame
	http.queue_free()
	if finished.is_empty():
		DirAccess.remove_absolute(part_path)
		return "通信が止まりました。接続を確かめて、もう一度お試しください"
	var result: Array = finished[0]
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		DirAccess.remove_absolute(part_path)
		push_warning("[GameUpdater] download failed (result %d, http %d)" % [result[0], result[1]])
		return "ダウンロードできませんでした。接続を確かめて、もう一度お試しください"
	progress.emit(size, size)
	await get_tree().process_frame

	var file := FileAccess.open(part_path, FileAccess.READ)
	var actual_size := file.get_length() if file != null else -1
	file = null
	if actual_size != size or FileAccess.get_sha256(part_path) != sha:
		DirAccess.remove_absolute(part_path)
		push_warning("[GameUpdater] downloaded patch does not match the manifest")
		return "ダウンロードしたファイルが正しくありませんでした。もう一度お試しください"
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	if DirAccess.rename_absolute(part_path, final_path) != OK:
		DirAccess.remove_absolute(part_path)
		return "アップデートを保存できませんでした"
	var state: Dictionary = boot.get("state")
	state["patch"] = {
		"version": version,
		"base": str(boot.get("base_version")),
		"file": file_name,
		"size": size,
		"sha256": sha,
		"failed_boots": 0,
	}
	if not boot.call("write_state"):
		return "アップデートを保存できませんでした"
	return ""


func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()
