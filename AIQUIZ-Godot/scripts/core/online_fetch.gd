extends Node
class_name OnlineFetch

signal fetch_completed(quizzes: Array[QuizItem])
signal fetch_partial(quizzes: Array[QuizItem])

func extract_json_from_text(text: String) -> Variant:
	text = text.strip_edges()
	if text.begins_with("```json"):
		text = text.substr(7)
	elif text.begins_with("```"):
		text = text.substr(3)
	if text.ends_with("```"):
		text = text.substr(0, text.length() - 3)
	text = text.strip_edges()
	
	if text.is_empty():
		return null
		
	var starts := []
	for i in range(text.length()):
		if text[i] == "[" or text[i] == "{":
			starts.append(i)
	if starts.is_empty():
		return null
	
	var ends := []
	for i in range(text.length() - 1, -1, -1):
		if text[i] == "]" or text[i] == "}":
			ends.append(i)
	if ends.is_empty():
		return null
	
	var json := JSON.new()
	for start in starts:
		for end in ends:
			if end < start:
				continue
			var sub := text.substr(start, end - start + 1)
			var err := json.parse(sub)
			if err == OK:
				return json.get_data()
	return null

func extract_quizzes_from_text(raw_text: String) -> Array:
	var obj = extract_json_from_text(raw_text)
	if obj == null:
		return []
	if obj is Array:
		var arr := []
		for x in obj:
			if x is Dictionary:
				arr.append(x)
		return arr
	if obj is Dictionary:
		var quizzes = obj.get("quizzes", [])
		if quizzes is Array:
			var arr := []
			for x in quizzes:
				if x is Dictionary:
					arr.append(x)
			return arr
	return []

func normalize_single(raw: Dictionary, src: String) -> QuizItem:
	var q := str(raw.get("q", "")).strip_edges()
	var c_raw = raw.get("c", [])
	var a = raw.get("a", null)
	var e := str(raw.get("e", raw.get("exp", ""))).strip_edges()
	
	if q.is_empty() or not (c_raw is Array) or (c_raw.size() != 2 and c_raw.size() != 4):
		return null
		
	var a_int: int
	if typeof(a) == TYPE_INT:
		a_int = a
	elif typeof(a) == TYPE_FLOAT:
		a_int = int(a)
	elif typeof(a) == TYPE_STRING and (a as String).is_valid_int():
		a_int = int(a)
	else:
		return null
	
	if a_int < 0 or a_int >= c_raw.size():
		return null
		
	var cleaned: PackedStringArray = []
	for x in c_raw:
		var s := str(x).strip_edges()
		if s.is_empty(): return null
		cleaned.append(s)
		
	# AI予測解答時間をパース
	var t_raw = raw.get("t", null)
	var est_sec: float = 4.0
	if t_raw != null:
		if typeof(t_raw) == TYPE_FLOAT:
			est_sec = clampf(t_raw, 1.5, 10.0)
		elif typeof(t_raw) == TYPE_INT:
			est_sec = clampf(float(t_raw), 1.5, 10.0)
		elif typeof(t_raw) == TYPE_STRING and (t_raw as String).is_valid_float():
			est_sec = clampf(float(t_raw), 1.5, 10.0)
	
	var item := QuizItem.new()
	item.q = q
	item.c = cleaned
	item.a = a_int
	item.e = e
	item.src = src
	item.estimated_seconds = est_sec
	return item

## システムインストラクション（ロール設定）を生成
## generationConfig.systemInstruction に渡す
func compose_system_instruction() -> String:
	var sys := "あなたは日本の小学校で20年以上の指導経験を持つベテラン教員です。\n"
	sys += "文部科学省の学習指導要領に完全準拠した、高品質なクイズ問題を生成します。\n"
	sys += "クイズは3Dランナーゲーム内で使われるため、問題文は短く明瞭にしてください（50文字以内）。\n"
	sys += "【重要】算数の問題は、計算用紙なしで暗算だけで解ける難易度にしてください。\n"
	sys += "大きな桁数の計算・複雑な筆算を必要とする問題は禁止です。\n"
	sys += "出力は常にJSON配列のみ。マークダウン装飾や説明文は一切含めないでください。\n"
	return sys

## 難易度に応じた temperature を返す
func get_temperature_for_difficulty(difficulty: String, retry_count: int = 0) -> float:
	var base: float
	match difficulty:
		"簡単":
			base = 0.3
		"普通":
			base = 0.5
		"難しい":
			base = 0.7
		_:
			base = 0.45
	# リトライ時は少し上げて多様性を出す
	base += retry_count * 0.1
	return clampf(base, 0.1, 1.0)

