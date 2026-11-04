extends Node
## Escenarios por carta con una partida real (contra el bot): se arma un tablero concreto, se juega la
## carta por el camino del juego (GoldManager.play_card_for_free / pagar_coste) y se verifica el
## resultado: qué zonas cambiaron, la Fuerza, las cartas robadas. Una carta por familia de efecto
## (robar, destruir, desterrar, subir a la mano, descartar, pagar y reagrupar Oros) más una prueba por
## bug arreglado.
## Las elecciones del jugador 0 se responden con un guion (pick()): el nombre de la carta a elegir, o "N"
## para no elegir. Sin guion, se elige lo primero válido (lo propio antes). El jugador 1 es el bot.
## Uso (o tools/run_tests.ps1):
##   Godot_v4.6-stable_win64_console.exe --headless --path . res://tools/tests/test_escenarios.tscn
## Sale con código 1 si algún caso falla.

const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const TurnClockScript = preload("res://scripts/core/network/TurnClock.gd")
const KeywordParser = preload("res://scripts/core/cards/KeywordParser.gd")

const BOARD := ["player_field", "player_linea_ataque", "player_linea_apoyo", "opponent_field",
	"opponent_linea_ataque", "opponent_linea_apoyo"]

var main: Node
var failed := 0
var passed := 0
var _driving := false
var _picks: Array = []
## Nombre del próximo objeto de la Pila que el rival Anula en su ventana de respuesta.
var _annul_next := ""
## Cada selección que se abrió: {prompt, validas (nombres)}.
var prompts: Array = []


func _ready() -> void:
	seed(1)
	Engine.time_scale = 4.0
	main = load("res://scenes/game/Main.tscn").instantiate()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)
	(func(): get_tree().current_scene = main).call_deferred()
	if not await _start_match():
		print("ERROR: no arrancó la partida")
		get_tree().quit(1)
		return
	NetworkClient.sim_force_ui = true  # ventanas propias (BoardChoice, RevealWindow...): opción por defecto
	_driving = true
	for test in [_robar_talisman, _robar_aliado, _destruir, _destruir_con_filtro, _desterrar, _subir_a_la_mano,
			_descartar, _descartar_talismanes, _pagar_y_reagrupar, _anular_en_respuesta, _arma_en_aliado_rival, _arma_sobrevive_del_rival]:
		await clear_board()
		await test.call()
		await settle()
	_driving = false
	print("Escenarios: %d/%d casos OK" % [passed, passed + failed])
	get_tree().quit(1 if failed > 0 else 0)


func _start_match() -> bool:
	var t0 := Time.get_ticks_msec()
	var started := false
	while not started and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if not is_instance_valid(main) or not main.is_inside_tree():
			continue
		for child in main.get_children():
			var s = child.get_script()
			if s and str(s.resource_path).ends_with("ui/zones/DeckSelector.gd"):
				var decks: Array = DeckLoader.get_bundled_decks()
				child.queue_free()
				main._bootstrap._on_decks_selected(decks[0], decks[0])
				started = true
	if not started:
		return false
	while not (main._mulligan_ctrl and main._mulligan_ctrl.is_in_mulligan):
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	await main._mulligan_ctrl._end_mulligan_phase()
	# Se juega en la Vigilia del jugador 0 (si empieza el bot, se espera su turno).
	t0 = Time.get_ticks_msec()
	while not (GameManager.is_game_active and GameManager.active_player_id == 0
			and GameManager.current_phase == Constants.Phase.VIGILIA and not busy()):
		if Time.get_ticks_msec() - t0 > 120000:
			return false
		if GameManager.active_player_id == 0 and GameManager.current_phase == Constants.Phase.FINAL:
			main._phase_flow._on_paso_pressed()
		await get_tree().process_frame
	await settle()
	return true


func _process(_delta: float) -> void:
	if _driving:
		_answer()


