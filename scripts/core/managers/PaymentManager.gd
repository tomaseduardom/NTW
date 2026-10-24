extends Node
## PaymentManager - Gestión de Costes y Pagos (DAR Sección 6.B)
##
## Maneja:
## - Cálculo de costes (base + modificadores)
## - Costes alternativos (Exhumar, sacrificio, etc.)
## - Scanner de Cementerio para cartas con Exhumar
## - Interfaz de selección de pago

# =============================================================================
# SEÑALES
# =============================================================================
signal payment_requested(card_data: Dictionary, cost_info: Dictionary)
signal payment_completed(card_data: Dictionary, method: String, amount_paid: int)
signal payment_cancelled(card_data: Dictionary, reason: String)
signal payment_failed(card_data: Dictionary, reason: String)

## Exhumar
signal exhumar_cards_available(player_id: int, cards: Array)
signal exhumar_card_selected(card_data: Dictionary, player_id: int)
signal exhumar_payment_confirmed(card_data: Dictionary, player_id: int)

## Coste Variable X
signal x_value_requested(card_data: Dictionary, max_value: int)
signal x_value_selected(card_data: Dictionary, x_value: int)
signal x_value_cancelled(card_data: Dictionary)

## UI
signal payment_ui_opened(options: Array)
signal payment_ui_closed

# =============================================================================
# ENUMS
# =============================================================================
enum PaymentMethod {
	NORMAL,           # Pago normal con Oros
	EXHUMAR,          # Desde Cementerio
	SACRIFICE,        # Sacrificar carta
	DISCARD,          # Descartar cartas
	LIFE,             # Pagar vida/daño a Castillo
	FREE,             # Sin coste
	ALTERNATIVE,      # Coste alternativo definido en carta
	VARIABLE_X        # Coste variable (X)
}

enum PaymentState {
	IDLE,
	AWAITING_SELECTION,    # Esperando que jugador elija método
	AWAITING_X_INPUT,      # Esperando valor de X
	AWAITING_PAYMENT,      # Esperando que pague
	PROCESSING,            # Procesando pago
	COMPLETED,
	CANCELLED
}

# =============================================================================
# ESTADO
# =============================================================================
var _state: PaymentState = PaymentState.IDLE
var _current_card: Dictionary = {}
var _current_player_id: int = -1
var _current_cost_info: Dictionary = {}
var _selected_method: PaymentMethod = PaymentMethod.NORMAL

## Módulos extraídos (Fase 4 de reestructuración)
var _cost_modifiers_mod: CostModifiers
var _exhumar: ExhumarSystem
var _x_cost: XCostSelector
var _validation: PaymentValidation
var _payment_ui: PaymentUI

# =============================================================================
# UI REFERENCES
# =============================================================================
var _payment_popup: Window = null

# =============================================================================
# MODIFICADORES DE COSTE (DAR Sección 6.B)
# =============================================================================
## Modificadores al COSTE IMPRESO [{source, modifier, condition, allow_zero}].
## modifier negativo = "reduce su coste en N" (piso 1 salvo allow_zero=true);
## modifier positivo = "aumenta su coste en N" (sin techo).
var cost_modifiers: Array = []
## "Jugar por X Oros menos" [{source, reduction, condition}] — descuento
## sobre lo que se PAGA, no toca el coste impreso. Sin piso, puede llegar a 0.
var oros_menos_modifiers: Array = []
## "Cuesta X Oro(s) adicional(es)" para pagar [{source, increase, condition}]
## — inverso de oros_menos: sube lo pagado sin tocar el coste impreso.
var oros_mas_modifiers: Array = []

## "Esa carta cuesta un Oro adicional el PRÓXIMO turno", por NOMBRE (Tesoro de los Césares).
## Registro aparte de oros_mas_modifiers, que se vacía en cada turn_started: este arranca recién el
## turno siguiente y dura ese turno. {nombre_lower: número_de_turno}.
var _named_surcharge_next_turn: Dictionary = {}

# =============================================================================
# TRACKING DE ORO GASTADO EN EL TURNO
# =============================================================================
## Acumulado de oro pagado en el turno actual (se resetea en cada nuevo turno)
var oro_gastado_este_turno: int = 0


