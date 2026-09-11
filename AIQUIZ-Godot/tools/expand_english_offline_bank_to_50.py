"""Expand the hand-authored English bank to 50 questions per tier.

This script uses no network or quiz-generation API.  It rebuilds the original
English section, adds locally authored question families, validates the exact
four-grades x three-tiers x fifty-questions contract, and
replaces only the final ``英語`` root member in ``offline_bank.json``.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import sync_english_offline_bank as bank


ROOT = Path(__file__).resolve().parents[1]
BANK_PATH = ROOT / "offline_bank.json"
TIERS = ("基本", "標準", "応用")


def add_family(
    grade: int,
    tier: str,
    genre: str,
    prompt: str,
    entries: list[tuple[str, str]],
    explanation: str = "正解は {answer} です。",
) -> None:
    """Add an authored family, using sibling answers as clear distractors."""
    if len(entries) < 4:
        raise ValueError(f"{grade}/{tier}/{genre}: at least four entries required")
    answers = [answer for _, answer in entries]
    if len(set(answers)) != len(answers):
        raise ValueError(f"{grade}/{tier}/{genre}: answers must be unique")
    for index, (cue, answer) in enumerate(entries):
        wrongs = tuple(answers[(index + offset) % len(answers)] for offset in range(1, 4))
        bank.add(
            grade,
            tier,
            genre,
            prompt.format(cue=cue),
            answer,
            wrongs,
            explanation.format(cue=cue, answer=answer),
        )


def rebuild_original_questions() -> None:
    for items in bank.QUESTIONS.values():
        items.clear()
    bank.build_grade_3()
    bank.add_rows(3, "標準", "文字", [
        ("大文字の並び「L, M, __」に入る文字は？", "N", "K", "O", "P", "L, M, N の順です。"),
    ])
    bank.build_grade_4()
    bank.build_grade_5()
    bank.build_grade_6()


def expand_grade_3() -> None:
    # 基本: 29問（既存21問と合わせて50問）
    add_family(3, "基本", "食べ物", "「{cue}」を表す英語は？", [
        ("りんご", "apple"), ("バナナ", "banana"), ("牛乳", "milk"),
        ("ジュース", "juice"), ("ごはん", "rice"), ("ケーキ", "cake"),
    ], "{cue} は {answer} と表します。")
    add_family(3, "基本", "教室", "「{cue}」を表す英語は？", [
        ("ペン", "pen"), ("鉛筆", "pencil"), ("本", "book"),
        ("消しゴム", "eraser"), ("定規", "ruler"), ("机", "desk"),
    ], "{cue} は {answer} と表します。")
    add_family(3, "基本", "体", "「{cue}」を表す英語は？", [
        ("頭", "head"), ("目", "eye"), ("耳", "ear"), ("手", "hand"), ("足", "leg"),
    ], "{cue} は {answer} と表します。")
    add_family(3, "基本", "動作", "「{cue}」を表す英語は？", [
        ("手をたたく", "clap"), ("向きを変える", "turn"), ("さわる", "touch"),
        ("指さす", "point"), ("止まる", "stop"), ("始める", "start"),
    ], "{cue} は {answer} と表します。")
    add_family(3, "基本", "文字", "大文字「{cue}」に合う小文字は？", [
        ("A", "a"), ("B", "b"), ("D", "d"), ("G", "g"), ("P", "p"), ("R", "r"),
    ], "大文字 {cue} の小文字は {answer} です。")

    # 標準: 30問
    add_family(3, "標準", "挨拶", "「{cue}」の意味は？", [
        ("Good afternoon.", "こんにちは"), ("See you.", "またね"),
        ("Nice to meet you.", "はじめまして"), ("I'm sorry.", "ごめんなさい"),
        ("Excuse me.", "すみません"),
    ], "{cue} は「{answer}」という意味です。")
    add_family(3, "標準", "数", "英語の「{cue}」はどの数？", [
        ("eleven", "11"), ("thirteen", "13"), ("fourteen", "14"),
        ("fifteen", "15"), ("eighteen", "18"),
    ], "{cue} は {answer} を表します。")
    add_family(3, "標準", "気分", "「{cue}」の意味は？", [
        ("I'm sad.", "かなしい"), ("I'm tired.", "つかれた"),
        ("I'm thirsty.", "のどがかわいた"), ("I'm sleepy.", "ねむい"),
        ("I'm great.", "とても元気"),
    ], "{cue} は「{answer}」という意味です。")
    add_family(3, "標準", "教室", "先生の「{cue}」の指示は？", [
        ("Sit down.", "座って"), ("Close your book.", "本を閉じて"),
        ("Listen.", "聞いて"), ("Look at me.", "私を見て"),
        ("Raise your hand.", "手を挙げて"),
    ], "{cue} は「{answer}」という指示です。")
    add_family(3, "標準", "好きなもの", "「{cue}」で好きなものは？", [
        ("I like apples.", "りんご"), ("I like music.", "音楽"),
        ("I like rabbits.", "うさぎ"), ("I like green.", "緑"),
        ("I like swimming.", "水泳"),
    ], "文では {answer} が好きだと言っています。")
    add_family(3, "標準", "色と形", "「{cue}」の意味は？", [
        ("green square", "緑の四角"), ("red circle", "赤い丸"),
        ("yellow star", "黄色い星"), ("blue triangle", "青い三角"),
        ("pink heart", "桃色のハート"),
    ], "{cue} は「{answer}」を表します。")

    # 応用: 30問
    add_family(3, "応用", "会話", "会話「{cue}」に合う返事は？", [
        ("Good morning!", "Good morning!"),
        ("How are you?", "I'm great."),
        ("Do you like dogs?", "Yes, I do."),
        ("What's this?", "It's an eraser."),
        ("How many pencils?", "Four pencils."),
    ], "{cue} への自然な返事は {answer} です。")
    add_family(3, "応用", "場面", "{cue}ときに言う言葉は？", [
        ("友達と別れる", "See you."), ("間違えてあやまる", "I'm sorry."),
        ("初めて会う", "Nice to meet you."), ("助けてもらった", "Thank you."),
        ("夜、寝る前に挨拶する", "Good night."),
    ], "この場面では {answer} が自然です。")
    add_family(3, "応用", "語順", "「{cue}」を表す正しい英文は？", [
        ("私は猫が好きです", "I like cats."), ("これは定規です", "It's a ruler."),
        ("私はおなかがすいています", "I'm hungry."), ("私は10歳です", "I'm ten."),
        ("5個のりんご", "Five apples."),
    ], "正しい表し方は {answer} です。")
    add_family(3, "応用", "読み取り", "文「{cue}」から分かることは？", [
        ("I like red apples.", "赤いりんごが好き"),
        ("I have two cats.", "猫を2匹飼っている"),
        ("I'm nine years old.", "9歳である"),
        ("This is a blue pen.", "これは青いペン"),
        ("I can jump.", "跳ぶことができる"),
    ], "文から「{answer}」と分かります。")
    add_family(3, "応用", "文字", "{cue}に入る文字は？", [
        ("A, C, E, __", "G"), ("B, D, F, __", "H"),
        ("M, N, O, __", "P"), ("R, S, T, __", "U"),
        ("W, X, Y, __", "Z"),
    ], "文字の並びから {answer} が入ります。")
    add_family(3, "応用", "組み合わせ", "{cue}を表す組み合わせは？", [
        ("3匹の犬", "three dogs"), ("2冊の本", "two books"),
        ("緑の星", "green star"), ("黄色い丸", "yellow circle"),
        ("4本の鉛筆", "four pencils"),
    ], "{cue} は {answer} と表します。")


def expand_grade_4() -> None:
    # 各難易度30問（既存20問と合わせて各50問）
    for genre, prompt, entries in [
        ("学校", "「{cue}」を表す英語は？", [("ノート", "notebook"), ("かばん", "bag"), ("はさみ", "scissors"), ("のり", "glue"), ("黒板", "board"), ("教室", "classroom")]),
        ("時刻", "英語の「{cue}」はどの数？", [("twenty", "20"), ("thirty", "30"), ("forty", "40"), ("fifty", "50"), ("sixty", "60"), ("ninety", "90")]),
        ("日課", "日課の「{cue}」を表す英語は？", [("昼食を食べる", "eat lunch"), ("宿題をする", "do homework"), ("テレビを見る", "watch TV"), ("お風呂に入る", "take a bath"), ("歯をみがく", "brush my teeth"), ("部屋を掃除する", "clean my room")]),
        ("町", "「{cue}」を表す英語は？", [("病院", "hospital"), ("学校", "school"), ("店", "store"), ("動物園", "zoo"), ("郵便局", "post office"), ("交番", "police box")]),
        ("文字", "大文字「{cue}」に合う小文字は？", [("E", "e"), ("H", "h"), ("J", "j"), ("Q", "q"), ("T", "t"), ("Y", "y")]),
    ]:
        add_family(4, "基本", genre, prompt, entries, "{cue} の答えは {answer} です。")

    for genre, prompt, entries in [
        ("天気", "「{cue}」の意味は？", [("It's windy.", "風が強い"), ("It's snowy.", "雪です"), ("It's hot.", "暑いです"), ("It's cold.", "寒いです"), ("It's warm.", "暖かいです")]),
        ("曜日", "{cue}の次の曜日は？", [("Tuesday", "Wednesday"), ("Wednesday", "Thursday"), ("Thursday", "Friday"), ("Friday", "Saturday"), ("Saturday", "Sunday")]),
        ("時刻", "「{cue}」の意味は？", [("I get up at six.", "6時に起きる"), ("I eat lunch at twelve.", "12時に昼食"), ("I go home at four.", "4時に帰宅"), ("I take a bath at eight.", "8時に入浴"), ("I go to bed at nine.", "9時に寝る")]),
        ("道案内", "道案内の「{cue}」の意味は？", [("Turn left.", "左に曲がる"), ("Go straight.", "まっすぐ進む"), ("Stop here.", "ここで止まる"), ("It's on your right.", "右側にある"), ("Cross the street.", "道を渡る")]),
        ("持ち物", "「{cue}」から分かることは？", [("I have a notebook.", "ノートを持つ"), ("I have two rulers.", "定規を2本持つ"), ("I don't have a pen.", "ペンを持たない"), ("I have a red bag.", "赤いかばんを持つ"), ("I don't have scissors.", "はさみを持たない")]),
        ("買い物", "店で「{cue}」の意味は？", [("Ten apples, please.", "りんごを10個"), ("How many do you want?", "ほしい数を質問"), ("This one, please.", "これをください"), ("Two cakes, please.", "ケーキを2個"), ("Thank you very much.", "どうもありがとう")]),
    ]:
        add_family(4, "標準", genre, prompt, entries, "答えは「{answer}」です。")

    for genre, prompt, entries in [
        ("会話", "会話「{cue}」に合う返事は？", [("What day is it?", "It's Thursday."), ("What time is it?", "It's nine."), ("How's the weather?", "It's cloudy."), ("Do you have a pen?", "No, I don't."), ("Where is the zoo?", "Turn left.")]),
        ("時間割", "文「{cue}」の授業は？", [("I have math on Monday.", "月曜に算数"), ("I have art on Tuesday.", "火曜に図工"), ("I have music on Friday.", "金曜に音楽"), ("I have P.E. on Thursday.", "木曜に体育"), ("I have science today.", "今日は理科")]),
        ("道案内", "道案内「{cue}」の内容は？", [("The park is on your left.", "左に公園"), ("The station is on your right.", "右に駅"), ("The school is straight ahead.", "正面に学校"), ("Turn left at the store.", "店で左折"), ("Turn right at the hospital.", "病院で右折")]),
        ("日課", "文「{cue}」で先にすることは？", [("I get up, then eat breakfast.", "起きる"), ("I eat lunch, then play.", "昼食"), ("I go home, then read.", "帰宅"), ("I bathe, then go to bed.", "入浴"), ("I brush my teeth, then sleep.", "歯みがき")]),
        ("文字", "{cue}を小文字で正しく書いたものは？", [("BOOK", "book"), ("PENCIL", "pencil"), ("MONDAY", "monday"), ("SUNNY", "sunny"), ("LIBRARY", "library")]),
        ("読み取り", "文「{cue}」から分かることは？", [("It's rainy. I have an umbrella.", "傘を持っている"), ("It's Sunday. I go to the park.", "日曜に公園へ行く"), ("I get up at seven every day.", "毎日7時に起きる"), ("I have three red pencils.", "赤鉛筆を3本持つ"), ("The library is on my right.", "図書館は右側")]),
    ]:
        add_family(4, "応用", genre, prompt, entries, "文から「{answer}」と分かります。")


def expand_grade_5() -> None:
    for genre, prompt, entries in [
        ("月", "「{cue}」を表す英語は？", [("3月", "March"), ("5月", "May"), ("6月", "June"), ("7月", "July"), ("9月", "September"), ("10月", "October"), ("11月", "November")]),
        ("教科", "「{cue}」を表す英語は？", [("英語", "English"), ("国語", "Japanese"), ("社会", "social studies"), ("家庭科", "home economics"), ("道徳", "moral education"), ("総合", "integrated studies")]),
        ("国", "国名「{cue}」を表す英語は？", [("アメリカ", "the U.S."), ("イギリス", "the U.K."), ("フランス", "France"), ("イタリア", "Italy"), ("中国", "China"), ("韓国", "Korea")]),
        ("活動", "活動「{cue}」を表す英語は？", [("絵を描く", "draw pictures"), ("サッカーをする", "play soccer"), ("本を読む", "read books"), ("速く走る", "run fast"), ("自転車に乗る", "ride a bike"), ("英語を話す", "speak English")]),
        ("位置", "「{cue}」を表す英語は？", [("〜の中", "in"), ("〜の上", "on"), ("〜の下", "under"), ("〜のそば", "by"), ("〜の前", "in front of")]),
    ]:
        add_family(5, "基本", genre, prompt, entries, "{cue} は {answer} と表します。")

    for genre, prompt, entries in [
        ("日付", "「{cue}」の意味は？", [("My birthday is in May.", "誕生日は5月"), ("It's on July third.", "7月3日です"), ("New Year's Day is in January.", "元日は1月"), ("Christmas is in December.", "クリスマスは12月"), ("My birthday is tomorrow.", "誕生日は明日")]),
        ("時間割", "「{cue}」から分かることは？", [("I have English on Monday.", "月曜に英語"), ("We have P.E. on Tuesday.", "火曜に体育"), ("Art is my favorite subject.", "図工が一番好き"), ("I have math after music.", "音楽の後に算数"), ("We don't have science today.", "今日は理科なし")]),
        ("できること", "「{cue}」の意味は？", [("I can swim well.", "上手に泳げる"), ("I can't cook.", "料理できない"), ("Can you play tennis?", "テニスできる？"), ("She can sing.", "彼女は歌える"), ("He can run fast.", "彼は速く走れる")]),
        ("ほしいもの", "「{cue}」の意味は？", [("I want a blue cap.", "青い帽子がほしい"), ("I want to play soccer.", "サッカーをしたい"), ("What do you want?", "何がほしい？"), ("I want some water.", "水がほしい"), ("I want to visit Canada.", "カナダを訪れたい")]),
        ("国", "「{cue}」の出身国は？", [("I'm from France.", "フランス"), ("I'm from India.", "インド"), ("I'm from Australia.", "オーストラリア"), ("I'm from Brazil.", "ブラジル"), ("I'm from Canada.", "カナダ")]),
        ("位置", "「{cue}」の位置は？", [("The ball is under the desk.", "机の下"), ("The cat is in the box.", "箱の中"), ("The book is on the table.", "机の上"), ("The park is by the school.", "学校のそば"), ("The bus is in front of us.", "私たちの前")]),
    ]:
        add_family(5, "標準", genre, prompt, entries, "答えは「{answer}」です。")

    for genre, prompt, entries in [
        ("会話", "会話「{cue}」に合う返事は？", [("When is your birthday?", "It's in April."), ("What subject do you like?", "I like science."), ("Can you cook?", "Yes, I can."), ("What do you want?", "I want a ruler."), ("Where are you from?", "I'm from Japan.")]),
        ("時間割", "文「{cue}」で最初の授業は？", [("Math, then music.", "算数"), ("Science, then art.", "理科"), ("English, then P.E.", "英語"), ("Japanese, then math.", "国語"), ("Art, then social studies.", "図工")]),
        ("できること", "文「{cue}」から分かることは？", [("I can swim, but I can't dive.", "泳げる"), ("Mai can cook curry.", "マイは料理できる"), ("Ken can't ride a bike.", "ケンは自転車不可"), ("We can speak English.", "私たちは英語を話せる"), ("She can play the piano.", "彼女はピアノを弾ける")]),
        ("旅行", "文「{cue}」で行きたい国は？", [("I want to see koalas in Australia.", "オーストラリア"), ("I want to see the Eiffel Tower.", "フランス"), ("I want to eat curry in India.", "インド"), ("I want maple leaves in Canada.", "カナダ"), ("I want to visit Rome in Italy.", "イタリア")]),
        ("語順", "「{cue}」の正しい英文は？", [("私は理科が好きです", "I like science."), ("私は上手に泳げます", "I can swim well."), ("赤い靴がほしいです", "I want red shoes."), ("誕生日は8月です", "It's in August."), ("本は机の下です", "It's under the desk.")]),
        ("道案内", "文「{cue}」に出てくる場所は？", [("Go straight to the library.", "図書館"), ("Turn left at the station.", "駅"), ("The park is by the hospital.", "公園"), ("The school is on your right.", "学校"), ("The post office is ahead.", "郵便局")]),
    ]:
        add_family(5, "応用", genre, prompt, entries, "答えは「{answer}」です。")


def expand_grade_6() -> None:
    for genre, prompt, entries in [
        ("過去形", "「{cue}」の過去形は？", [("go", "went"), ("eat", "ate"), ("see", "saw"), ("have", "had"), ("is", "was"), ("are", "were"), ("play", "played"), ("visit", "visited")]),
        ("職業", "職業「{cue}」を表す英語は？", [("看護師", "nurse"), ("消防士", "firefighter"), ("パイロット", "pilot"), ("科学者", "scientist"), ("芸術家", "artist"), ("農家", "farmer"), ("警察官", "police officer"), ("歌手", "singer")]),
        ("世界", "国名「{cue}」を表す英語は？", [("スペイン", "Spain"), ("ドイツ", "Germany"), ("メキシコ", "Mexico"), ("タイ", "Thailand"), ("シンガポール", "Singapore"), ("ニュージーランド", "New Zealand"), ("南アフリカ", "South Africa")]),
        ("環境", "環境の語「{cue}」を表す英語は？", [("再利用する", "reuse"), ("資源を再生する", "recycle"), ("節約する", "save"), ("ごみ", "trash"), ("自然", "nature"), ("電気", "electricity"), ("汚染", "pollution")]),
    ]:
        add_family(6, "基本", genre, prompt, entries, "{cue} は {answer} と表します。")

    for genre, prompt, entries in [
        ("過去", "「{cue}」の意味は？", [("I visited Osaka.", "大阪を訪れた"), ("We played baseball.", "野球をした"), ("She saw a dolphin.", "彼女はイルカを見た"), ("He ate noodles.", "彼は麺を食べた"), ("They had a good time.", "楽しく過ごした")]),
        ("将来", "「{cue}」の将来の夢は？", [("I want to help sick people.", "医者"), ("I want to teach children.", "教師"), ("I want to cook at a restaurant.", "料理人"), ("I want to help animals.", "獣医"), ("I want to travel in space.", "宇宙飛行士")]),
        ("理由", "「{cue}」で示す理由は？", [("Because it's exciting.", "わくわくするから"), ("Because I love animals.", "動物が好きだから"), ("Because I like helping people.", "人助けが好きだから"), ("Because it's beautiful.", "美しいから"), ("Because I enjoy cooking.", "料理が楽しいから")]),
        ("思い出", "「{cue}」から分かることは？", [("I went to Okinawa last summer.", "昨夏に沖縄へ行った"), ("We saw fireworks in August.", "8月に花火を見た"), ("I played soccer yesterday.", "昨日サッカーをした"), ("She enjoyed the school trip.", "修学旅行を楽しんだ"), ("He ate sushi in Tokyo.", "東京で寿司を食べた")]),
        ("環境", "「{cue}」の意味は？", [("Turn off the lights.", "電気を消そう"), ("Use less water.", "水を減らそう"), ("Pick up trash.", "ごみを拾おう"), ("Protect the forests.", "森を守ろう"), ("Reuse this bag.", "この袋を再利用")]),
        ("順序", "文「{cue}」で先にしたことは？", [("I ate lunch, then played soccer.", "昼食"), ("We visited Nara, then Kyoto.", "奈良訪問"), ("She got up and made breakfast.", "起床"), ("He studied, then watched TV.", "勉強"), ("I saw a movie after dinner.", "夕食")]),
    ]:
        add_family(6, "標準", genre, prompt, entries, "答えは「{answer}」です。")

    for genre, prompt, entries in [
        ("会話", "会話「{cue}」に合う返事は？", [("What did you see?", "I saw a tiger."), ("Where did you go?", "I went to Kobe."), ("How was the festival?", "It was exciting."), ("What do you want to be?", "I want to be a vet."), ("Why do you like pandas?", "Because they're cute.")]),
        ("読み取り", "文「{cue}」から分かることは？", [("Last year, I visited Canada.", "昨年カナダを訪問"), ("I ate pizza, but not salad.", "ピザだけ食べた"), ("We saw two bears in the zoo.", "熊を2頭見た"), ("My trip was short but fun.", "短いが楽しい旅行"), ("I didn't play tennis yesterday.", "昨日テニスなし")]),
        ("夢", "文「{cue}」に合う職業は？", [("I want to make sick people well.", "医者"), ("I want to grow vegetables.", "農家"), ("I want to teach math.", "教師"), ("I want to sing on stage.", "歌手"), ("I want to keep people safe.", "警察官")]),
        ("世界", "文「{cue}」の国は？", [("I saw pyramids in Egypt.", "エジプト"), ("I ate pasta in Italy.", "イタリア"), ("I saw koalas in Australia.", "オーストラリア"), ("I visited the Louvre in France.", "フランス"), ("I saw the Taj Mahal in India.", "インド")]),
        ("環境", "{cue}ための行動は？", [("紙を節約する", "Use both sides."), ("電気を節約する", "Turn off lights."), ("水を節約する", "Turn off the tap."), ("町をきれいにする", "Pick up trash."), ("物を再利用する", "Use it again.")]),
        ("語順", "「{cue}」の正しい英文は？", [("京都へ行きました", "I went to Kyoto."), ("何を見ましたか", "What did you see?"), ("教師になりたいです", "I want to be a teacher."), ("旅行はすばらしかった", "The trip was great."), ("なぜそれが好きですか", "Why do you like it?")]),
    ]:
        add_family(6, "応用", genre, prompt, entries, "正しい答えは {answer} です。")


def validate_exact_contract() -> None:
    normalized_seen: set[str] = set()
    total = 0
    for grade in range(3, 7):
        items = bank.QUESTIONS[str(grade)]
        if len(items) != 150:
            raise ValueError(f"grade {grade}: expected 150, got {len(items)}")
        tier_counts = {tier: 0 for tier in TIERS}
        for item in items:
            question = str(item["q"])
            tier = next((value for value in TIERS if question.startswith(f"【{value}】")), "")
            if not tier:
                raise ValueError(f"grade {grade}: missing tier: {question}")
            tier_counts[tier] += 1
            normalized = re.sub(r"[\s　]+", "", question).casefold()
            if normalized in normalized_seen:
                raise ValueError(f"normalized duplicate: {question}")
            normalized_seen.add(normalized)
            choices = [str(choice) for choice in item["c"]]
            if len({choice.casefold() for choice in choices}) != 4:
                raise ValueError(f"case-insensitive duplicate choices: {question}")
            if item.get("src") != "OFFLINE":
                raise ValueError(f"non-offline source: {question}")
        if tier_counts != {tier: 50 for tier in TIERS}:
            raise ValueError(f"grade {grade}: tier mismatch {tier_counts}")
        total += len(items)
        print(f"grade {grade}: {len(items)} questions, tiers={tier_counts}")
    if total != 600:
        raise ValueError(f"expected 600 total questions, got {total}")
    bank.validate_bank()


def replace_english_section() -> None:
    original = BANK_PATH.read_text(encoding="utf-8")
    parsed_before = json.loads(original)
    non_english_before = {key: value for key, value in parsed_before.items() if key != "英語"}
    marker = '\n  "英語": '
    start = original.rfind(marker)
    if start < 0:
        raise RuntimeError("active bank has no final English section")
    if list(parsed_before)[-1] != "英語":
        raise RuntimeError("English must be the final root member for scoped replacement")
    prefix = original[:start]
    fragment = json.dumps({"英語": bank.QUESTIONS}, ensure_ascii=False, indent=2)
    inner = fragment[2:-2]
    newline = "\r\n" if "\r\n" in original else "\n"
    inner = inner.replace("\n", newline)
    updated = prefix + newline + inner + newline + "}" + newline
    parsed_after = json.loads(updated)
    non_english_after = {key: value for key, value in parsed_after.items() if key != "英語"}
    if non_english_after != non_english_before:
        raise RuntimeError("non-English bank changed during scoped replacement")
    BANK_PATH.write_text(updated, encoding="utf-8", newline="")
    print("replaced only the English section with 600 validated questions")


def main() -> None:
    rebuild_original_questions()
    expand_grade_3()
    expand_grade_4()
    expand_grade_5()
    expand_grade_6()
    validate_exact_contract()
    replace_english_section()


if __name__ == "__main__":
    main()
