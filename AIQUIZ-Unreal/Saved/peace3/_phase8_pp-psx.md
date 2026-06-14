# PP_PSX postprocess

## summary
Ported the Godot PSX post-process shader (addons/psx/shaders/psx_postprocess.gdshader) to a UE5.7 Post Process material M_PP_PSX. The Godot source does exactly two things in the fragment pass: a 4x4 Bayer ORDERED DITHER and a color-depth reduction (quantization to (1<<psx_bit_depth)-1 levels per channel; default bit_depth=5 -> 31 = 32 distinct levels). I reproduced the exact Bayer matrix and the exact quantization expression verbatim in a Custom-node HLSL function.

Key faithfulness points:
- Bayer matrix copied exactly: {0,8,2,10, 12,4,14,6, 3,11,1,9, 15,7,13,5}, indexed by index = (px&3) + (py&3)*4 using screen pixel coords (Godot FRAGCOORD.xy).
- Quantization math is verbatim: norm = BAYER[idx]/16; bit_levels = (1<<bd)-1; out = floor((color + norm/bit_levels)*bit_levels)/bit_levels.
- Godot's discard guard (bit_depth<=0 || >=8 -> pass through) preserved as `return SceneColor`.
- Added a DitherAmt scalar (psx_dither_amount, default 1.0) scaling only the dither offset; at 1.0 the math is identical to the original (extra knob, does not change default look).

NO FOG is in the post-process pass. Fog in this addon lives entirely in the per-surface shader (psx.gdshaderinc, VERTEX_FOG_* paths blending psx_fog_color into ALBEDO/EMISSION), so it is out of scope for this PP material and is intentionally not added here.

Approximations vs Godot:
- Godot SCREEN_TEXTURE is the final LDR display-space framebuffer (0..1, gamma-encoded). The closest UE equivalent is BlendableLocation = After Tonemapping, so the dither/quantize operates on tonemapped 0..1 color — set that way. "Before Tonemapping" would give linear HDR (>1, no gamma) and the 32-level quantization math would not match PSX banding. I saturate() SceneColor before quantizing to stay in 0..1 like the original framebuffer.
- PixelPos is built as ViewportUV * SceneTexture.Size to match FRAGCOORD.xy integer pixel coords; this means dither tiling follows UE's internal render resolution (not the Godot 1:1). If the driver wants pixelation to match a specific low internal res, set r.ScreenPercentage or a fixed Size constant.

## recipe
MATERIAL M_PP_PSX (/Game/AiQuiz/Materials/M_PP_PSX)
- Material Domain = Post Process.
- Blendable Location = After Tonemapping (BL_SCENE_COLOR_AFTER_TONEMAPPING). Rationale: Godot's canvas_item SCREEN_TEXTURE is the final LDR, gamma-encoded framebuffer in 0..1; "After Tonemapping" is the UE equivalent. "Before Tonemapping" (linear HDR) would NOT match the 32-level quantization banding. State for the driver: if you instead want it before the tonemapper for stylistic reasons, the quantization will look wrong on bright/HDR pixels.

NODE GRAPH (all created by the script):
1. SceneTexture node, scene_texture_id = PostProcessInput0 (the tonemapped scene color). Its default color output -> Custom input "SceneColor".
2. ScreenPosition node -> ViewportUV output (0..1) -> Multiply.A.
3. SceneTexture.Size output -> Multiply.B. Multiply result (= pixel coords, matches Godot FRAGCOORD.xy) -> Custom input "PixelPos". (Script falls back to a Constant2(1920,1080) if the Size output name differs on this engine build.)
4. CollectionParameter psx_bit_depth (from MPC_PSX) -> Custom input "BitDepth".
5. CollectionParameter psx_dither_amount (from MPC_PSX) -> Custom input "DitherAmt".
6. Custom node "PSX_DitherQuantize" (output_type = CMOT_FLOAT3) -> EmissiveColor (standard PP material output).

MPC_PSX (/Game/AiQuiz/Materials/MPC_PSX), scalar params with Godot defaults from project.godot [shader_globals]:
- psx_bit_depth = 5  (=> (1<<5)-1 = 31, i.e. 32 levels/channel)
- psx_dither_amount = 1.0 (1.0 == original look; 0.0 == quantize only, no dither)
Driving these at runtime via SetScalarParameterValue on MPC_PSX reproduces Godot's Psx.bit_depth setter.

