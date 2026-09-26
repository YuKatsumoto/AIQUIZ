"""Shared constants and helpers for the Goal Stand build (Blender 5.1, run through
the Higgsfield Blender connector).  Blender units are metres, Z-up.  Spectators and
the stand face Blender -Y, which the glTF export turns into Godot +Z; GoalStand in
Godot turns the whole stand around so the crowd looks back down the conveyor.

    ns = {}; exec(open(r"C:/AIQUIZ/AIQUIZ-Godot/assets/goal_stand/source/gs_common.py", encoding="utf-8").read(), ns)
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

PROJECT = "C:/AIQUIZ/AIQUIZ-Godot"
SOURCE = PROJECT + "/assets/goal_stand/source"
OUT = PROJECT + "/assets/goal_stand"
SCENE = "AIQUIZ_GoalStand"
RIG = "RIG_Spectator"
FPS = 30

# Palette roles, encoded as UV.x = (role + 0.5) / ROLE_COUNT on every body/prop face.
# Godot (goal_stand_spectator.gdshader) resolves them with per-instance colours.
ROLE_COUNT = 16
SKIN, SHIRT, PANTS, HAIR, SHOES, DARK, ACCENT, WHITE, BLUSH, EGG, CARTON, WOOD = range(12)
PREVIEW_COLORS = {
    SKIN: (0.93, 0.74, 0.60), SHIRT: (0.94, 0.41, 0.35), PANTS: (0.20, 0.24, 0.34),
    HAIR: (0.23, 0.15, 0.10), SHOES: (0.12, 0.12, 0.14), DARK: (0.05, 0.05, 0.07),
    ACCENT: (0.95, 0.55, 0.20), WHITE: (0.96, 0.96, 0.94), BLUSH: (0.95, 0.55, 0.55),
    EGG: (0.97, 0.93, 0.84), CARTON: (0.74, 0.66, 0.54), WOOD: (0.62, 0.45, 0.28),
}

KEEP_BONES = [
    "root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
    "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
    "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
    "thigh_l", "calf_l", "foot_l", "ball_l",
    "thigh_r", "calf_r", "foot_r", "ball_r",
]


def scene():
    sc = bpy.data.scenes.get(SCENE)
    if bpy.context.window.scene != sc:
        bpy.context.window.scene = sc
    sc.render.fps = FPS
    sc.render.fps_base = 1.0
    return sc


def collection(name, parent=None):
    sc = scene()
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        (parent or sc.collection).children.link(coll)
    return coll


def clear_collection(name):
    coll = bpy.data.collections.get(name)
    if coll is None:
        return
    for obj in list(coll.objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)


def palette_image():
    img = bpy.data.images.get("SPEC_PaletteImage")
    if img is None:
        img = bpy.data.images.new("SPEC_PaletteImage", ROLE_COUNT, 1, alpha=False)
    px = []
    for role in range(ROLE_COUNT):
        c = PREVIEW_COLORS.get(role, (1.0, 0.0, 1.0))
        px += [c[0], c[1], c[2], 1.0]
    img.pixels = px
    img.update()
    return img


def palette_material():
    mat = bpy.data.materials.get("SPEC_Palette")
    if mat is None:
        mat = bpy.data.materials.new("SPEC_Palette")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = palette_image()
    tex.interpolation = "Closest"
    bsdf.inputs["Roughness"].default_value = 0.72
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def flat_material(name, color, rough=0.6, metal=0.0, emission=None, strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if bsdf is None:
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        bsdf.name = "Principled BSDF"
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    mat.diffuse_color = (*color, 1.0)
    return mat


def image_material(name, path, alpha=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path, check_existing=True)
    bsdf.inputs["Roughness"].default_value = 0.8
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.blend_method = "CLIP" if hasattr(mat, "blend_method") else None
        mat.surface_render_method = "DITHERED"
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def role_uv(role):
    return ((role + 0.5) / ROLE_COUNT, 0.5)


class MeshBuilder:
    """Collects boxes (each tagged with a palette role and a bone) into one bmesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.deform = self.bm.verts.layers.deform.verify()
        self.groups = {}

    def group_index(self, bone):
        if bone not in self.groups:
            self.groups[bone] = len(self.groups)
        return self.groups[bone]

    def box(self, center, size, role, bone=None, rot=None, uv_rect=None):
        """Axis-aligned (or rotated) box. uv_rect=(u0, v0, u1, v1) maps the -Y face
        to a texture instead of a palette role (used by signs and the banner)."""
        m = Matrix.Translation(Vector(center))
        if rot is not None:
            m = m @ (rot.to_matrix().to_4x4() if isinstance(rot, Quaternion) else rot.to_4x4())
        m = m @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        verts = res["verts"]
        faces = {f for v in verts for f in v.link_faces}
        self._tag(verts, faces, role, bone, uv_rect)
        return verts

    def cylinder(self, center, radius, depth, role, bone=None, rot=None, segments=10):
        m = Matrix.Translation(Vector(center))
        if rot is not None:
            m = m @ (rot.to_matrix().to_4x4() if isinstance(rot, Quaternion) else rot.to_4x4())
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments,
                                    radius1=radius, radius2=radius, depth=depth, matrix=m)
        verts = res["verts"]
        faces = {f for v in verts for f in v.link_faces}
        self._tag(verts, faces, role, bone)
        return verts

    def ellipsoid(self, center, radii, role, bone=None, rot=None, segments=12, rings=8):
        m = Matrix.Translation(Vector(center))
        if rot is not None:
            m = m @ (rot.to_matrix().to_4x4() if isinstance(rot, Quaternion) else rot.to_4x4())
        m = m @ Matrix.Diagonal((radii[0], radii[1], radii[2], 1.0))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segments, v_segments=rings, radius=1.0, matrix=m)
        verts = res["verts"]
        faces = {f for v in verts for f in v.link_faces}
        self._tag(verts, faces, role, bone)
        return verts

    def _tag(self, verts, faces, role, bone, uv_rect=None):
        if bone is not None:
            gi = self.group_index(bone)
            for v in verts:
                v[self.deform][gi] = 1.0
        for f in faces:
            f.smooth = False
            if uv_rect is not None and f.normal.y < -0.9:
                xs = [l.vert.co.x for l in f.loops]
                zs = [l.vert.co.z for l in f.loops]
                for loop in f.loops:
                    u = (loop.vert.co.x - min(xs)) / max(1e-6, max(xs) - min(xs))
                    w = (loop.vert.co.z - min(zs)) / max(1e-6, max(zs) - min(zs))
                    loop[self.uv].uv = (uv_rect[0] + (uv_rect[2] - uv_rect[0]) * u, uv_rect[1] + (uv_rect[3] - uv_rect[1]) * w)
            else:
                uv = role_uv(role)
                for loop in f.loops:
                    loop[self.uv].uv = uv

    def finish(self, name, coll, materials, rig=None):
        # Never adopt a datablock that belongs to another scene (the live session also
        # holds the Score Tower Finale, whose PRP_* names must stay untouched).
        obj = bpy.data.objects.get(name)
        if obj is not None and not any(c.name.startswith("GS_") for c in obj.users_collection):
            raise RuntimeError("name collision with a foreign object: " + name)
        mesh = bpy.data.meshes.get(name)
        if mesh is not None and any(o.data == mesh and o is not obj for o in bpy.data.objects):
            raise RuntimeError("name collision with a foreign mesh: " + name)
        if mesh is None:
            mesh = bpy.data.meshes.new(name)
        if obj is None:
            obj = bpy.data.objects.new(name, mesh)
            coll.objects.link(obj)
        obj.data = mesh
        # Group names live on the mesh (Blender 3+): name them before writing weights.
        obj.vertex_groups.clear()
        for bone, _index in sorted(self.groups.items(), key=lambda kv: kv[1]):
            obj.vertex_groups.new(name=bone)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh.materials.clear()
        for mat in materials:
            mesh.materials.append(mat)
        self.bm.to_mesh(mesh)
        self.bm.free()
        if rig is not None:
            obj.parent = rig
            obj.matrix_parent_inverse = Matrix.Identity(4)
            mod = obj.modifiers.get("Armature") or obj.modifiers.new("Armature", "ARMATURE")
            mod.object = rig
        return obj


