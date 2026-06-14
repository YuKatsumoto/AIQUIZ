# -*- coding: utf-8 -*-
"""Phase 8: Godot PSX SURFACE shader (addons/psx/shaders/psx.gdshaderinc) ported
to a UE opaque surface material M_PSX_Surface.

Reproduces:
  1) Clip-space XY/Z vertex QUANTIZATION (snap) implemented as a World Position
     Offset Custom node. Godot: v_clip.xy = trunc((v_clip.xy/clip_depth)*precXY)
     * clip_depth/precXY (and the Z analog), ported as a world-space WPO delta.
  2) Affine ("wobbly") UV approximation. UE interpolators are perspective-correct
     and cannot be made affine in fixed-function, so the WPO vertex snap itself
     destabilizes the projected UV (the PSX texel swim) and an optional
     UV-quantize Custom node (trunc(UV*PrecisionUV)/PrecisionUV) is provided for a
     textured variant. This material is a flat VectorParameter color, so the
     UV-quantize node is built but left unconnected.
  3) Low-spec (unlit) shading. Godot set SPECULAR=ROUGHNESS=METALLIC=0 + vertex
     color; here we use Unlit and route the "Color" VectorParameter to
     EmissiveColor so it is MID/MIC-drivable like M_Blockman.

Snap resolution params (MPC_PSX scalars):
  PrecisionXY (Godot psx_precision_xy), PrecisionZ (psx_precision_z),
  AffineStrength (psx_affine_strength), PrecisionUV (psx_precision_uv).

Style follows p5_import.py / p7_config_bp.py / magma_debug.py; prints RESULT json.
"""
import unreal
import json
import traceback

MAT_DIR = "/Game/AiQuiz/Materials"
MAT_NAME = "M_PSX_Surface"
MAT_PATH = MAT_DIR + "/" + MAT_NAME
MPC_DIR = "/Game/AiQuiz/Materials"
MPC_NAME = "MPC_PSX"
MPC_PATH = MPC_DIR + "/" + MPC_NAME

# WPO Custom node HLSL: clip/view-space vertex snap -> world-space WPO delta.
WPO_HLSL = r"""// --- PSX clip-space vertex snap -> world-space WPO delta ---
// WorldPos: absolute world position of the vertex (LWC-tile-relative float3 ok here)
// PrecisionXY / PrecisionZ: snap grid resolution (0 = axis disabled)

// World -> translated world (UE view matrices are in translated world space).
float3 twPos = WorldPos + ResolvedView.PreViewTranslation;

// World -> View. ResolvedView.TranslatedWorldToView is row-major float4x4.
float4 viewPos = mul(float4(twPos, 1.0), ResolvedView.TranslatedWorldToView);

// fov from projection: P[1][1] = 1/tan(fovY/2); Godot: fov = 2*atan(1/P[1][1]).
float p11 = ResolvedView.ViewToClip[1][1];
float fov = 2.0 * atan(1.0 / p11);

// In UE view space the camera looks down +Z and depth (viewPos.z) is positive in
// front of the camera, matching Godot's use of v_clip.z as a depth scale.
float depth = viewPos.z;
float clip_depth = depth * fov;

float3 snapped = viewPos.xyz;

// XY snap: quantize depth-normalized XY to a low-res grid, then rescale by depth.
if (PrecisionXY != 0.0 && clip_depth != 0.0)
{
    snapped.xy = trunc((viewPos.xy / clip_depth) * PrecisionXY) * clip_depth / PrecisionXY;
}
// Z (depth) snap.
if (PrecisionZ != 0.0 && fov != 0.0)
{
    snapped.z = trunc((viewPos.z / fov) * PrecisionZ) * fov / PrecisionZ;
}

// View -> translated world -> world.
float4 snappedTW = mul(float4(snapped, 1.0), ResolvedView.ViewToTranslatedWorld);
float3 snappedWorld = snappedTW.xyz - ResolvedView.PreViewTranslation;

// WPO is the delta from the original world position.
return snappedWorld - WorldPos;
"""

out = {"ok": False, "log": []}
L = out["log"].append
MEL = unreal.MaterialEditingLibrary
eal = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()


def E(mat, cls, x, y):
    return MEL.create_material_expression(mat, cls, x, y)


def ci(name):
    c = unreal.CustomInput()
    c.set_editor_property("input_name", name)
    return c


