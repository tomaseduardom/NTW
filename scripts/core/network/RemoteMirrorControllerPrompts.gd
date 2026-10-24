extends "res://scripts/core/network/RemoteMirrorControllerMesa.gd"
## RemoteMirrorControllerPrompts — familia Prompts de RemoteMirrorController.gd (ver RemoteMirrorControllerBase.gd).


# =============================================================================
# MULLIGAN
# =============================================================================


func _show_mulligan_loading() -> void:
	var loading := _main.get_node_or_null("/root/MatchLoadingOverlay")
	if not loading:
		return
	if _mulligan_loading == "waiting":
		loading.show_loading(_main, "ESPERANDO JUGADOR",
			"Tu mano ya está lista — esperando a que el otro jugador elija la suya...")
	elif _mulligan_loading == "showing":
		loading.show_loading(_main, "MOSTRANDO TU MANO", "Tu oponente está viendo tu mano...")


func _show_hand_shown(data: Dictionary) -> void:
	var loading := _main.get_node_or_null("/root/MatchLoadingOverlay")
	if loading and _mulligan_loading != "":
		loading.hide_loading()
	SelectionManager.open_reveal(data.get("cards", []), str(data.get("title", "Tu oponente muestra su mano")), 0)
	await SelectionManager.selection_completed
	NetworkClient.send_message({"op": "intent", "kind": "hand_shown_closed"})
	_show_mulligan_loading()


func _show_mulligan_prompt(data: Dictionary) -> void:
	"""El mulligan reusa los Nodos de Main.tscn (mulligan_overlay, mulligan_hand —el mismo abanico que
	ve el Anfitrión—, keep_hand_button, mulligan_button) en vez de un popup aparte (arquitectura.md
	§44). Esos botones vienen conectados a
	MulliganController.on_keep_hand_pressed()/on_mulligan_pressed(), que terminan en
	GameManager.start_game() de una partida local: hay que desconectarlos antes de reusarlos."""
	var hand: Array = data.get("hand", [])
	_mulligan_loading = ""
	_main.mulligan_hand.clear_cards_instant()
	for card_data in hand:
		var card_node = _main._create_card(card_data, false)
		card_node.can_interact = true
		card_node.drag_enabled = false
		_main.mulligan_hand.add_card(card_node, true)
	_main.mulligan_cards_label.text = "Mano actual: %d cartas" % hand.size()
	var next_hand_size: int = hand.size() - 1
	if next_hand_size <= 0:
		_main.mulligan_button.disabled = true
		_main.mulligan_button.text = "No puedes hacer mas mulligan"
	else:
		_main.mulligan_button.disabled = false
		_main.mulligan_button.text = "Mulligan (robar %d)" % next_hand_size
	_main.mulligan_overlay.visible = true

	if _main.keep_hand_button.pressed.is_connected(_main._mulligan_ctrl.on_keep_hand_pressed):
		_main.keep_hand_button.pressed.disconnect(_main._mulligan_ctrl.on_keep_hand_pressed)
	if _main.mulligan_button.pressed.is_connected(_main._mulligan_ctrl.on_mulligan_pressed):
		_main.mulligan_button.pressed.disconnect(_main._mulligan_ctrl.on_mulligan_pressed)
	var free_btn: Button = _main._mulligan_ctrl.free_mulligan_button
	if free_btn and free_btn.pressed.is_connected(_main._mulligan_ctrl.on_free_mulligan_pressed):
		free_btn.pressed.disconnect(_main._mulligan_ctrl.on_free_mulligan_pressed)
	_main._mulligan_ctrl.set_free_button(data.get("free_available", false), int(data.get("golds", 0)))
	# Un solo clic cuenta: cada opción suelta las tres, así no quedan conexiones colgando para el próximo prompt.
	var conns: Array = []  # [Button, Callable]
	var release := func():
		for pair in conns:
			if pair[0] and pair[0].pressed.is_connected(pair[1]):
				pair[0].pressed.disconnect(pair[1])
	var on_keep := func():
		release.call()
		_mulligan_loading = "waiting"
		_main.mulligan_overlay.visible = false
		_main.mulligan_hand.clear_cards_instant()
		NetworkClient.send_message({"op": "intent", "kind": "mulligan_choice", "keep": true})
		# Mulligan simultáneo: si el Anfitrión todavía está eligiendo, se espera aquí; lo tapa el primer
		# mensaje de partida iniciada (castillo_counts, ver _on_message).
		var loading := _main.get_node_or_null("/root/MatchLoadingOverlay")
		if loading:
			loading.show_loading(_main, "ESPERANDO JUGADOR",
				"Tu mano ya está lista — esperando a que el otro jugador elija la suya...")
	var on_mull := func():
		release.call()
		_main.mulligan_overlay.visible = false
		_main.mulligan_hand.clear_cards_instant()
		NetworkClient.send_message({"op": "intent", "kind": "mulligan_choice", "keep": false})
	var on_free := func():
		release.call()
		_main.mulligan_overlay.visible = false
		_main.mulligan_hand.clear_cards_instant()
		NetworkClient.send_message({"op": "intent", "kind": "mulligan_choice", "keep": false, "free": true})
		# Hasta que el Anfitrión cierre tu mano (o termine de mostrar la suya), llega el próximo prompt.
		_mulligan_loading = "showing"
		_show_mulligan_loading()
	conns.append_array([[_main.keep_hand_button, on_keep], [_main.mulligan_button, on_mull], [free_btn, on_free]])
	for pair in conns:
		if pair[0]:
			pair[0].pressed.connect(pair[1])

