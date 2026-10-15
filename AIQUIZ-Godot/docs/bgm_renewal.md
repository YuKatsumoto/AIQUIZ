# BGMリニューアル（全曲AI生成）

現在のBGMは4曲（2026年10月12日にオンライン対戦のマッチング待機用 `quiz_match_loop.ogg` を足した）。プレイ中（壁が割れてから）は `assets/audio/bgm/quiz_play_loop.ogg`（2026年10月11日採用）、クリア画面と2人用のスコアタワーは `assets/audio/bgm/quiz_result_loop.ogg`（2026年10月12日採用）、それ以外の場面は `assets/audio/bgm/quiz_party_loop.ogg` を流し、場面ごとに音量を変えている（`scripts/autoload/audio_manager.gd`）。どれもSunoで生成した（「採用した曲」の節）。メニュー曲は2026年10月8日に、それまでの `head_in_the_sand.ogg`（CC0、38秒）から差し替えた。これを場面別の素材に増やしていく。全曲を音楽生成AIで作る。

この文書は、生成AIへの発注仕様（プロンプト）と、Godotへ組み込むときの仕様をまとめたもの。

生成はSunoで行い、現行BGMのようにシンプルで壮大すぎない曲にする。プロンプトは「Suno用シンプル版（現行BGM準拠）」の節を優先し、「共通スタイル」以降の楽器の多い案は参考として残す。

## 素材一覧

| ID | 場面 | 種類 | 長さ | BPM | キー |
|---|---|---|---|---|---|
| `bgm_menu` | 起動・メインメニュー・カスタマイズ | ループ | 素材は2〜3分 | 92 | F |
| `bgm_online` | オンライン対戦画面（ヘリポートのトップ・ともだちコード・スキン設定・乗り込み〜検索中の飛行） | ループ | 素材は2〜3分 | 自由 | 自由 |
| `bgm_intro` | ヘリ降下・問題生成待ち・開始待ち・空撮 | ループ | 素材は1〜2分 | 120 | F |
| `sting_countdown` | カウントダウン「5・4・3・2・1」→壁が割れる | 単発 | 約6.5秒 | 120 | F→B♭ |
| `bgm_tutorial` | チュートリアル | ループ | 素材は2分 | 104 | F |
| `bgm_play` | 本編（1P10問・協力・オンライン・1Pエンドレス） | ループ | 素材は2〜3分 | 150 | B♭ |
| `bgm_chase` | のこぎり追跡（ローカル2Pの10問・エンドレス） | ループ | 素材は2分 | 168 | Gm |
| `bgm_goal` | ゴールまでの競争 | ループ | 素材は1〜2分 | 176 | B♭ |
| `ceremony_build` | スコアタワーが伸びる場面（〜6.3秒） | 単発 | 約8秒 | テンポ自由 | F（解決させない） |
| `sting_verdict` | 判定（6.9秒） | 単発 | 約4秒 | — | B♭ |
| `bgm_result` | スコアタワーの後・クリア画面 | ループ | 素材は2分 | 112 | F |
| `jingle_clear` | クリア | 単発 | 約6秒 | 150 | B♭ |
| `jingle_gameover` | ゲームオーバー | 単発 | 約5秒 | — | Gm |
| `bgm_gameover` | ゲームオーバー画面 | ループ | 素材は1〜2分 | 92 | Dm |

- **曲を作らない場面**
  - ポーズ：流れている曲にローパスフィルターをかけ、音量を−10dBにする。
  - サドンデスと設定ホール：使われていないので対象外。
- **テーマ曲を使う場合**：キーとテンポは「Suno用シンプル版」の「テーマ曲」の節を優先する（全曲C、`bgm_menu` は117 BPM）。
- **キーの選び方**：つながる場面同士を近いキーにして、クロスフェードしても濁らないようにした。
  - B♭とGmは平行調。FはB♭の属調。
  - 生成AIはキーの指定を守らないことがある。守られなくても切り替え自体は成立するので、作り直す必要はない。

## 時間の基準（コードから）

- **空撮**：3.8秒（`game_state.gd:2013`）。チュートリアルでは省略。
- **カウントダウン**：4.99秒（`QuizGameState.COUNTDOWN_SECONDS`、2026年10月11日に3.99秒から変更）。
  - 表示は `ceil(countdown_timer)` で「5・4・3・2・1」を約1秒ずつ（`game_world.gd`）。0秒で壁が割れて PLAYING になる。
  - 進むにつれて壁の揺れと蒸気が強くなる。
  - チュートリアルは3.0秒から始まるので「3・2・1」だけ。`sting_countdown` を2.0秒の位置から再生すれば合う。
  - 数字が変わるたびに電子音「ぷっ」、壁が割れる瞬間に「ぷーん」が鳴る（OtoLogic の素材、`docs/sound_effects.md`）。`sting_countdown` を作る場合はこの電子音と重なる。
- **スコアタワーの演出**（`assets/result_finale/finale_motion.json`。両者がゴールした時点を0秒とする）

| 時刻 | 出来事 |
|---|---|
| 2.0秒 | 出演者の登場 |
| 2.34秒 | 台座が出る |
| 4.1〜6.3秒 | 塔が伸びる |
| 6.3秒 | 静寂（hush） |
| 6.9秒 | 判定 |
| 7.4秒 | 負けた側の塔が沈み始める |
| 7.66秒 | 王冠が乗る |
| 7.05〜9.3秒 | 花火 |
| 11.2秒 | 演出が終わり、9.6〜11.2秒の動きをループする |

## Suno用シンプル版（現行BGM準拠）

現行BGMのような「シンプルで壮大すぎない」曲をSunoで作るための版。これを第一候補にする。メロディは全曲で下の「テーマ曲」のものを使う。

### テーマ曲（全曲のメロディの元）

Sunoで作った「8-bit J-Pop (Edit) (Edit)」のメロディを、全曲で使う。

| 項目 | 内容 |
|---|---|
| 元ファイル | `assets/audio/bgm/source/theme/theme_8bit_jpop_original.mp3`（145.5秒、48kHzステレオ、Sunoユーザー katsuyu2354） |
| 参考音源 | `assets/audio/bgm/source/theme/theme_24bars_reference.wav`（元ファイルの1.793〜51.019秒、49.23秒） |
| テンポ | 117 BPM、4/4。曲の最後までほとんど揺れない |
| キー | ハ長調（C） |
| 音 | 8-bitのチップチューン。音量は最初から最後までほぼ一定（−14.2 LUFS、ラウドネスレンジ1.3 LU） |
| 構成 | 1.793秒を0小節目とすると、24小節（約49.2秒）で1周する。0〜7小節目、8〜15小節目（前と同じメロディで、終わりだけ変えたもの）、16〜23小節目（別のメロディ）の順。これを2周したあと、102〜116秒あたりと135秒あたりに短いブレイクが入り、最後の数小節で終わる |

- **参考音源を切り出した理由**：元ファイルをそのままCoverすると、ブレイクや終わりまで真似される。最初の24小節だけにすると、ループに使いやすい約49秒の曲が返ってくる。
- **元ファイルから楽譜は作っていない**：解析でメロディの音を拾うと、伴奏やベースの音が混ざって正確にならないため。メロディが保たれているかは耳で確認する。
- **商用利用の権利**：元の曲を生成したときのプランを確認する。Sunoでは、無料プランで作った曲は、後から有料プランに入っても商用利用できない扱いになっている（最新の規約で確認する）。無料プランで作った曲なら、有料プランで作り直すかCoverし直す。

#### テーマ曲を使った作り方

テキストのプロンプトではメロディを指定できない。そこで、参考音源をCoverして、場面ごとにテンポと雰囲気だけを変える。

- **`bgm_menu`**：テーマ曲そのもの（参考音源の24小節）をループにして使う。ゲームの顔なので、テーマのメロディを最初に聴かせる。メニューにしては元気すぎると感じた場合は、92 BPMでCoverする。
- **それ以外のループ曲**：参考音源をCoverする。設定は下の「Sunoの設定」、プロンプトは「場面のプロンプト」。
- **キー**：全曲をテーマ曲と同じハ長調（C）にそろえる。同じキーなら、場面の切り替えでクロスフェードしても音が濁らない。追跡（`bgm_chase`）とゲームオーバー（`bgm_gameover`）だけは、同じメロディの短調版（Cマイナー）にする。上の素材一覧のキーより、こちらを優先する。
- **テンポ**：Coverは元の曲のテンポ（117 BPM）に引っ張られることがある。指定したBPMにならなくても場面に合っていれば使い、ループ長はそのテイクのBPMで計算する。

### 現行BGMの特徴

`head_in_the_sand.ogg` の解析結果と、配布ページ（OpenGameArt）の説明から。

| 項目 | 内容 |
|---|---|
| ジャンル | 初期ファミコン風のチップチューン（FamiTracker製）。配布ページのタグは retro / blues / upbeat / arcade |
| テンポ | 約150 BPM。8分音符がまっすぐ刻む（跳ねない） |
| キー | ハ長調寄り。ブルースっぽい半音が少し混ざる |
| 編成 | 4パートだけ：矩形波2本（メロディと和音・アルペジオ）、三角波のベース、ノイズのドラム |
| 構成 | 38.4秒で1周。前半は音が少なく、後半はメロディの音数が増える。盛り上がり・転調・終わりはない |
| 音量 | −25.4 LUFS、トゥルーピーク −9.0 dBTP。かなり小さい |

ここから「シンプルさ」の条件を5つにまとめ、全曲の共通文に入れた。

1. パートは4つだけ（メロディ、和音、ベース、ドラム）。途中で楽器を足さない
2. 短く覚えやすいフレーズを、少しずつ変えて繰り返す（メロディはテーマ曲のものを使う）
3. コードは基本的なものだけ（コードもテーマ曲のものを使う）
4. 最初から最後まで同じテンポ・同じ勢い。盛り上げ、転調、終わりを作らない
5. 残響を少なくし、音の隙間を多く残す

### 音の方向は2つ。テーマ曲に合わせてAを基本にする

| 方向 | 音 | 長所 | 短所 |
|---|---|---|---|
| A：チップチューン | 現行・テーマ曲と同じファミコン風の電子音 | テーマ曲の音をそのまま生かせる。今のBGMの雰囲気にも近い | 見た目（PS1風の3D）とは時代がずれる。下の「8bitにしない理由」とは逆の選択になる |
| B：4人編成の生楽器 | 同じ4パートを、PS1時代のサンプリング風の生楽器で鳴らす | 見た目の時代と合い、シンプルさも保てる | テーマ曲（`bgm_menu`）とだけ音が違ってしまう。Sunoが楽器を足しがちなので、テイク選びに手間がかかる |

- **Bを試すとき**：Coverならメロディは保てる。ただしBにするなら、`bgm_menu` もテーマ曲をBでCoverしたものに替える。
- **方向は全曲でそろえる**：AとBを混ぜると、場面が変わったときに別のゲームのように聞こえる。

### Sunoの設定

2026年9月時点のv6の画面に合わせた設定。項目名はアップデートで変わることがある。

- **モード**：Create の Advanced。音声に `theme_24bars_reference.wav` をアップロードして、Cover で作る。数秒の単発素材は Sounds の One-Shot で作る（後述）。
  - アップロード時の「オーディオの内容の説明」は、種類に「ループ」だけを選び、説明欄に次を書く：`8-bit chiptune instrumental, 117 BPM, C major, 4/4. A 24-bar section that loops seamlessly. A catchy lead melody over simple chords, bass and drums. No vocals. The lead melody is the most important part.`
