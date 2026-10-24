extends Node
## ContinuousEffectManager - Gestiona efectos continuos y modificadores (Sección 7.2)
## Registra modificadores de cartas en juego y recalcula valores dinámicamente

# =============================================================================
# SEÑALES
# =============================================================================
signal modifier_registered(modifier: Dictionary)
signal modifier_removed(modifier_id: String)
signal card_stats_changed(card: Node, stat: String, old_value: int, new_value: int)
signal recalculation_completed(affected_cards: Array)

## Señales para actualización visual de UI
signal strength_bonus_gained(card: Node, bonus: int, total_strength: int, source_name: String)
signal strength_bonus_lost(card: Node, bonus: int, total_strength: int, source_name: String)
signal cost_modified(card: Node, old_cost: int, new_cost: int)
signal card_visual_update_required(card: Node, stat: String, base_value: int, modified_value: int)

# =============================================================================
# ENUMS
# =============================================================================
enum ModifierType {
	STRENGTH,       # Modifica fuerza
	COST,           # Modifica coste
	DAMAGE,         # Modifica daño infligido
	KEYWORDS,       # Agrega/quita keywords
	ABILITIES,      # Agrega/quita habilidades
	PROTECTION,     # Protección contra efectos
	RESTRICTION,    # Restricciones (no puede atacar, etc.)
	ZONE_CHANGE,    # Modifica comportamiento de cambio de zona
	CUSTOM          # Efectos personalizados
}

enum ModifierDuration {
	PERMANENT,      # Mientras la fuente esté en juego
	UNTIL_END_TURN, # Hasta fin del turno
	UNTIL_LEAVES,   # Hasta que el objetivo salga del juego
	TIMED,          # Por X turnos
	CONDITIONAL     # Mientras se cumpla una condición
}

enum ModifierLayer {
	# Capas de aplicación (orden importa)
	LAYER_0_BASE,           # Valores base impresos
	LAYER_1_COPY,           # Efectos de copia
	LAYER_2_CONTROL,        # Cambios de control
	LAYER_3_TEXT,           # Cambios de texto/habilidades
	LAYER_4_TYPE,           # Cambios de tipo
	LAYER_5_COLOR,          # Cambios de color/raza
	LAYER_6_ABILITIES,      # Agregar/quitar habilidades
	LAYER_7A_CHAR_SETTING,  # Establecer fuerza/coste a valor específico
	LAYER_7B_CHAR_MODIFY,   # Modificar fuerza/coste (+X/-X)
	LAYER_7C_COUNTERS,      # Contadores
	LAYER_8_COMBAT          # Modificadores de combate
}

# =============================================================================
# ESTADO
# =============================================================================
## Todos los modificadores activos: {modifier_id: modifier_data}
var _modifiers: Dictionary = {}

## Índice por carta afectada: {card_id: [modifier_ids]}
var _modifiers_by_target: Dictionary = {}

## Índice por carta fuente: {source_id: [modifier_ids]}
var _modifiers_by_source: Dictionary = {}

## Índice por tipo: {ModifierType: [modifier_ids]}
var _modifiers_by_type: Dictionary = {}

## Cache de valores calculados: {card_id: {stat: value}}
var _calculated_cache: Dictionary = {}

## Valores anteriores para detectar cambios: {card_id: {stat: value}}
var _previous_values: Dictionary = {}

## Flag para invalidar cache
var _cache_dirty: bool = false

## Contador para IDs únicos
var _modifier_counter: int = 0

## Regla de Prioridad Negativa (Sección 7.4)
## Las restricciones y efectos negativos tienen prioridad absoluta
const NEGATIVE_PRIORITY_ENABLED: bool = true

# =============================================================================
# REFERENCIAS
# =============================================================================
var _game_board: Node = null

## Módulos extraídos (Fase 4 de reestructuración)
var _keyword_query: KeywordQuery
var _visual_sync: ContinuousVisualSync
var _modifier_registry: ModifierRegistry
var _effect_parser: ContinuousEffectParser


func _ready() -> void:
	_keyword_query = KeywordQuery.new()
	_keyword_query.setup(self)
	_visual_sync = ContinuousVisualSync.new()
	_visual_sync.setup(self)
	_modifier_registry = ModifierRegistry.new()
	_modifier_registry.setup(self)
	_effect_parser = ContinuousEffectParser.new()
	_effect_parser.setup(self)

	# Inicializar índices por tipo
	for type in ModifierType.values():
		_modifiers_by_type[type] = []

	call_deferred("_get_references")
	call_deferred("_connect_signals")
	print("[ContinuousEffectManager] Inicializado")


