"""審査用のプレイ動画（docs/submission の 04_プレイ動画 C〜E）の素材を撮る。

Godot の Movie Maker（--write-movie）で、ゲームの絵と音を 60fps の AVI に書き出す。画面の取り込みではないので、
ほかの窓が重なっても写らず、ゲームの音も PC からは鳴らない。ゲームの窓は画面の外に出す。

    python -X utf8 tests/submission_video/record_take.py online <出力フォルダ>     # C：中継サーバー + ホスト + ゲスト
    python -X utf8 tests/submission_video/record_take.py <台本の名前> <出力フォルダ> [台本への引数 ...]
        台本は tests/submission_video/<名前>_runtime.gd。1 つのゲームを 1920x1080 で撮る。
    python -X utf8 tests/submission_video/record_take.py solo_ai <出力フォルダ>    # E：実時間。2 台目のモニターを取り込む

出力：<役>.avi（絵と音）、<役>.json（台本の報告。フレームごとの実時刻つき）、<役>.log。
編集（2 画面を並べる・MP4 にする）は tests/submission_video/compose.py。
"""
from __future__ import annotations

import ctypes
import ctypes.wintypes as wt
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELAY = ROOT.parent / "relay-server"
GODOT = ROOT / "Godot_v4.7.2-stable_win64_console.exe"
PORT = 18766
RELAY_WS = f"ws://127.0.0.1:{PORT}"
BOOTSTRAP = "tests/net/net_match_bootstrap.gd"

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
ctypes.windll.shcore.SetProcessDpiAwareness(2)
user32.SetForegroundWindow.argtypes = [wt.HWND]
user32.GetForegroundWindow.restype = wt.HWND


def offscreen_x() -> int:
    """すべてのモニターの右端より外（窓を出しても見えない位置）。"""
    return user32.GetSystemMetrics(76) + user32.GetSystemMetrics(78) + 200


def health() -> dict:
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=3) as resp:
        return json.loads(resp.read())


def wait_for(predicate, timeout: float, what: str) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except Exception:
            pass
        time.sleep(0.2)
    raise SystemExit(f"timed out waiting for {what}")


def family(pid: int) -> set[int]:
    """コンソール版の exe は、本体を子プロセスとして起動する。窓は子のもの。"""
    out = subprocess.run(["powershell", "-NoProfile", "-Command",
                          f"(Get-CimInstance Win32_Process -Filter 'ParentProcessId={pid}').ProcessId"],
                         capture_output=True, text=True).stdout.split()
    return {pid} | {int(x) for x in out if x.isdigit()}


def keep_focus(previous: int, pids: set[int], seconds: float) -> None:
    """ゲームの窓が前面を取ったら、元の窓へ返す（作業中のキー入力がゲームに入らないように）。"""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        fg = user32.GetForegroundWindow()
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(fg, ctypes.byref(owner))
        if fg and owner.value in pids and previous and user32.IsWindow(previous):
            # Alt を一度押すと、ほかのプロセスの窓を前面にできる
            user32.keybd_event(0x12, 0, 0, 0)
            user32.keybd_event(0x12, 0, 2, 0)
            user32.SetForegroundWindow(previous)
            return
        time.sleep(0.05)


def launch(out: Path, role: str, runtime: str, size: str, extra: list[str], slot: int) -> tuple[subprocess.Popen, object]:
    log = open(out / f"{role}.log", "w", encoding="utf-8")
    (out / f"{role}.json").unlink(missing_ok=True)
    (out / f"{role}.avi").unlink(missing_ok=True)
    cmd = [str(GODOT), "--path", str(ROOT), "--resolution", size, "--position", f"{offscreen_x()},{slot * 60}",
           "--disable-vsync", "--fixed-fps", "60", "--write-movie", (out / f"{role}.avi").as_posix(),
           "--script", BOOTSTRAP, "--", f"runtime=res://tests/submission_video/{runtime}_runtime.gd",
           f"out={(out / f'{role}.json').as_posix()}", *extra]
    previous = user32.GetForegroundWindow()
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    time.sleep(0.4)
    keep_focus(previous, family(proc.pid), 12.0)
    return proc, log


