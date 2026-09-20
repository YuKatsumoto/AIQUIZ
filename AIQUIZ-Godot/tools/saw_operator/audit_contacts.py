"""Read-only posed mesh clearance check, independent of the IK endpoint check."""
import bpy,json
from mathutils import Vector
ROOT='C:/AIQUIZ/AIQUIZ-Godot'
scene=bpy.data.scenes['SawOperator_Workbench']
bpy.context.window.scene=scene
body=bpy.data.objects['GodotPlushMesh']
report=[]
for frame in [1,325,374,437,487,601,655,710,775,810,900,961]:
    scene.frame_set(frame);bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get()
    ev=body.evaluated_get(dg);mesh=ev.to_mesh()
    row={'frame':frame,'soles':{}}
    for side in ['L','R']:
        groups={body.vertex_groups['DEF-'+part+'.'+side].index for part in ['foot','toe']}
        plate=bpy.data.objects['OP_PedalPlate_'+side]
        transform=plate.matrix_world.inverted()@ev.matrix_world
        points=[transform@v.co for v in mesh.vertices if sum(g.weight for g in body.data.vertices[v.index].groups if g.group in groups)>.5]
        footprint=[p for p in points if abs(p.x)<.11 and abs(p.y)<.145]
        row['soles'][side]={'sample_vertices':len(footprint),'clearance':min(p.z for p in footprint)-.0225}
    report.append(row)
    ev.to_mesh_clear()
scene.frame_set(601)
values=[s['clearance'] for r in report for s in r['soles'].values()]
result={'samples':report,'minimum_sole_gap_m':min(values),'maximum_sole_gap_m':max(values),'passed':min(values)>=-.001 and max(values)<.01}
open(ROOT+'/artifacts/saw_operator/v2_mesh_contacts.json','w').write(json.dumps(result,indent=2))