- **モデル**：v6。商用のゲームに使うので、Pro か Premier で生成する（v6もPro・Premier向け）。
- **Instrumental**：オン。歌詞欄は空にする。
- **Styles**：「場面のプロンプト」の後ろに「共通文A」か「共通文B」を付ける。
- **More Options**

日本語画面での項目名をかっこ内に書いた。

| 項目 | 設定 | 理由 |
|---|---|---|
| Exclude styles（除外欄） | 下の除外リスト | 壮大さ・歌・余計な楽器を入れさせない |
| Vocal Gender（ボーカル性別） | どちらも選ばない | インストなので不要 |
| Duration（長さ） | Auto | Coverは参考音源（約49秒）の長さと構成に沿う |
| Max Mode（Maxモード） | オフで始める | Suno は「元の曲に近いCover」にはMax Modeを勧めている。通常でメロディが崩れるときだけオンにする |
| Weirdness（奇抜さ） | 25% | 予想外の展開を減らす |
| Style Influence（スタイルの影響） | 70% | テンポ・雰囲気・4パートの指定を守らせる |
| Audio Influence（オーディオの影響） | 70% | テーマ曲のメロディを保たせる |
| Variety（バリエーション） | 標準より1段低く | 全曲で音の世界をそろえる |
| My Taste（パーソナライズ） | オフ | 自分の再生履歴の好みを混ぜない |

- **オーディオの影響とスタイルの影響は引っ張り合う**：オーディオの影響は元の曲（117 BPM・元の音色）に寄せ、スタイルの影響はプロンプト（場面のテンポ・雰囲気）に寄せる。
  - メロディが別物になった → オーディオの影響を80〜85%に上げる。それでもだめならMaxモードをオンにする。
  - 元の曲とほとんど同じで、テンポや雰囲気が変わらない → オーディオの影響を55〜60%に下げるか、スタイルの影響を80%に上げる。
  - 一度に動かすのは1つだけにして、変化を聴き比べる。

### 共通文（Stylesの末尾に付ける）

共通文A（チップチューン）：

```
Simple looping background music for a cheerful kids' 3D quiz party game, in the style of an early 8-bit NES-era game soundtrack. Only four voices, like the original sound chip: two square-wave channels (lead melody, and simple chords or arpeggios), a triangle-wave bass, and noise-channel drums. Keep the main melody and chords of the source song: simple, catchy and bouncy. Dry and clean, lots of space. Same tempo and same energy from start to finish: no build-up, no big climax, no key change, no fade-out, no ending. Instrumental only.
```

共通文B（4人編成の生楽器）：

```
Simple looping background music for a cheerful kids' 3D quiz party game, like a modest late-1990s console game soundtrack made with sampled acoustic instruments. A small band of only four parts that never grows: marimba plays the lead melody, accordion plays simple off-beat chords, a round upright bass, and a light drum kit. Keep the main melody and chords of the source song: simple, catchy and bouncy. Dry and clean, lots of space. Same tempo and same energy from start to finish: no build-up, no big climax, no key change, no fade-out, no ending. Instrumental only.
```

- **Bの楽器を変えたいとき**：2文目の楽器名だけを差し替える（例：`marimba` → `mandolin`）。全曲で同じ4つの楽器を使うことが統一感になる。

除外リスト（Exclude styles）：

| 方向 | 除外リスト |
|---|---|
| A | `orchestral, cinematic, epic, choir, vocals, spoken word, acoustic drums, electric guitar, heavy reverb, EDM, dubstep, sound effects` |
| B | `orchestral, cinematic, epic, choir, vocals, spoken word, chiptune, 8-bit, synth pads, synth lead, string section, brass section, heavy reverb, EDM, sound effects` |

- **`sound effects` を入れる理由**：場面の説明に港や競争の言葉があると、Sunoがカモメや歓声の音を混ぜることがあるため。

### 場面のプロンプト（ループ曲）

楽器は共通文で、メロディは参考音源で決まるので、ここにはテンポ・雰囲気・音の密度だけを書く。

| ID | プロンプト |
|---|---|
| `bgm_menu` | テーマ曲そのものを使う（Coverしない）。元気すぎると感じたときだけ、次でCoverする：`Main menu theme, 92 BPM, C major, 4/4. Relaxed, friendly and catchy, like a calm title screen: the melody over a bouncy two-beat bass and a light, steady beat. Medium-low energy.` |
| `bgm_intro` | `Pre-game waiting loop, 120 BPM, C major, 4/4. Light anticipation, like a game show just before the first round: the melody played lightly over a repeating bass riff and ticking hi-hat, so it can loop while the game loads. Medium energy, no climax.` |
| `bgm_tutorial` | `Tutorial loop, 104 BPM, C major, 4/4. Friendly and encouraging, very sparse: the melody played softly with long rests over a simple bass and drum groove, so on-screen instructions stay easy to read. Low energy.` |
| `bgm_play` | `Main gameplay loop, 150 BPM, C major, 4/4, straight eighth notes. Upbeat and bouncy: the melody as a catchy lead, a busy walking bass, and a driving but light beat. Fun, never tense. Medium-high energy that stays even.` |
| `bgm_chase` | `Chase loop, 168 BPM, C minor, 4/4: a minor-key version of the same melody. Comedic hurry, like a cartoon chase in an old arcade game: fast pulsing bass and a busy beat. Urgent but funny, never scary. High energy that stays even.` |
| `bgm_goal` | `Final sprint loop, 176 BPM, C major, fast 2/4 galop feel. A cheerful dash to the finish line: the melody played quick and bouncy, oom-pah bass on every beat, snappy drums. Exciting and silly, but the same small band, not an orchestra. High energy that stays even.` |
| `bgm_result` | `Results screen loop, 112 BPM, C major, 4/4. Happy, relaxed "well done" mood: the melody played light and lilting over a gentle bass and a soft beat. Medium-low energy, pleasant to sit on for a while.` |
| `bgm_gameover` | `Game-over screen loop, 92 BPM, C minor, 4/4: a minor-key version of the same melody. Droll and a little sheepish, not sad: lazy lead, plodding bass and a soft beat. Gently funny, makes you want to try again. Low energy.` |

- **短調版（`bgm_chase`、`bgm_gameover`）**：メロディが崩れて別の曲になったら、`C minor` と `a minor-key version of the same melody` を外し、`C major` にして雰囲気だけで差をつける。

### 単発素材（Sounds の One-Shot で作る）

Advanced では1曲分の長さで作られるので、数秒の素材は Sounds の One-Shot で作る。BPMとキーを指定できる場合は、素材一覧の値を入れる。うまくいかないときは、Advanced で作った短い曲から切り出す。

プロンプトの `<音色>` は、方向Aなら `8-bit chiptune`、方向Bなら `Marimba, accordion and light drums` に置き換える。

| ID | プロンプト |
|---|---|
| `sting_countdown` | `<音色> countdown sting, 120 BPM, about 5.5 seconds. Four short notes exactly one second apart, each a step higher, then one bright B-flat major "GO" chord at 4.0 seconds with a quick ring-out.` |
| `ceremony_build` | `<音色> suspense build, about 8 seconds. A fast repeated note and a drum roll rising steadily in pitch and volume, holding an unresolved F chord. Never resolves, no final hit.` |
| `sting_verdict` | `<音色> winner sting, about 4 seconds, B-flat major. Starts instantly on a bright hit, then a short happy fanfare phrase, ending on a held B-flat major chord.` |
| `jingle_clear` | `<音色> stage-clear jingle, about 6 seconds, B-flat major, 150 BPM. A short cheerful rising melody ending on a bright held major chord.` |
| `jingle_gameover` | `<音色> game-over jingle, about 5 seconds, G minor. A comedic "oh no" phrase tumbling downward, ending on a deflated low note. Funny, not sad.` |

### テイクの選び方

- **捨てるテイク**：途中で楽器が増える、ストリングスやコーラスが入る、盛り上がって終わる、テンポが揺れる。
- **音の多さ**：現行BGMと並べて聴き、音の多さが同じくらいのものを選ぶ。
- **メロディの確認**：テーマ曲と交互に聴き、同じメロディだと分かるものを選ぶ。メロディが別物になったテイクは捨てる。

### 音量の注意

後処理ではループ曲を −16 LUFS にそろえる方針だが、前のBGM（`head_in_the_sand.ogg`）は −25.4 LUFS で、約9.4 dB小さかった。`CONTEXT_VOLUME_DB` の場面ごとの音量は前のBGMに合わせて決めてあるので、そのまま差し替えると、効果音に対してBGMがかなり大きく聞こえる。

そこで `audio_manager.gd` に `BGM_TRACK_GAIN_DB = -9.4` を置き、場面ごとの音量に足している。BGMをもっと大きくしたいときは、この値を0に近づける。

BGM音量のスライダー（0〜1）は、BGMバスの音量に次の対応で変換する（`bgm_volume_to_db()`、2026年10月9日から）。

| スライダー | 0 | 0.05 | 0.1 | 0.25 | 0.5（初期値） | 0.75 | 1.0（最大） |
|---|---|---|---|---|---|---|---|
| BGMバス | 無音 | −31.2 dB | −21.8 dB | −9.4 dB | 0 dB | +5.5 dB | +9.4 dB |

- 初期値の0.5は、それまでの最大（スライダー1.0＝0 dB）と同じ音量。スライダーを半分にするごとに9.4 dB下がる。
- 最大の +9.4 dB（`BGM_MAX_GAIN_DB`）は `BGM_TRACK_GAIN_DB` をちょうど打ち消す値。場面ごとの音量が 0 dB なら曲そのものの音量（−16 LUFS、ピーク −4.3 dBFS）になり、音割れしない。
- 場面ごとの音量（`CONTEXT_VOLUME_DB`）は、メニュー・プレイ中・結果がどれも −4 dB（2026年10月12日から）。それまではプレイ中だけ 0 dB で、ゲーム画面に入ると4 dB上がっていた。ポーズとサドンデスは −10 dB。
- それまでは、スライダーの値をそのまま音量の倍率にしていた（0.5＝−6 dB、1.0＝0 dB）。この形式で保存された設定（`user://audio_settings.cfg` に `version` がないもの）は、起動時に同じ音量になるスライダー位置へ直して保存し直す（1.0→0.5、0.5→0.3）。

### `bgm_play` の候補（2026年10月11日生成、選定待ち）

メニュー曲のメロディを使わず、新しいメロディで作った候補。ジャンルを10通りに変えた。Coverではなく、参考音源なしで作った。

- **設定**：Advanced、v6、歌詞欄は空、長さ2:30、奇抜さ35%、スタイルの影響70%、バリエーションはオフ、パーソナライズはオフ。
- **Styles**：ジャンルごとの文の後ろに、次の共通文を付けた。コード進行とキーは指定していない。

```
Gameplay background loop for a cheerful kids' 3D quiz party game: players run and bump through giant quiz walls with answer doors. A brand-new, original, catchy lead melody with short, hummable phrases. Bright, happy and fun, never dark, sad or scary. Steady tempo and even energy from start to finish: no build-up, no risers, no breakdowns, no big climax, no fade-out, no ending; each phrase flows straight into the next. Clean, punchy mix with space left for sound effects. Instrumental only.
```

- **除外リスト**：`vocals, choir, spoken word, humming, dark, sad, horror, minor key, epic, cinematic, risers, whoosh, sweeps, build-up, drops, dubstep, heavy reverb, sound effects`
  - `risers, whoosh, sweeps, build-up` は、区切りで低い音から駆け上がる音を入れさせないために足した。

