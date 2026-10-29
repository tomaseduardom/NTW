extends RefCounted
## ProtectionRules — Reglas de protección: no puede ser cancelado / Desterrado, daño al Destierro,
## Indestructible mientras bloquea, Armas que no pueden ser canceladas.
## Se usa con preload.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const KeywordParser = preload("res://scripts/core/cards/KeywordParser.gd")
const KeywordConditions = preload("res://scripts/core/cards/KeywordConditions.gd")


# -----------------------------------------------------------------------------
# "No puede ser Barajado": la propia carta (Ianthe: "Este Aliado no puede ser Barajado ni
# convertido"), lo que da un Arma al portador (Garras de Dragón, espada de akmallah, Hatchet:
# "El portador gana 2 de Fuerza y no puede ser Barajado"; nodachi: "Si el portador es de Raza
# Caballero, Guerrero y/o Héroe, gana 2 de Fuerza y no puede ser Barajado") y lo otorgado por un
# efecto (meta "cannot_be_shuffled_until", Sarcófago Impío). Lo consultan
# ActionReturnDiscard.return_to_deck() (con to_top = true, que es como lo llaman los efectos de
# Barajar) y la elección de objetivos de "Barajar" del compilador.
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# "Tu oponente no puede Desterrar cartas de tu Castillo" (Cetro Demoniaco) y "Si el portador está
# en Línea de Defensa los jugadores no pueden Desterrar cartas del Castillo de su oponente ni Botar
# cartas" (nehushtan). 'actor' es quien controla el efecto (-2: el EffectContext en curso; sin
# contexto se lo trata como rival del dueño). Lo consultan ActionMill/EffectController.mill_cards
# (Botar y Desterrar del tope), CardManager.banish_from_deck() (los patrones que Destierran del
# tope a mano), CastleLook y ActionSearch (buscar y Desterrar).
# -----------------------------------------------------------------------------
static func castle_banish_blocked(deck_owner: int, actor: int = -2) -> bool:
	# guardia varega: "no se puede ... Desterrar cartas de los Castillos ..., por efectos" (también el propio).
	if deck_owner >= 0 and RuleState.active("no_castle_exile", deck_owner):
		return true
	actor = _effect_actor(actor)
	if actor == deck_owner:
		return false
	# y vivieron felices: "por el resto del juego, tu oponente no puede Desterrar cartas de tu Castillo por efectos".
	if deck_owner >= 0 and RuleState.active("castle_exile_shield", deck_owner):
		return true
	for e in _castle_lock_sources():
		var t: String = e.text
		if e.pid == deck_owner and "tu oponente no puede desterrar cartas de tu castillo" in t:
			return true
		if e.defending and "desterrar cartas del castillo de su oponente" in t:
			return true
	return false


static func mill_blocked() -> bool:
	"""nehushtan: "...ni Botar cartas" mientras el portador está en Línea de Defensa. Solo Botar por
	efectos (el daño no pasa por aquí). guardia varega: "no se puede Botar ... por efectos"."""
	if RuleState.active("no_effect_mill", 0) or RuleState.active("no_effect_mill", 1):
		return true
	for e in _castle_lock_sources():
		if e.defending and "ni botar cartas" in e.text:
			return true
	return false


