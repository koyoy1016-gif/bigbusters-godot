#!/bin/bash
# 8人の待ちの姿勢を1枚に並べる：tools/idle_sheet.sh 出力.jpg [向き度] [動き]
cd "$(cd "$(dirname "$0")/.." && pwd)"
out=$1; yaw=${2:--30}; act=${3:-idle}
ids="brawler sprinter gunner bomber mage guardian summoner healer"
for id in $ids; do
  timeout 100 xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-/home/claude/godot/godot}" --rendering-driver opengl3 --path . --script res://tools/shot_anim.gd -- $id $act /tmp/idle_$id.png 1 $yaw 0.5 0.5 >/dev/null 2>&1
done
python3 - "$out" $ids <<'PY'
import sys
from PIL import Image
ims=[Image.open(f"/tmp/idle_{i}.png").convert("RGB") for i in sys.argv[2:]]
o=Image.new("RGB",(sum(i.width for i in ims),ims[0].height),(255,255,255)); x=0
for i in ims: o.paste(i,(x,0)); x+=i.width
o.save(sys.argv[1],quality=80); print("saved",sys.argv[1])
PY