func compose_prompt(subject: String, grade: int, difficulty: String, count: int, history: Array[String], is_coop: bool = false) -> String:
	var prompt := ""

	# ── 基本条件 ──
	prompt += "【基本条件】\n"
	prompt += "- 対象: 小学%d年生の%s\n" % [grade, subject]
	prompt += "- 難易度: %s\n" % difficulty
	prompt += "- 問題数: %d問\n" % count
	prompt += "- 形式: 4択（推奨）または 2択\n"
	prompt += "- 問題文(q)は50文字以内に収めること。長い文章題でも簡潔に書くこと\n"
	prompt += "- 解説文(e)は20文字以内で、なぜその答えになるか核心だけ書くこと\n"
	prompt += "- 選択肢(c)は各15文字以内に収めること\n"
	prompt += "- 予測解答時間(t)を各問題に付けること。対象学年の生徒が問題を読んで答えるまでの秒数（小数第1位）\n"
	prompt += "  目安: 即答=2.0, 標準=4.0, 思考問題=6.0, 難問=8.0\n\n"

	# ── 学年×教科別カリキュラムデータ ──
	var curriculum := _get_curriculum(grade, subject)
	
	# ── 案1: Few-Shot強化 — QuizOptimizer から JSON形式の例を注入 ──
	if QuizManager.quiz_optimizer != null:
		var feedback = QuizManager.quiz_optimizer.get_feedback_examples_json(subject, grade, 5)
		for b in feedback["bad"]:
			curriculum["bad_examples"].append(b)
		for g in feedback["good_json"]:
			curriculum["good_json_examples"].append(g)
		for g_text in feedback["good"]:
			curriculum["examples"].append(g_text)
			
	prompt += "【小学%d年生・%sのカリキュラム情報】\n" % [grade, subject]
	prompt += "＜学習単元＞ %s\n" % curriculum["topics"]
	prompt += "＜この学年のキーワード＞ %s\n" % curriculum["keywords"]
	
	# ── 案6: 重要概念（JSONデータから注入） ──
	if curriculum.has("key_concepts") and curriculum["key_concepts"].size() > 0:
		prompt += "＜重要概念・公式＞\n"
		for kc: String in curriculum["key_concepts"]:
			prompt += "  ・%s\n" % kc
		prompt += "→ 上記の概念を問う問題を出してください\n"
	
	# ── 案6: 出題範囲の明示 ──
	if curriculum.has("selected_unit_names") and curriculum["selected_unit_names"].size() > 0:
		prompt += "＜★出題範囲（以下の単元から出題せよ）＞\n"
		for uname in curriculum["selected_unit_names"]:
			prompt += "  - %s\n" % str(uname)
	
	# ── 案6: ありがちな間違い ──
	if curriculum["typical_mistakes"].size() > 0:
		prompt += "＜生徒がよくやる間違い（誤答のヒント）＞\n"
		for m: String in curriculum["typical_mistakes"]:
			prompt += "  - %s\n" % m
		prompt += "→ 上記の間違いを誤答選択肢に反映してください\n"
	
	prompt += "＜良い問題の例＞\n"
	for ex: String in curriculum["examples"]:
		prompt += "  - %s\n" % ex
	
	# ── 案1: JSON形式の良問例（Few-Shot） ──
	if curriculum["good_json_examples"].size() > 0:
		prompt += "\n＜出力参考例（JSON）＞\n"
		for json_ex: String in curriculum["good_json_examples"]:
			prompt += "%s\n" % json_ex
	prompt += "\n"

	# ── 絶対禁止事項（全難易度共通） ──
	prompt += "【絶対禁止事項 ― 違反すると不合格】\n"
	prompt += "- %d年生より下の学年で習う内容を出題すること\n" % grade
	if grade >= 3:
		prompt += "- 「偶数はどれ？」「一番大きい数は？」「〇×〇＝？」のような低学年レベルの一問一答\n"
	if grade >= 4:
		prompt += "- 単純な九九・1桁の足し引き算・2桁同士の足し算のような%d年生には簡単すぎる問題\n" % grade
	prompt += "- 同じ単元・パターンの問題ばかり出すこと（%d問すべて異なる単元から出題せよ）\n" % count
	prompt += "- 正解が曖昧な問題や、複数の選択肢が正解になりうる問題\n"
	prompt += "- 選択肢に「わからない」「どれでもない」を含めること\n"
	if subject == "算数":
		prompt += "- 【算数限定】3桁以上の数同士の計算を必要とする問題（暗算で解けない問題）\n"
		prompt += "- 【算数限定】このゲームは計算用紙がないため、筆算が必要な問題は全難易度で禁止\n"
	
	# ── bad_examples ──
	if curriculum["bad_examples"].size() > 0:
		prompt += "- ↓以下のような問題は品質が低いので生成禁止↓\n"
		for bad: String in curriculum["bad_examples"]:
			prompt += "  × %s\n" % bad
	prompt += "\n"

	# ── 難易度別の詳細指示 ──
	if difficulty == "簡単":
		prompt += _compose_easy_instructions(grade, subject, curriculum)
	elif difficulty == "普通":
		prompt += _compose_normal_instructions(grade, subject, curriculum)
	elif difficulty == "難しい":
		prompt += _compose_hard_instructions(grade, subject, curriculum)

	# ── 案3: プレイヤー行動分析フィードバック ──
	if QuizManager.player_analytics != null:
		var analytics_feedback := QuizManager.player_analytics.get_prompt_feedback(subject, grade, difficulty)
		if not analytics_feedback.is_empty():
			prompt += analytics_feedback

	# ── AI自己チェック・多様性と重複の絶対禁止 ──
	prompt += "【AI自己チェック・重複絶対禁止】（超重要 ― ここが最も重要な制約）\n"
	prompt += "- %d問の中で一切の重複を許さない。出力前に全問題ペアを比較し、以下のいずれかに該当する場合は片方を別の問題に差し替えること:\n" % count
	prompt += "  (a) まったく同じ問題文\n"
	prompt += "  (b) 数値・単語を変えただけの類似問題（例:「3+5は？」と「4+6は？」は同パターン）\n"
	prompt += "  (c) 聞き方を変えただけの同じ知識を問う問題（例:「半径と直径の関係は？」と「直径は半径の何倍？」）\n"
	prompt += "  (d) 同じ公式・概念を別の数値で問う問題（例:面積問題が2つ以上）\n"
	prompt += "- %d問すべて『完全に異なる単元・トピック』から出題すること。同じ単元から2問以上出さないこと。\n" % count
	prompt += "- 計算問題・知識問題・思考問題をバランスよく混ぜること\n"
	prompt += "- 正解の位置(a)を0〜3で均等に散らすこと（全部0や全部1にしない）\n"
	prompt += "- 4択と2択を任意に混ぜて出題すること\n"
	if history.size() > 0:
		prompt += "- 【出題済みリスト】以下の問題は既に出題済みなので、同じ問題・類似の問題は絶対に出さないこと:\n"
		var max_h = min(30, history.size())
		for i in range(max_h):
			prompt += "  × " + history[history.size() - 1 - i] + "\n"
	prompt += "\n"

	# ── 協力モード用追加指示 ──
	if is_coop:
		prompt += "【協力モード（分割問題）追加指示 - 厳守】\n"
		prompt += "この問題は2人協力モードで出題され、内部ロジックで自動的に「P1用ヒント」と「P2用答え」に分割されます。\n"
		prompt += "分割抽出が失敗しないよう、問題文(q)と正解(c)の形式を以下の教科ルールに『厳格に』従ってください:\n"
		match subject:
			"算数":
				prompt += "- 問題文(q)には必ず「3 + 4」や「12 × 3」のような『計算式』を半角記号等で明確に含めること。\n"
				prompt += "- 正解(c)は必ずその計算の「答え（数値や単位付き数値）」にすること。\n"
			"理科":
				prompt += "- 問題文(q)の核心となるヒントやキーワードを必ず「」で囲むこと。\n"
				prompt += "- 正解(c)はその現象・物質・生物などの「正式な名称（短い単語）」にすること。\n"
			"国語":
				prompt += "- 漢字の「読み」または「書き」を問う問題を中心に出すこと。\n"
				prompt += "- 問題文(q)には対象となる漢字やひらがなを必ず「」で囲むこと。（例：「時計」の読みは？）\n"
			"社会":
				prompt += "- 歴史の人物や出来事、地理の地名、用語などを問うこと。\n"
				prompt += "- 問題文(q)の手がかりとなるキーワードは必ず「」で囲むこと。\n"
			_:
				prompt += "- 問題文(q)の最も重要なキーワードやヒントは、必ず「」で囲んで強調すること。\n"
		prompt += "- ※出力フォーマットは通常のJSON（q, c, a, e）のままですが、上記ルールを満たさないとゲーム側での分割処理がエラーになります。\n\n"

	return prompt

# ── カリキュラムデータベース ──

