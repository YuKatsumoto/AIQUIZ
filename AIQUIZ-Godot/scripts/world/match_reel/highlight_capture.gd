class_name HighlightCapture
extends Node

## Records the match camera at low resolution for the LED programme's highlights
## (played on the goal stand scoreboard).
##
## A small SubViewport shares the match's World3D and re-renders the current camera
## a few times a second (no HUD or overlays). Each shot is read back from the GPU
## asynchronously, so the game never waits for it, into a ring buffer of the last
## PRE_ROLL_MAX seconds. mark() turns the buffered shots plus the seconds after the
## moment into a clip; overlapping moments share one clip and each keeps its own
## second in it (the menu replay slows down and names every one). Clips are
## JPEG-encoded on worker threads and handed to MatchReel through clip_ready.

signal clip_ready(clip: Dictionary)

const QualityRules = preload("res://scripts/core/graphics_quality.gd")

const SIZE := Vector2i(432, 243)
const PRE_ROLL_MAX := 2.5
## A fall into the sea runs on until the shark bites: moments keep extending a clip.
const MAX_CLIP_SECONDS := 8.0
const MIN_FRAMES := 4
const JPEG_QUALITY := 0.75

## MatchReel turns this on while there is something worth recording.
var recording := false
var fps := 0.0

var _viewport: SubViewport
var _camera: Camera3D
var _sink := FrameSink.new()
var _clock := 0.0
var _next_shot := 0.0
var _shot_time := -1.0
var _ring: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _encoding: Array[Dictionary] = []
var _follow: Camera3D
var _follow_until := -1.0


## Receives GPU readbacks. A RefCounted target, so a readback that lands after the
## match scene is gone does not call into a freed node.
class FrameSink extends RefCounted:
	var _mutex := Mutex.new()
	var _frames: Array[Dictionary] = []
	var _in_flight := 0

	func expect() -> void:
		_mutex.lock()
		_in_flight += 1
		_mutex.unlock()

	func receive(data: PackedByteArray, time: float, size: Vector2i) -> void:
		var image: Image = null
		if data.size() == size.x * size.y * 4:
			image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data)
		_mutex.lock()
		_in_flight -= 1
		if image != null:
			_frames.append({"t": time, "image": image})
		_mutex.unlock()

	func take() -> Array[Dictionary]:
		_mutex.lock()
		var frames := _frames
		_frames = []
		_mutex.unlock()
		return frames

	func in_flight() -> int:
		_mutex.lock()
		var count := _in_flight
		_mutex.unlock()
		return count


static func frames_per_second(quality: String) -> float:
	if QualityRules.is_mobile_target():
		return 0.0
	match QualityRules.normalize(quality):
		QualityRules.LOW:
			return 8.0
		QualityRules.BALANCED:
			return 12.0
	return 15.0


## Call once the node is in the match's scene tree.
func configure(quality: String) -> void:
	name = "HighlightCapture"
	fps = frames_per_second(quality)
	if fps <= 0.0:
		return
	_viewport = SubViewport.new()
	_viewport.name = "CaptureViewport"
	_viewport.size = SIZE
	_viewport.world_3d = get_viewport().world_3d
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	_viewport.use_debanding = false
	_viewport.positional_shadow_atlas_size = 0
	_viewport.mesh_lod_threshold = 4.0
	_viewport.audio_listener_enable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.name = "CaptureCamera"
	_viewport.add_child(_camera)
	_camera.current = true


func is_enabled() -> bool:
	return _viewport != null


## A clip is still collecting shots.
func has_pending() -> bool:
	return not _pending.is_empty()


## Shots or JPEGs still on their way.
func is_busy() -> bool:
	return not _pending.is_empty() or not _encoding.is_empty() or _sink.in_flight() > 0


func clock() -> float:
	return _clock


## Shoots `camera` instead of the match camera for the next `seconds` while its view
## is on screen (the death wipe showing a fallen player in 2P). 0 seconds ends it.
func follow(camera: Camera3D, seconds: float) -> void:
	_follow = camera
	_follow_until = _clock + seconds


func _source_camera() -> Camera3D:
	if is_instance_valid(_follow) and _clock < _follow_until:
		var holder := _follow.get_viewport().get_parent() as CanvasItem
		if holder == null or holder.is_visible_in_tree():
			return _follow
	return get_viewport().get_camera_3d()


## Marks a moment: {kind, player, priority, ...}. pre / post: seconds of the clip
## before and after now. A moment inside a clip still collecting joins it (and may
## extend it); the same kind for both players at once becomes one moment (player 0).
func mark(moment: Dictionary, pre: float, post: float) -> void:
	if not is_enabled():
		return
	var start := _clock - minf(pre, PRE_ROLL_MAX)
	var end := _clock + post
	var event := moment.duplicate()
	event["at"] = _clock
	for clip: Dictionary in _pending:
		if start > float(clip.end) or end < float(clip.start):
			continue
		var joined := false
		for held: Dictionary in clip.events:
			if held.get("kind") == event.get("kind") and absf(float(held.at) - _clock) < 0.3:
				held["player"] = 0 if int(held.get("player", 0)) != int(event.get("player", 0)) else held.get("player", 0)
				joined = true
		if not joined:
			(clip.events as Array).append(event)
		clip.end = minf(maxf(float(clip.end), end), float(clip.start) + MAX_CLIP_SECONDS)
		return
	var frames: Array[Dictionary] = []
	for frame: Dictionary in _ring:
		if float(frame.t) >= start:
			frames.append(frame)
	_pending.append({"events": [event], "start": start, "end": end, "frames": frames})