| 曲名（Suno） | ジャンル（ジャンルごとの文の要点） | song id |
|---|---|---|
| Quiz Play 01 Chiptune | 150 BPM。ファミコン風。オクターブで跳ねるメロディ | `f37af25c-9905-4c61-abe2-f45a3560430f`、`c21034ea-28ce-40ac-b485-0746f425ae24` |
| Quiz Play 02 Ska | 160 BPM。スカ。ホーン隊のユニゾン | `4f228f58-8f05-493d-8bf7-0ddec1a49f39`、`0b731c6f-231e-4662-badf-b80e00d4cdd6` |
| Quiz Play 03 Surf | 155 BPM。サーフロック。エレキギターの速いメロディ | `7936d123-65d3-45d9-8f26-ddc484e0b4de`、`969de7c3-7f77-4c72-ab45-41cd199109e7` |
| Quiz Play 04 Greek | 150 BPM。ギリシャの島の民族舞曲。ブズーキとマンドリン | `0934a3dc-6d97-4fd6-9c05-5c8a77498778`、`bd6a608d-95c2-4705-ab56-33ff8ec42afc`、`e05a8a9d-c724-43d7-8a97-c920453fa201`、`99a52dbb-f142-4531-848b-664c2bee0798` |
| Quiz Play 05 Swing | 150 BPM、跳ねる8分。ビッグバンド・スウィング | `70d6eb73-f50a-424f-abe1-99cdfaffded3`、`98fa08c3-6995-4524-b021-417b75d48a80` |
| Quiz Play 06 Shibuya | 145 BPM。90年代のバラエティ番組風の渋谷系 | `a8fb3ba1-85c3-4ccf-90d4-31adb2d613dd`、`805e5962-5a32-4403-a452-249efa3ceeee` |
| Quiz Play 07 Marimba | 150 BPM。マリンバ・アコーディオン・ウッドベース・ドラムの小編成 | `43280828-c72c-4cb1-854b-af018ea724ff`、`ac637923-577d-46cd-8ca9-486f9516fa6c` |
| Quiz Play 08 Cartoon March | 150 BPM、2拍子のノリ。アニメのドタバタ行進曲 | `509a5503-0c27-4ce1-85db-32204c890596`、`8e27b7a4-c4ce-44af-a88e-0848a2bcffca` |
| Quiz Play 09 Pop Rock | 170 BPM。スポーツアニメのオープニング風ポップロック | `20d0f780-4a9e-43f2-928d-0dfbfefe78f5`、`68538ece-0894-41e7-bee1-a28d42e2cf1c` |
| Quiz Play 10 90s Console | 140 BPM。90年代ゲーム機風のファンク（サンプリング音源） | `4a9cb0cd-fac0-40bf-bee6-32e3d78c62aa`、`aa96e20d-fae0-428d-8920-c5bf315384c6` |

- 曲のページは `https://suno.com/song/<song id>`。
- 10月9日に作った候補（Coverの2曲、新しいメロディのチップチューン4曲と生楽器4曲）も、選定待ちのまま残っている。

### Cartoon Marchのチップチューン版（2026年10月11日生成、選定待ち）

`bgm_play` の候補「Quiz Play 08 Cartoon March」（`8e27b7a4`、2:29）を、今のメニュー曲と同じ音色（ファミコン風の4パート）でCoverした候補。メロディと構成は08のまま、楽器だけを替える指示にした。

- **参考音源**：Sunoのワークスペースにある08の曲を、「オーディオ」→「参照」で選んだ。
- **設定**：Cover、v6、歌詞欄は `[Instrumental]`、長さAuto、奇抜さ25%、スタイルの影響70%、バリエーションはオフ、パーソナライズはオフ。オーディオの影響は70%と55%で1回ずつ。
- **Styles**：メニュー曲（Suno「Quiz Party Loop」）のスタイル文を元に、テンポを08の150 BPMにした。

```
Chiptune version of the source song: keep its main melody, chords, tempo and structure, and change only the instruments. Early 8-bit video game soundtrack, two square-wave channels trade a catchy lead and clipped chords, triangle-wave bass walks beneath crisp noise-channel drums; instrumental, buoyant straight eighths at 150 BPM, dry clean mix with open space. Bright, happy and playful, never dark. Even energy from start to finish: no build-up, no risers, no breakdowns, no big climax, no fade-out, no ending; each phrase flows straight into the next.
```

- **除外リスト**：`orchestral, cinematic, epic, choir, vocals, spoken word, acoustic drums, brass, tuba, strings, electric guitar, heavy reverb, EDM, dubstep, risers, whoosh, build-up, sound effects`

| オーディオの影響 | song id | 長さ |
|---|---|---|
| 70% | `65daed1f-feb8-4155-94d7-f2be08a5d6e2` | 134.6秒 |
| 70% | `61b02d79-fe39-4eb5-bfd6-6e3fcbce02db` | 132.0秒 |
| 55% | `e2f4d387-0027-416e-a650-7f25cda17c4a` | 148.8秒 |
| 55% | `c385d72f-0434-4a7e-b5fb-be82433c3799` | 146.4秒 |

- 同じ日に、逆の向き（メニュー曲を08の楽器でCover）の「Quiz Party Loop (Cartoon March)」も4曲作ったが、依頼と逆だったので候補にしない（`58debecc`、`ed66a9e6`、`17ee391b`、`acb6c603`）。

### メニュー曲の音色で作った新しいメロディ（2026年10月11日生成）

メニュー曲と同じ音色（ファミコン風の4パート）のまま、メロディの性格だけを変えて作った `bgm_play` の候補。参考音源は使っていない。この中の「Quiz Chip Sports 03 Clown Galop」（`c723f094`）を採用した（「採用した曲」の `quiz_play_loop.ogg`）。

- **設定**：Advanced、v6、歌詞欄は `[Instrumental]`、長さ2:30、奇抜さ35%、スタイルの影響70%、バリエーションはオフ、パーソナライズはオフ。
- **Styles**：メニュー曲（Suno「Quiz Party Loop」）のスタイル文に、テンポとメロディの説明（`Melody: ...`）を足し、次の共通文を付けた。

```
<メニュー曲のスタイル文（テンポを差し替え）> Melody: <メロディの説明> Gameplay background loop for a cheerful kids' 3D quiz party game. A brand-new, original, catchy melody. Bright, happy and fun, never dark. Same tempo and even energy from start to finish: no build-up, no risers, no breakdowns, no big climax, no fade-out, no ending; each phrase flows straight into the next.
```

- **除外リスト**：`orchestral, cinematic, epic, choir, vocals, spoken word, acoustic drums, electric guitar, heavy reverb, EDM, dubstep, risers, whoosh, build-up, dark, sad, minor key, sound effects`
- **「Sports」の付いた6種類**：「運動会で流れていそうな速さとメロディ」という要望で作った。拍子を2/4にし、ベースは「拍ごとに弾む」などに替えた。

| 曲名（Suno） | テンポ | メロディの説明（要点） | song id |
|---|---|---|---|
| Quiz Chip 01 Hopping | 150 | オクターブで跳ね、分散和音で飾る | `44c8e20d-5518-4fd2-8472-fc497559b7fc`、`86a9940d-0984-4b33-9cd7-f6b151c36f6e` |
| Quiz Chip 02 Singalong | 150 | 隣の音へ進む、口ずさめる歌のような旋律 | `b98d7e4b-2859-46e3-b618-b7b472b63bd0`、`f8e54f74-3b4a-4118-a97f-ef5563c158a1` |
| Quiz Chip 03 Running | 160 | 速い音階とトリルが駆け回る | `03df81c2-5d93-4039-9773-ff4162741033`、`cfc17613-4752-4b80-9698-3455d78e55b8` |
| Quiz Chip 04 Call and Response | 144 | 2本の矩形波が問いと答えを掛け合う | `7f678d16-aec4-4ba0-a63b-b81ef754931c`、`cf1c4a9d-d309-454c-90a1-15c5c166c947` |
| Quiz Chip 05 Syncopated | 150 | 裏拍のアクセントで弾む | `49cd4c32-6ab6-493d-a8b8-488b018290e2`、`9e046a01-11dd-4a3f-a343-8f7a2be4c098` |
| Quiz Chip 06 Fanfare | 156 | 連打音と大きな跳躍のファンファーレ風 | `284eb6ab-68ae-4f7a-b9ec-1291577dcc3d`、`5c52a2b8-042a-4e25-8270-0bb03c6725d3` |
| Quiz Chip 07 Cheeky | 140 | 装飾音と半音の経過音で、おどけたスタッカート | `4da1ea41-04fa-42ef-9d55-ab89accd6ea4`、`f1f78e58-5710-41c7-a280-a62b524c5615` |
| Quiz Chip 08 Pentatonic | 150 | ペンタトニックで、夏祭りのような軽さ | `5291151c-e250-4aa1-805c-605e2437351a`、`74f76fb0-4a9f-4273-8684-5aec1fcd7318` |
| Quiz Chip Sports 01 Galop | 176、2/4 | カンカン風のギャロップ。連打音と駆け上がり（リレー） | `4463a4e1-b214-4861-ab48-238c7a4557b7`、`9ab7d7af-3b18-4d66-bdb3-93284fed48f2` |
| Quiz Chip Sports 02 Post Horn | 168、2/4 | ラッパの合図のような付点リズムと3連符 | `6f19bc41-eb45-43a1-b300-78d0dfe3f655`、`91a7c66e-5cd5-4a2e-a9fc-10e4756a97e5` |
| Quiz Chip Sports 03 Clown Galop | 172、2/4 | 半音階で上下する、サーカス風のギャロップ（障害物競走） | `5e5ab5e4-6f40-46a2-8974-30b4ff6f21ac`、`c723f094-ec06-496a-a902-e72e4afe4b71` |
| Quiz Chip Sports 04 Gallop Finale | 160、2/4 | 「タタタン」と駆ける序曲のフィナーレ風（最終リレー） | `42bf426a-f7cc-41f5-a21d-d0766dd8cc55`、`aafeabfd-d0e0-4c55-8cfe-f453ef4e8e09` |
| Quiz Chip Sports 05 Polka | 160、2/4 | 付点で跳ねる速いポルカ（玉入れ） | `9c587c61-48cb-4e22-a813-843efb6b5175`、`d9a51543-9491-4475-8616-376c4812d58c` |
| Quiz Chip Sports 06 Quick March | 144、2/4 | 入場行進のような速い行進曲 | `28075351-c1de-4f75-9bca-3c12423aabaa`、`d1df04f1-621a-4ac6-badf-0052d76065f8` |

- 長さはどれも約2分29〜30秒。
- 生成の途中で、Sunoに「私はロボットではありません」の確認が出たので、ユーザーに対応してもらった。

### `bgm_result` の候補（2026年10月12日生成）

結果画面（1人用のクリア画面、2人用のスコアタワー演出の後）のループ曲の候補。メニュー曲と同じ音色で、メロディの性格を8通りに変えた。参考音源は使っていない。この中の「Quiz Result 03 Parade」（`319f8136`）を採用した（「採用した曲」の `quiz_result_loop.ogg`）。

- **設定**：「メニュー曲の音色で作った新しいメロディ」の節と同じ（Advanced、v6、歌詞欄 `[Instrumental]`、長さ2:30、奇抜さ35%、スタイルの影響70%、除外リストも同じ）。
- **Styles**：メニュー曲のスタイル文（テンポとノリを差し替え）＋ `Melody: <メロディの説明>` ＋次の共通文。

```
Results screen loop for a cheerful kids' 3D quiz party game, played after the race while players look at their scores. Happy and relaxed, never dark or sad. Same tempo and even energy from start to finish: no build-up, no risers, no breakdowns, no big climax, no fade-out, no ending; each phrase flows straight into the next.
```

