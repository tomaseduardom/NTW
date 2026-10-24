extends RefCounted
## AttackPatterns — "Cuando ataca/ataques" que deciden bloqueos:
## - príncipe orión, Amo de las Cadenas: "puedes elegir un Aliado oponente para que lo bloquee (si puede)";
## - Los Szgany, Cochero de Sombras, bullnax: "elige (hasta) un Aliado para que bloquee y a qué Aliado
## bloquea este turno";
## - elemental de magma: "elige un Aliado oponente para que no pueda bloquear este turno".
## Los bloqueos elegidos van a GameManager.forced_blocks (los de Cañón Helios), que se aplican al
## entrar a Bloqueo; el defensor ya no puede mover a ese Aliado.
## Se usa con preload desde TriggerResolution (on_attack).

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const CemeteryTriggersScript = preload("res://scripts/core/effects/triggers/CemeteryTriggers.gd")

const BLOCK_SELF := "puedes elegir un aliado oponente para que lo bloquee"
const BLOCK_PAIR_RX := "elige (?<upto>hasta )?un aliado para que bloquee y a que aliado bloquea este turno"
const NO_BLOCK := "elige un aliado oponente para que no pueda bloquear este turno"
const MARTIRES := "no se pueden utilizar habilidades ni jugar cartas por el resto del turno"
const ARTURO := "duplica su fuerza por el turno y es destruido en la fase final"
const FUMA := "la proxima carta que juegue tu oponente cuesta un oro adicional"
## ryujin el atormentador: "puedes Desterrar hasta dos cartas cuyos costes sumen 3 o menos".
const BANISH_SUM_RX := "puedes desterrar hasta (?<n>\\w+) cartas cuyos costes sumen (?<sum>\\d+) o menos"
const JOSE := "hasta tu proximo turno a tu oponente le cuesta un oro adicional utilizar habilidades de aliados de ese coste"
const HUASO := "baraja todas las cartas oponentes de ese coste y no se puede jugar cartas de ese coste hasta tu proximo turno"
const DAISUKE := "a tu oponente le cuesta un oro adicional utilizar habilidades de oro hasta tu proximo turno"
const LUPIN_RX :="puedes convertir hasta (?<n>\\w+) cartas cuyos costes sumen (?<sum>\\d+) o menos en armas sin habilidad y portalas"
const APOFIS := "una carta y todas sus copias pierden su habilidad y no pueden atacar ni bloquear hasta tu proximo turno"
const TOYOTOMI :="tu oponente no puede poner oros en juego en su proximo turno"
## gurzil: lo mostrado no vuelve al Castillo, va al Destierro.
const GURZIL := "tu oponente muestra tantas cartas del tope de su castillo como fuerza tengan hasta dos aliados que controles, ponlas en su destierro y roba una carta"
const SANDOKAN := "cuando ataques, las cartas que esten o sean puestas en los cementerios este turno pierden su habilidad hasta tu proximo turno"


## amuleto de oso (Oro).
const AMULETO := "por cada aliado de coste 1 o mas en tu linea de defensa puedes hacer que un aliado haga dano al destierro este turno"


# amuleto de oso: hasta un Aliado propio por cada Aliado de coste 1 o más en tu Línea de Defensa hace
# daño al Destierro este turno (la marca de BattleManager).
static func _amuleto(main: Node, card: Node, pid: int) -> void:
	var count := 0
	for c in PlayerSideScript.ally_containers(main, pid)[0].get_children():
		if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO and not ContinuousEffectManager.cost_at_most(c, 0):
			count += 1
	var allies: Array = []
	for container in PlayerSideScript.ally_containers(main, pid):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO and CardQuery.controller_of(c) == pid:
				allies.append(c)
	if count <= 0 or allies.is_empty():
		return
	var chosen: Array = []
	if PlayerSideScript.is_bot(pid):
		chosen = GameManager.attackers.filter(func(a): return a in allies).slice(0, count)
	else:
		chosen = await main._card_interaction.await_multi_target(
			"%s: hasta %d Aliado(s) hacen daño al Destierro este turno" % [str(card.get("card_name")), count],
			allies, count, Callable(), Callable(), true, null, pid)
	if chosen.is_empty() or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	for c in chosen:
		if is_instance_valid(c):
			c.set_meta("damage_to_exile_turn", GameManager.turn_serial)
	main._update_debug("%s: %d Aliado(s) hacen daño al Destierro este turno" % [str(card.get("card_name")), chosen.size()])


