class_name MenuLedProgram
extends Node

## "AIQUIZ VISION": the programme on the goal stand scoreboard (GoalStandScoreboard
## plays it after the winner's cut-in). It used to run on the main menu stage LED
## (AMS_LedScreen of the launch deck, see AiquizMenuStage.BUILD_LAUNCH_DECK).
##
## Plays the After Effects segments of led_motion.json (source/ae/build_led.jsx) into
## a SubViewport that an LED shader samples. The viewport can carry its own GPU mip
## chain (the menu LED shader used it); the goal stand scoreboard builds its own and
## takes none here. A round is:
##   HIGHLIGHTS title, the replay of one match (every moment HighlightStore kept, in
##   match order: fast-forward between moments, real speed around them, slow motion at
##   the moment itself, its name swept in bottom-left), RECORDS title, the last match
##   (2P panels or the 1P score card), the match history (four per page, two pages at
##   most), the all-time tiles, then the logo, which stays up for LOGO_HOLD_SECONDS
##   before the next round (the next round replays the next older match).
## Before anything was played it shows an invitation to play and the logo.
## Timing, layout and colours are After Effects'; words, numbers and clip frames are
## filled in here. Segments carry no transition of their own: WIPE_Strokes plays over
## every seam (its strokes cover the whole screen at WIPE_SEAM), so any order joins.

const MOTION_PATH := "res://assets/aiquiz_menu_stage/led/led_motion.json"
const LOGO_TEXTURE: Texture2D = preload("res://assets/aiquiz_menu_stage/led/led_logo.png")
const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const CANVAS := Vector2i(1296, 588)
const MIP_LEVELS := 4
## WIPE_Strokes covers the whole screen at this second (build_led.jsx SEAM).
const WIPE_SEAM := 0.45
## CUT_Strokes hides the cut between two replay moments at this second.
const CUT_SWAP := 0.24
## After a round the logo stays up this long.
const LOGO_HOLD_SECONDS := 180.0
const HISTORY_ROWS := 4
const HISTORY_PAGES := 2
## Replay pacing (seconds of the clip around each moment, playback rates).
const FAST_RATE := 2.0
const FASTER_RATE := 3.0
## A replay longer than this at FAST_RATE plays its gaps at FASTER_RATE.
const REPLAY_LONG := 70.0
const FOCUS_BEFORE := 1.2
const FOCUS_AFTER := 1.0
const SLOW_BEFORE := 0.12
const SLOW_AFTER := 0.5
const SLOW_RATE := 0.5
## The last frame of a moment holds this long before the cut.
const MOMENT_HOLD := 0.35
## The moment's name appears this much before the moment itself.
const CAPTION_LEAD := 0.35
## The replay holds its last frame under the closing wipe.
const REPLAY_OUTRO := 0.5
## Clip frames are decoded to this size (the LED shows 216 x 98 dots).
const FRAME_SIZE := Vector2i(320, 180)
## Vertical centre of the cover crop in a 16:9 clip frame: the runners are low in
## the gameplay camera, the finale looks up at the winner's tower and crown.
const CLIP_FOCUS_Y := 0.6
const CLIP_FOCUS_Y_BY_KIND := {"win": 0.4, "draw": 0.4}
## Slow push-in over each moment.
const CLIP_ZOOM := 0.05
const P_COLORS: Array[Color] = [Color(0.949, 0.549, 0.2), Color(0.2, 0.651, 0.902)]
const GOLD := Color(1.0, 0.824, 0.29)
const TRACK := Color(0.141, 0.2, 0.333)
const PALE := Color(0.961, 0.969, 1.0)
const INK := Color(0.043, 0.071, 0.125)
const DIM := 0.6
## Pills of a match settled by the sudden death (the hazard red of its cut-in).
const SUDDEN_DEATH_RED := Color(0.835, 0.153, 0.133)
## Widest percentage that fits inside the accuracy ring (its opening is 172 px).
const RING_TEXT_WIDTH := 140.0

