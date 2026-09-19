"""Create separate, ready-to-play Blender scenes for the two shark clips."""
import bpy
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve().parent


def setup():
    swim = bpy.context.scene
    swim.name = '01_SharkSwim'
    rig = bpy.data.objects['shark_armature']
    mesh = bpy.data.objects['SK_Shark.001']
    rig.animation_data.action = bpy.data.actions['SharkSwim']
    rig.animation_data.action_slot = rig.animation_data.action.slots[0]
    # Clear presentation objects owned by this script when rerunning it.
    for obj in list(bpy.data.objects):
        if obj.name.startswith(('PREVIEW_', 'BitePreview_')):
            bpy.data.objects.remove(obj, do_unlink=True)
    old_bite = bpy.data.scenes.get('02_SharkBite')
    if old_bite:
        bpy.data.scenes.remove(old_bite)
    world = bpy.data.worlds.get('SharkPreviewWorld') or bpy.data.worlds.new('SharkPreviewWorld')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = (0.028, 0.048, 0.075, 1)
    bg.inputs['Strength'].default_value = 0.4
    swim.world = world
    cam_data = bpy.data.cameras.new('PREVIEW_Camera')
    cam = bpy.data.objects.new('PREVIEW_Camera', cam_data)
    swim.collection.objects.link(cam)
    cam.location = (2.0, -18.0, 4.5)
    cam.rotation_euler = (Vector((0, 0, -0.12)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 10.8
    cam_data.lens = 50
    swim.camera = cam
    for name, location, energy, size in [
        ('PREVIEW_Key', (0, -6, 8), 1800, 8),
        ('PREVIEW_Fill', (4, 4, 3), 950, 7),
    ]:
        ld = bpy.data.lights.new(name, 'AREA')
        ld.energy, ld.shape, ld.size = energy, 'DISK', size
        lo = bpy.data.objects.new(name, ld)
        swim.collection.objects.link(lo)
        lo.location = location
        lo.rotation_euler = (-lo.location).to_track_quat('-Z', 'Y').to_euler()
    bite = bpy.data.scenes.new('02_SharkBite')
    bite.world, bite.camera = world, cam
    for o in swim.objects:
        if o.name.startswith('PREVIEW_'):
            bite.collection.objects.link(o)
    bite_rig = rig.copy()
    bite_rig.data = rig.data.copy()
    bite_rig.name = 'BitePreview_Rig'
    bite.collection.objects.link(bite_rig)
    bite_rig.animation_data.action = bpy.data.actions['SharkBite']
    bite_rig.animation_data.action_slot = bite_rig.animation_data.action.slots[0]
    bite_mesh = mesh.copy()
    bite_mesh.name = 'BitePreview_Shark'
    bite_mesh.parent = bite_rig
    bite.collection.objects.link(bite_mesh)
    for mod in bite_mesh.modifiers:
        if mod.type == 'ARMATURE':
            mod.object = bite_rig
    for sc, end in [(swim, 48), (bite, 13)]:
        sc.render.engine = 'BLENDER_EEVEE'
        sc.render.resolution_x, sc.render.resolution_y = 960, 540
        sc.render.resolution_percentage = 100
        sc.render.fps = 30
        sc.render.image_settings.file_format = 'PNG'
        sc.render.film_transparent = False
        sc.view_settings.view_transform = 'AgX'
        sc.frame_start, sc.frame_end = 1, end
        sc.timeline_markers.clear()
        for name, frame in ([('SWIM LOOP START', 1), ('LEFT', 13), ('RIGHT', 37)] if sc == swim else
                            [('REST', 1), ('WINDUP', 3), ('STRIKE', 5), ('FOLLOW THROUGH', 7), ('RECOVER', 13)]):
            sc.timeline_markers.new(name, frame=frame)
        sc.frame_set(1)
    for o in swim.objects:
        if o.name.startswith('SharkSaddle_'):
            o.hide_set(True)
            # Preview rendering only. The export script restores this flag
            # temporarily when exporting the shared runtime asset.
            o.hide_render = True
    bpy.context.window.scene = swim
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    for a in bpy.context.screen.areas:
        if a.type == 'VIEW_3D':
            a.spaces.active.region_3d.view_rotation = cam.rotation_euler.to_quaternion()
            a.spaces.active.region_3d.view_location = Vector((0, 0, -0.12))
            a.spaces.active.region_3d.view_distance = 12
            a.spaces.active.region_3d.view_perspective = 'ORTHO'
            a.spaces.active.shading.type = 'MATERIAL'
            a.spaces.active.overlay.show_overlays = True
            a.spaces.active.overlay.show_floor = False
            a.spaces.active.overlay.show_extras = False
        elif a.type == 'DOPESHEET_EDITOR':
            a.ui_type = 'DOPESHEET'
            a.spaces.active.mode = 'ACTION'
            region = next(r for r in a.regions if r.type == 'WINDOW')
            with bpy.context.temp_override(area=a, region=region):
                bpy.ops.action.view_all()
    help_text = bpy.data.texts.get('SHARK_README') or bpy.data.texts.new('SHARK_README')
    help_text.clear()
    help_text.write('SHARK ANIMATION\n\nScene selector (top right):\n01_SharkSwim: 1-48 at 30 fps, seamless 1.6 second loop.\n02_SharkBite: 1-13 at 30 fps, closed-mouth strike - recover. Mouth opening is disabled.\nPress Space to play. Select the rig and use Pose Mode to inspect bones.\n\nThe original mesh is preserved as SharkOriginalMesh_PreLipSplit.\nBoth clips animate the rig directly, with no overlapping NLA strips.\nThe runtime GLB also retains the three ghost clips, saddle and mount socket.\n')
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / 'shark_swim_with_jaw.blend'))
    return {'saved': str(HERE / 'shark_swim_with_jaw.blend'), 'scenes': [swim.name, bite.name]}


if __name__ == '__main__':
    print(setup())