## "Cuando entra en juego o ataca": la misma cláusula se resuelve al entrar.
const DEMETER := "tu oponente muestra dos cartas al azar de su mano y no puede jugarlas hasta tu proximo turno"
const BANDIDO := "busca dos oros en el castillo oponente y ponlos en su cementerio"
const TENEBRIS := "puedes buscar hasta tres cartas de distinto nombre en un castillo y desterrarlas"
const PALADIN_HARKER := "puedes nombrar una carta por cada arma que controles, hasta un maximo de tres"
const ENTER_TOO := [FUMA, DEMETER, BANDIDO, TENEBRIS, PALADIN_HARKER, "en armas sin habilidad y portalas"]  # el último: lupin


## Lo que también se resuelve al entrar en juego ("Cuando entra en juego o ataca(s)...").
static func handles_enter(full_text: String) -> bool:
	var t := CemeteryTriggersScript.normalize(full_text)
	return ENTER_TOO.any(func(k): return k in t)


# Capitán del Demeter: dos cartas al azar de la mano rival no se pueden jugar hasta tu próximo turno.
static func _gurzil_attack(main: Node, card: Node, pid: int) -> void:
	"""gurzil: "Cuando ataques, tu oponente muestra tantas cartas del tope de su Castillo como Fuerza
	tengan hasta dos Aliados que controles, ponlas en su Destierro y Roba una carta"."""
	var title := str(card.get("card_name"))
	if await TriggerSystem.open_response_window(card, title, pid):
		return
	var mine: Array = load("res://scripts/core/effects/mechanics/EnterPatterns.gd")._all_allies(main,
		func(c): return CardQuery.controller_of(c) == pid)
	var chosen: Array = await main._card_interaction.await_multi_target(
		"%s: elige hasta dos Aliados que controles (su Fuerza)" % title, mine, 2, Callable(), Callable(), true, null, pid)
	var n := 0
	for a in chosen:
		if is_instance_valid(a):
			n += maxi(0, int(ContinuousEffectManager.get_modified_strength(a)))
	if n > 0:
		var r: Dictionary = await ActionModule.mill(1 - pid, n, true, title, true)
		var shown: Array = []
		for c in r.get("cards", []):
			if is_instance_valid(c) and c.get("card_data") is Dictionary:
				shown.append(c.card_data)
		load("res://scripts/core/effects/mechanics/RevealedCards.gd").record(1 - pid, shown, title)
	await ActionModule.draw(pid, 1, title, true)


static func _demeter(main: Node, card: Node, pid: int) -> void:
	var hand: Array = PlayerSideScript.hand_cards(main, 1 - pid).filter(func(c): return is_instance_valid(c))
	if hand.is_empty() or not main._gold_manager or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	hand.shuffle()
	var shown: Array = hand.slice(0, 2)
	for c in shown:
		if is_instance_valid(c):
			main._gold_manager.lock_card_from_playing(c, pid)
	var names: String = ", ".join(shown.map(func(c): return str(c.get("card_name"))))
	main._update_debug("%s: tu oponente muestra %s y no puede jugarlas hasta tu próximo turno" % [str(card.get("card_name")), names])
	if CombatLog and CombatLog.has_method("log_action"):
		CombatLog.log_action("%s: se muestran %s" % [str(card.get("card_name")), names])


## Elige cartas de un Castillo (pick_in_zones: el Remoto por red, el bot las primeras) y las saca del
## mazo. Devuelve sus datos; el mazo queda barajado.
static func _pick_from_castle(zone_owner: int, chooser: int, title: String, eligible: Callable, min_count: int,
		max_count: int, distinct: bool) -> Array:
	var deck: Array = CardManager.get_deck(zone_owner)
	var entries: Array = []
	for d in deck:
		entries.append({"data": d, "eligible": eligible.call(d)})
	var pools: Array = [{"is_own": zone_owner == chooser, "zone": Constants.Zone.CASTILLO, "cards": entries, "exclusive": true}]
	var raw: Array = await ActionModule.pick_in_zones(chooser, title, pools, mini(min_count, entries.filter(
		func(e): return e.eligible).size()), max_count, distinct)
	var picked: Array = []
	for rp in raw:
		if rp is Array and rp.size() == 2 and int(rp[0]) == 0 and int(rp[1]) >= 0 and int(rp[1]) < entries.size() \
				and entries[int(rp[1])].eligible and not picked.has(entries[int(rp[1])].data) and picked.size() < max_count:
			picked.append(entries[int(rp[1])].data)
	for d in picked:
		deck.erase(d)
	CardManager.shuffle_deck(zone_owner)
	AnimationQueue.queue_shuffle(zone_owner, "Barajar mazo (%s)" % title.get_slice(":", 0))
	return picked


