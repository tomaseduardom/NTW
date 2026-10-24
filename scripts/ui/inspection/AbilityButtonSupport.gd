extends RefCounted
## AbilityButtonSupport — validación de habilidades ACTIVADAS y ciclo de vida del botón superpuesto
## (creación, activación vía ActionPipeline, brillo de "habilidad en la pila").
## CardInspectionLayer.gd es el único punto de entrada (_button_support, montado en setup()).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

var _inspector: CardInspectionLayer
var _glowing_cards: Dictionary = {}


func setup(inspector: CardInspectionLayer) -> void:
	_inspector = inspector


func _tamales_ability_restriction_reason(source_card: Node) -> String:
	"""Wrapper — la lógica real vive en ContinuousEffectManager.tamales_ability_restriction_reason
	(movida ahí para compartirla con TriggerSystem._check_trigger_conditions, que necesita el mismo
	chequeo para 'ni disparar')."""
	return ContinuousEffectManager.tamales_ability_restriction_reason(source_card)


func _is_annul_or_cancel_ability(ability_raw_text: String) -> bool:
	"""¿Esta habilidad ACTIVADA (raw_text ya aislado por parse_abilities()) es de Anular/Cancelar? Es
	la única categoría que se ofrece en el turno rival (arquitectura.md §10.11 caso 4). Mismas
	palabras que GoldManagerRestrictions._is_response_only_ability_text(), pero con 'contains' (el
	costo suele ir antes de "anular" en la misma oración, p.ej. Akari: "Puedes Desterrarlo para
	Anular..."). Excluye frases de protección ("no puede ser anulada/cancelada", p.ej. Padre de la
	Patria)."""
	var lower := ability_raw_text.to_lower()
	if "no puede ser anulad" in lower or "no puede ser cancelad" in lower:
		return false
	return "anula" in lower or "cancela" in lower


func _is_responding_to_opponent_action() -> bool:
	"""¿Hay una ventana de respuesta real (Paso D, PriorityContext.RESPONSE_WINDOW): se reacciona a
	algo puntual en la Pila (carta jugada o habilidad, §10.53)? Si no, se actúa proactivamente (tu
	Vigilia, o la palabra en Guerra de Talismanes sin responder a nada).
	Cartas como Bernardo O'Higgins o Lanza Argenta eligen la rama sola según esto: proactivo →
	Desterrar/Robar; respondiendo a algo del rival → Cancelar. Se mira el contexto de prioridad, no
	de quién es el turno."""
	return PriorityManager.priority_window_active \
		and PriorityManager.current_priority_context == PriorityManager.PriorityContext.RESPONSE_WINDOW


