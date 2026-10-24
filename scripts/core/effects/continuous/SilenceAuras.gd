extends RefCounted
## SilenceAuras — habilidades continuas "... pierden su habilidad" de las cartas en juego (tui, Daikaiju
## Furioso, Legendario Tenshi, tenshi x-2, oberon, Sariel, daidarabotchi, Xanadú, septimus, camilo
## henriquez, luthairon, skofnung, manu tara) y sobre los Cementerios/Destierros (torre de cristal,
## parche pirata, lycon, antartica, La Catrina, Pricolici; Ajo Protector protege el propio Cementerio).
## Se evalúan al consultar (KeywordManager.is_silenced / CardManager.is_cemetery_card_silenced): una
## fuente sin habilidad no quita habilidades.
##
## Regla de bucles (DAR 7.7): si las fuentes se quitan la habilidad en círculo (A a B, B a C, C a A), la
## ÚLTIMA en entrar en juego de las que forman el círculo no produce cambios con esa habilidad mientras
## las otras sigan en juego; cuando una sale, vuelve a aplicar. Se detecta el círculo durante la
## evaluación (pila de cartas en evaluación) y se reintenta sin esa fuente.
## Se usa con preload (ver §54).

const EffectCompilerScript = preload("res://scripts/core/effects/compiler/EffectCompiler.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

const VERBS := ["no pueden utilizar su habilidad", "pierden su habilidad", "pierde su habilidad"]
## Oraciones que no son continuas (disparadas, activadas, con duración, de un objetivo puntual) o que ya
## resuelve otro sistema (nombrar: KeywordManager.lock_ability_by_name; iga ryu).
const SKIP := ["cuando ", "hasta tu proxim", "por el turno", "este turno", "hasta el final", "una vez por turno",
	"puedes ", "elige", "hasta una", "hasta dos", "hasta tres", "un oro oponente", "una carta", "durante",
	"por dos turnos", "por el resto", " y es ", " y son ", "destruyel", "nombrad", "con ese nombre",
	"el primer aliado", "no pierden"]

## Texto -> specs (lista de Dictionary), para no volver a analizar.
static var _spec_cache: Dictionary = {}
## Fuentes en juego con alguna spec, por generación (invalidate()).
static var _sources: Array = []
static var _sources_gen: int = -1
static var _gen: int = 0
static var _sources_frame: int = -1
## Evaluación en curso.
static var _depth: int = 0
static var _stack: Array = []
static var _memo: Dictionary = {}
static var _cycle: Array = []
static var _disabled: Dictionary = {}
## Silenciadas por aura en el último refresco visual.
static var last_silenced: Dictionary = {}
static var _entry_seq: int = 0


static func reset_match() -> void:
	"""MatchReset: estado de partida en cero (los cachés por texto se conservan)."""
	_sources = []
	_sources_gen = -1
	_gen += 1
	_sources_frame = -1
	_depth = 0
	_stack = []
	_memo = {}
	_cycle = []
	_disabled = {}
	last_silenced = {}
	_entry_seq = 0


## Orden de entrada en juego (la regla de bucles mira la última en entrar).
static func mark_entered(card: Node) -> void:
	_entry_seq += 1
	card.set_meta("entered_play_seq", _entry_seq)


static func invalidate() -> void:
	_gen += 1


# -----------------------------------------------------------------------------
# Análisis del texto
# -----------------------------------------------------------------------------
static func specs_of(card: Node) -> Array:
	if not is_instance_valid(card) or card.get("card_ability") == null:
		return []
	if card.get("card_type") == Constants.CardType.TALISMAN:
		return []
	var text: String = str(card.card_ability)
	if _spec_cache.has(text):
		return _spec_cache[text]
	var out: Array = []
	for raw in EffectCompilerScript.normalize(text).split("."):
		var s: String = raw.strip_edges()
		var spec: Dictionary = _parse_sentence(s)
		if not spec.is_empty():
			out.append(spec)
	_spec_cache[text] = out
	return out


static func _parse_sentence(s: String) -> Dictionary:
	if s.is_empty():
		return {}
	# Ajo Protector: "Si controlas Bestias, Dragones o Sombras, las cartas en tu Cementerio no pierden su habilidad."
	if "las cartas en tu cementerio no pierden su habilidad" in s:
		var races: Array = []
		var who: String = s.substr(0, s.find("las cartas en tu cementerio"))
		for r in ["bestia", "dragon", "sombra", "caballero", "guerrero", "heroe", "eterno", "faerie", "sacerdote"]:
			if r in who:
				races.append(r)
		return {"protect_own_cemetery": true, "races": races}
	var v := -1
	var verb := ""
	for vb in VERBS:
		v = s.find(vb)
		if v >= 0:
			verb = vb
			break
	if v < 0:
		return {}
	for k in SKIP:
		if k in s:
			return {}
	var prefix: String = s.substr(0, v).strip_edges()
	var spec := {"zones": "in_play", "side": "any", "type": -1, "exclude_self": false}
	var subject := ""
	var cond := ""
	# Sariel: "Los Aliados oponentes no pueden portar Armas, pierden 1 de Fuerza y si tienen Fuerza 1 o menos
	# no pueden utilizar su habilidad."
	var rx := RegEx.new()
	rx.compile("si tienen fuerza (\\d+) o menos$")
	var m := rx.search(prefix)
	if m:
		spec["str_cmp"] = "le"
		spec["str_val"] = int(m.get_string(1))
		subject = prefix.get_slice(",", 0)
	else:
		# El sujeto empieza en el último "los/las/sus" que abre la cláusula (inicio, tras ", " o tras " y ").
		var start_rx := RegEx.new()
		start_rx.compile("(?:^|, | y )(?=(?:los|las|sus) )")
		var start := -1
		for mm in start_rx.search_all(prefix):
			start = mm.get_end()
		if start < 0:
			return {}
		subject = prefix.substr(start).strip_edges()
		cond = prefix.substr(0, start).strip_edges()
	# Condiciones de la fuente.
	if cond != "":
		var known := false
		if "si esta en tu reserva" in cond:
			spec["src_zone"] = Constants.Zone.RESERVA_ORO
			known = true
		if "si esta en tu oro pagado" in cond:
			spec["src_zone"] = Constants.Zone.ORO_PAGADO
			known = true
		if "controlas aliados de coste 1 o mas" in cond:
			spec["need_ally_cost1"] = true
			known = true
		if "tienes entre uno y tres aliados en linea de ataque" in cond:
			spec["need_attackers_1_3"] = true
			known = true
		if "si tiene coste 2 o mas" in cond:
			spec["need_bearer_cost2"] = true
			known = true
		if "si " in cond and not known:
			return {}
	# Sujeto.
	if subject.begins_with("sus ") or "oponente" in subject:
		spec.side = "opp"
	elif subject.begins_with("tus ") or "que controles" in subject:
		spec.side = "own"
	if "los demas" in subject or "las demas" in subject:
		spec.exclude_self = true
	if "aliados" in subject:
		spec.type = Constants.CardType.ALIADO
	elif "oros" in subject:
		spec.type = Constants.CardType.ORO
	elif "armas" in subject:
		spec.type = Constants.CardType.ARMA
	elif "totem" in subject:
		spec.type = Constants.CardType.TOTEM
	elif not "cartas" in subject:
		return {}
	if "cementerio" in subject or "destierro" in subject:
		spec.zones = "out"
		spec["cemetery"] = "cementerio" in subject
		spec["exile"] = "destierro" in subject
		if "los cementerios" in subject:
			spec.side = "any"
	elif "en linea de defensa" in subject:
		spec["line"] = Constants.Zone.LINEA_DEFENSA
	if "con menos fuerza que el portador" in subject:
		spec["less_than_bearer"] = true
	var crx := RegEx.new()
	crx.compile("de coste (\\d+)( o menos| o mas)?")
	var cm := crx.search(subject)
	if cm:
		spec["cost_val"] = int(cm.get_string(1))
		spec["cost_cmp"] = "le" if cm.get_string(2) == " o menos" else ("ge" if cm.get_string(2) == " o mas" else "eq")
	var frx := RegEx.new()
	frx.compile("de fuerza (\\d+)( o menos| o mas)?")
	var fm := frx.search(subject)
	if fm:
		spec["str_val"] = int(fm.get_string(1))
		spec["str_cmp"] = "le" if fm.get_string(2) == " o menos" else ("ge" if fm.get_string(2) == " o mas" else "eq")
	return spec


# -----------------------------------------------------------------------------
# Fuentes
# -----------------------------------------------------------------------------
static func _main() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")


static func _cards_in_play(main: Node) -> Array:
	var out: Array = []
	for pid in [0, 1]:
		var containers: Array = PlayerSideScript.line_containers(main, pid)
		containers.append(PlayerSideScript.gold_reserva(main, pid))
		containers.append(PlayerSideScript.oro_pagado(main, pid))
		for container in containers:
			if not container:
				continue
			for c in container.get_children():
				if not is_instance_valid(c) or c.get("card_ability") == null:
					continue
				if not (c in out):
					out.append(c)
				var weapons = c.get("equipped_weapons")
				if weapons is Array:
					for w in weapons:
						if is_instance_valid(w) and not (w in out):
							out.append(w)
	return out


static func _get_sources() -> Array:
	var frame: int = Engine.get_process_frames()
	if _sources_gen == _gen and _sources_frame == frame:
		return _sources
	_sources_gen = _gen
	_sources_frame = frame
	_sources = []
	var main := _main()
	if not main:
		return _sources
	for c in _cards_in_play(main):
		if not specs_of(c).is_empty():
			_sources.append(c)
	return _sources


static func _ctrl(c) -> int:
	if c is Dictionary:
		return -1
	if c.get("controller_id") != null:
		return int(c.controller_id)
	return int(c.owner_id) if c.get("owner_id") != null else 0


## La fuente cumple las condiciones de su texto (zona, "si controlas...", portador).
static func _source_ready(src: Node, spec: Dictionary) -> bool:
	var zone = src.get("current_zone")
	if zone == null or not (zone in Constants.ZONES_IN_PLAY):
		return false
	if spec.has("src_zone") and zone != spec.src_zone:
		return false
	var main := _main()
	var pid: int = _ctrl(src)
	if spec.get("need_ally_cost1", false):
		var ok := false
		for container in PlayerSideScript.line_containers(main, pid):
			for c in container.get_children():
				if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO \
						and ContinuousEffectManager.get_modified_cost(c) >= 1:
					ok = true
		if not ok:
			return false
	if spec.get("need_attackers_1_3", false):
		var line = main.player_linea_ataque if pid == 0 else main.opponent_linea_ataque
		var n := 0
		if line:
			for c in line.get_children():
				if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO:
					n += 1
		if n < 1 or n > 3:
			return false
	if spec.get("need_bearer_cost2", false) or spec.get("less_than_bearer", false):
		var bearer = src.get("wielder")
		if not is_instance_valid(bearer):
			return false
		if spec.get("need_bearer_cost2", false) and ContinuousEffectManager.get_modified_cost(bearer) < 2:
			return false
	return true


static func _cmp(value: int, op: String, target: int) -> bool:
	match op:
		"le":
			return value <= target
		"ge":
			return value >= target
	return value == target


## La spec de 'src' alcanza a 'card' (en juego), sin mirar si 'src' tiene habilidad.
static func _applies(src: Node, spec: Dictionary, card: Node) -> bool:
	if spec.zones != "in_play":
		return false
	if spec.exclude_self and card == src:
		return false
	var zone = card.get("current_zone")
	if zone == null or not (zone in Constants.ZONES_IN_PLAY):
		return false
	if spec.has("line") and zone != spec.line:
		return false
	if int(spec.type) >= 0 and card.get("card_type") != int(spec.type):
		return false
	var sc: int = _ctrl(src)
	var cc: int = _ctrl(card)
	if spec.side == "opp" and sc == cc:
		return false
	if spec.side == "own" and sc != cc:
		return false
	if spec.has("cost_val"):
		# Un Oro no tiene coste (salvo en juego como Aliado): nunca cumple un filtro de coste.
		if card.get("card_type") == Constants.CardType.ORO:
			return false
		if not _cmp(ContinuousEffectManager.get_modified_cost(card), spec.cost_cmp, int(spec.cost_val)):
			return false
	if spec.has("str_val") or spec.get("less_than_bearer", false):
		if card.get("card_type") != Constants.CardType.ALIADO:
			return false
		var st: int = ContinuousEffectManager.get_modified_strength(card)
		if spec.has("str_val") and not _cmp(st, spec.str_cmp, int(spec.str_val)):
			return false
		if spec.get("less_than_bearer", false):
			var bearer = src.get("wielder")
			if not is_instance_valid(bearer) or bearer == card or st >= ContinuousEffectManager.get_modified_strength(bearer):
				return false
	if not _source_ready(src, spec):
		return false
	return not _protected(card, src)


static func _protected(card: Node, src: Node) -> bool:
	if KeywordManager._is_protected_from_silence_by_weapon(card) \
			or KeywordManager._is_protected_from_silence_by_all_allies_source(card) \
			or KeywordManager._is_protected_from_silence_by_all_weapons_source(card) \
			or KeywordManager._is_protected_from_silence_by_self(card):
		return true
	# Terminal P-12: solo contra habilidades oponentes.
	return _ctrl(src) != _ctrl(card) and KeywordManager._is_protected_from_silence_by_reserva_source(card)


# -----------------------------------------------------------------------------
# Evaluación (con la regla de bucles)
# -----------------------------------------------------------------------------
## ¿Alguna aura en juego (con habilidad) le quita la habilidad a 'card'? Lo llama KeywordManager.is_silenced.
static func silenced(card: Node) -> bool:
	if not is_instance_valid(card):
		return false
	var sources: Array = _get_sources()
	if sources.is_empty():
		return false
	if _depth > 0:
		return _eval(card, sources)
	_disabled.clear()
	var result := false
	for _attempt in range(sources.size() + 1):
		_memo.clear()
		_cycle = []
		result = _eval(card, sources)
		if _cycle.is_empty():
			break
		var last: Node = _last_entered(_cycle)
		if last == null or _disabled.has(last.get_instance_id()):
			break
		_disabled[last.get_instance_id()] = true
		# La Fuerza calculada con el círculo a medio resolver no vale.
		ContinuousEffectManager._calculated_cache.clear()
	_memo.clear()
	return result


static func _eval(card: Node, sources: Array) -> bool:
	var id: int = card.get_instance_id()
	if _memo.has(id):
		return _memo[id]
	var at: int = _stack.find(card)
	if at >= 0:
		# Solo es un bucle de la regla si en el círculo hay auras de silencio (no, p.ej., una carta cuya
		# Fuerza depende de su propia habilidad).
		if _cycle.is_empty() and _stack.slice(at).any(func(c): return c in _sources):
			_cycle = _stack.slice(at)
		return false
	_stack.append(card)
	_depth += 1
	var result := false
	for src in sources:
		if not is_instance_valid(src) or _disabled.has(src.get_instance_id()):
			continue
		var hit := false
		for spec in specs_of(src):
			if _applies(src, spec, card):
				hit = true
				break
		if hit and not KeywordManager.is_silenced(src):
			result = true
			break
	_depth -= 1
	_stack.pop_back()
	if _cycle.is_empty():
		_memo[id] = result
	return result


static func _last_entered(cards: Array) -> Node:
	var best: Node = null
	var best_seq := -1
	for c in cards:
		if not is_instance_valid(c) or not (c in _sources):
			continue
		var seq: int = int(c.get_meta("entered_play_seq", 0))
		if seq >= best_seq:
			best_seq = seq
			best = c
	return best


## Fuentes que la regla de bucles apaga ahora (para el registro).
static func loop_disabled() -> Array:
	var out: Array = []
	for src in _get_sources():
		if is_instance_valid(src) and _disabled.has(src.get_instance_id()):
			out.append(src)
	return out


# -----------------------------------------------------------------------------
# Cementerio y Destierro
# -----------------------------------------------------------------------------
## 'data' está en el Cementerio (o Destierro) de 'owner': ¿lo alcanza un aura con habilidad?
static func zone_card_silenced(data: Dictionary, owner: int, in_exile: bool) -> bool:
	var sources: Array = _get_sources()
	if sources.is_empty():
		return false
	var main := _main()
	# Ajo Protector: "Si controlas Bestias, Dragones o Sombras, las cartas en tu Cementerio no pierden su habilidad".
	if not in_exile:
		for src in sources:
			for spec in specs_of(src):
				if spec.get("protect_own_cemetery", false) and _ctrl(src) == owner and _source_ready(src, spec) \
						and not KeywordManager.is_silenced(src) and _controls_race(main, owner, spec.races):
					return false
	for src in sources:
		for spec in specs_of(src):
			if spec.zones != "out" or not _source_ready(src, spec):
				continue
			if not (spec.get("exile", false) if in_exile else spec.get("cemetery", false)):
				continue
			if spec.side == "opp" and _ctrl(src) == owner:
				continue
			if spec.side == "own" and _ctrl(src) != owner:
				continue
			if int(spec.type) >= 0 and int(data.get("tipo", -1)) != int(spec.type):
				continue
			if not KeywordManager.is_silenced(src):
				return true
	return false


static func _controls_race(main: Node, pid: int, races: Array) -> bool:
	for container in PlayerSideScript.line_containers(main, pid):
		for c in container.get_children():
			if not is_instance_valid(c) or c.get("card_type") != Constants.CardType.ALIADO:
				continue
			var raza: String = EffectCompilerScript.normalize(str(c.get("card_raza")))
			for r in races:
				if r in raza:
					return true
	return false


# -----------------------------------------------------------------------------
# Refresco visual (giro "sin habilidad") y aviso al Remoto
# -----------------------------------------------------------------------------
## Recalcula qué cartas en juego pierden la habilidad por un aura; si cambió, gira las que cambiaron y
## avisa (KeywordManager.abilities_changed: Fuerza, Remoto). Lo agenda KeywordManager.
static func refresh() -> bool:
	var main := _main()
	if not main:
		return false
	var now: Dictionary = {}
	if not _get_sources().is_empty():
		for c in _cards_in_play(main):
			if silenced(c):
				now[c.get_instance_id()] = c
	var changed: Array = []
	for id in now:
		if not last_silenced.has(id):
			changed.append(now[id])
	for id in last_silenced:
		if not now.has(id) and is_instance_valid(last_silenced[id]):
			changed.append(last_silenced[id])
	last_silenced = now
	for c in changed:
		if is_instance_valid(c) and c.has_method("_refresh_disabled_rotation"):
			c._refresh_disabled_rotation()
	return not changed.is_empty()
