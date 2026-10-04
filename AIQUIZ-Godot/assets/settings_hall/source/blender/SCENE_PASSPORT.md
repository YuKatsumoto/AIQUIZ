# Scene Passport — 設定ホール「連結チップソー講座」のセットと登場人物（Blender 組み立て）

SCENE
- intent: 設定画面（`ui/settings_hall.tscn`、`docs/settings_hall.md`）の講義コーナーを、プリミティブの仮組みから Blender で作り込んだセットに置き換える。登場人物はゲームの他の場面（結果演出の審判・操縦席）と同じゴドーくん（Godot のロゴ形のぬいぐるみ）を 5 体、それぞれ別の芝居（講義・ノートを取る・挙手・居眠り・チップソーをよける実習）で、見ていて飽きないループにする
- deliverable: `assets/settings_hall/lecture_set_props.glb`（小道具一式）、`godotkun_lecturer.glb` / `godotkun_student_notes.glb` / `godotkun_student_hand.glb` / `godotkun_student_doze.glb` / `godotkun_trainee.glb`（各 1 体＝リグ 1 ＋ぬいぐるみ 1 ＋小道具 1、アクション 1 本）、`source/blender/lecture_set.blend`（`bpy.data.libraries.write` で書き出す編集用）、確認レンダー `source/previews/*.png`、`source/build_report.json`。Godot 側は `scripts/world/settings_hall/lecture_set.gd` が GLB を読み、黒板の文字と状態ランプ（API 連動）は Godot のまま重ねる
- units: metres; axes: right-handed Z-up。Godot のセットのローカル座標 (x, y, z) = Blender (x, -z, y)。人物の正面は Blender -Y（= Godot +Z）
- render: EEVEE Next、1600x900、24fps。確認用のカメラ `CAM_Review` はゲームの最終カメラ（`settings_hall.gd` の FINAL_EYE/FINAL_AIM/FINAL_FOV）と同じ位置・画角
- dynamic: yes（人物 5 体のループ。小道具は静止、実習レールの刃だけ練習生のリグで動く）
- build: ユーザーのライブ Blender（5.1）上で `build_lecture_set.py` を実行する（Higgsfield の Blender 連携 `bl_execute` 経由）。開いているファイル（surge_tank.blend、未保存の変更あり）は切り替えず、その中に専用シーン `LectureSet_Build` を作って組み立て、書き出し後に `lecture_set.blend` へ書く。開いている他のシーンのデータには触れない

HIERARCHY
- collection/object naming: シーン `LectureSet_Build`。コレクション `LS_Props`（`PRP_*`）、`LS_Cast`（`RIG_*` / `HERO_*`）、`LS_Review`（`CAM_Review`、`LGT_*`、書き出さない）
- parent/child relationships: 小道具はワールド（セットのローカル）座標に置き、まとめて 1 つの GLB。人物はそれぞれ足元を原点にしたリグ＋メッシュ 1 枚（部位ごとに頂点グループ、関節は球で隠す剛体スキン）で、配置は Godot 側（`lecture_set.gd` の定数）
- protected existing objects: 開いているファイルの既存シーン（`Scene`、`TK_Denoise`）とその全データ。ビルダーは自分のシーンと `LS_` プレフィックスのデータだけを作り直す

ASSETS（寸法 m、位置はセットのローカル = Blender (x, y, z)）
- A01 PRP_Platform | BLOCK | stylized | 12.0×11.5×0.08 | (-0.8, -4.2, 0.04) | 板張り（幅 0.3 の板、3 色の木目）と鋼の縁
- A02 PRP_Blackboard | BLOCK | detailed | 7.6×0.14×3.5 | (0, -8.6, 2.3) | 木枠、黒板面（深緑）、チョーク受け、チョーク 3 本と黒板消し、右端 1.8 m にチョーク画（8 枚の刃の列、矢印、ジャンプする棒人間）。左 5.6 m は Godot の文字のために空ける
- A03 PRP_Lectern | BLOCK | stylized | 1.0×0.6×1.2 | (2.0, -6.3, 0) | 斜めの天板、正面にゴドーくんの顔のエンブレム
- A04 PRP_Desk_0..2 / PRP_Stool_0..2 | BLOCK | stylized | 机 1.1×0.6×0.72、椅子 r0.22 h0.45 | x ∈ {-2.3, 0, 2.3}、机 y=-1.6、椅子 y=-0.8 | 机の上にノート（開いた 2 枚）、鉛筆、机 2 にミニチップソーの模型
- A05 PRP_ExhibitTable | BLOCK | stylized | 5.6×1.5×0.9 | (-3.9, -5.4, 0.45) | 青い布の台、名札立て（ゲーム側の台車 GLB をこの上に置く）
- A06 PRP_Bookshelf | BLOCK | stylized | 2.0×0.4×2.2 | (-5.6, -8.8, 0) | 3 段、色違いのバインダー、紙の束
- A07 PRP_PosterEasel | BLOCK | stylized | 1.0×0.8×1.8 | (4.9, -8.2, 0) | イーゼルに安全ポスター（黄色い三角の「!」、赤帯）
- A08 PRP_PracticeRail | BLOCK（練習生の GLB に含める） | detailed | 5.3×0.5×0.25 | 練習生の足元 (0,0,0) を通り y -2.8〜+2.5 | 鋼の U 字レール、端のストッパー、モーター箱、床の黄黒テープ。刃 r0.35（16 歯）はリグの `Blade` ボーンで走る
- A09 PRP_Cones ×3 / PRP_Sign_Practice | BLOCK | stylized | コーン h0.5 | レールの周り | 白帯のオレンジのコーン、A 型の黄色い看板
- A10 PRP_Extinguisher / PRP_Toolbox / PRP_Bin | BLOCK | stylized | 0.6 / 0.5 / 0.6 | 奥と脇 | 赤い消火器、赤い工具箱、鋼のごみ箱
- A11 HERO_Lecturer（RIG_Lecturer） | 既存資産 | detailed | 高さ 1.62（上の歯の先） | Godot (3.4, 0, 6.5)、正面 -Z | 丸眼鏡、赤い蝶ネクタイ、右手に指し棒。ぬいぐるみ本体は `assets/result_finale/referee_finale.glb` の `HERO_GodotPlush` / `RIG_Referee`（16 本の DEF ボーン）を読み込んで使う。小道具は `HERO_<name>_Gear`（別メッシュ、同じリグでスキン）
- A12 HERO_StudentNotes | 既存資産 | detailed | 同上 | 机 1（x=-2.3）の椅子 | 右手に鉛筆
- A13 HERO_StudentHand | 既存資産 | detailed | 同上 | 机 0（x=0）の椅子 | 緑の帽子（つばは後ろ）
- A14 HERO_StudentDoze | 既存資産 | detailed | 同上 | 机 2（x=2.3）の椅子 | 頭上に「Zzz」
- A15 HERO_Trainee | 既存資産 | detailed | 同上 | Godot (-4.4, 0, 1.2)、正面 +Z（刃の来る側） | 黄色いヘルメット、膝当て
- generation: 3D 生成は使わない（全部 BLOCK、手続き的に作る。クレジットの消費なし）
- fidelity: 人物とレール・黒板は detailed、他の小道具は stylized

