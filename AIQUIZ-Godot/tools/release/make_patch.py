"""アップデート用のパッチPCKとマニフェストを作る（Windows 版）。

更新を出すとき（project.godot の config/version を新しい版に上げてから）:

    python tools/release/make_patch.py --notes "直した内容"

できるもの（--out、既定は build/updates/。前のPCKとマニフェストは消してから書く）:

    patch_<新しい版>_windows.pck   配ったフル版から変わったファイルだけが入ったPCK
    windows.json                   ゲームが起動のたびに見に行くマニフェスト

このあと tools/release/verify_patch.py で確かめ、tools/release/deploy_update.py で公開する。

パッチはいつも「配ったフル版」との差分で作る（前のパッチとの差分にはしない）。
配ったフル版は tools/release/base.json に記録してある。次のときは、作る前に止まる:

    - フル版のPCKが無い、または記録した SHA-256 と合わない（別のPCKとの差分はゲームを壊す）
    - project.godot の設定がフル版から変わっている（パッチでは届かない。--allow-settings-change で進められる）
    - patch_boot.gd がフル版から変わっている（パッチでは差し替わらない）

フル版を配り直したとき（パッチでは届かない更新）は、そのフル版を記録し、パッチなしのマニフェストを作る:

    python tools/release/make_patch.py --full-release --base-pck <配ったフル版の TESTOPIA.pck> --page-url <配布ページ>

前のフル版の人には「ゲームをダウンロードし直す必要があります」と出て、配布ページを開ける。
しくみは docs/game_update.md。
"""
import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RELEASE_DIR = os.path.join(ROOT, "tools", "release")
BASE_FILE = os.path.join(RELEASE_DIR, "base.json")
BASE_SETTINGS_FILE = os.path.join(RELEASE_DIR, "base_project_settings.txt")
PATCH_BOOT = os.path.join(ROOT, "scripts", "autoload", "patch_boot.gd")
PRESET = "Windows Desktop"
MANIFEST_NAME = "windows.json"
# フル版と違っていてもよい設定。版の番号と、エディターのプラグインが勝手に書き換える値。
IGNORED_SETTINGS = ("application/config/version", "tripo_bridge/")


def find_godot():
    found = sorted(glob.glob(os.path.join(ROOT, "Godot_v*_console.exe")))
    if not found:
        sys.exit("Godot の実行ファイル（Godot_v*_console.exe）がプロジェクトのフォルダにありません。--godot で指定してください。")
    return found[-1]


def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def version_key(version):
    return [int(part) for part in version.split(".")]


def project_version(project_text):
    match = re.search(r'^config/version="([^"]+)"', project_text, re.M)
    if match is None:
        sys.exit("project.godot に config/version がありません。")
    return match.group(1)


def first_autoload(project_text):
    section = re.search(r"^\[autoload\]\s*$(.*?)(?=^\[)", project_text, re.M | re.S)
    if section is None:
        return ""
    for line in section.group(1).splitlines():
        if "=" in line:
            return line.split("=", 1)[0].strip()
    return ""


def parse_settings(project_text):
    """project.godot を {"section/key": "値の文字列"} にする。複数行の値は 1 つにまとめる。"""
    settings = {}
    section = ""
    key = None
    for line in project_text.splitlines():
        if line.startswith(";"):
            continue
        header = re.match(r"^\[([^\]]+)\]\s*$", line)
        if header:
            section = header.group(1)
            key = None
            continue
        assignment = re.match(r"^([A-Za-z0-9_./\-]+)=(.*)$", line)
        if assignment:
            key = section + "/" + assignment.group(1)
            settings[key] = assignment.group(2)
        elif key is not None and line.strip():
            settings[key] += "\n" + line
    return settings


def changed_settings(base_text, current_text):
    base = parse_settings(base_text)
    current = parse_settings(current_text)
    changed = []
    for key in sorted(set(base) | set(current)):
        if key.startswith(IGNORED_SETTINGS):
            continue
        if base.get(key) != current.get(key):
            changed.append(key)
    return changed


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_base():
    """記録してある「配ったフル版」。無ければ None。"""
    if not os.path.isfile(BASE_FILE):
        return None
    with open(BASE_FILE, encoding="utf-8") as handle:
        return json.load(handle)


def base_pck_path(base):
    return os.path.normpath(os.path.join(ROOT, base["pck"]))