POST PROCESS VOLUME (in /Game/AiQuiz/Maps/L_Game):
- Spawn an unbound PostProcessVolume labeled "PPV_PSX" (bUnbound = true so it covers the whole scene like a global post-process), Priority = 1.0.
- Register M_PP_PSX as a Weighted Blendable (weight = 1.0) in Settings.WeightedBlendables.
- Save L_Game.
The script removes any prior "PPV_PSX" first so re-runs don't stack volumes.

APPLIED WHERE: global, full-screen — it runs on the final image of L_Game for every camera, exactly like Godot's full-screen psx_postprocess pass.

## risks
NEEDS EDITOR/VISUAL VERIFICATION (could not run the editor):
1. API enum/property names may differ on this exact UE 5.7 build and need driver fixups:
   - BlendableLocation enum: tried BL_SCENE_COLOR_AFTER_TONEMAPPING then BL_AFTER_TONEMAPPING. One should exist; verify in the material's Post Process Material > Blendable Location dropdown that it reads "After Tonemapping".
   - SceneTexture Size output pin name: I try "Size" (and fall back to a 1920x1080 constant). On 5.7 SceneTexture exposes Color/Size/InvSize multi-outputs; if connect_material_expressions can't resolve "Size" by name the fallback constant is used — then dither tiling is locked to 1920x1080 instead of true viewport size. Confirm PixelPos is wired to the real Size output.
   - MaterialExpressionCollectionParameter requires the MPC + a valid parameter_name; if the property names differ the node may end up unbound. Verify psx_bit_depth/psx_dither_amount feed the Custom node.
2. PostProcessVolume blendable registration via Settings.WeightedBlendables (FWeightedBlendables struct with an "array" of FWeightedBlendable{weight, object}) is the part most likely to need adjustment in Python — struct field names ("weighted_blendables", "array", "object", "weight") can vary. If it fails, the script records blendable_err and the driver should add M_PP_PSX to the volume's Post Process Materials list manually, or set ppv.add_or_update_blendable(mat, 1.0) if that helper exists on this build.
3. After Tonemapping is my best match for Godot's LDR SCREEN_TEXTURE, but it is a judgment call — visually compare against the Godot reference. If banding looks washed out, try the "Replacing the Tonemapper" location; if too crushed, the saturate() can be removed. This is exactly the "見た目の8割" target, so a side-by-side screenshot in L_Game (PIE) is the real acceptance test.
4. The Custom HLSL bit-shift (1 << bd) and int2 bit-AND (p & 3) are valid HLSL but UE may emit warnings about int ops in a Custom node; harmless. Negative PixelPos (offscreen) can't occur for PP input so floor()+&3 stays correct.
5. Fog: deliberately NOT in this PP material (Godot fog is per-surface in psx.gdshaderinc). If the plan expects a screen-space fog tint here, that is a separate task and is flagged as out of scope.

## hlsl
```hlsl
// --- Godot PSX ORDERED DITHER + COLOR DEPTH REDUCTION (psx_postprocess.gdshader) ---
// Custom node inputs: SceneColor (float3), PixelPos (float2 = ViewportUV*ViewSize,
//                     = Godot FRAGCOORD.xy), BitDepth (float), DitherAmt (float).
// Output type: CMOT_FLOAT3.
// 4x4 Bayer matrix (PSX_DITHER_MATRIX) — identical ordering to Godot.
const float BAYER[16] = {
     0.0,  8.0,  2.0, 10.0,
    12.0,  4.0, 14.0,  6.0,
     3.0, 11.0,  1.0,  9.0,
    15.0,  7.0, 13.0,  5.0 };

int bd = (int)(BitDepth + 0.5);
// Godot original: bit_depth<=0 || >=8 -> discard (pass through unchanged).
if (bd <= 0 || bd >= 8) { return SceneColor; }

// p = ivec2(floor(uv)); xi = p.x & 3; yi = p.y & 3; index = xi + yi*4
int2 p  = (int2)floor(PixelPos);
int xi  = p.x & 3;
int yi  = p.y & 3;
int idx = xi + yi * 4;

float norm       = BAYER[idx] / 16.0;            // 0 .. 15/16
float bit_levels = (float)((1 << bd) - 1);       // bd=5 -> 31

// out = floor((color + (norm*DitherAmt)/bit_levels) * bit_levels) / bit_levels
float3 c = saturate(SceneColor);                 // clamp to 0..1 display range like a PSX framebuffer
float3 outc = floor((c + (norm * DitherAmt) / bit_levels) * bit_levels) / bit_levels;
return outc;
```
