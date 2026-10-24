"""Bloques que pasaron a compilados entre dos auditorías (tools/audit_cards.gd) y que además detecta
algún patrón que corre DESPUÉS de EffectInterpreter en TriggerResolution._resolve_look_and_play_patterns():
esos cambian de dueño (antes los resolvía el patrón, ahora el compilador) y hay que comparar a mano.
Los patrones de antes del intérprete (ActivatedPatterns, Azi, Dagon...) y los botones de habilidad
siguen ganando: no aparecen.
Uso: python -I tools/hijack_check.py base.json nuevo.json
"""
import json, sys, os, re, unicodedata

POST = ['LookAndPlayResolver.gd', 'LookRevealPatterns.gd', 'LookRevealPatternsA.gd', 'LookRevealPatternsB.gd',
        'SearchOwnZonePatterns.gd', 'BanishOpponentPatterns.gd', 'ShuffleDrawPatterns.gd', 'GoldConversionPatterns.gd',
        'PlayFromCemeteryPatterns.gd', 'MiscUniquePatterns.gd', 'TotemAbilityPatterns.gd', 'WeaponAbilityPatterns.gd',
        'OroAbilityPatterns.gd', 'CastleLook.gd', 'TalismanSearchPatterns.gd']


def fold(s):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFD', s.lower()) if unicodedata.category(c) != 'Mn').split())


def load(p):
    return {c['id']: c for c in json.loads(open(p, encoding='utf-8').read(), strict=False)}


phrases = {}
for dp, _, fs in os.walk('scripts'):
    for f in fs:
        if f in POST:
            text = open(os.path.join(dp, f), encoding='utf-8').read()
            for line in text.split('\n'):
                if line.strip().startswith('#') or '"""' in line:
                    continue
                for lit in re.findall(r'"([^"\\]{14,})"', line):
                    phrases.setdefault(fold(lit), f)

a, b = load(sys.argv[1]), load(sys.argv[2])
seen = set()
for k, c in b.items():
    ca = a.get(k)
    if not ca:
        continue
    for x, y in zip(ca['bloques'], c['bloques']):
        if x['estado'] == y['estado'] or y['estado'] != 'compilada':
            continue
        key = (c['nombre'].lower(), y['texto'])
        if key in seen:
            continue
        seen.add(key)
        t = fold(y['texto'])
        hits = sorted({f for ph, f in phrases.items() if ph in t})
        print('%-24s | %s' % (c['nombre'][:24], ', '.join(hits) if hits else 'ok (sin patrón posterior)'))