const TEXT := {
	"ja": {
		"highlights": "HIGHLIGHTS", "highlights_sub": "ハイライト",
		"records": "RECORDS", "records_sub": "きろく",
		"last_versus": "前回の対戦", "last_solo": "前回のプレイ", "all_time": "これまでの記録", "history": "勝負の記録",
		"correct": "正解", "correct_n": "正解 %d", "out_short": "脱落", "win": "WIN!", "draw": "DRAW",
		"streak_best": "最大連続", "play_time": "プレイ時間", "seconds": "%d秒",
		"matches": "あそんだ回数", "matches_unit": "回", "best": "最多正解", "best_unit": "問",
		"accuracy": "正答率",
		"empty": "まだ記録がないよ", "empty_sub": "あそぶと ここに記録がでるよ！",
		"mode_ten_2p": "10問バトル", "mode_ten_1p": "10問チャレンジ", "mode_endless": "エンドレス",
		"mode_online": "オンライン対戦",
		"replay": "REPLAY  %d/%d", "fast": "▶▶ %dx",
		"row_win": "P%d WIN", "row_draw": "DRAW", "row_clear": "CLEAR", "row_perfect": "PERFECT", "row_over": "GAME OVER",
		"streak": "%d連続正解！", "win_p": "P%dの勝ち！", "draw_event": "引き分け！", "perfect": "パーフェクト！",
		"clear": "10問クリア！", "goal": "P%dがゴール！", "near_miss": "間一髪！", "ocean": "海にドボン！",
		"shark": "サメにガブッ！", "ghost_hit": "サメで体当たり！", "saw": "つかまった！", "push": "体当たり！",
		"out": "脱落…", "sudden_death": "サドンデス決着！",
		"last_versus_sd": "前回の対戦・SUDDEN DEATH", "mode_sudden_death": "SUDDEN DEATH",
	},
	"en": {
		"highlights": "HIGHLIGHTS", "highlights_sub": "BEST MOMENTS",
		"records": "RECORDS", "records_sub": "YOUR STATS",
		"last_versus": "LAST MATCH", "last_solo": "LAST PLAY", "all_time": "ALL-TIME", "history": "MATCH HISTORY",
		"correct": "CORRECT", "correct_n": "%d correct", "out_short": "OUT", "win": "WIN!", "draw": "DRAW",
		"streak_best": "Best streak", "play_time": "Time", "seconds": "%ds",
		"matches": "MATCHES", "matches_unit": "played", "best": "MOST CORRECT", "best_unit": "in a match",
		"accuracy": "ACCURACY",
		"empty": "NO RECORDS YET", "empty_sub": "Play a match and your records show up here!",
		"mode_ten_2p": "10-Q BATTLE", "mode_ten_1p": "10-Q CHALLENGE", "mode_endless": "ENDLESS",
		"mode_online": "ONLINE",
		"replay": "REPLAY  %d/%d", "fast": "▶▶ %dx",
		"row_win": "P%d WIN", "row_draw": "DRAW", "row_clear": "CLEAR", "row_perfect": "PERFECT", "row_over": "GAME OVER",
		"streak": "%d IN A ROW!", "win_p": "P%d WINS!", "draw_event": "DRAW!", "perfect": "PERFECT!",
		"clear": "CLEARED!", "goal": "P%d FINISHED FIRST!", "near_miss": "CLOSE CALL!", "ocean": "SPLASH!",
		"shark": "SHARK BITE!", "ghost_hit": "SHARK ATTACK!", "saw": "CAUGHT!", "push": "BODY SLAM!",
		"out": "OUT!", "sudden_death": "SUDDEN DEATH!",
		"last_versus_sd": "LAST MATCH · SUDDEN DEATH", "mode_sudden_death": "SUDDEN DEATH",
	},
}

var viewport: SubViewport
var mips: Array[SubViewport] = []
var english := false
## Seconds the programme has been playing (tests read it).
var clock := 0.0

## Seconds into the lead-in: the cover half of WIPE_Strokes alone on a transparent
## viewport, so whatever is drawn under the programme is covered by the strokes before
## the first segment's own reveal half starts. -1 when there is no lead-in.
var _lead_in := -1.0
var _active := true

var _motion: AeMotion
var _screen: Control
var _ambient: AeMotion.Comp
var _wipe: AeMotion.Comp
## The playing segment: an AeMotion.Comp, or the replay's root Control.
var _segment: Control
var _segment_info: Dictionary = {}
var _segment_time := 0.0
var _segment_duration := 0.0
var _round: Array[Dictionary] = []
var _round_index := 0
var _records: Array[Dictionary] = []
var _summary: Dictionary = {}
var _clips: Array[Dictionary] = []
var _matches_with_clips: Array[Array] = []
var _replay_cursor := 0
## Loaded clip frames by clip id: {textures: Array[ImageTexture], clip}.
var _frames: Dictionary = {}
var _loading: Dictionary = {}
# The replay being played.
var _replay: Dictionary = {}
var _replay_media: Control
var _replay_frame: AeMotion.Comp
var _replay_caption: AeMotion.Comp
var _replay_cut: AeMotion.Comp
var _replay_now: Dictionary = {}


## Plays the saved history, or the given records / clips (tests and previews).
## `mip_levels` half-size copies of the programme are kept up to date for a shader that
## filters it itself (0 when the user of get_texture() builds its own mip chain).
func setup(records: Variant = null, clips: Variant = null, mip_levels: int = MIP_LEVELS) -> bool:
	name = "MenuLedProgram"
	_motion = AeMotion.load_file(MOTION_PATH)
	if not _motion.is_loaded():
		push_warning("MenuLedProgram: %s is missing" % MOTION_PATH)
		return false
	var state: QuizGameState = QuizManager.game_state
	english = state != null and state.use_english_ui
	if records == null:
		MatchReel.wait_for_write() # A match that just ended may still be writing.
	_records = MatchHistory.load_records() if records == null else Array(records, TYPE_DICTIONARY, "", null)
	_summary = MatchHistory.summary(_records)
	_clips = HighlightStore.list() if clips == null else Array(clips, TYPE_DICTIONARY, "", null)
	_matches_with_clips = HighlightStore.by_match(_clips)
	_build_viewports(mip_levels)
	_ambient = _motion.instance("BG_Ambient", FONT)
	_screen.add_child(_ambient)
	_wipe = _motion.instance("WIPE_Strokes", FONT)
	_wipe.z_index = 10
	_screen.add_child(_wipe)
	_next_round()
	_start_segment()
	return true