func _ready() -> void:
	_cost_modifiers_mod = CostModifiers.new()
	_cost_modifiers_mod.setup(self)
	_exhumar = ExhumarSystem.new()
	_exhumar.setup(self)
	_x_cost = XCostSelector.new()
	_x_cost.setup(self)
	_validation = PaymentValidation.new()
	_validation.setup(self)
	_payment_ui = PaymentUI.new()
	_payment_ui.setup(self)

	call_deferred("_connect_signals")
	_x_cost.call_deferred("_setup_x_selector")
	print("[PaymentManager] Inicializado")


func _on_turn_started_clear_modifiers(_player_id: int, _turn_num: int) -> void:
	cost_modifiers.clear()
	oros_menos_modifiers.clear()
	oros_mas_modifiers.clear()
	oro_gastado_este_turno = 0
	# Los recargos diferidos por nombre (Tesoro de los Césares) no se
	# limpian aquí — _get_named_surcharge_next_turn() se auto-expira sola
	# comparando contra GameManager.turn_serial. Pero si uno de esos
	# recargos recién arranca o recién expira justo este turno, la insignia
	# de coste de la carta en mano (si la tienes) no se enteraría hasta el
	# próximo refresh puntual — se refresca toda la mano aquí para no
	# depender de que algo más la dispare.
	refresh_all_hand_cost_badges()


func refresh_all_hand_cost_badges() -> void:
	"""Refresca la insignia de coste (Card.refresh_cost_badge) de todas las cartas en tu mano — llamar
	después de cualquier cambio que pueda afectar el coste de una carta ajena a ella misma: un
	modificador nuevo, uno que se limpia, o un recargo diferido que arranca/expira al cambiar de
	turno."""
	var main := get_node_or_null("/root/Main")
	if not main or not main.player_hand:
		return
	for c in main.player_hand.cards:
		if is_instance_valid(c) and c.has_method("refresh_cost_badge"):
			c.refresh_cost_badge()


func puede_jugar_carta(card: Node, player_id: int = 0) -> bool:
	"""Valida si el jugador puede pagar la carta considerando lo ya gastado este turno.
	Cartas de coste 0 siempre se permiten si hay prioridad.
	Returns: true si puede jugarla, false si no tiene oro suficiente."""
	var coste = calcular_coste_real(card)

	# Coste 0 → siempre jugable (Talismanes sin coste, etc.)
	if coste <= 0:
		return true

	var main = get_node_or_null("/root/Main")
	if not main:
		return false

	# Oro físico disponible en reserva ahora mismo
	var oro_reserva: int = GameState.get_oro_reserva(player_id)
	if main._gold_manager:  # gokin: Oros que solo pagan cartas de coste 3 o más
		oro_reserva -= main._gold_manager.unusable_physical_golds(int(card.get("card_cost")) if card.get("card_cost") != null else -1, player_id)

	# Oro Virtual (genérico + restringido), por jugador (arquitectura.md §33). Vive en
	# main._gold_manager (oros_virtuales/restricted_gold_pools), no en Main.
	var oros_virtuales: int = 0
	var oro_restringido: int = 0
	if main._gold_manager:
		oros_virtuales = main._gold_manager.oros_virtuales.get(player_id, 0)
		var card_type: int = card.get("card_type") if card.get("card_type") != null else -1
		var card_race: String = str(card.get("card_raza")) if card.get("card_raza") != null else ""
		var card_cost: int = card.get("card_cost") if card.get("card_cost") != null else -1
		oro_restringido = main._gold_manager._restricted_gold_available_for(card_type, card_race, card_cost, player_id)

	var disponible = oro_reserva + oros_virtuales + oro_restringido
	return coste <= disponible


func registrar_pago(amount: int) -> void:
	"""Registra un pago completado en el tracker del turno."""
	if amount > 0:
		oro_gastado_este_turno += amount


