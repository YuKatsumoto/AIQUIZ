import unreal
BASE=r"C:/AIQUIZ/AIQUIZ-Unreal/Saved/peace3"
ues=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
world=ues.get_editor_world()
eal=unreal.EditorAssetLibrary
mi=eal.load_asset("/Game/AiQuiz/Materials/MI_Magma")
rt=unreal.RenderingLibrary.create_render_target2d(world,512,512,unreal.TextureRenderTargetFormat.RTF_RGBA16F,unreal.LinearColor(0,0,0,1),False)
unreal.RenderingLibrary.draw_material_to_render_target(world, rt, mi)
unreal.RenderingLibrary.export_render_target(world, rt, BASE, "magma_uv.png")
# sample a few pixels
for (px,py) in [(256,256),(128,128),(400,300),(64,450)]:
    c=unreal.RenderingLibrary.read_render_target_raw_pixel(world, rt, px, py)
    print("PIXEL",px,py,"=",c.r,c.g,c.b)
print("done")
