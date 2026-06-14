# M_PSX_Surface

## summary
Ported the Godot PSX SURFACE include (addons/psx/shaders/psx.gdshaderinc + psx_template.gdshader) to a UE opaque Unlit surface material M_PSX_Surface. Reproduced: (1) clip/view-space XY+Z vertex QUANTIZATION via a World-Position-Offset Custom HLSL node that returns a world-space WPO delta; (2) an affine-ish "wobbly" UV approximation; (3) low-spec / unlit-ish shading. Approximations vs the Godot original: (a) Godot snaps in MODELVIEW (object+view) space using inverse(MODELVIEW); UE does the snap in World->View space using ResolvedView matrices. The snap grid is camera-relative either way, so the visible PSX jitter is equivalent, but per-object pivot framing differs slightly. (b) True affine (perspective-incorrect) UV interpolation cannot be toggled in UE's fixed interpolators, so the "texture wobble" is instead produced by the WPO vertex snap itself (which destabilizes the projected UVs exactly like PSX) plus an optional UV-quantize Custom node (trunc(UV*PrecisionUV)/PrecisionUV). Since M_PSX_Surface currently uses a single VectorParameter "Color" (no texture), the UV-quantize node is built but left unconnected, ready for a textured variant. (c) Godot multiplies albedo by vertex COLOR; that is dropped because the project's block-human meshes use flat MID color, matching M_Blockman. The material is Unlit, opaque, two-sided OFF, with Color routed to EmissiveColor so it is MID/MIC-drivable exactly like M_Blockman. Applying it to stage/wall/pawn meshes is OPTIONAL (driver decides) — the project currently keeps M_Blockman.

## recipe
Material: /Game/AiQuiz/Materials/M_PSX_Surface (unreal.Material, MaterialFactoryNew).
Domain/flags: Material Domain = Surface; Shading Model = Unlit (MSM_UNLIT) for low-spec shading (Godot set SPECULAR=ROUGHNESS=METALLIC=0); Blend Mode = Opaque; Two Sided = OFF.

Companion asset: /Game/AiQuiz/Materials/MPC_PSX (MaterialParameterCollection) with 4 scalar params controlling PSX quantization globally:
  - PrecisionXY (default 80) = clip/view-space XY snap grid resolution (Godot psx_precision_xy). Lower = coarser jitter.
  - PrecisionZ  (default 80) = depth snap resolution (Godot psx_precision_z).
  - AffineStrength (default 1.0) = affine UV / wobble strength 0..1 (Godot psx_affine_strength).
  - PrecisionUV (default 64) = fragment UV quantize resolution (Godot psx_precision_uv).

Node graph:
1) VectorParameter "Color" (default RGBA 0.85,0.48,0.18,1.0) -> ComponentMask(RGB) -> EmissiveColor (Unlit, so emissive = final color; named/used as the BaseColor param, MID-driven like M_Blockman's "Color").
2) WorldPosition node (Absolute World Position) -> Custom node "PSX_VertexSnap_WPO" input WorldPos.
3) MPC_PSX CollectionParameter "PrecisionXY" -> Custom input PrecisionXY; CollectionParameter "PrecisionZ" -> Custom input PrecisionZ.
4) Custom node output (Float3 WPO delta, world space) -> World Position Offset.
5) (Optional, built but unconnected) TextureCoordinate -> Custom node "PSX_UV_Quantize" (UV, PrecisionUV from MPC) -> Float2 quantized UV, ready to drive a texture sampler's UVs in a textured PSX variant.

Custom WPO node config: inputs = [WorldPos(float3), PrecisionXY(float), PrecisionZ(float)]; output_type = CMOT_FLOAT3; description = "PSX_VertexSnap_WPO".

Snap resolution params live on MPC_PSX so all PSX-surfaced meshes share one knob. The Color param is a per-material/per-MID VectorParameter (create a MaterialInstanceConstant child and set Color, mirroring MI_BM_* in p5_blockman.py) to recolor stage/wall/pawn boxes.

Application: OPTIONAL. To apply, assign M_PSX_Surface (or a MID/MIC of it with Color set) to the StaticMeshComponent material slot of stage/wall/pawn boxes in /Game/AiQuiz/Maps/L_Game, replacing M_Blockman/MI_BM_*. Driver decides whether to swap; default leaves M_Blockman in place.

