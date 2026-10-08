"""Turns the After Effects master into the submission mp4 and checks it (tools/pv/README.md).

    python tools/pv/finalize.py [--master artifacts/pv/final/AIQUIZ3D_PV_master_ae.mov]
                                [--out artifacts/pv/final/AIQUIZ3D_PV.mp4]
                                [--thumb artifacts/pv/final/AIQUIZ3D_thumbnail.png]

  - H.264 High, yuv420p, 1920x1080, constant 60 fps, BT.709 tags, AAC 320k 48 kHz stereo, +faststart
  - gain to -14 LUFS integrated with a 4x-oversampled -2.5 dB limiter (true peak about -1 dBTP after AAC)
  - report <out>.check.json: format, a full decode, blackdetect, freezedetect, EBU R128 loudness,
    and the contest limits (mp4, 15-90 s, 16:9 thumbnail); a one-frame-per-second contact sheet
    <out>.contact.jpg; the thumbnail also as JPEG
"""
import argparse
import json
import os
import re
import subprocess

FFMPEG = 'C:/ffmpeg/bin/ffmpeg.exe'
FFPROBE = os.path.expanduser('~/AppData/Local/Programs/Python/Python310/Scripts/ffprobe.exe')
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FINAL = os.path.join(ROOT, 'artifacts', 'pv', 'final')
LUFS, TP, LRA = -14.0, -1.0, 11.0


def ff(args, check=True):
    proc = subprocess.run([FFMPEG, '-y', '-nostdin', '-hide_banner'] + args, capture_output=True, text=True,
                          encoding='utf-8', errors='replace')
    if check and proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip()[-3000:])
    return proc


def probe(path):
    out = subprocess.run([FFPROBE, '-v', 'error', '-show_format', '-show_streams', '-of', 'json', path],
                         capture_output=True, text=True, encoding='utf-8')
    return json.loads(out.stdout)


def measure(path):
    """loudnorm first pass: the measured values for the second pass."""
    log = ff(['-i', path, '-vn', '-af', 'loudnorm=I=%g:TP=%g:LRA=%g:print_format=json' % (LUFS, TP, LRA),
              '-f', 'null', '-']).stderr
    return json.loads(log[log.rindex('{'):log.rindex('}') + 1])


def master_audio(master, wav):
    """Gain to the target loudness, then a peak limiter with room for intersample peaks and the AAC
    encode. The game's hits are spiky, so a plain linear gain would clip and loudnorm's dynamic
    fallback overshoots; the gain is corrected until the limited mix measures on target."""
    first = measure(master)
    gain = LUFS - float(first['input_i'])
    for _ in range(4):
        # limited at 4x oversampling (close to true peak), 1.5 dB under the target for the AAC encode
        limit = 10 ** ((TP - 1.5) / 20)
        ff(['-i', master, '-vn', '-af', 'volume=%.3fdB,aresample=192000,'
            'alimiter=limit=%.4f:attack=2:release=80:level=disabled,'
            'alimiter=limit=%.4f:attack=0.5:release=20:level=disabled,aresample=48000' % (gain, limit, limit),
            '-c:a', 'pcm_s24le', '-ac', '2', wav])
        now = measure(wav)
        miss = LUFS - float(now['input_i'])
        if abs(miss) < 0.15:
            break
        gain += miss
    return {'input_i': first['input_i'], 'input_tp': first['input_tp'], 'gain_db': round(gain, 2),
            'out_i': now['input_i'], 'out_tp': now['input_tp']}


def encode(master, out):
    wav = os.path.splitext(out)[0] + '.mix.wav'
    m = master_audio(master, wav)
    ff(['-i', master, '-i', wav, '-map', '0:v:0', '-map', '1:a:0',
        '-vf', 'scale=1920:1080:flags=lanczos,fps=60,format=yuv420p',
        '-c:v', 'libx264', '-profile:v', 'high', '-preset', 'slow', '-crf', '16', '-g', '120',
        '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
        '-c:a', 'aac', '-b:a', '320k', '-ar', '48000', '-ac', '2', '-shortest', '-movflags', '+faststart', out])
    os.remove(wav)
    return m


