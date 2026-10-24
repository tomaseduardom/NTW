"""Parte un .gd de funciones (estáticas o de instancia) en una cadena de herencia por familias.

Uso: python -I splitter.py <archivo.gd> <plan.json> [--dry]
plan.json: {"base": "NombreBase", "layers": [{"name": "Familia", "from": "texto del título de sección"}, ...]}
- La primera capa empieza en la primera sección cuyo título contiene layers[0].from, etc. Lo que está
  antes de la primera sección (cabecera, consts, tablas, ayudas iniciales) va a la base.
- Consts, enums, signals, vars y static vars van siempre a la base.
- Una función usada desde una capa anterior a la suya baja a la base (con lo que ella use).
- La última capa queda en el archivo original (mismas rutas y llamadas desde afuera).
"""
import re, sys, json, os

path, plan_path = sys.argv[1], sys.argv[2]
dry = '--dry' in sys.argv
plan = json.load(open(plan_path, encoding='utf-8'))
src = open(path, encoding='utf-8').read()
lines = src.split('\n')

# --- cabecera: extends / class_name / docstring inicial (## pegados arriba)
i = 0
header = []
class_name = None
extends = None
while i < len(lines) and (lines[i].startswith('extends') or lines[i].startswith('class_name')
        or lines[i].startswith('##') or lines[i].strip() == ''):
    if lines[i].startswith('class_name'):
        class_name = lines[i]
    elif lines[i].startswith('extends'):
        extends = lines[i]
    elif lines[i].startswith('##'):
        header.append(lines[i])
    i += 1
# Un "##" pegado a la primera definición es su doc, no de la cabecera: se devuelve.
while header and i > 0 and lines[i - 1].startswith('##'):
    header.pop()
    i -= 1
body_start = i

# --- bloques de nivel superior
TOP = re.compile(r'^(static func|func|const|static var|var|enum|signal|class) ')
blocks = []  # {kind, name, text(lines), section_idx}
pending_comments = []
section_titles = []  # (line_index_in_blocks_order, title)
cur = None
j = body_start
def flush():
    global cur
    if cur:
        blocks.append(cur)
    cur = None

while j < len(lines):
    l = lines[j]
    if l.startswith('# ====='):
        flush()
        title = lines[j + 1] if j + 1 < len(lines) else ''
        k = j + 1
        sec_lines = [l]
        while k < len(lines) and lines[k].startswith('#') and not lines[k].startswith('##'):
            sec_lines.append(lines[k])
            k += 1
            if lines[k - 1].startswith('# =====') and len(sec_lines) > 1:
                break
        blocks.append({'kind': 'section', 'name': title, 'text': pending_comments + sec_lines})
        pending_comments = []
        j = k
        continue
    m = TOP.match(l)
    if m:
        flush()
        kind = m.group(1)
        name = re.match(r'^(?:static func|func|const|static var|var|enum|signal|class) (\w+)', l).group(1)
        cur = {'kind': kind, 'name': name, 'text': pending_comments + [l]}
        pending_comments = []
        j += 1
        # cuerpo: líneas indentadas, en blanco o continuación de una expresión multilínea
        depth = l.count('(') + l.count('[') + l.count('{') - l.count(')') - l.count(']') - l.count('}')
        while j < len(lines):
            nl = lines[j]
            if depth <= 0 and nl and not nl[0].isspace() and not nl.startswith('#'):
                break
            if depth <= 0 and (nl.startswith('##') or nl.startswith('# ')) and kind not in ('static func', 'func'):
                break
            if depth <= 0 and nl.startswith('#') and kind in ('static func', 'func'):
                # comentario de nivel superior: pertenece al siguiente bloque si le sigue una definición
                k = j
                while k < len(lines) and lines[k].startswith('#'):
                    k += 1
                if k < len(lines) and (TOP.match(lines[k]) or lines[k].startswith('# =====')) or lines[j].startswith('# ====='):
                    break
            cur['text'].append(nl)
            depth += nl.count('(') + nl.count('[') + nl.count('{') - nl.count(')') - nl.count(']') - nl.count('}')
            j += 1
        # quitar líneas en blanco finales del bloque (se reponen al escribir)
        while cur['text'] and cur['text'][-1].strip() == '':
            cur['text'].pop()
        continue
    if l.startswith('#'):
        pending_comments.append(l)
    j += 1
flush()
if pending_comments:
    blocks.append({'kind': 'comment', 'name': '', 'text': pending_comments})

