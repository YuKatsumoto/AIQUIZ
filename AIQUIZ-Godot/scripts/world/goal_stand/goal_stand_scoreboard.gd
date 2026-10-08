class_name GoalStandScoreboard
extends Node

## Baseball-style electric scoreboard on the goal stand's LED face. One column
## per question (1-10) plus R: the player who took a question gets a lit ring in
## their colour, a question nobody got shows "−" on both rows. When the match
## winner is settled and the verdict "WIN" comes up, the board switches to that
## player's cut-in and holds it: a band in their colour, their own block figure
## (hat included) pumping both fists and "1P WIN!" / "2P WIN!" ("DRAW!" with both
## figures on a draw). Drawn into a SubViewport that only re-renders on change.
##
## A local 2P draw that branches into the sudden death (docs/sudden_death_underground.md
## 2.1) swaps "DRAW!" for a flashing hazard-red "SUDDEN DEATH!" from SUDDEN_DEATH_CUTIN
## while the sudden death runs; back on the surface the winner's cut-in carries a
## "SUDDEN DEATH" tag and the sub-line "サドンデス決着".
##
## Once the match is recorded (`programme_ready` of sync) the cut-in gives way to
## "AIQUIZ VISION" (MenuLedProgram): the strokes of its wipe sweep over the cut-in, then
## RECORDS, the last match, the history, the all-time stats and the logo play on the
## board until the stand is freed. The programme's highlight replay is left out here
## (PLAY_REPLAY).

const FONT: Font = preload("res://resources/fonts/NotoSansJP-Bold.otf")
const SIZE := Vector2i(1400, 600)   # the LED face is 11.2 x 4.8 m (7:3)
const COLUMNS := 10
const P_COLORS: Array[Color] = [Color(0.95, 0.55, 0.20), Color(0.20, 0.65, 0.90)]
const BOARD := Color("#0b1f17")
const BOARD_DEEP := Color("#06140e")
const GRID := Color("#1d3b2d")
const LAMP_OFF := Color("#17301f")
const AMBER := Color("#ffd35a")
const DIM := Color("#6f7f74")
const FLASH_SECONDS := 0.6
const LABEL_W := 170.0
const TOTAL_W := 160.0
const MARGIN := 38.0
const HEADER_Y := 132.0
const HEADER_H := 70.0
const ROW_H := 162.0
const ROW_GAP := 16.0
const CUTIN_ENTER := 0.25
## Seconds the winner's / draw cut-in stays up before the programme may take the board
## over, even when the match is already recorded.
const CUTIN_MIN_HOLD := 15.0
const DRAW := 3
## Cut-in of a draw branching into the sudden death.
const SUDDEN_DEATH := 4
## Ceremony second of the "SUDDEN DEATH!" cut-in (docs/sudden_death_underground.md 2.1).
const SUDDEN_DEATH_CUTIN := 8.6
const HAZARD_RED := Color("#d3261f")
const HAZARD_DEEP := Color("#2a0505")
const HAZARD_INK := Color("#160404")
const ARM_UP := 2.55
const PORTRAIT := Vector2i(560, 560)
## Viewport textures have no mipmaps. A chain of half-size SubViewports rebuilds
## them on the GPU whenever the board redraws, so the LED shader can filter the
## board properly far away instead of shimmering.
const MIP_LEVELS := 7
## Whether the programme's HIGHLIGHTS title and the highlight replay play on the board.
## Off: the programme gets no clips, so its round starts at RECORDS (MatchReel still
## records the clips; MenuLedProgram plays them when it is given any).
const PLAY_REPLAY := false
## NONE: the grid / cut-in. LEAD_IN: the programme's wipe strokes cover the cut-in.
## PLAYING: the programme on its own. FAILED: it could not start, the cut-in stays.
## The programme (1296 x 588) is stretched over the board (1400 x 600), +8 % wide.
enum Programme { NONE, LEAD_IN, PLAYING, FAILED }

var viewport: SubViewport
var mips: Array[SubViewport] = []
var marks := PackedInt32Array()
var current := -1
## Cut-in on the board: 0 = score grid, 1/2 = that player won, DRAW = draw,
## SUDDEN_DEATH = the draw goes to the sudden death.
var cutin_player := 0
## The winner's cut-in names the sudden death that settled the draw.
var cutin_sudden_death := false
## Milliseconds the frame that started the programme spent building it (tests report it).
var programme_setup_msec := 0.0