# -----------------------------------------------------------------------------
# "[Si controlas cuatro Aliados Jinete,] tu oponente no puede poner cartas en su mano por efectos"
# (Jinete de la Peste). 'pid' es quien recibiría la carta. Robar no cuenta (es otro verbo); lo
# consultan ActionSearch (buscar → mano) y CastleLook (la caja "a tu mano"). Falta: devolver a
# la mano y los patrones viejos que crean la carta en la mano a mano.
# -----------------------------------------------------------------------------
static func hand_by_effects_blocked(pid: int) -> bool:
	var main := CardQuery.main_node()
	if main == null or pid < 0:
		return false
	var opp := 1 - pid
	var rx := RegEx.create_from_string("(?:si controlas (\\w+) aliados ([a-záéíóúñü]+), )?tu oponente no puede poner cartas en su mano por efectos")
	for zone in PlayerSideScript.line_containers(main, opp):
		if not zone:
			continue
		for c in zone.get_children():
			if not is_instance_valid(c) or KeywordManager.is_silenced(c) or CardQuery.controller_of(c) != opp:
				continue
			var m := rx.search(CardQuery.ability_of(c))
			if m == null:
				continue
			if m.get_string(1).is_empty():
				return true
			var need: int = int(m.get_string(1)) if m.get_string(1).is_valid_int() else int(KeywordParser.NUMBERS.get(m.get_string(1), 99))
			var race := m.get_string(2)
			var count := 0
			for ally in KeywordConditions._allies_in_play(main, opp):
				# "Aliados Jinete": los Jinetes no tienen Raza, el grupo es por nombre.
				if KeywordConditions.race_matches(str(ally.get("card_raza")), [race]) \
						or race in str(ally.get("card_name")).to_lower():
					count += 1
			if count >= need:
				return true
	return false


# -----------------------------------------------------------------------------
# "A tu oponente le cuesta un Oro adicional afectar a tus Aliados" (manuel rodriguez, hasta tu
# próximo turno) y "Tu oponente debe pagar un Oro adicional para afectar a tus demás Oros" (Sake).
# Corre para las cartas del rival elegidas como objetivo (CardInteractionModule.await_target /
# await_multi_target): si 'chooser' no puede pagarlo la carta no es elegible; se paga al ceder el
# rival su prioridad (CardInteractionModule._pay_affect_tax). Los efectos masivos
# sin elección no lo cobran.
# -----------------------------------------------------------------------------
const SAKE_TAX_TEXT := "tu oponente debe pagar un oro adicional para afectar a tus demás oros"
static var _ally_affect_tax_until: Dictionary = {}  # pid → último turn_serial en que rige


static func reset_game_state() -> void:
	"""GameManager.start_game(): turn_serial vuelve a 1, los plazos de la partida anterior no sirven."""
	_ally_affect_tax_until.clear()


static func reset_match() -> void:
	"""MatchReset: los plazos son por turn_serial, que vuelve a empezar en cada partida."""
	reset_game_state()


static func grant_ally_affect_tax(pid: int, until_serial: int) -> void:
	_ally_affect_tax_until[pid] = maxi(int(_ally_affect_tax_until.get(pid, -1)), until_serial)


## Verbo de una elección a partir de su texto ("Baraja...", "Destierra..."): "shuffle", "banish" o "".
static func verb_of(prompt: String) -> String:
	var t := prompt.to_lower()
	if "baraj" in t:
		return "shuffle"
	if "destierr" in t or "desterr" in t:
		return "banish"
	return ""


static func affect_tax(card, chooser: int, verb: String = "") -> int:
	if card == null or not is_instance_valid(card) or chooser < 0:
		return 0
	var owner := CardQuery.controller_of(card)
	if owner < 0 or owner == chooser or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
		return 0
	var tax := 0
	# orden siniestra: "hasta tu próximo turno, tu oponente debe pagar un Oro adicional para Barajar y/o
	# Desterrar tus cartas en juego".
	if verb in ["shuffle", "banish"] and RuleState.active("shuffle_banish_tax", owner):
		tax += 1
	var zone = card.get("current_zone")
	if card.get("card_type") == Constants.CardType.ALIADO and zone not in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO] \
			and int(_ally_affect_tax_until.get(owner, -1)) >= GameManager.turn_serial:
		tax += 1
	if zone in [Constants.Zone.RESERVA_ORO, Constants.Zone.ORO_PAGADO]:
		var main := CardQuery.main_node()
		if main:
			for holder in [PlayerSideScript.gold_reserva(main, owner), PlayerSideScript.oro_pagado(main, owner)]:
				if not holder:
					continue
				for g in holder.get_children():
					if g != card and is_instance_valid(g) and not KeywordManager.is_silenced(g) \
							and SAKE_TAX_TEXT in CardQuery.ability_of(g):
						tax += 1
	return tax