func get_texture() -> Texture2D:
	return viewport.get_texture()


## Half-size copies of the programme, level 1 (648 x 294) down to MIP_LEVELS.
func get_mip_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for mip: SubViewport in mips:
		textures.append(mip.get_texture())
	return textures


func current_segment() -> Dictionary:
	return _segment_info


func segment_duration() -> float:
	return _segment_duration


func round_plan() -> Array[Dictionary]:
	return _round


## The replay being played: {moments, duration} (tests).
func replay_plan() -> Dictionary:
	return _replay


## Jumps to a segment of the current round at a second (tests and previews).
func show_segment(index: int, time: float) -> void:
	_round_index = clampi(index, 0, _round.size() - 1)
	_start_segment()
	_segment_time = time
	_apply(0.0)


func is_clip_loaded(clip: Dictionary) -> bool:
	return _frames.has(str(clip.get("id", "")))


## Pauses the programme and its viewports (nobody can see it) or resumes it.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	set_process(on)
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	viewport.render_target_update_mode = mode
	for mip: SubViewport in mips:
		mip.render_target_update_mode = mode


## The programme's first frames are the cover half of the wipe on a transparent
## background (a user draws its own picture first and this texture over it); the first
## segment then reveals from the strokes. Call before the programme is first processed.
func begin_lead_in() -> void:
	viewport.transparent_bg = true
	_lead_in = 0.0
	_apply_lead_in()


func is_lead_in() -> bool:
	return _lead_in >= 0.0


func _apply_lead_in() -> void:
	_ambient.visible = false
	_segment.visible = false
	_wipe.visible = true
	_wipe.apply(minf(_lead_in, WIPE_SEAM))


func _end_lead_in() -> void:
	_lead_in = -1.0
	_ambient.visible = true
	_segment.visible = true


func _build_viewports(mip_levels: int) -> void:
	viewport = SubViewport.new()
	viewport.name = "LedProgramViewport"
	viewport.size = CANVAS
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.size = Vector2(CANVAS)
	_screen.clip_contents = true
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_screen)
	var source: Texture2D = viewport.get_texture()
	var size := CANVAS
	for level in range(mip_levels):
		size = Vector2i(maxi(1, (size.x + 1) / 2), maxi(1, (size.y + 1) / 2))
		var mip := SubViewport.new()
		mip.name = "LedMip%d" % (level + 1)
		mip.size = size
		mip.disable_3d = true
		mip.transparent_bg = false
		mip.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(mip)
		var rect := TextureRect.new()
		rect.texture = source
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		rect.size = Vector2(size)
		mip.add_child(rect)
		mips.append(mip)
		source = mip.get_texture()


func _process(delta: float) -> void:
	if _segment == null:
		return
	clock += delta
	if _lead_in >= 0.0:
		_lead_in += delta
		if _lead_in < WIPE_SEAM:
			_apply_lead_in()
			return
		_end_lead_in()
	_segment_time += delta
	_poll_loading()
	if _segment_time >= _segment_duration:
		_segment_time -= _segment_duration
		_round_index += 1
		if _round_index >= _round.size():
			_next_round()
		_start_segment()
	_apply(delta)


func _apply(_delta: float) -> void:
	_ambient.apply(fmod(clock, _ambient.duration))
	if _segment is AeMotion.Comp:
		(_segment as AeMotion.Comp).apply(_segment_time)
		_update_segment()
	else:
		_apply_replay(_segment_time)
	# The transition over the seams: the reveal half at the start, the cover half at the end.
	var reveal := bool(_segment_info.get("wipe_in", true)) and _segment_time < _wipe.duration - WIPE_SEAM
	var cover := bool(_segment_info.get("wipe_out", true)) and _segment_time >= _segment_duration - WIPE_SEAM
	_wipe.visible = reveal or cover
	if reveal:
		_wipe.apply(WIPE_SEAM + _segment_time)
	elif cover:
		_wipe.apply(_segment_time - (_segment_duration - WIPE_SEAM))


# ---------------------------------------------------------------- playlist

func _next_round() -> void:
	_round.clear()
	_round_index = 0
	if _records.is_empty() and _clips.is_empty():
		_round.append({"comp": "LED_Empty"})
	else:
		if not _matches_with_clips.is_empty():
			var clips: Array = _matches_with_clips[_replay_cursor % _matches_with_clips.size()]
			_replay_cursor += 1
			if not (plan_replay(clips).moments as Array).is_empty():
				_round.append({"comp": "LED_Sting", "title": _t("highlights"), "sub": _t("highlights_sub")})
				_round.append({"comp": "REPLAY", "clips": clips})
		if not _records.is_empty():
			_round.append({"comp": "LED_Sting", "title": _t("records"), "sub": _t("records_sub")})
			var last := MatchHistory.latest(_records)
			_round.append({"comp": "LED_Versus" if int(last.get("players", 1)) >= 2 else "LED_Solo", "record": last})
			var newest := _records.duplicate()
			newest.reverse()
			for page in range(mini(HISTORY_PAGES, ceili(float(newest.size()) / HISTORY_ROWS))):
				_round.append({"comp": "LED_History", "rows": newest.slice(page * HISTORY_ROWS, (page + 1) * HISTORY_ROWS)})
			_round.append({"comp": "LED_Stats"})
	# The logo, then its loop for the hold; no transition between them.
	_round.append({"comp": "LED_Logo", "wipe_out": false})
	var loops := maxi(1, ceili(LOGO_HOLD_SECONDS / maxf(1.0, _motion.duration("LED_LogoLoop"))))
	for index in range(loops):
		_round.append({"comp": "LED_LogoLoop", "wipe_in": false, "wipe_out": index == loops - 1})
	for item: Dictionary in _round:
		if item.comp == "REPLAY":
			for clip: Dictionary in (item.clips as Array).slice(0, 2):
				_load_clip(clip)


