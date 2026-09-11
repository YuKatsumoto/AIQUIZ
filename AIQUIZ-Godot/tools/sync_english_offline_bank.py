"""Build and append the hand-authored English offline bank without using an API.

The active bank is intentionally updated by appending one root key so the large
existing Japanese bank is left byte-for-byte unchanged. Re-running is safe: the
script refuses to replace an existing English section.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BANK_PATH = ROOT / "offline_bank.json"
QUESTIONS: dict[str, list[dict[str, object]]] = {str(g): [] for g in range(3, 7)}


def add(
    grade: int,
    tier: str,
    genre: str,
    question: str,
    correct: str,
    wrongs: tuple[str, str, str],
    explanation: str,
) -> None:
    bucket = QUESTIONS[str(grade)]
    choices = list(wrongs)
    answer_index = len(bucket) % 4
    choices.insert(answer_index, correct)
    bucket.append(
        {
            "q": f"【{tier}】{question}",
            "c": choices,
            "a": answer_index,
            "exp": explanation,
            "src": "OFFLINE",
            "g": genre,
        }
    )


def add_vocab(
    grade: int,
    genre: str,
    entries: list[tuple[str, str]],
) -> None:
    if len(entries) < 4:
        raise ValueError(f"{grade}/{genre}: vocabulary groups need at least four entries")
    english_words = [english for _, english in entries]
    for index, (japanese, english) in enumerate(entries):
        wrongs: list[str] = []
        offset = 1
        while len(wrongs) < 3:
            candidate = english_words[(index + offset) % len(english_words)]
            if candidate != english and candidate not in wrongs:
                wrongs.append(candidate)
            offset += 1
        add(
            grade,
            "基本",
            genre,
            f"「{japanese}」を表す英語は？",
            english,
            (wrongs[0], wrongs[1], wrongs[2]),
            f"{japanese} は {english} と表します。",
        )


def add_rows(
    grade: int,
    tier: str,
    genre: str,
    rows: list[tuple[str, str, str, str, str, str]],
) -> None:
    for question, correct, wrong1, wrong2, wrong3, explanation in rows:
        add(grade, tier, genre, question, correct, (wrong1, wrong2, wrong3), explanation)


def build_grade_3() -> None:
    add_vocab(3, "挨拶", [
        ("こんにちは", "Hello."), ("ありがとう", "Thank you."),
        ("さようなら", "Goodbye."), ("おはよう", "Good morning."),
        ("おやすみ", "Good night."),
    ])
    add_vocab(3, "色", [
        ("赤", "red"), ("青", "blue"), ("黄色", "yellow"), ("緑", "green"),
    ])
    add_vocab(3, "動物", [
        ("犬", "dog"), ("猫", "cat"), ("鳥", "bird"), ("うさぎ", "rabbit"),
    ])
    add_vocab(3, "数", [
        ("1", "one"), ("5", "five"), ("10", "ten"), ("20", "twenty"),
    ])
    add_vocab(3, "形", [
        ("丸", "circle"), ("三角", "triangle"), ("星", "star"), ("四角", "square"),
    ])

    add_rows(3, "標準", "挨拶", [
        ("「How are you?」への自然な返事は？", "I'm fine.", "It's a pen.", "At seven.", "Good night.", "気分を聞かれたので I'm fine. と答えます。"),
        ("「Thank you.」への自然な返事は？", "You're welcome.", "Good morning.", "I'm hungry.", "See you.", "お礼には You're welcome. と返せます。"),
        ("朝8時に友達へ言う挨拶は？", "Good morning.", "Good night.", "Goodbye.", "I'm sorry.", "朝に会ったときは Good morning. を使います。"),
        ("寝る前に家族へ言う挨拶は？", "Good night.", "Hello.", "Good afternoon.", "Thank you.", "寝る前の挨拶は Good night. です。"),
    ])
    add_rows(3, "標準", "数", [
        ("「How many apples?」で尋ねているのは？", "りんごの数", "りんごの色", "りんごの味", "りんごの持ち主", "How many は数を尋ねる表現です。"),
        ("りんごが3個あるときの答えは？", "Three apples.", "Five apples.", "Ten apples.", "One apple.", "3個なので Three apples. と答えます。"),
        ("「twelve」が表す数は？", "12", "2", "20", "10", "twelve は12を表します。"),
        ("「eight」の次の数を英語で表すと？", "nine", "seven", "ten", "five", "8の次は9なので nine です。"),
    ])
    add_rows(3, "標準", "色と形", [
        ("「青い星」を表す組み合わせは？", "blue star", "red star", "blue circle", "green triangle", "blue は青、star は星です。"),
        ("「yellow circle」の意味は？", "黄色い丸", "青い丸", "黄色い三角", "緑の星", "yellow は黄色、circle は丸です。"),
        ("赤い三角を表す英語は？", "red triangle", "red circle", "blue triangle", "yellow star", "red と triangle を組み合わせます。"),
    ])
    add_rows(3, "標準", "好きなもの", [
        ("「I like soccer.」の意味は？", "サッカーが好き", "サッカーを持つ", "サッカーを教える", "サッカーが苦手", "I like ... は「…が好き」です。"),
        ("「Do you like cats?」への肯定の返事は？", "Yes, I do.", "Yes, I am.", "It's a cat.", "At home.", "Do you ...? には Yes, I do. と答えられます。"),
        ("犬が好きだと伝える英文は？", "I like dogs.", "I am a dog.", "I have like.", "Dogs like I.", "I like の後に好きなものを置きます。"),
    ])
    add_rows(3, "標準", "身近な物", [
        ("本を指して「What's this?」と聞かれたら？", "It's a book.", "I like books.", "Open the door.", "I'm a book.", "物の名前は It's a book. と答えられます。"),
        ("「Open your book.」の意味は？", "本を開いて", "本を閉じて", "立って", "座って", "open は「開く」を表します。"),
        ("「Stand up.」の意味は？", "立って", "座って", "走って", "本を開いて", "stand up は「立つ」です。"),
    ])
    add_rows(3, "標準", "気分", [
        ("「I'm hungry.」の意味は？", "おなかがすいた", "うれしい", "つかれた", "かなしい", "hungry は「おなかがすいた」です。"),
        ("うれしい気分を表す英語は？", "I'm happy.", "I'm sad.", "I'm tired.", "I'm hungry.", "happy は「うれしい」を表します。"),
    ])

    add_rows(3, "応用", "会話", [
        ("会話「Hello!」「___」に合う返事は？", "Hello!", "Good night.", "Ten.", "A pencil.", "同じ挨拶 Hello! を返すと自然です。"),
        ("会話「Thank you.」「___」に合う返事は？", "You're welcome.", "I'm ten.", "It's blue.", "Good night.", "お礼への自然な返事は You're welcome. です。"),
        ("会話「Do you like blue?」「___」の肯定は？", "Yes, I do.", "Yes, it is.", "I'm blue.", "Blue, please.", "好みの質問への肯定は Yes, I do. です。"),
        ("会話「What's this?」「___」本を答えるには？", "It's a book.", "I book this.", "Yes, I do.", "Three books?", "物を答えるときは It's a book. が自然です。"),
        ("会話「How many cats?」「___」10匹なら？", "Ten cats.", "Cat is ten.", "I like ten.", "Ten colors.", "数と動物名を Ten cats. の順で言います。"),
    ])
    add_rows(3, "応用", "文脈", [
        ("朝に先生と会った場面で最も自然なのは？", "Good morning.", "Good night.", "Goodbye.", "I'm hungry.", "朝の出会いでは Good morning. が自然です。"),
        ("プレゼントを受け取った場面で言う言葉は？", "Thank you.", "I'm sorry.", "Good night.", "How many?", "感謝を伝えるので Thank you. を使います。"),
        ("水がほしい人が言いそうなのは？", "I'm thirsty.", "I'm happy.", "I'm a bird.", "It's Monday.", "thirsty は「のどがかわいた」です。"),
        ("食べ物がほしい人が言いそうなのは？", "I'm hungry.", "I'm blue.", "I'm ten.", "Goodbye.", "hungry は空腹を表します。"),
        ("「I like red.」の人が選びそうな色は？", "red", "blue", "green", "yellow", "文中で好きだと言っている色は red です。"),
    ])
    add_rows(3, "応用", "語順", [
        ("「私は犬が好き」の正しい語順は？", "I like dogs.", "I dogs like.", "Like dogs I.", "Dogs I like.", "英語では I, like, dogs の順です。"),
        ("「これはペンです」の正しい英文は？", "It's a pen.", "A pen it's.", "Pen is I.", "This pen like.", "物の名前は It's a pen. と表せます。"),
        ("「青い丸」を表す正しい語順は？", "blue circle", "circle blue", "blue triangle", "red circle", "英語では色を形の前に置きます。"),
        ("「5匹の猫」を表す正しい語順は？", "five cats", "cats five", "five dogs", "cat five", "英語では数を名詞の前に置きます。"),
        ("「私は幸せです」の正しい英文は？", "I'm happy.", "Happy I'm.", "I happy like.", "It's happy me.", "I'm happy. で自分の気分を伝えます。"),
    ])
    add_rows(3, "応用", "文字", [
        ("並び「A, B, __, D」に入る文字は？", "C", "E", "G", "P", "A, B, C, D の順です。"),
        ("並び「F, G, __, I」に入る文字は？", "H", "E", "J", "K", "F, G, H, I の順です。"),
        ("「DOG」の最初の文字は？", "D", "O", "G", "B", "DOG は D から始まります。"),
        ("「CAT」の最後の文字は？", "T", "C", "A", "D", "CAT の最後は T です。"),
        ("「RED」と同じ最初の文字の単語は？", "rabbit", "dog", "cat", "blue", "RED と rabbit はどちらも R で始まります。"),
    ])


def build_grade_4() -> None:
    add_vocab(4, "天気", [
        ("晴れ", "sunny"), ("雨", "rainy"), ("くもり", "cloudy"),
        ("雪", "snowy"), ("風が強い", "windy"),
    ])
    add_vocab(4, "曜日", [
        ("月曜日", "Monday"), ("火曜日", "Tuesday"), ("金曜日", "Friday"),
        ("土曜日", "Saturday"), ("日曜日", "Sunday"),
    ])
    add_vocab(4, "日課", [
        ("起きる", "get up"), ("朝食を食べる", "eat breakfast"),
        ("学校へ行く", "go to school"), ("家へ帰る", "go home"),
        ("寝る", "go to bed"),
    ])
    add_vocab(4, "場所", [
        ("図書館", "library"), ("公園", "park"), ("駅", "station"),
        ("右", "right"), ("左", "left"),
    ])

    add_rows(4, "標準", "天気", [
        ("「How's the weather?」への返事は？", "It's sunny.", "It's Monday.", "It's seven.", "It's a pen.", "天気を聞かれたので It's sunny. と答えます。"),
        ("雨の日を表す英文は？", "It's rainy.", "It's sunny.", "It's windy.", "It's Sunday.", "rainy は雨の天気を表します。"),
        ("「It's cloudy.」の意味は？", "くもりです", "晴れです", "雪です", "火曜日です", "cloudy は「くもり」です。"),
    ])
    add_rows(4, "標準", "曜日", [
        ("「What day is it?」で尋ねているのは？", "曜日", "時刻", "天気", "場所", "What day は曜日を尋ねます。"),
        ("「今日は金曜日です」を表す英文は？", "It's Friday.", "It's five.", "It's rainy.", "I like Friday.", "曜日は It's Friday. のように答えます。"),
        ("Monday の2日後は何曜日？", "Wednesday", "Tuesday", "Thursday", "Sunday", "月曜日の2日後は水曜日です。"),
    ])
    add_rows(4, "標準", "時刻", [
        ("「What time is it?」で尋ねているのは？", "時刻", "曜日", "年齢", "天気", "What time は時刻を尋ねます。"),
        ("「It's seven.」が時刻を表すなら何時？", "7時", "5時", "10時", "12時", "seven は7を表します。"),
        ("7時に起きることを表す英文は？", "I get up at seven.", "I go home at seven.", "I am seven.", "Seven gets up.", "get up は起きる、at seven は7時にです。"),
    ])
    add_rows(4, "標準", "学校", [
        ("「Do you have a pen?」の意味は？", "ペンを持ってる？", "ペンが好き？", "ペンはどこ？", "ペンを使う？", "Do you have ...? は持っているかを尋ねます。"),
        ("ペンを持っているときの返事は？", "Yes, I do.", "No, I don't.", "It's a pen.", "I am a pen.", "持っているので Yes, I do. と答えます。"),
        ("本を持っていないときの返事は？", "No, I don't.", "Yes, I do.", "I like books.", "Open the book.", "持っていないので No, I don't. です。"),
    ])
    add_rows(4, "標準", "道案内", [
        ("「Turn right.」の意味は？", "右に曲がって", "左に曲がって", "まっすぐ進んで", "ここで止まって", "right は右、turn は曲がるです。"),
        ("「Go straight.」の意味は？", "まっすぐ進んで", "右に曲がって", "左に曲がって", "駅へ戻って", "go straight は「まっすぐ進む」です。"),
        ("図書館の場所を尋ねる英文は？", "Where is the library?", "What is the library?", "How many libraries?", "Do you like books?", "場所は Where is ...? で尋ねます。"),
    ])
    add_rows(4, "標準", "買い物", [
        ("りんごを2個頼む自然な英語は？", "Two apples, please.", "Two apple is.", "I am two apples.", "Apple two like.", "数と品物の後に please を付けて頼めます。"),
        ("店員の「How many apples?」で聞かれているのは？", "ほしいりんごの数", "好きな色", "行きたい場所", "今日の天気", "How many apples? は、ほしいりんごの数を尋ねています。"),
        ("30を表す英語は？", "thirty", "thirteen", "twenty", "three", "30 は thirty です。"),
    ])
    add_rows(4, "標準", "文字", [
        ("大文字「Q」に対応する小文字は？", "q", "p", "g", "d", "Q の小文字は q です。"),
        ("小文字「b」に対応する大文字は？", "B", "D", "P", "Q", "b の大文字は B です。"),
    ])

    add_rows(4, "応用", "会話", [
        ("会話「How's the weather?」「___」晴れなら？", "It's sunny.", "It's Sunday.", "At seven.", "In the park.", "晴れなので It's sunny. と答えます。"),
        ("会話「What day is it?」「___」月曜なら？", "It's Monday.", "It's sunny.", "It's one.", "I like Monday.", "曜日は It's Monday. と答えます。"),
        ("会話「What time is it?」「___」8時なら？", "It's eight.", "It's Friday.", "Eight books.", "I am eight.", "時刻は It's eight. と答えられます。"),
        ("会話「Do you have a ruler?」「___」肯定は？", "Yes, I do.", "Yes, I am.", "It's a ruler.", "At school.", "Do you ...? への肯定は Yes, I do. です。"),
        ("会話「Where is the park?」「___」に合う返事は？", "Go straight.", "It's rainy.", "I like parks.", "Three parks.", "場所を聞かれたので道案内が合います。"),
    ])
    add_rows(4, "応用", "文脈", [
        ("雨で傘が必要な日の天気は？", "rainy", "sunny", "cloudy", "windy", "雨の日は rainy です。"),
        ("木の葉が強く揺れている日の天気は？", "windy", "snowy", "sunny", "cloudy", "風が強い様子は windy です。"),
        ("朝7時に起き、8時に登校。get up は何時？", "at seven", "at eight", "on Monday", "in the park", "起きる時刻は7時です。"),
        ("今日はMonday。明日は何曜日？", "Tuesday", "Sunday", "Wednesday", "Friday", "月曜日の次は火曜日です。"),
        ("左に曲がった後まっすぐ進む指示は？", "Turn left. Go straight.", "Turn right. Stop.", "Go home. Sit down.", "It's left and sunny.", "左へ曲がり、その後まっすぐ進む順です。"),
    ])
    add_rows(4, "応用", "語順", [
        ("「私は7時に寝ます」の正しい英文は？", "I go to bed at seven.", "I seven bed go.", "At bed I seven.", "I am seven beds.", "I, go to bed, at seven の順です。"),
        ("「図書館はどこ？」の正しい英文は？", "Where is the library?", "Where the library is?", "What library where?", "Library is how many?", "場所は Where is ...? の語順で尋ねます。"),
        ("「今日は火曜日です」の正しい英文は？", "It's Tuesday.", "Tuesday it are.", "I Tuesday am.", "Tuesday likes it.", "曜日は It's Tuesday. と表します。"),
        ("「ペンを持っています」の正しい英文は？", "I have a pen.", "I pen have a.", "Have pen I.", "I am a pen.", "I, have, a pen の順です。"),
        ("「右に曲がって」の正しい語順は？", "Turn right.", "Right turn is.", "Go right turn.", "Right is turn.", "命令は Turn right. の順です。"),
    ])
    add_rows(4, "応用", "読み取り", [
        ("文「It's snowy. I have a coat.」季節は？", "冬", "春", "夏", "秋", "雪とコートが手がかりなので冬です。"),
        ("文「I go to bed at nine.」9時にすることは？", "寝る", "起きる", "登校する", "帰宅する", "go to bed は寝ることです。"),
        ("文「I have two pencils.」持っている数は？", "2本", "1本", "3本", "20本", "two は2を表します。"),
        ("文「The park is on your left.」公園はどちら？", "左", "右", "前", "後ろ", "on your left は「あなたの左」です。"),
        ("文「Sunday is sunny.」正しい組み合わせは？", "日曜・晴れ", "月曜・雨", "日曜・雪", "土曜・晴れ", "Sunday は日曜、sunny は晴れです。"),
    ])


def build_grade_5() -> None:
    add_vocab(5, "月", [
        ("1月", "January"), ("2月", "February"), ("4月", "April"),
        ("8月", "August"), ("12月", "December"),
    ])
    add_vocab(5, "教科", [
        ("算数", "math"), ("理科", "science"), ("音楽", "music"),
        ("図工", "art"), ("体育", "P.E."),
    ])
    add_vocab(5, "国", [
        ("日本", "Japan"), ("カナダ", "Canada"), ("インド", "India"),
        ("ブラジル", "Brazil"), ("オーストラリア", "Australia"),
    ])
    add_vocab(5, "できること", [
        ("泳ぐ", "swim"), ("料理する", "cook"), ("踊る", "dance"),
        ("歌う", "sing"), ("ピアノを弾く", "play the piano"),
    ])

    add_rows(5, "標準", "自己紹介", [
        ("「What's your name?」への自然な返事は？", "I'm Ken.", "I'm ten.", "I'm from Japan.", "I'm fine.", "名前を聞かれたので I'm Ken. と答えます。"),
        ("「Where are you from?」への返事は？", "I'm from Japan.", "I'm twelve.", "I like Japan.", "It's Japan.", "出身地は I'm from ... で答えます。"),
        ("名前のつづりを尋ねる英文は？", "How do you spell it?", "Where do you live?", "How old are you?", "What time is it?", "つづりは How do you spell it? と尋ねます。"),
        ("「How old are you?」で尋ねているのは？", "年齢", "名前", "出身地", "誕生日", "How old は年齢を尋ねます。"),
    ])
    add_rows(5, "標準", "誕生日", [
        ("「When is your birthday?」で尋ねているのは？", "誕生日", "年齢", "曜日", "出身地", "When は「いつ」を尋ねます。"),
        ("誕生日が5月なら使う月名は？", "May", "March", "June", "July", "5月は May です。"),
        ("「My birthday is in June.」の意味は？", "誕生日は6月", "誕生日は7月", "6月が好き", "6歳です", "June は6月を表します。"),
        ("October の次の月は？", "November", "September", "December", "August", "10月の次は11月です。"),
    ])
    add_rows(5, "標準", "時間割", [
        ("「What do you have today?」で尋ねているのは？", "今日の授業", "今日の天気", "今日の昼食", "今日の日付", "have はここでは授業があることを表します。"),
        ("「I have science.」の意味は？", "理科があります", "理科が好きです", "理科室です", "理科を教えます", "have science は理科の授業があることです。"),
        ("月曜に音楽があることを表す英文は？", "I have music on Monday.", "I like Monday music.", "Monday is music.", "Music has Monday.", "曜日の前に on を置き、I have music on Monday. と表します。"),
        ("「What's your favorite subject?」で聞くのは？", "好きな教科", "得意な運動", "好きな曜日", "将来の夢", "favorite subject は好きな教科です。"),
    ])
    add_rows(5, "標準", "できること", [
        ("「I can swim.」の意味は？", "私は泳げます", "私は泳ぎました", "私は泳ぎたい", "私は泳ぎません", "can は「できる」を表します。"),
        ("「Can you cook?」への肯定の返事は？", "Yes, I can.", "Yes, I do.", "Yes, I am.", "It's cooking.", "Can you ...? には Yes, I can. と答えます。"),
        ("ピアノを弾けないことを表す英文は？", "I can't play the piano.", "I can play the piano.", "I don't like the piano.", "I have a piano.", "can't は「できない」を表し、楽器のピアノには the を付けます。"),
        ("「What can you do?」への自然な返事は？", "I can dance.", "I'm from Japan.", "It's sunny.", "On Monday.", "できることを I can ... で答えます。"),
    ])
    add_rows(5, "標準", "欲しい物と場所", [
        ("「What do you want?」への自然な返事は？", "I want a ball.", "I am a ball.", "I can ball.", "It's Monday.", "欲しい物は I want ... で答えます。"),
        ("「Where is the library?」で尋ねているのは？", "図書館の場所", "図書館の数", "図書館の時間", "図書館の本", "Where は場所を尋ねます。"),
        ("机の下にある本を表す英文は？", "It's under the desk.", "It's on the desk.", "I read under books.", "The desk is a book.", "under the desk は「机の下に」を表します。"),
        ("店でピザを頼む自然な表現は？", "I'd like pizza.", "I am pizza.", "Pizza can I.", "I went pizza.", "I'd like ... は丁寧な注文表現です。"),
    ])

    add_rows(5, "応用", "会話", [
        ("会話「Where are you from?」「___」に合う返事は？", "I'm from Canada.", "I'm eleven.", "I can swim.", "It's in Canada.", "出身地を聞かれたので国を答えます。"),
        ("会話「When is your birthday?」「___」に合う返事は？", "In April.", "I'm April.", "It's Tuesday.", "I like birthdays.", "誕生月は In April. と答えられます。"),
        ("会話「Can you dance?」「___」否定の返事は？", "No, I can't.", "No, I don't.", "No, I'm not.", "I dance no.", "Can you ...? の否定は No, I can't. です。"),
        ("会話「What do you want?」「___」に合う返事は？", "I want a cap.", "I am a cap.", "I can cap.", "At the shop.", "欲しい物を I want ... で答えます。"),
        ("会話「What subject do you like?」「___」理科なら？", "Science.", "Sunday.", "Sunny.", "September.", "好きな教科を聞かれたので Science. と答えます。"),
    ])
    add_rows(5, "応用", "文脈", [
        ("文「I can cook, but I can't swim.」できるのは？", "料理", "水泳", "料理と水泳", "どちらも不可", "can cook とあるので料理ができます。"),
        ("文「I have math on Friday.」授業はいつ？", "金曜日", "月曜日", "5月", "毎日", "Friday は金曜日です。"),
        ("文「My birthday is in August.」誕生月は？", "8月", "4月", "10月", "12月", "August は8月です。"),
        ("文「The ball is under the desk.」ボールはどこ？", "机の下", "机の上", "机の横", "かばんの中", "under the desk は机の下です。"),
        ("文「I want juice, not milk.」欲しい物は？", "ジュース", "牛乳", "水", "お茶", "not milk とあり、欲しいのは juice です。"),
    ])
    add_rows(5, "応用", "語順", [
        ("「私はカナダ出身です」の正しい英文は？", "I'm from Canada.", "I'm Canada from.", "From Canada I.", "Canada is me.", "I'm from の後に国名を置きます。"),
        ("「あなたは泳げますか」の正しい英文は？", "Can you swim?", "Can swim you?", "Do can you swim?", "Swim you are?", "質問では Can を文の先頭に置きます。"),
        ("「誕生日はいつ？」の正しい英文は？", "When is your birthday?", "Where your birthday?", "What birthday is?", "How many birthday?", "時を尋ねる When を先頭に置きます。"),
        ("「私は赤い帽子がほしい」の正しい英文は？", "I want a red cap.", "I red want cap.", "Want cap red I.", "I am a red cap.", "I want の後に欲しい物を置きます。"),
        ("「本は机の上です」の正しい英文は？", "It's on the desk.", "It's under the desk.", "On desk it the.", "I have on desk.", "on the desk は「机の上に」を表します。"),
    ])
    add_rows(5, "応用", "読み取り", [
        ("文「I'm Aya. I'm from Japan.」出身国は？", "日本", "カナダ", "インド", "不明", "from Japan が出身国を示します。"),
        ("文「Art is on Tuesday. Music is on Friday.」金曜は？", "音楽", "図工", "算数", "理科", "Music is on Friday. とあるので金曜は音楽です。"),
        ("文「Ken can sing and dance.」できることは？", "歌とダンス", "料理と水泳", "歌だけ", "ダンスだけ", "sing and dance の両方ができます。"),
        ("文「Go straight. Turn left.」最初にすることは？", "まっすぐ進む", "左に曲がる", "右に曲がる", "止まる", "最初の指示は Go straight. です。"),
        ("文「I'd like two apples.」注文した数は？", "2個", "1個", "3個", "12個", "two は2を表します。"),
    ])


def build_grade_6() -> None:
    add_vocab(6, "過去", [
        ("行った", "went"), ("食べた", "ate"), ("見た", "saw"),
        ("楽しんだ", "enjoyed"), ("訪れた", "visited"),
    ])
    add_vocab(6, "職業", [
        ("医者", "doctor"), ("教師", "teacher"), ("獣医", "vet"),
        ("料理人", "cook"), ("宇宙飛行士", "astronaut"),
    ])
    add_vocab(6, "世界", [
        ("フランス", "France"), ("エジプト", "Egypt"), ("中国", "China"),
        ("イタリア", "Italy"), ("アメリカ", "the USA"),
    ])
    add_vocab(6, "環境", [
        ("地球", "Earth"), ("海", "ocean"), ("森", "forest"),
        ("川", "river"), ("絶滅の危機", "endangered"),
    ])

    add_rows(6, "標準", "過去", [
        ("「I went to Kyoto.」の意味は？", "京都へ行きました", "京都へ行きます", "京都へ行きたい", "京都から来ました", "went は go の過去を表します。"),
        ("「I ate curry.」の意味は？", "カレーを食べた", "カレーを作る", "カレーがほしい", "カレーが嫌い", "ate は eat の過去を表します。"),
        ("「We saw a big bird.」の意味は？", "大きな鳥を見た", "大きな鳥を飼う", "大きな鳥になった", "鳥が見えない", "saw は see の過去を表します。"),
        ("「I enjoyed the trip.」の意味は？", "旅行を楽しんだ", "旅行を計画する", "旅行を中止した", "旅行へ行きたい", "enjoyed は「楽しんだ」です。"),
        ("昨日したことを表す文はどれ？", "I played soccer.", "I play soccer.", "I can play soccer.", "I like soccer.", "played は過去の出来事を表します。"),
    ])
    add_rows(6, "標準", "将来", [
        ("「I want to be a vet.」の意味は？", "獣医になりたい", "獣医に会いたい", "獣医ではない", "獣医を手伝った", "want to be は「〜になりたい」です。"),
        ("将来の夢を尋ねる英文は？", "What do you want to be?", "Where did you go?", "What time is it?", "Can you swim?", "want to be を使って将来の夢を尋ねます。"),
        ("教師になりたいことを表す英文は？", "I want to be a teacher.", "I am a teacher now.", "I saw a teacher.", "I teach want.", "I want to be の後に職業を置きます。"),
        ("「Why?」と理由を聞かれた返事に合うのは？", "I like helping people.", "At seven.", "In August.", "Three books.", "Why? には理由を答えます。"),
        ("「My dream is to cook.」の意味は？", "夢は料理をすること", "昨日料理をした", "料理が食べたい", "料理人に会った", "dream は将来の夢を表します。"),
    ])
    add_rows(6, "標準", "世界と文化", [
        ("「I want to visit Italy.」の意味は？", "イタリアを訪れたい", "イタリア出身です", "イタリアに住んだ", "イタリアが嫌い", "want to visit は「訪れたい」です。"),
        ("エジプトを表す英語は？", "Egypt", "India", "Italy", "Brazil", "エジプトは Egypt と表します。"),
        ("「Where do you want to go?」で尋ねるのは？", "行きたい場所", "住んでいる場所", "昨日いた場所", "生まれた場所", "want to go は行きたい場所を表します。"),
        ("「You can see the Eiffel Tower.」国は？", "France", "Italy", "Egypt", "Canada", "エッフェル塔がある国はフランスです。"),
        ("「I like Chinese food.」で好きなものは？", "中国料理", "中国語", "中国の音楽", "中国の学校", "Chinese food は中国料理です。"),
    ])
    add_rows(6, "標準", "生活と環境", [
        ("「I usually walk to school.」の意味は？", "たいてい歩いて登校", "昨日歩いて登校", "学校まで走りたい", "学校では歩かない", "usually は「たいてい」を表します。"),
        ("「Save the animals.」の意味は？", "動物を守ろう", "動物を数えよう", "動物を見た", "動物を描こう", "save はここでは「守る」です。"),
        ("「Don't waste water.」の意味は？", "水を無駄にしないで", "水を飲まないで", "水を運んで", "川で泳いで", "waste water は水を無駄にすることです。"),
        ("「The panda is endangered.」の意味は？", "パンダは絶滅の危機", "パンダは元気", "パンダは大きい", "パンダは泳げる", "endangered は絶滅の危機にあることです。"),
        ("地球を守る行動として自然な英文は？", "Let's recycle.", "Let's waste water.", "Let's cut all trees.", "Let's drop trash.", "recycle は資源を再利用することです。"),
    ])

    add_rows(6, "応用", "会話", [
        ("会話「Where did you go?」「___」に合う返事は？", "I went to Nara.", "I go every day.", "I can go.", "I like Nara.", "過去の場所を I went to ... で答えます。"),
        ("会話「What did you eat?」「___」に合う返事は？", "I ate sushi.", "I eat at seven.", "I want sushi.", "Sushi is Japan.", "過去に食べた物を I ate ... で答えます。"),
        ("会話「What do you want to be?」「___」に合う返事は？", "I want to be a cook.", "I ate with a cook.", "I can cook rice.", "Cook is my lunch.", "将来の夢を I want to be ... で答えます。"),
        ("会話「Why do you like it?」「___」に合う返事は？", "Because it's fun.", "At the park.", "Last Sunday.", "Three times.", "Why には because を使って理由を答えられます。"),
        ("会話「How was your trip?」「___」に合う返事は？", "It was great.", "It's next week.", "I go by bus.", "In Canada.", "過去の感想には It was ... が合います。"),
    ])
    add_rows(6, "応用", "文脈", [
        ("文「I went to the zoo and saw pandas.」見たのは？", "パンダ", "鳥", "ライオン", "魚", "saw pandas と書かれています。"),
        ("文「I ate pizza, but I didn't eat salad.」食べたのは？", "ピザ", "サラダ", "両方", "どちらもなし", "ate pizza とあり、salad は食べていません。"),
        ("文「I want to be a vet. I love animals.」夢は？", "獣医", "医者", "教師", "料理人", "want to be a vet が将来の夢です。"),
        ("文「I visited France and saw a tower.」訪問国は？", "フランス", "イタリア", "インド", "日本", "visited France と書かれています。"),
        ("文「I recycle cans every week.」していることは？", "缶の再利用", "水の節約", "植樹", "ごみ拾い", "recycle cans は缶を再利用することです。"),
    ])
    add_rows(6, "応用", "語順", [
        ("「私は京都へ行きました」の正しい英文は？", "I went to Kyoto.", "I go to Kyoto.", "Went Kyoto I to.", "I want Kyoto.", "過去の移動は I went to ... と表します。"),
        ("「何を食べましたか」の正しい英文は？", "What did you eat?", "What do you ate?", "Did what you ate?", "Where did you eat?", "過去の質問は What did you eat? の語順です。"),
        ("「医者になりたい」の正しい英文は？", "I want to be a doctor.", "I want be doctor.", "I am want a doctor.", "Doctor wants me.", "want to be の後に職業を置きます。"),
        ("「旅行は楽しかった」の正しい英文は？", "The trip was fun.", "The trip is tomorrow.", "Was trip the fun.", "I fun the trip.", "過去の感想は was を使って表せます。"),
        ("「動物を守ろう」の正しい英文は？", "Let's save animals.", "Let's animals save.", "Save let's animals.", "Animals are let's.", "Let's の後に動作を表す語を置きます。"),
    ])
    add_rows(6, "応用", "読み取り", [
        ("文「Last Sunday, I played tennis.」いつした？", "先週の日曜日", "今週の月曜日", "来週の日曜日", "毎週土曜日", "Last Sunday は先週の日曜日です。"),
        ("文「Mika saw dolphins in Australia.」場所は？", "オーストラリア", "日本", "カナダ", "イタリア", "in Australia が場所を示します。"),
        ("文「Ken wants to teach children.」向く職業は？", "教師", "獣医", "料理人", "宇宙飛行士", "children に教える職業は教師です。"),
        ("文「Use both sides of paper.」環境に良い理由は？", "紙を節約できる", "水を増やせる", "空気を暖める", "動物を数える", "紙の両面を使うと使用量を減らせます。"),
        ("文「I got up at six, then ate breakfast.」先は？", "起きた", "朝食を食べた", "登校した", "寝た", "then の前に get up が書かれています。"),
    ])


def validate_bank() -> None:
    seen_questions: set[str] = set()
    for grade, items in QUESTIONS.items():
        if len(items) < 60:
            raise ValueError(f"grade {grade}: expected at least 60 questions, got {len(items)}")
        tier_counts = {"基本": 0, "標準": 0, "応用": 0}
        genres: set[str] = set()
        answer_slots = [0, 0, 0, 0]
        for item in items:
            question = str(item["q"])
            choices = [str(value) for value in item["c"]]
            answer = int(item["a"])
            if question in seen_questions:
                raise ValueError(f"duplicate question: {question}")
            seen_questions.add(question)
            if len(question) > 50:
                raise ValueError(f"question exceeds 50 characters: {question}")
            if len(choices) != 4 or len(set(choices)) != 4:
                raise ValueError(f"invalid choices: {question}")
            if any(not choice or len(choice) > 24 for choice in choices):
                raise ValueError(f"choice exceeds 24 characters: {question} -> {choices}")
            if not 0 <= answer < 4:
                raise ValueError(f"invalid answer index: {question}")
            answer_slots[answer] += 1
            genres.add(str(item["g"]))
            for tier in tier_counts:
                if question.startswith(f"【{tier}】"):
                    tier_counts[tier] += 1
        if min(tier_counts.values()) < 19:
            raise ValueError(f"grade {grade}: unbalanced tiers {tier_counts}")
        if len(genres) < 5:
            raise ValueError(f"grade {grade}: too few genres {genres}")
        if max(answer_slots) - min(answer_slots) > 1:
            raise ValueError(f"grade {grade}: unbalanced answer slots {answer_slots}")
        print(f"grade {grade}: {len(items)} questions, tiers={tier_counts}, genres={len(genres)}")


def append_to_active_bank() -> None:
    original = BANK_PATH.read_text(encoding="utf-8")
    active = json.loads(original)
    if "英語" in active:
        raise RuntimeError("offline_bank.json already contains 英語; refusing to overwrite it")
    closing = original.rfind("}")
    if closing < 0:
        raise RuntimeError("offline_bank.json has no closing object brace")
    fragment = json.dumps({"英語": QUESTIONS}, ensure_ascii=False, indent=2)
    inner = fragment[2:-2]
    newline = "\r\n" if "\r\n" in original else "\n"
    inner = inner.replace("\n", newline)
    updated = original[:closing].rstrip() + "," + newline + inner + newline + "}" + newline
    json.loads(updated)
    BANK_PATH.write_text(updated, encoding="utf-8", newline="")
    print(f"appended {sum(len(items) for items in QUESTIONS.values())} English questions")


def main() -> None:
    build_grade_3()
    # One additional standard question keeps all three grade-3 tiers at 20.
    add_rows(3, "標準", "文字", [
        ("大文字の並び「L, M, __」に入る文字は？", "N", "K", "O", "P", "L, M, N の順です。"),
    ])
    build_grade_4()
    build_grade_5()
    build_grade_6()
    validate_bank()
    append_to_active_bank()


if __name__ == "__main__":
    main()
