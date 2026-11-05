"""Clasifica cada habilidad de data/cards.json en disparada, activada o continua.

Unidad: cada párrafo (línea) del texto de la carta; las palabras clave sueltas al comienzo ("Furia.
Indestructible.") se separan como habilidades continuas propias. Los Talismanes son la excepción:
su texto es el efecto que ocurre al jugarlos (ni disparada ni activada ni continua), salvo las
frases que sí son una habilidad (p.ej. "Puedes pagar un Oro y Barajar esta carta desde tu mano...").

Criterio (DAR, con las decisiones del proyecto):
  - Disparada: ocurre sola cuando pasa algo ("Cuando...", "Al comienzo...", "En tu Fase Final..."),
    aunque diga "puedes" (disparada opcional). Las respuestas también: Anular, Cancelar o Prevenir algo
    del rival es disparada (la dispara lo que hace el rival), aunque se pague un costo y diga "puedes".
  - Activada: el jugador decide cuándo usarla, con un costo o un límite ("Una vez por turno,
    puedes...", "Puedes pagar un Oro para...", "Puedes Desterrarlo para...", "En tu Vigilia, puedes...").
  - Continua: está siempre activa mientras se cumple su condición ("Tus Aliados ganan...", "No puede
    ser...", palabras clave, permisos como "Puedes jugarlo al comienzo de cualquier Fase").
Lo que no calza con ninguna regla queda como "revisar".

Uso: python tools/clasificar_habilidades.py [--limite N]
Salida: docs/habilidades/clasificacion.csv y docs/habilidades/resumen.md
"""
import csv
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CARDS = ROOT / "data" / "cards.json"
OUT_DIR = ROOT / "docs" / "habilidades"

TIPOS = {0: "Oro", 1: "Aliado", 2: "Arma", 3: "Talismán", 4: "Tótem"}
KEYWORDS = ["furia", "imbloqueable", "indestructible", "indesterrable", "unica", "exhumar", "errante",
    "retador", "inmune", "oro inicial", "imbloqueble", "imbloquable"]


def fold(s: str) -> str:
    """Minúsculas sin tildes ni espacios repetidos."""
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(ch for ch in s if unicodedata.category(ch) != "Mn")
    return re.sub(r"\s+", " ", s).strip()


def split_keywords(par: str):
    """Separa las palabras clave sueltas del comienzo del párrafo: ('Furia', 'Cuando entra...')."""
    kws = []
    rest = par.strip()
    # La palabra clave sola, sin punto ("Exhumar"), o con una errata conocida ("Imbloqueble").
    if fold(rest).rstrip(".") in KEYWORDS + ["imbloqueble"]:
        return [rest.rstrip(".")], ""
    while True:
        m = re.match(r"^([A-Za-zÁÉÍÓÚáéíóúñÑ ]{3,20})\.\s*", rest)
        if not m or fold(m.group(1)) not in KEYWORDS:
            break
        kws.append(m.group(1).strip())
        rest = rest[m.end():]
    return kws, rest.strip()


# Una oración nueva es otra habilidad si empieza como una ("Cuando...", "Puedes...", "El portador..."); si
# no, sigue a la anterior ("Luego, Roba una carta.", "Baraja una carta oponente.").
OPENERS = r"^(cuando|cuanto|al comienzo|al final|al inicio|una vez|hasta (dos|tres|cuatro) veces|puedes|en tu |en la |en su |en guerra|en batalla|en respuesta|en el turno|en cada|tus |los aliados|las armas|el portador|su portador|si esta en|si este en|si es (destruid|desterrad|anulad|bloquead|barajad|puest|el unico)|si fuera|si hace|no puede|no pueden|no se puede|mientras|gana |tiene |es |son |solo |para (jugar|declarar|buscar|generar|afectar|poner)|reduce su coste|tu oponente (no|solo)|a tu oponente le cuesta|a los jugadores les cuesta|los jugadores (no|solo|deben)|cada vez|cada jugador|el primer|la primera|este aliado|esta arma|esta carta)"