## risks
Needs headless run + visual verification; I could not run the editor. Specific uncertainties:

1) ResolvedView member names in a Custom node. ResolvedView.TranslatedWorldToView, ViewToTranslatedWorld, ViewToClip, and PreViewTranslation are the standard UE5 view-uniform names, but exact spelling can drift between engine versions and a Custom node sometimes needs LWC-aware accessors. If compilation fails, swap to the engine helper functions: use GetWorldToView()/SVPositionToScreenPosition or feed the matrices via TransformPosition material nodes (World->View) into the Custom node as inputs instead of reading ResolvedView directly. Verify it compiles in UE 5.7.

2) View-space depth sign / handedness. I assumed viewPos.z is positive in front of the camera (so clip_depth = depth*fov > 0). If UE's view Z is negative-forward in 5.7, clip_depth flips sign — the snap still works (trunc symmetric-ish) but PrecisionXY tuning may invert. Confirm visually that geometry jitters rather than disappears; if it collapses, negate depth.

3) WorldPosition node in the WPO context. WPO evaluates pre-deformation; the WorldPosition node should give the un-offset absolute world vertex pos, but under Nanite/LWC the absolute-vs-tile semantics can shift. If vertices fly off, feed a known-good position via the standard WPO "Absolute World Position" and re-test.

4) Affine UV fidelity. This is an approximation, NOT true affine interpolation — UE perspective-corrects interpolators and there is no per-material toggle to disable it. The PSX texture wobble here comes from the WPO snap (real) plus optional UV quantization (built, unconnected). On the current flat-color material there is no texture, so the affine effect is essentially carried by vertex snap only; a textured variant is needed to judge the swim.

5) MPC_PSX may not yet exist and the factory class name (MaterialParameterCollectionFactoryNew) can vary; the script has a fallback but the driver should confirm the MPC and its 4 scalars actually serialized.

6) PrecisionXY/Z defaults (80) are guesses for UE's scale; the Godot values are scene-tuned. Expect to dial PrecisionXY down (coarser) for visible PSX jitter at the project's camera distance.

7) Unlit means the material ignores stage lighting/specular entirely (matches Godot SPECULAR=ROUGHNESS=METALLIC=0 intent) but will look flatter than M_Blockman (DefaultLit, roughness 0.7). If the driver wants subtle shading, switch shading_model to DefaultLit and add Constant roughness ~0.9 + specular 0; route Color to BaseColor instead of EmissiveColor.

8) Vertex-color albedo from Godot (u_vertex_color_use_as_albedo) is intentionally dropped; the box meshes have no meaningful vertex color and the project drives color via MID, so this is a deliberate simplification, not a bug.

Application to stage/wall/pawn meshes is left OPTIONAL per the task; the script only creates the asset and does not reassign any level mesh materials.

## hlsl
```hlsl
// --- PSX clip-space vertex snap -> world-space WPO delta ---
// WorldPos: absolute world position of the vertex (LWC-tile-relative float3 ok here)
// PrecisionXY / PrecisionZ: snap grid resolution (0 = axis disabled)
// Inputs: WorldPos(float3), PrecisionXY(float), PrecisionZ(float). Output: float3 (CMOT_FLOAT3).
// Port of psx.gdshaderinc vertex() XY/Z quantization. Godot snapped in MODELVIEW space;
// UE snaps in World->View space via ResolvedView (camera-relative grid is equivalent).

// World -> translated world (UE view matrices are in translated world space).
float3 twPos = WorldPos + ResolvedView.PreViewTranslation;

// World -> View. ResolvedView.TranslatedWorldToView is row-major float4x4.
float4 viewPos = mul(float4(twPos, 1.0), ResolvedView.TranslatedWorldToView);

// fov from projection: P[1][1] = 1/tan(fovY/2); Godot: fov = 2*atan(1/P[1][1]).
float p11 = ResolvedView.ViewToClip[1][1];
float fov = 2.0 * atan(1.0 / p11);

// UE view space: camera looks down +Z, viewPos.z positive in front -> matches Godot
// using v_clip.z as the depth scale.
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
```
