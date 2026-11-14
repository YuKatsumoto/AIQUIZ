"""アップデートのファイル（windows.json とパッチPCK）を Firebase Hosting に公開する。

    python tools/release/deploy_update.py            build/updates/ の中身を公開する
    python tools/release/deploy_update.py --dry-run  何を公開するかだけ表示する

- firebase コマンドは要らない。gcloud でログインしていれば動く（gcloud auth login）。
- 公開は一度に切り替わる。途中で止まっても、前の版がそのまま残る。
- フォルダの中身が、そのままサイトの中身になる。フォルダに無いファイルは、サイトからも消える。
- windows.json はキャッシュさせない（出した更新がすぐ届く）。
- 公開する前に確かめて、合わなければ止まる:
    - windows.json の中身と、PCKの大きさ・SHA-256 が合っているか
    - そのパッチが verify_patch.py の検証を通っているか（--skip-verify で飛ばせる）
    - いま公開中の版より古くないか。同じ版で中身だけ違うパッチでないか
      （同じ版のまま中身を変えても、もう更新した人には届かない。版を上げて出し直す）

サイトは https://<SITE>.web.app 。ゲームは .env の UPDATE_MANIFEST_URL でここを見る。
しくみは docs/game_update.md。
"""
import argparse
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROJECT = "aiquiz-a12f6"
SITE = "testopia-updates"
API = "https://firebasehosting.googleapis.com/v1beta1"
MANIFEST_NAME = "windows.json"
VERIFIED_FILE = os.path.join(ROOT, "build", ".update_verified.json")
HOSTING_CONFIG = {
    "headers": [
        {"glob": "**/*.json", "headers": {"Cache-Control": "no-cache"}},
        {"glob": "**/*.pck", "headers": {"Cache-Control": "public, max-age=3600"}},
    ]
}


def access_token():
    gcloud = shutil.which("gcloud") or shutil.which("gcloud.cmd")
    if gcloud is None:
        sys.exit("gcloud が見つかりません。Google Cloud SDK を入れて、gcloud auth login を済ませてください。")
    result = subprocess.run([gcloud, "auth", "print-access-token"], capture_output=True, text=True)
    token = result.stdout.strip()
    if result.returncode != 0 or not token:
        sys.exit("gcloud のログインが切れています。gcloud auth login をやり直してください。")
    return token


def call(method, url, token, body=None, data=None, length=None):
    headers = {"Authorization": "Bearer " + token, "x-goog-user-project": PROJECT}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif data is not None:
        headers["Content-Type"] = "application/octet-stream"
        if length is not None:
            headers["Content-Length"] = str(length)
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            text = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        sys.exit("Firebase Hosting がエラーを返しました（%d）: %s\n%s" % (error.code, url, error.read().decode("utf-8", "replace")))
    return json.loads(text) if text.strip() else {}


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_manifest(folder):
    """windows.json と、それが指すPCKが合っているか確かめる。合わなければ止める。"""
    manifest_path = os.path.join(folder, MANIFEST_NAME)
    if not os.path.isfile(manifest_path):
        sys.exit("%s がありません: %s" % (MANIFEST_NAME, folder))
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    if not manifest.get("version") or not manifest.get("base"):
        sys.exit("windows.json に version か base がありません。")
    patch = manifest.get("patch")
    if patch is None:
        return manifest
    url = str(patch.get("url", ""))
    if "/" in url or not url:
        sys.exit("windows.json の patch.url は、同じフォルダのファイル名にしてください: " + url)
    patch_path = os.path.join(folder, url)
    if not os.path.isfile(patch_path):
        sys.exit("windows.json が指すPCKがフォルダにありません: " + url)
    if os.path.getsize(patch_path) != patch.get("size") or sha256_of(patch_path) != patch.get("sha256"):
        sys.exit("PCKの大きさか SHA-256 が windows.json と合いません。make_patch.py で作り直してください。")
    return manifest


def version_key(version):
    return [int(part) for part in str(version).split(".")]


def check_verified(manifest):
    """verify_patch.py が、このパッチで成功を記録しているか。"""
    patch = manifest.get("patch")
    if patch is None:
        return
    verified = {}
    if os.path.isfile(VERIFIED_FILE):
        with open(VERIFIED_FILE, encoding="utf-8") as handle:
            verified = json.load(handle)
    if verified.get("sha256") != patch.get("sha256"):
        sys.exit("このパッチは、まだ検証を通っていません。先に python tools/release/verify_patch.py を実行してください。")


