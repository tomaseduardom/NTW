extends RefCounted
## GoldManagerRestrictions — elegibilidad para jugar una carta: Errante (una copia en juego), "Sólo
## puedes jugar un <Nombre> por turno", Talismanes de respuesta instantánea (Anula/Cancela: Red de
## Plata, Sacrificio Solar), portadores de Arma disponibles y excepciones de fase (Arma/Talismán en
## Guerra de Talismanes, Lobo Sagrado). GoldManager.gd expone con reenvíos de una línea las que se
## usan desde afuera (_get_eligible_weapon_wielders, _player_has_ally_in_play,
## _is_response_only_talisman, has_phase_exception, get_phase_rejection_reason) y las internas de
## play_card() (_errante_violation, _play_limit_violation, _register_play_limit,
## _is_response_only_talisman_data).
## _main es Main; _fix_mojibake() se alcanza vía _main._gold_manager.

const PlayerSideScript = preload("res://scripts/core/game/PlayerSide.gd")

var _main: Node = null


func setup(main: Node) -> void:
	_main = main


func _errante_violation(card: Node) -> bool:
	"""Errante (keyword de Mitos y Leyendas): solo una copia de esta carta en juego a la vez, sea
	quien sea el controlador. Distinto de Única, que limita copias en el MAZO."""
	if not KeywordManager.has_keyword(card, Constants.Keyword.ERRANTE):
		return false
	var card_name: String = card.card_name if card.get("card_name") != null else ""
	if card_name.is_empty():
		return false
	for field in [_main.player_field, _main.player_linea_ataque, _main.player_linea_apoyo, _main.opponent_field, _main.opponent_linea_ataque, _main.opponent_linea_apoyo]:
		if not field:
			continue
		for existing in field.get_children():
			if existing != card and existing.get("card_name") == card_name:
				return true
	return false


func _play_limit_violation(card: Node) -> bool:
	"""'Sólo puedes jugar un <Nombre> por turno' (p.ej. Aaru) — restricción de JUGAR la carta en sí
	(distinta de 'una vez por turno' sobre una habilidad ACTIVADA), por NOMBRE y compartida entre
	todas las copias: si ya jugaste un <Nombre> este turno, no puedes jugar un segundo aunque sea
	una copia distinta. Se registra en UniversalCardParser. turn_registry con un prefijo propio
	('play_limit:') para no compartir namespace con el registro de habilidades ACTIVADAS
	(card_id/ability_index numéricos)."""
	var habilidad: String = card.get("card_ability") if card.get("card_ability") != null else ""
	var lower := habilidad.to_lower()
	if _allies_shown_violation(card, lower):
		return true
	if not _has_play_limit_phrase(lower):
		return false
	var card_name: String = card.card_name if card.get("card_name") != null else ""
	if card_name.is_empty():
		return false
	var name_key: String = "play_limit:%s" % card_name.to_lower()
	return UniversalCardParser.turn_registry.was_used(name_key, 0, GameManager.turn_serial)


func _allies_shown_violation(card: Node, lower: String) -> bool:
	"""Camino del Guerrero: 'Sólo puedes jugar esta carta si controlas y/o muestras de tu mano al
	menos cuatro Aliados' — los que controlas más los Aliados de tu mano (que muestras) deben sumar
	cuatro."""
	if not ("jugar esta carta si controlas y/o muestras de tu mano al menos cuatro aliados" in lower):
		return false
	var pid: int = card.owner_id if card.get("owner_id") != null else 0
	var count := 0
	for container in PlayerSideScript.ally_containers(_main, pid):
		for a in container.get_children():
			if is_instance_valid(a) and a != card and a.get("card_type") == Constants.CardType.ALIADO:
				count += 1
	for h in PlayerSideScript.hand_cards(_main, pid):
		if is_instance_valid(h) and h != card and h.get("card_type") == Constants.CardType.ALIADO:
			count += 1
	return count < 4


func play_limit_message(card: Node) -> String:
	var lower: String = str(card.get("card_ability")).to_lower()
	if _allies_shown_violation(card, lower):
		return "%s: necesitas controlar y/o mostrar de tu mano al menos cuatro Aliados" % card.card_name
	return "Ya jugaste un %s este turno" % card.card_name


