# ゲーム内アップデート（Windows 版）

配ったゲームが、起動のたびに新しい版を確かめ、変わったファイルだけを入れた小さなPCK（パッチ）を
ダウンロードして当てるしくみ。プレイヤーは zip を落とし直さなくてよい。Android 版には入れていない。

更新を出すときの手順は `AGENTS.md` の「バージョン更新の公開」にも同じものがある。

## プレイヤーから見た流れ

1. ゲームを起動すると、起動画面で新しい版を確かめる。
2. あれば「アップデートがあります　バージョン 1.0.4（12.4 MB）」と出る。
3. 「更新する」でダウンロードが始まり、進みぐあいが出る。終わるとゲームが自動で立ち上がり直す。
4. 「あとで」を選ぶと、そのまま今の版で遊べる。次の起動でまた案内が出る。

ネットにつながっていないとき、確かめられなかったときは、何も出さずにそのまま起動する。

## ファイル

| ファイル | 役目 |
|---|---|
| `scripts/autoload/patch_boot.gd` | 一番最初の autoload。ダウンロード済みのパッチを、ほかのスクリプトより先に読み込む |
| `scripts/core/game_updater.gd` | マニフェストの確認、パッチのダウンロードと検証、再起動 |
| `scripts/ui/update_prompt.gd` | 案内の画面 |
| `scripts/ui/startup_loading.gd` の `_offer_update` | 起動画面から上の 2 つを呼ぶ |
| `tools/release/make_patch.py` | パッチとマニフェストを作る |
| `tools/release/verify_patch.py` | パッチを配ったフル版に当てて起動し、メニューまで届くか確かめる |
| `tools/release/deploy_update.py` | できたものを Firebase Hosting に公開する |
| `tools/release/base.json` | 配ったフル版の記録（版、PCKの場所と SHA-256） |
| `tools/release/base_project_settings.txt` | 配ったフル版の `project.godot` の写し（設定が変わっていないか比べる） |
| `tools/test_game_updater.gd` | 判定のテスト（通信なし） |