func _validate_ability(ability: Dictionary, source_card: Node, player_id: int = 0) -> Dictionary:
	"""Valida si una habilidad activada puede ejecutarse ahora: prioridad, Oro disponible, cartas en
	mano, carta girada, ActionPipeline. 'player_id': quién la activaría (el Remoto usa la misma
	validación que los botones del Anfitrión)."""
	if PriorityManager.priority_window_active and not PriorityManager.can_act(player_id):
		return {"can": false, "reason": "Sin prioridad ahora"}

	# Silenciada (por instancia o por nombre, KeywordManager.is_silenced()) = pierde todas sus
	# habilidades, activadas incluidas.
	if KeywordManager.is_silenced(source_card):
		return {"can": false, "reason": "Sin habilidad (silenciada)"}
	# anillo de tierra: una carta más o una habilidad más por el turno.
	if not GoldManager.one_more_action_left(player_id):
		return {"can": false, "reason": "Ya no puedes utilizar más habilidades este turno"}

	# Restricción de fase por texto propio de la carta (p.ej. Espada de O'Higgins: "En tu Vigilia, una
	# vez por turno, puedes..."). _build_ability_buttons ya permite el botón en Vigilia O en ventana de
	# prioridad (genérico, para cartas sin restricción de fase) — esto cierra el caso más estricto de
	# una carta que solo se puede usar en su propia Vigilia, ni siquiera con prioridad abierta en otra
	# fase.
	var raw_lower: String = str(ability.get("raw_text", "")).to_lower()
	if "en tu vigilia" in raw_lower and GameManager.current_phase != Constants.Phase.VIGILIA:
		return {"can": false, "reason": "Solo en tu Vigilia"}
	if raw_lower.begins_with("en guerra de talismanes") and GameManager.current_phase != Constants.Phase.GUERRA_TALISMANES:
		return {"can": false, "reason": "Solo en Guerra de Talismanes"}  # kabutowari

	# "Una vez EN tu/su turno" (arquitectura.md §10.11) restringe CUÁNDO: solo en tu turno normal, no
	# en ventanas anidadas, aunque pueda Anular/Cancelar (p.ej. paladín bestiarium). "Una vez por
	# turno" genérico vale en cualquier ventana de prioridad de tu turno (Guerra de Talismanes
	# incluida).
	if ability.get("once_per_turn_own_turn_only", false) and PriorityManager.priority_window_active:
		return {"can": false, "reason": "Solo en tu turno (no en una ventana de prioridad)"}

	# 'Tu oponente sólo puede utilizar las habilidades de Oros y cartas de coste 2 o más si no controla
	# más copias de esa carta' (Tamales) — único choke point real de validación de habilidades
	# ACTIVADAS, así que basta un chequeo aquí para cubrir cualquier carta.
	var tamales_reason: String = _tamales_ability_restriction_reason(source_card)
	if not tamales_reason.is_empty():
		return {"can": false, "reason": tamales_reason}

	var cost_type   = ability.get("cost_type",   UniversalCardParser.CostType.NONE)
	var cost_amount = ability.get("cost_amount", 0)

	match cost_type:
		UniversalCardParser.CostType.GOLD:
			if _inspector._main._gold_manager:
				var available = _inspector._main._gold_manager.get_oro_disponible(player_id)
				if not _inspector._main._gold_manager.puede_pagar(cost_amount, -1, "", -1, player_id):
					return {"can": false, "reason": "Oro insuficiente (%d/%d)" % [available, cost_amount]}

		UniversalCardParser.CostType.DISCARD:
			var count: int = PlayerSideScript.hand_cards(_inspector._main, player_id).size()
			if count == 0:
				return {"can": false, "reason": "Mano vacía"}

		UniversalCardParser.CostType.TAP:
			if source_card.get("is_tapped") == true:
				return {"can": false, "reason": "Carta ya girada"}

		UniversalCardParser.CostType.ONCE_PER_TURN:
			# instance_id, NO card_data.id (corrección: card_data.id es el ID de la carta/impresión,
			# compartido por TODAS las copias en juego — con 2 Aho en juego, usar uno marcaba el cupo también
			# para el otro. Cada copia física necesita su propio cupo).
			var card_id: String = str(source_card.get_instance_id())
			var ability_idx: int = ability.get("ability_index", 0)
			var turn: int = GameManager.turn_serial
			if UniversalCardParser.turn_registry.is_exhausted(card_id, ability_idx, turn, int(ability.get("uses_per_turn", 1))):
				return {"can": false, "reason": "Ya usada este turno"}

	# Flag once_per_turn desde parse_abilities() (puede venir sin cost_type ONCE_PER_TURN)
	if ability.get("once_per_turn", false) and cost_type != UniversalCardParser.CostType.ONCE_PER_TURN:
		var card_id: String = str(source_card.get_instance_id())
		var ability_idx: int = ability.get("ability_index", 0)
		var turn: int = GameManager.turn_serial
		if UniversalCardParser.turn_registry.is_exhausted(card_id, ability_idx, turn, int(ability.get("uses_per_turn", 1))):
			return {"can": false, "reason": "Ya usada este turno"}

	# Verificación adicional con ActionPipeline — source_card_node en el context para que
	# can_activate_ability también use el instance_id, no el id compartido entre copias.
	var context = {"controller_id": player_id, "source_card_node": source_card}
	var check = ActionPipeline.can_activate_ability(source_card.card_data, ability, context)
	if not check.get("can", true):
		return {"can": false, "reason": check.get("reason", "No disponible")}

	return {"can": true, "reason": ""}


func _apply_corners(style: StyleBoxFlat, top: bool, bottom: bool, r: int = 4) -> void:
	style.corner_radius_top_left = r if top else 0
	style.corner_radius_top_right = r if top else 0
	style.corner_radius_bottom_left = r if bottom else 0
	style.corner_radius_bottom_right = r if bottom else 0


