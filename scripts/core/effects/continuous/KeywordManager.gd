extends Node
## KeywordManager - Gestiona palabras clave de cartas (DAR Sección 7-8)
## Única consulta de keywords (has_keyword) y las otorgadas/quitadas por efectos
## NOTA: Usa Constants.Keyword como enum centralizado

# =============================================================================
# ALIAS - Usar Constants.Keyword para todo
# =============================================================================
## Alias para acceso rápido (KeywordManager.Keyword → Constants.Keyword)
var Keyword = Constants.Keyword

## Nombre de la keyword (en un array "keywords" de datos) → Constants.Keyword. Leer keywords del texto
## de una carta es cosa de KeywordParser.
var KEYWORD_MAP: Dictionary = {}

const KeywordParser = preload("res://scripts/core/cards/KeywordParser.gd")
const KeywordConditions = preload("res://scripts/core/cards/KeywordConditions.gd")
const KeywordAuras = preload("res://scripts/core/cards/KeywordAuras.gd")
const SilenceAurasScript = preload("res://scripts/core/effects/continuous/SilenceAuras.gd")


func _init() -> void:
	KEYWORD_MAP = {
		"furia": Constants.Keyword.FURIA,
		"imbloqueable": Constants.Keyword.IMBLOQUEABLE,
		"indestructible": Constants.Keyword.INDESTRUCTIBLE,
		"indesterrable": Constants.Keyword.INDESTERRABLE,
		"única": Constants.Keyword.UNICA,
		"unica": Constants.Keyword.UNICA,
		"exhumar": Constants.Keyword.EXHUMAR,
		"errante": Constants.Keyword.ERRANTE,
		"retador": Constants.Keyword.RETADOR,
	}

# =============================================================================
# SIGNALS
# =============================================================================
signal keyword_granted(card: Node, keyword: int, source: Node)
signal keyword_removed(card: Node, keyword: int, source: Node)
## Alguna carta ganó o perdió su habilidad (silencio, bloqueo por nombre o
## por instancia). GameStateBroadcaster lo usa para avisarle al Remoto (§63).
signal abilities_changed()

# =============================================================================
# ESTADO
# =============================================================================
## Keywords temporales otorgados por efectos {card_instance_id: {keyword: [sources]}}
var _temporary_keywords: Dictionary = {}

## Keywords removidos temporalmente {card_instance_id: {keyword: [sources]}}
var _removed_keywords: Dictionary = {}

## Cartas silenciadas (pierden TODAS sus keywords y no disparan habilidades)
## {card_instance_id: [{source, duration}]}
var _silenced_cards: Dictionary = {}

## Bloqueo de habilidad POR NOMBRE (DAR "nombra una carta para que pierda su habilidad", p.ej.
## Alicia en Wonderland: "en todas las Zonas mientras este Aliado esté en juego"). A diferencia de
## _silenced_cards, afecta cualquier copia del nombre en cualquier zona, incluso las que aún no son
## Node. {nombre_lower: [source_node, ...]}; sin unregister: is_name_locked() valida en cada
## consulta que la fuente siga viva y en juego.
var _named_ability_locks: Dictionary = {}

## Bloqueo de habilidad de UNA carta puntual, mientras una fuente concreta siga en juego (p.ej.
## Kuchiku Kan: "una carta pierda su habilidad... mientras este Aliado esté en juego") — análogo
## instance- based de _named_ability_locks (mismo criterio de auto-expiración perezosa), a
## diferencia de silence_card(..., "permanent") que es indefinido de verdad y no debe usarse aquí
## (rompería cartas como Convertir/_execute_targeted_silence, que SÍ son permanentes sin condición).
## {card_instance_id: [source_node,...]}
var _instance_ability_locks: Dictionary = {}



## "Tus Aliados que porten Arma no pueden perder su habilidad" (p.ej. Manuel Bulnes) — lista de
## fuentes activas de esta protección. Array[Node] — sin unregister explícito, se auto-limpia
## comparando is_instance_valid/is_in_play en cada consulta.
var _weapon_wielder_silence_immunity_sources: Array = []

## 'Tus Aliados... no pueden perder su habilidad' SIN calificador de Arma (p.ej. Abu Simbel) —
## versión más amplia de _weapon_wielder_silence_immunity_sources, protege a TODOS los Aliados del
## controlador de la fuente, no solo a los que porten Arma.
var _all_allies_silence_immunity_sources: Array = []

## '...No puede perder su habilidad' EN SINGULAR referido a sí misma (p.ej. lagrima del dragon: 'Oro
## Inicial. Indesterrable. No puede perder su habilidad.') — a diferencia de las dos listas de
## arriba (que protegen a TERCEROS mientras 'source' siga en juego), aquí 'source' se protege a SÍ
## MISMA.
var _self_silence_immunity_sources: Array = []