def split_abilities(par: str, card_type: int) -> list:
    """Parte un párrafo en habilidades (ver OPENERS). Un Talismán es un solo efecto, salvo las frases
    que son habilidades propias ("Puedes...", "Cuando...", "Si está en tu Cementerio...")."""
    if not par:
        return []
    sentences = [x.strip() for x in re.split(r"(?<=[.])\s+(?=[A-ZÁÉÍÓÚÑ])", par) if x.strip()]
    out: list = []
    for x in sentences:
        f = fold(x)
        opener = re.match(OPENERS, f) is not None
        if card_type == 3:
            opener = re.match(r"^(cuando|puedes|si esta en|si este en|si es (destruid|desterrad|anulad|bloquead|barajad|botad)|si fuera|al comienzo|en tu vigilia)", f) is not None
        if out and not opener:
            out[-1] += " " + x
        else:
            out.append(x)
    return out


# (expresión sobre el texto plegado, clasificación, nombre de la regla). Se prueban en orden; gana la
# primera. Las disparadas van antes que las activadas: "Cuando entra en juego, puedes..." es disparada.
RULES = [
    # --- permisos de juego y reglas fijas que empiezan con "Puedes" pero no se activan ---
    (r"^(este aliado |esta carta )?puedes? jugarl[oa]s? (en|al comienzo|durante|desde|en la|en tu|como)", "continua", "permiso para jugarla"),
    (r"^puedes jugar (esta carta|este aliado|este talisman|este totem|esta arma)", "continua", "permiso para jugarla"),
    (r"^(tus|los) aliados pueden portar", "continua", "permiso de portar"),
    (r"^(si [^,]*, )?puedes (jugar|jugarl[oa]s?|tener|poner en juego) (?!.*\bpara\b)", "continua", "permiso para jugarla"),
    (r"^(si [^,]*, )?puedes? jugarl[oa]s? (de|desde) tu (destierro|cementerio|mano|castillo)", "continua", "permiso para jugarla"),
    (r"^(solo puedes jugarl|solo puede ser jugad|solo se puede jugar|para jugar (este|esta)|reduce su coste|entra en juego como|su coste se reduce)", "continua", "costo o condición para jugarla"),
    # --- disparadas ---
    (r"^(una vez por turno, )?cuando ", "disparada", "cuando ..."),
    (r"^(si esta|si este|si estas|mientras este|mientras esta)[^,]*, (una vez por turno, )?cuando ", "disparada", "condición + cuando ..."),
    (r"^(una vez por turno, )?(al comienzo|al final|al inicio) de", "disparada", "al comienzo / al final de ..."),
    (r"^(una vez por turno, )?en (tu|la|cada|su) (fase final|fase de agrupacion|agrupacion|guerra de talismanes|paso de|fase de batalla)", "disparada", "en tu Fase X"),
    (r"^(una vez por turno, )?en la vigilia (de tu oponente|oponente|rival)", "disparada", "en la Vigilia rival"),
    (r"^(una vez por turno, )?(despues|luego) de (que|cada)", "disparada", "después de ..."),
    (r"^(cada vez que|siempre que) ", "disparada", "cada vez que ..."),
    (r"^(si|cuando) (es|fuera|seria|va a ser) (destruid|desterrad|anulad|bloquead|barajad)", "disparada", "si es destruido..."),
    (r"^(si|cuando) (entra|sale|ataca|bloquea|es bloqueado|recibe dano|haces dano|botas|bota)", "disparada", "si entra / ataca ..."),
    (r"^(si|cuando) (hace|hiciera) dano", "disparada", "si hace daño ..."),
    (r", cuando ", "disparada", "condición, cuando ..."),
    # --- activadas ---
    (r"^(en tu vigilia, )?(una vez|dos veces) (en tu turno|por turno|por fase|por partida|por juego)", "activada", "una vez por turno"),
    (r"^en tu vigilia,? (si [^,]*, )?puedes", "activada", "en tu Vigilia, puedes ..."),
    (r"^en tu vigilia, si no (has puesto|pusiste) oros", "activada", "en tu Vigilia, puedes ..."),
    (r"^en (guerra de talismanes|tu vigilia|el turno oponente)[^.]*(una vez por turno|puedes)", "activada", "una vez por turno"),
    (r"^(en tu vigilia o fase final|en ti vigilia|una vez en tu vigilia|en tu vigilia, una vez en por turno|en su vigilia, tu oponente puede)", "activada", "en tu Vigilia, puedes ..."),
    (r"^cuanto (entra|este|sale)", "disparada", "cuando ... (errata 'cuanto')"),
    (r"^(hasta (dos|tres|cuatro) veces por turno|en tu vigilia o fase final, una vez por turno),? (si [^,]*, )?puedes", "activada", "una vez por turno"),
    (r"^(en|durante la) guerra de talismanes,? (o [^,]*,? )?(si [^,]*, )?puedes", "activada", "en Guerra de Talismanes, puedes ..."),
    (r"^en (tu turno|cualquier fase|cualquier momento),? (una vez por turno, )?puedes", "activada", "en tu turno, puedes ..."),
    (r"^(paga|pagar|destierra|baraja|descarta|bota|convierte|destruye) [^.:]{0,60}:", "activada", "costo: efecto"),
    (r"^[^.]{0,80}: ", "activada", "costo: efecto"),
    (r"^(si [^,]*, )?puedes (pagar|desterrar|barajar|descartar|destruir|convertir|mostrar|poner|subir|anular|cancelar|sacrificar|bajar|girar|botar)", "activada", "puedes <costo> para ..."),
    (r"^(si [^,]*, )?puedes (desterrarl|barajarl|descartarl|destruirl|convertirl|pagarl|ponerl|mostrarl)", "activada", "puedes <costo de sí misma> ..."),
    (r"^(si [^,]*, )?puedes ", "activada", "puedes ... (otro)"),
    # --- continuas ---
    (r"^(tus|los|las|todos los|todas las|cada) (aliados|armas|totems|talismanes|oros|cartas|jugadores|demas)", "continua", "tus/los X ..."),
    (r"^(tu oponente|tus oponentes|los jugadores|ningun jugador|nadie) (no )?(puede|pueden|debe|deben|juega|juegan|roba|roban)", "continua", "regla para un jugador"),
    (r"^(este aliado|esta arma|este totem|esta carta|este oro|el portador|su portador|el aliado que la porta)", "continua", "este/el portador ..."),
    (r"^(no puede|no pueden|no se puede|no es|no son|no recibe|no hace)", "continua", "no puede ..."),
    (r"^(mientras|si controlas|si tienes|si hay|si tu oponente|si estas|si esta|si este|si no)", "continua", "mientras / si ..."),
    (r"^(gana|ganan|pierde|pierden|tiene|tienen|puede|pueden|es |son |cuesta|cuestan|hace|hacen|recibe|reciben|cuenta|cuentan|vale|valen)", "continua", "gana / tiene / puede ..."),
    (r"(ganan?|pierden?) \w+ de fuerza", "continua", "gana N de Fuerza"),
    (r"(no puede|no pueden|no pueden ser|no puede ser|no se puede|no se pueden)", "continua", "no puede (en medio)"),
    (r"\b(cuesta|cuestan|aumenta su coste|reduce su coste|limite de cartas)\b", "continua", "costo o límite modificado"),
    (r"^(el primer|la primera|su dano|ambos jugadores|si el portador fuera)", "continua", "regla fija"),
    (r"^en (batalla mitologica|respuesta a)[^,]*, puedes", "activada", "puedes <costo> para ..."),
    (r"^en tu vigilia o (al comienzo|en tu fase final)", "activada", "en tu Vigilia, puedes ..."),
    (r"^(el dano|el dano de combate|los efectos|las habilidades|la primera carta|tu aliado|durante|en la vigilia|en tu turno,)", "continua", "regla fija"),
    (r"^(tu oponente|tus oponentes|los jugadores) solo pueden?", "continua", "regla para un jugador"),
    (r"^(solo|para (poner|jugar|barajar|atacar|desterrar|utilizar|declarar|buscar|generar|afectar)|se considera|tu controlas|cualquier jugador puede|por cada efecto|en cada turno|cada jugador|entra en juego con|reduce el coste|no cuenta)", "continua", "regla fija"),
    (r"^si (porta|un jugador|en su|jugaste|se botaron)", "continua", "mientras / si ..."),
]