# El Bandido Egipcio: "busca dos Oros en el Castillo oponente y ponlos en su Cementerio".
static func _bandido(main: Node, card: Node, pid: int) -> void:
	var opp: int = 1 - pid
	var title := "%s: busca dos Oros en el Castillo oponente" % str(card.get("card_name"))
	if CardManager.get_deck(opp).is_empty() or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	var picked := await _pick_from_castle(opp, pid, title,
		func(d): return int(d.get("tipo", -1)) == Constants.CardType.ORO, 2, 2, false)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.add_to_cemetery(opp, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


# tenebris: "puedes buscar hasta tres cartas de distinto nombre en un Castillo y Desterrarlas".
static func _tenebris(main: Node, card: Node, pid: int) -> void:
	var zone_owner: int = 1 - pid
	if not PlayerSideScript.is_bot(pid):
		var pick: int = await SelectionManager.await_choice(main, "%s: puedes buscar en un Castillo" % str(card.get("card_name")),
			["Castillo oponente", "Tu Castillo", "No"], pid)
		if pick < 0 or pick > 1:
			return
		zone_owner = 1 - pid if pick == 0 else pid
	if CardManager.get_deck(zone_owner).is_empty() or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	var picked := await _pick_from_castle(zone_owner, pid,
		"%s: hasta tres cartas de distinto nombre para Desterrar" % str(card.get("card_name")), func(_d): return true, 0, 3, true)
	for d in picked:
		d["esta_oculta"] = false
		CardManager.append_to_exile(zone_owner, d)
	if main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


# Paladín Harker: nombra hasta una carta por Arma que controles (máximo tres); el rival no puede jugarlas
# hasta tu próximo turno.
static func _paladin_harker(main: Node, card: Node, pid: int) -> void:
	var weapons: int = CardQuery.weapons_in_play(pid).size()
	var count: int = mini(weapons, 3)
	if count <= 0 or not main._gold_manager:
		return
	var names: Array = []
	if PlayerSideScript.is_bot(pid):
		var rivals: Array = []
		for line in PlayerSideScript.line_containers(main, 1 - pid):
			for c in line.get_children():
				if is_instance_valid(c) and c.get("card_type") != Constants.CardType.ORO:
					rivals.append(c)
		rivals.sort_custom(func(a, b): return int(a.get("card_cost")) > int(b.get("card_cost")))
		for c in rivals:
			if names.size() < count and not names.has(str(c.get("card_name"))):
				names.append(str(c.get("card_name")))
	else:
		for i in count:
			var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
				"%s: nombra una carta (%d de %d) — no podrá ser jugada hasta tu próximo turno" % [str(card.get("card_name")), i + 1, count], pid)
			if picked.is_empty():
				break
			names.append(str(picked.get("nombre", "")))
	if names.is_empty() or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	for n in names:
		main._gold_manager.lock_name_from_playing(n, 1 - pid, pid)
	main._update_debug("%s: %s no pueden ser jugadas hasta tu próximo turno" % [str(card.get("card_name")), ", ".join(names)])


# arturo prat: "Cuando ataque solo, duplica su Fuerza por el turno y es Destruido en la Fase Final."
static func _arturo(main: Node, card: Node, pid: int) -> void:
	var title := str(card.get("card_name"))
	if await TriggerSystem.open_response_window(card, title, pid) or not is_instance_valid(card):
		return
	var strength: int = int(ContinuousEffectManager.get_modified_strength(card))
	if strength > 0 and not await EffectController.offer_prevention(card, card, "strength_change"):
		ContinuousEffectManager.register_modifier({
			"source": card,
			"target": card,
			"type": ContinuousEffectManager.ModifierType.STRENGTH,
			"stat": "strength",
			"value": strength,
			"operation": "add",
			"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
			"layer": ContinuousEffectManager.ModifierLayer.LAYER_7B_CHAR_MODIFY,
			"description": "%s: Fuerza duplicada" % title,
		})
		if card.has_method("refresh_strength_badge"):
			card.refresh_strength_badge()
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	EffectController.schedule_next_final_phase_effect(pid, func() -> void:
		if is_instance_valid(card) and card.has_method("is_in_play") and card.is_in_play():
			main._update_debug("%s es Destruido en la Fase Final" % title)
			await EffectController.destroy_card(owner, card, true, card))
	main._update_debug("%s duplica su Fuerza y será Destruido en la Fase Final" % title)


