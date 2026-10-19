"""ゲーム内で使う文字だけを含む日本語フォントを作る（Web版・端末に日本語フォントが無い時用）。
使い方: python3 -I tools/subset_font.py <元のNotoSerifJP.ttf> assets/fonts/NotoSerifJP-SemiBold-subset.ttf
文字を追加したら（新しい台詞・UI文言）実行し直す。必要: pip install fonttools
"""
import pathlib
import sys

from fontTools import subset

src, dst = sys.argv[1], sys.argv[2]
root = pathlib.Path(__file__).resolve().parent.parent
chars = set()
for p in list(root.glob("scripts/**/*.gd")) + list(root.glob("scenes/*.tscn")):
    chars.update(p.read_text(encoding="utf-8"))
# 将来の文言追加に備えて、かな・英数・記号は全部入れる
for lo, hi in [(0x20, 0x7E), (0x3000, 0x30FF), (0xFF01, 0xFF5E), (0x2010, 0x2027)]:
    chars.update(chr(c) for c in range(lo, hi + 1))
text = "".join(sorted(c for c in chars if c.isprintable()))
opts = subset.Options()
opts.layout_features = ["*"]
opts.name_IDs = ["*"]
opts.notdef_outline = True
font = subset.load_font(src, opts)
s = subset.Subsetter(opts)
s.populate(text=text)
s.subset(font)
subset.save_font(font, dst, opts)
print(f"{len(text)} chars -> {dst} ({pathlib.Path(dst).stat().st_size // 1024} KB)")