## 'Si está en tu Reserva, las cartas que controles no pueden perder su habilidad...' (p.ej.
## Terminal P-12) — protege TODAS las cartas del controlador de 'source' (sin restringir a Aliados,
## a diferencia de _all_allies_silence_immunity_sources), pero SOLO mientras 'source' esté
## específicamente en Reserva de Oro (no en juego en general).
var _reserva_conditional_full_silence_immunity_sources: Array = []


func _ready() -> void:
	# Conectar a las señales de fin de turno para limpiar temporales. GameManager es el único conductor
	# de turnos.
	if GameManager and GameManager.has_signal("turn_ended"):
		GameManager.turn_ended.connect(_on_turn_ended)


# =============================================================================
# PARSING DE KEYWORDS
# =============================================================================
func parse_keywords_from_text(ability_text: String) -> Array:
	"""Palabras clave impresas en el texto de una carta (KeywordParser)."""
	return KeywordParser.own_keywords(ability_text)


func parse_keywords_from_array(keywords_array: Array) -> Array:
	"""Convierte un array de strings a array de Keyword enum"""
	var result: Array = []

	for kw in keywords_array:
		if kw is String:
			var kw_lower = kw.to_lower()
			if kw_lower in KEYWORD_MAP:
				result.append(KEYWORD_MAP[kw_lower])
		elif kw is int and kw in Constants.Keyword.values():
			result.append(kw)

	return result


# =============================================================================
# CONSULTA DE KEYWORDS — única entrada (Card.has_keyword() delega aquí)
# =============================================================================
func scan_and_apply_keywords(card: Node) -> Array:
	"""Palabras clave impresas de la carta según su texto actual (para el log al entrar en juego o al
	ganar habilidades, p.ej. Reina Nyssara). No guarda nada: has_keyword() lee el texto cada vez."""
	if not is_instance_valid(card):
		return []
	var found: Array = _printed_keywords(card)
	if not found.is_empty():
		var kw_names = found.map(func(k): return Constants.Keyword.keys()[k])
		print("[KeywordManager] %s → Keywords: %s" % [_get_card_name(card), ", ".join(kw_names)])
	return found


func has_keyword(card: Node, keyword: int) -> bool:
	"""¿La carta tiene esta palabra clave ahora? Orden:
	1. Quitadas: por remove_keyword() (también el silencio, que quita las que tenía en ese momento), por
	un modificador KEYWORDS con keywords_remove o por un aura impresa "pierden X" (KeywordAuras: kuzuryu,
	Ianthe, Diadema Celestial...). Ganan sobre todo lo demás.
	2. Otorgadas por grant_keyword() (efectos, conversiones).
	3. Las de la carta, salvo que haya perdido su habilidad (silencio, bloqueo por nombre o por
	instancia): las impresas en su texto actual (KeywordParser), las del array card_keywords de sus
	datos y las condicionales que se cumplen (KeywordConditions).
	4. Las que le dan sus Armas: las del Arma, "El portador gana..." y las condicionales del portador
	(salvo un Arma que perdió su habilidad).
	5. Auras de otras cartas: las impresas ("Tus Aliados ganan Furia", KeywordAuras.grants()) y los
	modificadores de ContinuousEffectManager (p.ej. Espíritu Kotaix)."""
	if not is_instance_valid(card):
		return false
	var card_id = card.get_instance_id()
	if _removed_keywords.has(card_id) and _removed_keywords[card_id].has(keyword):
		return false
	if ContinuousEffectManager.aura_removes_keyword(card, keyword) or KeywordAuras.removes(card, keyword):
		return false
	if _temporary_keywords.has(card_id) and _temporary_keywords[card_id].has(keyword) \
			and _temporary_keywords[card_id][keyword].any(func(e): return int(e.get("until_serial", 1 << 30)) >= GameManager.turn_serial):
		return true
	if not is_silenced(card):
		if keyword in _printed_keywords(card):
			return true
		if _conditional_keyword(str(card.get("card_ability")), keyword, "self", card, _controller_of(card)):
			return true
	var weapons = card.get("equipped_weapons")
	if weapons is Array:
		for weapon in weapons:
			if not is_instance_valid(weapon) or is_silenced(weapon):
				continue
			var weapon_text := str(weapon.get("card_ability"))
			if keyword in KeywordParser.wielder_keywords(weapon_text):
				return true
			if _conditional_keyword(weapon_text, keyword, "wielder", card, _controller_of(weapon)):
				return true
	if KeywordAuras.grants(card, keyword):
		return true
	return ContinuousEffectManager.has_keyword(card, keyword)