# =============================================================================
# VIGILIA
# =============================================================================


func _show_vigilia_prompt(data: Dictionary) -> void:
	# Sin popup. Las cartas jugables de la mano real (player_hand, §45) brillan y se juegan con doble
	# clic, igual que el Anfitrión; el botón de paso del HUD ("Atacar") termina la Vigilia. Ver
	# on_card_double_clicked.
	_pending_vigilia = data
	var actions: Dictionary = {}
	for card in data.get("gold_candidates", []):
		var card_id: String = str(card.get("card_id", ""))
		actions[card_id] = {"op": "intent", "kind": "place_gold", "card_id": card_id}
	for key in ["ally_candidates", "weapon_candidates", "talisman_candidates", "totem_candidates"]:
		for card in data.get(key, []):
			var card_id: String = str(card.get("card_id", ""))
			actions[card_id] = {"op": "intent", "kind": "play_card", "card_id": card_id}
	_set_hand_actions(actions)
	# Habilidades activadas de sus cartas en juego: brillan en dorado; clic en la carta para usarla
	# (misma UI que en las ventanas de respuesta).
	var abilities: Array = []
	for a in data.get("abilities", []):
		# Una carta de la mano que también se puede jugar (doble clic) no se
		# ofrece para habilidad aquí: el primer clic del doble clic la
		# activaría sin querer.
		if not actions.has(str(a.get("card_id", ""))):
			abilities.append(a)
	if not abilities.is_empty():
		_start_ability_pick(abilities, func(choice: Dictionary) -> void:
			_send_intent_and_close({"op": "intent", "kind": "activate_ability",
				"card_id": str(choice.get("card_id", "")), "ability_index": int(choice.get("ability_index", 0))}))
	_main._update_debug("Tu Vigilia — Oro disponible: %d. Doble clic en una carta brillante para jugarla%s." % [
		int(data.get("gold_reserva", 0)), "; clic en una carta dorada para usar su habilidad" if not abilities.is_empty() else ""])
	_set_remote_paso("Atacar [P]" if data.get("can_attack", true) else "Fase Final [P]", false, func():
		_send_intent_and_close({"op": "intent", "kind": "end_vigilia"}))

# =============================================================================
# ATAQUE
# =============================================================================


