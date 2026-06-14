# 高速反復ワークフロー（常駐エディタ＋Remote Python）

## 結論
**エディタ操作の遅さの正体は「ビルド」ではなく「UnrealEditorのコールド起動（1回 25〜40秒）」だった。**
このプロジェクトは UE公式の **Python Remote Execution** が有効化済み（`Config/DefaultEngine.ini`:
`bRemoteExecution=True`, group `239.0.0.1:6766`）。常駐させた1つのエディタへ外部からPythonを直送すれば、
各操作が **約0.7秒**（実測）になる。**コールド起動の約30〜50倍速。**

| 方式 | 1操作あたり | 備考 |
|---|---|---|
| `UnrealEditor-Cmd -run=pythonscript`（従来） | 25〜40秒 | 毎回4.7万オブジェクト＋シェーダを再ロード。たまにハング |
| **`ue_exec.py`（常駐エディタへ直送）** | **〜0.7秒** | エディタは起動済みを再利用。DDC/パッケージ常温 |

## 使い方
1. **エディタを1つ開いておく**（GUIの `UnrealEditor.exe`/`-Cmd <project>`。これが常駐インスタンス）。
   - 既に開いていればそれでOK（remote execは起動中の同プロジェクトエディタへ自動接続）。
2. 任意のPythonを送る:
   ```bash
   # ファイルを実行（自分の commandlet スクリプトをそのまま投げられる）
   python3 Tools/ue_exec.py Saved/peace3/p8_pp_psx.py
   # ワンライナー
   python3 Tools/ue_exec.py -c "import unreal; print(unreal.SystemLibrary.get_engine_version())"
   ```
   - スクリプト内の `print("RESULT ...")` / `unreal.log()` はそのまま標準出力に返る。
   - 終了コード: 0=成功, 1=スクリプトが失敗報告, 3=エディタ未起動。

## 重要な利点
- **Slateが使える**：GUIエディタ常駐なので、ヘッドレスcommandletでクラッシュしていた処理
  （**フォントimport**＝`FontFileImportFactory`がSlate必須）も通る。実際、欠落していた
  FontFace `NotoSansJP-Regular` を本方式で0.7秒importして日本語□問題を解決した。
- **DDC/シェーダ常温**：`-game`の初回シェーダコンパイル待ちを毎回払わない。
- **マテリアル/アセット/automation/プロパティ設定**を即時反復できる。

## 併用すべき運用ルール（さらに速く・安全に）
1. **エディタ操作は常駐へ直送**（`ue_exec.py`）。`-run=pythonscript`のコールド起動は原則禁止。
2. **複数opは1スクリプトに束ねて1往復**にする。
3. **レンダが要る確認だけ`-game`**。ロジック/アセットは常駐エディタ（または`-NullRHI`）。
4. **GUIエディタを前景で長時間待たない**。常駐は意図的に起動しっぱなし、使い捨て起動はbackground＋短timeout＋監視kill。
5. **重い移植/調査は最初からWorkflowでバックグラウンド並列**（PSX移植・忠実性レビューはこれで無料化済み）。

## MCP（任意・次セッション以降）
`Tools/unreal-mcp-main`（chongdashu）はTCP 55557でアクタ/BP/UMG操作を提供。登録するなら
ルートに `.mcp.json`（`uv --directory Tools/unreal-mcp-main/Python run unreal_mcp_server.py`）。
ただしMCPツールは**セッション再起動で読み込み**＝即効性は本方式（Remote Python）が上。汎用Python実行は
本方式が完全上位なので、常用は `ue_exec.py` を推奨。

## ファイル
- `Tools/ue_exec.py` — 常駐エディタへPython直送するクライアント（依存なし・stdlibのみ）。
- 環境変数 `UE_REMOTE_EXEC_DIR` でエンジンのremote_execution.pyの場所を上書き可
  （既定 `G:\UE_5.7\Engine\Plugins\Experimental\PythonScriptPlugin\Content\Python`）。