func _start_segment() -> void:
	if _round_index >= _round.size():
		_next_round()
	_segment_info = _round[_round_index]
	if is_instance_valid(_segment):
		_segment.queue_free()
	_replay = {}
	if _segment_info.comp == "REPLAY":
		_segment = _build_replay(_segment_info.clips)
		_segment_duration = float(_replay.duration)
	else:
		var comp := _motion.instance(str(_segment_info.comp), FONT, {"led_logo.png": LOGO_TEXTURE}, ["BG_Ambient"])
		_segment = comp
		_segment_duration = comp.duration
	_screen.add_child(_segment)
	_screen.move_child(_segment, _ambient.get_index() + 1)
	if _segment is AeMotion.Comp:
		_fill_segment()


func _t(key: String) -> String:
	return str((TEXT["en" if english else "ja"] as Dictionary).get(key, key))


func _layer(layer_name: String) -> AeMotion.Layer:
	return (_segment as AeMotion.Comp).layer(layer_name) if _segment is AeMotion.Comp else null


func _set_text(layer_name: String, value: String) -> void:
	var layer := _layer(layer_name)
	if layer != null:
		layer.text = value


## A pill fitted to its words. side: where the pill's anchor holds it ("left" end,
## "right" end or "center"); a centred label on a right-anchored pill follows its centre.
static func fit_pill(pill: AeMotion.Layer, label: AeMotion.Layer, padding: float, side: String, minimum: float = 0.0) -> void:
	if pill == null or label == null:
		return
	var width := maxf(minimum, label.text_width() + padding)
	pill.width_override = width
	if side == "left":
		pill.override_base("anchor", [-width * 0.5, 0.0])
	elif side == "right":
		pill.override_base("anchor", [width * 0.5, 0.0])
		if label.text_spec.justification == "center":
			var pos: Array = (pill.record.base as Dictionary).position
			label.override_base("position", [float(pos[0]) - width * 0.5, float(pos[1])])


# ---------------------------------------------------------------- content

func _fill_segment() -> void:
	match str(_segment_info.comp):
		"LED_Sting":
			_set_text("TitleText", str(_segment_info.title))
			_set_text("SubText", str(_segment_info.sub))
			fit_pill(_layer("SubPill"), _layer("SubText"), 72.0, "center", 220.0)
		"LED_Versus":
			_fill_versus(_segment_info.record)
		"LED_Solo":
			_fill_solo(_segment_info.record)
		"LED_History":
			_fill_history(_segment_info.rows)
		"LED_Stats":
			_fill_stats()
		"LED_Empty":
			_set_text("EmptyTitle", _t("empty"))
			_set_text("EmptySub", _t("empty_sub"))


func _mode_label(entry: Dictionary) -> String:
	if bool(entry.get("online", false)):
		return _t("mode_online")
	if str(entry.get("mode", "")) == Constants.MODE_ENDLESS:
		return _t("mode_endless")
	return _t("mode_ten_2p") if int(entry.get("players", 1)) >= 2 else _t("mode_ten_1p")


func _date_label(unix: int) -> String:
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var date := Time.get_date_dict_from_unix_time(unix + bias_minutes * 60)
	return "%d/%d" % [int(date.month), int(date.day)]


## The name of one moment, e.g. "P1 3連続正解！" (the player only in 2P matches).
func event_label(event: Dictionary, players: int = 1) -> String:
	var player := int(event.get("player", 0))
	var label := ""
	match str(event.get("kind", "")):
		"streak":
			label = _t("streak") % int(event.get("streak", 3))
		"win":
			return _t("win_p") % player
		"draw":
			return _t("draw_event")
		"perfect":
			return _t("perfect")
		"clear":
			return _t("clear")
		"goal":
			return _t("goal") % player
		_:
			label = _t(str(event.get("kind", "")))
	if players >= 2 and player > 0:
		label = "P%d %s" % [player, label]
	return label


static func player_colour(player: int) -> Color:
	return P_COLORS[player - 1] if player == 1 or player == 2 else GOLD


## Shown number of a half-point total ("12.5") or plain count.
static func format_points(half_points: int, decimal: bool) -> String:
	if decimal:
		return "%d.%d" % [half_points >> 1, 5 if half_points & 1 else 0]
	return str(half_points >> 1)


## The record's sudden death {questions, by, winner} ({rows, by, winner} in records from the gate run),
## {} when the match had none (older records included).
static func sudden_death_of(record: Dictionary) -> Dictionary:
	var value: Variant = record.get("sudden_death")
	if value is Dictionary and int((value as Dictionary).get("winner", 0)) > 0:
		return value
	return {}