func _get_references() -> void:
	# _game_board queda siempre null: apuntaba a /root/Main/GameBoard, que es
	# un Control plano sin script (ver Main.tscn) — no un GameBoard.gd real
	# (ese archivo era huérfano y se eliminó). Sirve solo como fallback
	# inerte para recalculate_all()/update_all_card_visuals(), que hoy no
	# los llama nadie.
	pass


func _connect_signals() -> void:
	# Conectar a GameManager (único conductor de turnos) para limpiar los modificadores temporales al
	# final de cada turno.
	if GameManager and GameManager.has_signal("turn_ended"):
		GameManager.turn_ended.connect(_on_turn_ended)

	# Conectar a EffectController para detectar cartas que entran/salen del
	# juego. Antes intentaba conectarse a señales 'card_entered_zone'/
	# 'card_left_zone' de un GameBoard que nunca existió con esas señales
	# — _on_card_entered_zone()/_on_card_left_zone() nunca se llamaban, así
	# que ningún efecto continuo se registraba/limpiaba automáticamente al
	# entrar o salir de juego. EffectController sí emite estos eventos de
	# verdad (on_card_entered_play/on_card_left_play).
	EffectController.on_card_entered_play.connect(_on_effect_controller_card_entered)
	EffectController.on_card_left_play.connect(_on_effect_controller_card_left)
	# La Fuerza de las auras con condición (StrengthAuras: "Si tienes tres o más Aliados en tu
	# Cementerio...", "por cada Tótem...") cambia sin que se registre ningún modificador: se refrescan
	# los contadores de Fuerza cuando cambia algo de lo que dependen.
	EffectController.on_card_entered_play.connect(func(_p, _c, _z): request_strength_badge_refresh())
	EffectController.on_card_left_play.connect(func(_p, _c, _z): request_strength_badge_refresh())
	for sig in ["card_put_in_cemetery", "card_put_in_exile", "hand_count_changed", "cemetery_count_changed",
			"exile_count_changed", "field_count_changed"]:
		CardManager.connect(sig, func(_a = null, _b = null): request_strength_badge_refresh())
	GameManager.turn_started.connect(func(_p, _t): request_strength_badge_refresh())
	GameManager.phase_changed.connect(func(_ph): request_strength_badge_refresh())


var _badge_refresh_pending := false


func request_strength_badge_refresh() -> void:
	"""Refresca (una vez por frame) el contador de Fuerza de todas las cartas en juego."""
	if _badge_refresh_pending:
		return
	_badge_refresh_pending = true
	_refresh_strength_badges.call_deferred()


func _refresh_strength_badges() -> void:
	_badge_refresh_pending = false
	_invalidate_cache()
	for card in _get_all_cards_in_play():
		if is_instance_valid(card) and card.has_method("refresh_strength_badge"):
			card.refresh_strength_badge()


func _on_effect_controller_card_entered(_player_id: int, card: Node, zone: int) -> void:
	# "este turno" desde que entró (shade).
	if is_instance_valid(card):
		card.set_meta("entered_play_turn", GameManager.turn_serial)
		load("res://scripts/core/effects/continuous/SilenceAuras.gd").mark_entered(card)
		# Supremacia Kaiju: "El próximo Oro que ponga en juego tu oponente
		# entra sin habilidad por el turno."
		load("res://scripts/core/effects/mechanics/SearchPatterns.gd").on_card_entered(card, zone)
	_on_card_entered_zone(card, zone, _player_id)


func _on_effect_controller_card_left(_player_id: int, card: Node, from_zone: int) -> void:
	_on_card_left_zone(card, from_zone, _player_id)