static func try_execute(card: Node, clause: String, controller_id: int) -> bool:
	var t := CemeteryTriggersScript.normalize(clause)
	var main := CardQuery.main_node()
	# na tuk kong ("tu oponenteno puede", errata impresa) y Mártires: nadie juega cartas por el resto del
	# turno (GoldManager.set_no_more_cards_this_turn, el candado de Tempilcahue).
	if "no puede jugar cartas por el resto del turno" in t or "oponenteno puede jugar cartas por el resto del turno" in t \
			or MARTIRES in t:
		if main and main._gold_manager and not await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			var both: bool = MARTIRES in t
			for pid in ([0, 1] if both else [1 - controller_id]):
				main._gold_manager.set_no_more_cards_this_turn(pid)
			if both:
				ContinuousEffectManager.no_abilities_turn = GameManager.turn_serial
			main._update_debug("%s: %s por el resto del turno" % [str(card.get("card_name")),
				"no se pueden utilizar habilidades ni jugar cartas" if both else "tu oponente no puede jugar cartas"])
		return true
	if ARTURO in t:
		if main and card.has_method("is_in_play") and card.is_in_play():
			await _arturo(main, card, controller_id)
		return true
	var cost_sum: RegExMatch = RegEx.create_from_string(BANISH_SUM_RX).search(t)
	if cost_sum:
		if main and main._card_interaction:
			await _banish_cost_sum(main, card, controller_id, EffectCompiler.parse_amount(cost_sum.get_string("n")),
				int(cost_sum.get_string("sum")))
		return true
	for pair in [[LADY_MINA, "_lady_mina"], [URIKO, "_uriko"], [DHAMPIR, "_dhampir"], [HOMBRE_INVISIBLE, "_hombre_invisible"],
			[ANDRAS, "_andras"]]:
		if pair[0] in t:
			if main:
				await load("res://scripts/core/effects/mechanics/AttackPatterns.gd").call(pair[1], main, card, controller_id)
			return true
	# jose miguel carrera / huaso bueras: el coste se nombra en esta oración y se usa en la siguiente.
	var full := CemeteryTriggersScript.normalize(str(card.card_data.get("habilidad", ""))) if card.get("card_data") != null else t
	if ("nombra un coste" in t and JOSE in full) or ("elige un coste" in t and HUASO in full):
		if main:
			await _named_cost(main, card, controller_id, JOSE in full)
		return true
	if DAISUKE in t:
		if main and not await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			RuleState.set_until("gold_ability_toll", 1 - controller_id, RuleState.next_own_turn(controller_id))
			main._update_debug("%s: a tu oponente le cuesta un Oro adicional utilizar habilidades de Oro hasta tu próximo turno" % str(card.get("card_name")))
		return true
	var lupin: RegExMatch = RegEx.create_from_string(LUPIN_RX).search(t)
	if lupin:
		if main and main._card_interaction:
			await _lupin(main, card, controller_id, EffectCompiler.parse_amount(lupin.get_string("n")), int(lupin.get_string("sum")))
		return true
	if APOFIS in t:
		if main:
			await _apofis(main, card, controller_id)
		return true
	# toyotomi hideyoshi ("Cuando ataque por primera vez en el juego"): el candado de Escarapela Nacional.
	if TOYOTOMI in t:
		if main and main._gold_manager and not await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			main._gold_manager.block_gold_next_turn(1 - controller_id)
			main._update_debug("%s: tu oponente no puede poner Oros en juego en su próximo turno" % str(card.get("card_name")))
		return true
	if FUMA in t:
		if main and not await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			PaymentManager.add_next_card_surcharge(1 - controller_id)
			main._update_debug("%s: la próxima carta que juegue tu oponente cuesta un Oro adicional" % str(card.get("card_name")))
		return true
	for pair in [[DEMETER, "_demeter"], [BANDIDO, "_bandido"], [TENEBRIS, "_tenebris"], [PALADIN_HARKER, "_paladin_harker"]]:
		if pair[0] in t:
			if main:
				match pair[1]:
					"_demeter": await _demeter(main, card, controller_id)
					"_bandido": await _bandido(main, card, controller_id)
					"_tenebris": await _tenebris(main, card, controller_id)
					"_paladin_harker": await _paladin_harker(main, card, controller_id)
			return true
	if AMULETO in t:
		if main and main._card_interaction:
			await _amuleto(main, card, controller_id)
		return true
	if GURZIL in t:
		if main and main._card_interaction:
			await _gurzil_attack(main, card, controller_id)
		return true
	# sandokan: lo de Sable de Napoleón sin mínimo de atacantes.
	if SANDOKAN in t:
		if main and not await TriggerSystem.open_response_window(card, str(card.get("card_name")), controller_id):
			CardManager.silence_all_cemetery_cards(controller_id)
			main._update_debug("%s: las cartas de los Cementerios pierden su habilidad hasta tu próximo turno" % str(card.get("card_name")))
		return true
	# Sable de Napoleón y Estación Fantasma: los resuelve GameManager.confirm_attackers() aparte.
	if "cuando ataques con tres o mas aliados" in t or "elige hasta dos aliados con furia que controles para que no hagan dano" in t:
		return true
	# hacha de perun (Arma): lo resuelve GameManager._check_wielder_attack_triggers() cuando ataca su portador.
	if "cuando ataca puedes elegir un aliado que lo bloquee" in t:
		return true
	if BLOCK_SELF in t:
		if main and card in GameManager.attackers:
			await GameManager._choose_forced_blocker(card, card, controller_id)
		return true
	var pair: RegExMatch = RegEx.create_from_string(BLOCK_PAIR_RX).search(t)
	if pair:
		if main:
			await _block_pair(main, card, controller_id, not pair.get_string("upto").is_empty())
		return true
	if NO_BLOCK in t:
		if main:
			await _no_block(main, card, controller_id)
		return true
	return false