| 曲名（Suno） | テンポ・ノリ | メロディの説明（要点） | song id |
|---|---|---|---|
| Quiz Result 01 Victory Lap | 112、まっすぐな8分 | 隣の音へ進む、満足げな「よくできました」（ウイニングラン） | `823e3936-6a6d-448f-bfce-df7c51f78a9e`、`d01a88e3-4f49-4fb4-a190-abed39d30008` |
| Quiz Result 02 Shuffle | 104、跳ねるシャッフル | のんびり跳ねる、少しおどけた旋律 | `699d6095-77f5-49d9-97ea-c0be62bb7e35`、`89971fb8-d885-4123-9f3a-33098bfeeed1` |
| Quiz Result 03 Parade | 120、軽い行進 | 誇らしげだがくつろいだパレード。フレーズの終わりに小さなファンファーレ | `319f8136-24f1-401b-9157-027df0e2bfba`、`4053e4f2-57f1-4b9d-b06b-77e3748d94fd` |
| Quiz Result 04 Stroll | 96、ゆったり | レース後の散歩のような、口ずさめる旋律と穏やかな分散和音 | `157bd4ce-a7d7-45fc-80c7-4d07806e19c8`、`64fb6df5-4214-4b76-885a-b48d0081fc06` |
| Quiz Result 05 Party | 116、弾む | オクターブで跳ねる、お祝いパーティー | `9463c04a-c094-41d5-aeec-731cc6429654`、`cdf4e416-2004-4bc6-999c-752d5ac0325b` |
| Quiz Result 06 Waltz | 132、3/4 | メリーゴーラウンドのワルツ | `b69de95f-f257-4e82-a655-b1eb945ee71e`、`fa25fb0a-1a30-4f78-ba0d-98b27b1122fa` |
| Quiz Result 07 Island | 112、シンコペーション | 裏拍で弾む南の島のビーチパーティー | `a8f05732-626a-495d-a178-d3ef72b82327`、`bd070454-2beb-4f5f-a952-6ed523881a1d` |
| Quiz Result 08 Fun Day | 100、まっすぐな8分 | 楽しい一日を振り返るような、少し懐かしいが明るい旋律 | `282af357-c6c3-4439-ae42-3084e83b0064`、`46cf090e-c21f-47e7-a1f7-6d8f178ebf7a` |

- 長さはどれも約2分29〜30秒。

### `bgm_online` の候補（2026年10月12日生成）

オンライン対戦画面（`OnlineMenu`：ヘリポートのトップ、ともだちコード、スキン設定、乗り込みから検索中の飛行まで）のループ曲の候補。今はこの画面でメニュー曲が流れている。メニュー曲と同じ音色で、メロディの性格を8通りに変えた。参考音源は使っていない。

- **設定**：「メニュー曲の音色で作った新しいメロディ」の節と同じ（Advanced、v6、歌詞欄 `[Instrumental]`、長さ2:30、奇抜さ35%、スタイルの影響70%、バリエーションはオフ、除外リストも同じ）。「Quiz Result 08 Fun Day」の「プロンプトを再利用」で入力欄を埋め、スタイル文と曲名だけを差し替えた。
- **Styles**：メニュー曲のスタイル文（テンポとノリを差し替え）＋ `Melody: <メロディの説明>` ＋次の共通文。

```
Online versus lobby loop for a cheerful kids' 3D quiz party game: players wait at a seaside heliport and fly a helicopter over the sea while searching for an online rival. Excited, adventurous anticipation; bright and fun, never dark or scary. Same tempo and even energy from start to finish: no build-up, no risers, no breakdowns, no big climax, no fade-out, no ending; each phrase flows straight into the next.
```

| 曲名（Suno） | テンポ・ノリ | メロディの説明（要点） | song id |
|---|---|---|---|
| Quiz Online 01 Sky Patrol | 132、力強い8分 | 長くのばす音と5度の跳躍で舞い上がる旋律。下でローターのような16分の分散和音（海の上を高く飛ぶ） | `9bfdd76b-dec1-435d-99c6-9a7ea702f4ce`、`9c0961fe-e050-4794-87a2-f64c9dcabceb` |
| Quiz Online 02 Rival Radar | 124、弾む8分 | 短いスタッカートの「ピッピッ」が自分に答える、レーダーで相手を探すような旋律 | `7b61a97b-affa-470a-8026-5c6592f0117e`、`38ffefa3-35ff-438a-8c3d-3c891d97c286` |
| Quiz Online 03 Versus Lobby | 140、力強い8分 | 「だれと戦う？」という自信のあるスポーティな旋律。シンコペーションと、フレーズの終わりの駆け上がり（明るい格闘ゲームのキャラ選択画面） | `ea0e2ea5-5f00-4364-8fc6-2acd05497380`、`29471b78-03a2-443b-9696-5fe503407fba` |
| Quiz Online 04 Sea Breeze Flight | 120、跳ねるシャッフル | 口笛のようにのんきな旋律が、転がる分散和音の上をすべる（晴れた海の上の飛行） | `2cbc53b8-f4ad-4f92-927e-f4a49f8c5c0a`、`0fca5247-8394-4df1-a93d-f120e3c22cde` |
| Quiz Online 05 Takeoff March | 138、2/4の行進 | 付点のリズムとラッパの合図のような弱起。ヘリのパイロットたちが出発する行進曲 | `f17bfc0e-a92f-4275-8aaa-edc7a78cbdd5`、`87260afb-7410-4f3a-b8ae-3a30cf363f36` |
| Quiz Online 06 Waiting Room Groove | 112、ゆったりしたファンク | 裏拍のアクセントと短いスライドの、少しおどけたクールな旋律（試合を待つあいだ） | `94e3bfe5-42c5-4f7d-ad50-d85f7b02b007`、`6522e5ed-0d3b-4d7a-9c0f-58162c0c3ef2` |
| Quiz Online 07 Match Hype | 150、速い8分。ベースはオクターブで弾む | 短い反復で上へ進み続ける、「もうすぐ試合！」のわくわく感 | `248adff4-1df0-4624-90ce-f971c9d48c67`、`4a6b27f9-e946-437a-8c90-8d39875298f7` |
| Quiz Online 08 Cloud Hopper | 128、軽く弾む8分 | 高い音と低い音を跳び移る、雲から雲へ跳ねるような旋律。速い装飾音 | `69f03fec-d131-4026-8d57-60653a6f1fec`、`3be3332f-f742-420e-9029-c5a43887be1b` |

- 長さはどれも約2分29〜31秒。
- 05は最初、メロディの説明に `aviators'` と書いたところ、Sunoがアーティスト名とみなして生成を断った。`pilots'` に変えて作り直した。

#### ゆっくりでシンプルな待機曲（2026年10月12日生成）

上の8種類を聴いたユーザーの要望（「オンライン対戦メニュー画面にも使いたいので、もっとゆっくりで音の数も少なめでシンプルな待機曲」）で作り直した候補。設定は上と同じ（「Quiz Online 02 Rival Radar」の「プロンプトを再利用」で埋め、長さ2:30・奇抜さ35%・スタイルの影響70%に合わせ直した）。

- **Styles**：音色の文を「主旋律1本＋やわらかい和音＋穏やかなベース＋軽いドラム」に変え、テンポを88〜108 BPMにした。

```
Early 8-bit video game soundtrack, a simple square-wave lead over soft square-wave chords, a gentle triangle-wave bass and light noise-channel drums; instrumental, <ノリ> at <BPM> BPM, dry clean mix with open space. Melody: <メロディの説明> Waiting-room menu loop for a cheerful kids' 3D quiz party game: the online versus menu at a seaside heliport, where players pick settings and wait for an online rival. Calm, simple and friendly; bright, never dark or sad. Sparse, minimal arrangement with few notes and plenty of space. Same tempo and even energy from start to finish: no build-up, no risers, no breakdowns, no big climax, no fade-out, no ending; each phrase flows straight into the next.
```

| 曲名（Suno） | テンポ・ノリ | メロディの説明（要点） | song id |
|---|---|---|---|
| Quiz Online Wait 01 Heliport Lounge | 92、くつろいだ8分 | 長い音が隣の音へ進む、親しみやすい旋律。フレーズの間に休み（静かなヘリポートのラウンジ） | `e9de950c-c8cd-405f-afd1-29295be19d7a`、`4d957159-a045-4104-bf39-029d454b6f2b` |
| Quiz Online Wait 02 Easy Shuffle | 96、のんびりしたシャッフル | 数音だけの口ずさめる短いフレーズを、休みを多くはさんで少しずつ変えながら繰り返す | `77af9418-0a34-449b-b9f7-138e7ff02626`、`880defd7-00c4-48f4-b2b7-bcf75f09580c` |
| Quiz Online Wait 03 Seaside Bossa | 100、やわらかいボサノバ | 少しのシンコペーションと長い間の、なめらかでまばらな旋律（海辺のカフェ） | `920fa21f-9c09-424b-8b74-85304f7b42cc`、`89b53057-e624-4db7-9c94-661f246c5cb5` |
| Quiz Online Wait 04 Blue Sky Idle | 88、ゆっくりした4分の拍 | 長くのばす音と、ゆっくりした分散和音（青空を流れる雲） | `babe3487-fc3a-4300-983a-9ed0f492b433`、`6fc37409-a625-4dd8-8b3d-88c61b373bfb` |
| Quiz Online Wait 05 Tick Tock | 100、軽い8分 | 時計の「チクタク」のような数音のスタッカートに、やわらかい長い音が答える | `d49d6b37-0a66-4632-a29a-52b8eb53fbc3`、`7782cdbf-08cc-435e-bc7f-8706b5fa90f4` |
| Quiz Online Wait 06 Sunny Stroll | 104、歩く速さ | 小さな歩幅と短い休みの、明るい散歩の旋律 | `cc0c1f4d-1806-4676-8164-aabe94714b17`、`b584cd05-625e-42cc-93a3-807d28974c54` |
| Quiz Online Wait 07 Sea Breeze Waltz | 108、3/4のワルツ | 1小節に数音だけの、ゆれるワルツ（小舟をゆらす海風） | `b38609cc-6696-4c18-9d65-d935078bbd1a`、`309b4253-4903-462a-bc76-eec2db37a779` |
| Quiz Online Wait 08 Menu Chill | 90、ゆったりしたグルーヴ | 2小節の短いモチーフを少しずつ変えて繰り返す。長く聴いても疲れない | `8b60d976-8f83-4b76-9e86-a7ba930bd30c`、`2436c8d3-306c-471f-958c-9307caf9e064` |

- 長さはどれも約2分29〜32秒。

### 採用した曲

#### `quiz_party_loop.ogg`（2026年10月8日採用、10月9日に延長版へ差し替え）

テーマ曲の参考音源をCoverした曲。プレイ中以外の全場面でこの曲を流している。最初は66秒（32小節）のループだったが、ずっと聴いていると飽きるので、10月9日にSunoのExtend（延長）で続きを作り、134秒（65小節）のループに伸ばした。