func _fill_versus(record: Dictionary) -> void:
	_set_text("HeaderText", _t("last_versus"))
	if not sudden_death_of(record).is_empty():
		# Level points with a winner: the header says how it was settled.
		_set_text("HeaderText", _t("last_versus_sd"))
		var header := _layer("HeaderPill")
		if header != null:
			fit_pill(header, _layer("HeaderText"), 96.0, "center", float((header.shape.size as Array)[0]))
			header.fill_color = SUDDEN_DEATH_RED
	var players: Array = record.get("p", [])
	for index in range(2):
		var player: Dictionary = players[index] if index < players.size() else {}
		var detail := _t("correct_n") % int(player.get("correct", 0))
		if not bool(player.get("alive", true)):
			detail += "  " + _t("out_short")
		_set_text("P%dDetail" % (index + 1), detail)
	var winner := int(record.get("winner", -1))
	var win := _layer("WinGroup")
	if win != null:
		win.forced_hidden = winner < 0
		var base: Array = (win.record.base as Dictionary).position
		if winner == 2:
			win.override_base("position", [float(base[0]) + 648.0, float(base[1])])
		elif winner == 0:
			win.override_base("position", [648.0, float(base[1])])
			win.override_base("rotation", 0.0)
	_set_text("WinText", _t("draw") if winner == 0 else _t("win"))


## Final shown values of a 2P match as half points, and whether they carry a decimal
## (the finale's correct x (HP + 0.5) totals).
static func versus_totals(record: Dictionary) -> Array:
	var points: Array = record.get("points", [])
	if points.size() >= 2:
		var decimal := (int(points[0]) & 1) == 1 or (int(points[1]) & 1) == 1
		return [int(points[0]), int(points[1]), decimal]
	var players: Array = record.get("p", [])
	var totals := [0, 0, false]
	for index in range(mini(2, players.size())):
		totals[index] = int((players[index] as Dictionary).get("correct", 0)) * 2
	return totals


func _fill_solo(record: Dictionary) -> void:
	_set_text("HeaderText", _t("last_solo"))
	_set_text("ScoreLabel", _t("correct"))
	_set_text("ScoreSub", _mode_label(record))
	var player: Dictionary = (record.get("p", [{}]) as Array)[0]
	_set_text("Row1Label", _t("streak_best"))
	_set_text("Row1Value", str(int(player.get("best_streak", 0))))
	_set_text("Row2Label", _t("play_time"))
	_set_text("Row2Value", _t("seconds") % int(round(float(record.get("time", 0.0)))))


## One page of the match history (newest first).
func _fill_history(rows: Array) -> void:
	_set_text("HeaderText", _t("history"))
	for row in range(HISTORY_ROWS):
		var n := "R%d" % (row + 1)
		var group := _layer(n + "Group")
		var streak := _layer(n + "Streak")
		if row >= rows.size():
			for hidden: AeMotion.Layer in [group, streak]:
				if hidden != null:
					hidden.forced_hidden = true
			continue
		var record: Dictionary = rows[row]
		var players: Array = record.get("p", [])
		_set_text(n + "Date", _date_label(int(record.get("ts", 0))))
		# A draw settled underground shows "SUDDEN DEATH" in place of the mode.
		var sudden := not sudden_death_of(record).is_empty()
		_set_text(n + "ModeText", _t("mode_sudden_death") if sudden else _mode_label(record))
		var mode_pill := _layer(n + "ModePill")
		fit_pill(mode_pill, _layer(n + "ModeText"), 40.0, "left")
		if sudden and mode_pill != null:
			mode_pill.fill_color = SUDDEN_DEATH_RED
		var accent := GOLD
		var result := ""
		var result_fill := GOLD
		var result_ink := INK
		if int(record.get("players", 1)) >= 2:
			var totals := versus_totals(record)
			_set_text(n + "P1Val", format_points(totals[0], totals[2]))
			_set_text(n + "P2Val", format_points(totals[1], totals[2]))
			var winner := int(record.get("winner", -1))
			if winner == 1 or winner == 2:
				result = _t("row_win") % winner
				accent = player_colour(winner)
				result_fill = player_colour(winner)
			else:
				result = _t("row_draw")
		else:
			var player: Dictionary = players[0] if not players.is_empty() else {}
			var correct := int(player.get("correct", 0))
			var ten := str(record.get("mode", "")) == Constants.MODE_TEN
			_set_text(n + "P1Val", "%d/%d" % [correct, int(record.get("target", 10))] if ten else str(correct))
			# One score: it starts right of the P1 chip instead of ending at the "VS".
			var value := _layer(n + "P1Val")
			var chip := _layer(n + "P1Chip")
			if value != null and chip != null:
				var chip_pos: Array = (chip.record.base as Dictionary).position
				var value_pos: Array = (value.record.base as Dictionary).position
				value.override_base("position", [float(chip_pos[0]) + 44.0 + value.text_width(), float(value_pos[1])])
			for solo_hidden in ["Vs", "P2Val", "P2Chip", "P2ChipText"]:
				var layer := _layer(n + solo_hidden)
				if layer != null:
					layer.forced_hidden = true
			var cleared := str(record.get("end", "")) == Constants.STATE_CLEAR
			if cleared and ten and correct >= int(record.get("target", 10)):
				result = _t("row_perfect")
			elif cleared:
				result = _t("row_clear")
			else:
				result = _t("row_over")
				result_fill = TRACK
				result_ink = PALE
				accent = TRACK
		var accent_layer := _layer(n + "Accent")
		if accent_layer != null:
			accent_layer.fill_color = accent
		_set_text(n + "ResultText", result)
		var pill := _layer(n + "ResultPill")
		if pill != null:
			pill.fill_color = result_fill
		var label := _layer(n + "ResultText")
		if label != null:
			label.fill_color = result_ink
		fit_pill(pill, label, 40.0, "right", 150.0)