def ensure_fcurves(action, rig, bone_names, with_location=("pelvis",)):
    """Create (or reuse) rotation_quaternion curves for bones, plus location for the
    listed bones, on a layered action bound to the rig."""
    curves = {}
    for bone in bone_names:
        path = 'pose.bones["%s"].rotation_quaternion' % bone
        curves[(bone, "rot")] = [action.fcurve_ensure_for_datablock(rig, path, index=i, group_name=bone) for i in range(4)]
        if bone in with_location:
            path = 'pose.bones["%s"].location' % bone
            curves[(bone, "loc")] = [action.fcurve_ensure_for_datablock(rig, path, index=i, group_name=bone) for i in range(3)]
    return curves


def write_keys(curves, samples, frame_offset=0):
    """samples: list of {bone: (Quaternion, Vector|None)} per frame (frame 0..n-1)."""
    n = len(samples)
    continuous(samples, {bone for (bone, _kind) in curves})
    for (bone, kind), fcs in curves.items():
        for i, fc in enumerate(fcs):
            fc.keyframe_points.clear()
            fc.keyframe_points.add(n)
            co = []
            for f, pose in enumerate(samples):
                q, loc = pose[bone]
                value = q[i] if kind == "rot" else loc[i]
                co += [float(f + frame_offset), float(value)]
            fc.keyframe_points.foreach_set("co", co)
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"
            fc.update()


def continuous(samples, bones):
    """Flip quaternions so consecutive samples stay in one hemisphere."""
    for bone in bones:
        prev = None
        for pose in samples:
            q, loc = pose[bone]
            if prev is not None and prev.dot(q) < 0.0:
                q = -q
                pose[bone] = (q, loc)
            prev = q
    return samples


def new_action(name, rig):
    old = bpy.data.actions.get(name)
    if old is not None:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = action
    return action