| 項目 | 内容 |
|---|---|
| 生成元 | Suno「Quiz Party Loop」（ユーザー katsuyu2354）。元の曲は 2026-10-08T14:47:07Z、id `efe7efd1-dde8-44a5-9348-25bf92c801e6`。延長版の全曲は 2026-10-09T12:14:18Z、id `00fb9656-0cda-4678-a939-9e50d441dbee`（元の曲の0〜82.6秒＋延長部分 id `61f22aaa-5c53-4414-92d2-6a592674c6ea`） |
| 延長の設定 | 82.6秒（40小節目の頭）から延長、長さ3:00、モデル v6。スタイルは元の曲の文面のテンポを実際の116 BPMに直し、「seamless loop」を「変奏・軽いブレイクダウン・Bセクションを入れて終わらせない」に替えた。歌詞欄はセクション指定（`[Instrumental]` `[Variation]` `[Breakdown]` `[B Section]` `[Main Theme]`）だけ。長さを自動のままにすると、延長部分が17秒で曲が終わってしまった |
| 元ファイル | `assets/audio/bgm/source/quiz_party_loop_extended_original.mp3`（延長版の全曲、261.2秒、48kHzステレオ、−15.6 LUFS）。0〜82.6秒は `quiz_party_loop_original.mp3`（99.6秒）とサンプル単位で一致する |
| テンポ・キー | 約116.1 BPM（区間ごとに115.9〜116.2）、4/4、ハ長調（C） |
| 構成 | 0.065秒を0小節目とした約126小節。40〜79小節目が延長で増えた部分で、40〜47小節目は冒頭の変奏、48〜63小節目は前半の流れの再現、64〜79小節目は新しい展開。72小節目は1小節の「溜め」で、73小節目でテーマに戻る。80小節目以降はブレイクを挟んで、3.5kHz以上の高音が10〜25dB落ちた暗い音色に変わる |
| ループ区間 | 8〜73小節目の65小節（元ファイルの16.548〜150.898秒）。73小節目はテーマの頭で8小節目とよく似ているので、ここで8小節目に戻す。80小節目以降を含めると、戻り目で音色が急に明るく変わるので使わなかった |
| 納品ファイル | `assets/audio/bgm/quiz_party_loop.ogg`（134.350秒、6,448,799サンプル、48kHzステレオ、Ogg Vorbis 品質6、−16.0 LUFS、ピーク −4.3 dBFS） |
| インポート設定 | `loop=true`、`loop_offset=0`、`bpm=116.1`、`beat_count=260`、`bar_beats=4`。`beat_count` と `bpm` から求まる長さ（6,449,612サンプル）はファイルより少し長いので、ファイルの終わりで頭に戻る |

- **戻り位置の選び方**：小節ごとの和音（拍ごとのクロマ）、拍の打ち方、帯域ごとの音色、音量を、つなぎ目の前後4小節で比べて選んだ。73小節目への戻りは、音色の差が以前のループのつなぎ目（40小節目→8小節目）とほぼ同じ。
- **つなぎ目の処理**：Sunoの曲は同じフレーズでも波形が毎回少し違うので、そのままでは切れ目で音が飛ぶ。ループの頭の30ミリ秒を、「73小節目の頭（終わりから自然に続く音）」から「8小節目の頭」へ徐々に入れ替えた（等パワーのクロスフェード）。区切りは小節の頭の40ミリ秒前に置き、拍の頭の音にかからないようにした。
  - 73小節目の頭の位置は、前後32拍の打点に直線を当てはめる方法と、8小節目との打点の相互相関の2通りで求め、平均した（差は2.4ミリ秒）。開始点は以前のループと同じサンプル（794,315）。
  - つなぎ目の段差は、隣り合うサンプル同士の通常の変化（99.9パーセンタイル）の約1/16。
  - Godotで終わりの2秒前から再生して、ファイルの終わりで頭に戻り再生が続くことを確かめた。
- **48kHzのまま納品した理由**：後処理の基準は44.1kHzだが、ループ音源を変換すると両端に余計な揺れが出て、つなぎ目が乱れることがある。Godotは48kHzをそのまま再生できる。
- **商用利用の権利**：生成したときのSunoのプランを `assets/audio/bgm/LICENSE.md` に記入する。

#### `quiz_play_loop.ogg`（2026年10月11日採用、プレイ中の曲）

メニュー曲と同じ音色で、運動会のような速い2拍子のメロディにした新しい曲（「メニュー曲の音色で作った新しいメロディ」の節）。壁が割れてプレイが始まる瞬間に、曲の頭から流す。

| 項目 | 内容 |
|---|---|
| 生成元 | Suno「Quiz Chip Sports 03 Clown Galop」（ユーザー katsuyu2354）、2026-10-11T13:37:16Z、id `c723f094-ec06-496a-a902-e72e4afe4b71` |
| 元ファイル | `assets/audio/bgm/source/quiz_play_loop_original.mp3`（149.7秒、48kHzステレオ） |
| テンポ・キー | 約175.3 BPM（指示は172）、2拍子。0〜113秒ごろはト長調（G）、115秒あたりからイ長調（A）に転調して最後まで戻らない |
| 構成 | 4拍を1単位とすると、8単位（32拍）のフレーズが続く。10〜23単位目（13.8〜32秒）と、232拍後の68〜81単位目（93〜111秒）で、和音と拍の打ち方がよく一致する |
| ループ区間 | 初回はファイルの頭から流し、2周目からは13.811秒（10単位目の頭の40ミリ秒前）に戻る。戻り目は93.209秒（68単位目の頭の40ミリ秒前）で、ループは79.398秒（232拍）。転調した後の部分は使わなかった |
| 納品ファイル | `assets/audio/bgm/quiz_play_loop.ogg`（93.209秒、4,474,032サンプル、48kHzステレオ、Ogg Vorbis 品質6、−16.1 LUFS、ピーク −5.0 dBFS） |
| インポート設定 | `loop=true`、`loop_offset=13.811`、`bpm=175.32`、`beat_count=0`、`bar_beats=2`。`beat_count` を0にして、ファイルの終わりで `loop_offset` に戻す |

- **戻り位置の選び方**：4拍ごとの和音（拍ごとのクロマ）、拍の打ち方（1ミリ秒単位の打点の相互相関）、帯域ごとの音色、音量を、232拍離れた2か所で比べた。10単位目は和音0.80、打点0.87、音量差+0.5 dBでよく一致し、フレーズの頭でもある。18単位目より後は音色の差が大きくなる。
- **つなぎ目の処理**：メニュー曲と違い、ファイルの頭は初回のために残すので、ファイルの終わりの30ミリ秒を「戻り目から自然に続く音」から「戻り先（13.811秒）の直前の音」へ徐々に入れ替えた（等パワーのクロスフェード）。戻った先は元の曲のままつながる。
  - 戻り目の位置は、10単位目の頭（13.851秒）から232拍後の打点を、前後の4つの区間で相互相関をとって求めた（93.249秒、区間による差は5ミリ秒以内）。
  - つなぎ目の段差（0.0040）は、元の曲でその位置が自然につながっているときの段差（0.0040）と同じ。
  - Godotのデコーダで、ファイルの終わりの1秒前から再生して戻り目をまたぎ、13.811秒から直接再生した音と比べた（`tests/bgm_loop_seam_check.gd`）。戻った後の音は相関0.998で一致し、ずれは再生レート（44.1kHz）への変換による1フレーム（23マイクロ秒）だけ。メニュー曲も同じ結果。
- **頭の処理**：最初のサンプルが無音ではないので、3ミリ秒のフェードインを付けた。

#### `quiz_result_loop.ogg`（2026年10月12日採用、結果画面の曲）

メニュー曲と同じ音色の、軽いパレード風の曲（「`bgm_result` の候補」の節）。1人用のクリア画面（CLEAR）と、2人用のスコアタワー演出（RESULT_CEREMONY、演出の頭から）で、曲の頭から流す。

| 項目 | 内容 |
|---|---|
| 生成元 | Suno「Quiz Result 03 Parade」（ユーザー katsuyu2354）、2026-10-12T09:32:54Z、id `319f8136-24f1-401b-9157-027df0e2bfba` |
| 元ファイル | `assets/audio/bgm/source/quiz_result_loop_original.mp3`（149.6秒、48kHzステレオ） |
| テンポ・キー | 120.0 BPM、4/4。ハ長調が中心で、39〜45小節目（78〜92秒）あたりで一時的に変ホ長調・変イ長調方面へ寄ってから戻る |
| 構成 | 1小節（2秒）単位で、6〜26小節目と、46小節後の52〜72小節目がほぼ同じ（和音の一致0.93〜0.98） |
| ループ区間 | 初回はファイルの頭から流し、2周目からは12.202秒（6小節目の頭の40ミリ秒前）に戻る。戻り目は104.191秒（52小節目の頭の40ミリ秒前）で、ループは91.989秒（184拍） |
| 納品ファイル | `assets/audio/bgm/quiz_result_loop.ogg`（104.191秒、5,001,168サンプル、48kHzステレオ、Ogg Vorbis 品質6、−16.1 LUFS、ピーク −4.1 dBFS） |
| インポート設定 | `loop=true`、`loop_offset=12.202`、`bpm=120.0`、`beat_count=0`、`bar_beats=4` |

- **戻り位置の選び方**：プレイ曲と同じ。46小節離れた2か所は、打点のずれが約10ミリ秒で一定、帯域ごとの音色の差も小さく、全体でよく一致した。6小節目はハ長調の和音で始まる区切りで、和音0.93、打点0.85、音色の差2.0。
- **つなぎ目の処理**：プレイ曲と同じく、ファイルの終わりの30ミリ秒を戻り先の直前の音へクロスフェードした。つなぎ目の段差（0.0134）は、元の曲でその位置が自然につながっているときの段差（0.0135）と同じ。Godotのデコーダでの確認（`tests/bgm_loop_seam_check.gd`）も、戻った後の音は相関0.997で一致。
- **頭の処理**：最初のサンプルが無音ではないので、3ミリ秒のフェードインを付けた。

#### `quiz_match_loop.ogg`（2026年10月12日採用、オンライン対戦のマッチング待機の曲）

オンライン対戦で、相手が決まるのを待っているあいだ（演出の「検索中」。`OnlineStagingDirector` の `CRUISE`）に流す曲。ユーザーが用意した Suno の曲を、そのまま使った。

| 項目 | 内容 |
|---|---|
| 生成元 | Suno「Syncopated Groove」（ユーザー katsuyu2354）、2026-10-12T13:38:44Z、id `d0298999-0745-4bf8-8c22-2d8d929c384f` |
| 元ファイル | `assets/audio/bgm/source/quiz_match_original.mp3`（176.4秒、48kHzステレオ、−15.6 LUFS、ピーク −2.8 dBFS） |
| テンポ | 116.54 BPM（1拍 0.51484秒）、全体を通してほぼ安定（30秒ごとの拍の位置のずれは、最初の30秒が 32 ミリ秒、それ以降は 10 ミリ秒以内）。音量は最初から終わりの 4 秒前まで −16 dB 前後でほぼ一定 |
| 構成 | 180拍（約92.7秒）で同じ流れに戻る。拍ごとの和音・帯域ごとの音色・打点の一致が最も高く、音量差は 0.0 dB |
| ループ区間 | 初回はファイルの頭から流し、2周目からは63.587秒に戻る。戻り目は156.267秒で、ループは92.679秒（180拍） |
| 納品ファイル | `assets/audio/bgm/quiz_match_loop.ogg`（156.266秒、48kHzステレオ、Ogg Vorbis 品質6、−16.1 LUFS、ピーク −3.4 dBFS） |
| インポート設定 | `loop=true`、`loop_offset=63.587`、`bpm=116.54`、`beat_count=0`、`bar_beats=4` |