func _fill_stats() -> void:
	_set_text("HeaderText", _t("all_time"))
	_set_text("T1Label", _t("matches"))
	_set_text("T1Unit", _t("matches_unit"))
	_set_text("T2Label", _t("best"))
	_set_text("T2Unit", _t("best_unit"))
	_set_text("T3Label", _t("accuracy"))
	var ring := _layer("T3Ring")
	if ring != null:
		ring.trim_scale = float(_summary.get("accuracy", 0.0))


## Counters, winner badge and loser dimming follow the AE helper nulls.
func _update_segment() -> void:
	var count_layer := _layer("CountProgress")
	var count := count_layer.progress if count_layer != null else 1.0
	match str(_segment_info.comp):
		"LED_Versus":
			var record: Dictionary = _segment_info.record
			var totals := versus_totals(record)
			for index in range(2):
				var shown := int(round(float(totals[index]) * count))
				if not totals[2]:
					shown = (shown >> 1) << 1
				_set_text("P%dScore" % (index + 1), format_points(shown, totals[2]))
			var verdict_layer := _layer("VerdictProgress")
			var verdict := verdict_layer.progress if verdict_layer != null else 0.0
			var winner := int(record.get("winner", -1))
			for index in range(2):
				var group := _layer("P%dGroup" % (index + 1))
				if group != null:
					var loser := winner > 0 and winner != index + 1
					group.modulate = Color(1, 1, 1).lerp(Color(DIM, DIM, DIM), verdict if loser else 0.0)
		"LED_Solo":
			var record: Dictionary = _segment_info.record
			var player: Dictionary = (record.get("p", [{}]) as Array)[0]
			var correct := int(round(float(player.get("correct", 0)) * count))
			if str(record.get("mode", "")) == Constants.MODE_TEN:
				_set_text("ScoreText", "%d/%d" % [correct, int(record.get("target", 10))])
			else:
				_set_text("ScoreText", str(correct))
		"LED_Stats":
			_set_text("T1Value", str(int(round(float(_summary.get("matches", 0)) * count))))
			_set_text("T2Value", str(int(round(float(_summary.get("best_correct", 0)) * count))))
			_set_text("T3Value", "%d%%" % int(round(float(_summary.get("accuracy", 0.0)) * 100.0 * count)))
			var inside := _layer("T3Value")
			if inside != null:
				# "100%" is wider than the ring's opening at AE's size.
				inside.extra_scale = minf(1.0, RING_TEXT_WIDTH / maxf(1.0, inside.text_width()))


# ---------------------------------------------------------------- replay

## The moments of one clip (clips stored before moments were kept one per clip).
static func clip_events(clip: Dictionary) -> Array:
	var events: Array = clip.get("events", [])
	if not events.is_empty():
		return events
	return [{"kind": clip.get("kind", ""), "player": clip.get("player", 0), "streak": clip.get("streak", 3),
		"t": clip.get("event", 0.0)}]


## Playback pieces of one clip: {s0, s1 (clip seconds), rate, d0 (shown second)}.
## Fast-forward (`fast`) between moments, real speed FOCUS_BEFORE / FOCUS_AFTER around
## each, SLOW_RATE right at it.
static func clip_pieces(length: float, events: Array, fast: float) -> Array[Dictionary]:
	var cuts: Array[float] = [0.0, length]
	for event: Dictionary in events:
		var t := float(event.get("t", 0.0))
		for edge: float in [t - FOCUS_BEFORE, t - SLOW_BEFORE, t + SLOW_AFTER, t + FOCUS_AFTER]:
			cuts.append(clampf(edge, 0.0, length))
	cuts.sort()
	var pieces: Array[Dictionary] = []
	var shown := 0.0
	for index in range(cuts.size() - 1):
		var s0 := cuts[index]
		var s1 := cuts[index + 1]
		if s1 - s0 < 0.0001:
			continue
		var mid := (s0 + s1) * 0.5
		var rate := fast
		for event: Dictionary in events:
			var t := float(event.get("t", 0.0))
			if mid >= t - SLOW_BEFORE and mid <= t + SLOW_AFTER:
				rate = SLOW_RATE
				break
			if mid >= t - FOCUS_BEFORE and mid <= t + FOCUS_AFTER:
				rate = 1.0
		pieces.append({"s0": s0, "s1": s1, "rate": rate, "d0": shown})
		shown += (s1 - s0) / rate
	return pieces