func calcular_coste_real(card: Node) -> int:
	"""Calcula el coste real de una carta aplicando DAR 6.B. Dos familias de
	efecto, independientes entre sí:

	A. COSTE IMPRESO (cost_modifiers) — cambia el número base de la carta.
	   'Reduce su coste en N' tiene piso 1 salvo que el efecto indique
	   explícitamente 'hasta un mínimo de 0' (allow_zero=true al agregarlo).
	   'Aumenta su coste en N' no tiene techo.
	B. SOLO PARA PAGAR (oros_menos_modifiers / oros_mas_modifiers) — cambian
	   lo que se paga sin tocar el coste impreso de la carta. 'Jugar por X
	   Oros menos' y 'cuesta X Oro(s) adicional(es)' no tienen piso propio
	   (el piso final de 0 es solo para que el pago nunca sea negativo).
	"""
	if not is_instance_valid(card):
		return 0

	var coste_base: int = 0
	if card.get("card_cost") != null:
		coste_base = int(card.get("card_cost"))

	var coste_mod = coste_base
	var floor_impreso = 1
	for mod in cost_modifiers:
		if _modifier_applies(mod, card):
			coste_mod += mod.modifier
			if mod.modifier < 0 and mod.get("allow_zero", false):
				floor_impreso = 0
	if _first_ally_discount_applies(card):
		coste_mod -= 1
	# fusil patriota: "los siguientes dos Aliados de coste 2 o más que juegues en este turno reducen su coste en un Oro".
	if card.get("card_type") == Constants.CardType.ALIADO and coste_base >= 2:
		var fp_pid: int = int(card.owner_id) if card.get("owner_id") != null else 0
		var fp: Dictionary = RuleState.turn_data("fusil_patriota:%d" % fp_pid)
		if not fp.is_empty() and RuleState.count("ally2_played", fp_pid) - int(fp.get("base", 0)) < 2:
			coste_mod -= 1
	if coste_base > 0:
		coste_mod = maxi(coste_mod, floor_impreso)

	var oros_menos_total = 0
	for red in oros_menos_modifiers:
		if _modifier_applies(red, card):
			oros_menos_total += red.reduction

	var oros_mas_total = 0
	var payer: int = int(card.owner_id) if card.get("owner_id") != null else 0
	for inc in oros_mas_modifiers:
		if _modifier_applies(inc, card):
			var src = inc.get("source")
			var src_pid: int = int(src.controller_id) if src is Node and is_instance_valid(src) and src.get("controller_id") != null else -1
			if not EffectController.opp_cost_waived(payer, src_pid):  # costes adicionales (DAR abril 2026)
				oros_mas_total += inc.increase

	var card_name_for_surcharge: String = str(card.get("card_name")) if card.get("card_name") != null else ""
	if not card_name_for_surcharge.is_empty():
		oros_mas_total += _get_named_surcharge_next_turn(card_name_for_surcharge)

	oros_mas_total += _static_type_and_cheap_surcharge(card)
	if not _next_card_surcharge.is_empty() and card.get("card_type") != Constants.CardType.ORO \
			and _next_card_surcharge.get(payer, false) and not EffectController.opp_cost_waived(payer, 1 - payer):  # fuma kotaro
		oros_mas_total += 1

	oros_menos_total += _self_scaling_oro_discount(card)
	oros_menos_total += _conditional_boolean_discount(card)

	return maxi(coste_mod - oros_menos_total + oros_mas_total, 0)


func _self_scaling_oro_discount(card: Node) -> int:
	"""'...cuesta un Oro menos por cada Oro que controles' (Aaru) — descuento intrínseco de ESTA carta
	que escala con el propio estado del tablero de su controlador (Reserva + Oro Pagado), no un
	modificador registrado por un efecto externo como el resto de oros_menos_modifiers. Se detecta
	por texto y se recalcula fresco cada vez (no se cachea: el conteo de Oro puede cambiar entre
	llamadas del mismo turno)."""
	if card.get("card_data") == null:
		return 0
	var habilidad: String = str(card.card_data.get("habilidad", "")).to_lower()
	# "Reduce su coste en un Oro por cada Oro que controles" (Piruquina): mismo concepto que Aaru. El
	# texto dice "hasta un mínimo de 1", pero el piso de calcular_coste_real() es 0 (maxi(..., 0),
	# compartido con oros_menos_modifiers): desviación menor conocida.
	if not ("cuesta un oro menos por cada oro que controles" in habilidad
			or "reduce su coste en un oro por cada oro que controles" in habilidad):
		return 0
	var controller_id: int = card.get("controller_id") if card.get("controller_id") != null else 0
	return GameState.get_oro_total(controller_id)


