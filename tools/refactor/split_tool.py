#!/usr/bin/env python3
"""stick_prototype.gd から、決めた関数（と、その関数の中だけで使う変数）を、別のファイルへ移す道具（コミットしない）。
使い方: python3 split_tool.py 本体.gd 新しいファイル.gd 部品の変数名 部品のクラス名 "説明" 関数名,関数名,...
- 移した関数の中の、本体のメンバー（変数・関数・シグナル）には「b.」を付ける（b は本体）。
- 移した関数どうしの呼び出しと、移した変数は、そのまま。
- 本体の外（本体の残り・テスト・道具・ほかのスクリプト）から呼ばれる関数は、本体に「取り次ぎ」を残す。
- 本体の const（preload など）は、新しいファイルにも写す。
"""
import re, sys, os, glob

src_path, out_path, part_var, part_class, desc, names_csv = sys.argv[1:7]
move_funcs = [n for n in names_csv.split(",") if n]
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(src_path))))
lines = open(src_path, encoding="utf-8").read().split("\n")

# ---- 上の段（インデントなし）の区切りで、かたまりに分ける ----
TOP = re.compile(r'^(static func|func|var|const|signal|@onready var|@export var|class_name|extends|enum)\b')
blocks = []  # {kind, name, start, end(含まない)}
i = 0
n = len(lines)
starts = []
for idx, l in enumerate(lines):
    if TOP.match(l):
        starts.append(idx)
for k, s in enumerate(starts):
    e = starts[k + 1] if k + 1 < len(starts) else n
    # 次のかたまりの直前の、説明（## / #）と空行は、次のかたまりに付ける
    j = e
    while j - 1 > s and (lines[j - 1].startswith("#") or lines[j - 1].strip() == ""):
        j -= 1
    m = TOP.match(lines[s])
    kind = m.group(1)
    rest = lines[s][m.end():].strip()
    name = re.match(r'[A-Za-z_]\w*', rest).group(0) if re.match(r'[A-Za-z_]\w*', rest) else ""
    blocks.append({"kind": kind, "name": name, "start": s, "end": j})
# 各かたまりの前の説明行の始まり
for k, b in enumerate(blocks):
    prev_end = blocks[k - 1]["end"] if k > 0 else 0
    c = b["start"]
    while c - 1 >= prev_end and lines[c - 1].startswith("#"):
        c -= 1
    b["doc"] = c

members = {}
for b in blocks:
    if b["kind"] in ("var", "@onready var", "@export var"):
        members[b["name"]] = "var"
    elif b["kind"] in ("func", "static func"):
        members[b["name"]] = b["kind"]
    elif b["kind"] == "signal":
        members[b["name"]] = "signal"
# 本体（Node3D）がもともと持っている関数・値。移した先（RefCounted）にはないので、b. を付ける
for nm in ["add_child", "remove_child", "get_node", "get_node_or_null", "has_node", "is_inside_tree", "get_children", "get_child",
           "get_child_count", "get_viewport", "get_window", "get_tree", "get_parent", "find_child", "find_children", "queue_free",
           "is_node_ready", "get_world_3d", "position", "rotation", "global_position", "global_transform", "transform", "visible", "name",
           "set_process", "create_tween", "get_meta", "set_meta", "has_meta", "emit_signal", "call_deferred", "get_process_delta_time"]:
    members.setdefault(nm, "builtin")
consts = [b for b in blocks if b["kind"] == "const"]
const_names = {b["name"] for b in consts}
func_blocks = {b["name"]: b for b in blocks if b["kind"] in ("func", "static func")}
for f in move_funcs:
    if f not in func_blocks:
        sys.exit("ない関数: " + f)

TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_]\w*|#.*|\S')


def body_text(b):
    return "\n".join(lines[b["start"]:b["end"]])


def idents(text):
    out = []
    for line in text.split("\n"):
        prev = ""
        for m in TOKEN.finditer(line):
            t = m.group(0)
            if t.startswith("#"):
                break
            if t[0] in "\"'":
                prev = t
                continue
            if re.match(r'[A-Za-z_]', t) and prev != ".":
                out.append(t)
            prev = t
    return out


# 本体の外で使われる名前（テスト・道具・ほかのスクリプト）
outside_text = ""
for p in glob.glob(os.path.join(REPO, "tests", "*.gd")) + glob.glob(os.path.join(REPO, "tools", "*.gd")) + glob.glob(os.path.join(REPO, "scripts", "**", "*.gd"), recursive=True):
    if os.path.abspath(p) in (os.path.abspath(src_path), os.path.abspath(out_path)):
        continue
    outside_text += open(p, encoding="utf-8").read() + "\n"
outside_words = set(re.findall(r'[A-Za-z_]\w*', outside_text))

moved_set = set(move_funcs)
def _rem_text(b):
    t = body_text(b)
    if b["kind"] in ("var", "@onready var", "@export var"):
        t = t.replace(b["name"], "", 1)  # 自分の宣言の名前は数えない
    return t
remaining_text = "\n".join(_rem_text(b) for b in blocks if not (b["kind"] in ("func", "static func") and b["name"] in moved_set))
remaining_ids = set(idents(remaining_text))
# signal の connect（_draw_overlay など）は、残りの文字の中に名前として出る
moved_text = "\n".join(body_text(func_blocks[f]) for f in move_funcs)
moved_ids = set(idents(moved_text))

