"""新しい PC で試合中に固まらないかを、この PC で確かめる（Windows・NVIDIA で確認）。

新しい PC では、ゲームが初めて描くもの（材質・描き方）ごとに、グラフィックドライバーが描画の部品
（パイプライン）を作り、作り終えるまで画面が止まる。この PC ではドライバーとゲームのキャッシュに
部品が残っているので、そのまま遊んでも再現しない。そこで次のようにして「はじめての PC」を作る：

  * 書き出した製品版を、まだ一度も使っていない名前のフォルダと exe 名で置く
    （NVIDIA のドライバーは exe ごとにキャッシュを分けるので、空のキャッシュから作り直す）
  * ゲームのキャッシュ（user://shader_cache・user://vulkan）をよけておく（終わったら戻す）
  * テスト入りの書き出し（tests/ を含める）に、override.cfg で tests/perf_probe_entry.gd を足し、
    tests/perf_runtime.gd の自動プレイ（正解・わざと間違い・海に落ちる）で遊ばせて 1 フレームずつ記録する

ネットワークは使わない（exe の横に、すべての通信先を閉じたポートへ向ける .env を置く）。
プレイヤーの設定・記録（user:// の直下のファイル）は始める前に写しを取り、終わったら戻す。

使い方（プロジェクトのフォルダで）:
  python -X utf8 tools/perf/fresh_pc_probe.py              # 書き出し + 決まった場面をすべて
  python -X utf8 tools/perf/fresh_pc_probe.py --no-export  # 前回の書き出しを使う
  python -X utf8 tools/perf/fresh_pc_probe.py --scenario wrong_and_shark
合格の条件（場面ごと）: 試合中（PLAYING 以降）に、止まりの元になる部品（canvas・mesh・surface・draw）を
作らないこと、50 ms を超えるフレームがないこと。結果は artifacts/fresh_pc_probe/summary.json。
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "artifacts", "fresh_pc_probe")
BUILD = os.path.join(OUT, "build")
USER = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "TESTOPIA")
GODOT = os.path.join(ROOT, "Godot_v4.7.2-stable_win64_console.exe")
BLOCKED_ENV = (
    "PROXY_URL=http://127.0.0.1:9\n"
    "FIREBASE_DB_URL=http://127.0.0.1:9\n"
    "RELAY_SERVER_URL=ws://127.0.0.1:9\n"
)
SCENARIOS = {
    # 正解だけで 10 問を最後まで（ボス壁・ゴール・クリア）
    "ten_correct": ["--mode=ten", "--walls=40", "--tail_seconds=30"],
    # 3 枚目で間違えてハートが減り、5 枚目で海に落ちてサメにかまれる（エンドレス）
    "wrong_and_shark": ["--walls=40", "--wrong_every=3", "--ocean_at=4", "--tail_seconds=15"],
    # 2 人で 10 問（P2 は動かないので間違えて脱落する）
    "duo_ten": ["--players=2", "--mode=ten", "--walls=40", "--tail_seconds=30"],
}
HITCH_MS = 50.0
PLAY_STATES = {5: "PLAYING", 6: "CORRECT", 7: "GAME_OVER", 8: "CLEAR", 9: "GOAL_RACE", 10: "RESULT_CEREMONY", 11: "SUDDEN_DEATH"}
STALL_KINDS = ("canvas", "mesh", "surface", "draw")


def export_probe_build():
    """Windows Desktop の書き出し設定を写して tests/ を含めた PerfProbe を一時的に足し、書き出して元に戻す。"""
    presets = os.path.join(ROOT, "export_presets.cfg")
    backup = os.path.join(OUT, "export_presets.backup.cfg")
    shutil.copy2(presets, backup)
    try:
        text = open(presets, encoding="utf-8", newline="").read()
        nl = "\r\n" if "\r\n" in text else "\n"
        block = text[text.index("[preset.0]"):text.index("[preset.1]")]
        index = max(int(n) for n in re.findall(r"^\[preset\.(\d+)\]", text, re.M)) + 1
        block = block.replace("[preset.0]", f"[preset.{index}]").replace("[preset.0.options]", f"[preset.{index}.options]")
        block = block.replace('name="Windows Desktop"', 'name="FreshPcProbe"', 1).replace("tests/*, ", "", 1)
        block = re.sub(r'export_path="[^"]*"', 'export_path=""', block, count=1)
        open(presets, "w", encoding="utf-8", newline="").write(text.rstrip() + nl + nl + block.rstrip() + nl)
        if os.path.isdir(BUILD):
            shutil.rmtree(BUILD)
        os.makedirs(BUILD)
        # シェーダーの焼き込みは画面ありの書き出しでしか動かないので --headless を付けない
        log = open(os.path.join(OUT, "export.log"), "w", encoding="utf-8", errors="replace")
        code = subprocess.call([GODOT, "--path", ROOT, "--export-release", "FreshPcProbe",
                                os.path.join(BUILD, "TESTOPIA.exe")], stdout=log, stderr=subprocess.STDOUT)
        log.close()
        if code != 0 or not os.path.exists(os.path.join(BUILD, "TESTOPIA.pck")):
            sys.exit("export failed, see " + os.path.join(OUT, "export.log"))
    finally:
        shutil.copy2(backup, presets)


def run_scenario(name, args):
    stamp = time.strftime("%H%M%S")
    run_dir = os.path.join(OUT, f"{name}_{stamp}")
    exe_dir = os.path.join(OUT, f"exe_{name}_{stamp}")
    os.makedirs(run_dir)
    os.makedirs(exe_dir)
    exe = os.path.join(exe_dir, f"TESTOPIA_{name}_{stamp}.exe")
    shutil.copy2(os.path.join(BUILD, "TESTOPIA.exe"), exe)
    os.link(os.path.join(BUILD, "TESTOPIA.pck"), exe[:-4] + ".pck")
    open(os.path.join(exe_dir, ".env"), "w", encoding="utf-8").write(BLOCKED_ENV)
    open(os.path.join(exe_dir, "override.cfg"), "w", encoding="utf-8").write(
        '[autoload]\n\nPerfProbeEntry="*res://tests/perf_probe_entry.gd"\n')
    # プレイヤーのファイルを写し、チュートリアルの案内を出さない設定で遊ぶ
    backup_dir = os.path.join(run_dir, "user_backup")
    os.makedirs(backup_dir)
    backed = set()
    for entry in os.listdir(USER) if os.path.isdir(USER) else []:
        path = os.path.join(USER, entry)
        if os.path.isfile(path):
            shutil.copy2(path, os.path.join(backup_dir, entry))
            backed.add(entry)
    os.makedirs(USER, exist_ok=True)
    settings_path = os.path.join(USER, "settings.json")
    settings = json.load(open(settings_path, encoding="utf-8")) if os.path.exists(settings_path) else {}
    settings.update({"graphics_quality": "high", "max_fps": 60, "tutorial_prompt_seen_version": 99,
                     "practice_intro_seen": True, "tutorial_dismissed": True, "tutorial_dismissed_version": 99})
    json.dump(settings, open(settings_path, "w", encoding="utf-8"), ensure_ascii=False)
    moved = []
    for cache in ("shader_cache", "vulkan"):
        path = os.path.join(USER, cache)
        if os.path.isdir(path):
            aside = path + f"_fresh_pc_aside_{stamp}"
            os.rename(path, aside)
            moved.append((path, aside))
    try:
        cmd = [exe, "--", f"--label={name}", "--quality=high", "--max_fps=60", "--window=1920x1080",
               "--max_play_seconds=200"] + args
        proc = subprocess.Popen(cmd, cwd=exe_dir)
        try:
            proc.wait(timeout=900)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
        art = os.path.join(exe_dir, "artifacts", "perf")
        for entry in os.listdir(art) if os.path.isdir(art) else []:
            shutil.copy2(os.path.join(art, entry), os.path.join(run_dir, entry))
    finally:
        for cache in ("shader_cache", "vulkan"):
            path = os.path.join(USER, cache)
            if os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
        for path, aside in moved:
            os.rename(aside, path)
        for entry in os.listdir(USER):
            path = os.path.join(USER, entry)
            if os.path.isfile(path) and entry not in backed:
                os.remove(path)
        for entry in backed:
            shutil.copy2(os.path.join(backup_dir, entry), os.path.join(USER, entry))
        shutil.rmtree(exe_dir, ignore_errors=True)
    return judge(name, run_dir)


def judge(name, run_dir):
    frames_path = os.path.join(run_dir, f"endless_{name}_frames.json")
    main_path = os.path.join(run_dir, f"endless_{name}.json")
    if not os.path.exists(frames_path):
        return {"scenario": name, "passed": False, "reason": "no frames recorded", "run_dir": run_dir}
    frames = json.load(open(frames_path, encoding="utf-8"))
    main = json.load(open(main_path, encoding="utf-8")) if os.path.exists(main_path) else {}
    kinds = frames.get("pipe_kinds", {})
    slow, compiles = [], []
    for i, dt in enumerate(frames["dt"]):
        if frames["phase"][i] != 4 or frames["state"][i] not in PLAY_STATES:
            continue
        state = PLAY_STATES[frames["state"][i]]
        stall = {k: v for k, v in kinds.get(str(i), {}).items() if k in STALL_KINDS}
        if stall:
            compiles.append({"t": round(frames["t"][i], 2), "state": state, "wall": frames["wall_index"][i], "pipelines": stall})
        if dt > HITCH_MS:
            slow.append({"t": round(frames["t"][i], 2), "state": state, "wall": frames["wall_index"][i],
                         "frame_ms": dt, "draw_ms": frames["draw"][i], "process_ms": frames["process"][i],
                         "post_ms": frames["post"][i], "pipelines": kinds.get(str(i), {})})
    endless = main.get("endless", {})
    return {
        "scenario": name,
        "passed": not slow and not compiles and not main.get("errors"),
        "slow_frames": slow,
        "play_compiles": compiles,
        "end_reason": endless.get("end_reason"),
        "walls_passed": endless.get("walls_passed"),
        "startup_s": round(float(main.get("startup_report", {}).get("elapsed_ms", 0.0)) / 1000.0, 1),
        "harness_errors": main.get("errors"),
        "run_dir": run_dir,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--scenario", action="append", choices=sorted(SCENARIOS))
    options = parser.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if not options.no_export or not os.path.exists(os.path.join(BUILD, "TESTOPIA.pck")):
        export_probe_build()
    results = [run_scenario(name, SCENARIOS[name]) for name in (options.scenario or list(SCENARIOS))]
    json.dump(results, open(os.path.join(OUT, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for result in results:
        print(("PASS " if result["passed"] else "FAIL ") + json.dumps(result, ensure_ascii=False)[:1500])
    sys.exit(0 if all(r["passed"] for r in results) else 1)


if __name__ == "__main__":
    main()
