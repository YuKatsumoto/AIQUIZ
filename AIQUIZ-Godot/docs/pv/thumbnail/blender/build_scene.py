"""サムネイルを Cycles で描き直すための Blender のシーンを、Godot の書き出しから組む（開いている Blender の中で動かす）。

書き出しは tests/pv_capture/pv_thumb_runtime.gd の export=<フレーム>（foreground.glb と scene.json）。
t2 は手で組んだ（t2_thumbnail.blend）。その手順と値をここにまとめ、ショット名を渡せば同じように組めるようにした（t5 から）。
ヘッドレスの Blender ではなく、開いている Blender（Higgsfield の Blender 連携）で実行する:

    ns = {}
    exec(open(r"G:\\AIQUIZ-Main\\AIQUIZ-Godot\\docs\\pv\\thumbnail\\blender\\build_scene.py", encoding="utf-8").read(), ns)
    ns["build"]("t5")      # docs/pv/thumbnail/blender/t5_thumbnail.blend を新しく作って組み、保存する

先に make_label_textures.py <shot> で文字の板の画像を作っておく。組むもの（値はどれも t2 でゲームの絵に合わせたもの。README.md）:
  - コレクション P1・P2（2 人と帽子）・WALL（壁・扉・破片・看板・文字の板）・DECK（床・枠・レール）・CAM・LGT
  - カメラ・太陽・環境（拡散光は一様な環境光、映り込みはゲームの空）・Cycles の設定
  - 材質：2 人と帽子、壁の 3 方向から貼る模様、扉の破片、看板（光らせるだけ）、コンベアの床、鉄部
  - 文字の板（tex/<shot>_labels.json と画像）
  - 剛体（脱落したプレイヤーのラグドール・扉の破片）の、少し前からいままでの動き（モーションブラー用のキー）
  - view layer VL_chars / VL_p2trail（動きがあるとき）/ VL_wall / VL_deck / VL_depth と、
    描くための Text「thumb_render.py」（render_layers.py と同じ中身）
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

def find_root():
    """プロジェクト（project.godot のあるフォルダ）。開いている .blend から上へたどり、無ければ環境変数 AIQUIZ_ROOT、
    メインPC の C:\AIQUIZ\AIQUIZ-Godot・G:\AIQUIZ-Main\AIQUIZ-Godot、ノートPC の デスクトップ\AIQUIZ\AIQUIZ-Godot の順に探す"""
    p = bpy.data.filepath
    while p and os.path.dirname(p) != p:
        p = os.path.dirname(p)
        if os.path.isfile(os.path.join(p, "project.godot")):
            return p
    for c in (os.environ.get("AIQUIZ_ROOT", ""), r"C:\AIQUIZ\AIQUIZ-Godot", r"G:\AIQUIZ-Main\AIQUIZ-Godot",
              os.path.expanduser(r"~\Desktop\AIQUIZ\AIQUIZ-Godot")):
        if c and os.path.isfile(os.path.join(c, "project.godot")):
            return c
    raise RuntimeError("AIQUIZ-Godot が見つからない（環境変数 AIQUIZ_ROOT で指定できる）")


ROOT = find_root()
HERE = os.path.join(ROOT, "docs", "pv", "thumbnail", "blender")
TEX = os.path.join(ROOT, "assets", "environment", "conveyor_stage", "textures")

# 光（t2 で、太陽だけ・環境光だけ・空の映り込みだけの絵をゲームの絵に最小二乗で合わせ、太陽を少し強めた値）
SUN_GAIN = 0.70                 # 太陽：π × ゲームの energy × これ
AMBIENT_STRENGTH = 1.85         # 環境光：ゲームの ambient_light_color（線形）× ambient_light_energy × これ
SKY_REFLECTION_GAIN = 1.359     # 空の映り込み：ゲームの background_energy × これ
# ゲームの昼の空（aiquiz_day_night_sky.gdshader の昼。sRGB）
SKY_TOP = (0.08, 0.48, 0.98)
SKY_HORIZON = (0.64, 0.88, 1.0)
SKY_CLOUD = (0.98, 0.99, 1.0)
# モーションブラー：剛体（脱落したプレイヤーのラグドール・扉の破片）を、書き出しの速度と角速度で少し前へさかのぼらせ、
# いまの姿までの動きを写す（シャッターはいまで閉じる）。値はさかのぼるゲームの秒。ゲームのスローモーション（0.35 倍）の
# 1 フレームはゲームの 0.006 秒なので、どれも本物より長い露光（吹っ飛ぶ勢いを見せるため）。
# 吹っ飛ぶプレイヤーは、本体はくっきり描き（VL_chars はブラーなし）、後ろに伸びる残像の尾を別の層（VL_p2trail）に描いて
# 本体の下に重ねる（体ごとぶらすと、ぼやけた写真に見えて形が読めなくなるため）。扉の破片はぶらさない（奥へ飛ぶので、
# ぶらすと動きより「ピンぼけ」に見える）
MOTION_BLUR_S = {"P2": 0.10}
MOTION_ROT_SCALE = 0.4          # 回転のぶれは弱める（ラグドールの手足は速く回るので、そのままだと尾が形をなくす）
# シャッターの開き方（0 = 開いた時、1 = いま）。ほぼ均一にして、手足ごとの流れる線にする（いまに近いほど少し濃い）
MOTION_SHUTTER_CURVE = ((0.0, 0.6), (1.0, 1.0))
MOTION_FRAME = 10               # いまの姿のフレーム（その 1 フレーム前がシャッターの開き）
MOTION_KEYS = 8                 # さかのぼる道のりを何区切りでキーにするか（回転の弧をなめらかに）
# 絵コンテに寄せる演出（ショットごと）。t7（gen/t2_side.png の再現。真横の超望遠）:
#   deck_widen：床（コンベア）を手前（−x）へ広げる m。真横から遠くで撮ると、幅 24 m の床は細い帯になり、下にコンベアの側面が
#               大きく写る。絵コンテは床が画面の下まで続くので、床を手前へ広げ、手前の側面とレールをその分だけ外へ動かす
#               （床の模様は広げた分だけ横に伸ばして、端の帯が新しい端に来るようにする）
#   pose：走る人を、カメラ（−x）のほうへ turn 度振り向かせ、前へ lean 度傾ける（負ならうしろへ起こす）。真横からは胸も腕も
#         重なって細く見える。絵コンテの 2 人は 3/4 の向き（胸と両腕が見える）で走っている（向きを 30° 変えても、足の運びの
#         縮みは 0.87 倍で、走る向きはほぼ右のまま）。姿はゲームの全力疾走（撮影台本の sprint）で、前のめりが絵コンテより
#         強い（約 30°）ので、10° 起こす。scale：絵コンテの人の背丈は扉の高さの 0.68 倍（ゲームは 0.60）なので、1.13 倍にする
#   hat_tilt：帽子をうしろへ傾ける（度）。絵コンテの魔法使いの帽子は、走る勢いでうしろへ傾いている
#   dust：うしろ足の下から後ろへ、角ばった白い土ぼこり（絵コンテと同じ low-poly の煙）を小山に盛る
ART = {
    "t7": {"deck_widen": 12.0,
           "pose": {"P1": {"turn": 30.0, "lean": -10.0, "scale": 1.13}, "P2": {"turn": 30.0, "lean": -10.0, "scale": 1.13}},
           "hat_tilt": {"P2": 18.0},
           "dust": {"P1": {"seed": 3, "count": 42, "length": 1.2, "spread": 0.32, "size": 0.21, "height": 0.72},
                    "P2": {"seed": 8, "count": 36, "length": 1.1, "spread": 0.32, "size": 0.19, "height": 0.64}}},
}
DECK_NEAR_PARTS = ("ConveyorSideFrameLeft", "LeftRunningHead", "LeftWeb", "LeftMountingBase", "LeftEndCap")
# 鉄部（ground_steel.gdshader）の近似：仕上げの色 → (粗さ, 金属, 上面を磨く)
STEEL = {(0.30, 0.31, 0.33): (0.55, 0.12, False),
         (0.64, 0.68, 0.71): (0.36, 0.8, True),
         (0.16, 0.18, 0.21): (0.6, 0.12, False)}


# ------------------------------------------------------------------ 共通

def srgb(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin3(rgb):
    return tuple(srgb(c) for c in rgb[:3])


def g2b(v):
    """Godot (x, y, z) → Blender (x, −z, y)"""
    return Vector((v[0], -v[2], v[1]))


def g2b_matrix(x):
    cols = [g2b(c) for c in x["basis"]]
    m = Matrix.Identity(4)
    for i in range(3):
        m[0][i], m[1][i], m[2][i] = cols[i]
    m[0][3], m[1][3], m[2][3] = g2b(x["origin"])
    return m


def find_export(shot):
    """Godot の書き出し：artifacts/pv_capture/thumb_<shot>_export/export（git に入らない）が無ければ、
    docs/pv/thumbnail/<shot>/export（ほかの PC でも作業できるように写したもの。t8）"""
    for d in (os.path.join(ROOT, "artifacts", "pv_capture", "thumb_%s_export" % shot, "export"),
              os.path.join(ROOT, "docs", "pv", "thumbnail", shot, "export")):
        if os.path.isfile(os.path.join(d, "scene.json")):
            return d
    raise FileNotFoundError("thumb_%s_export の scene.json が無い" % shot)


def coll(name):
    scn = bpy.context.scene
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in [ch.name for ch in scn.collection.children]:
        scn.collection.children.link(c)
    return c


def camera_only(ob):
    ob.visible_diffuse = ob.visible_glossy = ob.visible_shadow = False
    ob.visible_transmission = ob.visible_volume_scatter = False


def material_info(J):
    """scene.json の材質（書き出しの名前 → ゲームの値）"""
    info = {}
    for e in J["meshes"]:
        for m in e["materials"]:
            info.setdefault(m["export_name"], m)
    return info


def image(path, noncolor):
    im = bpy.data.images.load(path, check_existing=True)
    im.colorspace_settings.name = 'Non-Color' if noncolor else 'sRGB'
    return im


class Nodes:
    """ノードを式のように組むための小さな道具（入力は数・タプル・ソケットのどれでもよい）"""

    def __init__(self, nt):
        self.nt = nt

    def _set(self, n, i, v):
        if v is None:
            return
        if isinstance(v, (int, float, tuple)):
            n.inputs[i].default_value = v
        else:
            self.nt.links.new(v, n.inputs[i])

    def m(self, op, a=None, b=None, c=None, clamp=False):
        n = self.nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b, c)):
            self._set(n, i, v)
        return n.outputs[0]

    def v(self, op, a=None, b=None, scale=None):
        n = self.nt.nodes.new("ShaderNodeVectorMath")
        n.operation = op
        for i, val in enumerate((a, b)):
            self._set(n, i, val)
        if scale is not None:
            self._set(n, n.inputs.find("Scale"), scale)
        return n.outputs["Value"] if op in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else n.outputs["Vector"]

    def smooth(self, x, e0, e1, lo=0.0, hi=1.0):
        n = self.nt.nodes.new("ShaderNodeMapRange")
        n.interpolation_type = 'SMOOTHSTEP'
        n.clamp = True
        self._set(n, 0, x)
        n.inputs[1].default_value = e0
        n.inputs[2].default_value = e1
        n.inputs[3].default_value = lo
        n.inputs[4].default_value = hi
        return n.outputs[0]

    def mixc(self, f, a, b):
        """色を f で a → b に混ぜる"""
        n = self.nt.nodes.new("ShaderNodeMix")
        n.data_type = 'RGBA'
        n.blend_type = 'MIX'
        self._set(n, 0, f)
        self._set(n, 6, a)
        self._set(n, 7, b)
        return n.outputs[2]

    def mulc(self, col, s):
        return self.v("SCALE", col, scale=s)

    def comb(self, x, y, z=0.0):
        n = self.nt.nodes.new("ShaderNodeCombineXYZ")
        for i, val in enumerate((x, y, z)):
            self._set(n, i, val)
        return n.outputs[0]

    def sep(self, vec):
        n = self.nt.nodes.new("ShaderNodeSeparateXYZ")
        self._set(n, 0, vec)
        return n.outputs

    def tex(self, img, vec):
        n = self.nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.interpolation = 'Cubic'
        self._set(n, 0, vec)
        return n.outputs["Color"]

    def noise(self, vec):
        """ゲームの値のノイズ（0〜1）に近い 2D のノイズ"""
        n = self.nt.nodes.new("ShaderNodeTexNoise")
        n.noise_dimensions = '2D'
        self._set(n, 0, vec)
        n.inputs["Scale"].default_value = 1.0
        n.inputs["Detail"].default_value = 0.0
        n.inputs["Roughness"].default_value = 0.0
        if "Normalize" in n.inputs:
            n.inputs["Normalize"].default_value = True
        # Blender のノイズ（だいたい 0.2〜0.8）をゲームの 0〜1 に広げる
        return self.m("MULTIPLY_ADD", self.m("SUBTRACT", n.outputs["Fac"], 0.5), 1.7, 0.5, clamp=True)


def fresh_tree(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    return nt, out


# ------------------------------------------------------------------ ファイル・読み込み・カメラ・光

def new_file(shot):
    """新しい空のファイルにする。開いているファイルに保存していない変更があれば止める（組み直す同じファイルなら捨てる）"""
    path = os.path.join(HERE, "%s_thumbnail.blend" % shot)
    same = os.path.normcase(os.path.abspath(bpy.data.filepath or "")) == os.path.normcase(path)
    assert same or not bpy.data.is_dirty, "開いているファイルに保存していない変更がある"
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.wm.save_as_mainfile(filepath=path)
    scn = bpy.context.scene
    scn.name = "THUMB_%s" % shot
    scn["thumb_shot"] = shot
    return path


def import_foreground(export_dir):
    """glTF の THUMB/P1・P2・WALL・DECK を、同じ名前のコレクションに分ける"""
    before = set(bpy.data.objects.keys())
    # 形はゲームの法線のまま（箱は面ごとに分かれているので角が立ち、帽子は丸いまま）
    bpy.ops.import_scene.gltf(filepath=os.path.join(export_dir, "foreground.glb"), merge_vertices=False,
                              import_shading='NORMALS')
    new = [o for o in bpy.data.objects if o.name not in before]
    target = {g: coll(g) for g in ("P1", "P2", "WALL", "DECK")}
    misc = coll("IMPORT_ROOT")
    counts = {}
    for o in new:
        top = o
        while top.parent is not None and top.parent.name != "THUMB":
            top = top.parent
        group = top.name.split(".")[0] if top.parent is not None else None
        dest = target.get(group, misc)
        for c in list(o.users_collection):
            c.objects.unlink(o)
        dest.objects.link(o)
        counts[dest.name] = counts.get(dest.name, 0) + 1
    return counts


def setup_camera(J):
    """ゲームの Camera3D そのまま（縦の画角）"""
    cj = J["camera"]
    assert cj["keep_aspect"] == 1 and cj["projection"] == 0, "縦の画角の透視カメラだけを扱う"
    data = bpy.data.cameras.new("CAM_main")
    data.sensor_fit = 'VERTICAL'
    data.sensor_height = 24.0
    data.angle_y = math.radians(cj["fov"])
    data.clip_start = cj["near"]
    data.clip_end = 2000.0
    data.dof.use_dof = False
    cam = bpy.data.objects.new("CAM_main", data)
    coll("CAM").objects.link(cam)
    cam.matrix_world = g2b_matrix(cj["xform"])
    bpy.context.scene.camera = cam
    return cam


def setup_sun(J):
    lj = next(l for l in J["lights"] if l["path"].endswith("StageEnvironment/DirectionalLight3D"))
    data = bpy.data.lights.new("LGT_sun", 'SUN')
    data.color = lin3(lj["color"])
    data.energy = math.pi * lj["energy"] * SUN_GAIN
    data.angle = math.radians(0.8)
    sun = bpy.data.objects.new("LGT_sun", data)
    coll("LGT").objects.link(sun)
    sun.matrix_world = g2b_matrix(lj["xform"])
    sun["fit"] = "game-matched balance with a little more sun for modelling (sun x%.2f, ambient x%.2f, sky reflection x%.3f)" % (
        SUN_GAIN, AMBIENT_STRENGTH, SKY_REFLECTION_GAIN)
    return sun


def sun_through_first_wall(J, sun):
    """ゲームの絵では、1 枚目の壁の後ろ（突き破った扉の奥の P1・破片・床）に、その壁の影が落ちていない（理由は不明。
    t5 の 63 フレーム目で確かめた）。同じに見せるため、太陽の光だけ 1 枚目の壁を通す（影のリンク。空の光の遮りと
    照り返しはそのまま）。壁の前にいるもの（t2 の 2 人、t5 の P2）には関係しない"""
    wall_z = J["state"]["wall_z"]
    prefix = None
    for e in J["meshes"]:
        if e["group"] == "WALL" and "RigidBody" not in e["path"] and abs(e["xform"]["origin"][2] - wall_z) < 0.7:
            prefix = e["path"].rsplit("/", 1)[0]
            break
    if prefix is None:
        return []
    names = [e["name"] for e in J["meshes"]
             if e["path"].startswith(prefix + "/") and "RigidBody" not in e["path"] and bpy.data.objects.get(e["name"])]
    blockers = bpy.data.collections.new("LL_sun_blockers")
    for n in names:
        blockers.objects.link(bpy.data.objects[n])
    for item in blockers.collection_objects:
        item.light_linking.link_state = 'EXCLUDE'
    sun.light_linking.blocker_collection = blockers
    return names


def setup_world(J):
    """拡散光はゲームと同じ一様な環境光、映り込み（Is Glossy Ray）はゲームの昼の空のグラデーション"""
    ej = J["environment"]
    w = bpy.data.worlds.new("WLD_game")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    b = Nodes(nt)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    out.name = "WO_main"
    bg_amb = nt.nodes.new("ShaderNodeBackground")
    bg_amb.name = "BG_ambient"
    amb = tuple(c * ej["ambient_energy"] for c in lin3(ej["ambient_color"]))
    bg_amb.inputs["Color"].default_value = amb + (1.0,)
    bg_amb.inputs["Strength"].default_value = AMBIENT_STRENGTH
    bg_sky = nt.nodes.new("ShaderNodeBackground")
    bg_sky.name = "BG_sky_reflection"
    bg_sky.inputs["Strength"].default_value = ej["background_energy"] * SKY_REFLECTION_GAIN
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.name = "MIX_by_ray"
    nt.links.new(lp.outputs["Is Glossy Ray"], mix.inputs[0])
    nt.links.new(bg_amb.outputs[0], mix.inputs[1])
    nt.links.new(bg_sky.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    z = b.sep(b.v("NORMALIZE", tc.outputs["Generated"]))[2]
    top, horizon, cloud = lin3(SKY_TOP) + (1.0,), lin3(SKY_HORIZON) + (1.0,), lin3(SKY_CLOUD) + (1.0,)
    ground = tuple(c * 0.52 for c in horizon[:3]) + (1.0,)
    hmask = b.m("POWER", b.m("SUBTRACT", 1.0, b.m("ABSOLUTE", z), clamp=True), 4.2)
    sky_up = b.mixc(hmask, top, horizon)
    sky_up = b.mixc(b.m("MULTIPLY", b.smooth(z, 0.02, 0.16), 0.32), sky_up, cloud)
    sky_dn = b.mixc(b.smooth(z, -0.85, 0.0), ground, horizon)
    sky = b.mixc(b.m("LESS_THAN", z, 0.0), sky_up, sky_dn)
    nt.links.new(sky, bg_sky.inputs["Color"])
    bpy.context.scene.world = w
    return amb


def setup_render():
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.device = 'GPU'
    scn.render.resolution_x, scn.render.resolution_y = 3840, 2160
    scn.render.resolution_percentage = 100
    scn.render.film_transparent = True
    vs = scn.view_settings
    vs.view_transform = 'Standard'
    vs.look = 'None'
    vs.exposure = 0.0
    vs.gamma = 1.0
    c = scn.cycles
    c.samples = 1024
    c.use_adaptive_sampling = True
    c.adaptive_threshold = 0.004
    c.adaptive_min_samples = 64
    c.use_denoising = True
    c.denoiser = 'OPENIMAGEDENOISE'
    c.denoising_prefilter = 'ACCURATE'
    if hasattr(c, "denoising_quality"):
        c.denoising_quality = 'HIGH'
    if hasattr(c, "denoising_use_gpu"):
        c.denoising_use_gpu = True
    scn.render.use_persistent_data = True
    scn.frame_set(MOTION_FRAME)


# ------------------------------------------------------------------ 材質

def character_materials():
    """色はゲームの値のまま。粗さと金属を Cycles 向けにし、角に丸みの陰影（形は変えない）"""
    done = []
    for mat in bpy.data.materials:
        if not mat.name.startswith(("P1__", "P2__")):
            continue
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        body = "__std_" in mat.name
        bsdf.inputs["Roughness"].default_value = 0.55 if body else 0.72
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Specular IOR Level"].default_value = 0.5
        bev = nt.nodes.new("ShaderNodeBevel")
        bev.name = "BEVEL_edges"
        bev.inputs["Radius"].default_value = 0.012 if body else 0.006
        bev.samples = 8
        if not bsdf.inputs["Normal"].is_linked:
            nt.links.new(bev.outputs["Normal"], bsdf.inputs["Normal"])
        mat["thumb_role"] = "character body" if body else "hat"
        done.append(mat.name)
    return done


def wall_uv_group():
    """ゲームの物体の座標で 3 方向から貼る模様の UV（wall_materials.gd の panel()、StandardMaterial3D の triplanar）。
    Blender の物体の座標 (x, y, z) = Godot の (x, −z, y)。模様は 9 m × 4.4 m × 9 m、縦のずらし 0.5・奥のずらし 0.19"""
    ng = bpy.data.node_groups.get("NG_wall_triplanar_uv")
    if ng is not None:
        return ng
    ng = bpy.data.node_groups.new("NG_wall_triplanar_uv", "ShaderNodeTree")
    ng.interface.new_socket("offset_u", in_out='INPUT', socket_type='NodeSocketFloat')
    for name in ("uv_front", "uv_top", "uv_side", "weights"):
        ng.interface.new_socket(name, in_out='OUTPUT', socket_type='NodeSocketVector')
    b = Nodes(ng)
    gi = ng.nodes.new("NodeGroupInput")
    go = ng.nodes.new("NodeGroupOutput")
    tc = ng.nodes.new("ShaderNodeTexCoord")
    p = b.sep(tc.outputs["Object"])
    u_x = b.m("MULTIPLY_ADD", p[0], 1.0 / 9.0, gi.outputs["offset_u"])
    v_z = b.m("MULTIPLY_ADD", p[2], 1.0 / 4.4, 0.5)
    u_y = b.m("MULTIPLY_ADD", p[1], 1.0 / 9.0, -0.19)
    ng.links.new(b.comb(u_x, v_z), go.inputs["uv_front"])
    ng.links.new(b.comb(u_x, u_y), go.inputs["uv_top"])
    ng.links.new(b.comb(u_y, v_z), go.inputs["uv_side"])
    a = b.v("ABSOLUTE", tc.outputs["Normal"])
    w = b.v("SCALE", a, scale=b.m("DIVIDE", 1.0, b.v("DOT_PRODUCT", a, (1.0, 1.0, 1.0))))
    ng.links.new(w, go.inputs["weights"])
    return ng


def build_wall(mat, offset_u):
    """壁と扉：模様（色 × ゲームの albedo_color）、粗さ（ORM の G）、法線（OpenGL、3 方向それぞれの向き）、角の丸み"""
    ng = wall_uv_group()
    alb = image(os.path.join(TEX, "wall_panel_albedo.png"), False)
    nrm = image(os.path.join(TEX, "wall_panel_normal.png"), True)
    orm = image(os.path.join(TEX, "wall_panel_orm.png"), True)
    old = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    base = tuple(old.inputs["Base Color"].default_value)
    nt, out = fresh_tree(mat)
    b = Nodes(nt)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    grp = nt.nodes.new("ShaderNodeGroup")
    grp.node_tree = ng
    grp.inputs["offset_u"].default_value = offset_u
    wsep = b.sep(grp.outputs["weights"])
    proj = (("uv_front", 1), ("uv_top", 2), ("uv_side", 0))   # 前（Godot の z 向き）＝ Blender の y の重み、など

    def tri(img):
        outs = [(b.tex(img, grp.outputs[sock]), wsep[k]) for sock, k in proj]
        acc = None
        for col, wv in outs:
            sc = b.v("SCALE", col, scale=wv)
            acc = sc if acc is None else b.v("ADD", acc, sc)
        return acc, outs

    col_rgb = nt.nodes.new("ShaderNodeRGB")
    col_rgb.label = "game albedo_color"
    col_rgb.outputs[0].default_value = base
    a_acc, _ = tri(alb)
    nt.links.new(b.v("MULTIPLY", a_acc, col_rgb.outputs[0]), bsdf.inputs["Base Color"])
    o_acc, _ = tri(orm)
    nt.links.new(b.sep(o_acc)[1], bsdf.inputs["Roughness"])        # ORM の G × 粗さ 1.0
    bsdf.inputs["Metallic"].default_value = 0.05
    _, n_outs = tri(nrm)
    frames = (((1, 0, 0), (0, 0, 1)), ((1, 0, 0), (0, 1, 0)), ((0, 1, 0), (0, 0, 1)))   # (U の向き, 画像の上の向き)
    pert = None
    for (col, wv), (T, B) in zip(n_outs, frames):
        s = b.sep(col)
        nx = b.m("MULTIPLY_ADD", s[0], 2.0, -1.0)
        ny = b.m("MULTIPLY_ADD", s[1], 2.0, -1.0)
        p = b.v("SCALE", b.v("ADD", b.v("SCALE", T, scale=nx), b.v("SCALE", B, scale=ny)), scale=wv)
        pert = p if pert is None else b.v("ADD", pert, p)
    vt = nt.nodes.new("ShaderNodeVectorTransform")
    vt.vector_type = 'VECTOR'
    vt.convert_from = 'OBJECT'
    vt.convert_to = 'WORLD'
    nt.links.new(pert, vt.inputs[0])
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.inputs["Radius"].default_value = 0.01
    bev.samples = 8
    nt.links.new(b.v("NORMALIZE", b.v("ADD", bev.outputs["Normal"], vt.outputs[0])), bsdf.inputs["Normal"])
    mat["thumb_role"] = "quiz wall panel (triplanar, offset_u=%.4f)" % offset_u


def build_panel(mat, rgb_srgb):
    """看板の板：ゲームでは光の当たらない一色（unshaded）"""
    nt, out = fresh_tree(mat)
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = lin3(rgb_srgb) + (1.0,)
    e.inputs["Strength"].default_value = 1.0
    nt.links.new(e.outputs[0], out.inputs["Surface"])
    mat["thumb_role"] = "question sign panel (unshaded in the game)"


def build_shard(mat):
    """扉の破片（quiz_wall.gd の _shatter_mesh：扉の色を少し白へずらした箱）。色はそのまま、角に丸みの陰影"""
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.5
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.inputs["Radius"].default_value = 0.012
    bev.samples = 8
    nt.links.new(bev.outputs["Normal"], bsdf.inputs["Normal"])
    mat["thumb_role"] = "door shard"


def wall_materials(J):
    info = material_info(J)
    built = {"triplanar": [], "panel": [], "shard": []}
    panel_mats = set()
    for name, m in info.items():
        mat = bpy.data.materials.get(name)
        if not name.startswith("WALL__") or mat is None:
            continue
        if m.get("triplanar"):
            sc, off = m["uv1_scale"], m["uv1_offset"]
            assert abs(sc[0] - 1 / 9) < 1e-4 and abs(sc[1] - 1 / 4.4) < 1e-4 and abs(off[1] + 0.5) < 1e-4 and abs(off[2] - 0.19) < 1e-4, name
            build_wall(mat, off[0])
            built["triplanar"].append((name, round(off[0], 4)))
        elif m.get("shading_mode") == 0:
            build_panel(mat, m["albedo"])
            panel_mats.add(name)
            built["panel"].append(name)
        else:
            build_shard(mat)
            built["shard"].append(name)
    # 看板は影を落とさず（ゲームも cast_shadow オフ）、まわりも照らさない
    for ob in coll("WALL").objects:
        if ob.type == 'MESH' and any(s.material and s.material.name in panel_mats for s in ob.material_slots):
            camera_only(ob)
    return built


def build_belt(mat, scroll, x_scale=1.0):
    """コンベアの床（conveyor_belt_floor.gdshader をノードに移したもの）。scroll はゲームの world_scroll_z。
    x_scale：床を手前（−x）へ x_scale 倍に広げたとき（ART の deck_widen）、模様の x を x = 12 を軸に縮めて元の幅に戻す"""
    nt, out = fresh_tree(mat)
    b = Nodes(nt)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    P = b.sep(geo.outputs["Position"])
    N = b.sep(geo.outputs["Normal"])
    xb, yb = P[0], P[1]
    if x_scale != 1.0:
        xb = b.m("MULTIPLY_ADD", xb, 1.0 / x_scale, 12.0 - 12.0 / x_scale)
    ax = b.m("ABSOLUTE", xb)
    top = b.smooth(b.m("ABSOLUTE", N[2]), 0.55, 0.85)
    belt_v = b.m("MULTIPLY_ADD", yb, -0.22, scroll * 0.22)          # (z_godot + scroll) × belt_scale、z_godot = −y
    stripe = b.smooth(b.m("SINE", b.m("MULTIPLY", belt_v, 12.0)), -0.08, 0.08)
    groove = b.m("MULTIPLY_ADD", b.m("SINE", b.m("MULTIPLY", belt_v, 24.6)), 0.5, 0.5)
    base_c, stripe_c = lin3((0.40, 0.41, 0.42)) + (1.0,), lin3((0.34, 0.345, 0.35)) + (1.0,)
    rim_c, side_c = lin3((0.26, 0.265, 0.27)) + (1.0,), lin3((0.33, 0.34, 0.35)) + (1.0,)
    col = b.mixc(stripe, base_c, stripe_c)
    col = b.mulc(col, b.m("MULTIPLY_ADD", groove, 0.12, 0.88))
    fp = b.m("FRACT", b.m("MULTIPLY", belt_v, 7.5))
    dist = b.m("MINIMUM", fp, b.m("SUBTRACT", 1.0, fp))
    line = b.m("EXPONENT", b.m("MULTIPLY", b.m("MULTIPLY", dist, dist), -180.0))
    col = b.mulc(col, b.m("MULTIPLY_ADD", line, -0.22, 1.0))
    rim_band = b.m("MULTIPLY", b.smooth(ax, 11.15 - 0.045, 11.15 + 0.045 * 0.35), b.m("SUBTRACT", 1.0, b.smooth(ax, 12.0 - 0.018, 12.01)))
    col = b.mixc(b.m("MULTIPLY", rim_band, top), col, rim_c)
    lip = b.m("MULTIPLY", b.m("EXPONENT", b.m("MULTIPLY", b.m("POWER", b.m("DIVIDE", b.m("SUBTRACT", ax, 11.15), 0.03), 2.0), -1.0)), top)
    col = b.mixc(b.m("MINIMUM", b.m("MULTIPLY", lip, 0.9), 1.0), col, tuple(c * 0.88 for c in rim_c[:3]) + (1.0,))
    col = b.mixc(top, side_c, col)
    # 細かい模様（detail_strength 1、normal_strength 1）。覆いの画像はベルトと一緒に動く
    frac_scroll = (scroll / 2.5) - math.floor(scroll / 2.5)
    uv = b.comb(b.m("DIVIDE", xb, 2.5), b.m("ADD", b.m("DIVIDE", yb, 2.5), 1.0 - frac_scroll))
    t_alb = b.tex(image(os.path.join(TEX, "belt_detail_albedo.png"), False), uv)
    t_orm = b.sep(b.tex(image(os.path.join(TEX, "belt_detail_orm.png"), True), uv))
    t_nrm = b.sep(b.tex(image(os.path.join(TEX, "belt_detail_normal.png"), True), uv))
    zg_s = b.m("ADD", b.m("MULTIPLY", yb, -1.0), scroll)                # ベルトの進む向きの m
    macro_a = b.noise(b.comb(b.m("MULTIPLY_ADD", xb, 0.42, 3.7), b.m("MULTIPLY_ADD", zg_s, 0.21, 1.3)))
    macro_b = b.noise(b.comb(b.m("MULTIPLY_ADD", xb, 1.35, 11.1), b.m("MULTIPLY_ADD", zg_s, 0.55, 7.9)))
    macro = b.m("MULTIPLY_ADD", macro_a, 0.62, b.m("MULTIPLY", macro_b, 0.38))
    contrast = b.m("MULTIPLY_ADD", b.smooth(macro, 0.2, 0.8), 0.75, 0.55)
    tex_mod = b.m("MULTIPLY", b.v("DOT_PRODUCT", t_alb, (1 / 3, 1 / 3, 1 / 3)), 1.064)
    albedo_mod = b.m("MULTIPLY_ADD", b.m("SUBTRACT", tex_mod, 1.0), contrast, 1.0)
    grime = b.m("MULTIPLY", b.smooth(macro_a, 0.45, 0.9), b.m("MULTIPLY_ADD", macro_b, 0.4, 0.6))
    albedo_mod = b.m("MULTIPLY", albedo_mod, b.m("ADD", b.m("MULTIPLY", grime, -0.07), b.m("MULTIPLY_ADD", macro_b, 0.025, 1.0 - 0.0125)))
    contact = b.m("EXPONENT", b.m("MULTIPLY", b.m("MAXIMUM", b.m("SUBTRACT", 11.76, ax), 0.0), -14.0))
    mod_out = b.m("MULTIPLY", albedo_mod, b.m("MULTIPLY_ADD", contact, -0.22, 1.0))
    ao = b.m("MULTIPLY", b.m("MULTIPLY_ADD", b.m("SUBTRACT", 1.0, t_orm[0]), -0.5, 1.0), b.m("MULTIPLY_ADD", contact, -0.45, 1.0))
    ao_soft = b.m("MULTIPLY_ADD", ao, 0.5, 0.5)                         # 画像の AO のくぼみを半分の強さで
    col = b.mixc(top, col, b.mulc(col, b.m("MULTIPLY", mod_out, ao_soft)))
    nt.links.new(col, bsdf.inputs["Base Color"])
    rough = b.m("ADD", b.m("MULTIPLY", b.m("MULTIPLY", b.m("SUBTRACT", t_orm[1], 0.814), 2.2), contrast),
                b.m("MULTIPLY_ADD", grime, 0.06, 0.78 - 0.03), clamp=True)
    rough = b.m("ADD", b.m("MULTIPLY", rim_band, b.m("SUBTRACT", 0.42, rough)), rough)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    nt.links.new(b.m("MULTIPLY_ADD", b.m("MULTIPLY", rim_band, top), 0.18, 0.12), bsdf.inputs["Metallic"])
    # 法線：ベルトの上面。U はワールドの +X、画像の上は Godot の −Z（Blender の +Y）
    nx = b.m("MULTIPLY_ADD", t_nrm[0], 2.0, -1.0)
    ny = b.m("MULTIPLY_ADD", t_nrm[1], 2.0, -1.0)
    amt = b.m("MULTIPLY", b.m("MULTIPLY", b.m("SUBTRACT", 1.0, rim_band), top), b.m("MULTIPLY_ADD", contrast, 0.2, 0.74))
    pert = b.v("ADD", b.v("SCALE", (1.0, 0.0, 0.0), scale=b.m("MULTIPLY", nx, amt)), b.v("SCALE", (0.0, 1.0, 0.0), scale=b.m("MULTIPLY", ny, amt)))
    nt.links.new(b.v("NORMALIZE", b.v("ADD", geo.outputs["Normal"], pert)), bsdf.inputs["Normal"])
    mat["thumb_role"] = "conveyor belt (conveyor_belt_floor.gdshader rebuilt, scroll_z=%.4f)" % scroll


def build_steel(mat, finish, rough_v, metal_v, polish_top):
    """枠とレール（遠くてぼけるので、色と粗さだけを ground_steel.gdshader に合わせる）"""
    nt, out = fresh_tree(mat)
    b = Nodes(nt)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(p.outputs[0], out.inputs["Surface"])
    g = nt.nodes.new("ShaderNodeNewGeometry")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = 3.0
    n.inputs["Detail"].default_value = 4.0
    nt.links.new(g.outputs["Position"], n.inputs["Vector"])
    nt.links.new(b.v("SCALE", lin3(finish), scale=b.m("MULTIPLY_ADD", n.outputs["Fac"], 0.25, 0.875)), p.inputs["Base Color"])
    p.inputs["Metallic"].default_value = metal_v
    r = b.m("MULTIPLY_ADD", n.outputs["Fac"], 0.15, rough_v - 0.075)
    if polish_top:
        r = b.m("ADD", r, b.smooth(b.sep(g.outputs["Normal"])[2], 0.7, 0.95, 0.0, -0.18))
    nt.links.new(r, p.inputs["Roughness"])
    mat["thumb_role"] = "steel (ground_steel.gdshader approx.)"


def deck_materials(J, shot=None):
    info = material_info(J)
    widen = ART.get(shot, {}).get("deck_widen", 0.0)
    built = []
    for name, m in info.items():
        mat = bpy.data.materials.get(name)
        if not name.startswith("DECK__") or mat is None:
            continue
        if "conveyor_belt_floor" in name:
            build_belt(mat, J["state"]["world_scroll_z"], (24.0 + widen) / 24.0)
            built.append((name, "belt"))
        elif "ground_steel" in name:
            params = m.get("params") or m.get("shader_params") or {}
            finish = tuple(round(c, 2) for c in params["finish_color"][:3])
            rough_v, metal_v, polish = STEEL[finish]
            build_steel(mat, finish, rough_v, metal_v, polish)
            built.append((name, finish))
    return built


# ------------------------------------------------------------------ 文字の板

def label_planes(shot):
    """make_label_textures.py の画像を、Label3D の位置に板で置く（カメラにだけ見える）"""
    rows = json.load(open(os.path.join(HERE, "tex", "%s_labels.json" % shot), encoding="utf-8"))
    wall = coll("WALL")
    made = []
    for i, r in enumerate(rows):
        name = "LBL_%02d" % i
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        face = bm.faces.new([bm.verts.new((x, y, 0.0)) for x, y in r["corners"]])   # 左下・右下・右上・左上
        uvl = bm.loops.layers.uv.new("UVMap")
        for loop, uv in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uvl].uv = uv
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        wall.objects.link(ob)
        ob.matrix_world = g2b_matrix(r["xform"])
        camera_only(ob)
        img = image(os.path.join(HERE, r["texture"]), False)
        img.alpha_mode = 'STRAIGHT'
        img.reload()
        mat = bpy.data.materials.new("MAT_label_%02d" % i)
        nt, out = fresh_tree(mat)
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        t.interpolation = 'Cubic'
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 1.0
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mx = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(t.outputs["Color"], em.inputs["Color"])
        nt.links.new(t.outputs["Alpha"], mx.inputs[0])
        nt.links.new(tr.outputs[0], mx.inputs[1])
        nt.links.new(em.outputs[0], mx.inputs[2])
        nt.links.new(mx.outputs[0], out.inputs["Surface"])
        me.materials.append(mat)
        ob["godot_label"] = r["path"]
        ob["text"] = r["text"]
        ob["source"] = "docs/pv/thumbnail/blender/make_label_textures.py"
        made.append((name, r["text"]))
    return made


# ------------------------------------------------------------------ 絵コンテに寄せる演出

def _world_bbox(ob):
    pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    return Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))), \
        Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))


def art_direction(shot, J, first_wall):
    """ART[shot] の演出をかける（first_wall は 1 枚目の壁のオブジェクト名。今は使わない）"""
    a = ART.get(shot)
    done = {}
    if not a:
        return done
    if a.get("deck_widen"):
        w = a["deck_widen"]
        scale = (24.0 + w) / 24.0
        widen = Matrix.Translation((12.0, 0.0, 0.0)) @ Matrix.Diagonal((scale, 1.0, 1.0, 1.0)) @ Matrix.Translation((-12.0, 0.0, 0.0))
        moved = []
        for ob in coll("DECK").objects:
            if ob.name.endswith("_Floor"):
                ob.matrix_world = widen @ ob.matrix_world
                moved.append(ob.name)
            elif any(part in ob.name for part in DECK_NEAR_PARTS):
                ob.matrix_world = Matrix.Translation((-w, 0.0, 0.0)) @ ob.matrix_world
                moved.append(ob.name)
        done["deck_widen"] = moved
    for group, p in a.get("pose", {}).items():
        done["pose_" + group] = pose_runner(group, p.get("turn", 0.0), p.get("lean", 0.0), p.get("scale", 1.0))
    for group, deg in a.get("hat_tilt", {}).items():
        hats = [o for o in coll(group).objects if o.type == 'MESH' and o.name in _hat_names(J, group)]
        if not hats:
            continue
        lo = Vector((min(_world_bbox(o)[0].x for o in hats), min(_world_bbox(o)[0].y for o in hats), min(_world_bbox(o)[0].z for o in hats)))
        hi = Vector((max(_world_bbox(o)[1].x for o in hats), max(_world_bbox(o)[1].y for o in hats), max(_world_bbox(o)[1].z for o in hats)))
        pivot = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))     # つばの真ん中
        tilt = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(deg), 4, 'X') @ Matrix.Translation(-pivot)
        for o in hats:
            o.matrix_world = tilt @ o.matrix_world
        done["hat_tilt_" + group] = [o.name for o in hats]
    for group, p in a.get("dust", {}).items():
        done["dust_" + group] = make_dust(group, exclude=set(_hat_names(J, group)), **p)
    return done


def _hat_names(J, group):
    return [e["name"] for e in J["meshes"] if e["group"] == group and "/HatMount/" in e["path"]]


def pose_runner(group, turn, lean, scale=1.0):
    """体の真ん中の床の上を軸に、前（−y）へ lean 度傾けて（負ならうしろへ起こして）から、カメラ（−x）のほうへ turn 度振り向かせ、
    scale 倍にし、いちばん低い所がもとの高さに来るように上下を合わせる（足が床から浮いたりめり込んだりしないように。帽子ごと）"""
    obs = [o for o in coll(group).objects if o.type == 'MESH' and not o.name.startswith("DUST_")]
    boxes = [_world_bbox(o) for o in obs]

    def lowest():
        return min(min((o.matrix_world @ v.co).z for v in o.data.vertices) for o in obs)

    low = lowest()
    pivot = Vector(((min(b[0].x for b in boxes) + max(b[1].x for b in boxes)) / 2,
                    (min(b[0].y for b in boxes) + max(b[1].y for b in boxes)) / 2, -1.2))
    m = (Matrix.Translation(pivot) @ Matrix.Scale(scale, 4) @ Matrix.Rotation(math.radians(-turn), 4, 'Z')
         @ Matrix.Rotation(math.radians(lean), 4, 'X') @ Matrix.Translation(-pivot))
    for o in obs:
        o.matrix_world = m @ o.matrix_world
    bpy.context.view_layer.update()
    lift = low - lowest()
    for o in obs:
        o.matrix_world = Matrix.Translation((0.0, 0.0, lift)) @ o.matrix_world
    return {"pivot": [round(v, 2) for v in pivot], "lift": round(lift, 3), "parts": len(obs)}


def _dust_material():
    mat = bpy.data.materials.get("MAT_dust")
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("MAT_dust")
    nt, out = fresh_tree(mat)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.inputs["Base Color"].default_value = lin3((0.93, 0.93, 0.95)) + (1.0,)
    p.inputs["Roughness"].default_value = 0.85
    p.inputs["Specular IOR Level"].default_value = 0.3
    nt.links.new(p.outputs[0], out.inputs["Surface"])
    mat["thumb_role"] = "dust puff (low-poly, like the storyboard)"
    return mat


def make_dust(group, seed, count, length, spread, size, height, exclude=()):
    """うしろ足（床から 0.7 m より低い部位のうち、いちばんうしろ（Blender の +y）のもの）の下から後ろへ length m、
    角ばった白い煙を小山に盛る（足もとがいちばん高く height m、うしろへ低く小さく）。細かい粒も上へ飛ばす"""
    import random
    floor = -1.2                                                    # 床の上（Godot の床の高さ −1.2）
    meshes = [o for o in coll(group).objects if o.type == 'MESH' and o.name not in exclude and not o.name.startswith("DUST_")]
    low = [o for o in meshes if _world_bbox(o)[0].z < floor + 0.7]
    back = max(low, key=lambda o: _world_bbox(o)[1].y)
    lo, hi = _world_bbox(back)
    base = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, floor))
    rng = random.Random(seed)
    mat = _dust_material()
    made = 0
    for i in range(count + 10):
        tiny = i >= count
        t = rng.random()                                            # 0 = 足もと、1 = 尾
        if tiny:
            r = rng.uniform(0.018, 0.045)
            pos = base + Vector((rng.uniform(-spread, spread), rng.uniform(-0.3, length * 1.1), rng.uniform(0.12, height * 1.3)))
        else:
            r = size * (1.0 - 0.45 * t) * rng.uniform(0.7, 1.05)
            top = height * (1.0 - 0.6 * t)                          # 小山の高さ（足もとがいちばん高い）
            z = rng.uniform(r * 0.7, max(top - r * 0.8, r * 0.7))    # 下の段に置くか上に積むか
            pos = base + Vector((rng.uniform(-spread, spread), t * length, z))
        name = "DUST_%s_%02d" % (group, i)
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1 if tiny else 2, radius=r)
        for v in bm.verts:                                          # 少しでこぼこに
            v.co *= rng.uniform(0.86, 1.1)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        coll(group).objects.link(ob)
        ob.location = pos
        ob.rotation_euler = (rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28))
        ob.scale = (rng.uniform(0.9, 1.2), rng.uniform(1.0, 1.35), rng.uniform(0.8, 1.0))
        made += 1
    return {"foot": back.name, "base": [round(v, 2) for v in base], "pieces": made}



# ------------------------------------------------------------------ モーションブラー

def motion_blur(J):
    """書き出しの剛体の動き（体の原点の位置・速度、角速度）から、MOTION_BLUR_S 秒前までの姿をキーにする。
    いまの姿は MOTION_FRAME、シャッターはその 1 フレーム前に開いていまで閉じ、開いた側ほど薄く写る"""
    scn = bpy.context.scene
    rows = {e["name"]: e for e in J["meshes"] if e.get("motion")}
    keyed = {}
    for ob in bpy.data.objects:
        e = rows.get(ob.name)
        if e is None or ob.type != 'MESH':
            continue
        span = MOTION_BLUR_S.get(e["group"])
        if not span:
            continue
        mo = e["motion"]
        origin, vel, omega = g2b(mo["origin"]), g2b(mo["v"]), g2b(mo["w"])
        now = ob.matrix_world.copy()
        ob.rotation_mode = 'QUATERNION'
        for i in range(MOTION_KEYS + 1):
            tau = -span * (1.0 - i / MOTION_KEYS)          # さかのぼる秒（0 がいま）
            rot = Matrix.Identity(4)
            if omega.length > 1e-6:
                rot = Matrix.Rotation(omega.length * tau * MOTION_ROT_SCALE, 4, omega.normalized())
            back = Matrix.Translation(origin + vel * tau) @ rot @ Matrix.Translation(-origin)
            ob.matrix_world = back @ now
            frame = MOTION_FRAME - 1 + i / MOTION_KEYS
            for path in ("location", "rotation_quaternion", "scale"):
                ob.keyframe_insert(path, frame=frame)
        ob.matrix_world = now
        if ob.animation_data and ob.animation_data.action:
            for fc in _fcurves(ob.animation_data):
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'
        ob.cycles.motion_steps = 3 if omega.length * span * MOTION_ROT_SCALE > 0.3 else 1
        ob["motion_blur_s"] = span
        ob["motion_group"] = e["group"]
        keyed[e["group"]] = keyed.get(e["group"], 0) + 1
    scn.frame_set(MOTION_FRAME)
    r = scn.render
    r.use_motion_blur = True
    r.motion_blur_position = 'END'
    r.motion_blur_shutter = 1.0
    cm = r.motion_blur_shutter_curve
    curve = cm.curves[0]
    while len(curve.points) > 2:
        curve.points.remove(curve.points[-1])
    curve.points[0].location = MOTION_SHUTTER_CURVE[0]
    curve.points[1].location = MOTION_SHUTTER_CURVE[-1]
    for x, y in MOTION_SHUTTER_CURVE[1:-1]:
        curve.points.new(x, y)
    cm.update()
    return keyed


def _fcurves(anim):
    """Blender 5 の層つきのアクションと、それより前のアクションの両方から F カーブを集める"""
    act = anim.action
    if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])) > 0:
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out.extend(bag.fcurves)
    return out


# ------------------------------------------------------------------ view layer・描画の Text

def view_layers():
    scn = bpy.context.scene
    md = bpy.data.materials.new("MAT_view_depth")       # カメラからの奥行き（ゲームの線形の奥行きと同じ）
    nt, out = fresh_tree(md)
    e = nt.nodes.new("ShaderNodeEmission")
    cd = nt.nodes.new("ShaderNodeCameraData")
    cc = nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        nt.links.new(cd.outputs["View Z Depth"], cc.inputs[i])
    nt.links.new(cc.outputs[0], e.inputs["Color"])
    nt.links.new(e.outputs[0], out.inputs["Surface"])
    base = scn.view_layers[0]
    setup = {   # show：見える、holdout：穴、indirect：影と照り返しだけ、exclude：無い
        "VL_chars": {"P1": "show", "P2": "show", "WALL": "holdout", "DECK": "holdout"},
        "VL_p2trail": {"P1": "holdout", "P2": "show", "WALL": "holdout", "DECK": "holdout"},
        "VL_wall": {"P1": "indirect", "P2": "indirect", "WALL": "show", "DECK": "holdout"},
        "VL_deck": {"P1": "indirect", "P2": "indirect", "WALL": "indirect", "DECK": "show"},
        "VL_depth": {"P1": "exclude", "P2": "exclude", "WALL": "show", "DECK": "show"},
    }
    if not any(o.get("motion_group") == "P2" for o in bpy.data.objects):
        del setup["VL_p2trail"]                 # 吹っ飛ぶプレイヤーがいない構図（t2 など）
    for name, modes in setup.items():
        vl = scn.view_layers.new(name)
        for lc in vl.layer_collection.children:
            mode = modes.get(lc.name, "show")
            lc.exclude = (mode == "exclude")
            if lc.exclude:
                continue
            lc.holdout = (mode == "holdout")
            lc.indirect_only = (mode == "indirect")
        vl.use_pass_combined = True
        vl.use = True
        if name == "VL_depth":
            vl.material_override = md
            vl.samples = 1
            vl.cycles.use_denoising = False
    base.use = False
    base.name = "VL_unused_default"
    return [vl.name for vl in scn.view_layers]


def render_text():
    src = os.path.join(HERE, "render_layers.py")
    txt = bpy.data.texts.get("thumb_render.py") or bpy.data.texts.new("thumb_render.py")
    txt.clear()
    txt.write(open(src, encoding="utf-8").read())


def look_through_camera():
    """作業の様子が見えるように、3D ビューをカメラの視点・材質の表示にする（できるときだけ）"""
    try:
        for area in bpy.context.window.screen.areas:
            if area.type == 'VIEW_3D':
                sp = area.spaces.active
                sp.region_3d.view_perspective = 'CAMERA'
                sp.shading.type = 'MATERIAL'
    except Exception:
        pass


# ------------------------------------------------------------------ まとめ

def build(shot, export_dir=None):
    export_dir = export_dir or find_export(shot)
    J = json.load(open(os.path.join(export_dir, "scene.json"), encoding="utf-8"))
    path = new_file(shot)
    res = {"file": path, "frame": J["frame"]}
    res["imported"] = import_foreground(export_dir)
    setup_camera(J)
    sun = setup_sun(J)
    res["sun_through"] = sun_through_first_wall(J, sun)
    res["ambient_linear"] = [round(c, 4) for c in setup_world(J)]
    setup_render()
    res["characters"] = len(character_materials())
    res["wall"] = wall_materials(J)
    res["deck"] = deck_materials(J, shot)
    res["labels"] = label_planes(shot)
    res["art"] = art_direction(shot, J, res["sun_through"])
    res["motion_blur"] = motion_blur(J)
    res["view_layers"] = view_layers()
    render_text()
    look_through_camera()
    bpy.context.scene["thumb_pipeline"] = "docs/pv/thumbnail/blender/README.md"
    try:
        bpy.ops.file.make_paths_relative()
    except Exception:
        pass
    bpy.ops.wm.save_mainfile()
    res["dirty"] = bpy.data.is_dirty
    return res