func _conditional_boolean_discount(card: Node) -> int:
	"""Descuentos intrínsecos de 1 Oro condicionados a un booleano del tablero (0 o 1, a diferencia de
	_self_scaling_oro_discount()). Lista chica y explícita. De Cetro Demoniaco solo se evalúa la
	mitad "controlas": no hay registro de "jugué un Arma este turno"."""
	if card.get("card_data") == null:
		return 0
	var habilidad: String = str(card.card_data.get("habilidad", "")).to_lower()
	var controller_id: int = card.get("controller_id") if card.get("controller_id") != null else 0
	var main := get_node_or_null("/root/Main")
	if not main:
		return 0

	# "Reduce su coste en un Oro si controlas o jugaste este turno Armas o
	# a Lucifer" (Cetro Demoniaco) — solo la mitad 'controlas Armas o a
	# Lucifer'.
	if "reduce su coste en un oro si controlas o jugaste este turno armas o a lucifer" in habilidad:
		var fields_a: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo, main.player_gold] \
			if controller_id == 0 else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo, main.opponent_gold]
		for field in fields_a:
			if not field:
				continue
			for c in field.get_children():
				if not is_instance_valid(c):
					continue
				if c.get("card_type") == Constants.CardType.ARMA:
					return 1
				if str(c.get("card_name")).to_lower() == "lucifer":
					return 1
		return 0

	# "Reduce su coste en un Oro si controlas Armas" (sable corto): las Armas son hijas de su portador,
	# así que se revisa 'equipped_weapons' de cada Aliado.
	if "reduce su coste en un oro si controlas armas" in habilidad:
		var fields_sc: Array = [main.player_field, main.player_linea_ataque, main.player_linea_apoyo] \
			if controller_id == 0 else [main.opponent_field, main.opponent_linea_ataque, main.opponent_linea_apoyo]
		for field in fields_sc:
			if not field:
				continue
			for c in field.get_children():
				if is_instance_valid(c):
					var w = c.get("equipped_weapons")
					if w is Array and not w.is_empty():
						return 1
		return 0

	# "Si controlas Dragones reduce su coste en un Oro" (Azi Raoiota).
	if "si controlas dragones reduce su coste en un oro" in habilidad:
		var fields_b: Array = [main.player_field, main.player_linea_ataque] if controller_id == 0 \
			else [main.opponent_field, main.opponent_linea_ataque]
		for field in fields_b:
			if not field:
				continue
			for c in field.get_children():
				if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO \
						and "drag" in str(c.get("card_raza")).to_lower():
					return 1
		return 0

	# "Si no controlas Aliados de coste 1 o menos, reduce su coste en un Oro" (Jabberwocky). Se mira el
	# coste BASE (card_cost): usar calcular_coste_real() entra en recursión infinita si el Aliado
	# revisado depende de este mismo chequeo.
	if "si no controlas aliados de coste 1 o menos, reduce su coste en un oro" in habilidad:
		var fields_c: Array = [main.player_field, main.player_linea_ataque] if controller_id == 0 \
			else [main.opponent_field, main.opponent_linea_ataque]
		for field in fields_c:
			if not field:
				continue
			for c in field.get_children():
				if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO \
						and c.get("card_cost") != null and int(c.card_cost) <= 1:
					return 0
		return 1

	return 0


func add_named_surcharge_next_turn(card_name: String, target_turn: int) -> void:
	"""Registra que 'card_name' cuesta 1 Oro adicional durante target_turn (Tesoro de los Césares —
	quien lo registra ya calculó target_turn como GameManager.turn_serial + 1 al activar la
	habilidad)."""
	if card_name.is_empty():
		return
	_named_surcharge_next_turn[card_name.to_lower()] = target_turn


## fuma kotaro: "la próxima carta que juegue tu oponente cuesta un Oro adicional". {jugador: true}
## hasta que ese jugador juegue una carta (consume_next_card_surcharge, desde GoldManager).
var _next_card_surcharge: Dictionary = {}


func add_next_card_surcharge(player_id: int) -> void:
	_next_card_surcharge[player_id] = true
	refresh_all_hand_cost_badges()