func _answer() -> void:
	var ci = main._card_interaction
	var dialogs = SelectionManager._dialogs
	if dialogs and dialogs._castillo_pick_active:
		dialogs._resolve_castillo_pick(true)
		return
	if ci and ci.is_selecting_target:
		var pool: Array = []
		pool.append_array(main.player_hand.cards)
		pool.append_array(main._opponent_fan.get_cards())
		for prop in TurnClockScript.IN_PLAY_CONTAINERS:
			var container: Node = main.get(prop)
			if container:
				pool.append_array(container.get_children())
		pool.append_array(ci._cemetery_target_nodes)
		var valid: Array = pool.filter(func(c): return is_instance_valid(c) and c is Node \
			and (not ci._target_filter.is_valid() or ci._target_filter.call(c)))
		valid.sort_custom(func(x, y): return int(x.get("controller_id") == 0) > int(y.get("controller_id") == 0))
		prompts.append({"prompt": EffectContextScript.last_prompt.get("what", ""), "validas": valid.map(func(c): return str(c.card_name))})
		var want: String = str(_picks.pop_front()) if not _picks.is_empty() else ""
		if want == "N":
			ci.cancel_target_selection()
			return
		for c in valid:
			if want == "" or str(c.card_name) == want:
				ci._resolve_target_selection(c)
				return
		ci.cancel_target_selection()
		return
	if SelectionManager.is_open:
		SelectionManager.force_default()
		return
	if not PriorityManager.priority_window_active:
		return
	# El rival Anula el objeto en el tope de la Pila durante su ventana de respuesta (como StackAnnul.apply).
	var top: Dictionary = ActionPipeline._get_stack_top()
	if _annul_next != "" and str(top.get("name", "")) == _annul_next and PriorityManager.current_stack_controller == 0:
		top["was_annulled"] = true
		top["annuller"] = {"nombre": "Prueba"}
		_annul_next = ""
	if PriorityManager.current_priority_player == 0:
		PriorityManager.pass_priority()


# =============================================================================
# AYUDAS
# =============================================================================
func check(label: String, got, expected) -> void:
	if got == expected:
		passed += 1
	else:
		failed += 1
		print("FALLA: %s\n   esperado: %s\n   obtenido: %s" % [label, str(expected), str(got)])


func busy() -> bool:
	if not EffectContextScript._stack.is_empty() or ActionPipeline._is_resolving or TriggerSystem.is_resolving:
		return true
	if PriorityManager.priority_window_active or GameManager.agrupacion_busy:
		return true
	if main._card_interaction and main._card_interaction.is_selecting_target:
		return true
	return SelectionManager.is_open or AnimationQueue.is_running


func settle(max_ms: int = 20000) -> void:
	var quiet := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		await get_tree().process_frame
		quiet = quiet + 1 if not busy() else 0
		if quiet >= 6:
			return


## Las elecciones que va a hacer el jugador 0, en orden ("N": no elegir).
func pick(names: Array) -> void:
	_picks = names.duplicate()
	prompts.clear()


func data(name: String, tipo: int = -1) -> Dictionary:
	for c in CardDatabase.cards.values():
		if str(c.nombre).to_lower() == name.to_lower() and (tipo < 0 or int(c.tipo) == tipo):
			return c.duplicate(true)
	print("ERROR: no está la carta '%s'" % name)
	return {}


func fake(name: String, cost: int, strength: int, text: String = "", tipo: int = Constants.CardType.ALIADO) -> Dictionary:
	return {"id": "test_" + name, "uuid": "test_" + name, "nombre": name, "tipo": tipo, "coste": cost,
		"fuerza": strength, "habilidad": text, "raza": "", "keywords": KeywordParser.own_keywords(text).duplicate()}


func put(card_data: Dictionary, pid: int, prop: String = "field") -> Node:
	var container: Node = main.get(("player_" if pid == 0 else "opponent_") + prop)
	var zone: int = {"field": Constants.Zone.LINEA_DEFENSA, "linea_ataque": Constants.Zone.LINEA_ATAQUE,
		"linea_apoyo": Constants.Zone.LINEA_APOYO}[prop]
	var card: Node = main._create_card(card_data, false)
	card.owner_id = pid
	card.controller_id = pid
	main._connect_card_signals(card)
	container.add_child(card)
	card.set_zone(zone)
	ContinuousEffectManager._register_card_continuous_effects(card)
	return card


func hand_names(pid: int) -> Array:
	return PlayerSideScript.hand_cards(main, pid).map(func(c): return str(c.card_name))


func zone_names(cards: Array) -> Array:
	return cards.map(func(c): return str(c.get("nombre", "")))


func board_names(pid: int) -> Array:
	var out: Array = []
	for prop in BOARD.slice(0, 3) if pid == 0 else BOARD.slice(3):
		for c in main.get(prop).get_children():
			if is_instance_valid(c) and not c.is_queued_for_deletion():
				out.append(str(c.card_name))
	return out


func fill_deck(pid: int, n: int) -> void:
	var deck: Array = CardManager.get_deck(pid)
	deck.clear()
	for i in n:
		deck.append(fake("Castillo %d" % i, 1, 1))
	main._zone_manager._update_castillo_counts()