# Verbos con los que empieza la segunda opción de una habilidad ("...para cancelar una habilidad o
# Desterrar una carta..."): "o" seguido de uno de estos es otra opción, no una lista de cartas
# ("un Arma o Aliado Caballero") ni de zonas ("de tu mano o que controles").
OPTION_VERBS = r"(anular|anula|cancelar|cancela|prevenir|preven|desterrar|destierra|barajar|baraja|robar|roba|destruir|destruye|descartar|descarta|botar|bota|generar|genera|buscar|busca|subir|sube|poner|pon|jugar|juega|convertir|convierte|ganar|gana|mirar|mira|mostrar|muestra|hacer|haz|agrupar|agrupa|mover|mueve|elegir|elige|recuperar|recupera|devolver|devuelve|sacrificar|sacrifica)"


def split_options(sentence: str) -> list:
    """Parte "A o B" en opciones cuando B empieza con un verbo, o cuando las dos son cláusulas con
    "sea(n)" ("prevenir que una habilidad sea cancelada o un Aliado de coste 1 sea Anulado")."""
    parts = []
    start = 0
    # En "Cuando ... , ..." / "En respuesta a que ..., ..." la condición no tiene opciones ("mirar tu mano o
    # buscar cartas" es lo que la dispara): se parte solo después de su coma.
    earliest = 0
    if re.match(r"^(cuando|cuanto|en respuesta|al comienzo|al final|si |cada vez)", fold(sentence)):
        earliest = sentence.find(", ") + 1
    for m in re.finditer(r",? o ", sentence):
        if m.start() < earliest:
            continue
        left = fold(sentence[start:m.start()])
        # "Puedes Descartar o Destruir una carta ... para": dos costos para el mismo efecto, no dos opciones.
        if re.search(r"\b" + OPTION_VERBS + r"$", left) or re.search(r"\bpagar$", left):
            continue
        right = fold(sentence[m.end():])
        new_verb = re.match(OPTION_VERBS + r"\b", right) is not None
        clause = re.match(r"^(un|una|el|la|los|las|tus|sus)\b[^,.]*\b(sea|sean)\b", right) is not None \
            and re.search(r"\b(sea|sean)\b", left) is not None
        if new_verb or clause:
            parts.append(sentence[start:m.start()].strip(" ,"))
            start = m.end()
    parts.append(sentence[start:].strip(" ,"))
    return [x for x in parts if x]