func _printed_keywords(card: Node) -> Array:
	"""Las impresas en el texto actual más las del array de datos (card_keywords)."""
	var out: Array = KeywordParser.own_keywords(str(card.get("card_ability"))).duplicate()
	var extra = card.get("card_keywords")
	if extra is Array:
		for kw in parse_keywords_from_array(extra):
			if kw not in out:
				out.append(kw)
	return out


func _conditional_keyword(text: String, keyword: int, who: String, subject: Node, pid: int) -> bool:
	for entry in KeywordParser.conditional_keywords(text):
		if entry.keyword == keyword and entry.who == who and KeywordConditions.holds(entry.cond, subject, pid):
			return true
	return false


func _controller_of(card: Node) -> int:
	if card.get("controller_id") != null:
		return int(card.controller_id)
	return int(card.owner_id) if card.get("owner_id") != null else 0


# =============================================================================
# FUNCIONES HELPER DE COMBATE (Sección 8)
# =============================================================================
func can_attack_immediately(card: Node) -> bool:
	"""DAR Sección 3.1: Aliados no pueden atacar el turno que entran, excepto con Furia o "Puede atacar
	cuando entra en juego" (Sir Galahad, brujo mendigo, Jaques de Molay)."""
	if has_keyword(card, Keyword.FURIA):
		return true
	if is_instance_valid(card) and int(card.get_meta("can_attack_turn", -1)) == GameManager.turn_serial:
		return true  # corvo campesino: "puede atacar ese turno" (GoldManager._apply_play_marks)
	return is_instance_valid(card) and not is_silenced(card) and card.get("card_ability") != null \
		and "puede atacar cuando entra en juego" in str(card.card_ability).to_lower()


func can_be_blocked(attacker: Node, blocker: Node = null) -> bool:
	"""DAR Sección 8: Verifica si un atacante puede ser bloqueado.
	Imbloqueable: no puede ser bloqueado, sin excepción por keyword — en
	Mitos y Leyendas no existe una keyword general tipo 'Alcance'. Si algún
	Aliado puede bloquear Imbloqueables, lo dice su propio texto."""
	if not has_keyword(attacker, Keyword.IMBLOQUEABLE):
		return true  # Atacante normal, puede ser bloqueado
	# Atacante es Imbloqueable — solo lo bloquea algo cuyo propio texto lo permita
	if blocker != null and blocker.get("card_ability") != null:
		var blocker_text: String = blocker.card_ability.to_lower()
		if "bloquear" in blocker_text and "imbloqueable" in blocker_text:
			return true

	return false


func can_be_destroyed(card: Node) -> bool:
	"""DAR Sección 8: Verifica si una carta puede ser destruida"""
	return not has_keyword(card, Keyword.INDESTRUCTIBLE)


func register_weapon_wielder_silence_immunity(source: Node) -> void:
	"""'Tus Aliados que porten Arma no pueden perder su habilidad' (p.ej. Manuel Bulnes) — mientras
	'source' siga en juego, protege de silence_card a los Aliados equipados con un Arma que
	controle el MISMO jugador que controla 'source' (no a los del rival)."""
	if not is_instance_valid(source):
		return
	if source not in _weapon_wielder_silence_immunity_sources:
		_weapon_wielder_silence_immunity_sources.append(source)


func _is_protected_from_silence_by_weapon(card: Node) -> bool:
	"""Consulta acumulativa de register_weapon_wielder_silence_immunity() —
	auto-limpia fuentes inválidas/fuera de juego en el camino."""
	if not is_instance_valid(card):
		return false
	var weapons = card.get("equipped_weapons")
	if not (weapons is Array) or weapons.is_empty():
		return false
	var card_controller: int = card.controller_id if card.get("controller_id") != null else -1
	var still_valid: Array = []
	var protected_by_weapon := false
	for source in _weapon_wielder_silence_immunity_sources:
		if not is_instance_valid(source) or not source.is_in_play():
			continue
		still_valid.append(source)
		var source_controller: int = source.controller_id if source.get("controller_id") != null else -2
		if source_controller == card_controller:
			protected_by_weapon = true
	_weapon_wielder_silence_immunity_sources = still_valid
	return protected_by_weapon


func register_all_allies_silence_immunity(source: Node) -> void:
	"""'Tus Aliados... no pueden perder su habilidad' SIN calificador de Arma (p.ej. Abu Simbel) —
	mientras 'source' siga en juego, protege de silence_card a TODOS los Aliados del MISMO
	controlador de 'source' (a diferencia de register_weapon_wielder_silence_immunity, que solo
	protege a los que porten Arma)."""
	if not is_instance_valid(source):
		return
	if source not in _all_allies_silence_immunity_sources:
		_all_allies_silence_immunity_sources.append(source)


