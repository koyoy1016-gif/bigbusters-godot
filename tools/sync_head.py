#!/usr/bin/env python3
"""web/head/*.js（名前の順）を、export_presets.cfg の3つの html/head_include に書き込む。
JS を直すときは、export_presets.cfg ではなく web/head/*.js を直して、これを実行する。
制約：cfg の文字列の中に入れるので、JS には二重引用符と円記号（バックスラッシュ）を使わない（' を使う）。
使い方: python3 tools/sync_head.py        （書き込む）
        python3 tools/sync_head.py --check（ずれていないか確認。ずれていれば終了コード1）"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parts = sorted((root / "web" / "head").glob("*.js"))
body = "\n".join(p.read_text() .rstrip("\n") for p in parts)
for p in parts:
    text = p.read_text()
    if '"' in text or "\\" in text:
        sys.exit("使えない文字（\" か \\）が %s にあります" % p.name)
new = 'html/head_include="<script>\n' + body + '\n</script>"\n'
cfg_path = root / "export_presets.cfg"
cfg = cfg_path.read_text()
pattern = re.compile(r'html/head_include="(?:<script>\n.*?\n</script>)?"\n', re.S)
matches = pattern.findall(cfg)
targets = [m for m in matches if m.startswith('html/head_include="<script>')]
if len(targets) != 3:
    sys.exit("head_include が3つ見つかりません（%d）" % len(targets))
if "--check" in sys.argv:
    sys.exit(0 if all(t == new for t in targets) else 1)
out = pattern.sub(lambda m: new if m.group(0).startswith('html/head_include="<script>') else m.group(0), cfg)
cfg_path.write_text(out)
print("書き込みました：%d ファイル → 3つのプリセット" % len(parts))