func _get_curriculum(grade: int, subject: String) -> Dictionary:
	# ── 案6: 教科書DB（JSONファイル）を優先的に使用 ──
	var db_data := CurriculumDB.build_curriculum(subject, grade, 3)
	if not db_data.is_empty():
		return db_data
	
	# ── フォールバック: JSONがない場合は従来のハードコード ──
	var data: Dictionary = {
		"topics": "", "keywords": "", "examples": [] as Array[String],
		"easy_desc": "", "normal_desc": "", "hard_desc": "",
		"bad_examples": [] as Array[String],
		"typical_mistakes": [] as Array[String],
		"good_json_examples": [] as Array[String]
	}

	# ── 算数 ──
	if subject == "算数":
		match grade:
			1:
				data["topics"] = "繰り上がり・繰り下がりのたし算ひき算、20より大きい数、時計（何時何分）、長さくらべ・かさくらべ、かたちあそび（立体・平面図形の弁別）"
				data["keywords"] = "繰り上がり, 繰り下がり, 10のまとまり, 時計, 長い・短い, 多い・少ない, まえ・うしろ, 三角・四角・丸"
				data["examples"] = [
					"9+6はいくつ？（繰り上がり）",
					"15−8はいくつ？（繰り下がり）",
					"時計が3時30分を指しているとき、長いはりはどの数字？",
					"□＋7＝13、□に入る数は？",
				]
				data["bad_examples"] = ["3+2は？（簡単すぎ）", "1+1は？"]
				data["typical_mistakes"] = [
					"繰り上がりで10の位への加算を忘れる（9+6=6と答える）",
					"繰り下がりで引けないとき引く数と引かれる数を逆にする",
					"時計の長い針と短い針を取り違える",
				]
			2:
				data["topics"] = "かけ算（九九すべて）、1000までの数、たし算ひき算の筆算（3桁）、長さの単位（cm, mm, m）、かさの単位（L, dL, mL）、時刻と時間、三角形と四角形、箱の形"
				data["keywords"] = "九九, 筆算, 繰り上がり, 繰り下がり, cm, mm, m, L, dL, 直角, 三角形, 四角形, 時刻, 時間"
				data["examples"] = [
					"7×8はいくつ？",
					"1m＝□cm、□に入る数は？",
					"2時40分から30分後は何時何分？",
					"30+50+20はいくつ？",
				]
				data["bad_examples"] = ["2+3は？（1年レベル）", "5×1は？（簡単すぎ）"]
				data["typical_mistakes"] = [
					"九九の7の段・8の段の暗記間違い（7×6=48, 8×7=54等）",
					"筆算で百の位への繰り上がりを忘れる",
					"cm/mm/mの単位変換ミス（1m=10cmと答える）",
					"時刻と時間の区別がつかない（30分後を30時と答える）",
				]
			3:
				data["topics"] = "わり算（あまりありなし）、大きな数（一万〜一億）、かけ算の筆算（2桁×1桁、2桁×2桁）、小数（0.1の位まで）、分数の導入（同分母の加減）、円と球（半径・直径）、三角形の分類（二等辺・正三角形）、棒グラフ・表、重さ（g, kg）、時間と時刻の計算"
				data["keywords"] = "わり算, あまり, 万, 小数, 分数, 円, 半径, 直径, 二等辺三角形, 正三角形, 棒グラフ, g, kg, コンパス"
				data["examples"] = [
					"23÷5の答えとあまりは？",
					"半径4cmの円の直径は何cm？",
					"0.3＋0.5はいくつ？",
					"1/4＋2/4はいくつ？",
				]
				data["bad_examples"] = ["6×3は？（単純九九）", "10+20は？（2年レベル）"]
				data["typical_mistakes"] = [
					"わり算であまりと商を取り違える（23÷5=3あまり4→商4あまり3と逆にする）",
					"半径と直径を混同する（半径=直径と答える）",
					"小数の位取りを間違える（0.3+0.5=0.35と答える）",
					"分数の加算で分母も足してしまう（1/4+2/4=3/8）",
				]
			4:
				data["topics"] = "大きな数（億・兆）、わり算の筆算（3桁÷2桁）、小数のかけ算わり算、がい数と四捨五入、面積（c㎡, m², km², a, ha）、角度（分度器、三角形の角の和）、垂直と平行、台形・平行四辺形・ひし形、折れ線グラフ、変わり方（□を使った式）、そろばん"
				data["keywords"] = "億, 兆, 筆算, 四捨五入, がい数, 面積, c㎡, m², 角度, 分度器, 垂直, 平行, 台形, 平行四辺形, ひし形, 折れ線グラフ"
				data["examples"] = [
					"24÷6の答えは？",
					"0.5×4はいくつ？",
					"たて5cm、横8cmの長方形の面積は？",
					"三角形の2つの角が45°と90°のとき、残りの角は？",
					"3500を千の位で四捨五入すると？",
				]
				data["bad_examples"] = ["5×6は？（九九＝2年レベル）", "偶数はどれ？（一般常識）", "78と45で大きい数は？（低学年レベル）"]
				data["typical_mistakes"] = [
					"四捨五入の位を間違える（千の位で丸めるべきを百の位で丸める）",
					"面積の公式でたて×横を足してしまう（5+8=13c㎡）",
					"角度の計算で180°を使うべきところ360°を使う",
					"小数のわり算で小数点の移動方向を間違える",
				]
			5:
				data["topics"] = "小数のかけ算わり算（小数÷小数）、分数のたし算ひき算（異分母＝通分・約分）、割合と百分率（%）、歩合、平均、単位量あたりの大きさ、速さ、三角形の面積、平行四辺形・台形の面積、円周と直径の関係（円周率3.14）、角柱と円柱の特徴、合同な図形、偶数と奇数、倍数と約数、公倍数・公約数"
				data["keywords"] = "通分, 約分, 割合, 百分率, %, 平均, 単位量あたり, 速さ, 面積, 底辺, 高さ, 円周率, 3.14, 合同, 偶数, 奇数, 倍数, 約数, 公倍数, 公約数"
				data["examples"] = [
					"2.5÷0.5はいくつ？",
					"1/3＋1/6を通分して計算すると？",
					"定価100円の50%引きはいくら？",
					"底辺6cm、高さ4cmの三角形の面積は？",
					"12と18の最大公約数は？",
				]
				data["bad_examples"] = ["7×8は？（九九）", "100−30は？（低学年レベル）"]
				data["typical_mistakes"] = [
					"通分で最小公倍数ではなく最大公約数を使ってしまう",
					"割合の計算で『くらべる量÷もとにする量』を逆にする",
					"三角形の面積で÷2を忘れる（底辺×高さだけで計算）",
					"円周率を3.14でなく3で計算してしまう",
					"百分率と歩合を混同する（25%=2割5分と答える）",
				]
			6:
				data["topics"] = "分数のかけ算わり算（分数×分数、分数÷分数）、比と比の値、比例と反比例（表・式・グラフ）、速さ（道のり・時間・速さの関係）、拡大図と縮図（縮尺）、対称な図形（線対称・点対称）、円の面積、角柱と円柱の体積、資料の調べ方（度数分布表・ドットプロット・代表値）、場合の数（順列・組合せの基礎）、文字を使った式"
				data["keywords"] = "分数×分数, 逆数, 比, 比の値, 比例, 反比例, 速さ, 道のり, 時間, 縮尺, 線対称, 点対称, 円の面積, 体積, 度数分布, 平均値, 場合の数, 文字式"
				data["examples"] = [
					"3/4÷2/5はいくつ？",
					"分速60mで5分歩くと何m？",
					"A:B＝3:5のとき、Aが6ならBは？",
					"赤白青の3色の旗を一列に並べる並べ方は何通り？",
					"50%引きの後さらに半額。元の何%？",
				]
				data["bad_examples"] = ["1/2＋1/2は？（同分母は3年レベル）", "3×4は？"]
				data["typical_mistakes"] = [
					"分数÷分数で逆数にするのを忘れる（3/4÷2/5をそのまま掛ける）",
					"速さの公式で距離÷時間と時間÷距離を逆にする",
					"円の面積を直径×3.14と計算（半径×半径×3.14が正しい）",
					"比の計算で内項の積と外項の積を取り違える",
					"場合の数で順列と組合せを混同する",
				]
			_:
				data["topics"] = "小学%d年生の学習内容全般" % grade
				data["keywords"] = ""
				data["examples"] = ["学年相応の問題を出してください"]
				data["bad_examples"] = []

	# ── 理科 ──
	elif subject == "理科":
		match grade:
			1, 2:
				# 1-2年は生活科のため理科に準じた内容
				data["topics"] = "季節の変化と植物・動物の観察、身近な自然現象（風・水・光・音）、ものの特徴"
				data["keywords"] = "春夏秋冬, 生き物, 観察, 水, 光, 風, 種, 球根"
				data["examples"] = [
					"チューリップの球根を植えるのは何の季節？",
					"水たまりの水がなくなるのはなぜ？",
					"影ができるのに必要なものは？",
				]
				data["bad_examples"] = []
			3:
				data["topics"] = "昆虫と植物の一生（卵→幼虫→さなぎ→成虫）、太陽と影の動き、光の性質（反射・集光）、磁石の性質（引き合う・退け合う・極）、電気の通り道（回路・導体・不導体）、風やゴムの力、ものと重さ"
				data["keywords"] = "昆虫, 完全変態, 不完全変態, 日なた, 日かげ, 方位磁針, N極, S極, 回路, 豆電球, 導線, 光の反射, ゴムの力"
				data["examples"] = [
					"モンシロチョウの育つ順番は？ たまご→□→さなぎ→成虫",
					"磁石のN極とN極を近づけるとどうなる？",
					"電気を通すものは？（鉄くぎ・割りばし・アルミホイル・消しゴム）",
					"太陽は東から出て□の方角に沈む",
				]
				data["bad_examples"] = []
				data["typical_mistakes"] = [
					"完全変態と不完全変態を混同する（バッタにさなぎがあると思う）",
					"磁石のN極とS極の引き合う・退け合うを逆に記憶する",
					"電気を通すものと通さないものでアルミを「通さない」と答える",
				]
			4:
				data["topics"] = "天気と一日の気温の変化、水の三態変化（固体・液体・気体）と温度、電池のつなぎ方（直列・並列の違い）、月や星の動き（月の満ち欠け・星座の動き）、人の体のつくりと運動（骨・筋肉・関節）、季節と生き物の変化、水の循環（蒸発・結露）"
				data["keywords"] = "気温, 天気, 水蒸気, 氷, 沸騰, 100℃, 0℃, 直列つなぎ, 並列つなぎ, 月, 星座, 骨, 筋肉, 関節, 蒸発, 結露"
				data["examples"] = [
					"水が沸騰するのは何℃？",
					"乾電池を直列につなぐとモーターはどうなる？",
					"月の形が毎日変わって見えるのはなぜ？",
					"骨と骨のつなぎ目を何という？",
				]
				data["bad_examples"] = ["春に咲く花は？（1-2年レベル）"]
				data["typical_mistakes"] = [
					"直列つなぎと並列つなぎの明るさの違いを逆に覚える",
					"水が氷になる温度を100℃と答える（0℃が正しい）",
					"月の満ち欠けの原因を「雲に隠れるから」と答える",
				]
			5:
				data["topics"] = "天気の変化と雲の動き（天気は西から東へ変わる）、流れる水のはたらき（浸食・運搬・堆積）、電磁石の性質（巻き数・電流で強さが変わる）、植物の発芽と成長（発芽条件：水・空気・適温）、メダカの誕生と成長、ふりこの運動（周期は長さで決まる）、もののとけ方（飽和・水温と溶ける量）、人の誕生"
				data["keywords"] = "雲, 天気予報, 浸食, 運搬, 堆積, 電磁石, コイル, 巻き数, 発芽条件, 水, 空気, 適温, メダカ, ふりこ, 周期, 長さ, 飽和水溶液, 溶解度"
				data["examples"] = [
					"ふりこの周期を長くするにはどうする？",
					"種子の発芽に必要な3つの条件は？",
					"電磁石を強くするには？（巻き数を増やす or 電流を大きくする）",
					"川の上流と下流で石の形が違うのはなぜ？",
				]
				data["bad_examples"] = ["磁石にくっつくものは？（3年レベル）"]
				data["typical_mistakes"] = [
					"ふりこの周期が重さで変わると思う（長さで決まる）",
					"発芽に日光が必要だと思う（正しくは水・空気・適温）",
					"電磁石の強さが「電池の大きさ」で決まると思う（巻き数・電流）",
				]
			6:
				data["topics"] = "水溶液の性質（酸性・中性・アルカリ性、リトマス紙）、てこの規則性（支点・力点・作用点、うでの長さ×おもりの重さ）、燃焼のしくみ（酸素が使われ二酸化炭素が出る）、発電と電気の利用（手回し発電機・コンデンサー・LED）、大地のつくりと変化（地層・火山・地震）、植物の体のつくりとはたらき（光合成・蒸散・水の通り道）、人の体のつくりとはたらき（消化・呼吸・血液循環）、月と太陽（月の位置と太陽の関係）、生物と環境"
				data["keywords"] = "酸性, アルカリ性, 中性, リトマス紙, てこ, 支点, 力点, 作用点, 燃焼, 酸素, 二酸化炭素, 光合成, 蒸散, 消化, 呼吸, 地層, 火山, 地震, LED, コンデンサー"
				data["examples"] = [
					"青色リトマス紙が赤に変わったら何性？",
					"てこが釣り合う条件は？（支点からの距離×重さが左右で等しい）",
					"ものが燃えるとき使われる気体は？",
					"植物が日光を使って養分を作ることを何という？",
				]
				data["bad_examples"] = ["水を凍らせると？（4年レベル）"]
				data["typical_mistakes"] = [
					"リトマス紙の色変化を逆に覚える（青が赤→酸性が正しい）",
					"てこの支点・力点・作用点の位置関係を入れ替える",
					"燃焼に必要な気体を二酸化炭素と答える（酸素が正しい）",
					"光合成と呼吸の気体の出入りを混同する",
				]
			_:
				data["topics"] = "小学%d年生の理科全般" % grade
				data["keywords"] = ""
				data["examples"] = ["学年相応の問題を出してください"]
				data["bad_examples"] = []

	# ── 国語 ──
	elif subject == "国語":
		match grade:
			1:
				data["topics"] = "ひらがな・カタカナの読み書き、1年生配当漢字80字、助詞「は・を・へ」の使い方、簡単な文の読み取り、しりとり、音の数（拍）"
				data["keywords"] = "ひらがな, カタカナ, 漢字80字, は・を・へ, 文づくり, 読み取り, しりとり"
				data["examples"] = [
					"「がっこう」をただしく書くと？（小さい「っ」）",
					"「わたし□学校へ行きます」□に入るのは？（は/を/が）",
					"「山」の読みかたは？",
					"「テレビ」はひらがな？カタカナ？",
				]
				data["bad_examples"] = []
			2:
				data["topics"] = "2年生配当漢字160字（読み書き・画数・部首）、主語と述語、修飾語、カタカナで書く語、作文・日記の書き方、物語文の読み取り（気持ち・場面）、同じ部分を持つ漢字"
				data["keywords"] = "漢字160字, 主語, 述語, 修飾語, カタカナ語, 画数, 部首, 場面, 気持ち"
				data["examples"] = [
					"「読む」の画数は何画？",
					"「きれいな花がさいた」の主語は？",
					"「思」という漢字の部首は？（心＝こころ）",
					"「□曜日」の□に入る漢字は？",
				]
				data["bad_examples"] = []
			3:
				data["topics"] = "3年生配当漢字200字、ローマ字（読み書き）、段落の役割とまとまり、つなぎ言葉（だから・しかし・そして…）、ことわざ・慣用句、国語辞典の使い方、詩の表現、指示語（これ・それ・あれ）、漢字の部首・成り立ち"
				data["keywords"] = "漢字200字, ローマ字, 段落, つなぎ言葉, ことわざ, 慣用句, 国語辞典, 詩, 指示語, 部首"
				data["examples"] = [
					"「sakura」をローマ字で正しく読むと？",
					"「猿も木から落ちる」の意味は？",
					"「しかし」はどんなとき使うつなぎ言葉？",
					"「転」の部首は？（車へん）",
				]
				data["bad_examples"] = ["「あ」はひらがな？カタカナ？（1年レベル）"]
				data["typical_mistakes"] = [
					"ローマ字で「shi」と「si」、「chi」と「ti」を混同する",
					"つなぎ言葉の「だから」と「しかし」の使い分けを逆にする",
					"ことわざの意味を字面どおりに解釈する",
				]
			4:
				data["topics"] = "4年生配当漢字202字、つなぎ言葉の種類と使い分け、文章の要約、故事成語（矛盾・五十歩百歩等）、類義語・対義語、慣用句・ことわざの深い理解、漢字辞典の使い方（部首引き・総画引き・音訓引き）、手紙の書き方（敬称）、物語の構成（起承転結）、説明文の構造"
				data["keywords"] = "漢字202字, 故事成語, 類義語, 対義語, 慣用句, 要約, 起承転結, 漢字辞典, 部首引き, 総画引き, 音訓索引, 説明文, 段落構成"
				data["examples"] = [
					"「矛盾」とはどういう意味？",
					"「明」の対義語は？",
					"「目からうろこ」の意味は？",
					"「便利」の「便」の音読みは？",
				]
				data["bad_examples"] = ["「山」の読み方は？（1年レベル）"]
				data["typical_mistakes"] = [
					"類義語と対義語を混同する（「明」の類義語を「暗」と答える）",
					"漢字の音読みと訓読みを取り違える",
					"故事成語の由来と意味を逆に覚える",
				]
			5:
				data["topics"] = "5年生配当漢字193字、敬語（尊敬語・謙譲語・丁寧語の使い分け）、古文に親しむ（竹取物語・枕草子の冒頭等）、和語・漢語・外来語の区別、文章の構成（序論・本論・結論）、同音異義語、四字熟語、複合語、言葉の由来、話し合い・討論の仕方"
				data["keywords"] = "漢字193字, 尊敬語, 謙譲語, 丁寧語, 古文, 竹取物語, 枕草子, 和語, 漢語, 外来語, 同音異義語, 四字熟語, 複合語, 序論本論結論"
				data["examples"] = [
					"「先生がいらっしゃる」は何語？（尊敬語）",
					"「春はあけぼの」はどの作品の冒頭？",
					"「パン」は和語・漢語・外来語のどれ？",
					"「以心伝心」の意味は？",
				]
				data["bad_examples"] = ["「犬」の読み方は？（1-2年レベル）"]
				data["typical_mistakes"] = [
					"尊敬語・謙譲語・丁寧語の区別を間違える（「いらっしゃる」を謙譲語と答える）",
					"和語・漢語・外来語の分類で「パン」を和語と答える",
					"古文の作品名と作者を取り違える（『枕草子』を紫式部と答える）",
				]
			6:
				data["topics"] = "6年生配当漢字191字、熟語の成り立ち（同義・対義・修飾など）、文の組み立て（主語述語の対応・複文・重文）、話し言葉と書き言葉、短歌と俳句（季語・五七五七七/五七五）、古典の名文に親しむ（平家物語・方丈記・徒然草等）、漢文の読み下し（レ点・一二点の基礎）、仮名遣いと歴史的仮名遣い、比喩・倒置・反復などの表現技法"
				data["keywords"] = "漢字191字, 熟語の成り立ち, 主語述語対応, 複文, 季語, 五七五, 五七五七七, 平家物語, 徒然草, 方丈記, レ点, 一二点, 比喩, 倒置, 反復, 歴史的仮名遣い"
				data["examples"] = [
					"「祇園精舎の鐘の声」はどの作品？（平家物語）",
					"「古池や蛙飛び込む水の音」の季語は？",
					"「不可能」はどのような熟語の成り立ち？（打ち消し＋可能）",
					"「月日は百代の過客にして」の出典は？",
				]
				data["bad_examples"] = ["「花」のよみがなは？（低学年レベル）"]
				data["typical_mistakes"] = [
					"短歌（五七五七七）と俳句（五七五）の形式を混同する",
					"季語を季節と関係ない言葉から選ぶ",
					"比喩と倒置の表現技法を取り違える",
					"レ点・一二点の読み下し順序を逆にする",
				]
			_:
				data["topics"] = "小学%d年生の国語全般" % grade
				data["keywords"] = ""
				data["examples"] = ["学年相応の問題を出してください"]
				data["bad_examples"] = []

	# ── 社会 ──
	elif subject == "社会":
		match grade:
			1, 2:
				data["topics"] = "学校のまわり・まちたんけん、地域の人々の仕事、季節と生活の変化、公共施設（図書館・公園・消防署）"
				data["keywords"] = "学校, まち, 地域, 仕事, 公共施設, 図書館, 消防署, 交番"
				data["examples"] = [
					"火事のとき電話する番号は？",
					"けがをした人を運ぶ車を何という？",
					"本をかりられる公共施設は？",
				]
				data["bad_examples"] = []
			3:
				data["topics"] = "市区町村のようすと地図記号、地図の見方（方位・等高線・縮尺の導入）、農家の仕事と工場の仕事、店ではたらく人（スーパーマーケットの工夫）、火事・事故からくらしを守る（消防署・警察署）、市の移り変わり"
				data["keywords"] = "地図記号, 方位, 東西南北, 消防署, 警察, スーパーマーケット, 農家, 工場, 市区町村"
				data["examples"] = [
					"地図で「文」の記号は何を表す？（学校）",
					"方位磁針のN極が指す方角は？",
					"スーパーマーケットが品物を安く売る工夫は？",
					"消防署の電話番号は何番？",
				]
				data["bad_examples"] = []
			4:
				data["topics"] = "都道府県の名前と位置（47都道府県）、県の地形と産業、水道の仕組み（浄水場→配水池→家庭）、ごみの処理と再利用（3R）、自然災害と防災（地震・台風・洪水）、地域の伝統文化・年中行事、昔のくらしと今のくらし"
				data["keywords"] = "47都道府県, 県庁所在地, 浄水場, ごみ処理, リサイクル, 3R, 防災, 地震, 台風, 伝統文化, 祭り"
				data["examples"] = [
					"日本で一番面積が大きい都道府県は？",
					"飲み水をきれいにする施設を何という？（浄水場）",
					"3Rに含まれないのはどれ？（リデュース・リユース・リサイクル）",
					"富士山がある都道府県は？（山梨県と静岡県）",
				]
				data["bad_examples"] = ["火事のときの電話番号は？（3年レベル）"]
				data["typical_mistakes"] = [
					"県庁所在地と県名を混同する（仙台市→仙台県と答える）",
					"3Rの内容を逆に覚える（リユースとリサイクルを混同）",
				]
			5:
				data["topics"] = "日本の国土と世界の中の位置（領土・排他的経済水域）、日本の気候区分（太平洋側・日本海側・瀬戸内・中央高地・沖縄・北海道）、米づくり・畑作・畜産（食料生産）、水産業（漁港・養殖）、自動車工業・製鉄業（工業生産）、情報社会とメディアリテラシー、自然環境と公害（四大公害病）、林業・森林の役割"
				data["keywords"] = "領土, 排他的経済水域, 気候区分, 太平洋側, 日本海側, 稲作, 畑作, 漁業, 養殖, 自動車工業, 情報社会, 公害, 四大公害病, 森林"
				data["examples"] = [
					"日本の最も北にある島は？（択捉島）",
					"冬に雪が多いのは太平洋側？日本海側？",
					"四大公害病に含まれるのはどれ？",
					"日本の食料自給率は約何％？",
				]
				data["bad_examples"] = ["47都道府県で一番大きいのは？（4年レベル）"]
				data["typical_mistakes"] = [
					"太平洋側と日本海側の気候の特徴を逆に覚える",
					"四大公害病の名前と発生地を取り違える",
					"食料自給率の数値を大きく見積もる（38%を約70%と答える）",
				]
			6:
				data["topics"] = "日本の歴史（縄文→弥生→古墳→飛鳥→奈良→平安→鎌倉→室町→安土桃山→江戸→明治→大正→昭和→平成→令和）の流れ、歴史上の人物と業績、日本国憲法の三原則（国民主権・基本的人権の尊重・平和主義）、三権分立（国会・内閣・裁判所）、選挙と政治参加、世界の中の日本（国際連合・ユニセフ）、税金の仕組み、震災復興"
				data["keywords"] = "縄文, 弥生, 古墳, 聖徳太子, 大化の改新, 平安, 鎌倉, 室町, 織田信長, 豊臣秀吉, 徳川家康, 明治維新, 国民主権, 基本的人権, 平和主義, 三権分立, 国会, 内閣, 裁判所, 国際連合"
				data["examples"] = [
					"日本国憲法の三原則に含まれないのはどれ？",
					"鎌倉幕府を開いた人は？（源頼朝）",
					"法律を作るのは三権のうちどこ？（国会＝立法）",
					"奈良時代に建てられた大仏がある寺は？（東大寺）",
				]
				data["bad_examples"] = ["日本の首都は？（常識すぎる）"]
				data["typical_mistakes"] = [
					"歴史上の人物と時代を取り違える（織田信長を江戸時代と答える）",
					"三権分立の役割を混同（内閣が法律を作ると答える）",
					"憲法の三原則に「三権分立」を含めてしまう",
					"時代の順序で鎌倉と室町を逆にする",
				]
			_:
				data["topics"] = "小学%d年生の社会全般" % grade
				data["keywords"] = ""
				data["examples"] = ["学年相応の問題を出してください"]
				data["bad_examples"] = []

	return data

