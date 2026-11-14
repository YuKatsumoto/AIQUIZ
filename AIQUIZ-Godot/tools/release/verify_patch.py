"""公開する前に、作ったパッチを「配ったフル版」に当てて起動し、メニューまで届くか確かめる。

    python tools/release/verify_patch.py

やること:
  1. build/updates/ の windows.json とPCKが合っているか確かめる。
  2. パッチを、ゲームがダウンロードしたときと同じ形で user://updates/ に置く。
  3. 配ったフル版の TESTOPIA.exe を起動し、起動の記録（godot.log）を見る。
       - パッチが読み込まれたか
       - メニューまで届いたか、バージョンが新しい版になっているか
       - スクリプトのエラーが出ていないか
  4. ゲームを閉じ、user://updates/ を元に戻す。

うまくいくと build/.update_verified.json に記録する。deploy_update.py は、この記録の無いパッチを公開しない。
起動中はゲームのウィンドウが開く（1 分ほど）。触らずに待つ。
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_patch  # noqa: E402

ROOT = make_patch.ROOT
VERIFIED_FILE = os.path.join(ROOT, "build", ".update_verified.json")
ERROR_MARKS = ("SCRIPT ERROR", "Parse Error", "Compile Error")


def user_data_dir():
    name = re.search(r'^config/name="([^"]+)"', make_patch.read_text(os.path.join(ROOT, "project.godot")), re.M)
    return os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", name.group(1))


def read_manifest(folder):
    manifest_path = os.path.join(folder, make_patch.MANIFEST_NAME)
    if not os.path.isfile(manifest_path):
        sys.exit("windows.json がありません。先に make_patch.py でパッチを作ってください: " + folder)
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    patch = manifest.get("patch")
    if not patch:
        sys.exit("このマニフェストにはパッチがありません（フル版のマニフェスト）。確かめるものがないので、そのまま公開できます。")
    patch_path = os.path.join(folder, patch["url"])
    if not os.path.isfile(patch_path):
        sys.exit("windows.json が指すPCKがありません: " + patch_path)
    if os.path.getsize(patch_path) != patch["size"] or make_patch.sha256_of(patch_path) != patch["sha256"]:
        sys.exit("PCKの大きさか SHA-256 が windows.json と合いません。make_patch.py で作り直してください。")
    return manifest, patch_path


def remove_tree(path):
    # ゲームを閉じた直後は、ファイルがまだつかまれていることがある。
    for _ in range(20):
        shutil.rmtree(path, ignore_errors=True)
        if not os.path.exists(path):
            return
        time.sleep(0.5)
    print("消せませんでした。手で消してください: " + path)


def run_game(exe, log_path, timeout):
    """ゲームを起動し、メニューまで届く（STARTUP_LOADING が出る）か、時間切れになるまで待つ。記録の文を返す。"""
    started = time.time()
    process = subprocess.Popen([exe], cwd=os.path.dirname(exe))
    text = ""
    try:
        while time.time() - started < timeout:
            time.sleep(1.0)
            if os.path.isfile(log_path) and os.path.getmtime(log_path) >= started - 1.0:
                with open(log_path, encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
                if "STARTUP_LOADING " in text:
                    break
            if process.poll() is not None:
                break
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default=os.path.join(ROOT, "build", "updates"), help="パッチのあるフォルダ")
    parser.add_argument("--timeout", type=float, default=240.0, help="メニューが出るまで待つ秒数")
    args = parser.parse_args()

    manifest, patch_path = read_manifest(os.path.abspath(args.dir))
    patch = manifest["patch"]
    version = manifest["version"]
    base = make_patch.load_base()
    if base is None or base["version"] != manifest["base"]:
        sys.exit("windows.json の base（%s）が、記録してあるフル版と合いません。" % manifest["base"])
    exe = os.path.join(os.path.dirname(make_patch.base_pck_path(base)), "TESTOPIA.exe")
    if not os.path.isfile(exe):
        sys.exit("配ったフル版の exe がありません: " + exe)

    user_dir = user_data_dir()
    updates = os.path.join(user_dir, "updates")
    backup = updates + ".verify_backup"
    log_path = os.path.join(user_dir, "logs", "godot.log")
    if os.path.exists(backup):
        sys.exit("前の検証の後始末が残っています。中身を確かめて、updates に戻すか消してください: " + backup)
    if os.path.exists(VERIFIED_FILE):
        os.remove(VERIFIED_FILE)

    had_updates = os.path.isdir(updates)
    if had_updates:
        os.rename(updates, backup)
    try:
        os.makedirs(updates)
        file_name = "patch_%s_%s.pck" % (version, patch["sha256"][:8])
        shutil.copyfile(patch_path, os.path.join(updates, file_name))
        state = {"patch": {"version": version, "base": base["version"], "file": file_name,
                           "size": patch["size"], "sha256": patch["sha256"], "failed_boots": 0}}
        with open(os.path.join(updates, "state.json"), "w", encoding="utf-8") as handle:
            json.dump(state, handle)
        print("フル版 %s にパッチ %s を当てて起動しています…（ウィンドウには触らないでください）" % (base["version"], version),
              flush=True)
        text = run_game(exe, log_path, args.timeout)
    finally:
        remove_tree(updates)
        if had_updates:
            os.rename(backup, updates)

    problems = []
    if "[PatchBoot] patch %s loaded on base %s" % (version, base["version"]) not in text:
        problems.append("パッチが読み込まれていません。")
    report = re.search(r"^STARTUP_LOADING (\{.*\})\s*$", text, re.M)
    if report is None:
        problems.append("メニューまで届きませんでした（%d 秒待ちました）。" % args.timeout)
    else:
        startup = json.loads(report.group(1))
        if not startup.get("ready"):
            problems.append("起動の報告が ready になっていません。")
        if startup.get("version") != version:
            problems.append("起動したバージョンが %s です（%s のはず）。" % (startup.get("version"), version))
    errors = [line for line in text.splitlines() if any(mark in line for mark in ERROR_MARKS)]
    if errors:
        problems.append("スクリプトのエラーが出ています:\n    " + "\n    ".join(errors[:10]))

    if problems:
        print("確かめた結果: 失敗")
        for problem in problems:
            print("  - " + problem)
        print("記録: " + log_path)
        sys.exit(1)
    with open(VERIFIED_FILE, "w", encoding="utf-8") as handle:
        json.dump({"version": version, "base": base["version"], "sha256": patch["sha256"],
                   "verified_at": time.strftime("%Y-%m-%d %H:%M:%S")}, handle, indent=2)
    print("確かめた結果: 成功（パッチ %s を当てて、メニューまで起動しました）" % version)
    print("次は python tools/release/deploy_update.py で公開できます。")


if __name__ == "__main__":
    main()