## Elegir con presupuesto en vivo (como Ngenechén): cartas en juego que no sean Oro (no tienen coste).
static func _banish_cost_sum(main: Node, card: Node, pid: int, max_count: int, max_sum: int) -> void:
	var chosen: Array = await _pick_cost_sum(main, card, pid, max_count, max_sum,
		"%s: puedes Desterrar hasta %d cartas cuyos costes sumen %d o menos" % [str(card.get("card_name")), max_count, max_sum])
	if not chosen.is_empty():
		await ActionModule.banish(chosen, card, true)


static func _pick_cost_sum(main: Node, card: Node, pid: int, max_count: int, max_sum: int, prompt: String) -> Array:
	var candidates: Array = []
	for side in [1 - pid, pid]:
		for container in PlayerSideScript.line_containers(main, side):
			for c in container.get_children():
				if is_instance_valid(c) and c != card and c.get("card_type") != Constants.CardType.ORO \
						and ContinuousEffectManager.cost_at_most(c, max_sum):
					candidates.append(c)
	if candidates.is_empty():
		return []
	var cost_of := func(c: Node) -> int: return int(ContinuousEffectManager.get_modified_cost(c))
	var chosen: Array = []
	if PlayerSideScript.is_bot(pid):
		# Las más caras del rival que entren en el presupuesto.
		var rivals: Array = candidates.filter(func(c): return CardQuery.controller_of(c) != pid)
		rivals.sort_custom(func(a, b): return cost_of.call(a) > cost_of.call(b))
		var total := 0
		for c in rivals:
			if chosen.size() < max_count and total + cost_of.call(c) <= max_sum:
				chosen.append(c)
				total += cost_of.call(c)
	else:
		var budget := func(so_far: Array, c: Node) -> bool:
			var total := 0
			for x in so_far:
				total += cost_of.call(x)
			return so_far.size() < max_count and total + cost_of.call(c) <= max_sum
		chosen = await main._card_interaction.await_multi_target(prompt, candidates, max_count, Callable(), budget, true, null, pid)
	return chosen


# jose miguel carrera: "nombra un coste. Hasta tu próximo turno a tu oponente le cuesta un Oro adicional
# utilizar habilidades de Aliados de ese coste" (TriggerTollPatterns.ability_toll).
# huaso bueras: "elige un coste. Baraja todas las cartas oponentes de ese coste y no se puede jugar cartas
# de ese coste hasta tu próximo turno" (los dos jugadores; GoldManager._card_play_locked).
static func _named_cost(main: Node, card: Node, pid: int, is_toll: bool) -> void:
	var title := str(card.get("card_name"))
	var rivals: Array = []
	for container in PlayerSideScript.line_containers(main, 1 - pid):
		for c in container.get_children():
			if is_instance_valid(c) and c.get("card_type") != Constants.CardType.ORO and c.get("card_cost") != null \
					and (not is_toll or c.get("card_type") == Constants.CardType.ALIADO):
				rivals.append(c)
	var cost := 0
	if PlayerSideScript.is_bot(pid):
		# El coste que más se repite entre las cartas rivales en juego.
		var freq: Dictionary = {}
		for c in rivals:
			freq[int(c.card_cost)] = int(freq.get(int(c.card_cost), 0)) + 1
		var best := -1
		for k in freq:
			if best < 0 or freq[k] > freq[best]:
				best = k
		cost = maxi(best, 0)
	else:
		var options: Array = []
		for i in 8:
			options.append("Coste %d" % i)
		cost = await SelectionManager.await_choice(main, "%s: %s un coste" % [title, "nombra" if is_toll else "elige"], options, pid)
		if cost < 0:
			return
	if await TriggerSystem.open_response_window(card, title, pid):
		return
	var until: int = RuleState.next_own_turn(pid)
	if is_toll:
		RuleState.set_until("ally_cost_toll:%d" % cost, 1 - pid, until)
		main._update_debug("%s: hasta tu próximo turno, a tu oponente le cuesta un Oro más utilizar habilidades de Aliados de coste %d" % [title, cost])
		return
	for c in rivals:
		if is_instance_valid(c) and int(c.card_cost) == cost:
			await PlayerSideScript.shuffle_into_castle(c, card, title)
	for p in [0, 1]:
		RuleState.set_until("cost_play_lock:%d" % cost, p, until)
	main._update_debug("%s: no se pueden jugar cartas de coste %d hasta tu próximo turno" % [title, cost])


