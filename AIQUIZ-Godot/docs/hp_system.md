# 3HP制と検証結果

## 動作

- 通常・エンドレスの1P／2Pは3HPで開始。不正解ドアと壁への衝突で1減少する。
- HPが残れば次問へ進み、0で従来の死亡・ゴーストシャークへ移行する。
- 海のサメ攻撃とスクロールアウトはHPに関係なく脱落する。
- エンドレスは正誤を問わず10問進むごとに生存者を1回復する。上限3、死亡者の復活なし。
- チュートリアル・協力のルールは変更しない。開始・リトライでHPと回復カウントをリセットする。
- のけぞり・操作硬直は0.35秒、点滅は0.6秒。ルート位置を巻き戻さず、自動前進を維持する。
- 左上にP1オレンジ／P2青の自作ベクターハートを表示する。

## 状態と互換性

`QuizGameState`がHP・被ダメージ時間・壁ごとの判定済み状態を保持する。同じ壁の再接触を無視し、2Pの先行ミスでは相手の回答を待つ。誰かが正解した場合、または回答可能な全員が回答済みの場合に、その問題を一度だけ完了する。

`health_changed(player_index, previous_hp, hp)`と`question_completed(wall_index, correct)`を追加した。壁の退場は問題完了で行い、全員不正解では正解音・正解扉の破壊・加点を発生させない。

オンラインは既存スナップショットへHPと被ダメージ時間を追加。信頼性のあるHP変更イベントも送信し、同じフレームで起きる「ダメージ→回復」を受信側のハートにも順番に反映する。

新規リプレイはversion 3／28フィールド。従来の24フィールドの記録は元のフレーム幅で読み、HPを非表示にする。既存の製品側リプレイ入口・自動記録の無効化設定は維持し、記録／再生クラスを更新した。

## 検証（2026-09-15）

| 検証 | 結果 |
|---|---|
| HPロジック・同期・新旧リプレイ | 186項目成功 |
| 既存の押し合い | 290項目成功 |
| 左右移動・ジャンプ・チュートリアル操作 | 21項目成功 |
| Forward+実ゲーム | solo / duo / both / stagger / recovery / goal / replay、7ケース成功 |
| 別プロセス通信 | 製品のNetworkManager / NetGameStateとローカルWebSocketで6段階のHP・姿勢・イベント順序が一致 |
| サメ接触 | 実ゲームで接触1回、死亡演出成立、顎角度0を維持 |
| エディターからの再起動 | 起動エラーなし、両者3HP、保存済みソースのハッシュ不変 |

実ゲームの記録では、のけぞりが最大約14度に達して0.35秒で0度に戻り、その間もZ座標が前進した。0.6秒後には全メッシュの点滅が解除された。

通信検証はローカルの2プロセスで実施し、外部リレーサーバー経由の対戦は実施していない。headless実行では既存のローディング表示のダミーテクスチャ警告、テスト終了時には既存同様のObjectDB／Resource解放警告が残る。Forward+検証ログにはGDScriptエラーなし。

## 証拠と再実行

- `artifacts/hp_system/hp_demo.mp4`：60FPSの実ゲーム録画。3回のミスからゴーストシャークへの移行。
- `artifacts/hp_system/unit.json`：HPの186項目。
- `artifacts/hp_system/runtime_*.json`：実ゲームの時刻・HP・姿勢角度・位置・HUD表示。
- `artifacts/hp_system/network_report.json`、`network_host.json`、`network_guest.json`：通信両側の比較。
- `artifacts/hp_system/implementation.diff`：作業開始時からの機能差分。

プロジェクトフォルダーで実行する。

```powershell
./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/hp_bootstrap.gd
./Godot_v4.7.2-stable_win64_console.exe --path . --script tests/hp_bootstrap.gd --fixed-fps 60 -- runtime case=duo
python artifacts/hp_system/run_network.py
```

通信用スクリプトはPythonのwebsocketsを使用し、127.0.0.1:18766でのみ待ち受ける。実ゲームケースは`solo / duo / both / stagger / recovery / goal / replay`を指定できる。