var _canvas: Control
var _blink := false
var _flash_started := {}
var _clock := 0.0
var _cutin_started := -1.0
var _cutin_english := false
var _actors := {}
var _mip_frames := 0
var _programme: MenuLedProgram = null
var _programme_phase := Programme.NONE


func setup() -> void:
	name = "Scoreboard"
	viewport = SubViewport.new()
	viewport.name = "ScoreboardViewport"
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	_canvas = Control.new()
	_canvas.name = "Board"
	_canvas.size = Vector2(SIZE)
	_canvas.draw.connect(_draw_board)
	viewport.add_child(_canvas)
	marks.resize(COLUMNS)
	marks.fill(-1)
	var source: Texture2D = viewport.get_texture()
	var size := SIZE
	for level in range(MIP_LEVELS):
		size = Vector2i(maxi(1, (size.x + 1) / 2), maxi(1, (size.y + 1) / 2))
		var mip := SubViewport.new()
		mip.name = "Mip%d" % (level + 1)
		mip.size = size
		mip.disable_3d = true
		mip.transparent_bg = false
		mip.render_target_update_mode = SubViewport.UPDATE_ONCE
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
	_mip_frames = MIP_LEVELS + 1


func get_texture() -> Texture2D:
	return viewport.get_texture()


## Half-size copies of the board, level 1 (700 x 300) down to level MIP_LEVELS.
func get_mip_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for mip in mips:
		textures.append(mip.get_texture())
	return textures


## `animate` is false far down the course: marks still land, the blink freezes.
## `verdict_winner` is the settled match winner once the verdict is out (0 = draw),
## -1 before that. `programme_ready` is true once the finished match is recorded and the
## board may hand over from the cut-in to the programme (it never goes back).
func sync(state: QuizGameState, clock: float, animate: bool = true, verdict_winner: int = -1,
		programme_ready: bool = false) -> void:
	_clock = clock
	var dirty := false
	for index in range(COLUMNS):
		var mark := state.get_question_winner(index)
		if mark != marks[index]:
			if mark >= 0 and marks[index] < 0:
				_flash_started[index] = clock
			marks[index] = mark
			dirty = true
	var wanted := 0 if verdict_winner < 0 else (verdict_winner if verdict_winner in [1, 2] else DRAW)
	if shows_sudden_death(state):
		wanted = SUDDEN_DEATH
	if _programme_phase == Programme.PLAYING:
		# The verdict stays out for good, so without this the cut-in would start again.
		wanted = 0
	elif _programme_phase == Programme.NONE and programme_ready and cutin_player != 0 \
			and clock - _cutin_started >= CUTIN_MIN_HOLD:
		_start_programme()
	if _programme_phase == Programme.LEAD_IN and not _programme.is_lead_in():
		_programme_phase = Programme.PLAYING
		wanted = 0
	if wanted != cutin_player:
		if wanted == 0:
			_end_cutin()
		else:
			_start_cutin(state, wanted, clock)
		dirty = true
	if cutin_player != 0:
		for player in _cutin_players():
			_pose_actor(player, clock - _cutin_started)
		dirty = true
	var playing := state.game_state == Constants.STATE_PLAYING
	var now := state.current_index if playing and state.current_index < COLUMNS else -1
	if now != current:
		current = now
		dirty = true
	var blink := animate and current >= 0 and int(clock * 4.0) % 2 == 0
	if blink != _blink:
		_blink = blink
		dirty = true
	for index: int in _flash_started.keys():
		if clock - float(_flash_started[index]) > FLASH_SECONDS:
			_flash_started.erase(index)
		dirty = true
	if is_programme_started():
		# Far down the course nobody sees it: the programme and the board freeze.
		_programme.set_active(animate)
		dirty = dirty or animate
	if dirty:
		_canvas.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		# Each level reads the previous one, so refresh the chain for a few frames
		# whatever order the renderer draws the viewports in.
		_mip_frames = MIP_LEVELS + 1
	if _mip_frames > 0:
		_mip_frames -= 1
		for mip in mips:
			mip.render_target_update_mode = SubViewport.UPDATE_ONCE


func is_cutin_playing() -> bool:
	return cutin_player != 0


