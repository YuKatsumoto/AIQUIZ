"""講義セットの長い処理（組み立て → 焼き込み → 書き出し → 確認レンダー）を、ライブ Blender の中でタイマーから順に流す。

接続の 1 回の呼び出しは時間切れがあるので、焼き込みは 1 フレームに 1 個ずつ進める。進み具合と各段の結果は
%TEMP%/aiquiz_lecture_jobs/<name>.json に書くので、呼んだ側はそれを読みにいく。
    ns = {"__name__": "lecture_jobs"}
    exec(open(r".../lsb_jobs.py", encoding="utf-8").read(), ns)
    ns["start"]("board_v2", ["build", "bake_all", "export", "review"])
段: build（stage_build）/ bake_all（stage_bake を 1 個ずつ、残りがなくなるまで）/ export（stage_export）/
review（Cycles の確認レンダー）。ヘッドレスの Blender は使わない（AGENTS.md）。
"""
import json
import os
import runpy
import sys
import tempfile
import time
import traceback

import bpy

BUILDER = "C:/AIQUIZ/AIQUIZ-Godot/assets/settings_hall/source/blender/build_lecture_set.py"
JOBS = os.path.join(tempfile.gettempdir(), "aiquiz_lecture_jobs")


def status_path(name):
    os.makedirs(JOBS, exist_ok=True)
    return os.path.join(JOBS, name + ".json")


def _write(name, st):
    with open(status_path(name), "w", encoding="utf-8") as fh:
        json.dump(st, fh, indent=1, ensure_ascii=False, default=str)


def _builder():
    sys.argv = ["blender", "--", "--no-render"]
    return runpy.run_path(BUILDER, run_name="lecture_build")


def start(name, steps, review_engine="CYCLES"):
    st = {"name": name, "state": "queued", "steps": [], "t0": time.time(), "queue": list(steps)}
    _write(name, st)
    queue = list(steps)
    holder = {"ns": None}

    def tick():
        stop = status_path(name) + ".stop"
        if os.path.exists(stop):
            os.remove(stop)
            st["state"] = "stopped"
            _write(name, st)
            return None
        if not queue:
            st["state"] = "done"
            st["secs"] = round(time.time() - st["t0"], 1)
            _write(name, st)
            return None
        step = queue[0]
        st["state"] = "running " + step
        _write(name, st)
        t = time.time()
        try:
            if holder["ns"] is None or step == "build":
                holder["ns"] = _builder()
            ns = holder["ns"]
            if step == "build":
                res = ns["stage_build"]()
                res.pop("clips", None)
                queue.pop(0)
            elif step == "bake_all":
                res = ns["stage_bake"](1)
                if res["left"] == 0:
                    queue.pop(0)
            elif step.startswith("rebake:"):
                res = ns["stage_rebake"](step.split(":", 1)[1])
                queue.pop(0)
            elif step == "export":
                res = ns["stage_export"](render=False)
                queue.pop(0)
            elif step == "review":
                scene = bpy.data.scenes[ns["SCENE_NAME"]]
                res = {"renders": ns["render_previews"](scene, bpy.data.objects["CAM_Review"],
                                                        bpy.data.objects["CAM_Cast"], review_engine)}
                queue.pop(0)
            else:
                raise ValueError("unknown step " + step)
            st["steps"].append({"step": step, "secs": round(time.time() - t, 1), "result": res})
        except Exception:
            st["steps"].append({"step": step, "error": traceback.format_exc()[-4000:]})
            st["state"] = "failed"
            _write(name, st)
            return None
        _write(name, st)
        return 0.05

    bpy.app.timers.register(tick, first_interval=0.2)
    return status_path(name)


def read(name):
    with open(status_path(name), encoding="utf-8") as fh:
        return json.load(fh)