func _is_protected_from_silence_by_all_allies_source(card: Node) -> bool:
	"""Consulta acumulativa de register_all_allies_silence_immunity() —
	auto-limpia fuentes inválidas/fuera de juego en el camino."""
	if not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ALIADO:
		return false
	var card_controller: int = card.controller_id if card.get("controller_id") != null else -1
	var still_valid: Array = []
	var protected_generally := false
	for source in _all_allies_silence_immunity_sources:
		if not is_instance_valid(source) or not source.is_in_play():
			continue
		still_valid.append(source)
		var source_controller: int = source.controller_id if source.get("controller_id") != null else -2
		if source_controller == card_controller:
			protected_generally = true
	_all_allies_silence_immunity_sources = still_valid
	return protected_generally


## 'Tus Armas no pueden perder su habilidad' (p.ej. skofnung) — mismo criterio que
## _all_allies_silence_immunity_sources, pero para Armas.
var _all_weapons_silence_immunity_sources: Array = []


func register_all_weapons_silence_immunity(source: Node) -> void:
	"""'Tus Armas... no pueden perder su habilidad' (p.ej. skofnung) — mientras 'source' siga en
	juego, protege de silence_card a TODAS las Armas del MISMO controlador de 'source'."""
	if not is_instance_valid(source):
		return
	if source not in _all_weapons_silence_immunity_sources:
		_all_weapons_silence_immunity_sources.append(source)


func _is_protected_from_silence_by_all_weapons_source(card: Node) -> bool:
	"""Consulta acumulativa de register_all_weapons_silence_immunity()."""
	if not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ARMA:
		return false
	var card_controller: int = card.controller_id if card.get("controller_id") != null else -1
	var still_valid: Array = []
	var protected_generally := false
	for source in _all_weapons_silence_immunity_sources:
		if not is_instance_valid(source) or not source.is_in_play():
			continue
		still_valid.append(source)
		var source_controller: int = source.controller_id if source.get("controller_id") != null else -2
		if source_controller == card_controller:
			protected_generally = true
	_all_weapons_silence_immunity_sources = still_valid
	return protected_generally


func register_self_silence_immunity(source: Node) -> void:
	"""'No puede perder su habilidad' en singular, referido a la propia carta (p.ej. lagrima del
	dragon)."""
	if not is_instance_valid(source):
		return
	if source not in _self_silence_immunity_sources:
		_self_silence_immunity_sources.append(source)


func _is_protected_from_silence_by_self(card: Node) -> bool:
	"""Consulta de register_self_silence_immunity() — auto-limpia fuentes
	inválidas/fuera de juego en el camino."""
	if not is_instance_valid(card):
		return false
	var still_valid: Array = []
	var protected_self := false
	for source in _self_silence_immunity_sources:
		if not is_instance_valid(source) or not source.is_in_play():
			continue
		still_valid.append(source)
		if source == card:
			protected_self = true
	_self_silence_immunity_sources = still_valid
	return protected_self


func register_reserva_conditional_full_silence_immunity(source: Node) -> void:
	"""'Si está en tu Reserva, las cartas que controles no pueden perder su habilidad...' (p.ej.
	Terminal P-12) — protege TODAS las cartas del mismo controlador de 'source' (no solo Aliados),
	pero solo mientras 'source' esté en Constants.Zone.RESERVA_ORO específicamente."""
	if not is_instance_valid(source):
		return
	if source not in _reserva_conditional_full_silence_immunity_sources:
		_reserva_conditional_full_silence_immunity_sources.append(source)


func _is_protected_from_silence_by_reserva_source(card: Node) -> bool:
	"""Consulta de register_reserva_conditional_full_silence_immunity() —
	auto-limpia fuentes inválidas/fuera de la Reserva en el camino."""
	if not is_instance_valid(card):
		return false
	var card_controller: int = card.controller_id if card.get("controller_id") != null else -1
	var still_valid: Array = []
	var protected_generally := false
	for source in _reserva_conditional_full_silence_immunity_sources:
		if not is_instance_valid(source) or source.get("current_zone") != Constants.Zone.RESERVA_ORO:
			continue
		still_valid.append(source)
		var source_controller: int = source.controller_id if source.get("controller_id") != null else -2
		if source_controller == card_controller:
			protected_generally = true
	_reserva_conditional_full_silence_immunity_sources = still_valid
	return protected_generally


