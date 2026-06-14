# Fog + MPC_PSX

## summary
Ported AIQUIZ's dense PSX fog and shared PSX shader params into UE. Source-verified the exact Godot values from addons/psx/scripts/Psx.gd (GLOBAL_VARS), addons/psx/scripts/PsxWorldEnvironment.gd, addons/psx/shaders/psx.gdshaderinc + psx_postprocess.gdshader, scripts/world/stage_environment.gd, and scripts/world/stage_constants.gd. Two deliverables: (1) MPC_PSX MaterialParameterCollection holding the shared PSX constants with Godot defaults, and (2) a dense ExponentialHeightFog on L_Game emulating Godot's near10m->far20m linear fog with BG_COLOR (0.82,0.85,0.90) inscattering.

Key Godot-source facts that drove the mapping:
- The literal Psx.gd default psx_fog_color is (0.5,0.5,0.5,0), but at runtime PsxWorldEnvironment.gd feeds Psx.fog_color = environment.fog_light_color, which StageEnvironment sets to StageConstants.BG_COLOR = (0.82,0.85,0.90). So the scene fog color the task references is (0.82,0.85,0.90) — that is what I used for both MPC_PSX.fog_color and the ExponentialHeightFog inscattering. The literal 0.5 grey is only the unused fallback.
- psx_fog_near=10.0, psx_fog_far=20.0 are in Godot meters; UE convention (plan §1.4, UU=100) -> 1000 UU / 2000 UU.
- bit_depth=5 (int), affine_strength=1.0, precision_uv=128, precision_xy=256, precision_z=512 from GLOBAL_VARS.
- "dither_amount" and "snap_resolution" are not literal Godot uniform names. I mapped dither_amount=1.0 (Bayer dither is unconditionally on in psx_postprocess.gdshader, gated only by bit_depth) and snap_resolution=256.0 (= psx_precision_xy, the clip-space XY vertex quantization used by M_PSX_Surface's WPO snap).

Approximations vs original: Godot's PSX fog is a per-vertex LINEAR blend (strength = clamp((depth-near)/(far-near),0,1)) done inside the surface shader; UE's ExponentialHeightFog is exponential, so the falloff curve differs. I tuned FogDensity=0.02 / HeightFalloff=0.05 / StartDistance=0 for a close, dense haze that visually matches. For a truly faithful linear near/far fog you would instead drive M_PSX_Surface from MPC_PSX.fog_near/fog_far/fog_color (that material is a separate task); the ExponentialHeightFog here is the atmospheric approximation requested.

## recipe
DOMAIN A — MPC_PSX (MaterialParameterCollection), /Game/AiQuiz/Materials/MPC_PSX
Scalar parameters (name = default, with Godot origin):
- bit_depth = 5.0        (Psx.gd psx_bit_depth=5; PP_PSX color quantization to (1<<5)-1=31 levels)
- dither_amount = 1.0    (psx_postprocess.gdshader 4x4 Bayer dither, always on)
- snap_resolution = 256.0(Psx.gd psx_precision_xy=256; M_PSX_Surface clip-space XY vertex snap)
- fog_near = 1000.0      (Godot psx_fog_near 10m * 100)
- fog_far = 2000.0       (Godot psx_fog_far 20m * 100)
- affine_strength = 1.0  (psx_affine_strength=1.0; affine UV interpolation amount) [aux]
- precision_uv = 128.0   (psx_precision_uv; UV truncation in fragment) [aux]
- precision_z = 512.0    (psx_precision_z; clip-space Z snap) [aux]
Vector parameters:
- fog_color = (0.82, 0.85, 0.90, 1.0)  (StageConstants.BG_COLOR, the runtime fog_light_color)
PP_PSX should reference bit_depth + dither_amount; M_PSX_Surface should reference snap_resolution + affine_strength + fog_near/fog_far/fog_color. Reference from a material via a "Collection Parameter" node pointing at MPC_PSX.

DOMAIN B — ExponentialHeightFog actor on /Game/AiQuiz/Maps/L_Game (label "Stage_Fog", reuse the one step4_fog.py made; location ~ (400,0,-100)):
ExponentialHeightFogComponent settings:
- FogDensity = 0.02            (dense; floor/walls start hazing ~150 UU out)
- FogHeightFalloff = 0.05      (nearly uniform vertically; runner lives around Z=-120..up)
- StartDistance = 0.0          (fog begins right in front of the Pawn, matching near~0-10m)
- FogMaxOpacity = 1.0          (allow full saturation by far~2000 UU)
- FogInscatteringLuminance (UE5.7) / FogInscatteringColor (older) = (0.82,0.85,0.90) — script tries both names
- DirectionalInscatteringColor = (0,0,0), DirectionalInscatteringExponent = 4.0 (kill sun-shaft tint -> flat PSX haze)
How near10/far20 is emulated: Godot uses a LINEAR vertex-fog ramp from near=1000 UU to fully-fogged at far=2000 UU. UE exponential fog can't reproduce that exactly; FogDensity 0.02 with StartDistance 0 gives transmittance ~exp(-0.02*d) so the scene reads near-opaque well before 2000 UU, giving the same "very dense, very close" look. If a faithful linear ramp is needed, drive M_PSX_Surface from MPC_PSX.fog_near/fog_far/fog_color instead (separate task).
Then LevelEditorSubsystem.save_current_level().

## risks
1) MaterialParameterCollection API surface: I used unreal.MaterialParameterCollectionFactoryNew + AssetTools.create_asset, then set scalar_parameters / vector_parameters as arrays of CollectionScalarParameter / CollectionVectorParameter structs with parameter_name + default_value. This is the standard UE Python pattern but exact struct field names should be confirmed against UE 5.7 (set_editor_property will raise if a name differs; the driver can adjust). No prior MPC script existed in peace3 to copy from.

2) Inscattering color property name differs across UE versions (FogInscatteringLuminance in newer 5.x vs FogInscatteringColor older). step4_fog.py already handles this both-names fallback and I copied that pattern, so it is low risk.

3) Fog density/falloff (0.02 / 0.05 / StartDistance 0) is a visual approximation of Godot's LINEAR near10/far20 ramp using UE's EXPONENTIAL fog — the curve shape differs and the exact "very dense, close" feel needs editor-GUI / screenshot verification against the Godot reference. step4_fog.py previously used 0.015 density; I increased to 0.02 for the requested density. Tune in-editor if too thick/thin. A faithful linear reproduction would require driving M_PSX_Surface from MPC_PSX.fog_near/fog_far instead, which is a separate material task.

4) fog_color source ambiguity: the literal Psx.gd default psx_fog_color is grey (0.5,0.5,0.5,0); the ACTUAL runtime color is BG_COLOR (0.82,0.85,0.90) injected by PsxWorldEnvironment.gd. I used (0.82,0.85,0.90) per the task spec and §3.3 of the plan. If the driver instead wants the raw uninitialized default, change MPC_PSX.fog_color to (0.5,0.5,0.5).

5) An existing Stage_Fog actor (from step4_fog.py) is reused rather than duplicated; if the level currently has no Stage_Fog the script spawns one. Verify only one ExponentialHeightFog ends up in L_Game.

6) The dither_amount and snap_resolution scalar names are my mapping (not literal Godot uniform names) — confirm PP_PSX / M_PSX_Surface authors expect exactly these param names when wiring Collection Parameter nodes.

## hlsl
```hlsl

```
