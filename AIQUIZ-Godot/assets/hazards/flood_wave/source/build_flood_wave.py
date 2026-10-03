"""Flash-flood front for the 2P sudden death (docs/sudden_death_underground.md 6.6), built in the LIVE Blender.

Run through jobs.py (never `blender --background`, AGENTS.md):

    ns = {"__name__": "flood_jobs"}
    exec(open("C:/AIQUIZ/AIQUIZ-Godot/assets/hazards/flood_wave/source/jobs.py", encoding="utf-8").read(), ns)
    ns["start"]("all", [("build_flood_wave.py", "build_front", ()), ("build_flood_wave.py", "bake_textures", ()),
        ("build_flood_wave.py", "export_front", ()), ("build_flood_wave.py", "render_preview", ()), ("jobs.py", "save", ())])

The front is a turbulent bore across the whole hall (x = -45..45 m; dense in the 24 m corridor), animated on a
fixed grid so it can be baked to a vertex animation texture (VAT): a fluid simulation changes topology every
frame and does not loop. Each column runs the same 2.0 s roller cycle (the lip throws forward, plunges and is
swallowed by the next one) with its own phase, a smooth function of x, so the crest breaks unevenly across the
hall (the "three phase-shifted thirds" of the spec, without seams); travelling turbulence on top loops exactly
in the 2 s.

Godot coordinates are used for everything written to the VAT (x across, y up, z = direction of travel, toe of
the front at z = 0 on the floor); the GLB is exported from Blender's Z-up (Godot +Z = Blender -Y).

Outputs (assets/hazards/flood_wave/):
  flood_front.glb                    grid mesh, UV0 = metres / 4, UV1 = VAT address
  textures/flood_front_vat_pos.exr   RGBA half: position (Godot, metres) + foam, FRAMES blocks of VAT_ROWS rows
  textures/flood_front_vat_nrm.png   RGBA8: normal * 0.5 + 0.5
  textures/flood_foam.png            tileable 1024: R fine lace, G coarse patches, B streaks
  textures/flood_water_normal.png    tileable 1024 OpenGL normal map of churned water
  textures/flood_spray.png           4 x 4 atlas of spray / droplet / mist sprites (white, alpha)
  flood_wave_layout.json             everything the Godot side needs
"""
import json
import math
import os

import bmesh
import bpy
import numpy as np

ROOT = "C:/AIQUIZ/AIQUIZ-Godot/assets/hazards/flood_wave/"
TEX = ROOT + "textures/"
PREVIEWS = ROOT + "source/previews/"

HALL_HALF = 45.0
CORRIDOR_HALF = 12.0
CORRIDOR_STEP = 0.25
AISLE_STEP = 0.5
NV = 72
FRAMES = 48
LOOP = 2.0
FPS = 24
VAT_WIDTH = 4096
CREST = 3.4
WATER_DEPTH = 1.2
BACK_Z = -9.0
SEED = 20261002


# ---------------------------------------------------------------------------------------------- geometry

def _columns():
	xs = list(np.arange(-CORRIDOR_HALF, CORRIDOR_HALF + 1e-6, CORRIDOR_STEP))
	right = list(np.arange(CORRIDOR_HALF + AISLE_STEP, HALL_HALF + 1e-6, AISLE_STEP))
	return np.array([-x for x in reversed(right)] + xs + right, dtype=np.float64)


def _phase_offset(x):
	"""Per-column phase of the roller cycle (0..1 offsets, smooth in x)."""
	return (0.31 * np.sin(x * (2.0 * math.pi / 17.0) + 0.7) + 0.19 * np.sin(x * (2.0 * math.pi / 7.3) + 1.9)
		+ 0.08 * np.sin(x * (2.0 * math.pi / 3.1) + 4.1))


def _bump(phi, centre, width):
	"""Smooth periodic bump in phase (exactly periodic: built from cos)."""
	d = np.cos(2.0 * math.pi * (phi - centre))
	return np.clip((d - math.cos(math.pi * width)) / (1.0 - math.cos(math.pi * width)), 0.0, 1.0) ** 1.5