func _create_ability_overlay_button(
	ability: Dictionary,
	validation: Dictionary,
	corner_top: bool = true,
	corner_bottom: bool = true
) -> Button:
	"""Botón superpuesto sobre el párrafo de la carta donde está impresa esta habilidad. No dibuja
	texto (la carta ya lo muestra); un rectángulo celeste de bordes curvos marca siempre qué
	habilidad se puede activar y dónde clickear. Al pasar el mouse se resalta más y muestra costo y
	efecto como tooltip."""
	var cost_type   = ability.get("cost_type",   UniversalCardParser.CostType.NONE)
	var cost_amount = ability.get("cost_amount", 0)
	var effect_text = ability.get("effect_text", ability.get("raw_text", ""))

	var cost_label: String
	match cost_type:
		UniversalCardParser.CostType.GOLD:
			cost_label = "Paga %d Oro" % cost_amount
		UniversalCardParser.CostType.ONCE_PER_TURN:
			cost_label = "Una vez por turno"
		UniversalCardParser.CostType.DISCARD:
			cost_label = "Descarta una carta"
		UniversalCardParser.CostType.TAP:
			cost_label = "Gira esta carta"
		_:
			cost_label = ability.get("cost_text", "")

	var btn = Button.new()
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = ""

	# Opción 2 refinada: Solo bordes rúnicos finos, fondo 100% transparente para máxima legibilidad.
	# En reposo: fondo transparente (sin tintes que oscurezcan el pergamino), trazo fino de 1px bien definido.
	# En hover: el borde se ilumina en cian eléctrico y resplandor sutil.

	# Estilo normal: Fondo 100% transparente; marco rúnico celeste bien definido
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style_normal.set_border_width_all(1)
	style_normal.border_color = Color(0.18, 0.65, 0.95, 0.70)
	style_normal.shadow_size = 0
	style_normal.anti_aliasing = true
	_apply_corners(style_normal, corner_top, corner_bottom, 4)
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("focus", style_normal)

	# Estilo hover: Borde cian eléctrico luminoso y velo de luz ultra-sutil (no azul fuerte invasivo)
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.20, 0.65, 0.98, 0.08)
	style_hover.set_border_width_all(1)
	style_hover.border_color = Color(0.35, 0.92, 1.0, 1.0)
	style_hover.shadow_color = Color(0.15, 0.70, 1.0, 0.40)
	style_hover.shadow_size = 2
	style_hover.anti_aliasing = true
	_apply_corners(style_hover, corner_top, corner_bottom, 4)
	btn.add_theme_stylebox_override("hover", style_hover)

	# Estilo pressed: Destello celeste de confirmación al hacer clic
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.20, 0.70, 1.0, 0.20)
	style_pressed.set_border_width_all(1)
	style_pressed.border_color = Color(0.85, 0.96, 1.0, 1.0)
	style_pressed.shadow_color = Color(0.30, 0.85, 1.0, 0.50)
	style_pressed.shadow_size = 3
	style_pressed.anti_aliasing = true
	_apply_corners(style_pressed, corner_top, corner_bottom, 4)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	return btn


func _activate_ability_via_pipeline(card_node: Node, card_data: Dictionary, ability: Dictionary, context: Dictionary) -> void:
	"""Envía la habilidad a la Pila LIFO y arranca el flujo Paso D.
	ActionPipeline se encarga de: Paso B (pagar), Paso C (triggers), añadir a pila, Paso D (ventana respuesta)."""
	print("[CardInspection] Activando habilidad '%s' vía Pila" % ability.get("cost_text", "?"))
	var result = await ActionPipeline.activate_ability(card_data, ability, context)
	if not result.get("success", false):
		_inspector._main._update_debug("Habilidad no pudo activarse: %s" % result.get("reason", "?"))
		return
	# Brillo en la carta fuente mientras la habilidad está en la pila
	if is_instance_valid(card_node):
		_start_card_glow(card_node)


func _start_card_glow(card_node: Node) -> void:
	if not is_instance_valid(card_node):
		return
	if card_node in _glowing_cards:
		_glowing_cards[card_node].kill()
	var tween = _inspector.create_tween().set_loops()
	tween.tween_property(card_node, "modulate", Color(1.5, 1.2, 0.2, 1.0), 0.45)
	tween.tween_property(card_node, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.45)
	_glowing_cards[card_node] = tween


func _stop_card_glow(card_node: Node) -> void:
	if card_node in _glowing_cards:
		_glowing_cards[card_node].kill()
		_glowing_cards.erase(card_node)
	if is_instance_valid(card_node):
		var tw = _inspector.create_tween()
		tw.tween_property(card_node, "modulate", Color.WHITE, 0.25)


func _on_ability_glow_resolved(stack_obj: Dictionary, _result: Dictionary) -> void:
	if not stack_obj.get("card_data", {}).get("_is_activated_ability", false):
		return
	var source_id = stack_obj.get("card_data", {}).get("id", "")
	if source_id.is_empty():
		return
	for card_node in _glowing_cards.keys():
		if not is_instance_valid(card_node):
			_glowing_cards.erase(card_node)
			continue
		var cd = card_node.get("card_data") if card_node.get("card_data") != null else {}
		if cd.get("id", "") == source_id:
			_stop_card_glow(card_node)
			break