static func _effect_actor(actor: int) -> int:
	if actor != -2:
		return actor
	var ctx := EffectContext.current()
	return int(ctx.controller_id) if not ctx.is_empty() else -1


static func _castle_lock_sources() -> Array:
	"""Cartas en juego (y Armas equipadas) con un bloqueo de Castillo: [{text, pid, defending}]."""
	var out: Array = []
	var main := CardQuery.main_node()
	if main == null:
		return out
	for pid in [0, 1]:
		for zone in PlayerSideScript.line_containers(main, pid):
			if not zone:
				continue
			for c in zone.get_children():
				if not is_instance_valid(c):
					continue
				var holders: Array = [c]
				var weapons = c.get("equipped_weapons")
				if weapons is Array:
					holders.append_array(weapons)
				for h in holders:
					if not is_instance_valid(h) or KeywordManager.is_silenced(h):
						continue
					var t := CardQuery.ability_of(h)
					if not ("desterrar cartas de tu castillo" in t or "desterrar cartas del castillo de su oponente" in t):
						continue
					out.append({"text": t, "pid": CardQuery.controller_of(h),
						"defending": h != c and c.get("current_zone") == Constants.Zone.LINEA_DEFENSA})
	return out


static func cannot_be_shuffled(card) -> bool:
	if card == null or not is_instance_valid(card) or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
		return false
	if int(card.get_meta("cannot_be_shuffled_until", -1)) >= GameManager.turn_serial:
		return true
	if not KeywordManager.is_silenced(card):
		for s in KeywordParser.sentences(str(card.get("card_ability"))):
			if s.begins_with("no puede ser barajad") or s.begins_with("este aliado no puede ser barajad"):
				return true
	var weapons = card.get("equipped_weapons")
	if weapons is Array:
		for w in weapons:
			if not is_instance_valid(w) or KeywordManager.is_silenced(w):
				continue
			for s in KeywordParser.sentences(str(w.get("card_ability"))):
				if not "no puede ser barajad" in s:
					continue
				if s.begins_with("el portador"):
					return true
				var m := RegEx.create_from_string("^si (el portador .+?), gana ").search(s)
				if m and KeywordConditions.holds(KeywordParser.parse_condition(m.get_string(1)), card, CardQuery.controller_of(w)):
					return true
	return false


# -----------------------------------------------------------------------------
# shade: "El ataque de tus Aliados no puede ser cancelado este turno." (el
# turno en que entra en juego). Ira: "su ataque no puede ser cancelado".
# -----------------------------------------------------------------------------
static func attack_uncancellable(attacker: Node) -> bool:
	if not is_instance_valid(attacker):
		return false
	if int(attacker.get_meta("attack_uncancellable_turn", -1)) == GameManager.turn_serial:
		return true
	for c in CardQuery.cards_in_play_with(CardQuery.controller_of(attacker), "el ataque de tus aliados no puede ser cancelado este turno"):
		if int(c.get_meta("entered_play_turn", -1)) == GameManager.turn_serial:
			return true
	return false