func _show_ataque_prompt(data: Dictionary) -> void:
	# Sin popup — los Aliados que pueden atacar brillan en tu Línea de Defensa (los Nodos espejados de
	# _card_nodes, mismo card_id que manda el Anfitrión). Un clic los marca/desmarca como atacantes
	# (tinte naranja, como en la pantalla del Anfitrión) y el botón de paso del HUD confirma. Ver
	# on_card_clicked.
	var attackable: Array = data.get("attackable", [])
	if attackable.is_empty():
		_main._update_debug("No tienes ningún Aliado que pueda atacar.")
		_set_remote_paso("Pasar [P]", false, func():
			_send_intent_and_close({"op": "intent", "kind": "declare_attackers", "card_ids": []}))
		return

	for card in attackable:
		var card_id: String = str(card.get("card_id", ""))
		var node: Node = _card_nodes.get(card_id, null)
		if not node or not is_instance_valid(node):
			continue
		_attack_candidates[card_id] = false
		node.can_interact = true
		node.set_activatable(true, CardBadges.GLOW_COLOR_CELESTE, &"remote_attackable")
	_main._update_debug("Clic en tus Aliados brillantes para elegir atacantes, luego Confirmar ataque.")
	_set_remote_paso("Confirmar ataque [P]", false, func():
		var chosen_ids: Array = []
		for card_id in _attack_candidates:
			if _attack_candidates[card_id]:
				chosen_ids.append(card_id)
		_send_intent_and_close({"op": "intent", "kind": "declare_attackers", "card_ids": chosen_ids}))

# =============================================================================
# VENTANA DE RESPUESTA (habilidades activadas — Capa 2 de la Pila de
# Respuesta Universal)
# =============================================================================


func _show_response_window_prompt(data: Dictionary) -> void:
	var candidates: Array = data.get("candidates", [])
	var vbox := _build_overlay("¿Quieres responder?")
	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No tienes ninguna habilidad activada disponible."
		vbox.add_child(lbl)

	_build_card_row(vbox, candidates)
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		var ability_index: int = int(c.get("ability_index", 0))
		var label_text: String = str(c.get("effect_text", c.get("cost_text", "Usar habilidad")))
		_add_row_button(vbox, "Usar: %s" % label_text, func():
			_send_intent_and_close({
				"op": "intent", "kind": "activate_ability",
				"card_id": card_id, "ability_index": ability_index,
			}))

	var sep := HSeparator.new()
	vbox.add_child(sep)
	_add_row_button(vbox, "Pasar", func():
		_send_intent_and_close({"op": "intent", "kind": "pass"}))

# =============================================================================
# ELEGIR PORTADOR DE ARMA (RemotePlayerController._choose_wielder_remote())
# =============================================================================


func _show_choose_wielder_prompt(data: Dictionary) -> void:
	var weapon: Dictionary = data.get("weapon", {})
	var candidates: Array = data.get("candidates", [])
	var on_wielder := func(card_id: String) -> void:
		_send_intent_and_close({"op": "intent", "kind": "choose_wielder", "card_id": card_id})
	if not candidates.is_empty() and _start_board_pick(_ids_of(candidates), on_wielder):
		_main._update_debug("Elige quién porta %s: clic en uno de tus Aliados brillantes" % str(
			weapon.get("nombre", "el Arma")))
		return
	var vbox := _build_overlay("Elige quién porta %s" % str(weapon.get("nombre", "el Arma")))
	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ningún Aliado en juego que pueda portarla."
		vbox.add_child(lbl)
		return

	_build_card_row(vbox, [weapon] if not weapon.is_empty() else [])
	_build_card_row(vbox, candidates)
	for card in candidates:
		var card_id: String = str(card.get("card_id", ""))
		_add_row_button(vbox, str(card.get("nombre", "?")), func():
			_send_intent_and_close({"op": "intent", "kind": "choose_wielder", "card_id": card_id}))