func clear_board() -> void:
	await settle()
	for prop in BOARD:
		for c in main.get(prop).get_children():
			if is_instance_valid(c):
				ContinuousEffectManager.remove_modifiers_from_source(c)
				c.get_parent().remove_child(c)
				c.free()
	main.player_hand.clear_hand()
	main._opponent_fan.clear_hand()
	for pid in [0, 1]:
		CardManager.get_cemetery(pid).clear()
		CardManager.get_exile(pid).clear()
		fill_deck(pid, 20)
	ContinuousEffectManager._invalidate_cache()
	_picks.clear()
	prompts.clear()
	await get_tree().process_frame


func play_free(card_data: Dictionary, pid: int = 0) -> bool:
	var ok: bool = await main._gold_manager.play_card_for_free(card_data, pid)
	await settle()
	return ok


# =============================================================================
# ESCENARIOS
# =============================================================================
func _robar_talisman() -> void:
	# Llamar a la Manada: "Roba tres cartas de tu Castillo."
	var manada := data("Llamar a la Manada")
	await play_free(manada)
	check("Llamar a la Manada: roba tres", [hand_names(0).size(), CardManager.get_deck(0).size()], [3, 17])
	check("Llamar a la Manada: el Talismán va al Cementerio", zone_names(CardManager.get_cemetery(0)), [manada.nombre])


func _robar_aliado() -> void:
	# Yomiel: "Cuando entra en juego, Roba dos cartas."
	await play_free(data("Yomiel", Constants.CardType.ALIADO))
	check("Yomiel: entra en juego", board_names(0), ["Yomiel"])
	check("Yomiel: roba dos al entrar", hand_names(0).size(), 2)


func _destruir() -> void:
	# Bola de Fuego: "Destruye una carta en juego que no sea un Oro."
	put(fake("Propio", 2, 2), 0)
	put(fake("Objetivo", 2, 2), 1)
	pick(["Objetivo"])
	await play_free(data("Bola de Fuego"))
	check("Bola de Fuego: el objetivo va al Cementerio de su dueño", zone_names(CardManager.get_cemetery(1)), ["Objetivo"])
	check("Bola de Fuego: lo demás sigue en juego", [board_names(0), board_names(1)], [["Propio"], []])


func _destruir_con_filtro() -> void:
	# Flecha Ácida: "Destruye un Aliado oponente de Fuerza 2 o menos. Luego, Roba una carta."
	# Coste 0: el Oro Inicial del mazo da +1 a los Aliados de coste 1 o más.
	put(fake("Propio", 0, 1), 0)
	put(fake("Debil", 0, 2), 1)
	put(fake("Muy debil", 0, 1), 1)
	put(fake("Fuerte", 0, 3), 1)
	pick(["Muy debil"])
	await play_free(data("Flecha Ácida"))
	# Con un solo objetivo posible se elige solo; con dos se abre la selección.
	var first: Dictionary = prompts[0] if not prompts.is_empty() else {}
	check("Flecha Ácida: solo Aliados oponentes de Fuerza 2 o menos", first.get("validas", []), ["Debil", "Muy debil"])
	check("Flecha Ácida: destruye el elegido y roba", [board_names(1), zone_names(CardManager.get_cemetery(1)), hand_names(0).size()],
		[["Debil", "Fuerte"], ["Muy debil"], 1])


func _desterrar() -> void:
	# vuelo del raiquen: "Destierra un Aliado con Furia, Exhumar o Indestructible de coste 2 o menos."
	put(fake("Con Furia", 2, 2, "Furia."), 1)
	put(fake("Sin nada", 1, 1), 1)
	pick(["Con Furia"])
	await play_free(data("vuelo del raiquen"))
	check("vuelo del raiquen: al Destierro, no al Cementerio",
		[zone_names(CardManager.get_exile(1)), zone_names(CardManager.get_cemetery(1)), board_names(1)],
		[["Con Furia"], [], ["Sin nada"]])


func _subir_a_la_mano() -> void:
	# Favor de la Corte: "Sube una carta oponente en juego que no sea Oro a la Mano de su dueño."
	put(fake("Visitante", 3, 3), 1)
	pick(["Visitante"])
	await play_free(data("Favor de la Corte"))
	check("Favor de la Corte: vuelve a la mano de su dueño", [board_names(1), hand_names(1)], [[], ["Visitante"]])


func _descartar() -> void:
	# viaje al oeste: "Descarta una carta de tu mano y tu oponente Descarta dos cartas."
	for n in ["Mia 1", "Mia 2"]:
		PlayerSideScript.put_in_hand(main, 0, fake(n, 1, 1))
	for n in ["Suya 1", "Suya 2", "Suya 3"]:
		PlayerSideScript.put_in_hand(main, 1, fake(n, 1, 1))
	await play_free(data("viaje al oeste"))
	check("viaje al oeste: tú descartas una y el rival dos",
		[hand_names(0).size(), hand_names(1).size(), CardManager.get_cemetery(1).size()], [1, 1, 2])