# --- capa de cada bloque según secciones
layer_names = [plan['base']] + [L['name'] for L in plan['layers']]
layer = 0
next_layer = 0
for b in blocks:
    if next_layer < len(plan['layers']):
        spec = plan['layers'][next_layer]
        starts = (b['kind'] == 'section' and 'from' in spec and spec['from'] in b['name']) \
            or (b['kind'] in ('static func', 'func') and spec.get('func') == b['name'])
        if starts:
            next_layer += 1
            layer = next_layer
    b['layer'] = layer
assert next_layer == len(plan['layers']), 'no se encontraron todos los cortes del plan'
for b in blocks:
    if b['kind'] in ('const', 'static var', 'var', 'enum', 'signal', 'class'):
        b['layer'] = 0

# Orden de la cadena (de abajo hacia arriba): por defecto el del archivo; 'order' pone primero las
# familias más usadas por las demás (así menos funciones bajan a la base).
if 'order' in plan:
    src_names = [L['name'] for L in plan['layers']]
    rank = {0: 0}
    for idx, nm in enumerate(src_names):
        rank[idx + 1] = plan['order'].index(nm) + 1
    for blk in blocks:
        blk['layer'] = rank[blk['layer']]
    layer_names = [plan['base']] + plan['order']
funcs = {b['name']: b for b in blocks if b['kind'] in ('static func', 'func')}
names = set(funcs) | {b['name'] for b in blocks if b['kind'] in ('const', 'static var', 'var', 'enum', 'class')}
def uses(b):
    body = '\n'.join(b['text'][1:]) if b['kind'] in ('static func', 'func') else '\n'.join(b['text'])
    body = re.sub(r'"(?:[^"\\]|\\.)*"', '""', body)  # sin literales
    body = re.sub(r'#.*', '', body)
    return {n for n in re.findall(r'(?<![\.\w])(\w+)\b', body) if n in funcs}

changed = True
while changed:
    changed = False
    for b in blocks:
        for n in uses(b):
            g = funcs[n]
            if g['layer'] > b['layer']:
                g['layer'] = b['layer'] if b['kind'] in ('static func', 'func') else 0
                changed = True

counts = {}
for b in blocks:
    if b['kind'] in ('static func', 'func'):
        counts[b['layer']] = counts.get(b['layer'], 0) + 1
print('funciones por capa:', {layer_names[k]: v for k, v in sorted(counts.items())})

# --- escribir
d = os.path.dirname(path)
stem = os.path.splitext(os.path.basename(path))[0]
res_dir = 'res://' + d.replace('\\', '/') + '/'
files = []
n_layers = len(layer_names)
for k in range(n_layers):
    is_leaf = k == n_layers - 1
    fname = os.path.basename(path) if is_leaf else '%s%s.gd' % (stem, layer_names[k])
    out = []
    if k == 0:
        out.append(extends or 'extends RefCounted')
        out.append('## %s%s — base de %s.gd: constantes, tablas y ayudas compartidas por todas las familias.' % (stem, layer_names[0], stem))
        out.append('## Cadena: %s. Lo de afuera usa solo %s.gd (hereda todo).' % (' <- '.join(
            ['%s%s' % (stem, n) for n in layer_names[:-1]] + [stem]), stem))
        out.append('')
        out.extend(header)
    else:
        prev = '%s%s.gd' % (stem, layer_names[k - 1])
        if is_leaf and class_name:
            out.append(class_name)
        out.append('extends "%s%s"' % (res_dir, prev))
        if is_leaf:
            out.append('## %s — familia %s (ver %s%s.gd para la cabecera, constantes y ayudas).' % (stem, layer_names[k], stem, layer_names[0]))
        else:
            out.append('## %s%s — familia %s de %s.gd (ver %s%s.gd).' % (stem, layer_names[k], layer_names[k], stem, stem, layer_names[0]))
        out.append('')
    for b in blocks:
        if b.get('layer') != k:
            continue
        if b['kind'] == 'section':
            out.append('')
            out.extend(b['text'])
            continue
        out.append('')
        if b['kind'] in ('static func', 'func'):
            out.append('')
        out.extend(b['text'])
    text = '\n'.join(out).rstrip('\n') + '\n'
    text = re.sub(r'\n{4,}', '\n\n\n', text)
    files.append((os.path.join(d, fname), text))

total_in = len([l for l in lines if l.strip()])
total_out = sum(len([l for l in t.split('\n') if l.strip()]) for _, t in files)
print('líneas no vacías: original %d, partido %d (+%d por cabeceras)' % (total_in, total_out, total_out - total_in))
for p, t in files:
    print('  %s: %d líneas' % (p, t.count('\n')))
if not dry:
    for p, t in files:
        open(p, 'w', encoding='utf-8', newline='\n').write(t)
