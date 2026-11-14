"""record_take.py で撮った素材（AVI）を、審査用のプレイ動画（1920x1080・60fps・MP4）に仕上げる。

    python -X utf8 tests/submission_video/compose.py online <素材フォルダ> <出力.mp4>   # C：2 画面を並べる
    python -X utf8 tests/submission_video/compose.py solo <素材.avi> <出力.mp4> [--start 秒] [--end 秒]
    python -X utf8 tests/submission_video/compose.py screen <素材フォルダ> <出力.mp4>   # E：実時間の取り込み + ゲームの音

online：ホストの画面（大）とゲストの画面（小）を 1 枚に並べ、音はホストの画面のものを使う。
2 本の AVI は別々のプロセスが書いたものなので、台本が残したフレームごとの実時刻（<役>.json の "clock"）で
ゲストのフレームをホストのフレームに合わせる（読み込みで片方が止まった所は、止まった側の絵を止めて合わせる）。
"""
from __future__ import annotations

import argparse
import bisect
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONTS = Path(r"C:\Windows\Fonts")
NAVY = (11, 21, 48)
PANEL = (20, 34, 72)
WHITE = (255, 255, 255)
SOFT = (188, 200, 228)
YELLOW = (255, 205, 60)
HOST_BOX = (32, 170, 1280, 720)
GUEST_BOX = (1344, 170, 544, 306)
## E の音は Godot の Dummy の音声ドライバーで録る（PC から鳴らさないため）。Dummy は実時間より少し遅く回り、
## 録った音は 1 秒あたり約 2 ms 短い（効果音の時刻と録音を比べて測った）。そのぶん音を引きのばして絵に合わせる。
DUMMY_AUDIO_DRIFT = 0.002
AUDIO_RATE = 44100
X264 = ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p", "-r", "60",
        "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
        "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"]
## 色：Movie Maker の AVI（MJPEG）は BT.601・フルレンジ、画面の取り込み（nvenc）は BT.601・リミテッドで印なし。
## どちらも、HD の動画でふつうの BT.709・リミテッドに直し、その印を付ける（印がないと再生側が BT.709 とみなして色がずれる）。
FROM_MJPEG = "in_range=full:in_color_matrix=bt601:out_range=tv:out_color_matrix=bt709"
FROM_SCREEN = "in_range=tv:in_color_matrix=bt601:out_range=tv:out_color_matrix=bt709"
TO_709 = "out_range=tv:out_color_matrix=bt709"


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"NotoSansJP-{weight}.ttf"), size)


def probe_frames(path: Path) -> int:
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=nb_frames",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True).stdout
    return int(out.strip().strip(","))


def load_clock(folder: Path, role: str) -> tuple[dict, list[int], list[float]]:
    report = json.loads((folder / f"{role}.json").read_text(encoding="utf-8"))
    clock = report["clock"]
    frames = [int(f) for f in clock["frames"]]
    # AVI は台本より先に回り始めている。最後のフレームをそろえて、台本のフレーム番号 → AVI のフレーム番号にする
    shift = probe_frames(folder / f"{role}.avi") - 1 - frames[-1]
    return report, [f + shift for f in frames], [float(u) for u in clock["unix"]]


def background(path: Path, version: str) -> None:
    image = Image.new("RGB", (1920, 1080), NAVY)
    draw = ImageDraw.Draw(image)
    draw.text((32, 34), "オンライン対戦", font=font("ExtraBold", 50), fill=WHITE)
    draw.text((420, 56), "1 台の PC で TESTOPIA を 2 つ起動して、ランダムマッチで対戦", font=font("Medium", 28), fill=SOFT)
    for box in (HOST_BOX, GUEST_BOX):
        x, y, w, h = box
        draw.rectangle((x - 4, y - 4, x + w + 3, y + h + 3), fill=PANEL)
    hx, hy, hw, hh = HOST_BOX
    gx, gy, gw, gh = GUEST_BOX
    draw.rectangle((hx, hy + hh + 22, hx + 10, hy + hh + 62), fill=YELLOW)
    draw.text((hx + 24, hy + hh + 18), "ソラの画面", font=font("ExtraBold", 34), fill=WHITE)
    draw.text((hx + 220, hy + hh + 26), "音はこちらの画面のもの", font=font("Medium", 24), fill=SOFT)
    draw.rectangle((gx, gy + gh + 22, gx + 10, gy + gh + 62), fill=(90, 190, 255))
    draw.text((gx + 24, gy + gh + 18), "ハテナの画面", font=font("ExtraBold", 34), fill=WHITE)
    draw.text((gx + 268, gy + gh + 26), "対戦相手", font=font("Medium", 24), fill=SOFT)
    notes = [
        "通信は中継サーバーを通る",
        "（撮影では同じ PC に用意）",
        "問題は内蔵の問題",
        "（算数・3年・ふつう）",
        "操作は 2 人とも自動（撮影用）",
        f"版 {version}",
    ]
    y = gy + gh + 110
    for line in notes:
        indent = line.startswith("（")
        if not indent:
            draw.ellipse((gx + 4, y + 16, gx + 14, y + 26), fill=YELLOW)
        draw.text((gx + 30, y), line, font=font("Medium", 26), fill=SOFT if indent else WHITE)
        y += 40 if indent else 46
        if indent:
            y += 10
    image.save(path)


