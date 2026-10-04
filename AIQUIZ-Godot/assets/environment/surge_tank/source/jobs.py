"""Run long steps (bakes, renders) in the LIVE Blender without blocking the connector call.

    ns = {"__name__": "tank_jobs"}
    exec(open(".../source/jobs.py", encoding="utf-8").read(), ns)
    ns["start"]("bakeA", [("bake_cistern.py", "unwrap", ("A",)), ("bake_cistern.py", "bake", ("A", "LIGHT"))])

The steps run one after another from a bpy.app.timers callback on Blender's main thread; the
progress and every step's return value go to %TEMP%/aiquiz_tank_jobs/<name>.json, which
the caller polls. Nothing here runs outside the user's open Blender.
"""
import json
import os
import tempfile
import time
import traceback

import bpy

SOURCE = "C:/AIQUIZ/AIQUIZ-Godot/assets/environment/surge_tank/source/"
JOBS = os.path.join(tempfile.gettempdir(), "aiquiz_tank_jobs")


def status_path(name):
    os.makedirs(JOBS, exist_ok=True)
    return os.path.join(JOBS, name + ".json")


def _write(name, st):
    with open(status_path(name), "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=1, default=str)


def start(name, steps):
    st = {"name": name, "state": "queued", "steps": [], "t0": time.time()}
    _write(name, st)
    queue = list(steps)

    def tick():
        if not queue:
            st["state"] = "done"
            st["secs"] = round(time.time() - st["t0"], 1)
            _write(name, st)
            return None
        script, fn, args = queue.pop(0)
        t = time.time()
        st["state"] = "running %s.%s%s" % (script, fn, args)
        _write(name, st)
        try:
            ns = {"__name__": "tank_job"}
            exec(open(SOURCE + script, encoding="utf-8").read(), ns)
            res = ns[fn](*args)
            st["steps"].append({"step": "%s.%s%s" % (script, fn, args), "secs": round(time.time() - t, 1), "result": res})
        except Exception:
            st["steps"].append({"step": "%s.%s%s" % (script, fn, args), "error": traceback.format_exc()})
            st["state"] = "failed"
            _write(name, st)
            return None
        try:
            bpy.context.view_layer.update()
        except Exception:
            pass
        _write(name, st)
        return 0.2

    bpy.app.timers.register(tick, first_interval=0.3)
    return status_path(name)


def save():
    """Checkpoint: overwrite the surge tank .blend (AGENTS.md: save the worked .blend)."""
    path = bpy.data.filepath.replace("\\", "/")
    if not path.endswith("surge_tank/source/surge_tank.blend"):
        raise RuntimeError("refusing to save: active file is %s" % path)
    bpy.ops.wm.save_mainfile()
    return path