## plaza de armas - sp: "Las cartas de ese tipo cuestan un Oro adicional" (el tipo nombrado queda en la meta
## "named_type" de cada plaza en juego). argos: "hasta tu próximo turno, la primera carta de coste 1 o menos
## que ponga en juego cada jugador en cada turno, cuesta un Oro adicional" (RuleState "argos_tax" y el
## contador "cheap_put" que suma GoldManager._trigger_enter_play()).
func _static_type_and_cheap_surcharge(card: Node) -> int:
	var card_type = card.get("card_type")
	if card_type == null or card_type == Constants.CardType.ORO:
		return 0
	var n := 0
	var main = get_node_or_null("/root/Main")
	if main:
		var CardQuery = load("res://scripts/core/effects/mechanics/CardQuery.gd")
		for pid in [0, 1]:
			for plaza in CardQuery.cards_in_play_with(pid, "nombra un tipo de carta que no sea oro ni aliado. las cartas de ese tipo cuestan un oro adicional"):
				if int(plaza.get_meta("named_type", -1)) == int(card_type) \
						and not EffectController.opp_cost_waived(int(card.owner_id) if card.get("owner_id") != null else 0, pid):
					n += 1
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else 0
	# Costes adicionales que puso el rival: no los paga un jugador que no puede ser afectado (DAR abril 2026).
	var tax := func(key: String) -> bool:
		return RuleState.active(key, owner) and not EffectController.rule_cost_waived(key, owner)
	# Amuleto de Serpiente: "jugar Talismanes cuesta un Oro adicional si ese jugador ha jugado Talismanes en
	# el turno".
	if card_type == Constants.CardType.TALISMAN and tax.call("talisman_repeat_tax") \
			and RuleState.count("played_type:%d" % Constants.CardType.TALISMAN, owner) >= 1:
		n += 1
	# Lady Mina Harker: "Jugar y/o utilizar habilidades de esa carta cuesta un Oro adicional hasta tu
	# próximo turno" (la parte de habilidades, en TriggerTollPatterns con "name_ability_toll").
	if tax.call("name_play_toll:" + str(card.get("card_name")).to_lower()):
		n += 1
	# castillo edo: "hasta tu próximo turno, a tu oponente le cuesta un Oro adicional jugar cartas del tipo que mostró".
	if tax.call("type_play_toll:%d" % int(card_type)):
		n += 1
	# No Más Magia: "Por el resto del juego, jugar Talismanes ... cuesta un Oro adicional".
	if card_type == Constants.CardType.TALISMAN and tax.call("no_mas_magia"):
		n += 1
	if card.get("card_cost") != null and int(card.card_cost) <= 1 and tax.call("argos_tax") \
			and RuleState.count("cheap_put", owner) == 0:
		n += 1
	return n


func consume_next_card_surcharge(player_id: int, card: Node) -> void:
	if _next_card_surcharge.get(player_id, false) and card.get("card_type") != Constants.CardType.ORO:
		_next_card_surcharge.erase(player_id)
		refresh_all_hand_cost_badges()


## urashima taro: "el primer Aliado que juegues en tu próximo turno reduce su coste en un Oro".
## {jugador: turn_serial de ese turno}. Vale mientras ese jugador no haya jugado un Aliado en el turno
## (TurnManager.ally_played_serial) y vence sola cuando el turno pasa.
var _first_ally_discount_turn: Dictionary = {}


func add_first_ally_discount(player_id: int, target_turn: int) -> void:
	_first_ally_discount_turn[player_id] = target_turn
	refresh_all_hand_cost_badges()


func _first_ally_discount_applies(card: Node) -> bool:
	if _first_ally_discount_turn.is_empty() or card.get("card_type") != Constants.CardType.ALIADO:
		return false
	var pid: int = int(card.owner_id) if card.get("owner_id") != null else 0
	if int(_first_ally_discount_turn.get(pid, -1)) != GameManager.turn_serial or GameManager.active_player_id != pid:
		return false
	return int(TurnManager.ally_played_serial.get(pid, -1)) != GameManager.turn_serial