# -----------------------------------------------------------------------------
# "No puede ser Desterrado" para cartas en juego:
#   - Indesterrable (KeywordManager.has_keyword(): en un Aliado incluye lo que
#     le da su Arma, p.ej. sable corto; "el portador gana ... e Indesterrable"
#     no es del Arma).
#   - Nefandos: "Tus demás Aliados no pueden ser Desterrados".
#   - dulce canasta: "Si está en tu Reserva, los Aliados de coste 1 o menos
#     no pueden ser Desterrados" (los de ambos jugadores).
# -----------------------------------------------------------------------------
static func cannot_be_banished(card) -> bool:
	if card == null or not is_instance_valid(card) or not (card.get("current_zone") in Constants.ZONES_IN_PLAY):
		return false
	if KeywordManager.has_keyword(card, Constants.Keyword.INDESTERRABLE):
		return true
	if card.get("card_type") != Constants.CardType.ALIADO:
		return false
	for c in CardQuery.cards_in_play_with(CardQuery.controller_of(card), "tus demás aliados no pueden ser desterrados"):
		if c != card:
			return true
	if ContinuousEffectManager.cost_at_most(card, 1):
		var main := CardQuery.main_node()
		for pid in [0, 1]:
			var reserva = PlayerSideScript.gold_reserva(main, pid) if main else null
			if not reserva:
				continue
			for g in reserva.get_children():
				if is_instance_valid(g) and not KeywordManager.is_silenced(g) \
						and "si está en tu reserva, los aliados de coste 1 o menos no pueden ser desterrados" in CardQuery.ability_of(g):
					return true
	return false


## Nefandos: "Tus demás Aliados ... hacen daño de combate al Destierro."
static func combat_damage_to_exile(attacker: Node) -> bool:
	if is_instance_valid(attacker) and attacker.get_meta("converted_damage_to_exile", false):
		return true  # Viejo del Saco
	for c in CardQuery.cards_in_play_with(CardQuery.controller_of(attacker), "tus demás aliados no pueden ser desterrados y hacen daño de combate al destierro"):
		if c != attacker:
			return true
	return false


const PAN_BLOCK_TEXT := "tus aliados son indestructibles mientras bloquean"


## Pan de Muerto: los bloqueadores de su controlador ganan Indestructible
## mientras dura el combate.
static func on_blockers_confirmed(blockers: Array) -> void:
	for b in blockers:
		if is_instance_valid(b) and not CardQuery.cards_in_play_with(CardQuery.controller_of(b), PAN_BLOCK_TEXT).is_empty():
			KeywordManager.grant_keyword(b, Constants.Keyword.INDESTRUCTIBLE, null, "combat")


# -----------------------------------------------------------------------------
# nu-galahad: "Tus Armas no pueden ser canceladas." (sus habilidades)
# -----------------------------------------------------------------------------
# Crono Diamante: "La primera habilidad de Oro que utilices cada turno no puede ser cancelada".
# Cuenta activadas y disparadas: ActionPipeline.activate_ability() y la ventana de respuesta de
# las disparadas (TriggerSystem.open_response_window()) anotan cada uso; el primero del turno lleva
# context._first_gold_ability, que StackAnnul.protected_from_cancel() respeta si su controlador
# tiene un Crono Diamante en juego (Reserva u Oro Pagado).
static func note_gold_ability_use(source: Node, controller_id: int) -> bool:
	if source == null or not is_instance_valid(source) or source.get("card_type") != Constants.CardType.ORO:
		return false
	var key := "first_gold_ability:%d" % controller_id
	if UniversalCardParser.turn_registry.was_used(key, 0, GameManager.turn_serial):
		return false
	UniversalCardParser.turn_registry.register(key, 0, GameManager.turn_serial)
	return true


static func first_gold_ability_protected(controller_id: int) -> bool:
	var main := CardQuery.main_node()
	if main == null or controller_id < 0:
		return false
	for holder in [PlayerSideScript.gold_reserva(main, controller_id), PlayerSideScript.oro_pagado(main, controller_id)]:
		if not holder:
			continue
		for g in holder.get_children():
			if is_instance_valid(g) and not KeywordManager.is_silenced(g) \
					and "la primera habilidad de oro que utilices cada turno no puede ser cancelada" in CardQuery.ability_of(g):
				return true
	return false


static func weapon_cancel_protected(source_data: Dictionary, controller_id: int) -> bool:
	if int(source_data.get("tipo", -1)) != Constants.CardType.ARMA:
		return false
	return not CardQuery.cards_in_play_with(controller_id, "tus armas no pueden ser canceladas").is_empty()
