# 海底・街区地盤・桟橋の設計と検証

## 作業チェックリスト
- [x] 公式スキル読了: blender-scene, scene-spec, modeling, lookdev, lighting-camera, animation, audit-finalize
- [x] A: 両接続の同一PID 75684、Scene、未保存ファイルと既存3オブジェクトを確認
- [x] B: 編集前の復元コピーと作業用シーンを作成
- [x] C: 輪郭、寸法、奥行き、接地、Blender画面の順で配置確認
- [x] D: 支柱、階段、開口、手すり、街側入口を仕上げる
- [x] E: Blenderの構造・表示・確認カメラとGodot実ゲームで検証

## Scene Passport

SCENE
- intent: コンベア・観客席・13街区が同じ海底へ接地し、観客席から街の遊歩道まで連続した入口を持つ。
- deliverable: ライブBlenderシーンの編集可能な地盤・桟橋設計とGodotへの設置。元の街・観客・ゲーム操作は維持。
- units: metres; axes: right-handed Z-up。Godot = (Blender X, Blender Z, -Blender Y)。
- render: EEVEE, 1280x720, 24fps, frames 1–144。確認専用のカメラ移動のみ。
- dynamic: inspection camera only; architectural models stay fixed in game.

HIERARCHY
- collection/object naming: ENV_Seabed, ENV_DistrictFoundations, PRP_AccessStair, PRP_PierBay, PRP_QuayGateway, REF_Town, REF_StandLeft/Right, CAM_AccessSurvey, LGT_Day.
- parent/child relationships: 街区別地盤、観客席の区画、階段・桟橋・入口を別オブジェクトで保持。Godotでは観客席の実際の通路位置へ桟橋を同期。
- protected existing objects: 元のSceneのCube/Camera/Light、既存街区の建物・植栽、既存Blenderソース・GLB、ゲームのP1/P2・観客の振る舞い。

ASSETS
- A01 Town | [EXISTING] | detailed | 約481x1028x48m | root height -9.2m | 13街区の上部形状を保持。
- A02 Seabed | [BLOCK] | stylized | 4000x4000x4m | [0,-150,-19.2] | upper surface -17.2m, flush with conveyor underside.
- A03 DistrictFoundations | [BLOCK] | stylized | 各街区の既存底面輪郭 | height -17.2 to -14.2m | 上部形状に接続する13個の閉じた押出形状。
- A04 GroundedGrandstand | [EXISTING] | detailed | 9.24x160x21.4m | original local origin | 支柱のみ下へ7.2m延長、基礎を同じ高さへ移動。4段の座席と通路を保持。
- A05 AccessStair | [BLOCK] | detailed | 約20x3.6x22m | stand root, upper entrance X8.18 / Z1.52 | 2段階の階段、36蹴上、各約0.186m、踏面0.34m、中間踊り場2.4m。
- A06 PierBay | [BLOCK] | detailed | 4x3.6x13.2m | top -5.16m | 繰り返し可能な石造桟橋、青手すり、海底に達する支柱。
- A07 QuayGateway | [BLOCK] | detailed | 約3.2x4.4x4m | quay promenade height -5.16m | 通れるアーチ入口と接続踊り場。
- generation estimate/submission: no GEN assets, no metered generation, zero added asset cost.

SHOT
- active camera: CAM_AccessSurvey; bridge, stair and town promenade in one three-quarter frame.
- framing/lens/target: 36mm survey, 42mm stair detail, orthographic side inspection (110m width).
- depth: stair foreground, pier middle, existing town background; temporary water guide hidden for seabed inspection.

LOOK
- palette: existing white plaster, cobalt railings, pale stone paving, dark volcanic footings, desaturated sandy seabed.
- material route: EXISTING flat PBR roles; no images or generated textures.
- texture scale: stone divisions in model metres; no procedural material dependency in GLB.
- relief: modeled steps, coping and arches; no displacement.
- roughness: stone 0.8–0.95, blue paint 0.55, no glossy seabed.
- world: neutral daylight, separate preview water guide; original game sky retained.

LIGHTING
- focal: upper stair entrance and quay gateway; under-deck may be darkest.
- mood: clear daytime inspection, fixed AgX exposure 0.
- environment route: NONE generated, neutral World fill.
- key: one lateral Sun; preserves terrain and stair shadows.
- fill: World only, enough to read support columns without flattening the stair profile.
- practicals: no new independent light rig in game.
- reflections/gobos/atmosphere: no additional effects; preserve game's water/lighting.
- audit: viewed Blender camera render plus actual Godot day/night and underwater evidence.

MOTION
- 24fps / 1–144; camera slowly surveys the connected entry and settles, excluded from export.
- architectural transforms static; no physical motion introduced.

