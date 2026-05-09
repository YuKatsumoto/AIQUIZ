import json
import random
import os
from pathlib import Path

BANK_PATH = Path(r"C:\AIQUIZ\AIQUIZ-Godot\offline_bank.json")

def load_bank():
    if not BANK_PATH.exists():
        return {}
    with open(BANK_PATH, "r", encoding="utf-8") as f:
        return json.load(f)

def save_bank(data):
    with open(BANK_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def generate_choices(ans, is_float=False):
    c_set = {str(ans)}
    attempts = 0
    while len(c_set) < 4 and attempts < 50:
        attempts += 1
        if is_float:
            offset = random.choice([-0.2, -0.1, 0.1, 0.2, 1.0, -1.0, 10.0])
            new_c = round(ans + offset, 2)
            if new_c == int(new_c):
                new_c_str = str(int(new_c))
            else:
                new_c_str = str(new_c)
            if new_c > 0:
                c_set.add(new_c_str)
        else:
            offset = random.choice([-10, -5, -2, -1, 1, 2, 5, 10, 100])
            new_c = ans + offset
            if new_c >= 0:
                c_set.add(str(new_c))
    
    c_list = list(c_set)
    random.shuffle(c_list)
    ans_str = str(ans)
    if is_float and ans == int(ans):
        ans_str = str(int(ans))
        
    try:
        a_idx = c_list.index(ans_str)
    except ValueError:
        c_list[0] = ans_str
        random.shuffle(c_list)
        a_idx = c_list.index(ans_str)
        
    return c_list, a_idx

def generate_g1():
    q_list = []
    # 足し算 (答え20まで)
    for a in range(1, 20):
        for b in range(1, 21 - a):
            ans = a + b
            c_list, a_idx = generate_choices(ans)
            q_list.append({
                "q": f"【けいさん】{a} ＋ {b} はいくつですか？",
                "c": c_list,
                "a": a_idx,
                "exp": f"{a} と {b} をあわせると {ans} になります。",
                "t": 2.5 if ans <= 10 else 3.5,
                "src": "ALGO_G1"
            })
    # 引き算 (20まで)
    for a in range(2, 21):
        for b in range(1, a):
            ans = a - b
            c_list, a_idx = generate_choices(ans)
            q_list.append({
                "q": f"【けいさん】{a} － {b} はいくつですか？",
                "c": c_list,
                "a": a_idx,
                "exp": f"{a} から {b} をひくと {ans} になります。",
                "t": 2.5 if a <= 10 else 4.0,
                "src": "ALGO_G1"
            })
    return q_list

def generate_g2():
    q_list = []
    # 暗算しやすい足し算
    for _ in range(500):
        # パターン: 1桁の繰り上がり, 繰り上がりなし, 10の倍数
        type_ = random.choice(["carry", "no_carry", "tens"])
        if type_ == "tens":
            a = random.randint(1, 8) * 10
            b = random.randint(1, 9 - (a//10)) * 10
        elif type_ == "carry":
            a = random.randint(11, 89)
            b = random.randint(1, 9)
        else:
            a = random.randint(11, 89)
            b_tens = random.randint(0, 9 - (a//10))
            b_ones = random.randint(0, 9 - (a%10))
            b = b_tens * 10 + b_ones
            if b == 0: b = 1

        ans = a + b
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【計算】{a} ＋ {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"暗算で計算します。答えは {ans} になります。",
            "t": 4.5,
            "src": "ALGO_G2"
        })
    # 暗算しやすい引き算
    for _ in range(500):
        type_ = random.choice(["borrow", "no_borrow", "tens"])
        if type_ == "tens":
            a = random.randint(2, 9) * 10
            b = random.randint(1, (a//10) - 1) * 10
            if b == 0: b = 10
        elif type_ == "borrow":
            a = random.randint(21, 99)
            b = random.randint(1, 9)
        else:
            a = random.randint(21, 99)
            b_tens = random.randint(1, a//10)
            b_ones = random.randint(0, a%10)
            b = b_tens * 10 + b_ones
            if b == a: b = a - 1
            if b == 0: b = 1

        ans = a - b
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【計算】{a} － {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"暗算でひき算をします。{a} － {b} ＝ {ans} になります。",
            "t": 4.5,
            "src": "ALGO_G2"
        })
    # かけ算 (九九)
    for a in range(1, 10):
        for b in range(1, 10):
            ans = a * b
            c_list, a_idx = generate_choices(ans)
            q_list.append({
                "q": f"【九九】{a} × {b} ＝ ？",
                "c": c_list,
                "a": a_idx,
                "exp": f"九九の「{a}の段」を思い出しましょう。{a}×{b}＝{ans} です。",
                "t": 2.0,
                "src": "ALGO_G2"
            })
    return q_list

def generate_g3():
    q_list = []
    # かけ算 (暗算可能な 2桁×1桁)
    for _ in range(500):
        type_ = random.choice(["tens", "teens"])
        if type_ == "tens":
            a = random.randint(2, 9) * 10
            b = random.randint(2, 9)
        else:
            a = random.randint(11, 15)
            b = random.randint(2, 5)
        ans = a * b
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【計算】{a} × {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"暗算で計算します。答えは {ans} になります。",
            "t": 6.0,
            "src": "ALGO_G3"
        })
    # 割り算 (あまりなし)
    for _ in range(400):
        b = random.randint(2, 9)
        ans = random.randint(2, 9)
        a = ans * b
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【計算】{a} ÷ {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"{b} に何をかけると {a} になるかを考えます。{b}×{ans}＝{a} だから答えは {ans} です。",
            "t": 3.0,
            "src": "ALGO_G3"
        })
    # 割り算 (あまりあり)
    for _ in range(400):
        b = random.randint(2, 9)
        ans = random.randint(2, 9)
        r = random.randint(1, b - 1)
        a = ans * b + r
        c_set = {f"{ans}あまり{r}"}
        while len(c_set) < 4:
            wrong_ans = max(1, ans + random.choice([-1, 0, 1]))
            wrong_r = r + random.choice([-1, 1, 2])
            if wrong_r < 0: wrong_r = 1
            if wrong_ans != ans or wrong_r != r:
                c_set.add(f"{wrong_ans}あまり{wrong_r}")
        c_list = list(c_set)
        random.shuffle(c_list)
        a_idx = c_list.index(f"{ans}あまり{r}")
        q_list.append({
            "q": f"【計算】{a} ÷ {b} はいくつで、あまりはいくつ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"{b}×{ans}＝{ans*b}。{a}－{ans*b}＝{r} だから、「{ans}あまり{r}」です。",
            "t": 6.5,
            "src": "ALGO_G3"
        })
    return q_list

def generate_g4():
    q_list = []
    # かけ算 (暗算可能な 2桁×2桁 や 簡単な数)
    for _ in range(600):
        type_ = random.choice(["tens", "twentyfive", "teens"])
        if type_ == "tens":
            a = random.randint(2, 9) * 10
            b = random.randint(2, 9) * 10
        elif type_ == "twentyfive":
            a = 25
            b = random.choice([2, 4, 6, 8])
        else:
            a = random.randint(11, 15)
            b = random.randint(11, 12)
        
        # shuffle a and b
        if random.random() > 0.5:
            a, b = b, a

        ans = a * b
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【計算】{a} × {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"暗算の工夫で計算します。答えは {ans} になります。",
            "t": 7.0,
            "src": "ALGO_G4"
        })
    # 割り算 (暗算可能な 2桁/3桁 ÷ 1桁)
    for _ in range(400):
        type_ = random.choice(["tens", "simple"])
        if type_ == "tens":
            ans = random.randint(2, 9) * 10
            b = random.randint(2, 9)
        else:
            ans = random.randint(11, 15)
            b = random.randint(2, 5)
        a = ans * b
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【計算】{a} ÷ {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"暗算でわり算をします。答えは {ans} です。",
            "t": 5.0,
            "src": "ALGO_G4"
        })
    # 小数足し算 (繰り上がり少なめ)
    for _ in range(300):
        a_int = random.randint(1, 9)
        a_dec = random.randint(1, 9)
        b_int = random.randint(1, 9)
        b_dec = random.randint(1, 9)
        
        # 50% chance to make it carry nicely
        if random.random() > 0.5:
            b_dec = 10 - a_dec

        a = a_int + a_dec * 0.1
        b = b_int + b_dec * 0.1
        ans = round(a + b, 1)
        c_list, a_idx = generate_choices(ans, is_float=True)
        q_list.append({
            "q": f"【小数】{a} ＋ {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"小数点をそろえてたし算します。答えは {ans} です。",
            "t": 4.5,
            "src": "ALGO_G4"
        })
    return q_list

def generate_g5():
    q_list = []
    import math
    # 最小公倍数 (暗算可能な範囲)
    for _ in range(300):
        pairs = [(2,3), (3,4), (4,5), (2,5), (3,5), (4,6), (6,8), (3,6), (2,8), (4,8), (5,10)]
        a, b = random.choice(pairs)
        if random.random() > 0.5:
            a, b = b, a
        ans = abs(a*b) // math.gcd(a, b)
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【倍数】{a} と {b} の最小公倍数は？",
            "c": c_list,
            "a": a_idx,
            "exp": f"{a} の倍数と {b} の倍数で、いちばん小さい共通の数は {ans} です。",
            "t": 5.5,
            "src": "ALGO_G5"
        })
    # 小数のかけ算 (整数×小数 または 簡単な小数)
    for _ in range(400):
        type_ = random.choice(["int_dec", "dec_int"])
        if type_ == "int_dec":
            a = random.randint(2, 9)
            b = round(random.randint(1, 9) * 0.1, 1)
        else:
            a = round(random.randint(1, 9) * 0.1, 1)
            b = random.randint(2, 9)
            
        ans = round(a * b, 2)
        c_list, a_idx = generate_choices(ans, is_float=True)
        q_list.append({
            "q": f"【小数】{a} × {b} ＝ ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"かけ算をして、小数点の位置に気をつけます。答えは {ans} になります。",
            "t": 6.0,
            "src": "ALGO_G5"
        })
    # 面積 (三角形、暗算可能)
    for _ in range(300):
        w = random.randint(2, 10)
        h = random.randint(2, 10)
        if w % 2 != 0 and h % 2 != 0:
            w += 1 # Make at least one even
        ans = (w * h) / 2
        c_list, a_idx = generate_choices(ans, is_float=True)
        q_list.append({
            "q": f"【図形】底辺が{w}cm、高さが{h}cmの三角形の面積は何c㎡？",
            "c": c_list,
            "a": a_idx,
            "exp": f"三角形の面積は「底辺×高さ÷２」です。{w}×{h}÷2＝{ans} c㎡。",
            "t": 5.0,
            "src": "ALGO_G5"
        })
    return q_list

