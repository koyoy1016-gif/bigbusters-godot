#!/bin/bash
# キャラの4つの技（A・Y・X・必殺）の動きを、1枚に並べる：tools/moves_sheet.sh キャラのid 動きの頭（Brawler など） 出力.jpg [向き度]
cd "$(cd "$(dirname "$0")/.." && pwd)"
id=$1; pre=$2; out=$3; yaw=${4:--40}
for k in A Y X Ult; do
  timeout 200 xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-/home/claude/godot/godot}" --rendering-driver opengl3 --path . --script res://tools/shot_anim.gd -- $id ${pre}_$k /tmp/mv_$k.png 7 $yaw >/dev/null 2>&1
done
python3 - "$out" <<'PY'
import sys
from PIL import Image
ims=[Image.open(f"/tmp/mv_{k}.png").convert("RGB") for k in ("A","Y","X","Ult")]
w=max(i.width for i in ims); h=sum(i.height for i in ims)
o=Image.new("RGB",(w,h),(255,255,255)); y=0
for i in ims: o.paste(i,(0,y)); y+=i.height
o=o.resize((o.width//2,o.height//2)); o.save(sys.argv[1],quality=78); print("saved",sys.argv[1])
PY