# =============================================================================
# REGISTRO DE MODIFICADORES Y CÁLCULO DE VALORES (implementación en
# ModifierRegistry.gd — Sección 7.4/8. El estado, _modifiers/_modifiers_by_*/
# cache, sigue viviendo aquí abajo en ESTADO; ModifierRegistry lo consulta
# vía _main, igual que ContinuousVisualSync.gd ya lo hacía)
# =============================================================================
func register_modifier(params: Dictionary) -> String:
	# Marca de los Justos: "Este turno, cada vez que un Aliado fuera a ganar Fuerza en vez de eso gana el
	# doble, hasta un máximo de 4 de Fuerza por vez. No puede modificar su Fuerza de otra forma este
	# turno." Solo lo que se registra después de jugarla (lo anterior no cambia).
	if not RuleState.turn_data("marca_justos").is_empty() and params.get("type") == ModifierType.STRENGTH:
		var target = params.get("target")
		if is_instance_valid(target) and target.get("card_type") == Constants.CardType.ALIADO:
			var value: int = int(params.get("value", 0))
			if params.get("operation", "add") != "add" or value <= 0:
				print("[ContinuousEffectManager] Marca de los Justos: la Fuerza de %s no se modifica de otra forma" % str(target.get("card_name")))
				return ""
			params["value"] = mini(value * 2, 4)
	var mod_id: String = _modifier_registry.register_modifier(params)
	_note_strength_gain(params, mod_id)
	# Shakar Raj: "Aliados que hayan modificado su Fuerza este turno" (cualquier efecto, de cualquier jugador).
	var mod_target = params.get("target")
	if not mod_id.is_empty() and params.get("type") == ModifierType.STRENGTH and is_instance_valid(mod_target) \
			and mod_target.get("card_type") == Constants.CardType.ALIADO:
		mod_target.set_meta("strength_mod_turn", GameManager.turn_serial)
	return mod_id


## pirata wokou, lobo malvado, Dinosaurio Megalosaurus: "cuando un Aliado gane Fuerza (permanentemente)".
## Las auras (PERMANENT con otra carta como fuente) no cuentan: se vuelven a registrar al recalcular.
func _note_strength_gain(params: Dictionary, mod_id: String) -> void:
	if mod_id.is_empty() or params.get("type") != ModifierType.STRENGTH or params.get("operation", "add") != "add" \
			or int(params.get("value", 0)) <= 0:
		return
	var target = params.get("target")
	if not is_instance_valid(target) or target.get("card_type") != Constants.CardType.ALIADO:
		return
	var source = params.get("source")
	var duration = params.get("duration", ModifierDuration.PERMANENT)
	var permanent: bool = duration == ModifierDuration.PERMANENT and source == null
	if duration == ModifierDuration.PERMANENT and source != null and source != target:
		return
	load("res://scripts/core/effects/triggers/LimitedEventTriggers.gd").fire("strength_gain",
		{"target": target, "permanent": permanent, "source": source})


func unregister_modifier(modifier_id: String) -> bool:
	return _modifier_registry.unregister_modifier(modifier_id)


func remove_modifiers_from_source(source: Node) -> int:
	return _modifier_registry.remove_modifiers_from_source(source)


func get_modified_strength(card: Node) -> int:
	return _modifier_registry.get_modified_strength(card)


func get_modified_cost(card: Node) -> int:
	return _modifier_registry.get_modified_cost(card)


## "Carta de coste N o menos" (regla confirmada por el usuario): un Oro NO tiene coste salvo que
## esté en juego como Aliado, así que nunca cumple un filtro de coste. get_modified_cost sigue igual
## (pagos, badge).
func cost_at_most(card, max_cost: int) -> bool:
	if card == null or not is_instance_valid(card) or card.get("card_type") == Constants.CardType.ORO:
		return false
	return get_modified_cost(card) <= max_cost


func data_cost_at_most(card_data: Dictionary, max_cost: int) -> bool:
	"""Lo mismo para datos (Castillo, Cementerio, Destierro)."""
	if int(card_data.get("tipo", -1)) == Constants.CardType.ORO:
		return false
	return int(card_data.get("coste", 99)) <= max_cost


func get_modified_damage(card: Node) -> int:
	return _modifier_registry.get_modified_damage(card)


func _get_base_stat(card: Node, stat: String) -> int:
	return _modifier_registry._get_base_stat(card, stat)


func _get_applicable_modifiers(card: Node, stat: String) -> Array:
	return _modifier_registry._get_applicable_modifiers(card, stat)


func _compare_modifiers(a: Dictionary, b: Dictionary) -> bool:
	return _modifier_registry._compare_modifiers(a, b)