SHOT
- active camera: CAM_Review = Godot FINAL_EYE (5.8, 6.6, -12) → Blender (5.8, 12.0, 6.6)、aim Godot (2.6, 1.6, 1.0) → Blender (2.6, -1.0, 1.6)、垂直画角 40°
- framing: 右 55〜60% にセット（左 1/3 はホールの柱列のために空ける）。手前に生徒、中景に教壇と講師、奥に黒板・本棚

LOOK
- material roles: ゴドーくんは読み込んだぬいぐるみの材質（`GK_Plush`、テクスチャ `GK_PlushAlbedo`）。小道具の色（緑・黄・赤・黒・銀）。教壇のエンブレムの青（#478CBF）。木（3 トーン）、鋼（縁・椅子・レール）、黒板の深緑、チョーク白（弱い発光）、安全色（黄・黒・オレンジ・赤）
- material route: すべて Principled のフラットな色（glTF で運べる範囲）。発光は emission strength で持たせる
- texture scale: テクスチャは使わない（板の継ぎ目は形で出す）
- world/background: 確認用は暗い灰色のワールド。書き出さない

LIGHTING（確認レンダー用のみ。ゲームでは Godot のスポットが照らす）
- key: ゲームの KeyLight と同じ向き（セットの +X 手前上から）。fill は左から弱く、rim は黒板の後ろ上から
- 暗い領域: 奥と左。黒板の文字が読める明るさ

MOTION（24fps。各人物 1 本のループ。Godot ではそれぞれ別の AnimationPlayer が位相をずらして回す）
- 共通: ぬいぐるみは頭と胴が一体のメッシュで顔が `DEF-head` / `DEF-hips` の両方に乗るので、この 2 本は曲げない（キーも打たない）。体の傾き・向きは足した `Body`（座面の高さ）、位置・向き・跳躍は `Root`（足元）で剛体として動かし、曲げるのは腕と脚だけ。腕が短く体の正面より前へ届かないので、机の上の手は机の手前の縁に置く
- Teach 288f: 待機 → 足元ごと振り向いて黒板を指し棒で 2 回叩く → 教室へ向き直っておじぎ 2 回、左手で説明 → 両腕を上げて「ジャンプ！」の小さな跳躍 → 待機へ戻る
- TakeNotes 192f: 黒板を見る → 前かがみになって鉛筆を走らせる（6 往復）→ 体を起こしてうなずく → 戻る
- RaiseHand 240f: 待機 → 右手を高く挙げて振る（横の歯に当たらないよう外・前へ開く。座面で弾む）→ 下ろす → 体ごと左右を見回す → 戻る
- Doze 216f: 体ごとゆっくり前へ垂れる（Zzz が大きく）→ はっと起きる（腕がびくっと開く、Zzz 消える）→ 見回す → また垂れる
- Practice 120f: 刃がレールを手前へ走る（96f で 5.3 m、残りは戻って待機）。練習生は予備動作 → 刃が足元を通る 51f を頂点に跳び越える（1.1 m、脚を抱える）→ 着地で沈む → 「ふう」と腕をぱたぱた → 構え直す（額は腕が届かないので拭わない）
- 休符: 各ループに 1 秒以上の静止に近い区間（サムネイル用のフレーム）

ACCEPTANCE
- structural: 書き出し 6 本、人物は armature 1 ＋ mesh 2（ぬいぐるみ・小道具）、`Root` / `Body` 以外の全ボーンに頂点が付く、三角形は人物 1 体 15k 以下・小道具合計 60k 以下、`.001` の重複材質なし、スケールは 1
- motion: 各アクションの最初と最後が同じ姿勢（ループ）、`DEF-head` / `DEF-hips` にキーがない、跳躍の間（28〜75f）ぬいぐるみが刃の円盤（歯を含む）に触れない、座った生徒の胴の底が座面にある（±0.03）
- visual: CAM_Review のレンダーで人物の顔が読める、黒板の左 5.6 m が空いている、刃の列がチョーク画と模型の両方で分かる、プリミティブの箱のまま見える資産がない
- game: Godot で `ui/settings_hall.tscn` を実行し、落ち着いた構図で 5 体が別々に動き、黒板の文字がチョーク画と重ならない