func _get_named_surcharge_next_turn(card_name: String) -> int:
	"""Devuelve 1 si 'card_name' tiene un recargo vigente para el turno
	ACTUAL, 0 si todavía no llega ese turno o ya pasó (y en ese caso limpia
	la entrada vencida, auto-expira sin necesidad de un hook de turn_started
	aparte)."""
	var key := card_name.to_lower()
	if not _named_surcharge_next_turn.has(key):
		return 0
	var target_turn: int = _named_surcharge_next_turn[key]
	if not GameManager or GameManager.turn_serial > target_turn:
		_named_surcharge_next_turn.erase(key)
		return 0
	if GameManager.turn_serial < target_turn:
		return 0
	return 1


func _modifier_applies(mod: Dictionary, card: Node) -> bool:
	if not mod.has("condition") or mod.condition == null:
		return true
	if mod.condition is Callable and mod.condition.is_valid():
		return mod.condition.call(card)
	return false  # Tipo de condición desconocido — no aplicar


# =============================================================================
# MODIFICADORES DE COSTE (implementación en CostModifiers.gd)
# =============================================================================
func agregar_modificador_coste(source: Node, modifier: int, condition: Callable = Callable(), allow_zero: bool = false) -> void:
	_cost_modifiers_mod.agregar_modificador_coste(source, modifier, condition, allow_zero)


func remover_modificador_coste(source: Node) -> void:
	_cost_modifiers_mod.remover_modificador_coste(source)


func agregar_oros_menos(source: Node, reduction: int, condition: Callable = Callable()) -> void:
	_cost_modifiers_mod.agregar_oros_menos(source, reduction, condition)


func remover_oros_menos(source: Node) -> void:
	_cost_modifiers_mod.remover_oros_menos(source)


func agregar_oros_mas(source: Node, increase: int, condition: Callable = Callable()) -> void:
	_cost_modifiers_mod.agregar_oros_mas(source, increase, condition)


func remover_oros_mas(source: Node) -> void:
	_cost_modifiers_mod.remover_oros_mas(source)


func _connect_signals() -> void:
	# El caché de Exhumar se invalida con CardManager.zone_changed; la prioridad, con
	# PriorityManager.priority_changed.
	if not CardManager.zone_changed.is_connected(_exhumar._on_card_moved_to_zone):
		CardManager.zone_changed.connect(_exhumar._on_card_moved_to_zone)

	if not PriorityManager.priority_changed.is_connected(_exhumar._on_priority_given):
		PriorityManager.priority_changed.connect(_exhumar._on_priority_given)

	# Limpiar modificadores al inicio de cada turno. GameManager es el único conductor de turnos.
	if GameManager and GameManager.has_signal("turn_started"):
		if not GameManager.turn_started.is_connected(_on_turn_started_clear_modifiers):
			GameManager.turn_started.connect(_on_turn_started_clear_modifiers)


# =============================================================================
# EXHUMAR (implementación en ExhumarSystem.gd)
# =============================================================================
func scan_cemetery_for_exhumar(player_id: int) -> Array[Dictionary]:
	return _exhumar.scan_cemetery_for_exhumar(player_id)


func get_all_exhumar_cards() -> Dictionary:
	return _exhumar.get_all_exhumar_cards()


func mark_playable_exhumar_cards(player_id: int) -> void:
	_exhumar.mark_playable_exhumar_cards(player_id)


func show_exhumar_options(player_id: int) -> void:
	_exhumar.show_exhumar_options(player_id)


func has_exhumar_available(player_id: int) -> bool:
	return _exhumar.has_exhumar_available(player_id)


func invalidate_cache() -> void:
	_exhumar.invalidate_cache()


func card_has_exhumar(card_data: Dictionary, player_id: int = -1) -> bool:
	"""Expone el chequeo privado de ExhumarSystem — usado por ZoneViewerModule para marcar como
	clickeables las cartas del Cementerio que se pueden jugar via Exhumar. Respeta el silencio de
	Cementerio (Sable de Napoleón) — 'pierde su habilidad' incluye Exhumar."""
	if CardManager.is_cemetery_card_silenced(card_data):
		return false
	return _exhumar._card_has_exhumar(card_data, player_id)