def finish(procs: list, timeout: float) -> list[int]:
    deadline = time.monotonic() + timeout
    codes = []
    for proc, log in procs:
        try:
            proc.wait(max(1.0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
        codes.append(proc.returncode)
        log.close()
    return codes


def take_online(out: Path, extra: list[str]) -> list[int]:
    relay_log = open(out / "relay.log", "w", encoding="utf-8")
    # 撮影中のゲームは実時間の約 1/5 の速さで進む（ping は 5 秒に 1 回になる）。中継サーバーが「返事がない」と
    # 切らないよう、無通信の待ち時間を延ばす（ふつうは 6 秒）。
    relay = subprocess.Popen([sys.executable, "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", str(PORT)],
                             cwd=RELAY, stdout=relay_log, stderr=subprocess.STDOUT,
                             env={**os.environ, "RELAY_HEARTBEAT_S": "120"})
    procs = []
    try:
        wait_for(lambda: health()["status"] == "ok", 20, "relay")
        # 大きさは 1920x1080（画面写真 shots/ がこの大きさになる。動画の中では縮めて置く）
        procs.append(launch(out, "host", "online_showcase", "1920x1080",
                            ["role=host", f"relay={RELAY_WS}", "pace=12.5", f"shots={(out / 'shots').as_posix()}", *extra], 0))
        wait_for(lambda: health()["queued"] >= 1, 240, "host to queue")
        procs.append(launch(out, "guest", "online_showcase", "1920x1080", ["role=guest", f"relay={RELAY_WS}", "pace=12.5", *extra], 1))
        return finish(procs, 2400)
    finally:
        for proc, _log in procs:
            if proc.poll() is None:
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
        relay.terminate()
        relay.wait(10)
        relay_log.close()


def take_screen(out: Path, take: str, extra: list[str]) -> list[int]:
    """実時間で撮る（AI の待ち時間を本当の長さで写す動画用）。ゲームを 2 台目のモニターに全画面で出し、
    そのモニターを ffmpeg（ddagrab）で取り込む。音はゲームが自分で WAV に残す（PC からは鳴らさない）。"""
    (out / "screen.mkv").unlink(missing_ok=True)
    (out / f"{take}.wav").unlink(missing_ok=True)
    (out / f"{take}.json").unlink(missing_ok=True)
    ff_log = open(out / "ffmpeg.log", "w", encoding="utf-8")
    ff = subprocess.Popen(["ffmpeg", "-hide_banner", "-y", "-filter_complex",
                           "ddagrab=output_idx=1:framerate=60:draw_mouse=0,setpts='time(0)/TB'", "-copyts",
                           "-c:v", "h264_nvenc", "-preset", "p5", "-rc", "constqp", "-qp", "16", "-g", "60", str(out / "screen.mkv")],
                          stdin=subprocess.PIPE, stdout=ff_log, stderr=subprocess.STDOUT)
    log = open(out / f"{take}.log", "w", encoding="utf-8")
    cmd = [str(GODOT), "--path", str(ROOT), "--audio-driver", "Dummy", "--resolution", "1280x720", "--position", "2700,400",
           "--script", BOOTSTRAP, "--", f"runtime=res://tests/submission_video/{take}_runtime.gd",
           f"out={(out / f'{take}.json').as_posix()}", "screen=second", f"record_audio={(out / f'{take}.wav').as_posix()}", *extra]
    previous = user32.GetForegroundWindow()
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        time.sleep(0.4)
        keep_focus(previous, family(proc.pid), 12.0)
        return finish([(proc, log)], 900)
    finally:
        try:
            ff.stdin.write(b"q")
            ff.stdin.flush()
            ff.wait(20)
        except Exception:
            ff.kill()
        ff_log.close()


def main() -> int:
    take = sys.argv[1]
    out = Path(sys.argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    extra = sys.argv[3:]
    if take == "online":
        codes = take_online(out, extra)
    elif take == "solo_ai":
        codes = take_screen(out, take, extra)
    else:
        codes = finish([launch(out, take, take, "1920x1080", [f"shots={(out / 'shots').as_posix()}", *extra], 0)], 3600)
    print("exit codes:", codes)
    return 0 if all(code == 0 for code in codes) else 1


if __name__ == "__main__":
    sys.exit(main())
