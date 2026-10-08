"""Assembles the PV rough cut from tools/pv/edit.json with ffmpeg (the After Effects build
reads the same list; tools/pv/README.md).

    python tools/pv/rough_cut.py [--bgm path/to/music.wav] [--out artifacts/pv/final/AIQUIZ3D_PV_rough.mp4]

edit.json:
  {"fps": 60, "shots": [
     {"clip": "intro_solo_t2_play", "in": 3.2, "dur": 2.5, "speed": 1.0,
      "telop": "正解のドアをぶち破れ！", "sub": "small second line", "note": "tiny corner note", "style": "lower"},
     {"card": "logo", "dur": 2.0, "telop": "...", "bg": "#0b1630", "image": "assets/.../logo.png"}
  ], "sfx_gain_db": -4.0}
Clips are artifacts/pv/mezz/<clip>.mov (tools/pv/encode.py). Each shot keeps its game audio;
a "card" shot is silent. With --bgm the music is laid under the whole cut (looped, faded out at
the end) and the mix is normalised to -14 LUFS.
"""
import argparse
import json
import os
import subprocess
import tempfile

FFMPEG = 'C:/ffmpeg/bin/ffmpeg.exe'
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MEZZ = os.path.join(ROOT, 'artifacts', 'pv', 'mezz')
FONT = os.path.join(ROOT, 'resources', 'fonts', 'NotoSansJP-Bold.otf').replace('\\', '/').replace(':', '\\:')
W, H = 1920, 1080


def ff(args):
    proc = subprocess.run([FFMPEG, '-y', '-nostdin', '-v', 'error'] + args, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(' '.join(args[-3:]) + '\n' + proc.stderr.strip()[-3000:])


def text_file(tmp, name, text):
    path = os.path.join(tmp, name)
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)
    return path.replace('\\', '/').replace(':', '\\:')


def telop_filters(tmp, index, shot, dur):
    """drawtext chain: a main line and an optional small line, faded in and out."""
    out = []
    style = shot.get('style', 'lower')
    fade = 'if(lt(t,0.25),t/0.25,if(gt(t,%f),(%f-t)/0.25,1))' % (dur - 0.25, dur)
    if shot.get('telop'):
        size = 92 if style == 'center' else 76
        y = '(h-text_h)/2' if style == 'center' else 'h-text_h-150'
        path = text_file(tmp, 't%02d_main.txt' % index, shot['telop'])
        out.append("drawtext=fontfile='%s':textfile='%s':fontsize=%d:fontcolor=white:borderw=7:bordercolor=0x10203a:"
                   "x=(w-text_w)/2:y=%s:alpha='%s'" % (FONT, path, size, y, fade))
    if shot.get('sub'):
        path = text_file(tmp, 't%02d_sub.txt' % index, shot['sub'])
        y = '(h/2)+80' if style == 'center' else 'h-text_h-80'
        out.append("drawtext=fontfile='%s':textfile='%s':fontsize=40:fontcolor=0xffe066:borderw=5:bordercolor=0x10203a:"
                   "x=(w-text_w)/2:y=%s:alpha='%s'" % (FONT, path, y, fade))
    if shot.get('note'):
        path = text_file(tmp, 't%02d_note.txt' % index, shot['note'])
        out.append("drawtext=fontfile='%s':textfile='%s':fontsize=26:fontcolor=white@0.85:borderw=3:bordercolor=0x10203a:"
                   "x=w-text_w-36:y=h-text_h-30:alpha='%s'" % (FONT, path, fade))
    return out


