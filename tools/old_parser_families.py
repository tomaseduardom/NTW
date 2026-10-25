# Agrupa por mecanismo los textos que resuelve el analizador viejo (salida .json de tools/old_parser_report.tscn).
# Uso: python tools/old_parser_families.py informe.md.json salida.json
import json,sys,re,collections
rows=json.load(open(sys.argv[1],encoding='utf-8'))
# Oraciones que otro sistema ya resuelve (palabras clave, restricciones de juego, inmunidades).
SKIP=re.compile(r"^(unica|no puede ser anulad[ao]|solo puedes jugarl[oa]\b[^.]*|no puedes jugar\b[^.]*|imbloqueable|furia|indestructible|guardian|exhumar|errante|inmunidad\b[^.]*|retador|primer ataque|dominador)$")
MECH=[
 ("elegir uno de varios efectos", r"elige (un|uno|dos) (efecto|de los siguientes)|elige uno:|^- "),
 ("mostrar hasta / reparto",       r"hasta (mostrar|que muestres)|muestra las? (primeras|\w+ cartas del tope)|el resto (al|en|a)|pon(las?|los?)? en (tu mano|juego|el cementerio)"),
 ("buscar y hacer algo con ella", r"busca"),
 ("coste con 'para' (destruirlo/desterrarlo/pagar para...)", r"(puedes|para) (destruir|desterrar|barajar|pagar|descartar|botar)\w* [^.]*? para "),
 ("cantidad variable (tantas/por cada/igual a/fuerza o coste)", r"tantas|tantos|por cada|igual a|como (coste|fuerza)|de oros pagados"),
 ("cada jugador / ambos jugadores", r"cada jugador|los jugadores|ambos jugadores"),
 ("efecto que hace el oponente", r"^tu oponente|tu oponente (debe|descarta|destierra|baraja|bota|roba|elige|muestra)"),
 ("condicion 'si ...'", r"(^|[ ,.])si (controlas|porta|tienes|tu|es|hay|el|la|esta|no)\b"),
 ("alternativa 'X o Y'", r"\b(roba\w*|destru\w+|destierr\w+|baraj\w+|bota\w*|descart\w+|anul\w+) [^.]*? o (robar|destruir|desterrar|barajar|botar|descartar|anular|jugar|poner|ganar)"),
 ("dos acciones encadenadas", r"( y | luego |\. )(roba|robas|destruye|destierra|baraja|bota|descarta|gana|pierde|anula|pon|juega|busca|mira|muestra|no recibes|tu dano|un aliado|tu oponente|una carta en juego|robar|barajar|desterrar|destruir)"),
 ("filtro de objetivo", r"de coste|que no sea|de fuerza|sin habilidad|con habilidad|aliado|oro|arma|totem|talisman|de tu mano|cementerio|al azar|del tope|del fondo"),
 ("duracion / hasta tu proximo turno", r"hasta (tu|el) (proximo|final)"),
]
def effect(t):
    t=re.sub(r"^(?:(?:cuando|al comienzo|al final|en tu|en la|una vez|hasta (?:una|dos|tres) veces?)[^,]*, )+","",t.strip())
    sents=[s.strip() for s in re.split(r"\.\s*",t) if s.strip()]
    return ". ".join(s for s in sents if not SKIP.match(s))
fam=collections.defaultdict(list)
for r in rows:
    e=effect(r['efecto'])
    tag=None
    for name,rx in MECH:
        if re.search(rx,e):
            tag=name;break
    r['mecanismo']=tag or "simple (lo cubre)"
    r['efecto_limpio']=e
    fam[r['mecanismo']].append(r)
json.dump(rows,open(sys.argv[2],'w',encoding='utf-8'),ensure_ascii=False,indent=1)
for k,v in sorted(fam.items(),key=lambda kv:-len(kv[1])):
    print(len(v),k)
    for r in v[:4]: print('    -',r['carta'][:18].encode('ascii','replace').decode(),'|',r['accion'].split(' ')[0],'|',r['efecto_limpio'][:95].encode('ascii','replace').decode())