## The draw is branching into the sudden death ("DRAW!" has had its moment) or the
## sudden death is being played: the board shows "SUDDEN DEATH!".
static func shows_sudden_death(state: QuizGameState) -> bool:
	if state.game_state == Constants.STATE_SUDDEN_DEATH:
		return true
	return state.sudden_death_pending and state.result_presentation_active \
		and state.result_ceremony_elapsed >= SUDDEN_DEATH_CUTIN


## The programme has taken the board over (its lead-in over the cut-in included).
func is_programme_started() -> bool:
	return _programme_phase == Programme.LEAD_IN or _programme_phase == Programme.PLAYING


## The cut-in is gone and only the programme is on the board.
func is_programme_playing() -> bool:
	return _programme_phase == Programme.PLAYING


func programme() -> MenuLedProgram:
	return _programme


## The programme's playing segment ({} before it started), e.g. {comp: "LED_Sting", ...}.
func programme_segment() -> Dictionary:
	return _programme.current_segment() if _programme != null else {}


# ------------------------------------------------------------------ programme

func _start_programme() -> void:
	var started_usec := Time.get_ticks_usec()
	var programme := MenuLedProgram.new()
	add_child(programme)
	# The board builds its own mip chain, so the programme keeps none.
	var clips: Variant = null if PLAY_REPLAY else []
	if not programme.setup(null, clips, 0):
		programme.queue_free()
		_programme_phase = Programme.FAILED
		return
	programme.begin_lead_in()
	_programme = programme
	_programme_phase = Programme.LEAD_IN
	programme_setup_msec = float(Time.get_ticks_usec() - started_usec) / 1000.0


func totals() -> Array[int]:
	var result: Array[int] = [0, 0]
	for mark in marks:
		if mark > 0:
			result[0] += 1 if mark & 1 else 0
			result[1] += 1 if mark & 2 else 0
	return result


# ------------------------------------------------------------------ cut-in

func _cutin_players() -> Array[int]:
	var players: Array[int] = []
	if cutin_player == DRAW:
		players.assign([1, 2])
	elif cutin_player != 0:
		players.append(cutin_player)
	return players