パッチと状態は `user://updates/`（`%APPDATA%\Godot\app_userdata\TESTOPIA\updates\`）に置く。

## 置き場所

Firebase Hosting の専用サイト `testopia-updates`（プロジェクト `aiquiz-a12f6`）。

- マニフェスト: https://testopia-updates.web.app/windows.json
- ゲームは `.env` の `UPDATE_MANIFEST_URL` でここを見る。この行を空にすると、アップデートを確かめない。
- 公開には `gcloud auth login` 済みの gcloud を使う（firebase コマンドは要らない）。
- サイトの中身は、公開のたびに `build/updates/` の中身と丸ごと入れ替わる。誰でも URL から読める。

## いまの状態

- 配ったフル版は **1.0.3**（`build/TESTOPIA_v1.0.3_Windows/`）。更新を受け取れる最初の版。
- 1.0.2 までの版は、更新を受け取るしくみが入っていない。

## 更新を出す手順

1. 直したい内容を作る。パッチには、作業フォルダのいまの中身がそのまま入る。
2. `project.godot` の `config/version` を上げる（例: 1.0.3 → 1.0.4）。
3. パッチを作る。`build/updates/` に `patch_1.0.4_windows.pck` と `windows.json` ができる。

   ```
   python tools/release/make_patch.py --notes "直した内容"
   ```

4. 確かめる。配ったフル版にパッチを当てて起動し、メニューまで届くかを自動で見る（ウィンドウが 1 分ほど開く）。

   ```
   python tools/release/verify_patch.py
   ```

5. 公開する。公開した時点から、起動した人に案内が出る。

   ```
   python tools/release/deploy_update.py
   ```

   `--dry-run` を付けると、確認だけして公開しない。

パッチはいつも「配ったフル版」との差分で作る。1.0.5 を出すときも、元は 1.0.3 のまま。
ゲームが持つパッチは 1 つだけで、新しいパッチが前のパッチを置き換える。

### スクリプトが止めてくれること

| 止まるとき | どのスクリプト |
|---|---|
| バージョンを上げ忘れた | `make_patch.py` |
| 配ったフル版のPCKが無い、または記録と中身が違う | `make_patch.py` |
| `project.godot` の設定がフル版から変わっている（パッチでは届かない） | `make_patch.py` |
| `patch_boot.gd` がフル版から変わっている（パッチでは差し替わらない） | `make_patch.py` |
| `PatchBoot` が autoload の先頭にない | `make_patch.py` |
| パッチを当てるとメニューまで届かない、スクリプトのエラーが出る | `verify_patch.py` |
| 検証を通っていないパッチを公開しようとした | `deploy_update.py` |
| 公開中の版より古い、または同じ版で中身だけ違う | `deploy_update.py` |

`verify_patch.py` が見るのは「起動してメニューまで届くか」まで。直した内容そのものが正しく動くかは、
パッチを作る前にエディターで確かめる。

### 出した更新に問題があったとき

公開した更新は取り消せない（もう更新した人は元に戻らない）。版を上げて、直したパッチを同じ手順で出す。
同じ版の番号のまま中身を変えても、もう更新した人には届かない。

## フル版を配り直すとき

次のものを変えたときは、パッチでは届かない。フル版を書き出して配り直す。

- Godot 本体（`TESTOPIA.exe`）の更新
- `project.godot` の設定（autoload の追加・入力マップ・描画の設定など）。パッチを読む時点で、設定はもう読み込み済み
- `patch_boot.gd` 自身

手順（1.1.0 を出す例）:

1. `config/version` を 1.1.0 に上げる。
2. 新しいフォルダへ書き出す。前の版のフォルダは上書きしない。

   ```
   Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/TESTOPIA_v1.1.0_Windows/TESTOPIA_v1.1.0/TESTOPIA.exe
   ```

3. 前の版のフォルダから `README.txt`（版の番号と日付を直す）・`CREDITS.txt`・`LICENSES/` を写す。
4. 書き出した `TESTOPIA.exe` を起動して確かめ、`build/TESTOPIA_v1.1.0_Windows.zip` にまとめて配る。
5. 配ったフル版を記録し、パッチなしのマニフェストを作って公開する。

   ```
   python tools/release/make_patch.py --full-release --base-pck build/TESTOPIA_v1.1.0_Windows/TESTOPIA_v1.1.0/TESTOPIA.pck --page-url <配布ページ>
   python tools/release/deploy_update.py
   ```

前のフル版の人には「新しいバージョンがあります。ゲームをダウンロードし直す必要があります」と出て、
`--page-url` のページを開ける。配ったフル版のフォルダは、次のフル版を出すまで消さない。

## 壊れたパッチへの備え（ゲーム側）

- ダウンロードしたファイルは、大きさと SHA-256 がマニフェストと合うときだけ使う。
- パッチを当てた起動が 2 回続けてメニューまで届かなかったら、3 回目の起動でそのパッチを捨てて、フル版のまま起動する。
  捨てたパッチは、そのPCではもう勧めない。直したパッチ（中身が変われば SHA-256 も変わる）は、また勧める。
- フル版を入れ直したら、前のフル版向けのパッチは捨てる。

## 守ること

- `PatchBoot` は `project.godot` の `[autoload]` の先頭に置く。後ろにあると、それより前の autoload の
  スクリプトがパッチで差し替わらない。
- `patch_boot.gd` では、ほかのスクリプトを `preload` しない。`class_name` や autoload の名前も直接書かない。
  書くと、そのスクリプトがパッチより先に読まれる。

## 案内の画面まで手で確かめたいとき

`verify_patch.py` は、ダウンロード済みの状態を作って起動する。案内の画面やダウンロードの動きを自分の目で見たいとき:

1. 配ったフル版の `TESTOPIA.exe` の横に `.env` を置き、`UPDATE_MANIFEST_URL=http://127.0.0.1:8765/windows.json` と書く
   （exe の横の `.env` は、PCKの中の `.env` の代わりに読まれる。ほかの設定も要るなら、元の `.env` を写して 1 行足す）。
2. `build/updates/` で `python -m http.server 8765` を動かす。
3. `TESTOPIA.exe` を起動する。案内が出て、「更新する」で再起動し、新しい版で立ち上がれば成功。
4. 終わったら、横に置いた `.env` と `%APPDATA%\Godot\app_userdata\TESTOPIA\updates\` を消す。

起動の記録は `%APPDATA%\Godot\app_userdata\TESTOPIA\logs\godot.log`。
パッチを読むと `[PatchBoot] patch 1.0.4 loaded on base 1.0.3` と出る。
