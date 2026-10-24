extends RefCounted
## DamageShields — reemplazos del daño que va a recibir un Castillo, por el turno (RuleState.set_turn_data):
## - puertas grandes y pequeñas: "Reduce a 0 el próximo daño que fueras a recibir este turno" (una vez);
## - arlequín: "Prevén todo el daño a tu Castillo. Tu oponente Destierra tantas cartas de su Castillo como
## daño hayas prevenido" (todo el turno).
## Se consulta en BattleManager._apply_castle_damage() (combate) y DamageManager (daño directo). Se usa
## con preload.

const NEXT_ZERO := "next_damage_zero:%d"
const ARLEQUIN := "arlequin_shield:%d"


static func add_next_zero(player_id: int) -> void:
	RuleState.set_turn_data(NEXT_ZERO % player_id, {"on": true})


static func add_arlequin(player_id: int) -> void:
	RuleState.set_turn_data(ARLEQUIN % player_id, {"on": true})


## Sesión Espiritista: "Por el resto del juego el daño de combate a tu Castillo se reduce en dos".
static func add_permanent_reduction(player_id: int) -> void:
	RuleState.set_until("combat_reduction_2", player_id, 1 << 30)


static func permanent_reduction(player_id: int) -> int:
	return 2 if RuleState.active("combat_reduction_2", player_id) else 0


## Devuelve el daño que queda después de los escudos de 'player_id'.
static func filter(player_id: int, damage: int) -> int:
	if damage <= 0 or player_id < 0:
		return damage
	var main: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")
	if not RuleState.turn_data(ARLEQUIN % player_id).is_empty():
		CardManager.banish_from_deck(1 - player_id, damage, false, player_id)
		if main:
			main._update_debug("arlequín: se previenen %d de daño y tu oponente Destierra %d cartas de su Castillo" % [damage, damage])
			if main.get("_zone_manager"):
				main._zone_manager._update_castillo_counts()
		return 0
	if not RuleState.turn_data(NEXT_ZERO % player_id).is_empty():
		RuleState.set_turn_data(NEXT_ZERO % player_id, {})
		if main:
			main._update_debug("puertas grandes y pequeñas: el daño (%d) se reduce a 0" % damage)
		return 0
	return damage