# lupin: "puedes convertir hasta dos cartas cuyos costes sumen 3 o menos en Armas sin habilidad y
# pórtalas" — las porta el propio lupin (bajo tu control).
static func _lupin(main: Node, card: Node, pid: int, max_count: int, max_sum: int) -> void:
	if not main._gold_manager or not (card.has_method("is_in_play") and card.is_in_play()):
		return
	var chosen: Array = await _pick_cost_sum(main, card, pid, max_count, max_sum,
		"%s: puedes convertir hasta %d cartas cuyos costes sumen %d o menos en Armas que porta" % [str(card.get("card_name")), max_count, max_sum])
	if chosen.is_empty() or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	for node in chosen:
		if not is_instance_valid(node) or not is_instance_valid(card):
			continue
		var wielder = node.get_parent()
		if wielder and wielder.get("equipped_weapons") is Array:
			wielder.equipped_weapons.erase(node)
		var weapons = node.get("equipped_weapons")
		if weapons is Array:
			for w in weapons.duplicate():
				if is_instance_valid(w):
					await CardManager.destroy_card(int(w.owner_id) if w.get("owner_id") != null else pid, w)
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.card_type = Constants.CardType.ARMA
		node.controller_id = pid
		node.is_converted = true
		await KeywordManager.silence_card(node, card, "permanent", true)
		ContinuousEffectManager.remove_modifiers_from_source(node)
		await main._gold_manager._equip_weapon(node, card, false)
		main._update_debug("%s: %s es ahora un Arma sin habilidad" % [str(card.get("card_name")), str(node.get("card_name"))])
	if main.get("_zone_manager"):
		main._zone_manager.compact_all_fields(true)


# Apofis del Caos: "una carta y todas sus copias pierden su habilidad y no pueden atacar ni bloquear hasta
# tu próximo turno" (el nombre, en juego o no; las copias en juego tampoco atacan ni bloquean).
static func _apofis(main: Node, card: Node, pid: int) -> void:
	var target: Node = await PlayerSideScript.pick_in_play(main, pid,
		"%s: elige una carta: ella y sus copias pierden su habilidad y no atacan ni bloquean hasta tu próximo turno" % str(card.get("card_name")),
		func(c: Node) -> bool: return c.get("current_zone") in Constants.ZONES_IN_PLAY and c != card, false, [1 - pid])
	if not target or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid) or not is_instance_valid(target):
		return
	var name := str(target.get("card_name"))
	KeywordManager.lock_name_until_next_turn(name, -1)
	for side in [0, 1]:
		for container in PlayerSideScript.line_containers(main, side):
			for c in container.get_children():
				if is_instance_valid(c) and str(c.get("card_name")) == name:
					for restriction in ["CANT_ATTACK", "CANT_BLOCK"]:
						ContinuousEffectManager.register_modifier({
							"source": c,
							"target": c,
							"type": ContinuousEffectManager.ModifierType.RESTRICTION,
							"restriction_type": restriction,
							"duration": ContinuousEffectManager.ModifierDuration.TIMED,
							"duration_value": 2,  # este fin de turno y el del rival
							"description": "%s: no ataca ni bloquea" % str(card.get("card_name")),
						})
	main._update_debug("%s: %s y sus copias pierden su habilidad y no atacan ni bloquean hasta tu próximo turno" % [str(card.get("card_name")), name])


static func _defense_allies(main: Node, defender: int) -> Array:
	var out: Array = []
	for c in PlayerSideScript.ally_containers(main, defender)[0].get_children():
		if is_instance_valid(c) and c.get("card_type") == Constants.CardType.ALIADO and ContinuousEffectManager.can_block(c):
			out.append(c)
	return out


