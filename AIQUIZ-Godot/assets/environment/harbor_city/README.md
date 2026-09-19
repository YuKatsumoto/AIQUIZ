# AIQUIZ Harbor City

メインメニューとゲーム本編に使用する、Blenderで自作したコの字型の人工島都市です。
実際に開いているBlender 5.1.2にMCPで接続し、その制作シーン上で生成・確認・保存・書き出しを行いました。
追加費用は0円です。外部モデル・外部テクスチャ・有料アドオン・生成APIは使用していません。

## データ

- `aiquiz_harbor_city.glb`: Godot用。テクスチャを埋め込み済み。
- `source/aiquiz_harbor_city.blend`: 編集用。建物・地盤・岸壁・植栽を地区別に整理。
- `source/build_harbor_city.py`: Blenderで実行する再生成スクリプト。
- `source/textures/`: 自作の外壁3種（色＋窓の発光マスク）と岸壁、計7枚のPNG。
- `source/previews/harbor_city_overview.png`: Blenderの確認用レンダー。
- `source/build_report.json`: 実際の制作環境・メッシュ数・三角形数。
- `source/ASSET_SOURCES.csv`: 素材名、提供元、URL、利用条件、クレジット、取得方法、費用の一覧。

`source/.gdignore` により編集用データはGodotに重複インポートされません。
テクスチャは.blendにもパック済みで、PNG単体も残しています。

## 確認した読み込み方法

このプロジェクトはGodot 4.7.2 / Forward+です。既存の観客席モデルが
GLBからPackedSceneにインポートされ、`StageEnvironment`がインスタンス化しています。
同じ読み込み方法を使用しました。GodotはglTF 2.0のGLBを推奨し、テクスチャも
埋め込めます（[Godot公式ドキュメント](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)）。

1 Blender単位 = 1 m。BlenderのZ=0が海面、地表はZ=4.15 m、基礎はZ=-6 mまで。
書き出し時にglTF標準のY-upへ変換し、Godot側で海面Y=-9.2 mに配置します。
全体は約2.96 km × 3.55 km、23街区・368棟・植栽1564本です。
13メッシュ・349718三角形（Godotの距離LOD適用前）に統合しています。窓・外壁の分割は自作テクスチャ、
床スラブ・段状屋上・塔・切妻屋根・港施設の曲面屋根はメッシュで表現しています。

## 開いているBlender上での再生成

Blenderの「スクリプト作成」ワークスペースで `source/build_harbor_city.py` を開き、
「スクリプト実行」を押します。現在のファイルに新しい `AIQUIZ U Harbor City` シーンを作成します。
Pythonコンソールからの実行も可能です。

```python
import runpy
runpy.run_path('C:/AIQUIZ/AIQUIZ-Godot/assets/environment/harbor_city/source/build_harbor_city.py')
```

同じ出力先の.blend、GLB、PNGを更新するため、手動で編集した.blendは再生成前に別名保存してください。
元から開かれていたシーンは残します。今回の作業開始前のファイルも
`artifacts/harbor_city/blender_before_live_city.blend` に保存しています。

## 別プロセスで再生成する場合（任意）

プロジェクトのルート `C:\AIQUIZ\AIQUIZ-Godot` で実行します。

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --factory-startup --python assets/environment/harbor_city/source/build_harbor_city.py
```

生成後、GodotのFileSystemを再スキャンしてGLBを再インポートします。
実行中のゲームは再起動すると新しいモデルを読み込みます。

## Blenderで手動編集する場合

1. `source/aiquiz_harbor_city.blend` を開き、シーン `AIQUIZ U Harbor City` を選択。
2. `Left district` / `Rear district` / `Right district` の各地区と、`00 Continuous U island` 内の地盤を編集し、.blendを保存。
3. 古い `EXPORT - merged district copies` は自動生成時のコピーです。
   手動編集後はこのコピーを選択せず、各地区内の編集済みメッシュを選択。
4. File > Export > glTF 2.0 で形式「glTF Binary (.glb)」、Selected Objects、
   Active Scene、Y Upを有効にし、Cameras / Lights / Animationsを無効にして
   `aiquiz_harbor_city.glb` へ書き出す。
5. `REVIEW ONLY` の海・照明・カメラ、`TEMPLATE` の制作部品はゲームに書き出さない。

手動書き出しでは編集用の415メッシュ構成になります。13メッシュに統合して調整を
反映したい場合は、スクリプトの建物パラメータを修正して再生成してください。

## ゲームへの配置

`scripts/world/harbor_city_backdrop.gd` が同じGLBを、メニューとプレイ中で同じ座標に配置します。
進行方向の前方（Godot +Z）を空け、左・後方・右に街を配置しています。
左右の内側岸壁はX=±1220 m、後方の内側岸壁はZ=-1240 mです。
コースの長さに追従して島を伸縮しません。
地盤・建物に衝突判定は付けず、遠景の影とGIを無効にして描画を抑えています。
窓の発光は既存の `WeatherCycle.night_amount_changed` に連動します。
ゲームカメラの描画距離を5000 mに延ばし、カメラの位置と画角は維持しています。
StageEnvironmentの `layout_include_harbor_city` で本編の表示を切り替えられます。
通常の正面プレイ視点では、左右の遠景は観客席に隠れ、後方の街は画角外になります。
メインメニューの背景では後方の街並みが見えます。
Godotの編集画面プレビューは、既存のGraphicsQualityのエディタ実行エラーにより確認できていません。
制作・実行確認の範囲と画像は [VERIFICATION.md](VERIFICATION.md) に記録しています。

## 無料素材の利用方針

今回はすべて自作し、配布条件が不明な外部素材を採用していません。
自作物をCC0として外部公開する操作は行っていません。
Blender本体は無料で商用制作にも使用でき、作成した.blend・画像・書き出しデータに
Blender本体のGPLを適用する義務はありません
（[Blender公式ライセンス](https://www.blender.org/about/license/)、2026-09-13確認）。

今後外部素材を追加する場合も、無料・公式配布・CC0優先を守り、個別の改変、ゲーム組み込み、
公開配布条件とクレジットを確認して `source/ASSET_SOURCES.csv` に追記してください。
無料体験の後課金、書き出し課金、有料連携、一括取得サービス、従量課金生成APIは採用しません。