def _control_points(phi):
	"""Spine of the bore (z forward, y up) for each column phase; arrays (C, P, 2)."""
	hc = CREST * (0.93 + 0.07 * np.sin(2.0 * math.pi * phi))
	throw = _bump(phi, 0.42, 0.55)          # the lip reaches forward
	plunge = _bump(phi, 0.72, 0.42)         # and falls onto the face
	lip_z = -0.45 + 1.35 * throw + 0.35 * plunge
	lip_y = hc * 0.9 - 1.5 * plunge + 0.15 * throw
	pts = [
		(np.full_like(phi, BACK_Z), np.full_like(phi, WATER_DEPTH)),
		(np.full_like(phi, -6.2), np.full_like(phi, WATER_DEPTH + 0.08)),
		(np.full_like(phi, -4.0), WATER_DEPTH + 0.55 + 0.1 * plunge),
		(np.full_like(phi, -2.5), hc * 0.82),
		(-1.25 + 0.2 * throw, hc),
		(lip_z, lip_y),
		(lip_z - 0.55, lip_y - 0.65 - 0.3 * throw),
		(-0.2 + 0.15 * plunge, 1.55 - 0.25 * plunge),
		(0.35 + 0.25 * plunge, 0.6),
		(0.95 + 0.2 * plunge, 0.14),
		(1.7 + 0.3 * plunge, np.zeros_like(phi)),
	]
	return np.stack([np.stack(np.broadcast_arrays(z + 0.0 * phi, y + 0.0 * phi), axis=-1) for z, y in pts], axis=1)


def _catmull(points, samples_per_span=24):
	"""Centripetal-ish Catmull-Rom through (C, P, 2) control points -> (C, S, 2) dense curve."""
	c, p, _ = points.shape
	ext = np.concatenate([2 * points[:, :1] - points[:, 1:2], points, 2 * points[:, -1:] - points[:, -2:-1]], axis=1)
	out = []
	for i in range(p - 1):
		p0, p1, p2, p3 = ext[:, i], ext[:, i + 1], ext[:, i + 2], ext[:, i + 3]
		for s in range(samples_per_span):
			t = s / samples_per_span
			t2, t3 = t * t, t * t * t
			out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
	out.append(points[:, -1])
	return np.stack(out, axis=1)


def _resample(curve, count):
	"""Even arc-length resampling of (C, S, 2) curves to (C, count, 2) and the arc length (C, count)."""
	seg = np.linalg.norm(np.diff(curve, axis=1), axis=-1)
	acc = np.concatenate([np.zeros((curve.shape[0], 1)), np.cumsum(seg, axis=1)], axis=1)
	out = np.zeros((curve.shape[0], count, 2))
	arcs = np.zeros((curve.shape[0], count))
	for c in range(curve.shape[0]):
		targets = np.linspace(0.0, acc[c, -1], count)
		out[c, :, 0] = np.interp(targets, acc[c], curve[c, :, 0])
		out[c, :, 1] = np.interp(targets, acc[c], curve[c, :, 1])
		arcs[c] = targets
	return out, arcs


def _turbulence_waves():
	rng = np.random.default_rng(SEED)
	waves = []
	for i in range(22):
		fine = i >= 14
		waves.append({
			"kx": rng.uniform(0.6, 3.2) * rng.choice([-1, 1]) * (2.2 if fine else 1.0),
			"ks": rng.uniform(0.8, 4.5) * (1.8 if fine else 1.0),
			"m": int(rng.choice([1, 1, 2, 2, 3, -1])),
			"ph": rng.uniform(0.0, 2.0 * math.pi),
			"a": rng.uniform(0.4, 1.0) * (0.45 if fine else 1.0),
		})
	total = sum(w["a"] for w in waves)
	for w in waves:
		w["a"] /= total
	return waves