static func _block_pair(main: Node, card: Node, pid: int, up_to: bool) -> void:
	var title := str(card.get("card_name"))
	var attackers: Array = GameManager.attackers.filter(func(a): return is_instance_valid(a))
	var blockers: Array = _defense_allies(main, 1 - pid).filter(func(b):
		return not (b in GameManager.forced_blocks.values()) \
			and attackers.any(func(a): return BattleManager.is_valid_block(a, b).get("valid", false)))
	if attackers.is_empty() or blockers.is_empty():
		return
	var blocker: Node = await PlayerSideScript.pick_in_play(main, pid,
		"%s: elige un Aliado oponente para que bloquee%s" % [title, " (N: ninguno)" if up_to else ""],
		func(c: Node) -> bool: return c in blockers, up_to, [1 - pid])
	if not blocker or not is_instance_valid(blocker):
		return
	var valid: Array = attackers.filter(func(a): return BattleManager.is_valid_block(a, blocker).get("valid", false))
	var attacker: Node = valid[0] if valid.size() == 1 else null
	if attacker == null:
		attacker = await PlayerSideScript.pick_in_play(main, pid,
			"%s: elige a qué Aliado atacante bloquea %s" % [title, str(blocker.get("card_name"))],
			func(c: Node) -> bool: return c in valid, false, [pid])
	if not attacker or not is_instance_valid(attacker):
		return
	if await TriggerSystem.open_response_window(card, title, pid):
		return
	if is_instance_valid(blocker) and is_instance_valid(attacker):
		GameManager.forced_blocks[attacker] = blocker
		main._update_debug("%s deberá bloquear a %s" % [str(blocker.get("card_name")), str(attacker.get("card_name"))])


static func _no_block(main: Node, card: Node, pid: int) -> void:
	var title := str(card.get("card_name"))
	var target: Node = await PlayerSideScript.pick_in_play(main, pid,
		"%s: elige un Aliado oponente para que no pueda bloquear este turno" % title,
		func(c: Node) -> bool:
			return c.get("card_type") == Constants.CardType.ALIADO and c.get("current_zone") in Constants.ZONES_IN_PLAY \
				and CardQuery.controller_of(c) == 1 - pid,
		false, [1 - pid])
	if not target or await TriggerSystem.open_response_window(card, title, pid) or not is_instance_valid(target):
		return
	ContinuousEffectManager.register_modifier({
		"source": target,
		"target": target,
		"type": ContinuousEffectManager.ModifierType.RESTRICTION,
		"restriction_type": "CANT_BLOCK",
		"duration": ContinuousEffectManager.ModifierDuration.UNTIL_END_TURN,
		"description": "No puede bloquear este turno (%s)" % title,
	})
	main._update_debug("%s no puede bloquear este turno" % str(target.get("card_name")))



# =============================================================================
# ÚLTIMO LOTE DE "CUANDO ATACA"
# =============================================================================
const LADY_MINA := "cuando ataques con un solo aliado, puedes nombrar una carta que no sea oro"
const URIKO := "puedes desterrarlo para que tu oponente solo pueda agrupar hasta cuatro oros en su proxima agrupacion"
const DHAMPIR := "hasta dos aliados no pueden ser afectados por efectos oponentes durante la batalla mitologica"
const HOMBRE_INVISIBLE := "puedes agruparlo para que tu oponente bote cartas igual a su fuerza y declarar ataque con otro aliado en su lugar"
const ANDRAS := "puedes subir un aliado de coste 2 o menos que controles a tu mano y jugar sin pagar su coste un aliado de igual coste atacando"


static func _lady_mina(main: Node, card: Node, pid: int) -> void:
	var EnterScript = load("res://scripts/core/effects/mechanics/EnterPatterns.gd")  # sin precarga: EnterPatterns precarga este
	var named := ""
	if PlayerSideScript.is_bot(pid):
		var rivals: Array = EnterScript._in_play(main, 1 - pid)
		rivals.sort_custom(func(a, b): return EnterScript._cost(a) > EnterScript._cost(b))
		named = EnterScript._name(rivals[0]) if not rivals.is_empty() else ""
	else:
		var picked: Dictionary = await TriggerSystem._card_name_search.open_and_wait(
			"%s: puedes nombrar una carta que no sea Oro (jugarla o usar sus habilidades cuesta un Oro más)" % str(card.get("card_name")), pid)
		if int(picked.get("tipo", -1)) == Constants.CardType.ORO:
			main._update_debug("%s: no puedes nombrar un Oro" % str(card.get("card_name")))
			return
		named = str(picked.get("nombre", ""))
	if named.is_empty() or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	var until: int = RuleState.next_own_turn(pid)
	for p in [0, 1]:
		RuleState.set_until("name_ability_toll:" + named.to_lower(), p, until)  # TriggerTollPatterns.ability_toll
		RuleState.set_until("name_play_toll:" + named.to_lower(), p, until)  # PaymentManager
	main._update_debug("%s: jugar o usar habilidades de %s cuesta un Oro más hasta tu próximo turno" % [str(card.get("card_name")), named])


