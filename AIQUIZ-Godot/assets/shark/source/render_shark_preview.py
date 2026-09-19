"""Render the saved editable clips, in a separate background Blender."""
import bpy
from pathlib import Path

OUT = Path(__file__).resolve().parents[3] / 'artifacts' / 'shark_rig_rebuild'
for scene_name, folder in [('01_SharkSwim', 'swim'), ('02_SharkBite', 'bite')]:
    scene = bpy.data.scenes[scene_name]
    bpy.context.window.scene = scene
    scene.render.resolution_x, scene.render.resolution_y = 768, 432
    scene.eevee.taa_render_samples = 24
    (OUT / folder).mkdir(parents=True, exist_ok=True)
    for frame in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(frame)
        scene.render.filepath = str(OUT / folder / f'{frame:04}.png')
        bpy.ops.render.render(write_still=True, scene=scene.name)