func _has_play_limit_phrase(lower: String) -> bool:
	"""'Sólo puedes jugar un <Nombre> por turno' (p.ej. Aaru), su variante en voz pasiva 'Sólo puede
	ser puesto en juego un <Nombre> por turno' (p.ej. La Torre), o la negativa 'no puedes poner en
	juego más de un <Nombre> por turno' (p.ej. rafael) — mismo concepto DAR, tres formas de
	imprimirlo."""
	if "por turno" not in lower:
		return false
	return "solo puedes jugar un" in lower or "sólo puedes jugar un" in lower \
		or "solo puede ser puesto en juego un" in lower or "sólo puede ser puesto en juego un" in lower \
		or "no puedes poner en juego más de un" in lower


func _register_play_limit(card: Node) -> void:
	"""Registra el uso del cupo de 'Sólo puedes jugar un <Nombre> por turno'
	(ver _play_limit_violation()) — llamar solo cuando el juego de la carta
	ya está garantizado (después de todas las validaciones, justo antes de
	colocarla), para no gastar el cupo en un intento que después se cancela
	(sin Oro suficiente, portador cancelado, etc.)."""
	var habilidad: String = card.get("card_ability") if card.get("card_ability") != null else ""
	var lower := habilidad.to_lower()
	if not _has_play_limit_phrase(lower):
		return
	var card_name: String = card.card_name if card.get("card_name") != null else ""
	if card_name.is_empty():
		return
	var name_key: String = "play_limit:%s" % card_name.to_lower()
	UniversalCardParser.turn_registry.register(name_key, 0, GameManager.turn_serial)


func _is_response_only_talisman(card: Node) -> bool:
	"""Detecta Talismanes de velocidad instantánea (DAR): 'Anula un Aliado o
	Tótem...' / 'Anula o cancela la habilidad de una carta...' (p.ej. Red de
	Plata, Sheut, Sacrificio Solar) o 'Puedes jugarlo en respuesta a que tu
	oponente...' explícito (p.ej. Transformación). Busca una ORACIÓN que
	EMPIECE con 'anula'/'cancela'/'puedes jugarlo en respuesta a' — no basta
	con 'anula' en cualquier parte del texto, porque frases de protección
	como 'no puede ser Anulada' o 'esta habilidad no puede ser cancelada'
	contienen la misma palabra pero son lo opuesto (protección de la propia
	carta, no su efecto)."""
	var ability_text: String = card.card_ability if card.get("card_ability") != null else ""
	return _is_response_only_ability_text(ability_text)


func _is_response_only_talisman_data(card_data: Dictionary) -> bool:
	"""Espejo de _is_response_only_talisman() sobre Dictionary (p.ej. play_card_from_cemetery() antes
	de instanciar la carta): misma detección."""
	return _is_response_only_ability_text(str(card_data.get("habilidad", "")))


func _is_response_only_ability_text(ability_text: String) -> bool:
	if ability_text.is_empty():
		return false
	for raw_sentence in ability_text.split("."):
		var sentence: String = raw_sentence.strip_edges().to_lower()
		# "Cancela una habilidad o una carta en juego pierde su habilidad" (Maldición Vudú): la otra
		# opción no es una respuesta.
		if "o una carta en juego pierde su habilidad" in sentence:
			continue
		# Sidhes del Bosque: "Puedes jugarlo en respuesta a que tu oponente fuera a buscar..." es un
		# momento EXTRA (EffectController.offer_sidhes); también se juega normal en tu Vigilia o en Guerra
		# de Talismanes.
		if sentence.begins_with("puedes jugarlo en respuesta a que tu oponente fuera a buscar cartas en un castillo"):
			continue
		if sentence.begins_with("anula") or sentence.begins_with("cancela") \
				or sentence.begins_with("puedes jugarlo en respuesta a"):
			return true
	return false


func _player_has_ally_in_play() -> bool:
	"""¿Hay al menos un Aliado en juego (propio o rival) con espacio para portar otra Arma? Requisito
	para jugar un Arma: sin portador posible, _select_weapon_wielder() quedaría sin candidatos."""
	return not _get_eligible_weapon_wielders().is_empty()


