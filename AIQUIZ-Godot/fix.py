import sys

def fix_candidates(content):
    content = content.replace('["LeftHandThumb1", "mixamorig:LeftHandThumb1"]', '["LeftThumbMetacarpal", "mixamorig_LeftHandThumb1"]')
    content = content.replace('["LeftHandThumb2", "mixamorig:LeftHandThumb2"]', '["LeftThumbProximal", "mixamorig_LeftHandThumb2"]')
    content = content.replace('["LeftHandIndex1", "mixamorig:LeftHandIndex1"]', '["LeftIndexProximal", "mixamorig_LeftHandIndex1"]')
    content = content.replace('["LeftHandIndex2", "mixamorig:LeftHandIndex2"]', '["LeftIndexIntermediate", "mixamorig_LeftHandIndex2"]')
    content = content.replace('["LeftHandIndex3", "mixamorig:LeftHandIndex3"]', '["LeftIndexDistal", "mixamorig_LeftHandIndex3"]')
    content = content.replace('["LeftHandMiddle1", "mixamorig:LeftHandMiddle1"]', '["LeftMiddleProximal", "mixamorig_LeftHandMiddle1"]')
    content = content.replace('["LeftHandMiddle2", "mixamorig:LeftHandMiddle2"]', '["LeftMiddleIntermediate", "mixamorig_LeftHandMiddle2"]')
    content = content.replace('["LeftHandMiddle3", "mixamorig:LeftHandMiddle3"]', '["LeftMiddleDistal", "mixamorig_LeftHandMiddle3"]')
    content = content.replace('["LeftHandRing1", "mixamorig:LeftHandRing1"]', '["LeftRingProximal", "mixamorig_LeftHandRing1"]')
    content = content.replace('["LeftHandRing2", "mixamorig:LeftHandRing2"]', '["LeftRingIntermediate", "mixamorig_LeftHandRing2"]')
    content = content.replace('["LeftHandRing3", "mixamorig:LeftHandRing3"]', '["LeftRingDistal", "mixamorig_LeftHandRing3"]')
    content = content.replace('["LeftHandPinky1", "mixamorig:LeftHandPinky1"]', '["LeftLittleProximal", "mixamorig_LeftHandPinky1"]')
    content = content.replace('["LeftHandPinky2", "mixamorig:LeftHandPinky2"]', '["LeftLittleIntermediate", "mixamorig_LeftHandPinky2"]')
    content = content.replace('["LeftHandPinky3", "mixamorig:LeftHandPinky3"]', '["LeftLittleDistal", "mixamorig_LeftHandPinky3"]')
    
    content = content.replace('["RightHandThumb1", "mixamorig:RightHandThumb1"]', '["RightThumbMetacarpal", "mixamorig_RightHandThumb1"]')
    content = content.replace('["RightHandThumb2", "mixamorig:RightHandThumb2"]', '["RightThumbProximal", "mixamorig_RightHandThumb2"]')
    content = content.replace('["RightHandIndex1", "mixamorig:RightHandIndex1"]', '["RightIndexProximal", "mixamorig_RightHandIndex1"]')
    content = content.replace('["RightHandIndex2", "mixamorig:RightHandIndex2"]', '["RightIndexIntermediate", "mixamorig_RightHandIndex2"]')
    content = content.replace('["RightHandIndex3", "mixamorig:RightHandIndex3"]', '["RightIndexDistal", "mixamorig_RightHandIndex3"]')
    content = content.replace('["RightHandMiddle1", "mixamorig:RightHandMiddle1"]', '["RightMiddleProximal", "mixamorig_RightHandMiddle1"]')
    content = content.replace('["RightHandMiddle2", "mixamorig:RightHandMiddle2"]', '["RightMiddleIntermediate", "mixamorig_RightHandMiddle2"]')
    content = content.replace('["RightHandMiddle3", "mixamorig:RightHandMiddle3"]', '["RightMiddleDistal", "mixamorig_RightHandMiddle3"]')
    content = content.replace('["RightHandRing1", "mixamorig:RightHandRing1"]', '["RightRingProximal", "mixamorig_RightHandRing1"]')
    content = content.replace('["RightHandRing2", "mixamorig:RightHandRing2"]', '["RightRingIntermediate", "mixamorig_RightHandRing2"]')
    content = content.replace('["RightHandRing3", "mixamorig:RightHandRing3"]', '["RightRingDistal", "mixamorig_RightHandRing3"]')
    content = content.replace('["RightHandPinky1", "mixamorig:RightHandPinky1"]', '["RightLittleProximal", "mixamorig_RightHandPinky1"]')
    content = content.replace('["RightHandPinky2", "mixamorig:RightHandPinky2"]', '["RightLittleIntermediate", "mixamorig_RightHandPinky2"]')
    content = content.replace('["RightHandPinky3", "mixamorig:RightHandPinky3"]', '["RightLittleDistal", "mixamorig_RightHandPinky3"]')

    return content

for filename in ['scripts/world/player_controller.gd', 'scripts/ui/emote_select.gd']:
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()
    content = fix_candidates(content)
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(content)
print('Fixed bone names in both files.')