func _start_cutin(state: QuizGameState, who: int, clock: float) -> void:
	_end_cutin()
	cutin_player = who
	_cutin_started = clock
	cutin_sudden_death = who in [1, 2] and state.sudden_death_winner == who
	_cutin_english = state.use_english_ui
	for player in _cutin_players():
		var hat := state.p1_hat if player == 1 else state.p2_hat
		var actor: Dictionary = _actors.get(player, {})
		if actor.is_empty() or int(actor.hat) != hat:
			if not actor.is_empty():
				(actor.viewport as SubViewport).queue_free()
			actor = _build_actor(player, hat)
			_actors[player] = actor
		(actor.viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_pose_actor(player, 0.0)


func _end_cutin() -> void:
	for actor: Dictionary in _actors.values():
		(actor.viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	cutin_player = 0
	cutin_sudden_death = false
	_cutin_started = -1.0


func _build_actor(player: int, hat: int) -> Dictionary:
	var portrait := SubViewport.new()
	portrait.name = "P%dPortrait" % player
	portrait.size = PORTRAIT
	portrait.transparent_bg = true
	portrait.own_world_3d = true
	portrait.msaa_3d = Viewport.MSAA_4X
	portrait.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(portrait)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	environment.environment.ambient_light_energy = 0.55
	portrait.add_child(environment)
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.transform = Transform3D(Basis(), Vector3(0.0, 0.15, 4.9)).looking_at(Vector3(0.0, 0.1, 0.0), Vector3.UP)
	portrait.add_child(camera)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 30.0 if player == 1 else -30.0, 0.0)
	key.light_energy = 1.25
	portrait.add_child(key)
	var root := Node3D.new()
	root.name = "Actor"
	root.rotation.y = 0.35 if player == 1 else -0.35
	portrait.add_child(root)
	var parts := EmoteBlockmanPreview.build_player_skeleton(player == 1, root, hat)
	return {"viewport": portrait, "root": root, "parts": parts, "hat": hat}


## Both arms thrown up with a hop, then fist pumps for as long as the board holds.
func _pose_actor(player: int, t: float) -> void:
	var actor: Dictionary = _actors[player]
	var parts: Dictionary = actor.parts
	var raise := _ease_back(clampf((t - 0.05) / 0.22, 0.0, 1.0))
	var pump := 0.35 * maxf(0.0, sin((t - 0.5) * TAU * 1.4)) if t > 0.5 else 0.0
	for key: String in ["l_shoulder", "r_shoulder"]:
		var dir := -1.0 if key.begins_with("l") else 1.0
		(parts[key] as Node3D).rotation.z = dir * (ARM_UP * raise - pump)
		(parts[key.replace("shoulder", "elbow")] as Node3D).rotation.z = dir * 0.35 * raise
	var hop := sin(clampf((t - 0.05) / 0.4, 0.0, 1.0) * PI) * 0.3
	var bounce := absf(sin((t - 0.5) * PI * 1.4)) * 0.1 if t > 0.5 else 0.0
	(actor.root as Node3D).position.y = hop + bounce


static func _ease_back(x: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


func _flip_x(x: float) -> float:
	return x if cutin_player != 2 else float(SIZE.x) - x


func _draw_cutin() -> void:
	if cutin_player == SUDDEN_DEATH:
		_draw_sudden_death_cutin()
		_draw_led_frame()
		return
	var t := _clock - _cutin_started
	var w := float(SIZE.x)
	var is_draw := cutin_player == DRAW
	var color: Color = AMBER if is_draw else P_COLORS[cutin_player - 1]
	# P1 slides in from the left, P2 from the right, a draw drops from the top.
	var enter := _ease_out(t / CUTIN_ENTER)
	var offset := Vector2(0.0, -float(SIZE.y) * (1.0 - enter)) if is_draw else Vector2((-1.0 if cutin_player == 1 else 1.0) * w * (1.0 - enter), 0.0)
	var figures: Array[Vector2] = []
	if is_draw:
		figures = [Vector2(250.0, 290.0) + offset, Vector2(w - 250.0, 290.0) + offset]
	else:
		figures = [Vector2(_flip_x(330.0), 290.0) + offset]
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), BOARD_DEEP)
	# Rotating light rays behind the figure (behind the title on a draw).
	var ray_center := Vector2(w * 0.5, 290.0) + offset if is_draw else figures[0]
	var rays := 14
	for ray in range(rays):
		var a := TAU * float(ray) / rays + t * 0.5
		var spread := PI / rays * 0.55
		_canvas.draw_colored_polygon(PackedVector2Array([ray_center,
			ray_center + Vector2.from_angle(a - spread) * 1800.0,
			ray_center + Vector2.from_angle(a + spread) * 1800.0]), Color(color.darkened(0.45), 0.55))
	# Slanted band in the winner's colour with a white rule under it.
	var top := 150.0
	var bottom := 470.0
	var slant := 110.0
	var tip := w + 60.0 if is_draw else w * 0.93
	var band := PackedVector2Array()
	for p: Vector2 in [Vector2(-60.0, top), Vector2(tip + slant, top), Vector2(tip, bottom), Vector2(-60.0, bottom)]:
		band.append(Vector2(_flip_x(p.x), p.y) + offset)
	_canvas.draw_colored_polygon(band, color)
	var rule := PackedVector2Array()
	for p: Vector2 in [Vector2(-60.0, bottom + 12.0), Vector2(tip - 6.0, bottom + 12.0), Vector2(tip - 10.0, bottom + 26.0), Vector2(-60.0, bottom + 26.0)]:
		rule.append(Vector2(_flip_x(p.x), p.y) + offset)
	_canvas.draw_colored_polygon(rule, Color(1, 1, 1, 0.92))
	# The players' own figures, standing on the band's lower edge.
	var box := Vector2(PORTRAIT)
	var players := _cutin_players()
	for index in range(players.size()):
		var portrait := (_actors[players[index]].viewport as SubViewport).get_texture()
		_canvas.draw_texture_rect(portrait, Rect2(figures[index] - box * 0.5, box), false)
	# The title slams in, then blinks like a lamp board.
	var slam := _ease_out((t - 0.15) / 0.25)
	if slam > 0.0:
		var title := "DRAW!" if is_draw else "%dP WIN!" % cutin_player
		var font_size := 190
		var grow := 1.0 + 0.7 * (1.0 - slam)
		var lit := Color.WHITE if t < 0.7 or int(t * 5.0) % 2 == 0 else (Color("#fff4c8") if is_draw else AMBER)
		var text_center := (Vector2(w * 0.5, 290.0) if is_draw else Vector2(_flip_x(930.0), 290.0)) + offset
		var text_size := FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var outline := Color(color.darkened(0.65), slam)
		_canvas.draw_set_transform(text_center, 0.0, Vector2(grow, grow))
		var origin := Vector2(-text_size.x * 0.5, font_size * 0.36)
		_canvas.draw_string_outline(FONT, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 26, outline)
		_canvas.draw_string(FONT, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(lit, slam))
		_canvas.draw_set_transform(Vector2.ZERO)
		var sub := "引き分け" if is_draw else "WINNER"
		if cutin_sudden_death and not _cutin_english:
			sub = "サドンデス決着"
		var sub_size := FONT.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 60)
		var sub_origin := Vector2(text_center.x - sub_size.x * 0.5, 440.0 + offset.y)
		_canvas.draw_string_outline(FONT, sub_origin, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, 14, outline)
		_canvas.draw_string(FONT, sub_origin, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color(1, 1, 1, slam))
		if cutin_sudden_death:
			_draw_sudden_death_tag(Vector2(text_center.x, 92.0 + offset.y), t, slam)
	_draw_led_frame()