## Clip second (x) and playback rate (y) at a shown second; holds on the last frame.
static func source_at(pieces: Array, shown: float) -> Vector2:
	for piece: Dictionary in pieces:
		var span := (float(piece.s1) - float(piece.s0)) / float(piece.rate)
		if shown < float(piece.d0) + span:
			return Vector2(float(piece.s0) + maxf(0.0, shown - float(piece.d0)) * float(piece.rate), float(piece.rate))
	if pieces.is_empty():
		return Vector2(0.0, 1.0)
	return Vector2(float(pieces[pieces.size() - 1].s1), 1.0)


static func shown_at(pieces: Array, source: float) -> float:
	for piece: Dictionary in pieces:
		if source <= float(piece.s1):
			return float(piece.d0) + maxf(0.0, source - float(piece.s0)) / float(piece.rate)
	return 0.0 if pieces.is_empty() else float(pieces[pieces.size() - 1].d0)


## Plans one match's replay: every clip in order, each clip's pieces, where each
## moment's caption starts. Gaps play faster when the whole would run too long.
func plan_replay(clips: Array, fast: float = FAST_RATE) -> Dictionary:
	var moments: Array[Dictionary] = []
	var captions: Array[Dictionary] = []
	var start := 0.0
	for clip: Dictionary in clips:
		var times: Array = clip.get("times", [])
		if times.size() < 2:
			continue
		var length := float(times[times.size() - 1])
		var events := clip_events(clip)
		var pieces := clip_pieces(length, events, fast)
		var shown := shown_at(pieces, length) + MOMENT_HOLD
		for event: Dictionary in events:
			captions.append({"at": start + shown_at(pieces, maxf(0.0, float(event.get("t", 0.0)) - CAPTION_LEAD)),
				"event": event, "players": int(clip.get("players", 1))})
		moments.append({"clip": clip, "start": start, "length": shown, "pieces": pieces})
		start += shown
	var plan := {"moments": moments, "captions": captions, "duration": start + REPLAY_OUTRO, "fast": fast}
	if start > REPLAY_LONG and fast < FASTER_RATE:
		return plan_replay(clips, FASTER_RATE)
	return plan


func _build_replay(clips: Array) -> Control:
	_replay = plan_replay(clips)
	var root := Control.new()
	root.name = "Replay"
	root.size = Vector2(CANVAS)
	root.clip_contents = true
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_replay_media = Control.new()
	_replay_media.name = "Media"
	_replay_media.size = Vector2(CANVAS)
	_replay_media.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_replay_media.draw.connect(_draw_replay_media)
	root.add_child(_replay_media)
	_replay_frame = _motion.instance("REPLAY_Frame", FONT)
	_replay_caption = _motion.instance("REPLAY_Caption", FONT)
	_replay_cut = _motion.instance("CUT_Strokes", FONT)
	for comp: AeMotion.Comp in [_replay_frame, _replay_caption, _replay_cut]:
		root.add_child(comp)
	var first: Dictionary = (_replay.moments as Array)[0].clip if not (_replay.moments as Array).is_empty() else {}
	var info := _replay_frame.layer("InfoText")
	if info != null:
		info.text = "%s  %s" % [_date_label(int(first.get("ts", 0))), _mode_label(first)]
		fit_pill(_replay_frame.layer("InfoPill"), info, 48.0, "right")
	_replay_now = {}
	return root


func _apply_replay(time: float) -> void:
	var moments: Array = _replay.moments
	if moments.is_empty():
		return
	var index := 0
	while index + 1 < moments.size() and time >= float(moments[index + 1].start):
		index += 1
	var moment: Dictionary = moments[index]
	var sample := source_at(moment.pieces, time - float(moment.start))
	if int(_replay_now.get("index", -1)) != index:
		for ahead in range(index, mini(index + 3, moments.size())):
			_load_clip(moments[ahead].clip)
	_replay_now = {"index": index, "clip": moment.clip, "source": sample.x, "rate": sample.y,
		"progress": clampf((time - float(moment.start)) / maxf(0.1, float(moment.length)), 0.0, 1.0)}
	_replay_media.queue_redraw()
	# Corner bugs: which moment, fast-forward while it runs, progress along the bottom.
	_replay_frame.apply(fmod(time, _replay_frame.duration))
	var word := _replay_frame.layer("ReplayText")
	if word != null:
		word.text = _t("replay") % [index + 1, moments.size()]
		fit_pill(_replay_frame.layer("ReplayPill"), word, 100.0, "left")
	var fast := _replay_frame.layer("FastGroup")
	if fast != null:
		fast.forced_hidden = sample.y <= 1.01
		var fast_text := _replay_frame.layer("FastText")
		if fast_text != null:
			fast_text.text = _t("fast") % int(round(sample.y))
	var bar := _replay_frame.layer("Progress")
	if bar != null:
		bar.scale.x = clampf(time / maxf(0.1, float(_replay.duration) - REPLAY_OUTRO), 0.0, 1.0)
	# The moment's name: the latest caption that has started, while its sweep runs.
	var active: Dictionary = {}
	for caption: Dictionary in _replay.captions:
		if float(caption.at) <= time:
			active = caption
	var local := time - float(active.get("at", -INF))
	_replay_caption.visible = not active.is_empty() and local < _replay_caption.duration
	if _replay_caption.visible:
		_replay_caption.apply(local)
		var event: Dictionary = active.event
		var words := _replay_caption.layer("CapText")
		var band := _replay_caption.layer("CapBand")
		if words != null and band != null:
			words.text = event_label(event, int(active.players))
			band.stroke_color = player_colour(int(event.get("player", 0)))
			band.line_end_x = 36.0 + words.text_width() + 44.0
			for echo_name: String in ["CapEchoTop", "CapEchoBottom"]:
				var echo := _replay_caption.layer(echo_name)
				if echo != null:
					echo.line_end_x = band.line_end_x * (0.72 if echo_name == "CapEchoTop" else 0.55)
	# The cut between moments: strokes and a flash peak on the swap.
	var cutting := false
	for next in range(1, moments.size()):
		var from := float(moments[next].start) - CUT_SWAP
		if time >= from and time < from + _replay_cut.duration:
			_replay_cut.apply(time - from)
			cutting = true
			break
	_replay_cut.visible = cutting


