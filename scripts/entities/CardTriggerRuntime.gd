extends RefCounted
class_name CardTriggerRuntime
## CardTriggerRuntime — triggers de una carta (DAR 7.2, 7.3, 7.4): parseo desde el texto de
## habilidad, condiciones, ejecución vía Callable y los hooks de entrar/salir de juego. Opera sobre
## el nodo Card vía _card. Card.gd reenvía los métodos que otros sistemas llaman sobre la carta
## (parse_triggers_from_ability, is_in_play, has_trigger, _trigger_conditions_met,
## _on_trigger_event, on_entered_play, on_left_play).
## Card.TRIGGER_KEYWORDS queda en Card.gd porque se accede de forma estática
## (Card.TRIGGER_KEYWORDS[...]).

var _card: Card

## Triggers parseados del texto de habilidad
var triggers: Array[Dictionary] = []

## Handlers de efectos personalizados por tipo de trigger
var effect_handlers: Dictionary = {}

var _triggers_connected: bool = false


func setup(card: Card) -> void:
	_card = card


func _connect_trigger_listeners() -> void:
	"""Inicializa el sistema de triggers de la carta
	Nota: TriggerSystem maneja la recolección global de eventos (DAR 7.4)
	La carta solo expone has_trigger() y _trigger_conditions_met()
	"""
	_triggers_connected = true


func parse_triggers_from_ability() -> void:
	"""Parsea el texto de habilidad para extraer triggers"""
	triggers.clear()

	if _card.card_ability.is_empty():
		return

	# "Puede atacar cuando entra en juego" (brujo mendigo, Guardia Real, Sir Galahad) es una regla, no un
	# disparador: la aplica KeywordManager. Sin quitarla, contaba como "cuando entra en juego".
	var ability_lower = _card.card_ability.to_lower().replace("puede atacar cuando entra en juego.", "") \
		.replace("puede atacar cuando entra en juego", "")
	# Lo que está entre comillas es la habilidad que la carta da o gana (colmillo arcano: "...en un Aliado con
	# la habilidad "Furia. Cuando ataca, ..."), no un disparador suyo.
	ability_lower = RegEx.create_from_string("[\"“”][^\"“”]*[\"“”]?").sub(ability_lower, "", true)

	for trigger_type in Card.TRIGGER_KEYWORDS:
		var keywords: Array = Card.TRIGGER_KEYWORDS[trigger_type]
		for keyword in keywords:
			if ability_lower.contains(keyword):
				triggers.append({
					"type": trigger_type,
					"keyword": keyword,
					"ability_text": _card.card_ability
				})
				# Solo un trigger por tipo
				break
	# Nota: los Talismanes NO se resuelven por aquí — no "disparan" nada (DAR Sección 7.4 es para
	# habilidades disparadas de permanentes). Su texto se resuelve directo al jugarlos, ver
	# TriggerSystem.resolve_talisman / GoldManager._trigger_enter_play.


func is_in_play() -> bool:
	"""Verifica si la carta está en una zona de juego"""
	return _card.current_zone in Constants.ZONES_IN_PLAY


func has_trigger(trigger_type: String) -> bool:
	"""Verifica si la carta tiene un trigger específico"""
	for trigger in triggers:
		if trigger.type == trigger_type:
			return true
	return false


func _check_and_activate_trigger(trigger_type: String, event_data: Dictionary) -> void:
	"""Verifica si el trigger aplica y lo registra con TriggerSystem"""
	# Solo activar si está en juego
	if not is_in_play():
		return

	# Verificar si tiene el trigger
	if not has_trigger(trigger_type):
		return

	# Verificar condiciones adicionales (ej: "tu" vs "oponente")
	if not _trigger_conditions_met(trigger_type, event_data):
		return

	print("[Card] Trigger detectado: %s en %s" % [trigger_type, _card.card_name])

	# Registrar con TriggerSystem para gestión de cola (DAR 7.4)
	TriggerSystem.register_trigger(_card, trigger_type, event_data)

	# También emitir señal local para conexiones directas
	_card.emit_signal("trigger_activated", _card, trigger_type, event_data)


func _trigger_conditions_met(trigger_type: String, event_data: Dictionary) -> bool:
	"""Verifica condiciones adicionales del trigger"""
	var ability_lower = _card.card_ability.to_lower()

	# Verificar si es "tu" o del "oponente"
	var event_player = event_data.get("player_id", -1)

	if ability_lower.contains("cuando tú") or ability_lower.contains("cuando robes"):
		# Solo se activa si es nuestro evento
		if event_player != _card.controller_id:
			return false

	if ability_lower.contains("cuando tu oponente") or ability_lower.contains("cuando el oponente"):
		# Solo se activa si es evento del oponente
		if event_player == _card.controller_id:
			return false

	# Verificar "otro aliado" (no esta carta)
	if trigger_type == "on_ally_enters" or trigger_type == "on_ally_dies":
		var event_card = event_data.get("card", null)
		if event_card == _card:
			return false

	return true


func register_effect_handler(trigger_type: String, handler: Callable) -> void:
	"""Registra un handler personalizado para un tipo de trigger
	Permite definir efectos específicos por carta
	"""
	effect_handlers[trigger_type] = handler


func _on_trigger_event(trigger_type: String, event_data: Dictionary) -> Dictionary:
	"""Handler principal llamado por TriggerSystem cuando se resuelve un trigger
	Usa Callable para ejecutar el efecto específico de la carta
	Resuelve 'en medida de lo posible' (DAR Sección 8)
	"""
	var result = {
		"success": true,
		"partial": false,
		"effects_applied": []
	}

	# Buscar handler específico registrado
	if effect_handlers.has(trigger_type):
		var handler: Callable = effect_handlers[trigger_type]
		if handler.is_valid():
			var handler_result = await handler.call(event_data)
			if handler_result is Dictionary:
				result.merge(handler_result, true)
			return result

	# Sin handler específico: no se escanea el texto completo buscando palabras clave (con varias
	# habilidades en el bloque, p.ej. Tyet, se tomaba la frase equivocada).
	# TriggerSystem._execute_trigger_effect() aísla la oración correcta y la resuelve cuando este
	# resultado no aplicó nada.
	result["no_handler"] = true
	return result


func on_entered_play() -> void:
	"""Llamado cuando la carta entra al juego
	Vincula la carta al TriggerSystem con Callable
	"""
	# Parsear triggers de la habilidad
	parse_triggers_from_ability()

	# Registrar con TriggerSystem
	TriggerSystem.bind_card_to_triggers(_card)

	print("[Card] %s entró al juego con %d triggers" % [_card.card_name, triggers.size()])


func on_left_play() -> void:
	"""Llamado cuando la carta deja el juego
	Limpia efectos continuos y handlers
	"""
	# Desregistrar efectos continuos
	TriggerSystem.unregister_continuous_effect(_card)

	effect_handlers.clear()
	# Este mensaje solo duplicaba lo que ya informa EffectController ("X fue destruida"/"X resuelve su
	# efecto y va al Cementerio") — 3 líneas distintas para el mismo evento de salida de juego. Se
	# mantiene gateado para depuración profunda.
	if Constants.VERBOSE_DIAG_LOGS:
		print("[Card] %s dejó el juego" % _card.card_name)
