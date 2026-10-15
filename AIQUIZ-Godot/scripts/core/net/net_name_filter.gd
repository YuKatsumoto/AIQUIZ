class_name NetNameFilter
extends RefCounted

## オンライン対戦で相手に見える「なまえ」の検査。
## ランダムマッチでは知らない子ども同士がつながるので、使える文字・長さ・数字の数を絞り、
## 悪口や下品な言葉、学校が分かる言葉を弾く。リレー（relay-server/relay/name_filter.py）でも
## 同じ規則で必ず検査する。NG_WORDS は両方で同じ内容に保つ（relay のテストが照合する）。

const MAX_LENGTH := 12
const MAX_DIGITS := 3

enum Result { OK, EMPTY, TOO_LONG, BAD_CHAR, TOO_MANY_DIGITS, NG_WORD }

# NG_WORDS_BEGIN（ひらがな・英小文字。照合前に名前もひらがな・小文字へそろえる）
const NG_WORDS: Array[String] = [
	"しね", "しんで", "ころす", "ころせ", "ころして", "きえろ", "きもい", "きしょい", "うざ",
	"ばか", "あほ", "くず", "ごみ", "ぶす", "でぶ", "ぶさいく", "のろま", "ざこ", "くそ",
	"うんこ", "うんち", "ちんこ", "ちんちん", "まんこ", "おっぱい", "せっくす", "えっち", "えろ",
	"ぱんつ", "へんたい", "ちかん", "ばばあ", "じじい", "きちがい", "がいじ",
	"死", "殺", "糞", "馬鹿", "阿呆", "屑", "変態", "痴漢", "乳",
	"がっこう", "学校", "しょうがく", "小学", "ちゅうがく", "中学",
	"fuck", "shit", "sex", "porn", "kill", "bitch", "dick", "pussy", "penis", "nazi", "hitler",
	"idiot", "stupid", "baka", "aho", "unko", "chinko", "manko", "oppai", "ecchi", "kimoi", "kuso",
]
# NG_WORDS_END

const _SYMBOLS := "ー・★☆♪"


static func check(raw: String) -> Result:
	var name := normalize(raw)
	if name.is_empty():
		return Result.EMPTY
	if name.length() > MAX_LENGTH:
		return Result.TOO_LONG
	var digits := 0
	for i in range(name.length()):
		var code := name.unicode_at(i)
		if not _allowed(code):
			return Result.BAD_CHAR
		if code >= 0x30 and code <= 0x39:
			digits += 1
	if digits > MAX_DIGITS:
		return Result.TOO_MANY_DIGITS
	var folded := _fold(name)
	for word in NG_WORDS:
		if folded.contains(word):
			return Result.NG_WORD
	return Result.OK


static func is_ok(raw: String) -> bool:
	return check(raw) == Result.OK


## 子ども向けの理由。ロビーで入力欄の下に出す。
static func message(result: Result) -> String:
	match result:
		Result.EMPTY:
			return "なまえを いれてね（サイコロでも きめられるよ）"
		Result.TOO_LONG:
			return "なまえは %d もじ までだよ" % MAX_LENGTH
		Result.BAD_CHAR:
			return "つかえない もじが あるよ（ひらがな・カタカナ・かんじ・えいすうじ）"
		Result.TOO_MANY_DIGITS:
			return "すうじは %d こ までだよ" % MAX_DIGITS
		Result.NG_WORD:
			return "その なまえは つかえないよ"
	return ""


## 前後の空白を除き、全角英数字を半角にそろえる（リレーの NFKC と同じ結果になる範囲）。
static func normalize(raw: String) -> String:
	var out := ""
	for i in range(raw.length()):
		var code := raw.unicode_at(i)
		if code >= 0xFF01 and code <= 0xFF5E:
			code -= 0xFEE0
		elif code == 0x3000:
			code = 0x20
		out += String.chr(code)
	return out.strip_edges()


static func _allowed(code: int) -> bool:
	return (
		(code >= 0x3041 and code <= 0x3096)  # ひらがな
		or (code >= 0x30A1 and code <= 0x30FA)  # カタカナ
		or (code >= 0x4E00 and code <= 0x9FFF)  # 漢字
		or code == 0x3005  # 々
		or (code >= 0x30 and code <= 0x39)
		or (code >= 0x41 and code <= 0x5A)
		or (code >= 0x61 and code <= 0x7A)
		or _SYMBOLS.contains(String.chr(code))
	)


## 照合用: カタカナ→ひらがな、小書き→大きい字、英字→小文字、記号を除く（「しーね」「シネ」も捕まえる）。
static func _fold(name: String) -> String:
	const SMALL := "ぁぃぅぇぉっゃゅょゎ"
	const LARGE := "あいうえおつやゆよわ"
	var out := ""
	for i in range(name.length()):
		var code := name.unicode_at(i)
		if code >= 0x30A1 and code <= 0x30F6:
			code -= 0x60
		var ch := String.chr(code).to_lower()
		var small := SMALL.find(ch)
		if small >= 0:
			ch = LARGE[small]
		if _SYMBOLS.contains(ch):
			continue
		out += ch
	return out
