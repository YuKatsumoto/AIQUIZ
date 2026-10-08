# BGMリニューアル（全曲AI生成）

現在のBGMは `assets/audio/bgm/quiz_party_loop.ogg`（Sunoで生成、66秒のループ）1曲だけで、全場面で流れ続け、場面ごとに音量だけを変えている（`scripts/autoload/audio_manager.gd`）。2026年10月8日に、それまでの `head_in_the_sand.ogg`（CC0、38秒）から差し替えた（「採用した曲」の節）。これを場面別の13素材に置き換える。全曲を音楽生成AIで作る。

この文書は、生成AIへの発注仕様（プロンプト）と、Godotへ組み込むときの仕様をまとめたもの。

生成はSunoで行い、現行BGMのようにシンプルで壮大すぎない曲にする。プロンプトは「Suno用シンプル版（現行BGM準拠）」の節を優先し、「共通スタイル」以降の楽器の多い案は参考として残す。

## 素材一覧

| ID | 場面 | 種類 | 長さ | BPM | キー |
|---|---|---|---|---|---|
| `bgm_menu` | 起動・メインメニュー・カスタマイズ・オンラインロビー | ループ | 素材は2〜3分 | 92 | F |
| `bgm_intro` | ヘリ降下・問題生成待ち・開始待ち・空撮 | ループ | 素材は1〜2分 | 120 | F |
| `sting_countdown` | カウントダウン「4・3・2・1」→壁が割れる | 単発 | 約5.5秒 | 120 | F→B♭ |
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
- **カウントダウン**：3.99秒（`game_state.gd:2025`）。
  - 表示は `ceil(countdown_timer)` で「4・3・2・1」を約1秒ずつ（`game_world.gd:2649`）。0秒で壁が割れて PLAYING になる。
  - 進むにつれて壁の揺れと蒸気が強くなる。
  - チュートリアルは3.0秒から始まるので「3・2・1」だけ。`sting_countdown` を1.0秒の位置から再生すれば合う。
  - カウントダウンには数字ごとの短い電子音と、GO の電子音・壁の爆発音を効果音として入れた（`docs/sound_effects.md`）。`sting_countdown` と重なって聞こえる場合は、効果音の `countdown_beep` / `countdown_go` を下げるか外す。
- **スコアタワーの演出**（`assets/result_finale/finale_motion.json`。両者がゴールした時点を0秒とする）

| 時刻 | 出来事 |
|---|---|
| 2.0秒 | 出演者の登場 |
| 2.34秒 | 台座のポップ音 |
| 4.1〜6.3秒 | 塔が伸びる |
| 6.3秒 | 静寂（hush） |
| 6.9秒 | 判定（シンバルの効果音） |
| 7.4秒 | 負けた側の塔が沈み始める。残念トロンボーンの効果音はその0.05秒後 |
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

### 採用した曲

#### `quiz_party_loop.ogg`（2026年10月8日採用）

テーマ曲の参考音源をCoverした曲。今は場面別の切り替えが未実装なので、全場面でこの曲を流している。

| 項目 | 内容 |
|---|---|
| 生成元 | Suno「Quiz Party Loop」（ユーザー katsuyu2354、2026-10-08T14:47:07Z、id `efe7efd1-dde8-44a5-9348-25bf92c801e6`） |
| 元ファイル | `assets/audio/bgm/source/quiz_party_loop_original.mp3`（99.6秒、48kHzステレオ、−15.6 LUFS） |
| テンポ・キー | 116.2 BPM、4/4、ハ長調（C）。Coverでもテーマ曲のテンポ（117 BPM）がほぼそのまま残った |
| 構成 | 0.065秒を0小節目とした48小節。8小節単位でフレーズが繰り返され、16小節ごとにほぼ同じ流れになる |
| ループ区間 | 8〜40小節目の32小節（元ファイルの16.548〜82.640秒）。40小節目は8小節目とよく似ているので、ここで8小節目に戻す |
| 納品ファイル | `assets/audio/bgm/quiz_party_loop.ogg`（66.092秒、3,172,414サンプル、48kHzステレオ、Ogg Vorbis 品質6、−16.0 LUFS、ピーク −4.6 dBFS） |
| インポート設定 | `loop=true`、`loop_offset=0`、`bpm=116.2`、`beat_count=128`、`bar_beats=4` |

- **つなぎ目の処理**：Sunoの曲は同じフレーズでも波形が毎回少し違うので、そのままでは切れ目で音が飛ぶ。ループの頭の30ミリ秒を、「40小節目の頭（終わりから自然に続く音）」から「8小節目の頭」へ徐々に入れ替えた。区切りは小節の頭の40ミリ秒前に置き、拍の頭の音にかからないようにした。
  - つなぎ目の段差は、隣り合うサンプル同士の通常の変化（99.9パーセンタイル）の約1/18。
  - つなぎ目の拍の頭の立ち上がりの強さは、元の曲の8小節目の頭とほぼ同じ。
- **48kHzのまま納品した理由**：後処理の基準は44.1kHzだが、ループ音源を変換すると両端に余計な揺れが出て、つなぎ目が乱れることがある。Godotは48kHzをそのまま再生できる。
- **商用利用の権利**：生成したときのSunoのプランを `assets/audio/bgm/LICENSE.md` に記入する。

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

狙い：6.9秒にコードから鳴らす。今ある `cymbal` の効果音とぶつかる場合は、効果音のほうを外す。その直後に残念トロンボーン（負けた側）が鳴るので、ファンファーレは4秒以内で終わらせる。

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

狙い：「あちゃー」という笑える失敗の音にして、暗くしない。残念トロンボーンの効果音とかぶらないよう、トロンボーンは使わない。

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
| startup_loading / main_menu / customize / online_lobby | `bgm_menu` |
| game_world に入ってヘリ降下、PRELOADING / WAITING_START / FLYOVER | `bgm_intro` |
| COUNTDOWN | `sting_countdown`（チュートリアルは1.0秒の位置から） |
| PLAYING / CORRECT | のこぎり追跡中は `bgm_chase`、チュートリアルは `bgm_tutorial`、それ以外は `bgm_play` |
| GOAL_RACE | `bgm_goal` |
| RESULT_CEREMONY | 2.0秒に `ceremony_build` → 6.3秒にカット → 6.9秒に `sting_verdict` → 11.2秒に `bgm_result` |
| CLEAR | `jingle_clear` → `bgm_result` |
| GAME_OVER | `jingle_gameover` → `bgm_gameover` |
| ポーズ | 再生中の曲にローパスフィルターをかけて −10dB |

`audio_manager.gd` は今のところプレイヤーが1つで音量しか変えないので、曲の切り替え（クロスフェード、または `AudioStreamInteractive` で小節の頭で切り替え）を新しく実装する必要がある。素材がそろってから実装する。