func _is_negative_modifier(modifier: Dictionary) -> bool:
	return _modifier_registry._is_negative_modifier(modifier)


func _is_modifier_active(modifier: Dictionary) -> bool:
	return _modifier_registry._is_modifier_active(modifier)


func _calculate_modifier_value(modifier: Dictionary, card: Node, current_value: int) -> int:
	return _modifier_registry._calculate_modifier_value(modifier, card, current_value)


func _apply_operation(current: int, value: int, operation: String) -> int:
	return _modifier_registry._apply_operation(current, value, operation)


# =============================================================================
# KEYWORDS, HABILIDADES Y RESTRICCIONES (implementación en KeywordQuery.gd)
# =============================================================================
func get_active_keywords(card: Node) -> Array:
	return _keyword_query.get_active_keywords(card)


func has_keyword(card: Node, keyword) -> bool:
	return _keyword_query.has_keyword(card, keyword)


func aura_removes_keyword(card: Node, keyword: int) -> bool:
	return _keyword_query.aura_removes_keyword(card, keyword)


func has_protection(card: Node, protection_type: String = "") -> bool:
	return _keyword_query.has_protection(card, protection_type)


func can_attack(card: Node) -> bool:
	return _keyword_query.can_attack(card)


func can_block(card: Node) -> bool:
	return _keyword_query.can_block(card)


func can_be_targeted(card: Node, source: Node = null) -> bool:
	return _keyword_query.can_be_targeted(card, source)

# =============================================================================
# EVENTOS Y LIMPIEZA
# =============================================================================
func _on_turn_ended(player_id: int) -> void:
	"""Handler para fin de turno - limpia modificadores temporales"""
	var to_remove: Array = []

	for mod_id in _modifiers:
		var mod = _modifiers[mod_id]

		match mod.duration:
			ModifierDuration.UNTIL_END_TURN:
				to_remove.append(mod_id)

			ModifierDuration.TIMED:
				mod.turns_remaining -= 1
				if mod.turns_remaining <= 0:
					to_remove.append(mod_id)

	# Remover modificadores expirados
	for mod_id in to_remove:
		unregister_modifier(mod_id)

	if not to_remove.is_empty():
		print("[ContinuousEffectManager] %d modificadores expirados al fin del turno" % to_remove.size())


func _on_card_entered_zone(card: Node, zone: int, player_id: int) -> void:
	"""Handler cuando una carta entra a una zona

	Registra efectos continuos de cartas que entran en juego.
	"""
	# Solo procesar cartas que entran en zonas de juego
	if zone not in Constants.ZONES_IN_PLAY:
		return

	# Verificar si la carta tiene efectos continuos
	_register_card_continuous_effects(card)

	# Invalidar cache
	_invalidate_cache()
	if _visual_sync:
		_visual_sync.call_deferred("update_all_card_visuals")


func _on_card_left_zone(card: Node, zone: int, player_id: int) -> void:
	"""Handler cuando una carta sale de una zona

	Remueve todos los modificadores de esa carta como fuente.
	"""
	# Solo procesar si sale de zonas de juego
	if zone not in Constants.ZONES_IN_PLAY:
		return

	# Remover modificadores de esta carta como fuente
	remove_modifiers_from_source(card)

	# Invalidar cache
	_invalidate_cache()
	if _visual_sync:
		_visual_sync.call_deferred("update_all_card_visuals")


func _register_card_continuous_effects(card: Node) -> void:
	_effect_parser._register_card_continuous_effects(card)


# =============================================================================
# RECÁLCULO Y CACHE
# =============================================================================
func _invalidate_cache() -> void:
	"""Invalida el cache de valores calculados"""
	_cache_dirty = true
	_calculated_cache.clear()
	KeywordManager.queue_aura_refresh()


# =============================================================================
# UTILIDADES
# =============================================================================
func _get_card_id(card) -> String:
	"""ID único de una carta para _calculated_cache: el instance_id de Godot, único por Node.
	'card_id' es el de la carta impresa (myl_id), igual en todas las copias, y hacía que una copia
	heredara los buffs cacheados de otra."""
	if card == null:
		return "null"

	if card is String:
		return card

	# is_instance_valid() PRIMERO: 'is Node' sobre una carta ya liberada (destruida/desterrada sin
	# limpiar su modificador) falla con "Left operand of 'is' is a previously freed instance";
	# is_instance_valid() es seguro sobre cualquier Variant.
	if is_instance_valid(card) and card is Node:
		return str(card.get_instance_id())

	if card is Dictionary:
		return card.get("id", str(card.hash()))

	return str(card)


