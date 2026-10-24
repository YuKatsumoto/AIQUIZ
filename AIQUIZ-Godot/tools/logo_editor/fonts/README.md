# ロゴの書体

| ファイル | 書体 | 入手先 | ライセンス |
| --- | --- | --- | --- |
| `Stereofunk.ttf` | Stereofunk（Display）／ Alan Brown（alanbrowndesign） | https://www.dafont.com/stereofunk.font （2026-10-19 に取得） | DaFont の表示は「100% Free」。zip に説明書きは無く、フォントの中は「All rights reserved」。公開前に作者へ商用利用の確認をとる |

ゲームはこの書体を読まない。`tools/logo_editor/extract_font_glyphs.py` が字形を多角形にして
`tools/logo_editor/testopia_font_glyphs.json` に書き出し、`build_testopia_logo.mjs` がそれでロゴを組む。
このフォルダは `.gdignore` で Godot の読み込みから外している。