def record_base(version, pck_path):
    relative = os.path.relpath(pck_path, ROOT).replace("\\", "/")
    base = {
        "version": version,
        "pck": relative,
        "pck_size": os.path.getsize(pck_path),
        "pck_sha256": sha256_of(pck_path),
        "patch_boot_sha256": sha256_of(PATCH_BOOT),
    }
    with open(BASE_FILE, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(base, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    shutil.copyfile(os.path.join(ROOT, "project.godot"), BASE_SETTINGS_FILE)
    print("フル版 %s を記録しました: %s" % (version, BASE_FILE))


def clear_output(out_dir):
    """前の版のPCKとマニフェストを消す。このフォルダの中身が、そのまま公開される。"""
    os.makedirs(out_dir, exist_ok=True)
    for name in os.listdir(out_dir):
        if name == MANIFEST_NAME or (name.startswith("patch_") and name.endswith(".pck")):
            os.remove(os.path.join(out_dir, name))


def write_manifest(out_dir, manifest):
    manifest_path = os.path.join(out_dir, MANIFEST_NAME)
    with open(manifest_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("マニフェスト: " + manifest_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--full-release", action="store_true",
                        help="いまの config/version をフル版として配った。--base-pck のPCKを記録し、パッチなしのマニフェストを作る")
    parser.add_argument("--base-pck", help="配ったフル版の TESTOPIA.pck（--full-release のときに指定する）")
    parser.add_argument("--out", default=os.path.join(ROOT, "build", "updates"), help="書き出し先のフォルダ")
    parser.add_argument("--notes", default="", help="更新の画面に出す短い説明")
    parser.add_argument("--page-url", default="", help="フル版の配布ページ（パッチで済まない人に案内する）")
    parser.add_argument("--required", action="store_true", help="「あとで」を出さない")
    parser.add_argument("--allow-settings-change", action="store_true",
                        help="project.godot の設定がフル版から変わっていても作る（変えた設定はパッチでは届かない）")
    parser.add_argument("--godot", default="", help="Godot の実行ファイル（console 版）")
    args = parser.parse_args()

    project_text = read_text(os.path.join(ROOT, "project.godot"))
    version = project_version(project_text)
    if first_autoload(project_text) != "PatchBoot":
        sys.exit("project.godot の [autoload] の先頭が PatchBoot ではありません。"
                 "エディターの「自動読み込み」で PatchBoot を一番上に戻してください。")
    out_dir = os.path.abspath(args.out)

    if args.full_release:
        if not args.base_pck or not os.path.isfile(args.base_pck):
            sys.exit("--full-release には、配ったフル版のPCKを --base-pck で指定してください。")
        record_base(version, os.path.abspath(args.base_pck))
        clear_output(out_dir)
        write_manifest(out_dir, {"version": version, "base": version, "required": args.required,
                                 "notes": args.notes, "page_url": args.page_url})
        print("フル版 %s のマニフェストを書きました（パッチなし）。" % version)
        return

    if args.base_pck:
        sys.exit("--base-pck は --full-release のときだけ使います。パッチは tools/release/base.json のフル版との差分で作ります。")
    base = load_base()
    if base is None:
        sys.exit("配ったフル版の記録（tools/release/base.json）がありません。"
                 "フル版を書き出して、--full-release --base-pck <PCK> で記録してください。")
    if version_key(version) <= version_key(base["version"]):
        sys.exit("project.godot の config/version（%s）を、フル版（%s）より新しくしてください。" % (version, base["version"]))
    base_pck = base_pck_path(base)
    if not os.path.isfile(base_pck):
        sys.exit("フル版のPCKが見つかりません: %s\n配った zip から同じ場所に戻してください。" % base_pck)
    print("フル版のPCKを確かめています…", flush=True)
    if os.path.getsize(base_pck) != base["pck_size"] or sha256_of(base_pck) != base["pck_sha256"]:
        sys.exit("フル版のPCKが、記録した内容と違います: %s\n配ったPCKと違うものとの差分は、ゲームを壊します。" % base_pck)
    if sha256_of(PATCH_BOOT) != base["patch_boot_sha256"]:
        sys.exit("scripts/autoload/patch_boot.gd がフル版から変わっています。"
                 "このスクリプトはパッチでは差し替わりません。フル版を配り直してください。")
    changed = changed_settings(read_text(BASE_SETTINGS_FILE), project_text)
    if changed and not args.allow_settings_change:
        sys.exit("project.godot の設定がフル版から変わっています。これらはパッチでは届きません:\n  "
                 + "\n  ".join(changed)
                 + "\nフル版を配り直すか、届かなくてよい変更なら --allow-settings-change を付けてください。")

    clear_output(out_dir)
    patch_name = "patch_%s_windows.pck" % version
    patch_path = os.path.join(out_dir, patch_name)
    godot = args.godot or find_godot()
    command = [godot, "--headless", "--path", ROOT, "--export-patch", PRESET, patch_path, "--patches", base_pck]
    print("書き出しています: " + " ".join(command), flush=True)
    code = subprocess.call(command)
    if not os.path.isfile(patch_path) or os.path.getsize(patch_path) == 0:
        sys.exit("パッチを書き出せませんでした（Godot の終了コード %d）。" % code)

    size = os.path.getsize(patch_path)
    write_manifest(out_dir, {
        "version": version,
        "base": base["version"],
        "patch": {"url": patch_name, "size": size, "sha256": sha256_of(patch_path)},
        "required": args.required,
        "notes": args.notes,
        "page_url": args.page_url,
    })
    size_text = "%.1f MB" % (size / 1048576.0) if size >= 1048576 else "%d KB" % max(1, round(size / 1024.0))
    print("パッチ: %s（%s）" % (patch_path, size_text))
    print("次は python tools/release/verify_patch.py で確かめてください。")


if __name__ == "__main__":
    main()