def is_response(t: str) -> bool:
    """¿Anula, Cancela o Previene algo del rival? Sin contar las protecciones ("no puede ser Anulado",
    "no se puede cancelar su habilidad"), que son continuas."""
    t = re.sub(r"\bno (puede|pueden|se puede|se pueden) (ser )?(anulad|cancelad|prevenid)\w*", "", t)
    t = re.sub(r"\bni (su habilidad )?(cancelad|anulad)\w*", "", t)
    return re.search(r"\b(anular|anula|anulalo|cancelar|cancela|cancelalo|prevenir|preven|prevenirlo|en respuesta a)\b", t) is not None


def classify(text: str, card_type: int, base_only: bool = False):
    t = fold(text)
    if not t:
        return None
    for rx, kind, rule in RULES:
        if re.search(rx, t):
            # Talismán: su texto es el efecto al jugarlo, salvo que sea una habilidad de verdad.
            # Siguen siendo reglas de la carta: cómo se juega y lo que hace desde el Cementerio o el Destierro.
            keeps = rule in ("permiso para jugarla", "costo o condición para jugarla", "palabra clave") \
                or re.match(r"^si (esta|este) en tu (cementerio|destierro|mano)", t)
            if card_type == 3 and kind == "continua" and not keeps:
                return "efecto de Talismán", "efecto al jugarlo"
            # Una respuesta (Anular, Cancelar, Prevenir) es disparada: la dispara lo que hace el rival
            # (que juegue una carta de coste 1, que use una habilidad, que un efecto vaya a afectar...),
            # aunque se pague un costo y diga "puedes". Criterio del proyecto.
            if kind == "activada" and is_response(t) and not base_only:
                return "disparada", "respuesta (Anular / Cancelar / Prevenir)"
            return kind, rule
    if card_type == 3:
        return "efecto de Talismán", "efecto al jugarlo"
    return "revisar", "sin regla"


def classify_base(text: str, card_type: int):
    return classify(text, card_type, True)


