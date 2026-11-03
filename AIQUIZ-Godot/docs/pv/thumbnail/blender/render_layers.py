"""<shot>_thumbnail.blend の view layer を描いて、合成用の .npy に書き出す（Blender の中で動かす）。

ヘッドレスの Blender ではなく、開いている Blender（Higgsfield の Blender 連携、または Text Editor の Run Script）で実行する。
各 .blend の Text「thumb_render.py」と同じ中身（build_scene.py が入れる。t2_thumbnail.blend のものは、この前の版）。

  VL_chars    2 人（帽子つき）。壁と床は穴（holdout）。モーションブラーなし（吹っ飛ぶプレイヤーもくっきり）
  VL_p2trail  吹っ飛ぶプレイヤーの残像の尾（長いモーションブラー）。ほかは穴。合成で本体の下に重ねる（t5 など、動きのある構図だけ）
  VL_wall     壁・扉・破片・看板・文字の板。床は穴、2 人は影と照り返しだけ（indirect only）
  VL_deck     コンベアの床・枠・レール。2 人と壁は影と照り返しだけ
  VL_depth    壁と床のカメラからの奥行き（材質を MAT_view_depth に差し替え、1 サンプル）

出力は artifacts/pv_capture/thumb_<shot>_blender/<tag>_<layer>.exr と .npy（float32、上から下、RGBA。色は線形、アルファは乗算済み）。
<shot> はシーンの thumb_shot（無ければファイル名の頭。t2_thumbnail.blend → t2）。合成は compose.py。
1 層ずつ描くこと（4K・1024 サンプルで 1 層 30〜120 秒。まとめて呼ぶと Blender 連携の待ち時間を超える。
待ち時間を超えても描画は Blender の中で続くので、書き出されるファイルを見て待つ）。
長い描画は render_async を使う（render_one・render_all_later は描き終わるまで Blender の画面を止め、Windows に「応答なし」として
閉じられることがある。render_async は裏で描き、終わると <tag>_<layer>_done.txt を書く）。
"""
import os
import time

import bpy
import numpy as np

def find_root():
    r"""プロジェクト（project.godot のあるフォルダ）。開いている .blend から上へたどり、無ければ環境変数 AIQUIZ_ROOT、
    メインPC の C:\AIQUIZ\AIQUIZ-Godot・G:\AIQUIZ-Main\AIQUIZ-Godot、ノートPC の デスクトップ\AIQUIZ\AIQUIZ-Godot の順に探す"""
    p = bpy.data.filepath
    while p and os.path.dirname(p) != p:
        p = os.path.dirname(p)
        if os.path.isfile(os.path.join(p, "project.godot")):
            return p
    for c in (os.environ.get("AIQUIZ_ROOT", ""), r"C:\AIQUIZ\AIQUIZ-Godot", r"G:\AIQUIZ-Main\AIQUIZ-Godot",
              os.path.expanduser(r"~\Desktop\AIQUIZ\AIQUIZ-Godot")):
        if c and os.path.isfile(os.path.join(c, "project.godot")):
            return c
    raise RuntimeError("AIQUIZ-Godot が見つからない（環境変数 AIQUIZ_ROOT で指定できる）")


ROOT = find_root()
# 層 → (サンプル数, フィルタの幅, モーションブラー)。ブラーは残像の尾の層だけ（吹っ飛ぶプレイヤーの影も、本体と同じくくっきり）
LAYERS = {
    "VL_chars": (1024, None, False),
    "VL_p2trail": (1024, None, True),
    "VL_wall": (1024, None, False),
    "VL_deck": (1024, None, False),
    "VL_depth": (1, 0.01, False),
    # t8：全部をいっしょに（カメラのぼけと、破片のモーションブラーは Cycles のまま。t8_art.py の layer()）
    "VL_t8": (1024, None, True),
}


def out_dir():
    shot = bpy.context.scene.get("thumb_shot") or os.path.basename(bpy.data.filepath).split("_")[0]
    return os.path.join(ROOT, "artifacts", "pv_capture", "thumb_%s_blender" % shot)


def layer_names():
    """このファイルにある層を、描く順に"""
    have = {vl.name for vl in bpy.context.scene.view_layers}
    return [name for name in LAYERS if name in have]