- **戻り位置の選び方**：拍を足場に、つなぎ目の前 16 拍（4 小節）の和音・音色・打点を、戻り目と戻り先で比べて選んだ（和音の一致 0.94、音色の差 0.23、打点の相関 0.66）。曲の終わりの約 4 秒（フェードアウト）は使わない。
- **つなぎ目の処理**：拍の頭の 40 ミリ秒前に区切りを置き、ファイルの終わりの 30 ミリ秒を戻り先の直前の音へ等パワーでクロスフェードした。戻り目の位置は、前 0.8 秒の音量の変化の相関で ±30 ミリ秒の範囲を探して +7.7 ミリ秒合わせた。つなぎ目の段差（0.0210）は、元の曲でその位置が自然につながっているときの段差（0.0210）と同じ。
- **確認**：`tests/bgm_loop_seam_check.gd` で、Godot のデコーダで戻った後の音が戻り先から直接再生した音と相関 0.991 で一致し、つなぎ目の段差は 0.0174（通常のサンプル間の変化の 99.9 パーセンタイルは 0.146）。
- **頭の処理**：最初のサンプルが無音ではないので、3ミリ秒のフェードインを付けた。
- **流れる場面**：ヘリポートのトップとスキン設定などはメニュー曲のまま。乗り込みが始まると、メニュー曲を止めずに音量だけ −16 dB まで下げ（0.6秒。通常は −4 dB）、離陸・急発進して暗転しきるまではヘリの効果音を聞かせる。暗転が明けて「検索中」に入ったら、この曲にクロスフェードして音量を通常に戻し、検索を探し直すときも流れ続ける。やめる・失敗・時間切れでヘリポートに戻ると、メニュー曲が通常の音量に戻る。相手が決まった後は合流・VS カットイン・読み込みまでこの曲のまま続き、ゲーム画面に入ると 0.8 秒で消える（今まで通り）。乗り込みの途中で相手が決まったときは検索中を通らないので、下げた音量のメニュー曲のままゲームへ進む。

## 共通スタイル（全プロンプトの末尾に付ける）

全曲で同じ「音の世界」にそろえるための共通文。

```
Style anchor: late-1990s 3D console party-game soundtrack, bright comedic TV quiz-show energy for kids, sunny Mediterranean harbor-town flavor. Acoustic/orchestral instruments: brass section, pizzicato strings, clarinet, piccolo, marimba, xylophone, glockenspiel, accordion, mandolin, acoustic guitar, upright bass, live drums, hand claps. Punchy, clean mix with the mid-range left open for sound effects. Instrumental only: no vocals, no choir, no chants, no spoken words.
```

文字数制限が厳しいときは短縮版を使う。

```
Late-90s console party game, comedic kids TV quiz show, sunny Mediterranean harbor. Brass, pizzicato strings, clarinet, marimba, accordion, mandolin, live drums. Instrumental, no vocals.
```

- **8bit（チップチューン）にしない理由**：見た目がPSX風の3Dなので、当時のゲームのようなサンプリングした生楽器の音でそろえる。
- **アーティスト名や既存曲名を書かない理由**：生成AIに拒否されることがあり、元曲に近づきすぎる危険もあるため。`bgm_goal` は「天国と地獄」系の曲調を、曲名を出さずに描写で指定している。

## プロンプト

各プロンプトの末尾に、上の共通スタイルを付けて使う。

### `bgm_menu` — タイトル／メニュー

狙い：港町の明るさとゲームの顔になるメロディ。このメロディをほかの曲にも流用できると統一感が出る（後述）。

```
Main menu theme, 92 BPM, F major, 4/4. Cheerful, inviting and catchy; makes kids want to press Start. Mandolin and acoustic guitar strumming, accordion counter-melody, light brass stabs, marimba, bouncy upright bass, relaxed drums with claps. A memorable 8-bar main melody that can become the game's signature motif. Steady energy throughout, no big build-ups, no fade-out.
```

### `bgm_menu` のジャンル違い（92 BPM、シンセなし）

メニュー曲を、ゆっくりめのテンポとシンセを使わない編成で作って聴き比べるためのプロンプト。テンポは92 BPM、キーはF。4/4拍子なら16小節で約41.7秒のループになる。ワルツ（#4）だけは3/4拍子で、16小節で約31.3秒。

上の「共通スタイル」は付けない。代わりに、次の共通文を末尾に付ける。禁止しているのはシンセサイザーだけで、打ち込みドラムやエレキギター・エレキベースは使ってよい。

```
Main menu theme for a kids' 3D quiz party game set in a sunny Mediterranean harbor town. Warm, cheerful and inviting; relaxed but not sleepy, with a simple, memorable melody. No synthesizers of any kind: no synth pads, no synth leads, no synth bass, no arpeggiators. Instrumental only: no vocals, no choir, no humming, no spoken words. Steady tempo, no big build-ups, no fade-out, no ending.
```

| # | ジャンル | プロンプト |
|---|---|---|
| 1 | 地中海アコースティック（基準） | `92 BPM, F major, 4/4. Mediterranean acoustic café band: mandolin melody, nylon-string guitar strumming, accordion counter-melody, upright bass, cajón and tambourine.` |
| 2 | ボサノバ | `92 BPM, F major, 4/4. Breezy bossa nova: nylon-string guitar comping, flute melody, soft acoustic piano, upright bass, brushed snare and shaker.` |
| 3 | ジプシージャズ | `92 BPM, F major, 4/4, relaxed swing. Gypsy jazz (jazz manouche): acoustic rhythm guitar "la pompe", violin and clarinet sharing the melody, upright bass.` |
| 4 | フレンチ・ミュゼット（ワルツ） | `92 BPM, F major, 3/4 waltz. French musette: accordion melody, acoustic guitar and upright bass oom-pah-pah, light glockenspiel, seaside promenade feel.` |
| 5 | ナポリのセレナーデ | `92 BPM, F major, 4/4. Neapolitan seaside serenade: tremolo mandolins, classical guitar, pizzicato strings, accordion, a light frame drum.` |
| 6 | ギリシャ民謡（ゆったり） | `92 BPM, F major, 4/4. Gentle Greek island folk (slow hasapiko feel): bouzouki melody, baglama, acoustic guitar, accordion, upright bass, soft hand percussion. No accelerando.` |
| 7 | カリプソ | `92 BPM, F major, 4/4. Laid-back calypso: steel pan melody, acoustic guitar skank, upright bass, congas, shaker and claves.` |
| 8 | ウクレレ・ハワイアン | `92 BPM, F major, 4/4. Sunny ukulele tune: ukulele strumming and picked melody, glockenspiel, acoustic bass, hand claps and light cajón.` |
| 9 | ケルト／アイリッシュ | `92 BPM, F major, 4/4. Cheerful Celtic folk: tin whistle and fiddle melody, acoustic guitar, bouzouki, bodhrán, upright bass.` |
| 10 | ラグタイム・ピアノ | `92 BPM, F major, 4/4. Easygoing ragtime: honky-tonk acoustic piano with stride left hand, clarinet and muted trumpet answering phrases, upright bass, brushed snare.` |
| 11 | 室内楽（絵本の映画音楽風） | `92 BPM, F major, 4/4. Whimsical European chamber ensemble like a storybook film score: oboe and clarinet melody, pizzicato and legato strings, harp, celesta, light timpani.` |
| 12 | アコースティック・フォーク | `92 BPM, F major, 4/4. Bright indie folk: acoustic guitars, ukulele, banjo, glockenspiel, upright bass, hand claps and stomps.` |
| 13 | ニューオーリンズ・ブラス | `92 BPM, F major, 4/4. Easy second-line New Orleans brass band: trumpet and trombone melody, clarinet fills, sousaphone bass, snare and bass drum groove.` |
| 14 | シティポップ | `92 BPM, F major, 4/4. Sunny 1980s Japanese city pop instrumental: clean electric guitar cutting, slap electric bass, electric piano, brass section hits, tight programmed drums.` |
| 15 | ローファイ・ヒップホップ | `92 BPM, F major, 4/4. Warm lo-fi hip-hop: dusty programmed boom-bap drums, mellow electric piano chords, nylon-string guitar melody, round electric bass, soft vinyl texture.` |
| 16 | レゲエ | `92 BPM, F major, 4/4. Sunny seaside reggae: off-beat electric guitar skank, deep electric bass, organ bubble, melodica melody, one-drop drums, light percussion.` |
| 17 | ギターポップ／ネオアコ | `92 BPM, F major, 4/4. Jangly guitar pop: chiming clean electric guitars, acoustic guitar strumming, melodic electric bass, glockenspiel, live drums with tambourine.` |
| 18 | ソフトなファンク | `92 BPM, F major, 4/4. Light, friendly funk: wah and muted electric guitar, punchy electric bass, clavinet, horn section riffs, crisp programmed drums.` |

- **#13のトロンボーン**：結果演出の「残念トロンボーン」と同じ楽器だが、メニューと結果演出は同時に鳴らないので問題ない。
- **シンセっぽい音が混ざったテイク**：生成AIは禁止しても薄いパッドを足すことがあるので、そういうテイクは捨てる。
- **エレピ・オルガン・クラビネット**（#14〜#18）：鍵盤楽器であってシンセサイザーではないので使っている。これも避けたい場合は、各プロンプトから外す。

### `bgm_menu` の世界観版（92 BPM、シンセなし）

上の「ジャンル違い」を、ゲームの世界観に寄せたもの。こちらを優先する。世界観を次の4つの要素に分けて、各プロンプトに混ぜている。

| 世界観 | 音での表し方 |
|---|---|
| エーゲ海の白い港町（青いドーム、観覧車、海辺のスタジアム） | ブズーキ、マンドリン、アコーディオン、クラリネット |
| 子ども向けクイズ番組「AIQUIZ」 | 時計のように刻むウッドブロック、フレーズの終わりの金管「ジャン！」、正解チャイムのような鉄琴 |
| 小学生の学び | リコーダー、鍵盤ハーモニカ、木琴 |
| ブロックマンのドタバタ・PS1時代のパーティゲーム | ファゴットやチューバのとぼけた低音、90年代ゲーム機のサンプリングした音色 |

共通文（末尾に付ける）：

```
Main menu theme for "AIQUIZ", a kids' TV quiz variety show filmed in a whitewashed Greek island harbor town with blue domes, a seaside Ferris wheel and a stadium by the sea. The players are clumsy blocky characters in a slapstick late-1990s console party game. Warm, sunny, cheerful and a little goofy; relaxed but not sleepy, with a simple melody kids can hum. No synthesizers of any kind: no synth pads, no synth leads, no synth bass, no arpeggiators. Instrumental only: no vocals, no choir, no humming, no spoken words, no sound effects. Steady tempo, no big build-ups, no fade-out, no ending.
```

