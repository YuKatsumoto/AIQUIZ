"""Bake the shared Godot contact solution into the editable Blender source.
Run tests/saw_operator_export_poses.gd first; execute here via Higgsfield Bridge.
This does not re-export the runtime asset (which is procedurally evaluated).
"""
import bpy,json,math
from mathutils import Matrix,Vector
ROOT='C:/AIQUIZ/AIQUIZ-Godot'
scene=bpy.data.scenes['SawOperator_Workbench'];bpy.context.window.scene=scene
poses=json.load(open(ROOT+'/assets/hazards/saw_operator/source/evaluated_poses.json'))
root=bpy.data.objects['OperatorStation'];rig=bpy.data.objects['Rig']
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
for obj in [root]+list(root.children_recursive):obj.animation_data_clear()
for bone in rig.pose.bones:
    for constraint in bone.constraints:constraint.mute=True
    bone.rotation_mode='QUATERNION'
rails=[]
for side,x in [('L',.32),('R',-.32)]:
    name='OP_PreviewTelescoping_'+side
    o=bpy.data.objects.get(name)
    if not o:
        bpy.ops.mesh.primitive_cube_add(size=1)
        o=bpy.context.object;o.name=name;o.parent=root
        o.data.materials.append(bpy.data.materials['OP_Machined'])
    o['source_preview_only']=True
    rails.append((o,x))
scene.frame_start=1;scene.frame_end=poses[-1]['frame'];scene.render.fps=60
for row in poses:
    f=row['frame'];ext=row['sample']['extension']
    drop=.628274*row['sample']['lowering']
    root.location=(-10.7-2.25*ext,0,-drop);root.rotation_euler.z=math.pi/2
    root.keyframe_insert('location',frame=f)
    for name,values in row['controls'].items():
        o=bpy.data.objects.get(name)
        if o is None:continue
        o.matrix_basis=C@Matrix(values)@C.inverted()
        o.keyframe_insert('location',frame=f);o.keyframe_insert('rotation_euler',frame=f);o.keyframe_insert('scale',frame=f)
    # glTF bones retain their longitudinal local Y axis; only the world basis changes.
    for bone in rig.pose.bones:
        desired=C@Matrix(row['bones'][bone.name])
        if bone.parent:
            parent_desired=C@Matrix(row['bones'][bone.parent.name])
            bone.matrix_basis=bone.bone.matrix_local.inverted()@bone.parent.bone.matrix_local@parent_desired.inverted()@desired
        else:bone.matrix_basis=bone.bone.matrix_local.inverted()@desired
        bone.keyframe_insert('location',frame=f)
        bone.keyframe_insert('rotation_quaternion',frame=f)
        bone.keyframe_insert('scale',frame=f)
    for o,x in rails:
        length=abs(2.25*ext-1.42)+.22
        o.location=(x,(1.42-2.25*ext)*.5,.78)
        o.scale=(.10,length,.16)
        o.keyframe_insert('location',frame=f);o.keyframe_insert('scale',frame=f)
scene.timeline_markers.clear()
for name,frame in [('Stowed / instruments',1),('Transfer / extension',325),('Lower floor',355),('Start press',374),('Cover opens',412),('Toggle',437),('RPM dial',487),('Forward / raise',655),('Height hold',710),('Reverse / lower',775),('Neutral',900)]:
    scene.timeline_markers.new(name,frame=frame)
scene.frame_set(601)
bpy.context.view_layer.update()
cam=scene.camera
cam.location=(-9.4,-4.8,2.8)
cam.rotation_euler=(Vector((-12.6,0,.9))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.lens=48
scene.render.filepath=ROOT+'/artifacts/saw_operator/blender_final.png'
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/hazards/saw_operator/source/saw_operator.blend')
result={'frames':len(poses),'markers':len(scene.timeline_markers),'source':bpy.data.filepath,'render':scene.render.filepath}
