# HTML のアピール資料を PowerPoint に移す道具

2026-11-01 に `../02_appeal.html` を `docs/submission/02_アピール資料.pptx` に移したときのもの。
**もう一度実行すると、PowerPoint で直したところは消える**（HTML から作り直すため）。ふだんは使わない。

```
python -I docs/submission/pdf/to_pptx/run_extract.py <作業フォルダ>/deck.json
python -I docs/submission/pdf/to_pptx/build_pptx.py <作業フォルダ>/deck.json docs/submission/pdf/to_pptx/base.pptx <作業フォルダ>/02.pptx
powershell -File docs/submission/pdf/to_pptx/export.ps1 -Pptx <作業フォルダ>\02.pptx -OutDir <確認用 PNG のフォルダ> -SavePptx <保存先.pptx> -Pdf <保存先.pdf>
```

| ファイル | 役目 |
|---|---|
| `extract.js` | Edge で HTML を開いたまま、各ページの箱・画像・文字・矢印・三角・表の位置と見た目を JSON にする（下書きの印は `#final` で消した状態） |
| `run_extract.py` | Edge のヘッドレスで `extract.js` を動かし、JSON を書き出す |
| `build_pptx.py` | JSON から各ページの PowerPoint の図形（DrawingML）を組む。追加のライブラリは使わない |
| `base.pptx` | PowerPoint で作った白紙 15 ページ（16:9、テーマのフォントは Noto Sans JP） |
| `export.ps1` | PowerPoint を動かして、確認用の PNG・保存し直した .pptx・PDF を書き出す |

移すときに決めたこと

- 1 px = 0.5 pt（1920×1080 → 960×540 pt）。文字の太さはフォント名で表す（Noto Sans JP Medium・SemiBold・ExtraBold・Black、700 は Noto Sans JP の太字）。
  Windows に `../fonts/` の 6 本が入っていること。
- 画像は元の画像を入れて、PowerPoint のトリミングで切り抜く（あとでトリミングを直せる）。SVG のロゴは SVG のまま（古い PowerPoint 用の PNG つき）。
- 文字の箱は、PowerPoint の折り返しが Chrome より早くならないよう 2% 広げた。表は右の余白を同じだけ減らした。そのため、改行の位置が HTML 版と少し違う行がある。
- 縦書きの帯のラベル（「試合ごと」「毎晩」「メニュー」「ステージ」）は、1 字ずつ改行して積んだ。PowerPoint の縦書きは Noto Sans JP の小さい字でかな・カナが横に倒れるため。長音「ー」は「丨」にした。
- ページ番号は PowerPoint の自動の番号（`/ 15` は文字）。