def main():
    limit = None
    if "--limite" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limite") + 1])
    cards = json.loads(CARDS.read_text(encoding="utf-8"))
    rows = []
    seen = set()
    for c in cards:
        text = str(c.get("habilidad") or "").replace("\r\n", "\n").strip()
        if not text:
            continue
        name = str(c.get("nombre", "?"))
        tipo = int(c.get("tipo", -1)) if str(c.get("tipo", "")).lstrip("-").isdigit() else -1
        # Las opciones de "Elige un efecto: - X" van con el párrafo anterior; las notas entre paréntesis
        # ("Versión en lenguaje Enoquiano") no son habilidades.
        pars: list = []
        for p in [p.strip() for p in text.split("\n") if p.strip()]:
            if p.startswith("(") and p.endswith(")"):
                continue
            if p.startswith("-") and pars:
                pars[-1] += " " + p
            else:
                pars.append(p)
        for par in pars:
            kws, rest = split_keywords(par)
            pieces = [(k, ("continua", "palabra clave")) for k in kws]
            for sentence in split_abilities(rest, tipo):
                res = classify(sentence, tipo)
                options = split_options(sentence) if res and res[0] in ("disparada", "activada") else [sentence]
                if len(options) < 2:
                    pieces.append((sentence, res))
                    continue
                # Cada opción es su propia habilidad: una respuesta es disparada; las otras, lo que es la
                # habilidad sin la respuesta (activada si se usa a voluntad, disparada si la dispara un evento).
                base = classify_base(sentence, tipo)
                prev_response = False
                for i, opt in enumerate(options):
                    t_opt = fold(opt)
                    response = is_response(t_opt) or (prev_response and re.match(r"^(un|una|el|la|los|las|tus|sus)\b", t_opt) is not None)
                    kind = "disparada" if response or base[0] == "disparada" else base[0]
                    rule = "respuesta (Anular / Cancelar / Prevenir)" if response else base[1]
                    pieces.append((sentence, (kind, rule + " · opción %d de %d" % (i + 1, len(options)), opt)))
                    prev_response = response
            for piece, res in pieces:
                if res is None:
                    continue
                option = res[2] if len(res) > 2 else ""
                key = (fold(name), fold(piece), fold(option))
                if key in seen:  # la misma carta reimpresa con el mismo texto
                    continue
                seen.add(key)
                rows.append({"carta": name, "tipo": TIPOS.get(tipo, str(tipo)), "edicion": c.get("edicion", ""),
                    "habilidad": piece, "opcion": option, "clasificacion": res[0], "regla": res[1]})
        if limit and len(rows) >= limit:
            break
    if limit:
        rows = rows[:limit]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUT_DIR / "clasificacion.csv", "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["clasificacion", "regla", "carta", "tipo", "edicion", "habilidad", "opcion"])
        w.writeheader()
        for r in sorted(rows, key=lambda r: (r["clasificacion"], r["regla"], r["carta"].lower())):
            w.writerow(r)

    by_kind = Counter(r["clasificacion"] for r in rows)
    by_rule = defaultdict(Counter)
    examples = defaultdict(list)
    for r in rows:
        by_rule[r["clasificacion"]][r["regla"]] += 1
        if len(examples[(r["clasificacion"], r["regla"])]) < 3:
            examples[(r["clasificacion"], r["regla"])].append(r)
    order = ["disparada", "activada", "continua", "efecto de Talismán", "revisar"]
    lines = ["# Clasificación de habilidades", "",
        f"{len(rows)} habilidades de {len({r['carta'].lower() for r in rows})} cartas (data/cards.json), sin repetir reimpresiones.",
        "Detalle completo en `clasificacion.csv`. Generado por `tools/clasificar_habilidades.py`.", "",
        "| Clasificación | Habilidades |", "| --- | --- |"]
    for k in order:
        lines.append(f"| {k} | {by_kind.get(k, 0)} |")
    for k in order:
        if not by_kind.get(k):
            continue
        lines += ["", f"## {k[0].upper() + k[1:]} ({by_kind[k]})", "", "| Regla | Cantidad | Ejemplo |", "| --- | --- | --- |"]
        for rule, n in by_rule[k].most_common():
            ex = examples[(k, rule)][0]
            txt = (ex["opcion"] or ex["habilidad"]).replace("|", "/")
            txt = txt if len(txt) <= 110 else txt[:107] + "..."
            lines.append(f"| {rule} | {n} | **{ex['carta']}**: {txt} |")
    (OUT_DIR / "resumen.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    for k in order:
        print(f"{k}: {by_kind.get(k, 0)}")
    print(f"total: {len(rows)}")


if __name__ == "__main__":
    main()
