"""Turns PV captures into edit-ready clips (tools/pv/README.md).

    python tools/pv/encode.py G:/aiquiz_pv_raw/intro_solo_t2 [--preview]

For every segment in <take>/marks.json:
  artifacts/pv/mezz/<shot>_t<take>_<tag>.mov     ProRes 422 HQ, 1920x1080, 60 fps, PCM 48 kHz stereo
  artifacts/pv/review/<shot>_t<take>_<tag>.jpg   contact sheet, one frame every half second
  artifacts/pv/review/<shot>_t<take>_<tag>.mp4   (--preview) small H.264 for a quick look
The JPEG frames are named by Engine.get_frames_drawn(); the Movie Maker AVI runs on the same frame
clock (its frame 0 is the white sync frame), so a segment's audio is the AVI's [first/60, (last+1)/60].
"""
import json
import os
import subprocess
import sys

FFMPEG = 'C:/ffmpeg/bin/ffmpeg.exe'
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MEZZ = os.path.join(ROOT, 'artifacts', 'pv', 'mezz')
REVIEW = os.path.join(ROOT, 'artifacts', 'pv', 'review')


def run(args):
    proc = subprocess.run([FFMPEG, '-y', '-nostdin', '-v', 'error'] + args, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip()[-2000:])


def main():
    take_dir = sys.argv[1].rstrip('/\\')
    preview = '--preview' in sys.argv
    marks = json.load(open(os.path.join(take_dir, 'marks.json'), encoding='utf-8'))
    shot, take = marks['shot'], marks['take']
    fps = int(marks.get('fps', 60))
    sync = int(marks.get('sync_frame', 0))
    os.makedirs(MEZZ, exist_ok=True)
    os.makedirs(REVIEW, exist_ok=True)
    frames = os.path.join(take_dir, 'frames', '%08d.jpg')
    movie = os.path.join(take_dir, 'movie.avi')
    report = []
    for seg in marks['segments']:
        first, last, tag = int(seg['first']), int(seg['last']), seg['tag']
        if first < 0 or last < first:
            continue
        count = last - first + 1
        name = '%s_t%d_%s' % (shot, take, tag)
        start = (first - sync) / fps
        duration = count / fps
        mov = os.path.join(MEZZ, name + '.mov')
        run(['-framerate', str(fps), '-start_number', str(first), '-i', frames,
             '-ss', '%.6f' % start, '-t', '%.6f' % duration, '-i', movie,
             '-map', '0:v', '-map', '1:a?', '-frames:v', str(count),
             '-c:v', 'prores_ks', '-profile:v', '3', '-pix_fmt', 'yuv422p10le',
             '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
             '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2', '-shortest', mov])
        step = max(1, fps // 2)
        run(['-framerate', str(fps), '-start_number', str(first), '-i', frames, '-frames:v', str(count),
             '-vf', "select='not(mod(n\\,%d))',scale=320:-1,tile=6x%d" % (step, max(1, (count // step + 5) // 6)),
             '-frames:v', '1', os.path.join(REVIEW, name + '.jpg')])
        if preview:
            run(['-i', mov, '-vf', 'scale=960:-2', '-c:v', 'libx264', '-crf', '26', '-preset', 'veryfast',
                 '-c:a', 'aac', '-b:a', '128k', os.path.join(REVIEW, name + '.mp4')])
        report.append({'clip': name, 'frames': count, 'seconds': round(duration, 2)})
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