# =============================================================================
# SELECCIÓN DE CARTAS GENÉRICA (SelectionManager._delegate_selection_to_
# remote(), Fase 3 del plan de paridad remota) — cubre de taquito cualquier
# "busca una carta"/"elige del cementerio"/etc. que ya use SelectionManager
# del lado del motor de efectos, sin que cada patrón nuevo necesite su propio
# caso de prompt acá. Las cartas se identifican por ÍNDICE en 'candidates'
# (son Dictionary de datos crudos, no nodos Card con instance_id).
# =============================================================================


func _show_select_cards_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige carta(s)"))
	var candidates: Array = data.get("candidates", [])
	var max_sel: int = int(data.get("max_selections", 1))
	var min_sel: int = int(data.get("min_selections", 0))
	var can_cancel: bool = bool(data.get("can_cancel", true))
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ninguna carta para elegir."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": []}))
		return

	_build_card_row(vbox, candidates)
	if max_sel <= 0:
		# Solo mostrar (SelectionMode.REVEAL) — sin elección real; la fila de
		# cartas reales de arriba ya es la "lista", no hace falta texto.
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": []}))
		return

	if max_sel == 1:
		# Un clic elige y cierra — mismo criterio que el panel local
		# (SelectionManager._on_card_clicked() con max_selections == 1).
		for i in range(candidates.size()):
			var card: Dictionary = candidates[i]
			var idx: int = i
			_add_row_button(vbox, "%s (coste %s)" % [str(card.get("nombre", "?")), str(card.get("coste", "?"))], func():
				_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": [idx]}))
		if can_cancel:
			var sep := HSeparator.new()
			vbox.add_child(sep)
			_add_row_button(vbox, "Cancelar", func():
				_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "cancelled": true, "indices": []}))
		return

	# Multi-selección: checkboxes + Confirmar, mismo criterio que _show_ataque_prompt().
	var checkboxes: Dictionary = {}  # índice (int) -> CheckBox
	for i in range(candidates.size()):
		var card: Dictionary = candidates[i]
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var cb := CheckBox.new()
		row.add_child(cb)
		checkboxes[i] = cb
		var lbl := Label.new()
		lbl.text = "%s (coste %s)" % [str(card.get("nombre", "?")), str(card.get("coste", "?"))]
		row.add_child(lbl)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)
	_add_row_button(button_row, "Confirmar", func():
		var chosen: Array = []
		for i in checkboxes:
			if checkboxes[i].button_pressed:
				chosen.append(i)
		if chosen.size() > max_sel:
			chosen = chosen.slice(0, max_sel)
		if chosen.size() < min_sel:
			return  # mismo criterio que el panel local: no confirma bajo el mínimo
		_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "indices": chosen}))
	if can_cancel:
		_add_row_button(button_row, "Cancelar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cards_choice", "cancelled": true, "indices": []}))

# =============================================================================
# SELECCIÓN DE CARTAS DE CEMENTERIO/DESTIERRO/CASTILLO REVELADO
# (ZoneViewerModule._delegate_cemetery_picker_to_remote()/_delegate_reveal_
# picker_to_remote(), Fase 3 del plan de paridad remota) — mismo protocolo
# que "select_cards" pero con etiquetas extra de zona/lado cuando vienen
# (el picker de Cementerios las manda, el de revelado del Castillo no, al
# ser un solo pool sin "lado rival").
# =============================================================================


