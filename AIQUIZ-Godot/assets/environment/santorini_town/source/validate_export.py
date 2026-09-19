"""Validate generated glTF structure, palette and independent render agreement."""
from pathlib import Path
import json,struct,hashlib
import bpy,numpy as np
source=Path(__file__).resolve().parent
path=source.parent/'aiquiz_santorini_town.glb';raw=path.read_bytes()
magic,version,total=struct.unpack_from('<4sII',raw)
assert magic==b'glTF' and version==2 and total==len(raw)
n=struct.unpack_from('<I',raw,12)[0];data=json.loads(raw[20:20+n]);binary=raw[28+n:]
assert len(binary)==data['buffers'][0]['byteLength']
for view in data['bufferViews']:
    assert view.get('byteOffset',0)%4==0
    assert view.get('byteOffset',0)+view['byteLength']<=len(binary)
colors={p['attributes']['COLOR_0'] for m in data['meshes'] for p in m['primitives'] if 'COLOR_0' in p['attributes']}
for i in colors:
    a=data['accessors'][i]
    assert a['componentType']==5121 and a['type']=='VEC4' and a['normalized']
assert len(data['meshes'])==39
assert not any(n.get('name','')=='Cube' or n.get('name','').endswith('.001') for n in data['nodes'])
assert len(data['materials'])==6
assert all(m.get('alphaMode','OPAQUE')=='OPAQUE' for m in data['materials'])
names=[m['name'] for m in data['materials']]
assert 'Santorini Window Warm Glass' in names and 'Santorini Lantern Warm Bulb' in names
surfaces=sum(len(m['primitives']) for m in data['meshes'])
triangles=sum(data['accessors'][p['indices']]['count']//3 for m in data['meshes'] for p in m['primitives'])
source_image=bpy.data.images.load(str(source/'previews'/'rear_church_detail.png'))
roundtrip=bpy.data.images.load(str(source/'previews'/'glb_roundtrip_rear.png'))
a=np.empty(len(source_image.pixels),dtype=np.float32);b=np.empty(len(roundtrip.pixels),dtype=np.float32)
source_image.pixels.foreach_get(a);roundtrip.pixels.foreach_get(b)
delta=np.abs(a-b)
report={'passed':True,'glb_sha256':hashlib.sha256(raw).hexdigest(),'glb_bytes':len(raw),'export_meshes':len(data['meshes']),'export_materials':len(data['materials']),'export_surfaces':surfaces,'export_triangles':triangles,'normalized_rgba8_color_accessors':len(colors),'roundtrip_render_mean_absolute_linear_rgba_difference':float(delta.mean()),'roundtrip_render_99th_percentile_difference':float(np.quantile(delta,.99)),'validation_scope':'GLB structure and independent Blender GLB import/render; Godot gameplay evidence is separate'}
(source/'export_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2),flush=True)