static func _uriko(main: Node, card: Node, pid: int) -> void:
	var EnterScript = load("res://scripts/core/effects/mechanics/EnterPatterns.gd")  # sin precarga: EnterPatterns precarga este
	if not await EnterScript._confirm(main, pid, str(card.get("card_name")), "Desterrarlo: tu oponente solo agrupa hasta cuatro Oros"):
		return
	var owner: int = int(card.owner_id) if card.get("owner_id") != null else pid
	if not await EffectController.exile_card(owner, card, true, card):  # el costo: Desterrarlo
		return
	RuleState.set_pending("regroup_cap", 1 - pid, 4)  # GoldManager._reset_gold / EasyBot.reset_gold
	main._update_debug("uriko-hime: tu oponente solo puede agrupar hasta cuatro Oros en su próxima Agrupación")


static func _dhampir(main: Node, card: Node, pid: int) -> void:
	var EnterScript = load("res://scripts/core/effects/mechanics/EnterPatterns.gd")  # sin precarga: EnterPatterns precarga este
	var allies: Array = EnterScript._all_allies(main, func(c): return CardQuery.controller_of(c) == pid or not PlayerSideScript.is_bot(pid))
	var chosen: Array = await EnterScript._pick_many(main, pid, "%s: hasta dos Aliados no pueden ser afectados por efectos oponentes en la Batalla" % str(card.get("card_name")),
		allies, 2, true)
	if chosen.is_empty() or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	for c in chosen:
		if is_instance_valid(c):
			c.set_meta("opp_immune_battle_turn", GameManager.turn_serial)  # EffectController.opp_immune_card


static func _hombre_invisible(main: Node, card: Node, pid: int) -> void:
	var EnterScript = load("res://scripts/core/effects/mechanics/EnterPatterns.gd")  # sin precarga: EnterPatterns precarga este
	if not (card in GameManager.attackers):
		return
	var others: Array = EnterScript._in_play(main, pid, func(c): return c != card and c.get("card_type") == Constants.CardType.ALIADO \
		and not (c in GameManager.attackers) and TurnManager.can_attack(c).get("can_attack", true))
	if not await EnterScript._confirm(main, pid, str(card.get("card_name")), "Agruparlo: tu oponente Bota cartas igual a su Fuerza y otro Aliado ataca en su lugar"):
		return
	if await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	var strength: int = int(ContinuousEffectManager.get_modified_strength(card))
	GameManager.attackers.erase(card)
	if main._card_interaction and main._card_interaction.has_method("unmark_attackers"):
		await main._card_interaction.unmark_attackers([card])
	if strength > 0:
		await ActionModule.mill(1 - pid, strength, false, str(card.get("card_name")))
	var other: Node = await EnterScript._pick_from(main, pid, "%s: elige otro Aliado para atacar en su lugar" % str(card.get("card_name")), others, true)
	if is_instance_valid(other):
		GameManager.replacement_attackers.append(other)


static func _andras(main: Node, card: Node, pid: int) -> void:
	var EnterScript = load("res://scripts/core/effects/mechanics/EnterPatterns.gd")  # sin precarga: EnterPatterns precarga este
	if not main._gold_manager:
		return
	var small: Array = EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO and EnterScript._cost(c) <= 2)
	if small.is_empty() or not await EnterScript._confirm(main, pid, str(card.get("card_name")),
			"Subir un Aliado de coste 2 o menos y jugar gratis uno de igual coste atacando"):
		return
	var back: Node = await EnterScript._pick_from(main, pid, "%s: sube un Aliado de coste 2 o menos a tu mano" % str(card.get("card_name")), small, true)
	if not is_instance_valid(back) or await TriggerSystem.open_response_window(card, str(card.get("card_name")), pid):
		return
	var cost: int = EnterScript._cost(back)
	GameManager.attackers.erase(back)
	if not await EnterScript.bounce_to_owner_hand(main, back, card):
		return
	var same: Array = EnterScript._hand(main, pid).filter(func(c): return c.get("card_type") == Constants.CardType.ALIADO and int(c.get("card_cost")) == cost)
	var chosen: Node = await EnterScript._pick_from(main, pid, "%s: juega sin pagar su coste un Aliado de coste %d (entra atacando)" % [str(card.get("card_name")), cost], same, true)
	if not is_instance_valid(chosen):
		return
	var data: Dictionary = PlayerSideScript.take_from_hand(main, pid, chosen)
	var before: Array = EnterScript._in_play(main, pid)
	if not await main._gold_manager.play_card_for_free(data, pid):
		return
	for c in EnterScript._in_play(main, pid):
		if not (c in before) and EnterScript._name(c) == str(data.get("nombre", "")):
			GameManager.replacement_attackers.append(c)  # entra atacando
			break