func _show_select_cemetery_cards_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige carta(s)"))
	var candidates: Array = data.get("candidates", [])
	var max_sel: int = int(data.get("max_selections", 1))
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ninguna carta para elegir."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "select_cemetery_cards_choice", "indices": []}))
		return

	_build_card_row(vbox, candidates)
	var zone_words := {"cemetery": "Cementerio", "exile": "Destierro"}
	var side_words := {"own": "tuyo", "opponent": "rival"}
	var label_for := func(card: Dictionary) -> String:
		var base: String = "%s (coste %s)" % [str(card.get("nombre", "?")), str(card.get("coste", "?"))]
		var extra := ""
		if card.has("zone_type"):
			extra += str(zone_words.get(str(card.get("zone_type", "")), str(card.get("zone_type", ""))))
		if card.has("side"):
			extra += (" · " if not extra.is_empty() else "") + str(side_words.get(str(card.get("side", "")), str(card.get("side", ""))))
		return "%s [%s]" % [base, extra] if not extra.is_empty() else base

	if max_sel == 1:
		for i in range(candidates.size()):
			var idx: int = i
			_add_row_button(vbox, label_for.call(candidates[i]), func():
				_send_intent_and_close({"op": "intent", "kind": "select_cemetery_cards_choice", "indices": [idx]}))
		return

	var checkboxes2: Dictionary = {}  # índice (int) -> CheckBox
	for i in range(candidates.size()):
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var cb := CheckBox.new()
		row.add_child(cb)
		checkboxes2[i] = cb
		var lbl2 := Label.new()
		lbl2.text = label_for.call(candidates[i])
		row.add_child(lbl2)

	_add_row_button(vbox, "Confirmar", func():
		var chosen: Array = []
		for i in checkboxes2:
			if checkboxes2[i].button_pressed:
				chosen.append(i)
		if chosen.size() > max_sel:
			chosen = chosen.slice(0, max_sel)
		_send_intent_and_close({"op": "intent", "kind": "select_cemetery_cards_choice", "indices": chosen}))

# =============================================================================
# OBJETIVO SOBRE CARTAS YA EN JUEGO (CardInteractionModule.await_target()/
# await_multi_target(), Fase 3 del plan de paridad remota, cuarto sistema) —
# a diferencia de los otros 3 prompts de elegir cartas, acá 'card_id' es un
# get_instance_id() real (Nodos persistentes del tablero), no un índice.
# =============================================================================


func _show_await_target_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige un objetivo"))
	var candidates: Array = data.get("candidates", [])
	var cancellable: bool = bool(data.get("cancellable", true))
	var on_target := func(card_id: String) -> void:
		_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "card_id": card_id})
	if not candidates.is_empty() and _start_board_pick(_ids_of(candidates), on_target):
		_main._update_debug("%s: clic en una carta brillante" % title)
		if cancellable:
			_set_remote_paso("No hacerlo [N]", false, func():
				_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "cancelled": true}))
			_skip_action = _paso_action
		return
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ningún objetivo válido ahora mismo."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "cancelled": true}))
		return

	_build_card_row(vbox, candidates)
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		_add_row_button(vbox, "%s (coste %s)" % [str(c.get("nombre", "?")), str(c.get("coste", "?"))], func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "card_id": card_id}))
	if cancellable:
		var sep := HSeparator.new()
		vbox.add_child(sep)
		_add_row_button(vbox, "Cancelar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_choice", "cancelled": true}))


func _show_await_multi_target_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige objetivo(s)"))
	var candidates: Array = data.get("candidates", [])
	var max_sel: int = int(data.get("max_selections", -1))
	if not candidates.is_empty() and _start_board_pick(_ids_of(candidates), _toggle_multi_pick.bind(max_sel)):
		_main._update_debug("%s: clic en las cartas brillantes para marcarlas, luego Confirmar" % title)
		_set_remote_paso("Confirmar [P]", false, func():
			var chosen_ids: Array = []
			for id in _pick_multi:
				chosen_ids.append(id)
			_send_intent_and_close({"op": "intent", "kind": "await_multi_target_choice", "card_ids": chosen_ids}))
		if bool(data.get("cancellable", true)):
			_skip_action = _paso_action
		return
	var vbox := _build_overlay(title)

	if candidates.is_empty():
		var lbl := Label.new()
		lbl.text = "No hay ningún objetivo válido ahora mismo."
		vbox.add_child(lbl)
		_add_row_button(vbox, "Continuar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_multi_target_choice", "card_ids": []}))
		return

	_build_card_row(vbox, candidates)
	var checkboxes3: Dictionary = {}  # card_id (String) -> CheckBox
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var cb := CheckBox.new()
		row.add_child(cb)
		checkboxes3[card_id] = cb
		var lbl2 := Label.new()
		lbl2.text = "%s (coste %s)" % [str(c.get("nombre", "?")), str(c.get("coste", "?"))]
		row.add_child(lbl2)

	_add_row_button(vbox, "Confirmar", func():
		var chosen_ids: Array = []
		for card_id in checkboxes3:
			if checkboxes3[card_id].button_pressed:
				chosen_ids.append(card_id)
		if max_sel >= 0 and chosen_ids.size() > max_sel:
			chosen_ids = chosen_ids.slice(0, max_sel)
		_send_intent_and_close({"op": "intent", "kind": "await_multi_target_choice", "card_ids": chosen_ids}))