def generate_g6():
    q_list = []
    # 速さ (暗算可能)
    for _ in range(400):
        speed = random.randint(3, 9) * 10 # km/h
        hours = random.randint(2, 5)
        dist = speed * hours
        c_list, a_idx = generate_choices(dist)
        q_list.append({
            "q": f"【速さ】時速{speed}kmで走る車が、{hours}時間で進むきょりは何km？",
            "c": c_list,
            "a": a_idx,
            "exp": f"きょり＝速さ×時間。{speed}×{hours}＝{dist} km になります。",
            "t": 5.0,
            "src": "ALGO_G6"
        })
    for _ in range(400):
        speed = random.choice([50, 60, 70, 80, 100]) # m/min
        time_m = random.randint(2, 9)
        dist = speed * time_m
        c_list, a_idx = generate_choices(speed)
        q_list.append({
            "q": f"【速さ】{time_m}分間で{dist}m歩く人の分速は何m？",
            "c": c_list,
            "a": a_idx,
            "exp": f"速さ＝きょり÷時間。{dist}÷{time_m}＝分速{speed}m になります。",
            "t": 5.5,
            "src": "ALGO_G6"
        })
    # 比
    for _ in range(300):
        ratio1 = random.randint(2, 5)
        ratio2 = random.randint(2, 5)
        if ratio1 == ratio2: ratio1 += 1
        mult = random.randint(2, 6)
        val1 = ratio1 * mult
        ans = ratio2 * mult
        c_list, a_idx = generate_choices(ans)
        q_list.append({
            "q": f"【比】AとBの比は {ratio1}:{ratio2} です。Aが{val1}のとき、Bはいくつ？",
            "c": c_list,
            "a": a_idx,
            "exp": f"Aは比の{mult}倍（{val1}÷{ratio1}）です。Bも同じように {ratio2}×{mult}＝{ans} になります。",
            "t": 6.0,
            "src": "ALGO_G6"
        })
    return q_list

def main():
    print("Starting mass algorithmic generation for Math (Mental Math Edition)...")
    bank = load_bank()
    if "算数" not in bank:
        bank["算数"] = {str(i): [] for i in range(1, 7)}
        
    g1 = generate_g1()
    g2 = generate_g2()
    g3 = generate_g3()
    g4 = generate_g4()
    g5 = generate_g5()
    g6 = generate_g6()
    
    # Merge existing and remove duplicates based on question text
    for grade, qs in zip(["1", "2", "3", "4", "5", "6"], [g1, g2, g3, g4, g5, g6]):
        existing_qs = bank["算数"].get(grade, [])
        existing_q_texts = set(q["q"] for q in existing_qs)
        added = 0
        for new_q in qs:
            if new_q["q"] not in existing_q_texts:
                existing_qs.append(new_q)
                existing_q_texts.add(new_q["q"])
                added += 1
        bank["算数"][grade] = existing_qs
        print(f"Grade {grade}: Added {added} new algorithm questions. Total: {len(existing_qs)}")

    save_bank(bank)
    
    total = 0
    for subj in bank.values():
        for qs in subj.values():
            total += len(qs)
    print(f"Generation complete. Offline bank now has {total} questions total.")

if __name__ == "__main__":
    main()