## LED scanlines and the board frame on top of a cut-in.
func _draw_led_frame() -> void:
	var w := float(SIZE.x)
	for y in range(0, SIZE.y, 6):
		_canvas.draw_line(Vector2(0.0, y), Vector2(w, y), Color(0, 0, 0, 0.14), 2.0)
	var full := Rect2(Vector2.ZERO, Vector2(SIZE))
	_canvas.draw_rect(full.grow(-6.0), Color(0.93, 0.92, 0.89), false, 12.0)
	_canvas.draw_rect(full.grow(-17.0), BOARD_DEEP, false, 10.0)


## A strip of black and amber hazard stripes from x0 to x1, crawling sideways.
func _draw_hazard_tape(x0: float, x1: float, top: float, height: float, t: float, alpha: float = 1.0) -> void:
	_canvas.draw_rect(Rect2(x0, top, x1 - x0, height), Color(AMBER, alpha))
	var period := 72.0
	var stripe := 34.0
	var tape := PackedVector2Array([Vector2(x0, top), Vector2(x1, top), Vector2(x1, top + height), Vector2(x0, top + height)])
	var x := x0 - height - period + fposmod(t * 90.0, period)
	while x < x1:
		var slant := PackedVector2Array([Vector2(x + height, top), Vector2(x + height + stripe, top),
			Vector2(x + stripe, top + height), Vector2(x, top + height)])
		# Stripes are cut at the tape's ends.
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(slant, tape):
			# Clipping at the tape's ends can leave slivers that cannot be triangulated.
			if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
				_canvas.draw_colored_polygon(piece, Color(HAZARD_INK, alpha))
		x += period


## The "SUDDEN DEATH" tag over a sudden death winner's title: a hazard tape with a
## dark plate on it, slid in with the title.
func _draw_sudden_death_tag(center: Vector2, t: float, alpha: float) -> void:
	var words := "SUDDEN DEATH"
	var size := 46
	var text_size := FONT.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var plate := Rect2(center - Vector2(text_size.x * 0.5 + 34.0, 34.0), Vector2(text_size.x + 68.0, 68.0))
	_draw_hazard_tape(plate.position.x - 150.0, plate.end.x + 150.0, center.y - 20.0, 40.0, t, alpha)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(HAZARD_DEEP, alpha)
	box.border_color = Color(HAZARD_RED, alpha)
	box.set_border_width_all(6)
	box.set_corner_radius_all(14)
	_canvas.draw_style_box(box, plate)
	var lit := AMBER if int(t * 4.0) % 2 == 0 or t < 0.7 else Color.WHITE
	var origin := Vector2(center.x - text_size.x * 0.5, center.y + size * 0.36)
	_canvas.draw_string(FONT, origin, words, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(lit, alpha))


