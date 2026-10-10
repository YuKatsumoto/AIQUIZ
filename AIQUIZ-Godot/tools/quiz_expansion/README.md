# オフライン問題 大量補充（クラウドセッション運用）

どのPCからでも、Claude Desktop（同じアカウント）でクラウドセッションを起動すれば作業できる。
仕様は `SPEC.md`、レビュー手順は `REVIEW.md`、セッションの担当表と手順は `ORCHESTRATOR.md`。

## 1. クラウドセッションの起動

1. Claude Desktop の Code タブで新規セッション。実行環境 **Cloud（デフォルト）**、リポジトリ **AIQUIZ**、ブランチ **master** のままでよい。モデルは Opus 推奨。
2. 下の指示文を貼って送信する。`S1` / `s1` の部分だけ、担当セッションに合わせて変える。

```text
リポジトリ YuKatsumoto/AIQUIZ で作業します。最初に次を実行してください:
git fetch origin quiz-expansion/base && git checkout -b quiz-expansion/s1 origin/quiz-expansion/base
その後 AIQUIZ-Godot/tools/quiz_expansion/ORCHESTRATOR.md を全部読み、セッションID「S1」のオーケストレーターとして、質問で止まらず最後まで自律的に実行してください。
```

| ID | 担当 | 目安 |
|---|---|---|
| S1 | 理科 3年 | 約340問（完了） |
| S2 | 理科 4〜6年 | 約830問 |
| S3 | 国語 1〜3年 | 約830問 |
| S4 | 国語 4〜6年 | 約1,040問 |
| S5 | 社会 3年 | 約340問 |
| S6 | 社会 4〜6年 | 約800問 |
| S7 | 英語 3〜6年 | 約800問 |
| S8 | 算数 5・6年 | 約400問 |
| S9 | 試験運用の800問の磨き直し | 新規なし |

- **理科・社会の1・2年は作らない**。学校では生活科にあたるため、ゲームでは理科・社会・英語は3〜6年しか選べない
  （`scripts/core/constants.gd` の `SUBJECT_GRADE_OPTIONS`）。validate.py もこの学年のシャードをエラーにする。
  S1 が push 済みの `science_g1_*` / `science_g2_*`（計765問）は統合しない（下の「統合」手順3）。
- 同じIDのセッションを2つ起動しない（同じブランチに push して衝突する）。
- 途中で止まったセッションは、同じIDで起動し直せば、push 済みのシャードは残っている。
  その場合は指示文の最後に「`origin/quiz-expansion/s1` に push 済みのシャードは作り直さず、残りのシャードから続けてください」と足す
  （`git checkout -b` の代わりに `git checkout -b quiz-expansion/s1 origin/quiz-expansion/s1` を使う）。
- クラウドセッションクレジットが使われるのは Desktop の Cloud セッション（または `claude --cloud`）だけ。
  ルーチン（スケジュール実行）やローカルセッションはプランの使用量から引かれる。

## 2. 進み具合の確認

```
git fetch origin
git branch -r --list "origin/quiz-expansion/*"
```

## 3. 全部終わったら: offline_bank.json への統合

Claude Code（ローカルでもクラウドでも可）に次のように頼む:

```text
YuKatsumoto/AIQUIZ の quiz-expansion/s1〜s9 ブランチにあるシャードを統合してください。
AIQUIZ-Godot/tools/quiz_expansion/README.md の「統合」の手順に従ってください。
```

手順（作業する人・Claude 向け）:
1. master から作業ブランチ `quiz-expansion/merge` を作る。
2. `quiz-expansion/base` の `AIQUIZ-Godot/tools/quiz_expansion/` を持ってくる。
3. 各 `origin/quiz-expansion/s1`〜`s9` から `AIQUIZ-Godot/tools/quiz_expansion/shards/*.json` を取り出して `shards/` に置く。
   試験運用の4ファイル（`*_a.json`）は **s9 の版を優先**する（s9 が無ければ base の版）。
   `science_g1_*`・`science_g2_*`・`social_g1_*`・`social_g2_*` は**持ってこない**（ゲームで選べない学年。残っていると validate.py がエラーになる）。
4. `python AIQUIZ-Godot/tools/quiz_expansion/validate.py` でエラー0を確認。
5. `python AIQUIZ-Godot/tools/quiz_expansion/merge.py --dry-run` で追加数を確認し、問題なければ `merge.py` を実行。
6. ゲーム（Godot）で `offline_bank.json` が読み込めること、メニューの問題数表示が増えていることを確認する。
7. `offline_bank.json` の変更をコミットする。master への merge と push はリポジトリの持ち主が確認してから行う。
