from pathlib import Path
code=Path('C:/AIQUIZ/AIQUIZ-Godot/assets/animations/result_referee/source/animate_stage.py').read_text(encoding='utf-8')
exec(code[:code.index('rig.animation_data_clear()')])
for side,sign in [('l',-1),('r',1)]:
    joint('LOSE_',side+'_shoulder',[(9.55,(-15,0,sign*68)),(11.4667,(-10,0,sign*74))])
for t,scale in [(9.55,11.7),(11.4667,12.1),(12.6667,12.1)]:
    s.camera.data.ortho_scale=scale;s.camera.data.keyframe_insert('ortho_scale',frame=round(t*60))
for o in s.objects:
    if o.name.startswith('WIN_') and any(x in o.name for x in ['_prox','_mid','_dist']):
        joint('WIN_',o.name[4:],[(0,(0,0,0)),(7.33,(0,0,0)),(8.3,(-65,0,0)),(11.4667,(-65,0,0))])
s.frame_set(688)