func _get_card_name(card) -> String:
	"""Obtiene el nombre de una carta"""
	if card == null:
		return "???"

	if is_instance_valid(card) and card is Node:
		if card.get("card_name"):
			return card.card_name
		if card.get("nombre"):
			return card.nombre

	if card is Dictionary:
		return card.get("name", card.get("nombre", "???"))

	return "???"


func _get_card_type(card: Node) -> String:
	"""Obtiene el tipo de una carta"""
	if card == null:
		return ""

	if card.get("card_type"):
		var ct = card.card_type
		if ct is int:
			return Constants.CardType.keys()[ct]
		return str(ct)

	if card.get("tipo"):
		return str(card.tipo)

	return ""


func _get_card_owner(card: Node) -> int:
	"""Jugador que CONTROLA la carta ahora (pese al nombre), para targeting ALLIES/ENEMIES. Usa
	controller_id, que sigue a owner_id salvo que un efecto gane el control
	(gain_control_of_card())."""
	if card == null:
		return -1
	if card.get("controller_id") != null:
		return card.controller_id
	if card.get("owner_id") != null:
		return card.owner_id
	return -1


func _abu_simbel_in_play(main: Node) -> bool:
	for container in [main.player_gold, main.player_oro_pagado, main.opponent_gold, main.opponent_oro_pagado,
			main.player_field, main.opponent_field, main.player_linea_apoyo, main.opponent_linea_apoyo]:
		if not container:
			continue
		for c in container.get_children():
			if is_instance_valid(c) and not KeywordManager.is_silenced(c) \
					and "los jugadores no pueden ganar el control de cartas de las que no sean dueño" in str(c.get("card_ability")).to_lower():
				return true
	return false


func gain_control_of_card(card: Node, new_controller_id: int) -> void:
	""""Gana el control de" una carta en juego (p.ej. shedo titan: "gana el control de un Aliado"):
	reparenta el nodo al contenedor del nuevo controlador (Aliado → Línea de Defensa, Tótem → Línea
	de Apoyo, Oro → Reserva) y cambia controller_id, no owner_id (DAR: sigue siendo del dueño y
	vuelve a su Cementerio/Destierro). Como _get_card_owner() usa controller_id, los targets
	ALLIES/ENEMIES y las auras "tus Aliados" ven el cambio de inmediato."""
	if not is_instance_valid(card) or new_controller_id == card.controller_id:
		return
	var main := get_node_or_null("/root/Main")
	if not main:
		return
	# Abu Simbel: "Los jugadores no pueden ganar el control de cartas de las que no sean dueño."
	var owner_of: int = card.owner_id if card.get("owner_id") != null else new_controller_id
	if new_controller_id != owner_of and _abu_simbel_in_play(main):
		main._update_debug("Abu Simbel: no se puede ganar el control de cartas ajenas")
		return
	# duelo en ganryu: "no puede ... cambiar de controlador hasta tu próximo turno" (meta = último turn_serial).
	if GameManager.turn_serial <= int(card.get_meta("no_control_change_until", -1)):
		main._update_debug("%s no puede cambiar de controlador" % str(card.get("card_name")))
		return
	var card_type: int = card.get("card_type") if card.get("card_type") != null else -1
	var old_parent = card.get_parent()
	if old_parent:
		old_parent.remove_child(card)

	var target_container: Node = null
	var target_zone: int = Constants.Zone.LINEA_DEFENSA
	match card_type:
		Constants.CardType.TOTEM:
			target_container = main.player_linea_apoyo if new_controller_id == 0 else main.opponent_linea_apoyo
			target_zone = Constants.Zone.LINEA_APOYO
		Constants.CardType.ORO:
			target_container = main.player_gold if new_controller_id == 0 else main.opponent_gold
			target_zone = Constants.Zone.RESERVA_ORO
		_:
			target_container = main.player_field if new_controller_id == 0 else main.opponent_field
			target_zone = Constants.Zone.LINEA_DEFENSA
	if not target_container:
		return

	target_container.add_child(card)
	card.controller_id = new_controller_id
	card.can_interact = (new_controller_id == 0)
	card.set_zone(target_zone)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