func _process(delta: float) -> void:
	if not is_enabled():
		return
	for frame: Dictionary in _sink.take():
		_push_frame(frame)
	_poll_encoding()
	if not recording:
		return
	_clock += delta
	if _shot_time >= 0.0:
		_read_back(_shot_time)
		_shot_time = -1.0
	if _clock >= _next_shot:
		_shoot()
		_next_shot = maxf(_next_shot + 1.0 / fps, _clock + 0.5 / fps)
	for clip: Dictionary in _pending.duplicate():
		if _clock >= float(clip.end) + 1.0 / fps and _sink.in_flight() == 0:
			_pending.erase(clip)
			_encode(clip)


func _shoot() -> void:
	var source := _source_camera()
	if source == null:
		return
	_camera.global_transform = source.global_transform
	_camera.projection = source.projection
	_camera.keep_aspect = source.keep_aspect
	_camera.fov = source.fov
	_camera.size = source.size
	_camera.near = source.near
	_camera.far = source.far
	_camera.h_offset = source.h_offset
	_camera.v_offset = source.v_offset
	_camera.frustum_offset = source.frustum_offset
	_camera.cull_mask = source.cull_mask
	_camera.environment = source.environment
	_camera.attributes = source.attributes
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_shot_time = _clock


## The shot rendered last frame. The main RenderingDevice copies it out once the GPU
## is done with it; without one (Compatibility renderer) the small copy is direct.
func _read_back(time: float) -> void:
	var texture := _viewport.get_texture()
	var device := RenderingServer.get_rendering_device()
	if device != null:
		var rid := RenderingServer.texture_get_rd_texture(texture.get_rid())
		if rid.is_valid():
			var format := device.texture_get_format(rid)
			if format.format in [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB]:
				_sink.expect()
				var size := Vector2i(format.width, format.height)
				if device.texture_get_data_async(rid, 0, _sink.receive.bind(time, size)) == OK:
					return
				_sink.receive(PackedByteArray(), time, size)
	var image := texture.get_image()
	if image != null:
		image.convert(Image.FORMAT_RGBA8)
		_push_frame({"t": time, "image": image})


func _push_frame(frame: Dictionary) -> void:
	var t := float(frame.t)
	_ring.append(frame)
	while not _ring.is_empty() and float(_ring[0].t) < _clock - PRE_ROLL_MAX - 0.25:
		_ring.pop_front()
	for clip: Dictionary in _pending:
		if t >= float(clip.start) and t <= float(clip.end):
			(clip.frames as Array).append(frame)


func _encode(clip: Dictionary) -> void:
	var frames: Array = clip.frames
	if frames.size() < MIN_FRAMES:
		return
	var images: Array[Image] = []
	var times: Array[float] = []
	var start := float((frames[0] as Dictionary).t)
	for frame: Dictionary in frames:
		images.append(frame.image)
		times.append(snappedf(float(frame.t) - start, 0.001))
	var events: Array[Dictionary] = []
	var priority := 0
	for held: Dictionary in clip.events:
		var event := held.duplicate()
		event["t"] = snappedf(float(held.at) - start, 0.001)
		event.erase("at")
		priority = maxi(priority, int(event.get("priority", 0)))
		event.erase("priority")
		events.append(event)
	var holder: Array[PackedByteArray] = []
	var task := WorkerThreadPool.add_task(HighlightCapture._encode_task.bind(images, holder), false, "Highlight JPEG")
	_encoding.append({"task": task, "holder": holder, "clip": {
		"events": events, "priority": priority, "at": snappedf(start, 0.001), "times": times,
		"size": [SIZE.x, SIZE.y],
	}})


static func _encode_task(images: Array[Image], holder: Array[PackedByteArray]) -> void:
	for image: Image in images:
		holder.append(image.save_jpg_to_buffer(JPEG_QUALITY))


func _poll_encoding(wait: bool = false) -> void:
	for job: Dictionary in _encoding.duplicate():
		if not wait and not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_encoding.erase(job)
		var clip: Dictionary = job.clip
		clip["jpegs"] = job.holder
		clip_ready.emit(clip)


## Worker tasks must be waited for; a clip still encoding when the match scene
## closes unrecorded is dropped.
func _exit_tree() -> void:
	for job: Dictionary in _encoding:
		WorkerThreadPool.wait_for_task_completion(job.task)
	_encoding.clear()


## Closes every clip with the shots it has and waits for the JPEGs (the match
## scene is closing). clip_ready fires for each before this returns.
func finish_now() -> void:
	if not is_enabled():
		return
	for frame: Dictionary in _sink.take():
		_push_frame(frame)
	for clip: Dictionary in _pending:
		_encode(clip)
	_pending.clear()
	_poll_encoding(true)