def render_layer_to_npy(layer, out_dir, tag, samples=None, res=None, filter_width=None, motion_blur=None):
    """そのひとつの view layer だけを有効にして描き、float の EXR と、上から下の float32 RGBA の .npy を書く。
    motion_blur が None ならシーンの設定のまま"""
    scn = bpy.context.scene
    uses = {vl.name: vl.use for vl in scn.view_layers}
    keep = (scn.render.resolution_x, scn.render.resolution_y, scn.cycles.samples, scn.cycles.filter_width,
            scn.render.image_settings.file_format, scn.render.image_settings.color_depth, scn.render.filepath,
            scn.render.use_single_layer, scn.render.use_motion_blur)
    try:
        for vl in scn.view_layers:
            vl.use = (vl.name == layer)
        scn.render.use_single_layer = False
        if res:
            scn.render.resolution_x, scn.render.resolution_y = res
        if samples:
            scn.cycles.samples = samples
        if filter_width is not None:
            scn.cycles.filter_width = filter_width
        if motion_blur is not None:
            scn.render.use_motion_blur = motion_blur
        st = scn.render.image_settings
        st.file_format = 'OPEN_EXR'
        st.color_depth = '32'
        st.color_mode = 'RGBA'
        st.exr_codec = 'ZIP'
        os.makedirs(out_dir, exist_ok=True)
        exr = os.path.join(out_dir, "%s_%s.exr" % (tag, layer))
        scn.render.filepath = exr
        t = time.time()
        bpy.ops.render.render(write_still=True)
        secs = time.time() - t
        img = bpy.data.images.load(exr, check_existing=False)
        w, h = img.size
        buf = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        arr = np.flipud(buf.reshape(h, w, 4)).copy()
        bpy.data.images.remove(img)
        npy = exr[:-4] + ".npy"
        np.save(npy, arr)
        return {"layer": layer, "size": [w, h], "seconds": round(secs, 1),
                "alpha_mean": round(float(arr[..., 3].mean()), 4), "rgb_max": round(float(arr[..., :3].max()), 3)}
    finally:
        for vl in scn.view_layers:
            vl.use = uses[vl.name]
        (scn.render.resolution_x, scn.render.resolution_y, scn.cycles.samples, scn.cycles.filter_width,
         scn.render.image_settings.file_format, scn.render.image_settings.color_depth, scn.render.filepath,
         scn.render.use_single_layer, scn.render.use_motion_blur) = keep


def render_one(layer, tag="final4k", res=(3840, 2160), samples=None, out=None):
    """層をひとつ描く（既定は 4K・本番のサンプル数。layer は名前か、layer_names() の番号）"""
    if isinstance(layer, int):
        layer = layer_names()[layer]
    spp, filter_width, mb = LAYERS[layer]
    if samples and layer != "VL_depth":
        spp = samples
    return render_layer_to_npy(layer, out or out_dir(), tag, samples=spp, res=res, filter_width=filter_width, motion_blur=mb)


def exr_to_npy(exr):
    """EXR → 上から下の float32 RGBA の .npy（render_layer_to_npy と同じ形）"""
    img = bpy.data.images.load(exr, check_existing=False)
    try:
        w, h = img.size
        buf = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        arr = np.flipud(buf.reshape(h, w, 4)).copy()
    finally:
        bpy.data.images.remove(img)
    npy = exr[:-4] + ".npy"
    np.save(npy, arr)
    return {"size": [w, h], "alpha_mean": round(float(arr[..., 3].mean()), 4), "rgb_max": round(float(arr[..., :3].max()), 3)}