func count_other_copies_in_play(card: Node) -> int:
	"""Cuenta las OTRAS copias (mismo nombre, sin contar 'card') del controlador de 'card' que hay en
	juego, para "si no controla otra copia de esa carta" (Tamales). Es relativo a la copia puntual:
	con 1 copia en juego, esa funciona y las de mano/Cementerio/Castillo no (para ellas la de juego
	es "otra copia"); con 2 en juego, ambas quedan bloqueadas. Incluye Reserva y Oro Pagado
	(Tamales habla de Oros)."""
	if not is_instance_valid(card):
		return 0
	var name: String = str(card.get("card_name")).to_lower() if card.get("card_name") != null else ""
	if name.is_empty():
		return 0
	var owner: int = _get_card_owner(card)
	var main = get_node_or_null("/root/Main")
	if not main:
		return 0
	var count := 0
	for field in [main.get("player_field"), main.get("player_linea_ataque"), main.get("player_linea_apoyo"),
			main.get("opponent_field"), main.get("opponent_linea_ataque"), main.get("opponent_linea_apoyo"),
			main.get("player_gold"), main.get("opponent_gold"), main.get("player_oro_pagado"), main.get("opponent_oro_pagado")]:
		if not field:
			continue
		for other in field.get_children():
			if other == card or not is_instance_valid(other):
				continue
			if _get_card_owner(other) != owner:
				continue
			if str(other.get("card_name")).to_lower() == name:
				count += 1
	return count


## Mártires: "no se pueden utilizar habilidades ni jugar cartas por el resto del turno" (turn_serial).
var no_abilities_turn: int = -1


func tamales_ability_restriction_reason(card: Node) -> String:
	"""Tamales: "Tu oponente sólo puede utilizar las habilidades de Oros y cartas de coste 2 o más si
	no controla otra copia de esa carta". Combina el chequeo de jugador (¿hay un Tamales rival en
	juego?) y el de carta, relativo a la copia que intenta usar la habilidad
	(count_other_copies_in_play(); con 2 copias en juego, ninguna dispara ni activa). Se usa para
	habilidades ACTIVADAS (CardInspectionLayer._validate_ability()) y DISPARADAS
	(TriggerSystem._check_trigger_conditions()); los efectos continuos siguen en pie.
	También corta todas las habilidades el turno de Mártires (no_abilities_turn).
	Devuelve '' si no aplica; si no, un motivo legible."""
	if not is_instance_valid(card):
		return ""
	if no_abilities_turn == GameManager.turn_serial:
		return "no se pueden utilizar habilidades por el resto del turno"
	var card_type = card.get("card_type")
	var card_cost: int = int(card.get("card_cost")) if card.get("card_cost") != null else 0
	if card_type != Constants.CardType.ORO and card_cost < 2:
		return ""
	var owner: int = _get_card_owner(card)
	var main = get_node_or_null("/root/Main")
	if not main:
		return ""

	var tamales_against_me := false
	for field in [main.get("player_field"), main.get("opponent_field"), main.get("player_linea_ataque"), main.get("opponent_linea_ataque"),
			main.get("player_linea_apoyo"), main.get("opponent_linea_apoyo"),
			main.get("player_gold"), main.get("opponent_gold"), main.get("player_oro_pagado"), main.get("opponent_oro_pagado")]:
		if not field:
			continue
		for c in field.get_children():
			if not is_instance_valid(c) or str(c.get("card_name")).to_lower() != "tamales":
				continue
			if _get_card_owner(c) != owner:
				tamales_against_me = true
				break
		if tamales_against_me:
			break
	if not tamales_against_me:
		return ""

	if count_other_copies_in_play(card) > 0:
		var card_name: String = str(card.get("card_name")) if card.get("card_name") != null else "Esa carta"
		return "Tamales: %s no puede usar su habilidad — controlas otra copia" % card_name
	return ""


