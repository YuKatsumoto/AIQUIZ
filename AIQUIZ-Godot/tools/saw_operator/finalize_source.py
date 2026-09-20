"""Open the dependency-only source library as a normal, editable .blend file.
Use Blender --factory-startup --background <source.blend> --python <this-file>.
No add-on/user preferences are changed; the connected working scene is untouched.
"""
import bpy,os
scene=bpy.data.scenes['SawOperator_Workbench']
bpy.context.window.scene=scene
scene.frame_set(601)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('OPERATOR_SOURCE_FINALIZED',bpy.context.scene.name,len(bpy.data.objects['Rig'].data.bones),scene.frame_end,os.path.getsize(bpy.data.filepath))