# ── 難易度別プロンプト生成 ──

func _compose_easy_instructions(grade: int, subject: String, curriculum: Dictionary) -> String:
	var p := ""
	p += "【難易度：簡単 ― %d年生の基礎定着問題】\n" % grade
	p += "目的：その学年で学ぶ内容の基礎をしっかり確認する問題を出してください。\n\n"
	p += "＜問題文のルール＞\n"
	p += "- 必ず小学%d年生の学習範囲から出題すること（下の学年の内容は禁止）\n" % grade
	p += "- 1ステップで解ける素直な問題にすること\n"
	p += "- 教科書の例題レベルの基本問題を中心にすること\n"
	p += "- ただし「はい/いいえ」で答えられる問題は避けること\n"
	if curriculum["bad_examples"].size() > 0:
		p += "- 以下のような問題は簡単すぎるので出さないこと：\n"
		for bad: String in curriculum["bad_examples"]:
			p += "  × %s\n" % bad
	p += "\n＜選択肢のルール＞\n"
	p += "- 正解が比較的見つけやすいが、まったくでたらめな選択肢は入れないこと\n"
	p += "- 誤答も同じ分野の用語・数値にすること（ランダムな数字は禁止）\n"
	p += "- 4択の場合、正解以外の3つも一見もっともらしい値にすること\n\n"
	p += "＜%sの具体的な出題指針＞\n" % subject
	match subject:
		"算数":
			p += "- %d年生で新しく習う計算・概念の基本問題を出すこと\n" % grade
			p += "- 教科書の練習問題（A問題）レベルを想定\n"
			p += "- 数値は小さめで計算しやすいものを選ぶこと（暗算で解ける範囲に限定）\n"
		"理科":
			p += "- 基本的な用語・概念の確認問題を出すこと\n"
			p += "- 「〇〇とは何か？」「〇〇の名前は？」のような知識確認が中心\n"
		"国語":
			p += "- 漢字の読み書き、基本的な文法、よく知られたことわざ等を出すこと\n"
			p += "- 使用する漢字は%d年生の配当漢字および既習漢字の範囲内にすること\n" % grade
		"社会":
			p += "- 基本的な地名・人名・施設名の確認問題を出すこと\n"
			p += "- 教科書の太字になっている重要語句から出題すること\n"
	p += "\n"
	return p

