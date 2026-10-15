# kkb — 要領書メーカー

スマホで作業要領書を作る1ファイルのWebアプリ。写真に文字・矢印・囲み・番号を書き込み、A4のPDFかJPEG画像で保存する。

## 構成
- `index.html` だけで完結(ビルドなし)。外部読み込みは jsPDF 2.5.1(cdnjs)と Google Fonts の BIZ UDPGothic のみ。
- データはブラウザの IndexedDB(`yoryosho` / `docs`)に自動保存。現在の要領書IDは localStorage `yoryosho.current`。
- 書き込みの座標は写真に対する比率(0〜1)で持つ。サイズは写真の短辺に対する倍率。
- 出力は A4 を 1240×1754px(150dpi)のキャンバスに描いてから PDF / JPEG にする(PDF に日本語フォントを埋め込まないため)。

## 保存の経路(saveFiles)
1. claude.ai Artifact 内 → `downloads` 機能
2. スマホ(pointer:coarse)→ Web Share(写真アプリ・ファイル・LINE等へ)
3. それ以外 → `<a download>`
4. どれも使えない Artifact 内 → 画像を表示し長押し保存

## 撮影
- 撮影ボタンの input に `capture` を付けない(Claude アプリ内などで capture 付きが開かないため)。OS のメニューから「写真を撮る」を選ぶ。

## PDFのレイアウト
- 写真なしの手順(`src: null`)も作れる。PDFでは文字を全幅で描き、「写真だけ保存」では飛ばす。
- 1ページ 1つ=写真の下に文字、2〜3つ=写真の右に文字、4〜10=2列(写真の下に文字、縮小)。

## 公開
- `<!--APP-START-->` 〜 `<!--APP-END-->` の間が Artifact として公開する部分(外側の doctype/head/body と、間の `</head><body>` は公開時に除く)。

## 確認
- Chromium(Playwright)でモバイル幅にして読み込み → 写真編集 → PDF 出力までを流す。