func get_exhumar_cost(card_data: Dictionary) -> int:
	"""Coste de jugar esta carta via Exhumar (normalmente el coste base,
	salvo que la carta tenga un coste de Exhumar alternativo definido)."""
	return _exhumar._calculate_exhumar_cost(card_data, card_data.get("coste", 0))


func card_playable_from_exile(card_data: Dictionary) -> bool:
	"""'Puedes jugar(lo/la) desde/de tu Destierro' — p.ej. uriel, batallon de ovejas, cruzar el
	bosque) — usado por ZoneViewerModule para marcar como clickeables las cartas del Destierro
	propio jugables vía GoldManager.play_card_from_exile. Lista chica y explícita (mismo criterio
	que card_has_exhumar/_ability_is_hand_usable), no un permiso genérico por presencia de
	'Destierro' en el texto (esa palabra aparece en muchísimas habilidades sin relación con jugar
	desde ahí."""
	var text: String = str(card_data.get("habilidad", "")).to_lower()
	if "puedes jugarlo de tu destierro pagando su coste" in text:
		return true  # uriel
	if "puedes jugarlo de tu destierro reduciendo su coste en un oro" in text:
		# rafael: condicionado a controlar Sacerdotes
		if "si controlas sacerdotes" in text:
			var main = get_node_or_null("/root/Main")
			if not main:
				return false
			for field in [main.player_field, main.player_linea_ataque, main.player_linea_apoyo]:
				if not field:
					continue
				for c in field.get_children():
					if c.get("card_type") == Constants.CardType.ALIADO and str(c.get("card_raza")).to_lower() == "sacerdote":
						return true
			return false
		return true
	if "puedes jugarlo desde tu destierro" in text:
		# batallon de ovejas: condicionado a mano de 4 o menos
		if "cuatro cartas o menos en tu mano" in text:
			var main = get_node_or_null("/root/Main")
			if main and main.player_hand:
				return main.player_hand.cards.size() <= 4
			return false
		return true
	if "puedes jugar esta carta desde tu destierro" in text:
		return true  # cruzar el bosque
	return false


func get_exile_play_discount(card_data: Dictionary) -> int:
	"""Descuento fijo al jugar desde el Destierro (p.ej. rafael: 'reduciendo su coste en un Oro') — 0
	si no aplica (la mayoría, p.ej. uriel/batallon de ovejas pagan el coste completo)."""
	var text: String = str(card_data.get("habilidad", "")).to_lower()
	if "puedes jugarlo de tu destierro reduciendo su coste en un oro" in text:
		return 1
	return 0


# =============================================================================
# VALIDACIÓN DE CARTAS ÚNICAS Y CONSULTAS DE ORO — ver PaymentValidation.gd ("módulos gordos":
# _card_is_unique/_validate_unique_card/_check_unique_in_play/_check_unique_in_stack/_get_cards_in_zone/_get_player_cemetery/_get_player_available_gold
# se movieron ahí, acceso vía _validation. Se quedaron aquí porque son consultas sin estado — nada
# que ver con _current_card/_payment_popup/etc., que sí están entrelazados con
# ExhumarSystem.gd/XCostSelector.gd como blackboard compartido.)


# =============================================================================
# COSTE VARIABLE X (implementación en XCostSelector.gd)
# =============================================================================
func has_variable_x_cost(card_data: Dictionary) -> bool:
	return _x_cost.has_variable_x_cost(card_data)


func parse_x_cost(card_data: Dictionary) -> Dictionary:
	return _x_cost.parse_x_cost(card_data)


func request_x_value_input(card_data: Dictionary, player_id: int, callback: Callable = Callable()) -> void:
	_x_cost.request_x_value_input(card_data, player_id, callback)


func get_x_value() -> int:
	return _x_cost.get_x_value()


func get_x_total_cost() -> int:
	return _x_cost.get_x_total_cost()


# =============================================================================
# HELPER FUNCTIONS - Log y Player Name
# =============================================================================
func _log_action(action_type: String, message: String, data: Dictionary = {}) -> void:
	"""Registra una acción en el CombatLog"""
	CombatLog.add_entry(action_type, message, data)


func _get_player_name(player_id: int) -> String:
	"""Nombre del jugador para logs. GameManager.players no tiene nombre legible: se usa un nombre
	genérico."""
	return "Jugador %d" % (player_id + 1)