| # | 曲のイメージ | プロンプト |
|---|---|---|
| 1 | 番組のテーマ曲・港町版（本命） | `92 BPM, F major, 4/4. The quiz show's signature theme played by a Greek harbor band: bouzouki and mandolin carrying the main melody, accordion counter-melody, a woodblock ticking like a quiz clock, short brass "ta-da" stabs at phrase endings, upright bass, light drums.` |
| 2 | 収録前の港 | `92 BPM, F major, 4/4. Relaxed pre-show moment at the harbor before the cameras roll: strummed nylon guitar and mandolin, gentle accordion melody, soft hand claps on 2 and 4, upright bass, brushed snare, a glockenspiel "ding" like a correct-answer chime now and then.` |
| 3 | エーゲ海の朝市 | `92 BPM, F major, 4/4. Bustling but easygoing Greek island morning market: bouzouki riffs, clarinet melody, tambourine and frame drum, acoustic guitar, upright bass, playful xylophone answers. No accelerando.` |
| 4 | 白い家と青いドーム | `92 BPM, F major, 4/4. Bright sea-breeze theme over white houses and blue domes: flute and mandolin melody, warm legato strings, nylon guitar arpeggios, harp glissandi, upright bass, light percussion. Open and sunny.` |
| 5 | 海辺の観覧車（ワルツ） | `92 BPM, F major, 3/4 waltz. A seaside Ferris wheel and boardwalk fair: accordion and barrel-organ style melody, bouzouki strumming, glockenspiel sparkles, oom-pah-pah tuba and guitar, triangle.` |
| 6 | 小学校のクイズ大会 | `92 BPM, F major, 4/4. Cheerful elementary-school quiz contest by the sea: soprano recorder and melodica melody, xylophone, mandolin, toy piano, pizzicato strings, school snare drum, a ticking woodblock. Innocent and fun.` |
| 7 | ブロックマンの行進 | `92 BPM, F major, 4/4. Clumsy blocky characters waddling along the quay: plodding bassoon and tuba melody, bouncy pizzicato strings, bouzouki chops, slide-whistle and kazoo-like comic accents, woodblock and temple blocks. Goofy slapstick, not silly-loud.` |
| 8 | PS1パーティゲームのメニュー | `92 BPM, F major, 4/4. Late-1990s console party-game menu made with sampled acoustic instruments, not synthesizers: sampled brass stabs, marimba, bouzouki melody, slap electric bass, punchy programmed breakbeat drums, orchestra hits used sparingly.` |
| 9 | 地中海シティポップ | `92 BPM, F major, 4/4. Sunny city pop with a Greek island twist: clean electric guitar cutting, slap electric bass, electric piano, bouzouki and mandolin melody, brass section hits, tight programmed drums.` |
| 10 | 港のブラスバンド | `92 BPM, F major, 4/4. A seaside promenade brass band opening the TV show: trumpet and clarinet melody, sousaphone bass, bouzouki rhythm, snare and bass drum, cheerful brass "ta-da" endings on each phrase.` |
| 11 | ギリシャ×ロックステディ | `92 BPM, F major, 4/4. Laid-back rocksteady with a Greek island flavor: off-beat electric guitar skank, round electric bass, bouzouki melody, melodica answers, one-drop drums, shaker.` |
| 12 | シンキングタイム風 | `92 BPM, F major, 4/4. A cheerful "thinking time" groove from the quiz show: pizzicato strings and woodblock ticking like a clock, nylon guitar, playful clarinet question-and-answer phrases, mandolin, glockenspiel "ding" accents, upright bass.` |

- **`no sound effects` の理由**：「港」「市場」と書くと、生成AIがカモメや波の音を混ぜることがあるため。環境音はゲーム側で鳴らす。
- **文字数**：共通文とプロンプトを合わせて900字前後。入らない場合は、共通文の2文目（blocky characters…）を削る。

### `bgm_menu` のシンプル版（オー・シャンゼリゼのような曲調）

「オー・シャンゼリゼ」のような、シンプルで口ずさめる散歩風の曲を目指す版。現在はこれが第一候補。

曲名やアーティスト名はプロンプトに入れない。生成AIに拒否されることがあり、メロディが元曲に似すぎると著作権の問題になるため。代わりに、次の特徴を言葉で指定する。

- 短く覚えやすいメロディを1つだけ作り、少しずつ変えて繰り返す。音の動きは隣の音へ移るのが中心
- コードは基本の3〜4つだけ
- ベースは2拍で弾む（根音と5度）
- アコースティックギターを毎拍刻み、スネアは2拍目と4拍目に軽く入れる
- 楽器が少なく隙間が多い

共通文（末尾に付ける）：

```
Main menu theme for "AIQUIZ", a kids' TV quiz show filmed in a whitewashed Greek island harbor town. A simple, sunny, sing-along strolling tune in the spirit of a classic 1960s European pop song: one short, catchy, stepwise major-key melody repeated with small variations, only three or four basic chords, bouncy two-beat root-and-fifth bass, steady strummed acoustic guitar, light snare on 2 and 4. Few instruments and lots of space; easy to hum after one listen. No synthesizers. Instrumental only: no vocals, no choir, no humming, no spoken words, no sound effects. Steady tempo, no build-ups, no key changes, no fade-out, no ending.
```

各プロンプトでは、主にメロディを弾く楽器を変えている。

| # | 主にメロディを弾く楽器 | プロンプト |
|---|---|---|
| 1 | アコーディオン | `92 BPM, F major, 4/4. Accordion plays the melody; acoustic guitar strum, upright bass, brushed snare.` |
| 2 | ブズーキ（港町版） | `92 BPM, F major, 4/4. Bouzouki plays the melody, answered by accordion at phrase ends; acoustic guitar strum, upright bass, light tambourine.` |
| 3 | マンドリン | `92 BPM, F major, 4/4. Tremolo mandolin plays the melody, doubled by flute in the second half; nylon guitar strum, upright bass, brushed snare.` |
| 4 | 鍵盤ハーモニカとリコーダー（小学校版） | `92 BPM, F major, 4/4. Melodica plays the melody, soprano recorder joins on the repeat; acoustic guitar strum, upright bass, xylophone accents, school snare drum.` |
| 5 | ブラスバンド | `92 BPM, F major, 4/4. Trumpet plays the melody, clarinet harmony on the repeat; tuba oom-pah bass, snare and bass drum, banjo strum.` |
| 6 | ウクレレと鉄琴 | `92 BPM, F major, 4/4. Glockenspiel and ukulele play the melody together; ukulele strum, acoustic bass, hand claps on 2 and 4.` |
| 7 | ピアノとクラリネット | `92 BPM, F major, 4/4. Clarinet plays the melody over bouncy acoustic piano chords; upright bass, brushed snare, a glockenspiel "ding" at the end of each phrase.` |
| 8 | 90年代ゲーム機風 | `92 BPM, F major, 4/4. Late-1990s console game version with sampled instruments: sampled accordion and marimba play the melody, slap electric bass, simple programmed drums, sampled acoustic guitar strum.` |

- **テンポ**：のんびり散歩する感じを強めたいときは `100 BPM` も試す。
- **似すぎの確認**：メロディが元曲そのものに聞こえるテイクは使わない。雰囲気が近いのはよいが、メロディが同じなのは不可。
- **シンプルさ**：生成AIは2周目以降に楽器を足しがちなので、最後まで楽器の少ないテイクを選ぶ。

### `bgm_intro` — ヘリ降下〜問題生成〜空撮

狙い：問題を作っている間（長さが毎回変わる）も、待たされている感じがしないようにする。

```
Pre-game anticipation loop, 120 BPM, F major, 4/4. "Something big is about to start" feeling, like a TV game show right before the first round. Pulsing staccato strings and timpani on the beat, snare rolls, brass swells, ticking woodblock, playful xylophone runs. Stays on a suspended, unresolved feeling so it can loop while waiting. Medium intensity, no melody climax, no ending.
```

### `sting_countdown` — 4・3・2・1・GO

狙い：1秒おきの「4・3・2・1」に音を合わせ、壁が割れる瞬間に「GO」の一撃を鳴らす。

```
Short countdown sting, exactly 120 BPM, 4/4, about 5.5 seconds total. Four big orchestral hits exactly one second apart, each louder and higher than the last, over a rising snare roll and brass crescendo. Then a huge "GO!" brass-and-cymbal hit on a B-flat major chord at exactly 4.0 seconds, followed by a short 1.5-second ring-out. No melody, no vocals.
```

### `bgm_tutorial` — チュートリアル

狙い：説明を読む邪魔をしない。チュートリアルの演出中はBGMを−6dB下げる既存処理（`set_tutorial_ducked`）があるので、密度は低めにする。

```
Tutorial practice loop, 104 BPM, F major, 4/4. Friendly, light and encouraging, like a playful training drill at a school sports day. Pizzicato strings, bouncy clarinet and bassoon melody, glockenspiel accents, soft marching snare, gentle tuba. Low density and rhythm-driven so on-screen instructions stay easy to read; sparse, simple melody. Even energy, no build-ups, no ending.
```

### `bgm_play` — 本編（クイズの壁を突破する）

```
Main gameplay loop, 150 BPM, B-flat major, 4/4. High-energy comedic obstacle-course music for a kids' TV quiz show: running through giant walls with answer doors. Driving live drums, galloping bass, punchy brass riffs, fast xylophone and piccolo runs, accordion chops, slide-whistle and cartoon accents used sparingly. Exciting and fun, never scary. Constant energy, no breakdowns, no ending.
```

### `bgm_play` のジャンル違い（150 BPM）

本編の曲を、いろいろなジャンルで作って聴き比べるためのプロンプト。テンポとキーは本編の仕様（150 BPM、B♭、4/4）と同じなので、どのジャンルを選んでもループ長（16小節で25.6秒）や、のこぎり追跡（Gm）への切り替えは変わらない。

このジャンル違いには上の「共通スタイル」を付けない。楽器の指定がジャンルとぶつかるため。代わりに、次のジャンルに依存しない共通文を末尾に付ける。

```
Main gameplay loop for a kids' 3D party game: players race through giant quiz walls with answer doors. Bright, comedic and exciting, never scary. Steady tempo throughout. Instrumental only: no vocals, no choir, no chants, no spoken words. Constant energy, no breakdowns, no fade-out, no ending. Clean, punchy mix with the mid-range left open for sound effects.
```

港町らしさを足したいときは、`Add a light Mediterranean touch with mandolin or accordion.` を追加する。

| # | ジャンル | プロンプト |
|---|---|---|
| 1 | コミカル・オーケストラ（基準） | `150 BPM, B-flat major, 4/4. Cartoon orchestral comedy: punchy brass riffs, fast xylophone and piccolo runs, pizzicato strings, galloping tuba bass, driving snare and timpani, occasional slide-whistle accents.` |
| 2 | スカ | `150 BPM, B-flat major, 4/4. Upbeat ska: off-beat skank guitar and organ chops, tight horn section (trumpet, trombone, tenor sax) playing a catchy unison riff, walking bass, energetic drums with rimshots.` |
| 3 | ギリシャの島の民族舞曲 | `150 BPM, B-flat major, 4/4. Lively Greek island folk dance: fast bouzouki and mandolin tremolo melody, accordion, clarinet runs, acoustic guitar strumming, hand claps, tambourine and festive drums. Sunny Mediterranean harbor festival. No accelerando.` |
| 4 | バルカン・ブラス | `150 BPM, B-flat major, 4/4. Balkan brass band party: blazing trumpets and flugelhorn trading fast ornamented phrases, oom-pah tuba, snare and big bass drum, clarinet flourishes. Wild, joyful wedding-band energy.` |
| 5 | マンボ／サルサ | `150 BPM, B-flat major, 4/4. Hot mambo and salsa: piano montuno, stabbing brass section, congas, timbales and cowbell, bouncy upright-bass tumbao, guiro. Playful and fiery.` |
| 6 | サーフロック | `150 BPM, B-flat major, 4/4. Surf rock: twangy reverb-drenched electric guitar playing a fast picked melody, driving surf drums with tom fills, rhythm guitar, bass, a little organ. Sunny beach-party energy.` |
| 7 | ビッグバンド・スウィング | `150 BPM, B-flat major, 4/4, swung eighths. Big-band swing like a classic TV game show: shout-chorus brass, saxophone section riffs, walking bass, ride cymbal with snare kicks, bright stride-piano fills.` |
| 8 | ブルーグラス | `150 BPM, B-flat major, 4/4. Fast bluegrass hoedown: rolling banjo, racing fiddle melody, flat-picked acoustic guitar, mandolin chops, upright bass, light brushed snare. Comedic country chase energy.` |
| 9 | サーカス・マーチ | `150 BPM, B-flat major, 4/4 with an oom-pah two-beat feel. Circus march for a slapstick race: brass band with tuba oom-pah, trumpet melody, chromatic trombone slides, piccolo trills, glockenspiel, crash cymbals and bass drum.` |
| 10 | ポップパンク | `150 BPM, B-flat major, 4/4. Bright pop-punk instrumental: crunchy power-chord guitars, a catchy lead-guitar melody, fast punchy drums, driving bass. Youthful sports-anime opening energy.` |
| 11 | エレクトロ・スウィング | `150 BPM, B-flat major, 4/4. Electro swing: swung brass and clarinet samples, upright bass, four-on-the-floor kick with crisp claps, vintage piano chops, playful filter sweeps.` |
| 12 | 渋谷系 | `150 BPM, B-flat major, 4/4. Shibuya-kei: sparkling, sophisticated pop with bright brass, flute and strings, jazzy chord changes, glockenspiel, bouncy bass and breezy drums. Stylish and cheerful like a 1990s Japanese TV variety show.` |
| 13 | 90年代ゲーム機風 | `150 BPM, B-flat major, 4/4. Late-1990s console game soundtrack made with sampled instruments: sampled brass stabs and orchestra hits, slap bass, bright synth-lead melody, punchy breakbeat drums, marimba accents. Not chiptune.` |