def check_against_live(manifest):
    """いま公開中のマニフェストと比べる。古い版や、同じ版で中身の違うパッチは公開しない。"""
    url = "https://%s.web.app/%s" % (SITE, MANIFEST_NAME)
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            live = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return  # まだ何も公開していない。
        sys.exit("公開中のマニフェストを読めませんでした（%d）: %s" % (error.code, url))
    except (urllib.error.URLError, ValueError) as error:
        sys.exit("公開中のマニフェストを読めませんでした: %s（%s）" % (url, error))
    live_version = live.get("version", "0")
    print("公開中の版: %s" % live_version)
    if version_key(manifest["version"]) < version_key(live_version):
        sys.exit("公開しようとしている版（%s）が、公開中の版（%s）より古いです。" % (manifest["version"], live_version))
    live_sha = (live.get("patch") or {}).get("sha256")
    new_sha = (manifest.get("patch") or {}).get("sha256")
    if manifest["version"] == live_version and live_sha and new_sha and live_sha != new_sha:
        sys.exit("公開中の版（%s）と同じ番号で、中身の違うパッチです。もう更新した人には届きません。"
                 "config/version を上げて、パッチを作り直してください。" % live_version)


def gzip_to_temp(path, temp_dir):
    """Hosting は gzip したファイルを受け取り、その SHA-256 で管理する。"""
    target = os.path.join(temp_dir, hashlib.sha256(path.encode("utf-8")).hexdigest() + ".gz")
    with open(path, "rb") as source, open(target, "wb") as raw:
        # mtime を 0 にして、同じ中身なら同じ gzip になるようにする（上げ直しを避ける）。
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=6, mtime=0) as packed:
            shutil.copyfileobj(source, packed, 1 << 20)
    return target, sha256_of(target)


def main():
    global PROJECT, SITE
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default=os.path.join(ROOT, "build", "updates"), help="公開するフォルダ")
    parser.add_argument("--site", default=SITE, help="Hosting のサイト ID")
    parser.add_argument("--project", default=PROJECT, help="Firebase のプロジェクト ID")
    parser.add_argument("--dry-run", action="store_true", help="何を公開するかだけ表示する（確認はすべて行う）")
    parser.add_argument("--skip-verify", action="store_true", help="verify_patch.py の検証を通っていなくても公開する")
    args = parser.parse_args()
    PROJECT, SITE = args.project, args.site

    folder = os.path.abspath(args.dir)
    manifest = check_manifest(folder)
    names = sorted(name for name in os.listdir(folder)
                   if os.path.isfile(os.path.join(folder, name)) and not name.startswith("."))
    patch = manifest.get("patch")
    print("サイト: https://%s.web.app" % SITE)
    print("版: %s（フル版 %s 向け、%s）" % (manifest["version"], manifest["base"],
          "パッチ %s" % patch["url"] if patch else "パッチなし"))
    for name in names:
        print("  /%s  %d bytes" % (name, os.path.getsize(os.path.join(folder, name))))
    if not args.skip_verify:
        check_verified(manifest)
    check_against_live(manifest)
    if args.dry_run:
        print("確認はすべて通りました。--dry-run なので公開していません。")
        return

    token = access_token()
    with tempfile.TemporaryDirectory() as temp_dir:
        packed = {}
        for name in names:
            packed["/" + name] = gzip_to_temp(os.path.join(folder, name), temp_dir)
        version = call("POST", "%s/sites/%s/versions" % (API, SITE), token, body={"config": HOSTING_CONFIG})["name"]
        populated = call("POST", "%s/%s:populateFiles" % (API, version), token,
                         body={"files": {path: digest for path, (_, digest) in packed.items()}})
        required = set(populated.get("uploadRequiredHashes", []))
        for path, (gz_path, digest) in packed.items():
            if digest not in required:
                continue
            print("アップロード: " + path, flush=True)
            with open(gz_path, "rb") as handle:
                call("POST", "%s/%s" % (populated["uploadUrl"], digest), token,
                     data=handle, length=os.path.getsize(gz_path))
        call("PATCH", "%s/%s?update_mask=status" % (API, version), token, body={"status": "FINALIZED"})
        call("POST", "%s/sites/%s/releases?versionName=%s" % (API, SITE, version), token,
             body={"message": "update %s" % manifest["version"]})
    print("公開しました: https://%s.web.app/%s" % (SITE, MANIFEST_NAME))


if __name__ == "__main__":
    main()