# 移す変数：移した関数の中で使われ、本体の残り・外では使われない
move_vars = [b["name"] for b in blocks if b["kind"] == "var" and b["name"] in moved_ids and b["name"] not in remaining_ids and b["name"] not in outside_words]
move_var_set = set(move_vars)
# 取り次ぎがいる関数：本体の残りか、外で使われる
need_wrap = [f for f in move_funcs if f in remaining_ids or f in outside_words]


def locals_of(func_text):
    loc = set()
    sig = func_text.split("\n")[0]
    for m in re.finditer(r'func\s*\w*\s*\(([^)]*)\)', func_text):
        for p in m.group(1).split(","):
            p = p.strip()
            if p:
                loc.add(re.match(r'[A-Za-z_]\w*', p).group(0))
    for m in re.finditer(r'\bvar\s+([A-Za-z_]\w*)', func_text):
        loc.add(m.group(1))
    for m in re.finditer(r'\bconst\s+([A-Za-z_]\w*)', func_text):
        loc.add(m.group(1))
    for m in re.finditer(r'\bfor\s+([A-Za-z_]\w*)\s+in\b', func_text):
        loc.add(m.group(1))
    return loc


def transform(func_text, is_static):
    loc = locals_of(func_text)
    clash = loc & set(members)
    out_lines = []
    for li, line in enumerate(func_text.split("\n")):
        res = []
        pos = 0
        prev = ""
        for m in TOKEN.finditer(line):
            t = m.group(0)
            res.append(line[pos:m.start()])
            pos = m.end()
            if t.startswith("#"):
                res.append(t)
                prev = t
                continue
            if t[0] in "\"'":
                res.append(t)
                prev = t
                continue
            word = re.match(r'[A-Za-z_]\w*$', t)
            if word and prev != "." and li > 0:
                if t == "b" and "b" in loc:
                    t = "bk"  # 元の、b という名前のローカル変数（本体の b とぶつかるので名前を変える）
                elif t == "self":
                    t = "b"
                elif t in members and t not in loc and t not in moved_set and t not in move_var_set:
                    if is_static:
                        sys.exit("static 関数が本体のメンバーを使う: %s in %s" % (t, func_text.split(chr(10))[0]))
                    t = "b." + t
            res.append(t)
            prev = t
        res.append(line[pos:])
        out_lines.append("".join(res))
    return "\n".join(out_lines), clash


# ---- 新しいファイル ----
rel_out = "res://" + os.path.relpath(out_path, REPO)
out = []
out.append("extends RefCounted")
out.append("## " + desc)
out.append("## stick_prototype.gd（まとめ役。状態の変数はそちら）から分けた部品。本体の変数・関数は b. で使う。動きは分ける前と同じ。")
out.append("")
for b in consts:
    out.append("\n".join(lines[b["start"]:b["end"]]).rstrip())
out.append("")
out.append("var b: StickPrototype  ## まとめ役（stick_prototype.gd）")
for v in move_vars:
    vb = next(x for x in blocks if x["kind"] == "var" and x["name"] == v)
    txt, _ = transform("\n".join(lines[vb["doc"]:vb["end"]]).rstrip(), False)
    out.append(txt)
out.append("")
out.append("")
out.append("func _init(main: StickPrototype) -> void:")
out.append("\tb = main")
out.append("")
clashes = []
for f in move_funcs:
    fb = func_blocks[f]
    txt = "\n".join(lines[fb["doc"]:fb["end"]]).rstrip()
    t2, clash = transform(txt, fb["kind"] == "static func")
    if clash:
        clashes.append((f, sorted(clash)))
    out.append("")
    out.append(t2)
    out.append("")
open(out_path, "w", encoding="utf-8").write("\n".join(out).rstrip() + "\n")

# ---- 本体：移した物を消し、取り次ぎを置く ----
remove = set()
for f in move_funcs:
    fb = func_blocks[f]
    remove.update(range(fb["doc"], fb["end"]))
for v in move_vars:
    vb = next(x for x in blocks if x["kind"] == "var" and x["name"] == v)
    remove.update(range(vb["doc"], vb["end"]))
wrappers = {}
for f in need_wrap:
    fb = func_blocks[f]
    sig = lines[fb["start"]]
    m = re.match(r'(static func|func)\s+(\w+)\s*\((.*)\)\s*(->\s*([\w\[\]]+))?\s*:', sig)
    params = [p.strip() for p in m.group(3).split(",") if p.strip()]
    args = ", ".join(re.match(r'[A-Za-z_]\w*', p).group(0) for p in params)
    ret = m.group(5)
    call = ("%s.%s(%s)" % (part_class, f, args)) if fb["kind"] == "static func" else ("%s.%s(%s)" % (part_var, f, args))
    body = ("\t" + call) if ret == "void" else ("\treturn " + call)
    wrappers[fb["doc"]] = ["## → %s" % os.path.basename(out_path), sig, body, "", ""]
new = []
for idx, l in enumerate(lines):
    if idx in wrappers:
        new.extend(wrappers[idx])
    if idx in remove:
        continue
    new.append(l)
text = "\n".join(new)
text = re.sub(r'\n{4,}', '\n\n\n', text)
open(src_path, "w", encoding="utf-8").write(text)

print("移した関数", len(move_funcs), "取り次ぎ", len(need_wrap), need_wrap)
print("移した変数", move_vars)
if clashes:
    print("注意：ローカル変数と本体のメンバーが同じ名前", clashes)
