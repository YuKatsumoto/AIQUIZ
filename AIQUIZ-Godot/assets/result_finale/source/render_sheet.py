"""Render labelled frames of the active finale camera for review (evidence only)."""
import bpy
import os

OUT = "C:/AIQUIZ/AIQUIZ-Godot/artifacts/result_finale/blender"


def render_times(times, tag, camera="CAM_FinaleWin", size=(640, 360), samples=8):
    s = bpy.data.scenes["AIQUIZ_ScoreTowerFinale"]
    s.camera = bpy.data.objects[camera]
    old = (s.render.resolution_x, s.render.resolution_y, s.render.filepath, s.eevee.taa_render_samples, s.frame_current)
    s.render.resolution_x, s.render.resolution_y = size
    s.eevee.taa_render_samples = samples
    paths = []
    folder = os.path.join(OUT, tag)
    os.makedirs(folder, exist_ok=True)
    for t in times:
        frame = int(round(t * 60))
        s.frame_set(frame)
        s.render.filepath = os.path.join(folder, "t%05.2f.png" % t)
        bpy.ops.render.render(write_still=True)
        paths.append(s.render.filepath)
    s.render.resolution_x, s.render.resolution_y, s.render.filepath, s.eevee.taa_render_samples = old[:4]
    s.frame_set(old[4])
    return paths