try:
    # 1) MPC_PSX : PSX quantization resolution params (project-wide knob).
    SCALARS = {
        "PrecisionXY": 80.0,
        "PrecisionZ": 80.0,
        "AffineStrength": 1.0,
        "PrecisionUV": 64.0,
    }
    mpc = None
    if eal.does_asset_exist(MPC_PATH):
        mpc = eal.load_asset(MPC_PATH)
        L("MPC exists")
    else:
        try:
            fac = unreal.MaterialParameterCollectionFactoryNew()
        except Exception:
            fac = unreal.MaterialParameterCollectionFactory()
        mpc = at.create_asset(MPC_NAME, MPC_DIR,
                              unreal.MaterialParameterCollection, fac)
        L("MPC created")

    if mpc is not None:
        existing = mpc.get_editor_property("scalar_parameters")
        have = set()
        for p in existing:
            try:
                have.add(str(p.get_editor_property("parameter_name")))
            except Exception:
                pass
        new_list = list(existing)
        for nm, dv in SCALARS.items():
            if nm in have:
                continue
            sp = unreal.CollectionScalarParameter()
            sp.set_editor_property("parameter_name", nm)
            sp.set_editor_property("default_value", dv)
            new_list.append(sp)
            L("MPC add scalar %s=%s" % (nm, dv))
        mpc.set_editor_property("scalar_parameters", new_list)
        eal.save_loaded_asset(mpc)
    out["mpc"] = MPC_PATH

    # 2) M_PSX_Surface material.
    mat = None
    if eal.does_asset_exist(MAT_PATH):
        mat = eal.load_asset(MAT_PATH)
        MEL.delete_all_material_expressions(mat)
        L("material exists -> cleared expressions")
    else:
        mat = at.create_asset(MAT_NAME, MAT_DIR, unreal.Material,
                              unreal.MaterialFactoryNew())
        L("material created")

    # Low-spec shading: Unlit / opaque / single-sided.
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_OPAQUE)
    mat.set_editor_property("two_sided", False)

    # BaseColor: VectorParameter "Color" (same name as M_Blockman, MID-drivable).
    col = E(mat, unreal.MaterialExpressionVectorParameter, -520, -40)
    col.set_editor_property("parameter_name", "Color")
    col.set_editor_property("default_value", unreal.LinearColor(0.85, 0.48, 0.18, 1.0))
    col_mask = E(mat, unreal.MaterialExpressionComponentMask, -300, -40)
    col_mask.set_editor_property("r", True)
    col_mask.set_editor_property("g", True)
    col_mask.set_editor_property("b", True)
    col_mask.set_editor_property("a", False)
    MEL.connect_material_expressions(col, "", col_mask, "")
    # Unlit -> color goes to EmissiveColor (final unlit output).
    MEL.connect_material_property(col_mask, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    L("Color VectorParameter wired to emissive (unlit base color)")

    # Snap resolutions from MPC.
    precXY_node = E(mat, unreal.MaterialExpressionCollectionParameter, -900, 360)
    precXY_node.set_editor_property("collection", mpc)
    precXY_node.set_editor_property("parameter_name", "PrecisionXY")
    precZ_node = E(mat, unreal.MaterialExpressionCollectionParameter, -900, 470)
    precZ_node.set_editor_property("collection", mpc)
    precZ_node.set_editor_property("parameter_name", "PrecisionZ")
    L("collection parameters PrecisionXY / PrecisionZ created")

    # WorldPosition (absolute).
    wpos = E(mat, unreal.MaterialExpressionWorldPosition, -900, 250)
    try:
        wpos.set_editor_property("world_position_shader_offset",
                                 unreal.MaterialPositionTransformSource.ABSOLUTE_WORLD_POSITION)
    except Exception:
        pass

    # WPO Custom node.
    wpo = E(mat, unreal.MaterialExpressionCustom, -560, 320)
    wpo.set_editor_property("description", "PSX_VertexSnap_WPO")
    wpo.set_editor_property("inputs", [ci("WorldPos"), ci("PrecisionXY"), ci("PrecisionZ")])
    wpo.set_editor_property("code", WPO_HLSL)
    wpo.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT3)
    MEL.connect_material_expressions(wpos, "", wpo, "WorldPos")
    MEL.connect_material_expressions(precXY_node, "", wpo, "PrecisionXY")
    MEL.connect_material_expressions(precZ_node, "", wpo, "PrecisionZ")
    MEL.connect_material_property(wpo, "", unreal.MaterialProperty.MP_WORLD_POSITION_OFFSET)
    L("WPO custom node wired to MP_WORLD_POSITION_OFFSET")

    # Optional affine-ish UV quantize (unconnected; ready for textured variant).
    uv_node = E(mat, unreal.MaterialExpressionTextureCoordinate, -900, 600)
    precUV_node = E(mat, unreal.MaterialExpressionCollectionParameter, -900, 700)
    precUV_node.set_editor_property("collection", mpc)
    precUV_node.set_editor_property("parameter_name", "PrecisionUV")
    uvq = E(mat, unreal.MaterialExpressionCustom, -560, 620)
    uvq.set_editor_property("description", "PSX_UV_Quantize")
    uvq.set_editor_property("inputs", [ci("UV"), ci("PrecisionUV")])
    uvq.set_editor_property(
        "code",
        "// affine-ish PSX texel swim: quantize UV to a low-res grid.\n"
        "if (PrecisionUV == 0.0) return UV;\n"
        "return trunc(UV * PrecisionUV) / PrecisionUV;\n")
    uvq.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT2)
    MEL.connect_material_expressions(uv_node, "", uvq, "UV")
    MEL.connect_material_expressions(precUV_node, "", uvq, "PrecisionUV")
    L("UV-quantize custom node created (unconnected; ready for textured variant)")

    MEL.recompile_material(mat)
    eal.save_asset(MAT_PATH, only_if_is_dirty=False)
    L("material recompiled + saved")

    out["material"] = MAT_PATH
    out["shading_model"] = "Unlit"
    out["params"] = {"vector": ["Color"], "mpc_scalars": list(SCALARS.keys())}
    out["ok"] = True
except Exception as e:
    out["err"] = str(e)
    out["tb"] = traceback.format_exc()

print("RESULT " + json.dumps(out, ensure_ascii=False))