## The current clip frame over the whole screen, cover-fitted, cross-fading between
## captured frames, with a slow push-in.
func _draw_replay_media() -> void:
	var rect := Rect2(Vector2.ZERO, _replay_media.size)
	_replay_media.draw_rect(rect, Color(0.055, 0.086, 0.173))
	if _replay_now.is_empty():
		return
	var clip: Dictionary = _replay_now.clip
	var loaded: Dictionary = _frames.get(str(clip.get("id", "")), {})
	if loaded.is_empty():
		return
	var textures: Array = loaded.textures
	var sample := frame_at(clip.get("times", []), float(_replay_now.source))
	var focus := float(CLIP_FOCUS_Y_BY_KIND.get(str(clip.get("kind", "")), CLIP_FOCUS_Y))
	var zoom := 1.0 + CLIP_ZOOM * float(_replay_now.progress)
	var index := mini(int(sample.x), textures.size() - 1)
	_draw_cover(_replay_media, textures[index], rect, 1.0, focus, zoom)
	if sample.y > 0.01 and index + 1 < textures.size():
		_draw_cover(_replay_media, textures[index + 1], rect, sample.y, focus, zoom)


## Frame index (x) and blend towards the next (y) at a clip second.
static func frame_at(times: Array, source: float) -> Vector2:
	if times.is_empty():
		return Vector2.ZERO
	var index := 0
	while index + 1 < times.size() and float(times[index + 1]) <= source:
		index += 1
	if index + 1 >= times.size():
		return Vector2(index, 0.0)
	var span := float(times[index + 1]) - float(times[index])
	return Vector2(index, clampf((source - float(times[index])) / maxf(span, 0.001), 0.0, 1.0))


static func _draw_cover(canvas: CanvasItem, texture: Texture2D, rect: Rect2, alpha: float, focus_y: float, zoom: float) -> void:
	var source := texture.get_size()
	var fit := maxf(rect.size.x / source.x, rect.size.y / source.y) * zoom
	var region := Rect2(Vector2.ZERO, rect.size / fit)
	region.position.x = (source.x - region.size.x) * 0.5
	region.position.y = clampf(source.y * focus_y - region.size.y * 0.5, 0.0, source.y - region.size.y)
	canvas.draw_texture_rect_region(texture, rect, region, Color(1, 1, 1, alpha))


func _load_clip(clip: Dictionary) -> void:
	var id := str(clip.get("id", ""))
	if id.is_empty() or _frames.has(id) or _loading.has(id):
		return
	var holder: Array = []
	var task := WorkerThreadPool.add_task(MenuLedProgram._load_task.bind(clip, holder), false, "LED clip")
	_loading[id] = {"task": task, "holder": holder, "clip": clip}


## Decodes a clip and shrinks its frames to FRAME_SIZE (worker thread).
static func _load_task(clip: Dictionary, holder: Array) -> void:
	for image: Image in HighlightStore.load_frames(clip):
		image.resize(FRAME_SIZE.x, FRAME_SIZE.y, Image.INTERPOLATE_BILINEAR)
		holder.append(image)


func _exit_tree() -> void:
	for id: String in _loading:
		WorkerThreadPool.wait_for_task_completion(_loading[id].task)
	_loading.clear()


func _poll_loading() -> void:
	for id: String in _loading.keys():
		var job: Dictionary = _loading[id]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_loading.erase(id)
		var textures: Array[ImageTexture] = []
		for image: Image in job.holder:
			textures.append(ImageTexture.create_from_image(image))
		if textures.size() >= 2:
			_frames[id] = {"textures": textures, "clip": job.clip}
	# Keep the playing clip, the two after it and the first two of the round's replay.
	var wanted := {}
	if not _replay.is_empty() and not _replay_now.is_empty():
		var moments: Array = _replay.moments
		for ahead in range(maxi(0, int(_replay_now.index) - 1), mini(int(_replay_now.index) + 3, moments.size())):
			wanted[str(moments[ahead].clip.get("id", ""))] = true
	for item: Dictionary in _round:
		if item.comp == "REPLAY" and _round.find(item) >= _round_index:
			for clip: Dictionary in (item.clips as Array).slice(0, 2):
				wanted[str(clip.get("id", ""))] = true
	for id: String in _frames.keys():
		if not wanted.has(id):
			_frames.erase(id)