ACCEPTANCE
- structural: seabed top exactly -17.2m; 13 ground extensions; stand bases touch seabed; original seats unchanged; stair risers <=0.20m; no closed railing crosses a used doorway; piers terminate on actual town promenade.
- motion: Blender inspection camera varies smoothly, contains the access path at start/mid/end; game length changes keep stair entries on stand gates.
- visual: view entire access path in Blender, underwater contact, and normal game camera; no obstruction inside the playable/shark corridor.
- lighting: stair treads, white/blue materials and supports readable, no missing material.

refs_read: blender-scene, blender-scene-spec, blender-modeling, blender-lookdev, blender-lighting-camera, blender-animation, blender-audit-finalize.

## 完了結果（2026-09-14）

- Blender の同一ライブウィンドウで製作。元の Scene の Cube/Light/Camera を保持し、設計用・モジュール用の2シーンを追加した。
- 編集用コピー: `assets/environment/santorini_waterfront/source/20260914_waterfront_final.blend`（約22MB）。現行ウィンドウのファイルパスは変更せず、コピーとして保存。フレーム1、CAM_AccessSurvey の編集画面を表示して終了。
- 13街区の既存底面輪郭を3m押し下げた独立地盤を作成。座席の高さを維持し、観客席の支柱18本と基礎18個（片側）を海底まで延長。
- 観客席の既存通路に開口を作り、各側2本の桟橋を接続。各経路は36蹴上の階段、踊り場、青い手すり、街側アーチ入口を持つ。未使用開口は手すりで閉じた。
- 新規21メッシュの非多様体エッジ数は0。Blenderの確認カメラの開始・中間・終了画像、階段詳細、海底断面を実際に表示して確認した。

## 実ゲーム検証

Godot 4.7.2 Forward+、オフライン問題のみで確認。実際の到着演出から WAITING_START → FLYOVER → COUNTDOWN → PLAYING まで進め、メニューへ復帰。設定・出題ソースを復元した。

| 検証 | 結果 |
| --- | --- |
| 通常2人プレイ | 経路4本、支柱・13地盤・コンベアの接地確認、エラー0 |
| 1人エンドレス | 観客席長倍率5.840625でも経路4本、階段の寸法を維持、エラー0 |
| 海底とコンベア底面 | 両方Y=-17.20000076、差0 |
| 街区地盤 | 13個すべて底面Y=-17.2、上面Y=-14.2 |
| 観客席 | 両側の基礎底面Y=-17.2、上端Y=4.2、観客495/508人と4列を維持 |
| 画質・時間帯 | low/balanced/high × 昼/夕方/夜の9条件を撮影、構造・状態保持検査合格。代表画像3条件を目視確認 |
| 影の品質連動 | 新設Geometryの影有効数 low=0、balanced/high=23 |
| 街側の地形 | 通常・エンドレス各4経路の入口周囲をBlender実メッシュへ投射。通路を突き抜ける地形0、地盤上面Y=-5.2 |
| ゲーム画面 | 全景・階段・水中の接地部を撮影して目視確認 |
| エディター | 既存の古いGDScriptキャッシュと開いていたCodeEditの内容を両方更新し、WaterfrontInfrastructureの表示を確認。一時更新ノードを除去して保存。game_world.tscnのSHA256は更新前と同じ |
| 保存・再起動 | 古い編集タブが保存時に連携コードを上書きする問題を修正。最終run46でディスクに連携コードが残り、メニューの新設基盤が1個生成されることを確認 |

2.5秒のPLAYING実時間サンプルは各603フレーム。フレーム間隔p95は通常2Pで4.958ms、エンドレス1Pで5.005ms。撮影は測定区間外。短い観測値であり、全端末・全状況の性能保証ではない。エディター連携の一時スクリプト検証はclass_name重複により誤ったreload error 43を返したが、実際の共有スクリプトの再読み込みはOK（0）、新規エディターログエラーなし。

背景構造としての設置。新規CollisionObjectは0で、桟橋をプレイヤーが歩く機能や観客の経路移動は追加していない。

## 証跡

- `artifacts/santorini_waterfront/blender_structural_audit.json`
- `artifacts/santorini_waterfront/blender_access_start.png`, `blender_access_mid.png`, `blender_access_end.png`
- `artifacts/santorini_waterfront/blender_stair_detail.png`, `blender_seabed_section.png`
- `artifacts/santorini_waterfront/waterfront_p2_playing_start_audit.json`
- `artifacts/santorini_waterfront/waterfront_endless_p1_playing_start_audit.json`
- `artifacts/santorini_waterfront/waterfront_p2_playing_start_overview.png`, `waterfront_p2_playing_start_stairs.png`, `waterfront_p2_playing_start_seabed.png`
- `artifacts/santorini_renovation/waterfront_p2_sequence.json`, `waterfront_endless_p1_sequence.json`
- `assets/environment/santorini_waterfront/export_manifest.json`