func _compose_normal_instructions(grade: int, subject: String, curriculum: Dictionary) -> String:
	var p := ""
	p += "【難易度：普通 ― %d年生の標準問題（最重要ルール）】\n" % grade
	p += "目的：小学%d年生が授業で扱う教科書の標準問題〜章末問題レベルを出す。\n\n" % grade
	p += "＜最重要ルール：学年レベルの厳守＞\n"
	p += "- 小学%d年生の教科書に載っている単元から出題すること\n" % grade
	p += "- %d年生より下の学年で習う基礎内容は【絶対に出さないこと】\n" % grade
	if curriculum["bad_examples"].size() > 0:
		p += "- ↓以下のような問題は%d年生には簡単すぎるので【絶対禁止】↓\n" % grade
		for bad: String in curriculum["bad_examples"]:
			p += "  × %s\n" % bad
	p += "\n＜問題文のルール＞\n"
	p += "- 教科書の練習問題（B問題）〜章末テストレベルの問題を出すこと\n"
	p += "- 単純な一手計算ではなく、少し考えさせる問題を含めること\n"
	p += "- ときどき短い文章題も混ぜること（ただし問題文は50文字以内に収めること）\n"
	p += "\n＜選択肢のルール＞\n"
	p += "- 誤答は「ありがちな間違い」を反映すること\n"
	p += "- 計算問題：計算ミスで出やすい値を誤答に含めること\n"
	p += "- 知識問題：同じカテゴリの紛らわしい用語を誤答に含めること\n"
	p += "- 一目で「ありえない」とわかる選択肢は入れないこと\n"
	p += "\n＜%sの具体的な出題指針＞\n" % subject
	match subject:
		"算数":
			p += "- 以下の単元から満遍なく出題すること: %s\n" % curriculum["topics"]
			p += "- 計算用紙なしで暗算で解ける範囲の数値を使うこと（3桁以上の計算は禁止）\n"
			p += "- 面積、角度、グラフの読み取り等%d年生で実際に学ぶ内容\n" % grade
			p += "- 数値は暗算しやすい小さめの値にすること\n"
			if grade >= 3:
				p += "- 九九の単純暗唱問題は禁止（3年以上は既習）\n"
			if grade >= 4:
				p += "- 「偶数/奇数はどれ？」「大きい順に並べると？」等の低学年的問題は禁止\n"
		"理科":
			p += "- 単なる用語暗記ではなく「なぜそうなるか」を問う問題も含めること\n"
			p += "- 実験の結果予測や、観察結果からの推論問題を混ぜること\n"
		"国語":
			p += "- 漢字は読み書きだけでなく、部首・画数・熟語の構成も問うこと\n"
			p += "- 文法（品詞や文の構造）、慣用句の意味、文章読解を混ぜること\n"
		"社会":
			p += "- 単なる地名暗記ではなく「なぜ・どのように」を問う問題も含めること\n"
			p += "- 地理・産業・くらし・歴史を満遍なく出すこと\n"
	p += "\n"
	return p

