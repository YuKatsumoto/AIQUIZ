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
"""
import os
import time

import bpy
import numpy as np

ROOT = r"G:\AIQUIZ-Main\AIQUIZ-Godot"
# 層 → (サンプル数, フィルタの幅, モーションブラー)。ブラーは残像の尾の層だけ（吹っ飛ぶプレイヤーの影も、本体と同じくくっきり）
LAYERS = {
    "VL_chars": (1024, None, False),
    "VL_p2trail": (1024, None, True),
    "VL_wall": (1024, None, False),
    "VL_deck": (1024, None, False),
    "VL_depth": (1, 0.01, False),
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
