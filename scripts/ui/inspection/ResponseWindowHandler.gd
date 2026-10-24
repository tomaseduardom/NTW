extends RefCounted
class_name ResponseWindowHandler
## ResponseWindowHandler — overlays de ventana de respuesta: Paso D genérico
## (ActionPipeline.step_d_waiting, para cualquier objeto de la Pila) y Signo Amarillo
## (_offer_signo_amarillo_for_step_d()). Opera sobre CardInspectionLayer vía _inspector (y sobre
## Main vía _inspector._main).

var _inspector: CardInspectionLayer


func setup(inspector: CardInspectionLayer) -> void:
	_inspector = inspector


func _on_step_d_waiting(stack_obj: Dictionary, priority_player: int) -> void:
	# Pila de Respuesta Universal (docs/plans/2026-09-09-pila-respuesta-universal-design.md): la
	# ventana puede abrirse para cualquiera de los dos jugadores. Si le toca al bot, intenta responder
	# (_bot_pass_after()) y si no, pasa por el camino real de PriorityManager, para no romper la
	# secuencia de "ambos pasan" que espera ActionPipeline.
	if priority_player != 0:
		# Un jugador Remoto real decide por su cuenta (lo maneja
		# PhaseFlowController._on_priority_changed_bot_autopass →
		# RemotePlayerController.on_priority_received) — sin este return había dos caminos pasando por él
		# a la vez.
		if _inspector._main._easy_bot is RemotePlayerController:
			return
		# Se captura la generación de ESTA ventana (ver PriorityManager._window_generation) — mismo motivo
		# que PhaseFlowController._human_pass_after, ver ese comentario.
		_bot_pass_after(0.15, PriorityManager._window_generation)  # corto: las cadenas de varias cartas no acumulan demora
		return

	# El botón único ¿Paso?/Atacar del HUD (GameHUDModule) ya se pone visible y brilla solo apenas la
	# prioridad es tuya, y PhaseFlowController._on_priority_changed_glow ya se encarga del auto-pase
	# "no hay nada que decidir" — dejó de hacer falta un panel propio aquí solo para pasar. Lo único
	# que sigue necesitando UI propia es la oferta de Signo Amarillo (cancelar convirtiendo un Oro): es
	# una decisión real, así que se ofrece como diálogo reactivo, y suprime ese auto-pase mientras
	# espera tu click (ver _offer_signo_amarillo_for_step_d).
	if _qualifies_for_signo_amarillo(stack_obj):
		_offer_signo_amarillo_for_step_d(stack_obj)


func _offer_signo_amarillo_for_step_d(stack_obj: Dictionary) -> void:
	var signo_card := _find_signo_amarillo_in_reserve(0)
	if not signo_card:
		return
	# Suprime el auto-pase "no hay nada que decidir" mientras este diálogo espera un click
	# (PriorityManager.suppress_human_autopass).
	# 'scheduled_for_generation' (como _bot_pass_after()): si se abrió una ventana NUEVA mientras se
	# esperaba (dos Signo Amarillo seguidos), esa ventana pudo poner suppress_human_autopass = true
	# para su propio diálogo; no se resetea por debajo.
	var scheduled_for_generation: int = PriorityManager._window_generation
	PriorityManager.suppress_human_autopass = true
	var ability_name: String = stack_obj.get("name", "esta habilidad")
	var use_it: bool = await SelectionManager.await_two_choice(
		_inspector._main,
		"¿Convertir %s en un Oro sin habilidad para cancelar %s?" % [str(signo_card.card_name), ability_name],
		"Sí, cancelar", "No")
	if PriorityManager._window_generation == scheduled_for_generation:
		PriorityManager.suppress_human_autopass = false
	if not use_it:
		return
	if not PriorityManager.priority_window_active:
		return  # la ventana ya se cerró mientras decidías (p.ej. pasaste con el botón)
	signo_card.is_converted = true
	ActionPipeline.cancel_stack_object(stack_obj.get("id", -1))
	if PriorityManager.priority_window_active:
		PriorityManager.pass_priority()


