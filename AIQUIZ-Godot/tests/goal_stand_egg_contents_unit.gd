extends Node

## Raw egg contents models (no drawing): GoalStandEggSplat timing and volume
## books against a real egg, the yolk wobble, drips and strands, and the body
## proxies that splats ride on (including the finale's P2 mirror).
## Run: Godot --headless --path . --script tests/goal_stand_egg_contents_bootstrap.gd

const STEP := 1.0 / 60.0
const DOWN_WALL := Vector2(0.0, -9.8)

var checks := 0
var failures: Array[String] = []
var model := GoalStandEggRheology.new(5.6)


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func run() -> void:
	check_rheology()
	check_floor_splat()
	check_wall_splat()
	check_yolk()
	check_rupture()
	check_puddle_merge()
	check_drips()
	check_strand()
	await check_body()
	print("GOAL_STAND_EGG_CONTENTS_UNIT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	get_tree().quit(0 if failures.is_empty() else 1)


func impact(extra: Dictionary = {}) -> Dictionary:
	var base := {"normal_speed": 15.0, "tangential": Vector2.ZERO, "reach": 0.34, "yolks": 1, "seed": 7}
	base.merge(extra, true)
	return base


func check_rheology() -> void:
	check(absf(model.yolk_radius - 0.0897) < 0.003, "yolk radius scales to ~9 cm (%.4f)" % model.yolk_radius)
	check(absf(model.white_volume - 3.3e-5 * pow(5.6, 3.0)) < 1e-6, "white volume scales with S^3")
	check(absf(model.capillary_length - 0.0121) < 0.001, "capillary length ~1.2 cm (%.4f)" % model.capillary_length)
	var film := model.film_speed(0.0078, 1.0)
	check(film > 0.3 and film < 1.0, "film on a wall runs 0.3-1 m/s (%.2f)" % film)
	check(model.thick_creep_speed(0.03, 1.0) == 0.0, "a thin dome holds on a wall")
	var creep := model.thick_creep_speed(0.05, 1.0)
	check(creep > 0.04 and creep < 0.16, "a fresh dome creeps 4-16 cm/s (%.3f)" % creep)
	check(is_equal_approx(GoalStandEggRheology.scale_for_length(0.32), 0.32 / 0.057), "scale from the egg's length")


func check_floor_splat() -> void:
	var splat := GoalStandEggSplat.create(model, impact())
	var booked := splat.booked_volume()
	var events: Array[Dictionary] = []
	var peak := 0.0
	var peak_time := 0.0
	var thick_peak := 0.0
	var spray := 0
	var t := 0.0
	while t < 5.0:
		splat.step(1.0 / 240.0 if t < 0.2 else STEP, Vector2.ZERO, events)
		t += 1.0 / 240.0 if t < 0.2 else STEP
		var mean := splat.mean_radius()
		if mean > peak:
			peak = mean
			peak_time = t
		thick_peak = maxf(thick_peak, splat.thick_radius)
	for event: Dictionary in events:
		spray += 1 if event.type == "spray" else 0
	check(absf(splat.booked_volume() - booked) / booked < 0.03, "floor splat keeps its volume (%.5f -> %.5f)" % [booked, splat.booked_volume()])
	check(peak_time >= 0.03 and peak_time <= 0.08, "sheet peaks at 30-80 ms (%.3f s)" % peak_time)
	check(peak >= 0.26 and peak <= 0.42, "sheet spreads ~2.5-3 egg widths (%.3f m)" % peak)
	check(splat.mean_radius() / peak > 0.93, "thin film keeps most of its spread (%.3f)" % (splat.mean_radius() / peak))
	var recoil := 1.0 - splat.thick_radius / thick_peak
	check(recoil > 0.08 and recoil < 0.2, "thick albumen recoils 10-18 %% (%.3f)" % recoil)
	check(splat.thick_center.length() < 0.01, "a square hit on the floor does not drift (%.4f)" % splat.thick_center.length())
	check(spray >= 2, "finger tips shed spray (%d)" % spray)
	var ratio := 1.0
	for index in range(GoalStandEggSplat.RIM):
		var a := splat.rim[index]
		var b := splat.rim[(index + 1) % GoalStandEggSplat.RIM]
		ratio = maxf(ratio, maxf(a, b) / minf(a, b))
	check(ratio < 1.35, "outline stays smooth sample to sample (%.3f)" % ratio)
	check(splat.film > 0.003 and splat.film < 0.015, "film 3-15 mm thick (%.4f)" % splat.film)
	check(not splat.awake, "floor splat goes to sleep")
	var data := PackedFloat32Array()
	data.resize(GoalStandEggSplat.ROW_TEXELS * 4 * 2)
	splat.write_row(data, 1)
	var header := (GoalStandEggSplat.ROW_TEXELS + GoalStandEggSplat.HEADER) * 4
	check(is_equal_approx(data[GoalStandEggSplat.ROW_TEXELS * 4], splat.rim[0]) and is_equal_approx(data[header], splat.film), "row data written at its row")
	# A glancing hit runs further along the throw.
	var glancing := GoalStandEggSplat.create(model, impact({"tangential": Vector2(9.0, 0.0), "seed": 3}))
	for _i in range(60):
		glancing.step(STEP, Vector2.ZERO, events)
	check(glancing.rim_at(0.0) > glancing.rim_at(PI) * 1.3, "glancing hit spreads along the throw (%.3f vs %.3f)" % [glancing.rim_at(0.0), glancing.rim_at(PI)])


func check_wall_splat() -> void:
	# A torso front: 0.76 wide, the white lands 0.2 under the top edge.
	var wall := impact({"wrap": GoalStandEggSplat.Wrap.BOX, "extents": Vector4(-0.38, 0.38, -0.62, 0.2), "depth": 0.44, "seed": 11})
	var splat := GoalStandEggSplat.create(model, wall)
	var booked := splat.booked_volume()
	var events: Array[Dictionary] = []
	var edge_time := -1.0
	var creep_stopped := -1.0
	var t := 0.0
	var last_center := splat.thick_center
	var thick_speed_max := 0.0
	var rivulet_speed_max := 0.0
	var last_length := 0.0
	while t < 6.0:
		splat.step(STEP, DOWN_WALL, events)
		t += STEP
		var creep := (splat.thick_center - last_center).length() / STEP
		last_center = splat.thick_center
		if t > 0.2:
			thick_speed_max = maxf(thick_speed_max, creep)
		if creep < 0.0005 and t > 0.5 and creep_stopped < 0.0:
			creep_stopped = t
		var longest := 0.0
		for rivulet: Dictionary in splat.rivulets:
			longest = maxf(longest, float(rivulet.length))
		rivulet_speed_max = maxf(rivulet_speed_max, (longest - last_length) / STEP)
		last_length = longest
		for event: Dictionary in events:
			if event.type == "edge" and edge_time < 0.0:
				edge_time = t
		events.clear()
	check(splat.rivulets.size() >= 1, "film gathers into rivulets on a wall (%d)" % splat.rivulets.size())
	check(edge_time > 0.15 and edge_time < 2.0, "a rivulet reaches the lower edge in 0.15-2 s (%.2f)" % edge_time)
	check(rivulet_speed_max > thick_speed_max, "thin film runs faster than the thick dome creeps (%.2f vs %.2f)" % [rivulet_speed_max, thick_speed_max])
	check(creep_stopped > 0.0 and creep_stopped < 4.5, "thick creep stops by ~4 s (%.2f)" % creep_stopped)
	check(splat.thick_center.y < -0.01, "the dome crept downhill (%.3f)" % splat.thick_center.y)
	check(absf(splat.booked_volume() - booked) / booked < 0.03, "wall splat books its volume (%.5f -> %.5f)" % [booked, splat.booked_volume()])
	var fold := GoalStandEggSplat.wrap_point(GoalStandEggSplat.Wrap.BOX, Vector4(-0.38, 0.38, -0.62, 0.2), 0.44, Vector2(0.0, 0.3), 0.0)
	check((fold.normal as Vector3).dot(Vector3.BACK) > 0.99 and (fold.position as Vector3).y < -0.05, "sheet past the top edge folds over onto the top face")
	var flat := GoalStandEggSplat.wrap_point(GoalStandEggSplat.Wrap.BOX, Vector4(-0.38, 0.38, -0.62, 0.2), 0.44, Vector2(0.1, -0.1), 0.01)
	check((flat.position as Vector3).is_equal_approx(Vector3(0.1, 0.01, -0.1)), "inside the face the sheet is flat")


func check_yolk() -> void:
	var splat := GoalStandEggSplat.create(model, impact({"seed": 5}))
	var events: Array[Dictionary] = []
	var yolk: Dictionary = splat.yolks[0]
	var crossings := 0
	var last := float(yolk.flatten)
	var settled := -1.0
	var t := 0.0
	while t < 2.0:
		splat.step(STEP, Vector2.ZERO, events)
		t += STEP
		var f := float(yolk.flatten)
		if signf(f) != signf(last) and absf(f) > 0.002:
			crossings += 1
		if absf(f) > 0.002:
			last = f
		if absf(f) < 0.005 and absf(float(yolk.flatten_vel)) < 0.05 and settled < 0.0:
			settled = t
		elif absf(f) >= 0.005:
			settled = -1.0
	check(crossings >= 1 and crossings <= 3, "yolk rebounds with 1-3 overshoots, not like jelly (%d)" % crossings)
	check(settled > 0.0 and settled < 1.0, "yolk settles within a second (%.2f)" % settled)
	var aspect := GoalStandEggRheology.YOLK_REST_ASPECT * pow(1.0 + float(yolk.flatten), 1.5)
	check(aspect > 0.45 and aspect < 0.7, "resting yolk is a dome 0.45-0.7 tall over wide (%.2f)" % aspect)
	# On a wall it leans downhill and, once its weight beats the white's hold, slides out.
	var wall := GoalStandEggSplat.create(model, impact({"wrap": GoalStandEggSplat.Wrap.BOX, "extents": Vector4(-0.38, 0.38, -0.3, 0.2), "depth": 0.44, "seed": 9}))
	var wall_yolk: Dictionary = wall.yolks[0]
	wall_yolk.stick = 6.0
	var released := false
	t = 0.0
	while t < 6.0 and not released:
		wall.step(STEP, DOWN_WALL, events)
		t += STEP
		if t < 0.6:
			check((wall_yolk.sag as Vector2).y <= 0.0001, "yolk sag points downhill")
		for event: Dictionary in events:
			released = released or event.type == "yolk"
		events.clear()
	check(released, "a yolk on a wall slides out of the white and lets go (%.2f s)" % t)
	check(t > 0.3, "the white holds the yolk for a moment before it goes (%.2f s)" % t)
	var clinging := GoalStandEggSplat.create(model, impact({"wrap": GoalStandEggSplat.Wrap.BOX, "extents": Vector4(-0.38, 0.38, -0.3, 0.2), "depth": 0.44, "seed": 9}))
	clinging.yolks[0].stick = 11.0
	for _i in range(240):
		clinging.step(STEP, DOWN_WALL, events)
	check(clinging.yolks.size() == 1, "a yolk that holds harder than its weight stays on the wall")
	events.clear()


func check_rupture() -> void:
	var wall := GoalStandEggSplat.create(model, impact({"wrap": GoalStandEggSplat.Wrap.BOX, "extents": Vector4(-0.38, 0.38, -0.6, 0.2),
		"depth": 0.44, "rupture": true, "seed": 21}))
	var yolk: Dictionary = wall.yolks[0]
	yolk.stick = 100.0
	var booked := wall.booked_yolk()
	var events: Array[Dictionary] = []
	for _i in range(120):
		wall.step(STEP, DOWN_WALL, events)
	var stream := false
	for rivulet: Dictionary in wall.rivulets:
		stream = stream or bool(rivulet.yolk)
	check(stream, "torn yolk runs out as a stream down the wall")
	check(float(yolk.deflate) > 0.3, "torn yolk's sac collapses (%.2f)" % float(yolk.deflate))
	check(absf(wall.booked_yolk() - booked) / booked < 0.01, "torn yolk keeps its volume (sac + stream)")
	var floor_splat := GoalStandEggSplat.create(model, impact({"rupture": true, "seed": 4}))
	for _i in range(90):
		floor_splat.step(STEP, Vector2.ZERO, events)
	check(float(floor_splat.yolks[0].deflate) > 0.9, "on the floor a torn yolk spills flat")


func check_puddle_merge() -> void:
	var drop := 1.2e-5
	var puddle := GoalStandEggSplat.create(model, {"volume": drop, "normal_speed": 3.0, "seed": 2}, GoalStandEggSplat.Kind.PUDDLE)
	var events: Array[Dictionary] = []
	for _i in range(60):
		puddle.step(STEP, Vector2.ZERO, events)
	var before := puddle.mean_radius()
	puddle.absorb(Vector2(0.01, 0.0), {"volume": drop * 3.0, "normal_speed": 3.0})
	for _i in range(60):
		puddle.step(STEP, Vector2.ZERO, events)
	check(puddle.mean_radius() > before * 1.5, "drops landing in a puddle make it grow (%.3f -> %.3f)" % [before, puddle.mean_radius()])
	check(puddle.film <= model.puddle_height() + 0.0001, "a puddle is never thicker than capillary height")


func check_drips() -> void:
	for spec: Array in [[GoalStandEggDrip.Kind.THIN, Vector2(0.12, 0.6)], [GoalStandEggDrip.Kind.THICK, Vector2(0.8, 4.0)]]:
		var kind: int = spec[0]
		var window: Vector2 = spec[1]
		var drip := GoalStandEggDrip.create(model, kind, Vector3(0.0, 1.0, 0.0), 2.0e-4, 1.0e-4, 3)
		var events: Array[Dictionary] = []
		var neck_start := -1.0
		var pinch := -1.0
		var thinning := true
		var last_radius := INF
		var recoiled := false
		var t := 0.0
		while t < 8.0 and pinch < 0.0:
			drip.step(STEP / 2.0, Vector3(0.0, 1.0, 0.0), events)
			t += STEP / 2.0
			if drip.phase == GoalStandEggDrip.Phase.NECK:
				if neck_start < 0.0:
					neck_start = t
				thinning = thinning and drip.thread_radius <= last_radius + 1e-6
				last_radius = drip.thread_radius
			if not events.is_empty():
				pinch = t
				recoiled = drip.phase == GoalStandEggDrip.Phase.RECOIL and drip.stub > 0.0
		var name := "thin" if kind == GoalStandEggDrip.Kind.THIN else "thick"
		check(neck_start > 0.0 and pinch > 0.0, "%s drip necks and pinches off" % name)
		check(thinning, "%s drip's thread only thins" % name)
		var span := pinch - neck_start
		check(span >= window.x and span <= window.y, "%s drip pinches in %.2f-%.2f s (%.2f)" % [name, window.x, window.y, span])
		check(events.size() == 2, "%s drip drops a drop and a satellite (%d)" % [name, events.size()])
		check(recoiled, "%s drip's stub recoils after the snap" % name)
		check(float(events[0].radius) > float(events[1].radius), "%s satellite is smaller than the drop" % name)


func check_strand() -> void:
	var strand := GoalStandEggStrand.create(Vector3.ZERO, Vector3(0.0, 0.0, 0.05), 0.01, 0.5, 0.3)
	strand.step(STEP, Vector3.ZERO, Vector3(0.0, 0.0, 0.2))
	var expected := 0.01 * sqrt(0.05 / 0.2)
	check(absf(strand.radius() - expected) / expected < 0.05, "strand thins as r0 sqrt(L0/L) (%.4f vs %.4f)" % [strand.radius(), expected])
	var pull := strand.step(STEP, Vector3.ZERO, Vector3(0.0, 0.0, 0.3))
	check(pull.z < 0.0, "a stretched strand pulls the shell piece back")
	check(strand.beading() > 0.0 and strand.beading() < 1.0, "strand beads up close to the snap (%.2f)" % strand.beading())
	strand.step(STEP, Vector3.ZERO, Vector3(0.0, 0.0, 0.6))
	check(strand.broken, "strand snaps past its length")
	for _i in range(30):
		strand.step(STEP, Vector3.ZERO, Vector3(0.0, 0.0, 0.9))
	check(strand.is_done(), "a snapped strand recoils away")


func check_body() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var parts := EmoteBlockmanPreview.build_player_skeleton(true, holder, HatData.HAT_NONE)
	await get_tree().process_frame
	var spine := parts.spine as Node3D
	var body := GoalStandEggBody.from_target(spine)
	check(body.shapes.size() >= 10, "blockman parts become boxes (%d)" % body.shapes.size())
	var chest := spine.global_position + Vector3(0.0, 0.2, 0.0)
	var hit := body.raycast(chest + Vector3(0.0, 0.0, 2.0), Vector3.FORWARD)
	check(not hit.is_empty() and String(body.shapes[int(hit.shape)].part) == "chest", "a ray at the chest hits the chest box (%s)" % [hit.get("shape", -1)])
	if hit.is_empty():
		return
	check((hit.normal as Vector3).dot(Vector3.BACK) > 0.99, "chest hit normal faces the thrower")
	var anchor := body.anchor_for(hit)
	var bounds: Vector4 = anchor.extents
	check(bounds.y - bounds.x > 0.7 and bounds.y - bounds.x < 0.8, "face spans the chest's width (%.3f)" % (bounds.y - bounds.x))
	check(maxf(-bounds.z, bounds.w) > 0.0 and bounds.w - bounds.z > 0.8, "lower torso continues the chest face (%.3f tall)" % (bounds.w - bounds.z))
	var frame := body.frame_of(anchor)
	check(frame.basis.determinant() > 0.0 and frame.basis.y.dot(Vector3.BACK) > 0.99, "splat frame is right-handed with +Y out of the chest")
	check(frame.origin.distance_to(hit.point as Vector3) < 0.001, "frame sits on the hit point")
	# The finale mirrors its stage when P2 wins, and the body moves and turns.
	holder.scale = Vector3(-1.0, 1.0, 1.0)
	holder.position = Vector3(0.5, -0.2, 1.0)
	spine.rotation = Vector3(0.3, 0.2, 0.0)
	var part := body.shapes[int(hit.shape)].node as MeshInstance3D
	var expected := part.global_transform * (anchor.local_point as Vector3)
	frame = body.frame_of(anchor)
	check(frame.basis.determinant() > 0.0, "splat frame stays right-handed under the mirror (%.3f)" % frame.basis.determinant())
	check(frame.origin.distance_to(expected) < 0.001, "splat rides the moving, mirrored part")
	var normal := GoalStandEggBody._world_normal(part.global_transform, anchor.local_normal)
	check(frame.basis.y.normalized().dot(normal) > 0.999, "splat normal follows the part's face")
	var near := body.nearest(spine.global_position, Vector3.FORWARD)
	check(not near.is_empty(), "an egg inside the body still finds a surface")
	var capsule := GoalStandEggBody._ray_capsule(Vector3(0.0, 0.5, 2.0), Vector3(0.0, 0.0, -1.0), 1.0, 0.2)
	check(not capsule.is_empty() and absf((capsule.point as Vector3).z - 0.2) < 0.001, "ray meets a capsule's side")
	holder.queue_free()