func _compose_hard_instructions(grade: int, subject: String, curriculum: Dictionary) -> String:
	var p := ""
	p += "【難易度：難しい ― %d年生のハイレベル応用問題（最重要ルール）】\n" % grade
	p += "目的：%d年生の学習範囲内で最も高度な応用・思考問題を出す。\n\n" % grade
	p += "＜最重要ルール：問題の質＞\n"
	p += "- 単純な一手計算・一問一答は【絶対禁止】\n"
	p += "- 必ず2ステップ以上の思考・計算・推論を要する問題にすること\n"
	p += "- %d年生で習う最も難しい単元・応用場面から出題すること\n" % grade
	if curriculum["bad_examples"].size() > 0:
		p += "- ↓以下のような問題は論外なので【絶対禁止】↓\n"
		for bad: String in curriculum["bad_examples"]:
			p += "  × %s\n" % bad
	p += "\n＜問題文のルール＞\n"
	p += "- 文章題・応用問題を中心にすること\n"
	p += "- 複数の知識を組み合わせて解く問題を出すこと\n"
	p += "- ただし問題文は50文字以内に収めること（短い文で核心を突く）\n"
	p += "\n＜%sの具体的な応用問題例＞\n" % subject
	match subject:
		"算数":
			p += "\n＜★★★ 暗算制約（最重要・絶対遵守）★★★＞\n"
			p += "- このゲームでは計算用紙を使えません。すべての問題は暗算だけで解けること！\n"
			p += "- 3桁以上の計算（例: 2500÷5, 345+278）は【絶対禁止】\n"
			p += "- 掛け算は九九の範囲内（1桁×1桁）、または10×□, □×10 等の簡単なもののみ可\n"
			p += "- 割り算は割り切れる簡単な組合せのみ（例: 20÷4, 36÷6）\n"
			p += "- 小数は0.1, 0.5, 0.25 等、暗算しやすい値のみ使用\n"
			p += "- 分数は分母が2,3,4,5,6,8,10程度の簡単なもののみ\n"
			p += "- 割合・百分率は 10%, 20%, 25%, 50%, 75% 等のキリが良い値のみ使用\n"
			p += "- 面積・体積は小さくて暗算しやすい数値のみ（例: 3×4, 5×6）\n"
			p += "- 「難しさ」は計算の複雑さではなく、概念理解・思考力・ひっかけで表現すること\n\n"
			p += "＜良い「難しい」問題の方向性＞\n"
			p += "- 概念の本質を問う問題（なぜそうなるか？どの公式を使うか？）\n"
			p += "- 紛らわしい選択肢で判断力を試す問題\n"
			p += "- 日常場面の文章題で立式力を試す（ただし数値は簡単に）\n"
			p += "- 図形の性質や単位の関係を問う問題\n"
			p += "- 条件整理が必要だが計算自体は簡単な問題\n\n"
			p += "＜悪い「難しい」問題の例（絶対禁止）＞\n"
			p += "  × 2500÷5＝？（大きな数の計算 → 暗算困難）\n"
			p += "  × 345+278＝？（3桁の足し算 → 筆算必要）\n"
			p += "  × 1500×0.65＝？（大きな数×小数 → 暗算困難）\n"
			p += "  × 半径5cmの円の面積は？ 5×5×3.14＝78.5（暗算困難）\n\n"
			p += "＜良い「難しい」問題の例＞\n"
			p += "  ○ 底辺6cm高さ4cmの三角形の面積は？（6×4÷2=12 → 暗算可能）\n"
			p += "  ○ 50%引きの後さらに20%引き。元の何%？（概念理解）\n"
			p += "  ○ 比 3:5 でAが6のとき、Bは？（比例の理解、6÷3×5=10）\n"
			p += "  ○ 正三角形の1つの角は何度？（図形知識）\n"
			p += "  ○ 分速60mで5分歩くと何m？（60×5=300 → 暗算可能）\n\n"
			if grade >= 4:
				p += "- がい数の概念、四捨五入のルール理解を問う問題は良い\n"
			if grade >= 5:
				p += "- 割合・百分率の概念理解（計算は10%,25%,50%等に限定）\n"
				p += "- 倍数・約数の概念を問う問題（小さな数値で）\n"
			if grade >= 6:
				p += "- 速さ=道のり÷時間 の立式力（数値は暗算範囲内）\n"
				p += "- 比の概念理解（小さな整数の比のみ）\n"
				p += "- 場合の数（3〜4個程度の並べ方・選び方）\n"
		"理科":
			p += "- 実験結果から原因・法則を推測させる問題\n"
			p += "- 「もし条件を変えたらどうなるか？」という思考実験系の問題\n"
			p += "- 複数の概念を組み合わせる問題（例：電磁石＋回路）\n"
		"国語":
			p += "- 紛らわしい同音異義語・同訓異字の使い分け\n"
			p += "- 文脈から語句の意味を推測させる問題\n"
			p += "- 古典の有名な一節の出典・意味を問う問題\n"
			p += "- 複数の表現技法を見分ける問題\n"
		"社会":
			p += "- 複数の事実を結びつけて判断させる問題\n"
			p += "- 「なぜ〇〇な地域で△△が盛んか」のような因果推論\n"
			p += "- 歴史上の出来事の順序・因果関係を問う問題\n"
			p += "- グラフや資料の読み取りを想定した問題\n"
	p += "\n＜選択肢のルール（最重要）＞\n"
	p += "- 不正解の選択肢は、正解と非常に似た値・表現にすること\n"
	p += "- 計算問題：よくある計算ミスの結果を誤答にすること（例：繰り上がり忘れ、÷と×の取り違え）\n"
	p += "- 知識問題：同カテゴリの紛らわしい用語を誤答にすること\n"
	p += "- 「明らかに違う」選択肢は【絶対に入れないこと】\n"
	p += "- 4択の場合、4つすべてが「ありえそう」に見えるのが理想\n\n"
	return p

