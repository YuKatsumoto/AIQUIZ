"""Read-only geometry audit against snapshots exported from the real dock.
Temporary Blender scene only; original source objects are never edited.
"""
import bpy,json,math
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
ROOT='C:/AIQUIZ/AIQUIZ-Godot';OUT=ROOT+'/artifacts/saw_operator'
source=bpy.data.scenes['SawOperator_Workbench'];station=bpy.data.objects['OperatorStation']
records=json.load(open(OUT+'/dock_poses.json'))
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
R=Matrix.Rotation(math.pi,4,'Z');B=R@C
audit=bpy.data.scenes.new('SawOperator_TransportAudit');report=[]
for row in records:
    bpy.context.window.scene=source;source.frame_set(round(row['time']*60)+1);bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get();cart=B@Matrix(row['carriage'])@B.inverted()
    points=[];faces=[];owners=[]
    for obj in station.children_recursive:
        if obj.type not in ['MESH','CURVE','FONT']:continue
        ev=obj.evaluated_get(dg);me=ev.to_mesh();start=len(points)
        points.extend(cart@ev.matrix_world@v.co for v in me.vertices)
        faces.extend(tuple(start+i for i in p.vertices) for p in me.polygons)
        owners.extend([obj.name]*len(me.polygons))
        ev.to_mesh_clear()
    station_bvh=BVHTree.FromPolygons(points,faces)
    low=Vector(tuple(min(v[i] for v in points) for i in range(3)))
    high=Vector(tuple(max(v[i] for v in points) for i in range(3)))
    bpy.context.window.scene=audit
    bpy.ops.import_scene.gltf(filepath=ROOT+row['file'].replace('res:/',''))
    for obj in list(audit.objects):
        if obj.parent is None:obj.matrix_world=R@obj.matrix_world
    bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();hits=[];tested=[]
    for obj in audit.objects:
        if obj.type!='MESH':continue
        corners=[obj.matrix_world@Vector(p) for p in obj.bound_box]
        if any(max(p[i] for p in corners)<low[i] or min(p[i] for p in corners)>high[i] for i in range(3)):continue
        tested.append(obj.name)
        ev=obj.evaluated_get(dg);me=ev.to_mesh()
        tree=BVHTree.FromPolygons([ev.matrix_world@v.co for v in me.vertices],[tuple(p.vertices) for p in me.polygons])
        overlaps=station_bvh.overlap(tree)
        if overlaps:
            hitpoints=[ev.matrix_world@me.vertices[i].co for b in set(b for a,b in overlaps) for i in me.polygons[b].vertices]
            hits.append({'object':obj.name,'triangle_pairs':len(overlaps),'station_parts':sorted(set(owners[a] for a,b in overlaps)), 'collider_bounds':[[min(p[i] for p in hitpoints) for i in range(3)],[max(p[i] for p in hitpoints) for i in range(3)]]})
        ev.to_mesh_clear()
    report.append({'time':row['time'],'station_bounds':[list(low),list(high)],'candidates':tested,'intersections':hits})
    for obj in list(audit.objects):bpy.data.objects.remove(obj,do_unlink=True)
bpy.context.window.scene=source;source.frame_set(601)
bpy.data.scenes.remove(audit)
open(OUT+'/transport_clearance.json','w').write(json.dumps(report,indent=2))
result={'samples':report}
