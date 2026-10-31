# Android 版（Galaxy Z Flip 7 向け）

## ビルド

前提: Godot 4.7.2 のエクスポートテンプレート、Android SDK、JDK 17（エディタ設定の Export > Android に登録済み）。

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-debug "Android" build/android/AIQUIZ.apk
adb install -r build/android/AIQUIZ.apk
```

- プリセット「Android」: arm64-v8a のみ、Vulkan（Mobile レンダラー）、没入モード、シェーダーベイク有効、
  権限は INTERNET / ACCESS_NETWORK_STATE / VIBRATE。
- デバッグ鍵で署名される。配布用（release）は自分の keystore を Export > Android に登録してから `--export-release`。
- `.env`（APP_SECRET）は APK に入れない。そのため Android 版の AI 出題はプロキシに 403 を返され、オフライン問題集で動く。
- artifacts/ docs/ tests/ tools/ などの開発用フォルダと未使用の glb は除外している（export_presets.cfg の exclude_filter）。
- APK は約 1.07 GB（大半は焼き込みライトと設定ホールの大きいテクスチャ）。直接インストールなら問題ないが、
  Google Play で配るなら AAB（gradle ビルド）と Play Asset Delivery が必要。

## PC での確認（モバイルプレビュー）

- コマンドライン: `Godot_v4.7.2-stable_win64.exe --path . --resolution 1680x720 -- --mobile-preview`
- エディタから: プロジェクト設定 `aiquiz/debug/mobile_preview` をオン（必要なら window_width/height_override を 1680x720）。
  終わったら必ず戻す。エクスポート版はこの設定を読まない。

プレビュー中はタッチ操作・セーフエリア（左端に 64px の疑似パンチホール）・モバイル向けの描画設定がすべて有効になる。
左クリックが1本の指として扱われる。描画は Forward+ のままなので、性能と見た目の最終確認は実機で行う。

## 仕組み

- `GraphicsQuality.is_mobile_target()`: モバイルの分岐はすべてこれで判定する（デスクトップの挙動は変えない）。
- `TouchControls`（autoload）: 試合中の仮想スティック・ジャンプ・エモート・一時停止・スタート/OK・サドンデスの回答ボタン。
  タッチをキー入力（WASD / Space / 1-3 / Enter / Esc、2P は矢印 / 右Ctrl / 8-0）として流し込むので、ゲーム本体の入力処理はそのまま動く。
- `MobileLifecycle`（autoload）: 戻るジェスチャー（= Esc）、トップ画面での終了確認、裏に回ったときのポーズ・消音・設定保存。
- `SafeArea`（autoload）: パンチホールと角丸を避ける余白。`MobileUi`: 文字の大きさとタップ領域の下限。`Haptics`: 振動。
- 縦横比 1.3 未満（カバー画面・分割画面）では「本体をひらいて あそんでね」を表示して試合を止める。

## 確認用テスト

- `tests/android/script_load_check.tscn`: autoload 込みで全スクリプトを読み込む（`--headless` で実行、failed=0 になること）。
- `tests/android/mobile_shader_compile_check.tscn`: モバイル用シェーダーを Mobile レンダラーでコンパイルする。