def check(out, thumb):
    info = probe(out)
    v = next(s for s in info['streams'] if s['codec_type'] == 'video')
    a = next((s for s in info['streams'] if s['codec_type'] == 'audio'), None)
    duration = float(info['format']['duration'])
    decode = ff(['-v', 'error', '-i', out, '-f', 'null', '-'], check=False)
    scan = ff(['-i', out, '-vf', 'blackdetect=d=0.3:pix_th=0.04,freezedetect=n=0.003:d=1.5',
               '-af', 'ebur128=peak=true', '-f', 'null', '-'], check=False).stderr
    black = re.findall(r'black_start:([\d.]+) black_end:([\d.]+)', scan)
    freeze = re.findall(r'freeze_start: ([\d.]+)[\s\S]*?freeze_end: ([\d.]+)', scan)
    summary = scan[scan.rfind('Summary:'):]
    loud = float(re.search(r'I:\s+(-?[\d.]+) LUFS', summary).group(1))
    peak = float(re.search(r'Peak:\s+(-?[\d.]+) dBFS', summary).group(1))
    report = {
        'file': out,
        'size_mb': round(os.path.getsize(out) / 1e6, 1),
        'duration_s': round(duration, 3),
        'video': {'codec': v['codec_name'], 'profile': v.get('profile'), 'size': [v['width'], v['height']],
                  'pix_fmt': v['pix_fmt'], 'fps': v['r_frame_rate'], 'frames': v.get('nb_frames')},
        'audio': {'codec': a['codec_name'], 'rate': a['sample_rate'], 'channels': a['channels']} if a else None,
        'decode_errors': decode.stderr.strip()[-1000:] or None,
        'black': [[float(s), float(e)] for s, e in black],
        'freeze': [[float(s), float(e)] for s, e in freeze],
        'loudness_lufs': loud,
        'true_peak_dbfs': peak,
    }
    rules = {
        'mp4': out.lower().endswith('.mp4') and 'mp4' in info['format']['format_name'],
        '15_to_90_s': 15.0 <= duration <= 90.0,
        '1920x1080': [v['width'], v['height']] == [1920, 1080],
        'h264_aac': v['codec_name'] == 'h264' and a is not None and a['codec_name'] == 'aac',
        'decodes_clean': not report['decode_errors'],
        'no_black_gaps': not report['black'],
        'loudness_ok': abs(loud - LUFS) <= 1.0 and peak <= -0.5,
    }
    if thumb and os.path.exists(thumb):
        t = next(s for s in probe(thumb)['streams'] if s['codec_type'] == 'video')
        report['thumbnail'] = {'file': thumb, 'size': [t['width'], t['height']]}
        rules['thumbnail_16_9'] = t['width'] * 9 == t['height'] * 16
        jpg = os.path.splitext(thumb)[0] + '.jpg'
        ff(['-v', 'error', '-i', thumb, '-q:v', '2', jpg])
        report['thumbnail']['jpg'] = jpg
    report['rules'] = rules
    report['ok'] = all(rules.values())
    rows = max(1, int(duration + 5) // 6)
    ff(['-v', 'error', '-i', out, '-vf', 'fps=1,scale=320:-1,tile=6x%d' % rows, '-frames:v', '1',
        os.path.splitext(out)[0] + '.contact.jpg'])
    with open(os.path.splitext(out)[0] + '.check.json', 'w', encoding='utf-8') as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--master', default=os.path.join(FINAL, 'AIQUIZ3D_PV_master_ae.mov'))
    parser.add_argument('--out', default=os.path.join(FINAL, 'AIQUIZ3D_PV.mp4'))
    parser.add_argument('--thumb', default=os.path.join(FINAL, 'AIQUIZ3D_thumbnail.png'))
    parser.add_argument('--check-only', action='store_true')
    a = parser.parse_args()
    if not a.check_only:
        measured = encode(a.master, a.out)
        print('audio', json.dumps(measured))
    print(json.dumps(check(a.out, a.thumb), ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