## "SUDDEN DEATH!" while the draw branches underground: a hazard-red board with
## rotating beacon beams, crawling hazard tapes and the title flashing like a siren.
func _draw_sudden_death_cutin() -> void:
	var t := _clock - _cutin_started
	var w := float(SIZE.x)
	var h := float(SIZE.y)
	var siren := 0.5 + 0.5 * sin(t * TAU * 1.5)
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), HAZARD_DEEP.lerp(HAZARD_RED.darkened(0.55), siren * 0.6))
	# Two beacon beams sweeping round the centre.
	var center := Vector2(w * 0.5, h * 0.5)
	for beam in range(2):
		var a := t * 3.2 + PI * beam
		for layer in range(3):
			var spread := 0.16 + 0.1 * layer
			_canvas.draw_colored_polygon(PackedVector2Array([center,
				center + Vector2.from_angle(a - spread) * 1600.0,
				center + Vector2.from_angle(a + spread) * 1600.0]), Color(1.0, 0.45, 0.12, 0.16 - 0.04 * layer))
	# The red band drops in from the top with its hazard tapes.
	var enter := _ease_out(t / CUTIN_ENTER)
	var drop := -h * (1.0 - enter)
	var top := 150.0 + drop
	var bottom := 420.0 + drop
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(-60.0, top), Vector2(w + 60.0, top),
		Vector2(w + 60.0, bottom), Vector2(-60.0, bottom)]), HAZARD_RED.lerp(Color("#ff4a2a"), siren * 0.35))
	_draw_hazard_tape(0.0, w, top - 52.0, 40.0, t)
	_draw_hazard_tape(0.0, w, bottom + 12.0, 40.0, -t)
	# White flash as the title lands.
	var flash := clampf(1.0 - absf(t - 0.32) / 0.18, 0.0, 1.0)
	var slam := _ease_out((t - 0.15) / 0.25)
	if slam > 0.0:
		var title := "SUDDEN DEATH!"
		var font_size := 170
		var natural := FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var fit := minf(1.0, (w - 150.0) / maxf(1.0, natural.x))
		var grow := fit * (1.0 + 0.7 * (1.0 - slam))
		var lit := Color.WHITE if t < 0.7 or int(t * 6.0) % 2 == 0 else AMBER
		var text_center := Vector2(w * 0.5, (top + bottom) * 0.5)
		_canvas.draw_set_transform(text_center, 0.0, Vector2(grow, grow))
		var origin := Vector2(-natural.x * 0.5, font_size * 0.36)
		_canvas.draw_string_outline(FONT, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 28, Color(HAZARD_INK, slam))
		_canvas.draw_string(FONT, origin, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(lit, slam))
		_canvas.draw_set_transform(Vector2.ZERO)
		var sub := "TO THE UNDERGROUND!" if _cutin_english else "地下神殿で決着！"
		var sub_size := FONT.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 56)
		var sub_origin := Vector2(w * 0.5 - sub_size.x * 0.5, 548.0 + drop)
		_canvas.draw_string_outline(FONT, sub_origin, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, 14, Color(HAZARD_INK, slam))
		_canvas.draw_string(FONT, sub_origin, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1, 1, 1, slam))
	if flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color(1, 1, 1, 0.55 * flash))


# ------------------------------------------------------------------ drawing

func _column_w() -> float:
	return (float(SIZE.x) - MARGIN * 2.0 - LABEL_W - TOTAL_W) / float(COLUMNS)


func _column_x(index: int) -> float:
	return MARGIN + LABEL_W + _column_w() * index


func _row_y(row: int) -> float:
	return HEADER_Y + HEADER_H + ROW_GAP + (ROW_H + ROW_GAP) * row