- **テイク数**：ジャンルごとに3〜4テイク生成して、良いものを残す。
- **ファイル名**：`bgm_play_<ジャンル>_<テイク番号>`（例：`bgm_play_ska_2.wav`）にしておくと、聴き比べのときに区別しやすい。
- **ギリシャ舞曲（#3）**：この系統は曲の途中でどんどん速くなりがちなので、`No accelerando` を入れてある。それでも速くなったテイクはループに使えない。
- **スウィング系（#7、#11）**：8分音符が跳ねるだけでテンポは150のままなので、ループ長は他のジャンルと同じ。

### `bgm_chase` — のこぎり追跡

狙い：`bgm_play` の平行調（Gm）にして、追跡が始まったときに自然に切り替える。焦りは出すが、怖くはしない。

```
Chase loop, 168 BPM, G minor, 4/4. Comedic panic: a giant row of spinning saw blades is chasing the players from behind. Urgent ostinato in staccato strings and low brass, frantic snare and toms, stabbing brass hits, frantic clarinet runs, a touch of cartoon slapstick so it stays funny for kids, not horror. Tension stays high and even throughout, no breakdowns, no ending.
```

### `bgm_goal` — ゴールまでの競争

狙い：運動会の定番クラシックのような「ギャロップ／カンカン」の熱さ。観客の歓声（`goal_stand`）を重ねるので、上の帯域を詰め込みすぎない。

```
Final sprint loop, 176 BPM, B-flat major, fast 2/4 galop feel. The players dash to the finish line in front of a cheering stadium crowd, like a school sports-day relay. 19th-century operetta galop / can-can style: full orchestra, brass fanfares, rapid strings, piccolo, cymbal crashes, bass drum on every beat. Triumphant, silly and breathless. Constant peak energy, no ending.
```

### `ceremony_build` — スコアタワーが伸びる

狙い：6.3秒の静寂で最高潮になるようにする。生成AIは秒単位で長さを合わせられないので、長めに作り、6.3秒にコード側で0.08秒のフェードで切る。最高潮の位置で切れるよう、末尾から4.3秒前の位置から2.0秒の時点で再生を始める。

```
Suspense build for a score reveal, about 8 seconds, free tempo. Continuous snare drumroll crescendo with a timpani roll, rising chromatic strings and a brass swell climbing steadily higher, holding an unresolved dominant F chord. Gets louder and more tense the whole time and never resolves: no final hit, no melody, no ending.
```

### `sting_verdict` — 判定

狙い：6.9秒にコードから鳴らす。7.4秒から負けた側の塔が沈み始めるので、ファンファーレは4秒以内で終わらせる。

```
Winner reveal sting, about 4 seconds, B-flat major. Starts instantly on a huge brass-and-cymbal hit with no lead-in, then a bright, slightly comedic winner's fanfare: trumpets, snare flourish, glockenspiel sparkle, ending on a big sustained B-flat major chord. No vocals.
```

### `bgm_result` — スコアタワーの後／クリア画面

```
Results screen loop, 112 BPM, F major, 4/4. Relaxed, happy "well done!" celebration after the race: bouncy acoustic guitar and mandolin, warm brass pads, marimba melody, light claps, tambourine. Pleasant to sit on for a while; medium-low energy, no build-ups, no ending.
```

### `jingle_clear` — クリア

```
Stage-clear jingle, about 6 seconds, B-flat major, 150 BPM. Joyful brass fanfare with snare roll and cymbal, quick xylophone and piccolo flourish, ending on a bright sustained major chord with a clean ring-out. Celebratory and a little silly, for kids. No vocals.
```

### `jingle_gameover` — ゲームオーバー

狙い：「あちゃー」という笑える失敗の音にして、暗くしない。定番の残念トロンボーンは暗く聞こえやすいので使わない。

```
Game-over jingle, about 5 seconds, G minor. A comedic "oh no!" moment for kids, not sad or dark: a descending clarinet and bassoon phrase over bouncy pizzicato, a xylophone tumbling down, ending on a deflated low note with a soft cymbal choke. Do not use trombone. No vocals.
```

### `bgm_gameover` — ゲームオーバー画面

```
Game-over screen loop, 92 BPM, D minor, 4/4. Droll, slapstick "better luck next time" mood: lazy bassoon and tuba melody, pizzicato strings, brushed snare, muted trumpet comments, soft marimba. Gently funny and encouraging to try again, never gloomy. Low energy, no build-ups, no ending.
```

## 生成のコツ

- **ループ曲は長めに生成して、きれいな8〜16小節を切り出す。** 生成AIは「イントロなし・フェードアウトなし」と指定しても前奏や終わりを付けがちなので、完璧なループを狙わないほうが早い。
- **1曲につき3〜4テイク生成して選ぶ。** テンポがふらつくテイク、終盤で崩れるテイク、ボーカルや掛け声が混ざったテイクは捨てる。
- **統一感を強めたい場合**：先に `bgm_menu` を作り、そのメロディを参照・カバー・リミックス機能で他の曲の素にする。使えるかどうかは生成AIによる。
- **Sunoの場合**：設定は「Suno用シンプル版（現行BGM準拠）」の「Sunoの設定」を参照。
- **商用の権利**：無料プランでは商用利用できないサービスが多い。利用するプランの規約で、生成物を商用ゲームに使えるか確認し、記録しておく。

## 後処理と納品形式

- **ループの切り出し**：小節の境目で切る。ループ長は `小節数 × 1小節の拍数 × 60 ÷ BPM` 秒（4/4拍子なら拍数4、2/4拍子なら2）。

| 素材 | ループ長 |
|---|---|
| `bgm_menu`（テーマ曲、117 BPMの24小節） | 約49.23秒 |
| `bgm_play`（150 BPMの16小節） | 25.6秒 |
| `bgm_chase`（168 BPMの16小節） | 約22.86秒 |
| `bgm_goal`（176 BPMの2/4拍子で32小節） | 約21.82秒 |

- **音量**
  - ループ曲は −16 LUFS（integrated）前後にそろえる。
  - 単発の曲も、聞こえる大きさがループ曲と同じくらいになるようにする。
  - 全曲でトゥルーピークを −1 dBTP 以下にする。
- **納品形式**
  - `assets/audio/bgm/<ID>.ogg`：Ogg Vorbis、ステレオ、44.1kHz、品質0.6程度。
  - 前奏付きのループ曲は、インポート設定で `loop=true` にし、`loop_offset` に前奏の秒数を入れる。
  - `AudioStreamOggVorbis` の `bpm` / `beat_count` / `bar_beats` も設定しておくと、`AudioStreamInteractive` を使って小節の頭で切り替えられる。
- **元データの保管**：`assets/audio/bgm/source/` に置く（`.gdignore` を入れて、Godotに取り込ませない）。置くもの：
  - 生成元のWAV
  - 生成記録：サービス名、プラン、日付、プロンプト、テイクのURLまたはシード
- **ライセンスの記録**：`assets/audio/bgm/LICENSE.md` を差し替え、生成AIのサービス名、プラン、商用利用の可否を書く。

## 場面と素材の対応（実装用）

| ゲーム状態 | 再生する素材 |
|---|---|
| startup_loading / main_menu / customize | `bgm_menu` |
| online_menu（オンライン対戦画面。VSカットインからゲーム画面へ移るまで） | `bgm_online` |
| game_world に入ってヘリ降下、PRELOADING / WAITING_START / FLYOVER | `bgm_intro` |
| COUNTDOWN | `sting_countdown`（チュートリアルは1.0秒の位置から） |
| PLAYING / CORRECT | のこぎり追跡中は `bgm_chase`、チュートリアルは `bgm_tutorial`、それ以外は `bgm_play` |
| GOAL_RACE | `bgm_goal` |
| RESULT_CEREMONY | 2.0秒に `ceremony_build` → 6.3秒にカット → 6.9秒に `sting_verdict` → 11.2秒に `bgm_result` |
| CLEAR | `jingle_clear` → `bgm_result` |
| GAME_OVER | `jingle_gameover` → `bgm_gameover` |
| ポーズ | 再生中の曲にローパスフィルターをかけて −10dB |

### 今の実装（2026年10月12日）

上の表は最終形。今は3曲だけで、次のように切り替えている。

| ゲーム状態 | 曲 |
|---|---|
| メニュー | メニュー曲（`quiz_party_loop.ogg`） |
| ゲーム画面に入ってから（ヘリ到着）、WAITING_START / FLYOVER / COUNTDOWN | 曲なし（`MUSIC_TRACK_NONE`）。メニュー曲を0.8秒でフェードアウトし、観客のざわめきだけを流す（2026年10月12日から） |
| PLAYING / CORRECT / GOAL_RACE | プレイ曲（`quiz_play_loop.ogg`）。PLAYING になった瞬間に頭から流す |
| CLEAR | 結果画面の曲（`quiz_result_loop.ogg`、頭から） |
| RESULT_CEREMONY | 判定（6.9秒）までは曲なし（観客のざわめきとドラムロールだけ）。判定の瞬間に結果画面の曲を頭から流す（`ResultCeremonyDirector`、2026年10月12日から） |
| GAME_OVER | 曲なし。プレイ曲を1秒でフェードアウトする（2026年10月12日まではメニュー曲が流れていた）。`bgm_gameover` ができたらここで流す |
| SUDDEN_DEATH / MENU | メニュー曲（頭から） |
| PRELOADING | 曲を変えない（エンドレスの途中の問題補充で PLAYING と行き来するため） |

- `AudioManager.set_music_track()` が曲ごとのプレイヤーを持ち（`MUSIC_TRACK_NONE` は曲を止めたままにする）、前の曲を0.35秒でフェードアウトして止め、新しい曲を頭から0.35秒でフェードインする。同じ曲を指定したときは何もしない（流し続ける）。
- 曲は `game_world.gd` の `_on_state_changed()` で選ぶ。ゲーム画面を出るとき（`_exit_tree()`）はメニュー曲に戻す。
- 場面ごとの音量（`set_music_context()`）とチュートリアル中の音量下げは、今流れている曲にかかる。
- 実際の流れで切り替わることを `tests/bgm_track_runtime.gd`（`--script res://tests/bgm_track_bootstrap.gd`）で確かめた。
- **画面切り替えのフェード**（2026年10月12日から）：黒い画面の切り替え演出が画面を覆う割合（`SceneTransition.get_cover_factor()`）に合わせて、BGMバスと観客の声のバス（`Ambience`、SFXバスへ送る）の音量を下げる（`AudioManager._process()`）。覆うにつれてフェードアウトし、真っ黒の間（読み込み中）は無音、新しい画面が開くにつれてフェードインする。カーブは等パワー（半分覆うと約−3 dB）。どの切り替え方（ハーフトーンのワイプ、フェード、ドア、VSの分割）でも同じように動く。曲の切り替え（`set_music_track()`）は黒い間に起きるので、新しい曲は画面が開くのに合わせて聞こえ始める。