func silence_card(card: Node, source: Node = null, duration: String = "permanent", skip_prevention: bool = false) -> void:
	"""Silencia una carta: pierde todas sus keywords (vía remove_keyword, con la misma limpieza por
	duración/salida de juego) y deja de disparar sus habilidades
	(TriggerSystem._check_trigger_conditions() consulta is_silenced()). No hace nada si aplica
	alguna protección: "Aliados que porten Arma no pueden perder su habilidad" (Manuel Bulnes),
	"Tus Aliados... no pueden perder su habilidad" (Abu Simbel) o la prevención de efectos
	oponentes (Estaca)."""
	if not is_instance_valid(card):
		return
	if _is_protected_from_silence_by_weapon(card):
		print("[KeywordManager] %s no pierde su habilidad — protegido por porta Arma" % _get_card_name(card))
		return
	if _is_protected_from_silence_by_all_allies_source(card):
		print("[KeywordManager] %s no pierde su habilidad — protección de Aliados" % _get_card_name(card))
		return
	if _is_protected_from_silence_by_all_weapons_source(card):
		print("[KeywordManager] %s no pierde su habilidad — protección de Armas" % _get_card_name(card))
		return
	if _is_protected_from_silence_by_self(card):
		print("[KeywordManager] %s no pierde su habilidad — protección propia" % _get_card_name(card))
		return
	if _is_protected_from_silence_by_reserva_source(card):
		print("[KeywordManager] %s no pierde su habilidad — protección de Terminal P-12 en Reserva" % _get_card_name(card))
		return
	# Prevención reactiva (Estaca, tag "silence"); por eso los llamadores de silence_card() usan await.
	# skip_prevention: el llamador ya ofreció la Prevención para todo el efecto (p.ej. Padre Dagón).
	if not skip_prevention and await EffectController.offer_prevention(card, source, "silence"):
		return
	var card_id = card.get_instance_id()
	if not _silenced_cards.has(card_id):
		_silenced_cards[card_id] = []
	_silenced_cards[card_id].append({"source": source, "duration": duration})
	# Solo las keywords que la carta realmente tiene (el log no lista las que no tenía). is_silenced()
	# solo mira si hay entrada en _silenced_cards.
	for keyword in Constants.Keyword.values():
		if has_keyword(card, keyword):
			remove_keyword(card, keyword, source, duration)
	print("[KeywordManager] %s fue silenciada (fuente: %s)" % [
		_get_card_name(card), _get_card_name(source) if source else "efecto"
	])
	if card.has_method("_refresh_disabled_rotation"):
		card._refresh_disabled_rotation()
	_notify_abilities_changed()


## Recalcula las cartas sin habilidad por un aura (SilenceAuras) una vez por frame, tras cualquier
## cambio de Fuerza/zona/habilidad (ContinuousEffectManager._invalidate_cache).
var _aura_refresh_queued := false


func queue_aura_refresh() -> void:
	SilenceAurasScript.invalidate()
	if _aura_refresh_queued:
		return
	_aura_refresh_queued = true
	_run_aura_refresh.call_deferred()


func _run_aura_refresh() -> void:
	_aura_refresh_queued = false
	if SilenceAurasScript.refresh():
		var off: Array = SilenceAurasScript.loop_disabled()
		for src in off:
			print("[KeywordManager] Regla de bucles (DAR 7.7): %s no aplica su habilidad mientras sigan en juego las otras cartas del bucle" % _get_card_name(src))
		_notify_abilities_changed()


func _notify_abilities_changed() -> void:
	"""Las auras de una carta sin habilidad dejan de aplicar (ModifierRegistry.
	_is_modifier_active, §63): hay que recalcular Fuerza/protecciones ya."""
	ContinuousEffectManager._invalidate_cache()
	if ContinuousEffectManager._visual_sync:
		ContinuousEffectManager._visual_sync.call_deferred("update_all_card_visuals")
	abilities_changed.emit()


func _is_card_in_play_generic(card: Node) -> bool:
	var zone = card.get("current_zone")
	return zone != null and zone in Constants.ZONES_IN_PLAY


## Tercer Sello: "los Aliados que estén o entren en juego... si tienen Fuerza 0 no pueden disparar
## sus habilidades". El Talismán se va al Cementerio al resolver, así que no depende de una fuente
## viva (a diferencia de las auras de SilenceAuras): se apaga por conteo de turnos, igual que
## su modificador de Fuerza -3 (SearchOwnZonePatterns.try_execute_tercer_sello_pattern(), mismo
## valor 2 para ambos). Global, sin registrar cartas: se evalúa la Fuerza efectiva en cada consulta
## (ContinuousEffectManager.get_modified_strength()).
var _zero_strength_ability_lock_turns_remaining: int = 0