func _bot_pass_after(delay: float, scheduled_for_generation: int) -> void:
	"""Capa 2 de la Pila de Respuesta Universal: antes de pasar, el bot intenta responder con una
	habilidad activada propia (EasyBotController.try_respond_with_activated_ability()). La
	Prevención va aparte (EffectController.offer_prevention_for_player()). Si usó algo, el objeto
	ya está en el tope de ActionPipeline y StackStepResolver lo ve como respuesta: no se pasa. Si
	no, pasa por PriorityManager con un pequeño delay, solo para que no se sienta instantáneo.
	'scheduled_for_generation' (PriorityManager._window_generation): si la ventana para la que se
	programó el timer ya cerró y se abrió otra, no se toca la nueva."""
	await _inspector.get_tree().create_timer(delay).timeout
	if PriorityManager._window_generation != scheduled_for_generation:
		return
	if not PriorityManager.priority_window_active:
		return
	if _inspector._main._easy_bot and await _inspector._main._easy_bot.try_respond_with_activated_ability():
		return
	if PriorityManager._window_generation == scheduled_for_generation and PriorityManager.priority_window_active:
		PriorityManager.pass_priority()
		await _inspector.get_tree().create_timer(0.15).timeout
		if PriorityManager._window_generation == scheduled_for_generation and PriorityManager.priority_window_active:
			PriorityManager.pass_priority()


func _qualifies_for_signo_amarillo(stack_obj: Dictionary) -> bool:
	"""¿La fuente de este objeto de la Pila es un Oro, o una carta fuera del juego
	(Mano/Destierro/Cementerio/Castillo)? Esas dos categorías son las que Signo Amarillo puede
	cancelar (texto real de la carta)."""
	var context: Dictionary = stack_obj.get("context", {})
	var source_data: Dictionary = context.get("source_card", stack_obj.get("card_data", {}))
	if source_data.get("tipo", -1) == Constants.CardType.ORO:
		return true
	var source_node = context.get("source_card_node")
	if source_node and is_instance_valid(source_node):
		var off_board_zones = [Constants.Zone.MANO, Constants.Zone.DESTIERRO, Constants.Zone.CEMENTERIO, Constants.Zone.CASTILLO]
		return source_node.get("current_zone") in off_board_zones
	return false


func _find_signo_amarillo_in_reserve(player_id: int) -> Node:
	"""Busca en la Reserva de Oro de player_id un Oro con el texto de Signo
	Amarillo que todavía no se haya convertido — detección por texto, no por
	nombre, para cubrir cualquier carta con el mismo patrón."""
	var container = _inspector._main.player_gold if player_id == 0 else _inspector._main.opponent_gold
	if not container:
		return null
	for c in container.get_children():
		if not is_instance_valid(c) or c.get("is_converted") == true:
			continue
		var ability_text: String = str(c.get("card_ability") if c.get("card_ability") != null else "")
		if "convertir este oro en un oro sin habilidad" in ability_text.to_lower():
			return c
	return null


func _on_trigger_waiting_for_responses(trigger: Dictionary, responding_player: int) -> void:
	"""Diálogo de respuesta para triggers de entrada de Oro / fuera del juego. Sin llamador:
	TriggerSystem.waiting_for_responses ya no se emite (§10.53); Signo Amarillo para triggers se
	ofrece por _offer_signo_amarillo_for_step_d(), que escucha ActionPipeline.step_d_waiting."""
	if responding_player != 0:
		return  # el bot no usa Signo Amarillo todavía
	var signo_card := _find_signo_amarillo_in_reserve(responding_player)
	if not signo_card:
		return
	var source_card: Node = trigger.get("card")
	var card_name: String = str(source_card.card_name) if source_card and is_instance_valid(source_card) else "esta habilidad"
	var use_it: bool = await SelectionManager.await_two_choice(
		_inspector._main,
		"¿Convertir %s en un Oro sin habilidad para cancelar %s?" % [str(signo_card.card_name), card_name],
		"Sí, cancelar", "No")
	if not TriggerSystem.awaiting_response:
		return  # ya se resolvió solo (timeout de 8s) mientras decidías
	if use_it:
		signo_card.is_converted = true
		TriggerSystem.cancel_current_trigger(signo_card)
	else:
		TriggerSystem.pass_response()