def guest_map(folder: Path) -> tuple[int, int, list[int], dict, dict]:
    """ホストの AVI のフレーム h ごとに、同じ実時刻のゲストの AVI のフレームを返す。"""
    host, hf, hu = load_clock(folder, "host")
    guest, gf, gu = load_clock(folder, "guest")
    # 始まり：ゲストのオンラインメニューが出た少しあと。終わり：どちらかが終わる少し前
    guest_menu = int(guest["marks"]["menu"]) + (gf[0] - int(guest["clock"]["frames"][0])) + 45
    start_unix = gu[min(range(len(gf)), key=lambda i: abs(gf[i] - guest_menu))]
    end_unix = min(hu[-1], gu[-1]) - 0.6
    mapping: list[int] = []
    first = last = -1
    for i, unix in enumerate(hu):
        if unix < start_unix or unix > end_unix:
            continue
        j = bisect.bisect_left(gu, unix)
        if j > 0 and (j == len(gu) or unix - gu[j - 1] <= gu[j] - unix):
            j -= 1
        if first < 0:
            first = hf[i]
        last = hf[i]
        mapping.append(gf[j])
    # ずれが 3 フレーム（50 ms）になるまでは、ゲストをそのまま 1 フレームずつ進める（こまかい止め・とばしを作らない）
    for i in range(1, len(mapping)):
        steady = mapping[i - 1] + 1
        mapping[i] = steady if abs(mapping[i] - steady) < 3 else max(mapping[i], mapping[i - 1])
    return first, last, mapping, host, guest


def write_concat(path: Path, avi: Path, mapping: list[int]) -> dict:
    """ゲストのフレームの並び（止める所・とばす所つき）を ffconcat に書く。"""
    runs: list[list[int]] = []  # [ゲストの最初のフレーム, 進むフレーム数, そのあと止めるフレーム数]
    for g in mapping:
        if runs and runs[-1][2] == 0 and g == runs[-1][0] + runs[-1][1]:
            runs[-1][1] += 1
        elif runs and g == runs[-1][0] + runs[-1][1] - 1:
            runs[-1][2] += 1
        else:
            runs.append([g, 1, 0])
    lines = ["ffconcat version 1.0"]
    for g, count, freeze in runs:
        lines += [f"file '{avi.as_posix()}'", f"inpoint {(g - 0.25) / 60:.6f}", f"outpoint {(g + count - 0.25) / 60:.6f}"]
        if freeze:
            lines.append(f"duration {(count + freeze) / 60:.6f}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"runs": len(runs), "frozen_frames": sum(r[2] for r in runs),
            "skipped_frames": sum(max(0, runs[i + 1][0] - (runs[i][0] + runs[i][1])) for i in range(len(runs) - 1))}


def compose_online(folder: Path, out: Path, version: str) -> None:
    first, last, mapping, host, guest = guest_map(folder)
    info = write_concat(folder / "guest.ffconcat", folder / "guest.avi", mapping)
    background(folder / "background.png", version)
    count = last - first + 1
    seconds = count / 60
    print(f"host frames {first}..{last} ({seconds:.1f} s), guest alignment: {info}")
    hx, hy, hw, hh = HOST_BOX
    gx, gy, gw, gh = GUEST_BOX
    graph = (
        f"[0:v]scale={hw}:{hh}:flags=lanczos:{FROM_MJPEG},format=yuv420p[h];"
        f"[1:v]fps=60,scale={gw}:{gh}:flags=lanczos:{FROM_MJPEG},format=yuv420p[g];"
        f"[2:v]scale={TO_709},format=yuv420p[bg];"
        f"[bg][h]overlay={hx}:{hy}[a];[a][g]overlay={gx}:{gy},"
        f"fade=t=in:st=0:d=0.4,fade=t=out:st={seconds - 0.5:.3f}:d=0.5[v];"
        f"[0:a]afade=t=in:st=0:d=0.4,afade=t=out:st={seconds - 0.5:.3f}:d=0.5[au]"
    )
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y",
           "-ss", f"{(first - 0.25) / 60:.6f}", "-t", f"{seconds:.6f}", "-i", str(folder / "host.avi"),
           "-f", "concat", "-safe", "0", "-i", str(folder / "guest.ffconcat"),
           "-loop", "1", "-framerate", "60", "-t", f"{seconds:.6f}", "-i", str(folder / "background.png"),
           "-filter_complex", graph, "-map", "[v]", "-map", "[au]", "-t", f"{seconds:.6f}", *X264, str(out)]
    subprocess.run(cmd, check=True)