func register_zero_strength_ability_lock(turns: int) -> void:
	_zero_strength_ability_lock_turns_remaining = max(_zero_strength_ability_lock_turns_remaining, turns)


func _is_silenced_by_zero_strength_lock(card: Node) -> bool:
	if _zero_strength_ability_lock_turns_remaining <= 0:
		return false
	if not is_instance_valid(card) or card.get("card_type") != Constants.CardType.ALIADO:
		return false
	if not _is_card_in_play_generic(card):
		return false
	return ContinuousEffectManager.get_modified_strength(card) <= 0


func is_silenced(card: Node) -> bool:
	"""Verifica si una carta está silenciada (no debe disparar habilidades). Incluye el silencio por
	instancia (_silenced_cards) Y el bloqueo por nombre (_named_ability_locks) — ambos comparten el
	mismo indicador visual (giro 180°, ver Card._refresh_disabled_rotation) y el mismo choke point
	real (TriggerSystem._check_trigger_conditions)."""
	if not is_instance_valid(card):
		return false
	# Convertida "sin habilidad" (Tótem / Oro / Aliado sin habilidad, ConvertPatterns): es otra carta, sin habilidad; no
	# es "perder la habilidad", así que ninguna protección de silencio la cubre.
	if card.get_meta("converted_blank", false):
		return true
	var entries = _silenced_cards.get(card.get_instance_id(), [])
	if not entries.is_empty():
		return true
	if is_instance_locked(card):
		return true
	if _is_silenced_by_zero_strength_lock(card):
		return true
	# Auras "... pierden su habilidad" de las cartas en juego, con la regla de bucles (SilenceAuras.gd).
	if SilenceAurasScript.silenced(card):
		return true
	if _is_turn_name_locked(card):
		return true
	# Sin habilidad por varios turnos (illapa, tukuturi, Cementerio de Kingstead): meta con el último
	# turn_serial en que vale.
	if GameManager.turn_serial <= int(card.get_meta("silenced_until", -1)):
		return true
	# Lanza del Juramento: "una carta no puede utilizar sus habilidades, el próximo turno" (solo ese turno).
	if GameManager.turn_serial == int(card.get_meta("silenced_on_turn", -1)):
		return true
	var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else ""
	if card_name.is_empty():
		return false
	return is_name_locked(card_name)


func lock_ability_by_name(card_name: String, source: Node) -> void:
	"""Registra que todas las copias de 'card_name' (en cualquier zona, presentes o futuras) pierden
	su habilidad mientras 'source' siga vivo y en juego (DAR "nombra una carta para que pierda su
	habilidad", p.ej. Alicia en Wonderland). Sin unregister: is_name_locked() descarta las fuentes
	inválidas."""
	if card_name.is_empty() or not is_instance_valid(source):
		return
	var key := card_name.to_lower()
	if not _named_ability_locks.has(key):
		_named_ability_locks[key] = []
	_named_ability_locks[key].append(source)
	print("[KeywordManager] '%s' pierde su habilidad en todas las Zonas (fuente: %s)" % [
		card_name, _get_card_name(source)
	])
	_notify_abilities_changed()


## "Tu oponente no puede utilizar más habilidades de cartas con ese nombre este turno" (Culto a la
## Muerte): {nombre: {player, turn, active}}. player -1 = las cartas de todos los jugadores (Medalla de
## Santa Muerte: "Las cartas con ese nombre no tienen habilidad por el turno").
var _turn_name_locks: Dictionary = {}


func lock_name_this_turn(card_name: String, player_id: int) -> void:
	_turn_name_locks[card_name.to_lower()] = {"player": player_id, "turn": GameManager.turn_serial,
		"active": GameManager.active_player_id}


## Apofis del Caos: "una carta y todas sus copias pierden su habilidad ... hasta tu próximo turno" —
## este turno y el del rival. player_id -1 = las de todos.
func lock_name_until_next_turn(card_name: String, player_id: int) -> void:
	_turn_name_locks[card_name.to_lower()] = {"player": player_id, "turn": GameManager.turn_serial,
		"until": GameManager.turn_serial + 1, "active": GameManager.active_player_id}


func _is_turn_name_locked(card: Node) -> bool:
	if _turn_name_locks.is_empty():
		return false
	var entry: Dictionary = _turn_name_locks.get(str(card.get("card_name")).to_lower(), {})
	if entry.is_empty():
		return false
	if entry.has("until"):  # lock_name_until_next_turn()
		if GameManager.turn_serial > int(entry.until):
			_turn_name_locks.erase(str(card.get("card_name")).to_lower())
			return false
	elif entry.turn != GameManager.turn_serial or entry.active != GameManager.active_player_id:
		_turn_name_locks.erase(str(card.get("card_name")).to_lower())
		return false
	if int(entry.player) < 0:
		return true
	var ctrl: int = card.controller_id if card.get("controller_id") != null else 0
	return ctrl == int(entry.player)