def frame_positions(time_s, xs):
	"""Positions (C, V, 3) in Godot coordinates and foam (C, V) at time_s."""
	phi = np.mod(time_s / LOOP + _phase_offset(xs), 1.0)
	spine = _catmull(_control_points(phi))
	prof, arc = _resample(spine, NV)
	tang = np.gradient(prof, axis=1)
	tang /= np.maximum(np.linalg.norm(tang, axis=-1, keepdims=True), 1e-6)
	normal = np.stack([-tang[..., 1], tang[..., 0]], axis=-1)   # (z, y): outward from the water
	v = np.linspace(0.0, 1.0, NV)[None, :]
	# Turbulence: none at the back edge (it meets the flat water), strongest on the lip and the face.
	weight = (np.clip((v - 0.05) / 0.25, 0.0, 1.0) * (0.07 + 0.42 * np.clip((v - 0.4) / 0.2, 0.0, 1.0)))
	weight *= 1.0 - np.clip((v - 0.93) / 0.07, 0.0, 1.0) * 0.8
	turb = np.zeros_like(arc)
	sway = np.zeros_like(arc)
	tt = 2.0 * math.pi * time_s / LOOP
	for w in _turbulence_waves():
		ang = w["kx"] * xs[:, None] + w["ks"] * arc + w["m"] * tt + w["ph"]
		turb += w["a"] * np.sin(ang)
		sway += w["a"] * np.cos(ang * 0.7 + 1.3)
	disp = turb * weight
	z = prof[..., 0] + normal[..., 0] * disp
	y = prof[..., 1] + normal[..., 1] * disp
	x = np.repeat(xs[:, None], NV, axis=1) + sway * weight * 0.35
	# Keep the leading sheet on the floor and the back edge on the water line.
	y = np.maximum(y, 0.0)
	y[:, 0] = WATER_DEPTH
	z[:, 0] = BACK_Z
	pos = np.stack([x, y, z], axis=-1)
	# Foam (0..1): whitewater on the breaking lip, foam falling down the upper face, streaky churn lower down,
	# a foam apron at the toe, a few streaks on the back slope. The rest is dark, turbulent water.
	churn = np.clip(0.5 + 0.9 * turb, 0.0, 1.0)
	def band(a, b):
		return np.clip((v - a) / 0.03, 0.0, 1.0) * (1.0 - np.clip((v - (b - 0.03)) / 0.03, 0.0, 1.0))
	foam = (band(0.08, 0.42) * (0.04 + 0.22 * churn) + band(0.40, 0.62) * (0.62 + 0.38 * churn)
		+ band(0.60, 0.76) * (0.35 + 0.5 * churn) + band(0.74, 0.93) * (0.06 + 0.38 * churn)
		+ band(0.91, 1.01) * (0.5 + 0.4 * churn))
	foam = np.clip(foam, 0.0, 1.0)
	foam[:, 0] = 0.0
	return pos, foam


def _normals(pos):
	"""Per-vertex normals (C, V, 3) of the grid (Godot coordinates)."""
	d_prof = np.gradient(pos, axis=1)
	d_x = np.gradient(pos, axis=0)
	n = np.cross(d_prof, d_x)
	n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
	return n


def _to_blender(p):
	"""Godot (x, y, z) -> Blender (x, -z, y)."""
	return np.stack([p[..., 0], -p[..., 2], p[..., 1]], axis=-1)


def _save_float_image(name, width, height, pixels, path):
	img = bpy.data.images.get(name)
	if img is not None:
		bpy.data.images.remove(img)
	img = bpy.data.images.new(name, width=width, height=height, alpha=True, float_buffer=True)
	img.colorspace_settings.name = "Non-Color"
	img.pixels.foreach_set(pixels.astype(np.float32).ravel())
	scene = bpy.context.scene
	settings = scene.render.image_settings
	saved = (settings.file_format, settings.color_depth, settings.color_mode, getattr(settings, "exr_codec", None))
	settings.file_format = "OPEN_EXR"
	settings.color_mode = "RGBA"
	settings.color_depth = "16"
	settings.exr_codec = "ZIP"
	img.save_render(path, scene=scene)
	settings.file_format, settings.color_depth, settings.color_mode = saved[0], saved[1], saved[2]
	if saved[3] is not None:
		settings.exr_codec = saved[3]
	return img


def _save_byte_image(name, width, height, pixels, path):
	"""pixels: (H, W, 4) floats 0..1, row 0 = TOP (flipped for Blender's bottom-up storage)."""
	img = bpy.data.images.get(name)
	if img is not None:
		bpy.data.images.remove(img)
	img = bpy.data.images.new(name, width=width, height=height, alpha=True)
	img.colorspace_settings.name = "Non-Color"
	img.pixels.foreach_set(np.ascontiguousarray(pixels[::-1]).astype(np.float32).ravel())
	img.filepath_raw = path
	img.file_format = "PNG"
	img.save()
	return img