func fetch_quiz_parallel(subject: String, grade: int, difficulty: String, count: int, history: Array[String], force_ten_mode: bool = false) -> void:
	# 10問モード: 4並列リクエスト（各バッチに異なる単元を割当て → セマンティックdedupで最終フィルタ）
	# エンドレスモード: 5並列リクエストで速度最重視
	var is_ten_mode := count >= 6 or force_ten_mode  # 6問以上、または強制フラグで10問モード扱い
	
	var unique_seen := {}
	
	# 案5: 難易度に応じた temperature
	var temperature := get_temperature_for_difficulty(difficulty)
	
	# ── 共通コールバック ──
	var _make_on_complete = func(expected_ref: Array, completed_ref: Array) -> Callable:
		return func(items: Array[QuizItem]):
			# 案2: ルールベースバリデーション（即時・無料）
			var validator: QuizValidator = QuizManager.quiz_validator
			if validator:
				var rule_result := validator.validate_rules(items)
				items = rule_result["valid"]
				if rule_result["reasons"].size() > 0:
					print("[OnlineFetch] Rule validation removed %d items" % rule_result["reasons"].size())
			
			var unique_items: Array[QuizItem] = []
			items.shuffle()
			for q in items:
				if unique_seen.has(q.q): continue
				# セマンティック重複チェック: 既に見た問題と内容レベルで比較
				var is_dup := false
				for seen_q: String in unique_seen.keys():
					if _is_semantically_similar(q.q, seen_q):
						is_dup = true
						print("[OnlineFetch] Dedup blocked (semantic): '%s' ≈ '%s'" % [q.q.left(30), seen_q.left(30)])
						break
				if is_dup:
					continue
				unique_seen[q.q] = true
				unique_items.append(q)
				
			if unique_items.size() > 0:
				# 速度優先: 先着バッチの結果を即座にバッファ投入
				fetch_partial.emit(unique_items)
				
				if validator and unique_items.size() > 0:
					validator.validate_answers_llm(unique_items, subject, grade,
						func(valid_items: Array[QuizItem], invalid_reasons: Array[String]):
							if invalid_reasons.size() > 0:
								print("[OnlineFetch] LLM validation flagged %d items (async)" % invalid_reasons.size())
								for reason in invalid_reasons:
									print("  - %s" % reason)
					)
			
			completed_ref[0] += 1
			if completed_ref[0] >= expected_ref[0]:
				fetch_completed.emit([] as Array[QuizItem])
	
	if is_ten_mode:
		# ═══ 10問モード: 4並列 × 各4問（超高速レスポンス + セマンティックdedup）═══
		# 各バッチに異なる単元テーマを明示的に割り当て → バッチ間重複を構造的に防止
		# 4問/バッチは非常に軽量なのでAPIレスポンスが最速
		const TEN_PARALLEL: int = 4
		var per_batch: int = 4  # 各バッチの問題数（合計16問 → dedup後10問以上確保）
		var expected_ref := [TEN_PARALLEL]
		var completed_ref := [0]
		
		var timer := get_tree().create_timer(20.0)  # 4並列・軽量バッチなので20sで十分
		timer.timeout.connect(func():
			if completed_ref[0] < expected_ref[0]:
				completed_ref[0] = 999
				fetch_completed.emit([] as Array[QuizItem])
		)
		
		var on_complete: Callable = _make_on_complete.call(expected_ref, completed_ref)
		
		# バッチごとに異なる単元テーマを強制割り当て（4分類で重複率を最小化）
		var batch_themes := [
			"【バッチ指示】問1〜4は以下のジャンルから出題: 計算・数値操作・公式適用・単位変換。他バッチとジャンルが異なります。",
			"【バッチ指示】問1〜4は以下のジャンルから出題: 文章題・応用思考・因果推論・日常場面の問題。他バッチとジャンルが異なります。",
			"【バッチ指示】問1〜4は以下のジャンルから出題: 図形・グラフ読取・空間認識・図の性質。他バッチとジャンルが異なります。",
			"【バッチ指示】問1〜4は以下のジャンルから出題: 概念理解・知識問題・定義の確認・法則の適用。他バッチとジャンルが異なります。"
		]
		
		for i in range(TEN_PARALLEL):
			var extra_history: Array[String] = history.duplicate()
			extra_history.append(batch_themes[i])
			var prompt := compose_prompt(subject, grade, difficulty, per_batch, extra_history, QuizManager.game_state.is_coop_mode())
			var proxy_msg := " (via AI Gateway)" if not ApiStatusAutoload.get_env("PROXY_URL").is_empty() else ""
			print("[OnlineFetch] 10-question mode - batch %d/%d: requesting %d questions%s" % [i+1, TEN_PARALLEL, per_batch, proxy_msg])
			_fetch_gemini_target(prompt, ApiStatusAutoload.gemini_model, temperature, on_complete)
	else:
		# ═══ エンドレスモード: 並列リクエストで速度重視 ═══
		const NUM_PARALLEL: int = 5
		var per_call: int = maxi(2, ceili(float(count) / float(NUM_PARALLEL)))
		var expected_ref := [NUM_PARALLEL]
		var completed_ref := [0]
		
		var timer := get_tree().create_timer(30.0)
		timer.timeout.connect(func():
			if completed_ref[0] < expected_ref[0]:
				completed_ref[0] = 999
				fetch_completed.emit([] as Array[QuizItem])
		)
		
		var on_complete: Callable = _make_on_complete.call(expected_ref, completed_ref)
		
		var themes := [
			"テーマA: 基礎的な用語や計算、単純な事実を問う問題",
			"テーマB: 日常生活に関連した文章題や応用問題",
			"テーマC: 図形、単位、文字、グラフなどの表現・概念を問う問題",
			"テーマD: 少しひねった問題や、よくある間違いを誘う問題",
			"テーマE: この学年の学習内容のうち、最も難易度が高い問題"
		]
		
		for i in range(NUM_PARALLEL):
			var extra_history: Array[String] = history.duplicate()
			extra_history.append("【並列バッチ制約: この生成では必ず『%s』の傾向を中心に出題し、他のバッチと内容が被るのを防いでください】" % themes[i % themes.size()])
			var prompt := compose_prompt(subject, grade, difficulty, per_call, extra_history, QuizManager.game_state.is_coop_mode())
			var proxy_msg := " (via AI Gateway)" if not ApiStatusAutoload.get_env("PROXY_URL").is_empty() else ""
			print("[OnlineFetch] Endless mode - batch %d: requesting %d questions%s" % [i+1, per_call, proxy_msg])
			_fetch_gemini_target(prompt, ApiStatusAutoload.gemini_model, temperature, on_complete)

