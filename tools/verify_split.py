"""Compara el original (git HEAD) con la cadena partida: mismas definiciones de nivel superior,
cada una una sola vez y con el mismo texto (ignorando líneas en blanco)."""
import re, subprocess, sys, glob, os
path = sys.argv[1]
stem = os.path.splitext(path)[0]
orig = subprocess.run(['git', 'show', 'HEAD:' + path], capture_output=True, text=True, encoding='utf-8').stdout
TOP = re.compile(r'^(static func|func|const|static var|var|enum|signal|class) (\w+)')

def defs(text):
    out = {}
    lines = text.split('\n')
    cur = None
    for l in lines:
        m = TOP.match(l)
        if m:
            cur = m.group(2)
            out.setdefault(cur, []).append([l])
            continue
        if cur is None:
            continue
        if l and not l[0].isspace() and not l.startswith('#') and not l.startswith(')') and not l.startswith(']') and not l.startswith('}'):
            cur = None
            continue
        if l.startswith('#') :
            continue
        out[cur][-1].append(l)
    return {k: ['\n'.join(x for x in v if x.strip()) for v in vs] for k, vs in out.items()}

o = defs(orig)
new_text = ''
files = []
cur_file = path
while cur_file:
    files.append(cur_file)
    first = [l for l in open(cur_file, encoding='utf-8').read().splitlines() if l.startswith('extends')][0]
    m = re.match(r'extends "res://(.+)"', first)
    cur_file = m.group(1) if m else None
for f in files:
    new_text += '\n' + open(f, encoding='utf-8').read()
n = defs(new_text)
problems = 0
for k, v in o.items():
    if k not in n:
        print('FALTA', k); problems += 1
    elif len(n[k]) != len(v):
        print('CANTIDAD', k, len(v), len(n[k])); problems += 1
    elif sorted(n[k]) != sorted(v):
        print('DISTINTA', k); problems += 1
for k in n:
    if k not in o:
        print('NUEVA', k); problems += 1
print('%s: %d definiciones, %d problemas' % (path, len(o), problems))