func _descartar_talismanes() -> void:
	# caceria de brujas: "Tu oponente muestra su mano y Descarta todos los Talismanes de ahí."
	PlayerSideScript.put_in_hand(main, 1, fake("Talisman A", 5, 0, "", Constants.CardType.TALISMAN))
	PlayerSideScript.put_in_hand(main, 1, fake("Talisman B", 5, 0, "", Constants.CardType.TALISMAN))
	PlayerSideScript.put_in_hand(main, 1, fake("Aliado", 1, 1))
	await play_free(data("caceria de brujas"))
	check("caceria de brujas: el rival descarta solo los Talismanes",
		[hand_names(1), zone_names(CardManager.get_cemetery(1))], [["Aliado"], ["Talisman A", "Talisman B"]])


func _pagar_y_reagrupar() -> void:
	# Bug arreglado: los Oros pagados y reagrupados no actualizaban su zona (current_zone).
	var reserva: Array = main.player_gold.get_children().filter(func(c):
		return is_instance_valid(c) and c.get("card_type") == Constants.CardType.ORO \
			and not "virtual_gold" in str(c.get("keywords")))
	if reserva.is_empty():
		check("hay un Oro en la Reserva para pagar", false, true)
		return
	var oro: Node = reserva[0]
	var disponible: int = main._gold_manager.get_oro_disponible(0)
	await main._gold_manager.pagar_coste(1, -1, "", -1, 0)
	await settle()
	check("pagar: el Oro pasa al Oro Pagado", [oro.get_parent() == main.player_oro_pagado, oro.current_zone],
		[true, Constants.Zone.ORO_PAGADO])
	check("pagar: un Oro menos disponible", main._gold_manager.get_oro_disponible(0), disponible - 1)
	await main._gold_manager._reset_gold()
	await settle()
	check("reagrupar: vuelve a la Reserva", [oro.get_parent() == main.player_gold, oro.current_zone],
		[true, Constants.Zone.RESERVA_ORO])
	check("reagrupar: Oro disponible como al principio", main._gold_manager.get_oro_disponible(0), disponible)


func _anular_en_respuesta() -> void:
	# El Aliado se juega, el rival lo Anula en su ventana de respuesta: va al Cementerio sin entrar en juego
	# ni disparar "Cuando entra en juego" (Yomiel no roba).
	_annul_next = "Yomiel"
	await play_free(data("Yomiel", Constants.CardType.ALIADO))
	_annul_next = ""
	check("Anulado en respuesta: no entra en juego ni roba",
		[board_names(0), hand_names(0).size(), zone_names(CardManager.get_cemetery(0))], [[], 0, ["Yomiel"]])


func _arma_en_aliado_rival() -> void:
	# Bug arreglado: un Arma propia portada por un Aliado rival iba al Cementerio del portador al morir
	# este (el conteo de cartas por jugador quedaba 49/51).
	var ally := put(fake("Portador rival", 2, 2), 1)
	var weapon: Node = main._create_card(fake("Arma propia", 1, 0, "", Constants.CardType.ARMA), false)
	weapon.owner_id = 0
	weapon.controller_id = 0
	main._connect_card_signals(weapon)
	await main._gold_manager._equip_weapon(weapon, ally, false)
	await settle()
	pick(["Portador rival"])
	await play_free(data("Bola de Fuego"))
	check("Arma propia en Aliado rival: cada carta al Cementerio de su dueño",
		[zone_names(CardManager.get_cemetery(1)), zone_names(CardManager.get_cemetery(0)).has("Arma propia")],
		[["Portador rival"], true])


func _arma_sobrevive_del_rival() -> void:
	# Paridad: "Cuando el portador fuera a salir del juego, súbela a tu mano o cámbiala de portador" (Aho)
	# solo se aplicaba al jugador 0; la del jugador 1 (bot o Remoto) seguía a su portador al Cementerio.
	var ally := put(fake("Portador", 2, 2), 1)
	var weapon: Node = main._create_card(fake("Arma fiel", 1, 0,
		"Cuando el portador fuera a salir del juego, súbela a tu mano o cámbiala de portador.", Constants.CardType.ARMA), false)
	weapon.owner_id = 1
	weapon.controller_id = 1
	main._connect_card_signals(weapon)
	await main._gold_manager._equip_weapon(weapon, ally, false)
	await settle()
	pick(["Portador"])
	await play_free(data("Bola de Fuego"))
	check("Arma que sobrevive al portador, del jugador 1: vuelve a su mano",
		[zone_names(CardManager.get_cemetery(1)), hand_names(1)], [["Portador"], ["Arma fiel"]])