## セマンティック重複検出
## 問題文からキーワードを抽出し、Jaccard類似度で内容レベルの重複を検出する
## 「数値を変えただけ」「聞き方を変えただけ」のパターンを確実にブロック
func _is_semantically_similar(q1: String, q2: String) -> bool:
	# 完全一致チェック
	if q1 == q2:
		return true
	# 通常の文字列類似度（GDScript built-in）
	if q1.similarity(q2) > 0.70:
		return true
	# キーワード抽出ベースの類似度チェック
	var kw1 := _extract_keywords(q1)
	var kw2 := _extract_keywords(q2)
	if kw1.is_empty() or kw2.is_empty():
		return false
	# Jaccard類似度: 共通キーワード / 全キーワードの和集合
	var intersection := 0
	for k in kw1:
		if kw2.has(k):
			intersection += 1
	var union_size := kw1.size() + kw2.size() - intersection
	if union_size == 0:
		return false
	var jaccard := float(intersection) / float(union_size)
	return jaccard > 0.55  # 55%以上のキーワードが一致 → 重複と判定

## 問題文からコンテンツキーワードを抽出する
## 助詞・構造語・数値を除去して内容の骨格だけを残す
func _extract_keywords(text: String) -> Dictionary:
	# 数字を正規化（全角→半角は GDScript では手動）
	var normalized := text
	# 助詞・接続詞・構造語を除去してトークン化
	var noise_words := ["は", "の", "が", "を", "に", "で", "と", "も", "へ", "から",
		"まで", "より", "など", "たり", "って", "です", "ます", "した", "する",
		"ある", "いる", "なる", "ない", "この", "その", "どの", "どれ",
		"いくつ", "何", "どう", "とき", "こと", "もの", "ため", "ところ",
		"？", "。", "、", "「", "」", "（", "）", "＝", "＋", "−", "×", "÷",
		"?", ".", ",", "(", ")", "=", "+", "-"]
	# 文字を1〜3文字のn-gramに分割してキーワード辞書を構築
	var keywords := {}
	# まずスペースや記号で大まかにトークン分割
	var tokens := normalized.split(" ")
	var expanded_tokens: Array[String] = []
	for t in tokens:
		# さらに日本語の助詞的な境界で分割（簡易）
		expanded_tokens.append(t)
	for token: String in expanded_tokens:
		var cleaned := token.strip_edges()
		if cleaned.length() < 2:
			continue
		if cleaned in noise_words:
			continue
		# 数値だけのトークンは除外（数値違いの問題を同一視するため）
		if cleaned.is_valid_int() or cleaned.is_valid_float():
			continue
		keywords[cleaned] = true
	# 2文字bigram も追加（日本語は空白区切りがないため）
	for i in range(normalized.length() - 1):
		var bigram := normalized.substr(i, 2)
		var skip := false
		for nw: String in ["は", "の", "が", "を", "に", "で", "と", "も"]:
			if bigram.contains(nw):
				skip = true
				break
		if skip:
			continue
		if bigram.strip_edges().length() == 2:
			keywords[bigram] = true
	return keywords

func _fetch_gemini_target(prompt: String, target_model: String, temperature: float, callback: Callable) -> void:
	var proxy := ApiStatusAutoload.get_env("PROXY_URL")
	var url: String
	if not proxy.is_empty():
		url = proxy + "/gemini?model=" + target_model
	else:
		var key := ApiStatusAutoload.get_env("GOOGLE_API_KEY")
		if key.is_empty():
			key = ApiStatusAutoload.get_env("GEMINI_API_KEY")
		if key.is_empty():
			callback.call([])
			return
		url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [target_model, key]
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 30.0
	
	# 案5: systemInstruction の分離
	var sys_instruction := compose_system_instruction()
	
	# 案4: Structured Output (responseSchema)
	var response_schema := {
		"type": "ARRAY",
		"items": {
			"type": "OBJECT",
			"required": ["q", "c", "a", "e"],
			"properties": {
				"q": {"type": "STRING", "description": "問題文 (50文字以内)"},
				"c": {
					"type": "ARRAY",
					"items": {"type": "STRING"},
					"description": "選択肢 (2個または4個、各15文字以内)"
				},
				"a": {"type": "INTEGER", "description": "正解インデックス (0始まり)"},
				"e": {"type": "STRING", "description": "解説 (20文字以内)"}
			}
		}
	}
	
	var body := JSON.stringify({
		"systemInstruction": {"parts": [{"text": sys_instruction}]},
		"contents": [{"parts": [{"text": prompt}]}],
		"generationConfig": {
			"temperature": temperature,
			"responseMimeType": "application/json",
			"responseSchema": response_schema
		}
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		var out: Array[QuizItem] = []
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("candidates"):
				var text: String = json["candidates"][0]["content"]["parts"][0].get("text", "")
				var raw_arr = extract_quizzes_from_text(text)
				for r in raw_arr:
					var p = normalize_single(r, "GEMINI")
					if p: out.append(p)
		http.queue_free()
		callback.call(out)
	)
	http.request(url, ApiStatusAutoload.get_proxy_headers() if not proxy.is_empty() else ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _fetch_openai(prompt: String, callback: Callable) -> void:
	var model := ApiStatusAutoload.get_env("OPENAI_FAST_MODEL", "gpt-4o-mini")
	
	var proxy := ApiStatusAutoload.get_env("PROXY_URL")
	var url: String
	var headers: PackedStringArray
	
	if not proxy.is_empty():
		url = proxy + "/openai"
		headers = ApiStatusAutoload.get_proxy_headers()
	else:
		var key := ApiStatusAutoload.get_env("OPENAI_API_KEY")
		if key.is_empty():
			callback.call([])
			return
		url = "https://api.openai.com/v1/chat/completions"
		headers = ["Content-Type: application/json", "Authorization: Bearer " + key]
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 15.0
	
	var body := JSON.stringify({
		"model": model,
		"messages": [{"role": "user", "content": prompt}],
		"temperature": 0.45
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		var out: Array[QuizItem] = []
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("choices"):
				var text: String = json["choices"][0]["message"].get("content", "")
				var raw_arr = extract_quizzes_from_text(text)
				for r in raw_arr:
					var p = normalize_single(r, "OPENAI")
					if p: out.append(p)
		http.queue_free()
		callback.call(out)
	)
	http.request(url, headers, HTTPClient.METHOD_POST, body)

func fetch_explanation(subject: String, grade: int, quiz_q: String, quiz_c: PackedStringArray, quiz_a: int, callback: Callable) -> void:
	var model := ApiStatusAutoload.gemini_model
	var proxy := ApiStatusAutoload.get_env("PROXY_URL")
	var url: String
	
	if not proxy.is_empty():
		url = proxy + "/gemini?model=" + model
	else:
		var key := ApiStatusAutoload.get_env("GOOGLE_API_KEY")
		if key.is_empty():
			key = ApiStatusAutoload.get_env("GEMINI_API_KEY")
		if key.is_empty():
			callback.call("解説を取得できませんでした")
			return
		url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [model, key]
	
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 10.0
	
	var q_str := "問題: " + quiz_q + "\n"
	q_str += "選択肢: " + ", ".join(quiz_c) + "\n"
	q_str += "正解: " + quiz_c[quiz_a] + "\n"
	q_str += "この正解となる理由を、小学" + str(grade) + "年生向けに15文字以内で簡潔に説明してください。出力は解説のテキストのみにしてください。"
	
	var body := JSON.stringify({
		"contents": [{"parts": [{"text": q_str}]}],
		"generationConfig": {"temperature": 0.2}
	})
	
	http.request_completed.connect(func(result: int, response_code: int, _h, b: PackedByteArray):
		var ans := "解説を取得できませんでした"
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.parse_string(b.get_string_from_utf8())
			if json is Dictionary and json.has("candidates"):
				var text: String = json["candidates"][0]["content"]["parts"][0].get("text", "")
				ans = text.strip_edges().trim_prefix('"').trim_suffix('"').strip_edges()
		http.queue_free()
		callback.call(ans)
	)
	http.request(url, ApiStatusAutoload.get_proxy_headers() if not proxy.is_empty() else ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
