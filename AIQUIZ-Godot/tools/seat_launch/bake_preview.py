"""Bake runtime poses into a separate editable demonstration; preserve the workbench.
Execute through Higgsfield Bridge after tests/seat_launch_export.gd.
"""
import bpy, json, math, os, uuid
from mathutils import Matrix, Vector
from pathlib import Path

ROOT = Path('C:/AIQUIZ/AIQUIZ-Godot')
scene = bpy.context.scene
station = bpy.data.objects['OperatorStation']
rig = bpy.data.objects['Rig']
flight = bpy.data.objects['OP_SeatFlightRoot']
tongue = bpy.data.objects['SL_Tongue']
web = bpy.data.objects['SL_LapWebbing'].data.shape_keys
rows = json.loads((ROOT/'assets/hazards/saw_operator/source/chair_transfer_poses.json').read_text())
C = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
objects = [station] + list(station.children_recursive)
saved = {o:(o.animation_data.action if o.animation_data else None,o.matrix_basis.copy()) for o in objects}
saved_keys = [key.value for key in web.key_blocks]
saved_web_action = web.animation_data.action if web.animation_data else None
saved_frame, saved_end = scene.frame_current, scene.frame_end
saved_camera, saved_output = scene.camera, scene.render.filepath
saved_bones = {b:b.matrix_basis.copy() for b in rig.pose.bones}
markers = [(m.name,m.frame) for m in scene.timeline_markers]
try:
    for o in objects:
        if o.animation_data: o.animation_data.action = None
    for o in [rig,flight,tongue]:
        o.animation_data_create()
        o.animation_data.action=bpy.data.actions.new('ChairTransfer_'+o.name)
    web.animation_data_create()
    web.animation_data.action=bpy.data.actions.new('ChairTransfer_LapBelt')
    for name,values in rows[0]['controls'].items():
        if name in bpy.data.objects:
            bpy.data.objects[name].matrix_basis=C@Matrix(values)@C.inverted()
    for row in rows:
        f=row['frame']; extension=row['belt']
        flight.location.z=row['height']; flight.keyframe_insert('location',frame=f)
        tongue.location=(.345-.690*extension,.10-.247*math.sin(math.pi*extension),1.465)
        tongue.keyframe_insert('location',frame=f)
        for i,key in enumerate(list(web.key_blocks)[1:]):
            key.value=max(0,1-abs(extension*4-i));key.keyframe_insert('value',frame=f)
        for bone in rig.pose.bones:
            desired=C@Matrix(row['bones'][bone.name])
            if bone.parent:
                parent_desired=C@Matrix(row['bones'][bone.parent.name])
                bone.matrix_basis=bone.bone.matrix_local.inverted()@bone.parent.bone.matrix_local@parent_desired.inverted()@desired
            else: bone.matrix_basis=bone.bone.matrix_local.inverted()@desired
            bone.keyframe_insert('location',frame=f)
            bone.keyframe_insert('rotation_quaternion',frame=f)
            bone.keyframe_insert('scale',frame=f)
    scene.timeline_markers.clear()
    for name,frame in [('Belt pull',1),('Right hip latch',117),('Rocket ignition',175),('Arrival after loading',259),('Contact',367),('Release',385)]:
        scene.timeline_markers.new(name,frame=frame)
    scene.frame_end=len(rows);scene.frame_set(157)
    bpy.context.view_layer.update()
    output=ROOT/'assets/hazards/saw_operator/source/chair_transfer_preview.blend'
    if globals().get('preview_render_only', False):
        scene.camera=bpy.data.objects['SL_AuditCamera']
        for f,label in [(70,'belt_pull'),(118,'belt_contact'),(183,'chair_liftoff')]:
            scene.frame_set(f)
            scene.render.filepath=str(ROOT/'artifacts/seat_launch_rebuild'/('model_'+label+'.png'))
            bpy.ops.render.render(write_still=True)
    else:
        temporary=output.with_name('chair_transfer_'+uuid.uuid4().hex+'.blend')
        bpy.data.libraries.write(str(temporary),{scene},path_remap='RELATIVE_ALL',fake_user=True,compress=True)
        os.replace(temporary,output)
    result={'frames':len(rows),'preview':str(output),'original_actions_restored':True}
finally:
    scene.camera, scene.render.filepath=saved_camera,saved_output
    for o,(action,basis) in saved.items():
        if o.animation_data: o.animation_data.action=action
        o.matrix_basis=basis
    web.animation_data.action=saved_web_action
    for key,value in zip(web.key_blocks,saved_keys): key.value=value
    for bone,basis in saved_bones.items():bone.matrix_basis=basis
    scene.frame_end=saved_end
    scene.timeline_markers.clear()
    for name,frame in markers:scene.timeline_markers.new(name,frame=frame)
    scene.frame_set(saved_frame)
    bpy.context.view_layer.update()