def render_async(layer, tag="final", res=(1920, 1080), samples=None, out=None, tile=1024):
    """画面を止めずに描く（Blender のふつうのレンダリング：裏で進み、レンダーの窓に進み具合が出る）。
    render_one や render_all_later は、描き終わるまで Blender の画面が止まり、長いと Windows に「応答なし」として閉じられる
    （2026-10-31、t8 の 1080p・512 サンプルで起きた）。こちらは描いているあいだも画面が動く。
    終わると、タイマー（画面の処理の合間）で EXR を .npy に直し、設定を元に戻して <tag>_<layer>_done.txt を書く
    （中止・失敗は _error.txt）。外からはこのファイルを見て待つ。メモリを抑えるため、タイルを小さめにし、データを持ち越さない"""
    import json
    scn = bpy.context.scene
    folder = out or out_dir()
    os.makedirs(folder, exist_ok=True)
    spp, filter_width, mb = LAYERS[layer]
    if samples and layer != "VL_depth":
        spp = samples
    exr = os.path.join(folder, "%s_%s.exr" % (tag, layer))
    done = os.path.join(folder, "%s_%s_done.txt" % (tag, layer))
    err = os.path.join(folder, "%s_%s_error.txt" % (tag, layer))
    for p in (exr, exr[:-4] + ".npy", done, err):
        if os.path.exists(p):
            os.remove(p)
    r, c, st = scn.render, scn.cycles, scn.render.image_settings
    keep = {"res": (r.resolution_x, r.resolution_y, r.resolution_percentage), "samples": c.samples,
            "filter": c.filter_width, "fmt": (st.file_format, st.color_depth, st.color_mode), "path": r.filepath,
            "single": r.use_single_layer, "mb": r.use_motion_blur, "persistent": r.use_persistent_data,
            "tile": (c.use_auto_tile, c.tile_size), "uses": {vl.name: vl.use for vl in scn.view_layers}}

    def restore():
        r.resolution_x, r.resolution_y, r.resolution_percentage = keep["res"]
        c.samples, c.filter_width = keep["samples"], keep["filter"]
        st.file_format, st.color_depth, st.color_mode = keep["fmt"]
        r.filepath, r.use_single_layer, r.use_motion_blur = keep["path"], keep["single"], keep["mb"]
        # 持ち越し（persistent data）は戻さない：描いたあとに物体を消すと Blender が落ちた（2026-10-31、t8 の破片の作り直し）
        r.use_persistent_data = False
        c.use_auto_tile, c.tile_size = keep["tile"]
        for vl in scn.view_layers:
            vl.use = keep["uses"].get(vl.name, vl.use)

    for vl in scn.view_layers:
        vl.use = (vl.name == layer)
    r.use_single_layer = False
    r.resolution_x, r.resolution_y = res
    r.resolution_percentage = 100
    c.samples = spp
    if filter_width is not None:
        c.filter_width = filter_width
    r.use_motion_blur = mb
    r.use_persistent_data = False
    c.use_auto_tile, c.tile_size = True, tile
    st.file_format, st.color_depth, st.color_mode = 'OPEN_EXR', '32', 'RGBA'
    st.exr_codec = 'ZIP'
    r.filepath = exr
    started = time.time()
    state = {"seen_running": False, "stats": ""}

    # 止まったときの Blender の言い分（GPU のメモリ不足など）は、レンダーの窓の見出しにしか出ないので、最後の進み具合の文を取っておく
    # （2026-11-02、確認の絵・本番が 10 秒ほどで書き出さずに止まったが、理由が残らなかった）
    def on_stats(stats, *args):
        state["stats"] = str(stats)

    bpy.app.handlers.render_stats.append(on_stats)

    def unhook():
        if on_stats in bpy.app.handlers.render_stats:
            bpy.app.handlers.render_stats.remove(on_stats)

    def watch():
        running = bpy.app.is_job_running('RENDER')
        if running:
            state["seen_running"] = True
            return 1.0
        unhook()
        if not os.path.exists(exr) or os.path.getmtime(exr) < started:
            if state["seen_running"] or time.time() - started > 30:
                restore()
                with open(err, "w", encoding="utf-8") as f:
                    f.write("%s を書かずに止まった（中止か失敗）。Blender の最後の表示：%s"
                            % (os.path.basename(exr), state["stats"] or "なし"))
                return None
            return 1.0
        try:
            info = exr_to_npy(exr)
            info.update({"layer": layer, "seconds": round(time.time() - started, 1), "samples": spp})
            with open(done, "w", encoding="utf-8") as f:
                f.write(json.dumps(info))
        except Exception:
            import traceback
            with open(err, "w", encoding="utf-8") as f:
                f.write(traceback.format_exc())
        finally:
            restore()
        return None

    win = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=win):
        bpy.ops.render.render('INVOKE_DEFAULT', write_still=True)
    bpy.app.timers.register(watch, first_interval=2.0)
    return {"exr": exr, "done": done, "samples": spp, "res": list(res)}


def render_all_later(tag="final4k", res=(3840, 2160), samples=None, out=None):
    """全部の層を、Blender 連携の呼び出しが返ったあとに順に描く（タイマー）。進み具合は書き出されるファイルで見る"""
    def job():
        folder = out or out_dir()
        for name in layer_names():
            try:
                render_one(name, tag=tag, res=res, samples=samples, out=out)
            except Exception:
                # タイマーの中の失敗は表に出ないので、書き出し先に残して止める
                import traceback
                os.makedirs(folder, exist_ok=True)
                with open(os.path.join(folder, "%s_%s_error.txt" % (tag, name)), "w", encoding="utf-8") as f:
                    f.write(traceback.format_exc())
                break
        return None
    bpy.app.timers.register(job, first_interval=0.5)


if __name__ == "__main__":
    for name in layer_names():
        print(render_one(name))