func _get_eligible_weapon_wielders() -> Array:
	"""Aliados en juego (propios o rivales: DAR no restringe el portador salvo que la carta lo diga)
	con espacio para otra Arma (ver _max_weapons_for())."""
	var eligible: Array = []
	for field in [_main.player_field, _main.player_linea_ataque, _main.opponent_field, _main.opponent_linea_ataque]:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			if card.get("card_type") != Constants.CardType.ALIADO:
				continue
			if _ally_weapon_count(card) >= _max_weapons_for(card):
				continue
			eligible.append(card)
	return eligible


func _max_weapons_for(ally: Node, _for_new_weapon: bool = true) -> int:
	"""Cuántas Armas puede portar ESTE Aliado:
	- 1 por defecto;
	- +1 si el propio Aliado dice "puede portar un Arma adicional" (Vinci y Yang, Húsar Cazador);
	- +1 por cada carta en juego de SU controlador (Aliados, Armas, Tótems y Oros) con "Aliados
	pueden portar un Arma adicional" (Levisterio, Patrulla Nocturna);
	- +1 por Carro Szgany del controlador si controla Caballeros, Guerreros o Héroes y este es su
	Aliado de mayor coste.
	Las cartas sin habilidad (silenciadas/convertidas) no cuentan."""
	var ctrl: int = ally.controller_id if ally.get("controller_id") != null else 0
	# "Los Aliados oponentes no pueden portar Armas" (Sariel). DAR (Portar): portar es estar anexada, así
	# que también cuenta para las que ya portaba; quedan sin portador válido y van al Cementerio
	# (GoldManager._enforce_weapon_capacity(), sin Destruirlas).
	for container in ([_main.opponent_field, _main.opponent_linea_ataque, _main.opponent_linea_apoyo] if ctrl == 0
			else [_main.player_field, _main.player_linea_ataque, _main.player_linea_apoyo]):
		if not container:
			continue
		for c in container.get_children():
			if "aliados oponentes no pueden portar armas" in _ability_lower(c):
				return 0
	var total := 1
	var own_text: String = _ability_lower(ally)
	# udug, Los Señalados, Día de los Muertos (Aliados convertidos con la habilidad "No puede portar Armas").
	var own_raw: String = "" if KeywordManager.is_silenced(ally) else str(ally.get("card_ability")).to_lower()
	if "no puede portar armas" in own_raw or "ni portar armas" in own_raw:
		return 0
	if "puede portar un arma adicional" in own_text and not ("aliados pueden portar un arma adicional" in own_text):
		total += 1
	var allies: Array = []
	var sources: Array = []
	var containers: Array = [_main.player_field, _main.player_linea_ataque, _main.player_linea_apoyo,
		_main.player_gold, _main.player_oro_pagado] if ctrl == 0 else [_main.opponent_field,
		_main.opponent_linea_ataque, _main.opponent_linea_apoyo, _main.opponent_gold, _main.opponent_oro_pagado]
	for container in containers:
		if not container:
			continue
		for c in container.get_children():
			if not is_instance_valid(c):
				continue
			sources.append(c)
			if c.get("card_type") == Constants.CardType.ALIADO:
				allies.append(c)
			var weapons = c.get("equipped_weapons")
			if weapons is Array:
				for w in weapons:
					if is_instance_valid(w):
						sources.append(w)
	var has_kgh := false
	var top_cost := -999
	for a in allies:
		var raza: String = _main._gold_manager._fix_mojibake(str(a.get("card_raza") if a.get("card_raza") != null else "")).to_lower()
		if "caballero" in raza or "guerrero" in raza or "héroe" in raza or "heroe" in raza:
			has_kgh = true
		top_cost = maxi(top_cost, int(ContinuousEffectManager.get_modified_cost(a)))
	# Carro Szgany: el Arma adicional es para UN solo Aliado de mayor coste (cualquier raza). Con
	# empate, se la queda el que ya porta más Armas; si ninguno la usa, cualquiera. Si entra uno de
	# mayor coste, el anterior pierde la primera Arma que portaba (_enforce_weapon_capacity).
	var top_ally_ok := false
	if has_kgh and int(ContinuousEffectManager.get_modified_cost(ally)) >= top_cost:
		top_ally_ok = true
		for a in allies:
			if a == ally or int(ContinuousEffectManager.get_modified_cost(a)) < top_cost:
				continue
			var mine: int = _ally_weapon_count(ally)
			var theirs: int = _ally_weapon_count(a)
			# Dos empatados con dos Armas cada uno: solo uno se queda la extra.
			if theirs > mine or (theirs == mine and mine >= 2 and a.get_instance_id() < ally.get_instance_id()):
				top_ally_ok = false
				break
	for s in sources:
		var text: String = _ability_lower(s)
		if text.is_empty():
			continue
		if "aliados pueden portar un arma adicional" in text:
			total += 1
		if "tu aliado de mayor coste puede portar un arma adicional" in text and top_ally_ok:
			total += 1
	return total