def build_front():
	xs = _columns()
	cols = xs.shape[0]
	count = cols * NV
	rows_per_frame = int(math.ceil(count / VAT_WIDTH))
	frames = []
	foams = []
	normals = []
	for f in range(FRAMES):
		pos, foam = frame_positions(f * LOOP / FRAMES, xs)
		frames.append(pos)
		foams.append(foam)
		normals.append(_normals(pos))
	# Vertex index = column * NV + row (row along the profile).
	vat_pos = np.zeros((FRAMES * rows_per_frame, VAT_WIDTH, 4), dtype=np.float32)
	vat_nrm = np.zeros((FRAMES * rows_per_frame, VAT_WIDTH, 4), dtype=np.float32)
	idx = np.arange(count)
	px, py = idx % VAT_WIDTH, idx // VAT_WIDTH
	for f in range(FRAMES):
		p = frames[f].reshape(count, 3)
		n = normals[f].reshape(count, 3)
		vat_pos[f * rows_per_frame + py, px, :3] = p
		vat_pos[f * rows_per_frame + py, px, 3] = foams[f].reshape(count)
		vat_nrm[f * rows_per_frame + py, px, :3] = n * 0.5 + 0.5
		vat_nrm[f * rows_per_frame + py, px, 3] = 1.0
	height = FRAMES * rows_per_frame
	# Blender stores images bottom-up: image row r = pixel row r from the bottom. Godot's texelFetch(y) reads
	# from the top, so flip: the address written to UV1 counts from the top.
	_save_float_image("FLW_VAT_Pos", VAT_WIDTH, height, vat_pos[::-1], TEX + "flood_front_vat_pos.exr")
	_save_byte_image("FLW_VAT_Nrm", VAT_WIDTH, height, vat_nrm, TEX + "flood_front_vat_nrm.png")

	# --- the mesh (rest = frame 0), with shape keys so the loop plays in the viewport
	mesh_name = "FLW_Front"
	obj = bpy.data.objects.get(mesh_name)
	if obj is not None:
		bpy.data.objects.remove(obj, do_unlink=True)
	old = bpy.data.meshes.get(mesh_name)
	if old is not None:
		bpy.data.meshes.remove(old)
	rest = _to_blender(frames[0].reshape(count, 3))
	faces = []
	for c in range(cols - 1):
		for r in range(NV - 1):
			a = c * NV + r
			faces.append((a, a + 1, a + NV + 1, a + NV))
	mesh = bpy.data.meshes.new(mesh_name)
	mesh.from_pydata(rest.tolist(), [], faces)
	mesh.update()
	uv0 = mesh.uv_layers.new(name="UVMap")
	uv1 = mesh.uv_layers.new(name="VAT")
	_, arc0 = _resample(_catmull(_control_points(np.mod(_phase_offset(xs), 1.0))), NV)
	loop_vert = np.zeros(len(mesh.loops), dtype=np.int64)
	mesh.loops.foreach_get("vertex_index", loop_vert)
	col_of = loop_vert // NV
	row_of = loop_vert % NV
	uv_a = np.stack([xs[col_of] / 4.0, arc0[col_of, row_of] / 4.0], axis=-1)
	uv_b = np.stack([(loop_vert % VAT_WIDTH + 0.5) / VAT_WIDTH, (loop_vert // VAT_WIDTH + 0.5) / 8.0], axis=-1)
	uv0.data.foreach_set("uv", uv_a.astype(np.float32).ravel())
	uv1.data.foreach_set("uv", uv_b.astype(np.float32).ravel())
	for poly in mesh.polygons:
		poly.use_smooth = True
	obj = bpy.data.objects.new(mesh_name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	obj.shape_key_add(name="Basis", from_mix=False)
	for f in range(FRAMES):
		key = obj.shape_key_add(name="F%02d" % f, from_mix=False)
		key.data.foreach_set("co", _to_blender(frames[f].reshape(count, 3)).astype(np.float32).ravel())
	# Viewport playback: one key at a time, constant interpolation, frames 1..FRAMES loop.
	keys = obj.data.shape_keys
	for f in range(FRAMES):
		kb = keys.key_blocks["F%02d" % f]
		for frame in range(1, FRAMES + 2):
			kb.value = 1.0 if frame == f + 1 or (frame == FRAMES + 1 and f == 0) else 0.0
			kb.keyframe_insert("value", frame=frame)
	if keys.animation_data and keys.animation_data.action:
		for fc in _fcurves(keys.animation_data.action):
			for kp in fc.keyframe_points:
				kp.interpolation = "CONSTANT"
	scene = bpy.context.scene
	scene.render.fps = FPS
	scene.frame_start = 1
	scene.frame_end = FRAMES
	_preview_material(obj)
	bounds_min = np.min([fr.reshape(count, 3).min(axis=0) for fr in frames], axis=0)
	bounds_max = np.max([fr.reshape(count, 3).max(axis=0) for fr in frames], axis=0)
	layout = {
		"units": "Godot metres, y up, z = direction of travel; toe of the front at z = 0 on the floor",
		"columns": int(cols), "rows": NV, "vertices": int(count), "triangles": int((cols - 1) * (NV - 1) * 2),
		"frames": FRAMES, "loop_seconds": LOOP, "vat_width": VAT_WIDTH, "vat_rows_per_frame": rows_per_frame,
		"vat_height": height, "uv1": "x = (index % vat_width + 0.5) / vat_width, y = (index // vat_width + 0.5) / 8",
		"vat_pos": "RGBA half: position xyz (metres), a = foam 0..1; frame f occupies rows f * rows_per_frame .. from the top",
		"vat_nrm": "RGBA8: normal * 0.5 + 0.5",
		"crest_height": CREST, "water_depth": WATER_DEPTH, "back_z": BACK_Z,
		"half_width": HALL_HALF, "corridor_half_width": CORRIDOR_HALF,
		"bounds_min": [round(float(v), 3) for v in bounds_min], "bounds_max": [round(float(v), 3) for v in bounds_max],
	}
	with open(ROOT + "flood_wave_layout.json", "w", encoding="utf-8") as fh:
		json.dump(layout, fh, indent=1)
	return layout


def _fcurves(action):
	"""Blender 4.4+ layered actions keep F-curves in channelbags."""
	if hasattr(action, "fcurves") and len(action.fcurves) > 0:
		return list(action.fcurves)
	out = []
	for layer in getattr(action, "layers", []):
		for strip in layer.strips:
			for bag in getattr(strip, "channelbags", []):
				out.extend(bag.fcurves)
	return out


def _preview_material(obj):
	"""Viewport/review look only (Godot builds its own shader): murky water, foam by height."""
	mat = bpy.data.materials.get("FLW_Water") or bpy.data.materials.new("FLW_Water")
	mat.use_nodes = True
	nt = mat.node_tree
	for node in list(nt.nodes):
		nt.nodes.remove(node)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	geo = nt.nodes.new("ShaderNodeNewGeometry")
	sep = nt.nodes.new("ShaderNodeSeparateXYZ")
	ramp = nt.nodes.new("ShaderNodeValToRGB")
	ramp.color_ramp.elements[0].position = 0.45
	ramp.color_ramp.elements[0].color = (0.035, 0.05, 0.045, 1.0)
	ramp.color_ramp.elements[1].position = 0.85
	ramp.color_ramp.elements[1].color = (0.85, 0.88, 0.86, 1.0)
	mr = nt.nodes.new("ShaderNodeMapRange")
	mr.inputs["From Min"].default_value = 0.8
	mr.inputs["From Max"].default_value = 3.6
	nt.links.new(geo.outputs["Position"], sep.inputs[0])
	nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
	nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
	nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.12
	nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
	obj.data.materials.clear()
	obj.data.materials.append(mat)


# ---------------------------------------------------------------------------------------------- textures

def _spectral_noise(n, beta, seed, low_cut=1.0):
	"""Tileable 1/f^beta noise in 0..1 (FFT synthesis is periodic by construction)."""
	rng = np.random.default_rng(seed)
	white = rng.standard_normal((n, n))
	f = np.fft.fftfreq(n) * n
	fx, fy = np.meshgrid(f, f)
	r = np.sqrt(fx * fx + fy * fy)
	r[0, 0] = 1.0
	amp = 1.0 / np.power(np.maximum(r, low_cut), beta)
	amp[0, 0] = 0.0
	field = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
	field -= field.min()
	return field / max(field.max(), 1e-9)


def _worley(n, cells, seed):
	"""Tileable Worley F1 and F2 (distances in cell units)."""
	rng = np.random.default_rng(seed)
	pts = rng.random((cells, cells, 2))
	coords = (np.arange(n) + 0.5) / n * cells
	gx, gy = np.meshgrid(coords, coords)
	cx, cy = np.floor(gx).astype(int), np.floor(gy).astype(int)
	f1 = np.full((n, n), 9.0)
	f2 = np.full((n, n), 9.0)
	for dy in (-1, 0, 1):
		for dx in (-1, 0, 1):
			nx_, ny_ = cx + dx, cy + dy
			p = pts[ny_ % cells, nx_ % cells]
			d = np.sqrt((nx_ + p[..., 0] - gx) ** 2 + (ny_ + p[..., 1] - gy) ** 2)
			f2 = np.where(d < f1, f1, np.minimum(f2, d))
			f1 = np.minimum(f1, d)
	return f1, f2


def _smooth(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def bake_textures():
	n = 1024
	# Foam: lace of bubble walls at two scales, coarse patches, streaks along the flow (v).
	f1a, f2a = _worley(n, 24, SEED + 1)
	f1b, f2b = _worley(n, 64, SEED + 2)
	lace = np.clip(1.0 - _smooth(0.0, 0.16, f2a - f1a), 0.0, 1.0) * 0.6 + np.clip(1.0 - _smooth(0.0, 0.2, f2b - f1b), 0.0, 1.0) * 0.55
	patches = _spectral_noise(n, 1.6, SEED + 3, low_cut=2.0)
	streak_src = _spectral_noise(n, 1.4, SEED + 4, low_cut=1.0)
	# Streaks: stretch the noise along v by averaging rows (periodic roll).
	streaks = np.zeros_like(streak_src)
	for k in range(-24, 25, 3):
		streaks += np.roll(streak_src, k, axis=0)
	streaks = (streaks - streaks.min()) / max(np.ptp(streaks), 1e-9)
	foam = np.stack([np.clip(lace * (0.55 + 0.6 * patches), 0, 1), patches, streaks, np.ones_like(patches)], axis=-1)
	_save_byte_image("FLW_Foam", n, n, foam, TEX + "flood_foam.png")
	# Churned water normal map (OpenGL +Y), from a height field of two noise bands.
	height = _spectral_noise(n, 2.1, SEED + 5, low_cut=3.0) * 0.7 + _spectral_noise(n, 1.4, SEED + 6, low_cut=12.0) * 0.3
	dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * n * 0.012
	dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * n * 0.012
	nrm = np.stack([-dx, dy, np.ones_like(dx)], axis=-1)
	nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
	_save_byte_image("FLW_WaterNormal", n, n, np.concatenate([nrm * 0.5 + 0.5, np.ones((n, n, 1))], axis=-1), TEX + "flood_water_normal.png")
	# Spray atlas: 16 sprites (rows: mist puffs, dense spray, droplet clusters, streaks), white with alpha.
	cell = 256
	atlas = np.zeros((cell * 4, cell * 4, 4))
	yy, xx = np.meshgrid((np.arange(cell) + 0.5) / cell * 2 - 1, (np.arange(cell) + 0.5) / cell * 2 - 1, indexing="ij")
	rng = np.random.default_rng(SEED + 7)
	for i in range(16):
		row, col = divmod(i, 4)
		noise = _spectral_noise(cell, 1.5, SEED + 20 + i, low_cut=2.0)
		r = np.sqrt(xx * xx + yy * yy)
		fine_noise = _spectral_noise(cell, 1.1, SEED + 60 + i, low_cut=6.0)
		if row == 0:          # mist: soft, uneven veils
			alpha = (_smooth(1.0, 0.0, r) ** 2) * np.clip((noise - 0.25) * 1.6, 0, 1) ** 1.5 * 0.7
		elif row == 1:        # spume: ragged wisps torn into strands, holes through them
			wisp = np.clip((noise * 0.7 + fine_noise * 0.5 - 0.55) * 3.0, 0, 1)
			alpha = wisp * _smooth(1.0, 0.2, r + 0.3 * (noise - 0.5)) * 0.85
		elif row == 2:        # droplet clusters
			alpha = np.zeros_like(r)
			for _ in range(70):
				cx_, cy_ = rng.normal(0, 0.38, 2)
				rad = rng.uniform(0.012, 0.05)
				alpha = np.maximum(alpha, _smooth(rad, rad * 0.35, np.sqrt((xx - cx_) ** 2 + (yy - cy_) ** 2)))
			alpha *= _smooth(1.0, 0.6, r)
		else:                 # streaks (droplets in motion, stretched along y)
			alpha = np.zeros_like(r)
			for _ in range(26):
				cx_ = rng.normal(0, 0.3)
				cy_ = rng.uniform(-0.6, 0.6)
				w = rng.uniform(0.008, 0.02)
				length = rng.uniform(0.12, 0.35)
				d = np.sqrt(((xx - cx_) / w) ** 2 + ((yy - cy_) / length) ** 2)
				alpha = np.maximum(alpha, _smooth(1.0, 0.3, d))
			alpha *= _smooth(1.0, 0.7, r)
		tile = np.stack([np.ones_like(alpha), np.ones_like(alpha), np.ones_like(alpha), np.clip(alpha, 0, 1)], axis=-1)
		atlas[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = tile
	_save_byte_image("FLW_Spray", cell * 4, cell * 4, atlas, TEX + "flood_spray.png")
	return {"foam": TEX + "flood_foam.png", "normal": TEX + "flood_water_normal.png", "spray": TEX + "flood_spray.png"}


# ---------------------------------------------------------------------------------------------- export / review

def export_front():
	obj = bpy.data.objects["FLW_Front"]
	for o in bpy.context.scene.objects:
		o.select_set(False)
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.context.scene.frame_set(1)
	bpy.ops.export_scene.gltf(filepath=ROOT + "flood_front.glb", export_format="GLB", use_selection=True,
		export_yup=True, export_apply=False, export_texcoords=True, export_normals=True, export_morph=False,
		export_animations=False, export_materials="PLACEHOLDER", export_extras=False)
	return {"glb": ROOT + "flood_front.glb", "bytes": os.path.getsize(ROOT + "flood_front.glb")}


def render_preview():
	"""A review still of the front (frame 12) for source/previews."""
	os.makedirs(PREVIEWS, exist_ok=True)
	scene = bpy.context.scene
	cam = bpy.data.objects.get("FLW_ReviewCam")
	if cam is None:
		cam = bpy.data.objects.new("FLW_ReviewCam", bpy.data.cameras.new("FLW_ReviewCam"))
		scene.collection.objects.link(cam)
	# Godot camera at (3, 2.2, 9) looking back at the front -> Blender (3, -9, 2.2).
	cam.location = (3.5, -10.5, 2.4)
	direction = np.array([-1.5, 9.5, 0.4])
	cam.rotation_euler = (math.radians(87.0), 0.0, math.atan2(-direction[0], direction[1]))
	cam.data.lens = 24
	scene.camera = cam
	key = bpy.data.objects.get("FLW_ReviewKey")
	if key is None:
		key = bpy.data.objects.new("FLW_ReviewKey", bpy.data.lights.new("FLW_ReviewKey", "SPOT"))
		scene.collection.objects.link(key)
	key.location = (6.0, -12.0, 9.0)
	key.rotation_euler = (math.radians(50.0), 0.0, math.radians(25.0))
	key.data.energy = 9000.0
	key.data.spot_size = math.radians(75.0)
	world = scene.world or bpy.data.worlds.new("FLW_World")
	scene.world = world
	world.use_nodes = True
	background = next((node for node in world.node_tree.nodes if node.type == "BACKGROUND"), None)
	if background is None:
		background = world.node_tree.nodes.new("ShaderNodeBackground")
		output = next((node for node in world.node_tree.nodes if node.type == "OUTPUT_WORLD"), None) or world.node_tree.nodes.new("ShaderNodeOutputWorld")
		world.node_tree.links.new(background.outputs[0], output.inputs[0])
	background.inputs[0].default_value = (0.01, 0.012, 0.014, 1.0)
	scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE_NEXT"
	scene.render.resolution_x = 1280
	scene.render.resolution_y = 720
	scene.render.image_settings.file_format = "PNG"
	scene.render.image_settings.color_depth = "8"
	scene.render.image_settings.color_mode = "RGB"
	scene.frame_set(12)
	scene.render.filepath = PREVIEWS + "front_f12.png"
	bpy.ops.render.render(write_still=True)
	scene.frame_set(1)
	return {"preview": PREVIEWS + "front_f12.png"}