# =============================================================================
# CARRERA "OBJETIVO O CASTILLO" (CardInteractionModule.await_target_or_castillo_pick();
# arquitectura.md §41): cartas candidatas + Castillo propio/rival en un solo prompt.
# =============================================================================


func _show_await_target_or_castillo_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige un objetivo"))
	var candidates: Array = data.get("candidates", [])
	var castillo_title: String = str(data.get("castillo_title", "Castillo"))
	var castillo_own_only: bool = bool(data.get("castillo_own_only", false))
	var cancellable: bool = bool(data.get("cancellable", true))
	var on_card := func(card_id: String) -> void:
		_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "card",
			"card_id": card_id})
	if candidates.is_empty() or _start_board_pick(_ids_of(candidates), on_card):
		_start_remote_castillo_pick(castillo_title, castillo_own_only)
		_main._update_debug("%s: clic en una carta brillante o en un Castillo" % title)
		if cancellable:
			_set_remote_paso("No hacerlo [N]", false, func():
				_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "none"}))
			_skip_action = _paso_action
		return
	var vbox := _build_overlay(title)

	_build_card_row(vbox, candidates)
	for c in candidates:
		var card_id: String = str(c.get("card_id", ""))
		_add_row_button(vbox, "%s (coste %s)" % [str(c.get("nombre", "?")), str(c.get("coste", "?"))], func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "card", "card_id": card_id}))

	var sep := HSeparator.new()
	vbox.add_child(sep)
	_add_row_button(vbox, "%s — Tu Castillo" % castillo_title, func():
		_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "castillo", "own": true}))
	if not castillo_own_only:
		_add_row_button(vbox, "%s — Castillo rival" % castillo_title, func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "castillo", "own": false}))
	if cancellable:
		_add_row_button(vbox, "Cancelar", func():
			_send_intent_and_close({"op": "intent", "kind": "await_target_or_castillo_choice", "type": "none"}))

# =============================================================================
# ELECCIÓN DE OPCIÓN DE TEXTO (SelectionDialogs.await_choice()/await_two_
# choice(), Fase 3 del plan de paridad remota) — la otra familia de UI
# aparte de "elegir cartas": popups de botones de texto (A/B, o N opciones),
# sin cartas de por medio. Mismo criterio de bajo pulido que el resto.
# =============================================================================


func _show_choose_option_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Elige una opción"))
	var options: Array = data.get("options", [])
	# Las mismas fichas sobre la mesa que en el Anfitrión (BoardChoice), ancladas a la carta del efecto.
	var source = _card_nodes.get(str(data.get("source_id", "")), null)
	var idx: int = await load("res://scripts/ui/hud/BoardChoice.gd").choose(_main, title, options, source)
	NetworkClient.send_message({"op": "intent", "kind": "choose_option_choice", "index": idx})

# =============================================================================
# NOMBRAR UNA CARTA (CardNameSearchDialog.open_and_wait(); arquitectura.md §42): no viaja una lista
# de candidatas; el Remoto tiene su propia CardDatabase y corre el mismo buscador local; solo el
# resultado va por red. CardNameSearchDialog administra su propio CanvasLayer (no usa
# _build_overlay()).
# =============================================================================


func _show_name_card_prompt(data: Dictionary) -> void:
	var title: String = str(data.get("title", "Nombra una carta"))
	var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(title)
	NetworkClient.send_message({"op": "intent", "kind": "name_card_choice", "card_data": picked})