func _ability_lower(card: Node) -> String:
	if not is_instance_valid(card) or card.get("is_converted") == true or KeywordManager.is_silenced(card):
		return ""
	var text: String = card.get("card_ability") if card.get("card_ability") != null else ""
	return _main._gold_manager._fix_mojibake(text).to_lower()


func _ally_weapon_count(ally: Node) -> int:
	# equipped_weapons es la lista mantenida por _equip_weapon() — mismo
	# campo que ya usan BernardoAbilityHandler/CardManager/ActionModule, más
	# directo que volver a escanear get_children() a mano.
	var weapons = ally.get("equipped_weapons")
	return weapons.size() if weapons is Array else 0


func _can_play_weapons_in_guerra_talismanes(player_id: int = 0) -> bool:
	"""Detecta 'Puedes jugar Armas en Guerra de Talismanes' (p.ej. Lobo Sagrado) en el propio jugador
	— misma técnica de escaneo-de-texto que _register_talisman_totem_tax, pero como chequeo de
	legalidad puntual en vez de un modificador registrado, porque aquí solo importa el instante de
	jugar el Arma, no algo que deba persistir. 'player_id' (ver arquitectura.md §34): play_card ya
	puede jugarse en nombre del jugador 1, así que el campo a escanear tiene que ser el suyo, no
	siempre el del Anfitrión."""
	var fields: Array = [_main.player_field, _main.player_linea_ataque, _main.player_linea_apoyo] if player_id == 0 \
		else [_main.opponent_field, _main.opponent_linea_ataque, _main.opponent_linea_apoyo]
	for field in fields:
		if not field:
			continue
		for card in field.get_children():
			if not is_instance_valid(card):
				continue
			var ability_text: String = card.get("card_ability") if card.get("card_ability") != null else ""
			if ability_text.is_empty():
				continue
			var lower: String = _main._gold_manager._fix_mojibake(ability_text).to_lower()
			if "jugar armas en guerra de talismanes" in lower:
				return true
	return false


func has_phase_exception(card_type: int, player_id: int = 0) -> bool:
	"""Punto único para las excepciones de fase (Arma tipo Lobo Sagrado + Talismanes en Guerra de
	Talismanes). Llamarlo desde cualquier punto que decida si una carta se puede jugar fuera de
	Vigilia (también CardInteractionModule._on_card_double_clicked())."""
	if GameManager.current_phase != Constants.Phase.GUERRA_TALISMANES:
		return false
	if card_type == Constants.CardType.TALISMAN:
		return true
	if card_type == Constants.CardType.ARMA:
		return _can_play_weapons_in_guerra_talismanes(player_id)
	return false


func get_phase_rejection_reason(card_type: int) -> String:
	"""Motivo específico de por qué ESTA carta no se puede jugar ahora (un Talismán en Guerra de
	Talismanes normalmente sí; un Aliado nunca fuera de Vigilia). Llamar solo cuando ya se decidió
	rechazar (current_phase != VIGILIA and not has_phase_exception(card_type))."""
	var phase := GameManager.current_phase
	if phase == Constants.Phase.GUERRA_TALISMANES:
		match card_type:
			Constants.CardType.ARMA:
				return "Necesitas un efecto en juego (como Lobo Sagrado) para jugar Armas en Guerra de Talismanes"
			Constants.CardType.TALISMAN:
				return "Ese Talismán es de respuesta — solo se juega en respuesta a una carta o habilidad del oponente"
			_:
				return "En Guerra de Talismanes solo se pueden jugar Talismanes (y Armas, si algo lo permite)"
	return "Solo puedes jugar cartas en tu Vigilia o en Guerra de Talismanes (Talismanes/Armas habilitadas)"