func _get_all_cards_in_play() -> Array:
	"""Todas las cartas de ambos jugadores en las 3 líneas del campo — usado para refrescar el badge
	visual de TODOS los afectados cuando se registra/quita un aura de target dinámico
	(ALL/ALLIES/ENEMIES/OTHER), ya que _resolve_targets no las enumera (se resuelven carta por
	carta en _get_applicable_modifiers, no aquí)."""
	var main = get_node_or_null("/root/Main")
	if not main:
		return []
	var result: Array = []
	for field in [main.get("player_field"), main.get("player_linea_ataque"), main.get("player_linea_apoyo"),
				  main.get("opponent_field"), main.get("opponent_linea_ataque"), main.get("opponent_linea_apoyo")]:
		if not field:
			continue
		for card in field.get_children():
			result.append(card)
	return result


func _controls_n_allies_of_same_race(player_id: int, threshold: int) -> bool:
	"""¿'player_id' controla al menos 'threshold' Aliados que compartan UNA misma Raza? (p.ej. Trono
	del Dragón: 'Si controlas tres o más Aliados de la misma Raza') — no es 'threshold Aliados en
	total', necesitan compartir Raza entre sí. Se recuenta desde cero en cada llamada (sin cache):
	se usa como condition Callable de un modificador CONDITIONAL, que ContinuousEffectManager
	reevalúa en cada consulta."""
	if threshold <= 0:
		return true
	var race_counts: Dictionary = {}
	for c in _get_all_cards_in_play():
		if not is_instance_valid(c) or c.get("card_type") != Constants.CardType.ALIADO:
			continue
		if _get_card_owner(c) != player_id:
			continue
		var race: String = str(c.get("card_raza")) if c.get("card_raza") != null else ""
		if race.is_empty():
			continue
		race_counts[race] = race_counts.get(race, 0) + 1
	for race in race_counts:
		if race_counts[race] >= threshold:
			return true
	return false


func _get_card_zone(card: Node) -> int:
	"""Zona actual de una carta. Se compara contra null, no por verdad: Constants.Zone.RESERVA_ORO
	vale 0 y 'if 0:' es false, lo que dejaba fuera de juego a todo Oro de la Reserva (y sin efecto
	sus auras PERMANENT, p.ej. Armería del Guerrero)."""
	if card == null:
		return -1

	var zone = card.get("current_zone")
	if zone == null:
		return -1

	return zone


func _is_card_in_play(card: Node) -> bool:
	"""Verifica si una carta está en una zona de juego"""
	if card == null or not is_instance_valid(card):
		return false

	var zone = _get_card_zone(card)
	return zone in Constants.ZONES_IN_PLAY


func _resolve_targets(modifier: Dictionary) -> Array:
	"""Resuelve los targets de un modificador a un array de cartas"""
	var target = modifier.target
	var targets: Array = []

	if target == null:
		return targets

	# is_instance_valid() PRIMERO (como _get_card_id()/_get_card_name()): modifier.target puede ser una
	# carta que salió de juego sin limpiar el modificador.
	if is_instance_valid(target) and target is Node:
		targets.append(target)
	elif target is Array:
		targets = target
	# Strings como "ALL", "ALLIES" se manejan dinámicamente

	return targets


func _string_to_keyword(keyword_str: String) -> int:
	"""Convierte string de keyword a enum"""
	match keyword_str.to_upper():
		"FURIA": return Constants.Keyword.FURIA
		"IMBLOQUEABLE": return Constants.Keyword.IMBLOQUEABLE
		"INDESTRUCTIBLE": return Constants.Keyword.INDESTRUCTIBLE
		"INDESTERRABLE": return Constants.Keyword.INDESTERRABLE
		"EXHUMAR": return Constants.Keyword.EXHUMAR
		"UNICA", "ÚNICA": return Constants.Keyword.UNICA
		"ERRANTE": return Constants.Keyword.ERRANTE
		"RETADOR": return Constants.Keyword.RETADOR
		_: return -1


# =============================================================================
# ACTUALIZACION VISUAL, DESGLOSES Y DEBUG (implementacion en ContinuousVisualSync.gd)
# =============================================================================
func update_all_card_visuals() -> void:
	_visual_sync.update_all_card_visuals()


func get_strength_breakdown(card: Node) -> Dictionary:
	return _visual_sync.get_strength_breakdown(card)


func get_cost_breakdown(card: Node) -> Dictionary:
	return _visual_sync.get_cost_breakdown(card)


func debug_print_modifiers() -> void:
	_visual_sync.debug_print_modifiers()


func debug_print_card_stats(card: Node) -> void:
	_visual_sync.debug_print_card_stats(card)