func is_name_locked(card_name: String) -> bool:
	"""Verifica si el nombre de carta dado está bloqueado por algún
	lock_ability_by_name() todavía vigente — descarta en el camino las
	fuentes inválidas o que ya salieron de juego (auto-limpieza perezosa,
	sin necesidad de un hook explícito de 'on_left_play' de la fuente)."""
	var key := card_name.to_lower()
	if not _named_ability_locks.has(key):
		return false
	var sources: Array = _named_ability_locks[key]
	var still_valid: Array = []
	var any_active := false
	for source in sources:
		if not is_instance_valid(source):
			continue
		var zone = source.get("current_zone")
		if zone != null and zone not in Constants.ZONES_IN_PLAY:
			continue
		still_valid.append(source)
		any_active = true
	if still_valid.size() != sources.size():
		if still_valid.is_empty():
			_named_ability_locks.erase(key)
		else:
			_named_ability_locks[key] = still_valid
	return any_active


func lock_ability_by_instance(card: Node, source: Node) -> void:
	"""Registra que ESTA carta (no todas las copias, ver lock_ability_by_name) pierde su habilidad
	mientras 'source' siga vivo y en juego (DAR "pierda su habilidad... mientras [esta carta] esté
	en juego", p.ej. Kuchiku Kan). Sin unregister: is_instance_locked() descarta las fuentes
	inválidas."""
	if not is_instance_valid(card) or not is_instance_valid(source):
		return
	var key := card.get_instance_id()
	if not _instance_ability_locks.has(key):
		_instance_ability_locks[key] = []
	_instance_ability_locks[key].append(source)
	print("[KeywordManager] %s pierde su habilidad (fuente: %s, mientras esté en juego)" % [
		_get_card_name(card), _get_card_name(source)
	])
	_notify_abilities_changed()


func is_instance_locked(card: Node) -> bool:
	"""Verifica si esta carta puntual está bloqueada por algún
	lock_ability_by_instance() todavía vigente — descarta en el camino las
	fuentes inválidas o que ya salieron de juego (auto-limpieza perezosa)."""
	if not is_instance_valid(card):
		return false
	var key := card.get_instance_id()
	if not _instance_ability_locks.has(key):
		return false
	var sources: Array = _instance_ability_locks[key]
	var still_valid: Array = []
	var any_active := false
	for source in sources:
		if not is_instance_valid(source):
			continue
		var zone = source.get("current_zone")
		if zone != null and zone not in Constants.ZONES_IN_PLAY:
			continue
		still_valid.append(source)
		any_active = true
	if still_valid.size() != sources.size():
		if still_valid.is_empty():
			_instance_ability_locks.erase(key)
		else:
			_instance_ability_locks[key] = still_valid
	return any_active


func is_errante(card: Node) -> bool:
	"""Verifica Errante (solo 1 copia de esta carta en juego a la vez)"""
	return has_keyword(card, Keyword.ERRANTE)


func is_retador(card: Node) -> bool:
	"""Verifica Retador (el atacante elige qué Aliado enemigo debe bloquearlo)"""
	return has_keyword(card, Keyword.RETADOR)


# =============================================================================
# MODIFICACIÓN TEMPORAL DE KEYWORDS
# =============================================================================
func grant_keyword(card: Node, keyword: int, source: Node = null, duration: String = "turn") -> void:
	"""Otorga un keyword temporalmente a una carta

	Args:
		card: Carta objetivo
		keyword: Keyword a otorgar
		source: Carta/efecto que otorga el keyword
		duration: "turn", "combat", "permanent", "until_next_turn" (hasta el próximo turno de quien la
			otorga: vale este turno y el del rival, ver has_keyword())
	"""
	var card_id = card.get_instance_id()

	if not _temporary_keywords.has(card_id):
		_temporary_keywords[card_id] = {}

	if not _temporary_keywords[card_id].has(keyword):
		_temporary_keywords[card_id][keyword] = []

	var entry := {"source": source, "duration": duration}
	if duration == "until_next_turn":
		entry["until_serial"] = GameManager.turn_serial + 1
	_temporary_keywords[card_id][keyword].append(entry)

	print("[KeywordManager] %s ganó %s (fuente: %s, duración: %s)" % [
		_get_card_name(card),
		Constants.Keyword.keys()[keyword],
		_get_card_name(source) if source else "efecto",
		duration
	])

	emit_signal("keyword_granted", card, keyword, source)


