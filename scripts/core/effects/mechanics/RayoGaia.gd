extends RefCounted
## Rayo Gaia: "Solo puedes jugarlo en respuesta que un Aliado fuera a salir del juego por un efecto oponente.
## Destierra un Aliado de coste 2 o menos que controles. Durante tres turnos, puedes utilizar la habilidad de ese
## Aliado desde tu Destierro como si estuviera en juego."
## - Se ofrece desde la mano justo en ese momento (EffectControllerBase, registro de Prevención "rayo gaia"; el Remoto
##   elige por red y el bot al azar, como las demás). No se juega de otra forma (GoldManager.play_card). No previene la
##   salida, salvo que se Destierre justo ese Aliado: entonces el efecto oponente ya no lo encuentra.
## - Las habilidades activadas del Aliado Desterrado se usan desde el Destierro hasta que pasen los tres turnos
##   (CardInspectionLayer.usable_abilities_for; el Remoto por RemotePlayerController._exile_proxies). Las marcas viven en
##   sus datos del Destierro: "_rayo_gaia_pid", "_rayo_gaia_until" y "_usage_key" (cupo de "una vez por turno" estable,
##   ya que esos Nodos se recrean en cada consulta).
## Se usa con load / preload.

const EnterScript = preload("res://scripts/core/effects/mechanics/EnterPatterns.gd")
const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")
const EffectContextScript = preload("res://scripts/core/effects/EffectContext.gd")
const CardQuery = preload("res://scripts/core/effects/mechanics/CardQuery.gd")
const TEXT := "solo puedes jugarlo en respuesta que un aliado fuera a salir del juego por un efecto oponente"

static var _next_key: int = 1


static func reset_match() -> void:
	_next_key = 1


static func is_rayo(text: String) -> bool:
	return TEXT in load("res://scripts/core/cards/CardText.gd").fold(text)


## Cupo de "una vez por turno" de una habilidad activada: el de la carta en el Destierro de Rayo Gaia, o el del Nodo.
static func usage_key(card: Node) -> String:
	var data = card.get("card_data")
	if data is Dictionary and str(data.get("_usage_key", "")) != "":
		return str(data._usage_key)
	return str(card.get_instance_id())


static func usable_from_exile(data: Dictionary, pid: int) -> bool:
	return int(data.get("_rayo_gaia_pid", -1)) == pid and GameManager.turn_serial < int(data.get("_rayo_gaia_until", -1))


static func _own_small_allies(main: Node, pid: int) -> Array:
	return EnterScript._in_play(main, pid, func(c): return c.get("card_type") == Constants.CardType.ALIADO \
		and ContinuousEffectManager.cost_at_most(c, 2))


static func can_use(card: Node) -> bool:
	var main := CardQuery.main_node()
	if not main or not main.get("_gold_manager") or not is_instance_valid(card):
		return false
	var pid: int = int(card.owner_id) if card.get("owner_id") != null else 0
	return main._gold_manager.puede_pagar(PaymentManager.calcular_coste_real(card), Constants.CardType.TALISMAN, "", -1, pid) \
		and not _own_small_allies(main, pid).is_empty()


## Se juega (paga su coste, se resuelve y va al Cementerio). true si Desterró justo al Aliado que iba a salir.
static func use(card: Node, leaving: Node) -> bool:
	var main := CardQuery.main_node()
	if not main or not is_instance_valid(card):
		return false
	var pid: int = int(card.owner_id) if card.get("owner_id") != null else 0
	var name: String = str(card.get("card_name"))
	if not await PlayerSideScript.pay(main, pid, PaymentManager.calcular_coste_real(card), card):
		return false
	var token: int = EffectContextScript.push(card, pid, "talisman")
	var allies := _own_small_allies(main, pid)
	var picked: Node = await EnterScript._pick_from(main, pid, "%s: Destierra un Aliado de coste 2 o menos que controles" % name,
		allies, false)
	var prevented := false
	if is_instance_valid(picked):
		prevented = picked == leaving
		var owner: int = int(picked.owner_id) if picked.get("owner_id") != null else pid
		var ally_name: String = str(picked.get("card_name"))
		await ActionModule.banish([picked], card, true, true)
		# "Desde tu Destierro": solo si quedó en el tuyo (un Aliado rival que controlabas va al de su dueño).
		var exile: Array = CardManager.get_exile(owner)
		if owner == pid and not exile.is_empty() and str(exile[-1].get("nombre", "")) == ally_name:
			exile[-1]["_rayo_gaia_pid"] = pid
			exile[-1]["_rayo_gaia_until"] = GameManager.turn_serial + 3
			exile[-1]["_usage_key"] = "rayo_gaia:%d" % _next_key
			_next_key += 1
			main._update_debug("%s: durante tres turnos puedes usar la habilidad de %s desde tu Destierro" % [name, ally_name])
	EffectContextScript.pop(token)
	if is_instance_valid(card) and PlayerSideScript.hand_cards(main, pid).has(card):
		CardManager.add_to_cemetery(pid, PlayerSideScript.take_from_hand(main, pid, card))
	return prevented