def render_shot(tmp, index, shot, fps):
    seg = os.path.join(tmp, 'seg_%02d.mov' % index)
    dur = float(shot['dur'])
    if 'card' in shot:
        bg = shot.get('bg', '#0b1630').replace('#', '0x')
        inputs = ['-f', 'lavfi', '-i', 'color=c=%s:s=%dx%d:r=%d:d=%f' % (bg, W, H, fps, dur),
                  '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo']
        chain = '[0:v]'
        filters = []
        if shot.get('image'):
            inputs += ['-loop', '1', '-t', '%f' % dur, '-i', os.path.join(ROOT, shot['image'])]
            scale = float(shot.get('image_scale', 0.5))
            filters.append('[2:v]scale=iw*%f:-1,format=rgba[logo]' % scale)
            filters.append('[0:v][logo]overlay=(W-w)/2:(H-h)/2-%d:format=auto[base]' % int(shot.get('image_lift', 60)))
            chain = '[base]'
        draw = telop_filters(tmp, index, shot, dur)
        filters.append(chain + (','.join(draw) if draw else 'null') + ',format=yuv420p[v]')
        ff(inputs + ['-filter_complex', ';'.join(filters), '-map', '[v]', '-map', '1:a', '-t', '%f' % dur,
                     '-c:v', 'libx264', '-crf', '14', '-preset', 'medium', '-c:a', 'pcm_s16le', '-ar', '48000', seg])
        return seg
    clip = os.path.join(MEZZ, shot['clip'] + '.mov')
    speed = float(shot.get('speed', 1.0))
    src_dur = dur * speed
    # Seek on the input (ProRes is all intra frames, so this is frame-accurate and fast).
    vf = ['setpts=(PTS-STARTPTS)/%f' % speed, 'fps=%d' % fps, 'scale=%d:%d' % (W, H)]
    if shot.get('dim'):
        keep = 1 - float(shot['dim'])
        vf.append('colorchannelmixer=rr=%f:gg=%f:bb=%f' % (keep, keep, keep))
    inputs = ['-ss', '%f' % float(shot['in']), '-t', '%f' % (src_dur + 0.05), '-i', clip]
    if shot.get('image'):
        inputs += ['-loop', '1', '-t', '%f' % dur, '-i', os.path.join(ROOT, shot['image'])]
        scale = float(shot.get('image_scale', 0.5))
        lift = int(shot.get('image_lift', 60))
        graph = ('[0:v]' + ','.join(vf) + '[base];[1:v]scale=iw*%f:-1,format=rgba,fade=t=in:st=0:d=0.3:alpha=1[logo];'
                 '[base][logo]overlay=(W-w)/2:(H-h)/2-%d:format=auto' % (scale, lift))
        draw = telop_filters(tmp, index, shot, dur)
        graph += (',' + ','.join(draw) if draw else '') + ',format=yuv420p[v]'
        video_args = ['-filter_complex', graph, '-map', '[v]']
    else:
        vf += telop_filters(tmp, index, shot, dur)
        vf.append('format=yuv420p')
        video_args = ['-vf', ','.join(vf)]
    af = ['atrim=duration=%f' % src_dur, 'asetpts=PTS-STARTPTS']
    if abs(speed - 1.0) > 1e-3:
        af.append('atempo=%f' % max(0.5, min(2.0, speed)))
    af += ['apad', 'atrim=duration=%f' % dur, 'afade=t=in:d=0.04', 'afade=t=out:st=%f:d=0.06' % max(0.0, dur - 0.06)]
    # Video and audio are rendered apart and then muxed: in one pass a sped-up clip with a
    # padded audio chain never finishes (the muxer waits on the endless pad).
    seg_v = os.path.join(tmp, 'seg_%02d_v.mov' % index)
    seg_a = os.path.join(tmp, 'seg_%02d_a.wav' % index)
    ff(inputs + video_args + ['-an', '-t', '%f' % dur, '-c:v', 'libx264', '-crf', '14', '-preset', 'medium', seg_v])
    ff(['-ss', '%f' % float(shot['in']), '-t', '%f' % (src_dur + 0.05), '-i', clip, '-vn', '-af', ','.join(af),
        '-t', '%f' % dur, '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2', seg_a])
    ff(['-i', seg_v, '-i', seg_a, '-map', '0:v', '-map', '1:a', '-c', 'copy', '-t', '%f' % dur, seg])
    return seg


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--edit', default=os.path.join(ROOT, 'tools', 'pv', 'edit.json'))
    parser.add_argument('--bgm', default=None)
    parser.add_argument('--out', default=os.path.join(ROOT, 'artifacts', 'pv', 'final', 'AIQUIZ3D_PV_rough.mp4'))
    a = parser.parse_args()
    edit = json.load(open(a.edit, encoding='utf-8'))
    fps = int(edit.get('fps', 60))
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        segs = [render_shot(tmp, i, shot, fps) for i, shot in enumerate(edit['shots'])]
        listing = os.path.join(tmp, 'list.txt')
        with open(listing, 'w', encoding='utf-8') as fh:
            for seg in segs:
                fh.write("file '%s'\n" % seg.replace('\\', '/'))
        joined = os.path.join(tmp, 'joined.mov')
        ff(['-f', 'concat', '-safe', '0', '-i', listing, '-c', 'copy', joined])
        total = sum(float(s['dur']) for s in edit['shots'])
        sfx = float(edit.get('sfx_gain_db', -4.0))
        if a.bgm:
            ff(['-i', joined, '-stream_loop', '-1', '-i', a.bgm, '-filter_complex',
                '[0:a]volume=%fdB[g];[1:a]atrim=duration=%f,afade=t=out:st=%f:d=1.5,volume=-6dB[m];'
                '[g][m]amix=inputs=2:normalize=0,loudnorm=I=-14:TP=-1.0:LRA=11[a]' % (sfx, total, max(0.0, total - 1.5)),
                '-map', '0:v', '-map', '[a]', '-c:v', 'libx264', '-crf', '17', '-preset', 'slow', '-profile:v', 'high',
                '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-movflags', '+faststart', a.out])
        else:
            ff(['-i', joined, '-af', 'volume=%fdB,loudnorm=I=-14:TP=-1.0:LRA=11' % sfx, '-c:v', 'libx264', '-crf', '17',
                '-preset', 'slow', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k', '-ar', '48000',
                '-movflags', '+faststart', a.out])
    print(json.dumps({'out': a.out, 'seconds': round(total, 2), 'shots': len(edit['shots'])}, ensure_ascii=False))


if __name__ == '__main__':
    main()
