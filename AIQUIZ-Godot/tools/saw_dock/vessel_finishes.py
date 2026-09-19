"""Native deterministic PBR finish maps for metre-projected vessel UVs.
No paid/image generation. The maps are editable Blender image datablocks.
"""
import bpy, numpy as np, math, os
OUT='C:/AIQUIZ/AIQUIZ-Godot/assets/hazards/vessel_finishes'
os.makedirs(OUT,exist_ok=True)
N=1024
yy,xx=np.mgrid[:N,:N]/N
rng=np.random.default_rng(1809)
grain=rng.normal(0,1,(N,N))
wide=(np.sin(xx*math.tau*3+.45*np.sin(yy*math.tau*2))+np.sin(yy*math.tau*5+xx*math.tau))/2
def write(name,rgb,color_space):
    data=np.ones((N,N,4),dtype=np.float32);data[:,:,:3]=np.clip(rgb,0,1)
    image=bpy.data.images.get(name) or bpy.data.images.new(name,N,N,alpha=False)
    image.colorspace_settings.name=color_space
    image.pixels.foreach_set(data.ravel());image.filepath_raw=OUT+'/'+name+'.png';image.file_format='PNG';image.save()
    return image
def normal(height):
    dx=(np.roll(height,-1,axis=1)-np.roll(height,1,axis=1))*.5
    dy=(np.roll(height,-1,axis=0)-np.roll(height,1,axis=0))*.5
    z=np.ones_like(dx);n=np.stack([-dx,-dy,z],-1);n/=np.linalg.norm(n,axis=2,keepdims=True)
    return n*.5+.5
fine=write('VesselR2_PaintNormal',normal(grain*.045),'Non-Color')
# Repeated diagonal anti-slip lozenges, sparse enough to survive a game camera.
gx=xx*16;gy=yy*16;phase=(np.floor(gx)+np.floor(gy))%2
cx=(gx%1-.5);cy=(gy%1-.5)
ridge=np.maximum(0,1-np.abs(cx+np.where(phase==0,cy,-cy))/.09)*np.maximum(0,1-np.maximum(np.abs(cx),np.abs(cy))/.37)
deck_normal=write('VesselR2_DeckNormal',normal(ridge*1.8+grain*.035),'Non-Color')
roles={'Navy':((.018,.055,.105),.42),'Ivory':((.72,.76,.76),.39),'Deck':((.18,.22,.24),.61),'SafetyYellow':((.93,.52,.045),.42)}
for role,(base,roughness) in roles.items():
    tone=1+wide*.045+grain*.009
    if role=='Deck':tone*=1-ridge*.055
    linear=np.array(base)[None,None,:]*tone[:,:,None]
    encoded=np.where(linear<=.0031308,linear*12.92,1.055*np.maximum(linear,0)**(1/2.4)-.055)
    albedo=write('VesselR2_'+role+'_Color',encoded,'sRGB')
    rough=write('VesselR2_'+role+'_Roughness',np.repeat(np.clip(roughness+wide*.04+grain*.008,0,1)[:,:,None],3,axis=2),'Non-Color')
    material=bpy.data.materials['Vessel_'+role];nodes=material.node_tree.nodes;links=material.node_tree.links
    shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    for n in list(nodes):
        if n.name.startswith('R2_'):nodes.remove(n)
    for label,img,socket in [('Albedo',albedo,'Base Color'),('Roughness',rough,'Roughness')]:
        node=nodes.new('ShaderNodeTexImage');node.name='R2_'+label;node.image=img;links.new(node.outputs['Color'],shader.inputs[socket])
    tex=nodes.new('ShaderNodeTexImage');tex.name='R2_NormalTexture';tex.image=deck_normal if role=='Deck' else fine
    n=nodes.new('ShaderNodeNormalMap');n.name='R2_Normal';n.inputs['Strength'].default_value=.55 if role=='Deck' else .24
    links.new(tex.outputs['Color'],n.inputs['Color']);links.new(n.outputs['Normal'],shader.inputs['Normal'])
result={'maps':10,'resolution':N,'materials':list(roles),'path':OUT}