def label_image(path: Path, text: str) -> None:
    """画面の左下に出す札（透明の 1920x1080 の PNG）。"""
    image = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    face = font("SemiBold", 26)
    width = int(draw.textlength(text, font=face))
    x, y = 24, 1080 - 24 - 52
    draw.rounded_rectangle((x, y, x + width + 62, y + 52), radius=10, fill=(11, 21, 48, 225))
    draw.rectangle((x + 16, y + 12, x + 24, y + 40), fill=YELLOW)
    draw.text((x + 40, y + 5), text, font=face, fill=WHITE)
    image.save(path)


def compose_solo(avi: Path, out: Path, start: float, end: float, label: str = "") -> None:
    total = probe_frames(avi) / 60
    end = total if end <= 0 else min(end, total)
    seconds = end - start
    inputs = ["-ss", f"{start:.6f}", "-t", f"{seconds:.6f}", "-i", str(avi)]
    overlay = ""
    if label:
        label_image(avi.with_name("label.png"), label)
        inputs += ["-loop", "1", "-framerate", "60", "-t", f"{seconds:.6f}", "-i", str(avi.with_name("label.png"))]
        overlay = f"[base];[1:v]scale={TO_709},format=yuva420p[lb];[base][lb]overlay=0:0"
    graph = (f"[0:v]scale={FROM_MJPEG},format=yuv420p{overlay},fade=t=in:st=0:d=0.4,fade=t=out:st={seconds - 0.5:.3f}:d=0.5[v];"
             f"[0:a]afade=t=in:st=0:d=0.4,afade=t=out:st={seconds - 0.5:.3f}:d=0.5[au]")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", *inputs,
           "-filter_complex", graph, "-map", "[v]", "-map", "[au]", "-t", f"{seconds:.6f}", *X264, str(out)]
    subprocess.run(cmd, check=True)


def compose_screen(folder: Path, out: Path, take: str, patch_left: int) -> None:
    """実時間の取り込み（screen.mkv。時刻は実時刻）と、ゲームが残した音（<台本>.wav）を、台本の印の時刻で切って合わせる。"""
    report = json.loads((folder / f"{take}.json").read_text(encoding="utf-8"))
    start = float(report["marks_unix"]["menu"]) + 0.3
    end = float(report["marks_unix"]["end"])
    seconds = end - start
    audio_from = start - float(report["audio_start_unix"])
    # 2 台目のモニターの左端には、となりのモニターの窓のふちが数 px 写り込む。ゲームの絵ではないので、すぐ右の列で埋める
    patch = f"split[full][edge];[edge]crop={patch_left}:1080:{patch_left}:0[fill];[full][fill]overlay=0:0," if patch_left > 0 else ""
    graph = (f"[0:v]setpts=PTS-{start:.3f}/TB,trim=start=0:end={seconds:.3f},fps=60,scale=1920:1080:flags=lanczos:{FROM_SCREEN},{patch}format=yuv420p,"
             f"fade=t=in:st=0:d=0.4,fade=t=out:st={seconds - 0.5:.3f}:d=0.5[v];"
             f"[1:a]asetrate={AUDIO_RATE}*{1.0 - DUMMY_AUDIO_DRIFT},aresample=48000,"
             f"atrim=start={audio_from:.3f}:end={audio_from + seconds:.3f},asetpts=PTS-STARTPTS,"
             f"afade=t=in:st=0:d=0.4,afade=t=out:st={seconds - 0.5:.3f}:d=0.5[au]")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-y", "-copyts", "-i", str(folder / "screen.mkv"),
           "-i", str(folder / f"{take}.wav"), "-filter_complex", graph, "-map", "[v]", "-map", "[au]",
           "-t", f"{seconds:.3f}", *X264, str(out)]
    print(f"screen take: {seconds:.1f} s, audio offset {audio_from:.3f} s")
    subprocess.run(cmd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["online", "solo", "screen"])
    parser.add_argument("source")
    parser.add_argument("out")
    parser.add_argument("--start", type=float, default=0.0)
    parser.add_argument("--end", type=float, default=0.0)
    parser.add_argument("--version", default="v1.0.3")
    parser.add_argument("--take", default="solo_ai")
    parser.add_argument("--label", default="", help="solo：画面の左下に出しつづける札の文")
    parser.add_argument("--patch-left", type=int, default=0, help="screen：左端の何 px を右どなりの列で埋めるか")
    args = parser.parse_args()
    out = Path(args.out).resolve()
    if args.kind == "online":
        compose_online(Path(args.source).resolve(), out, args.version)
    elif args.kind == "screen":
        compose_screen(Path(args.source).resolve(), out, args.take, args.patch_left)
    else:
        compose_solo(Path(args.source).resolve(), out, args.start, args.end, args.label)
    print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