func _text(pos: Vector2, width: float, text: String, size: int, color: Color) -> void:
	_canvas.draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _draw_board() -> void:
	if is_programme_started():
		var full := Rect2(Vector2.ZERO, Vector2(SIZE))
		if _programme_phase == Programme.LEAD_IN and cutin_player != 0:
			# The programme's strokes sweep over the cut-in, which keeps playing under them.
			_draw_cutin()
		else:
			_canvas.draw_rect(full, BOARD_DEEP)
		_canvas.draw_texture_rect(_programme.get_texture(), full, false)
		return
	if cutin_player != 0:
		_draw_cutin()
		return
	var full := Rect2(Vector2.ZERO, Vector2(SIZE))
	_canvas.draw_rect(full, Color(0.93, 0.92, 0.89))
	_canvas.draw_rect(full.grow(-12.0), BOARD_DEEP)
	_canvas.draw_rect(full.grow(-22.0), BOARD)
	# Title strip.
	_canvas.draw_string(FONT, Vector2(MARGIN + 14.0, 104.0), "AIQUIZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 78, AMBER)
	_canvas.draw_string(FONT, Vector2(MARGIN + 300.0, 100.0), "SCOREBOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 38, DIM)
	var shown := current + 1 if current >= 0 else _played()
	var right := float(SIZE.x) - MARGIN - 14.0
	_canvas.draw_string(FONT, Vector2(right - 360.0, 100.0), "Q %d / %d" % [shown, COLUMNS],
		HORIZONTAL_ALIGNMENT_RIGHT, 360.0, 56, Color.WHITE)
	_canvas.draw_line(Vector2(MARGIN, HEADER_Y - 10.0), Vector2(float(SIZE.x) - MARGIN, HEADER_Y - 10.0), GRID, 4.0)
	var cw := _column_w()
	# Current question column glow behind the lamps.
	if current >= 0:
		var column := Rect2(_column_x(current) + 4.0, HEADER_Y, cw - 8.0, _row_y(2) - HEADER_Y - ROW_GAP)
		_canvas.draw_rect(column, Color(1.0, 0.85, 0.35, 0.10 if _blink else 0.05))
	# Column headings.
	for index in range(COLUMNS):
		var color := AMBER if index == COLUMNS - 1 else Color(0.85, 0.9, 0.86)
		if index == current:
			color = Color.WHITE if _blink else AMBER.darkened(0.35)
		_text(Vector2(_column_x(index), HEADER_Y + 56.0), cw, str(index + 1), 52, color)
	var total_x := float(SIZE.x) - MARGIN - TOTAL_W
	_text(Vector2(total_x, HEADER_Y + 56.0), TOTAL_W, "R", 56, AMBER)
	var sums := totals()
	for row in range(2):
		var y := _row_y(row)
		var color: Color = P_COLORS[row]
		_canvas.draw_rect(Rect2(MARGIN + 8.0, y + 8.0, LABEL_W - 24.0, ROW_H - 16.0), color.darkened(0.55))
		_canvas.draw_rect(Rect2(MARGIN + 8.0, y + 8.0, 10.0, ROW_H - 16.0), color)
		_text(Vector2(MARGIN + 18.0, y + ROW_H * 0.5 + 24.0), LABEL_W - 34.0, "%dP" % (row + 1), 68, Color.WHITE)
		for index in range(COLUMNS):
			_draw_cell(index, row, Vector2(_column_x(index) + cw * 0.5, y + ROW_H * 0.5), cw)
		_canvas.draw_rect(Rect2(total_x + 10.0, y + 8.0, TOTAL_W - 20.0, ROW_H - 16.0), BOARD_DEEP)
		_text(Vector2(total_x, y + ROW_H * 0.5 + 40.0), TOTAL_W, str(sums[row]), 112, color.lightened(0.15))
	# Grid lines between the question columns and around R.
	for index in range(COLUMNS + 1):
		var x := _column_x(index)
		_canvas.draw_line(Vector2(x, HEADER_Y), Vector2(x, _row_y(2) - ROW_GAP), GRID, 3.0)
	_canvas.draw_line(Vector2(total_x + 4.0, HEADER_Y), Vector2(total_x + 4.0, _row_y(2) - ROW_GAP), GRID, 6.0)
	_canvas.draw_line(Vector2(MARGIN, _row_y(1) - ROW_GAP * 0.5), Vector2(float(SIZE.x) - MARGIN, _row_y(1) - ROW_GAP * 0.5), GRID, 3.0)


func _draw_cell(index: int, row: int, center: Vector2, cw: float) -> void:
	var radius := minf(cw, ROW_H) * 0.34
	var mark := marks[index]
	var won := mark > 0 and (mark & (1 << row)) != 0
	if not won:
		_canvas.draw_arc(center, radius, 0.0, TAU, 40, LAMP_OFF, 12.0, true)
		if mark == 0:
			_canvas.draw_rect(Rect2(center.x - radius * 0.7, center.y - 6.0, radius * 1.4, 12.0), DIM)
		return
	var boost := 1.0
	if _flash_started.has(index):
		boost += 0.8 * clampf(1.0 - (_clock - float(_flash_started[index])) / FLASH_SECONDS, 0.0, 1.0)
	var color: Color = P_COLORS[row]
	var lit := Color(minf(color.r * boost, 1.0), minf(color.g * boost, 1.0), minf(color.b * boost, 1.0))
	for glow in range(3):
		_canvas.draw_arc(center, radius, 0.0, TAU, 40, Color(color, 0.16 - glow * 0.04), 30.0 + glow * 12.0, true)
	_canvas.draw_arc(center, radius, 0.0, TAU, 48, lit, 14.0, true)
	_canvas.draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.45 * (boost - 0.6)), 4.0, true)


func _played() -> int:
	var count := 0
	for mark in marks:
		count += 1 if mark >= 0 else 0
	return count