func remove_keyword(card: Node, keyword: int, source: Node = null, duration: String = "turn") -> void:
	"""Remueve temporalmente un keyword de una carta (Regla de Prioridad Negativa)"""
	var card_id = card.get_instance_id()

	if not _removed_keywords.has(card_id):
		_removed_keywords[card_id] = {}

	if not _removed_keywords[card_id].has(keyword):
		_removed_keywords[card_id][keyword] = []

	_removed_keywords[card_id][keyword].append({
		"source": source,
		"duration": duration
	})

	print("[KeywordManager] %s perdió %s (fuente: %s)" % [
		_get_card_name(card),
		Constants.Keyword.keys()[keyword],
		_get_card_name(source) if source else "efecto"
	])

	emit_signal("keyword_removed", card, keyword, source)


# =============================================================================
# LIMPIEZA
# =============================================================================
func _on_turn_ended(_player_id: int) -> void:
	"""Limpia keywords temporales al final del turno"""
	_cleanup_by_duration("turn")
	# Tercer Sello — mismo criterio de conteo que el modificador de Fuerza -3 hermano
	# (ContinuousEffectManager, duration=TIMED): se descuenta en CADA fin de turno de cualquier
	# jugador, no solo el propio.
	if _zero_strength_ability_lock_turns_remaining > 0:
		_zero_strength_ability_lock_turns_remaining -= 1


func cleanup_combat_keywords() -> void:
	"""Limpia keywords que duran solo el combate"""
	_cleanup_by_duration("combat")


func _cleanup_by_duration(duration: String) -> void:
	"""Limpia keywords con duración específica"""
	# Limpiar temporales otorgados
	for card_id in _temporary_keywords.keys():
		var keywords_to_remove: Array = []
		for keyword in _temporary_keywords[card_id]:
			var sources = _temporary_keywords[card_id][keyword]
			# Las "hasta tu próximo turno" vencidas también se van.
			sources = sources.filter(func(s): return s.duration != duration \
				and int(s.get("until_serial", 1 << 30)) >= GameManager.turn_serial)
			if sources.is_empty():
				keywords_to_remove.append(keyword)
			else:
				_temporary_keywords[card_id][keyword] = sources

		for keyword in keywords_to_remove:
			_temporary_keywords[card_id].erase(keyword)

		if _temporary_keywords[card_id].is_empty():
			_temporary_keywords.erase(card_id)

	# Limpiar removidos temporales
	for card_id in _removed_keywords.keys():
		var keywords_to_restore: Array = []
		for keyword in _removed_keywords[card_id]:
			var sources = _removed_keywords[card_id][keyword]
			sources = sources.filter(func(s): return s.duration != duration)
			if sources.is_empty():
				keywords_to_restore.append(keyword)
			else:
				_removed_keywords[card_id][keyword] = sources

		for keyword in keywords_to_restore:
			_removed_keywords[card_id].erase(keyword)

		if _removed_keywords[card_id].is_empty():
			_removed_keywords.erase(card_id)

	# Limpiar silenciados con esta duración
	for card_id in _silenced_cards.keys():
		var entries = _silenced_cards[card_id]
		entries = entries.filter(func(e): return e.duration != duration)
		if entries.is_empty():
			_silenced_cards.erase(card_id)
			# Ya no está silenciada — restaurar el giro visual si tampoco está convertida (ver
			# Card._refresh_disabled_rotation).
			var card_node = instance_from_id(card_id)
			if card_node and is_instance_valid(card_node) and card_node.has_method("_refresh_disabled_rotation"):
				card_node._refresh_disabled_rotation()
		else:
			_silenced_cards[card_id] = entries


func clear_all_for_card(card: Node) -> void:
	"""Limpia los keywords temporales y el silencio de una carta (cuando sale del juego)"""
	var card_id = card.get_instance_id()
	_temporary_keywords.erase(card_id)
	_removed_keywords.erase(card_id)
	_silenced_cards.erase(card_id)


# =============================================================================
# UTILIDADES
# =============================================================================
func _get_card_name(card) -> String:
	"""Helper para obtener nombre de carta"""
	if card == null:
		return "null"
	# is_instance_valid() PRIMERO: 'is Node' sobre una referencia ya liberada falla con "Left operand
	# of 'is' is a previously freed instance" (como en ContinuousEffectManager y ContinuousVisualSync).
	if is_instance_valid(card) and card is Node and card.get("card_name") != null:
		return card.card_name
	return "Carta"
