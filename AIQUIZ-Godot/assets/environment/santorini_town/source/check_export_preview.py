"""Independent glTF round-trip visual QA; never saves or changes the GLB/source."""
import bpy
from mathutils import Vector
from pathlib import Path
source=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(source/'aiquiz_santorini_town.blend'))
scene=bpy.data.scenes['AIQUIZ | Santorini Caldera Town'];bpy.context.window.scene=scene
bpy.data.collections['EXPORT | Town districts and cliff terrain'].hide_render=True
bpy.context.view_layer.active_layer_collection=bpy.context.view_layer.layer_collection
bpy.ops.import_scene.gltf(filepath=str(source.parent/'aiquiz_santorini_town.glb'))
cam=scene.camera;cam.data.clip_end=10000;cam.data.lens=50
cam.location=(185,158,77);cam.rotation_euler=(Vector((130,306,39))-cam.location).to_track_quat('-Z','Y').to_euler()
bpy.context.view_layer.update()
scene.render.filepath=str(source/'previews'/'glb_roundtrip_rear.png')
bpy.ops.render.render(write_still=True,scene=scene.name)
print('ROUNDTRIP_EXPORT_PREVIEW_COMPLETE',flush=True)
