extends RefCounted
## AbilityButtonPatternsA — primer cuarto de los patrones especiales de botones de habilidad
## ACTIVADA de CardInspectionLayer._build_ability_buttons(). Cada patrón es un `if` en try_build()
## que corta en el PRIMER match y devuelve true. CardInspectionLayer llama a los 4 archivos (A, B,
## C, D) en orden, así que el orden de los chequeos importa.
## Aquí: Bernardo O'Higgins, Padre de la Patria, Cetro Demoniaco, quimera voragh (mill), voragh el
## devorador (x2), tenshi Z, dyyavol titán, jinete de la peste, sandraudiga, asmodeus, belcebu,
## cuerno titán, Don de Amma, Tesoro de los Césares, Miguel, Tyet (primera habilidad), Maldición
## Vudú.

var _inspector: CardInspectionLayer


func setup(inspector: CardInspectionLayer) -> void:
	_inspector = inspector


func try_build(ability_lower: String, btn: Button, panel: Control, card_for_glow: Node, captured: Dictionary) -> bool:
	# Maldición Vudú: desde el Cementerio, Desterrarla para Barajar o Desterrar una carta de un
	# Cementerio. Va antes que Espíritu de la Máquina (grupo B), que tiene el mismo final de texto.
	if "desterrarlo de tu cementerio para barajar o desterrar una carta de un cementerio" in ability_lower:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await load("res://scripts/core/effects/triggers/NoePatterns.gd").maldicion_from_cemetery(card_for_glow)
		)
		panel.add_child(btn)
		return true
	# Patrón especial de Bernardo O'Higgins: coste alternativo (barajar un Arma/Aliado Caballero) +
	# elegir entre dos efectos con objetivo (desterrar ≤3 / cancelar habilidad) — no encaja en el
	# sistema genérico de costes/acciones de ActionPipeline (un solo tipo de coste, sin targeting), así
	# que se resuelve aparte.
	var is_bernardo_pattern: bool = ("barajar" in ability_lower and "caballero" in ability_lower
		and ("desterrar" in ability_lower or "cancelar" in ability_lower))

	if is_bernardo_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._bernardo._activate_bernardo_shuffle_removal(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Patrón especial de Padre de la Patria: "genera un Oro para jugar X" es Oro Virtual RESTRINGIDO
	# (GoldManager. restricted_gold_pools), un concepto que ActionPipeline no conoce — se genera
	# directo aquí, sin pasar por el pipeline genérico.
	var is_padre_patria_gold_pattern: bool = ("genera" in ability_lower
		and "para jugar" in ability_lower and "caballero" in ability_lower)
	if is_padre_patria_gold_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			_inspector._search_handler._activate_padre_patria_gold(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Patrón especial de Cetro Demoniaco: "genera un Oro y Destierra cuatro cartas del tope de un
	# Castillo" — Oro SIN restringir + Destierro masivo de tope elegido, ActionPipeline no resuelve
	# acciones compuestas de dos tipos distintos en una sola habilidad.
	var is_cetro_demoniaco_pattern: bool = ("genera un oro y destierra cuatro cartas del tope de un castillo" in ability_lower)
	if is_cetro_demoniaco_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_cetro_demoniaco_gold_and_banish(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Patria Vieja: "En tu Vigilia, si no has puesto Oros en juego este turno, puedes mirar las
	# primeras seis cartas de tu Castillo y poner un Oro de ahí en tu Reserva".
	if "mirar las primeras seis cartas de tu castillo y poner un oro de ahí en tu reserva" in ability_lower:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_patria_vieja_look_six(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Duelo Espacial en el Cementerio: gana "En tu Vigilia, puedes Robar una carta" (una vez por
	# turno).
	if "en tu cementerio" in ability_lower and "gana la habilidad" in ability_lower \
			and "puedes robar una carta" in ability_lower:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_cemetery_granted_draw(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Patrón especial de quimera voragh: "cada jugador Bota tres cartas. Si se Botaron Aliados u Oros,
	# pon en juego una carta de un Cementerio como un Aliado de Fuerza 2 con Furia" — botado por ambos
	# jugadores con seguimiento de tipos (ActionModule.mill no informa tipos en su fallback), condición
	# sobre lo botado y conversión real.
	var is_quimera_voragh_mill_pattern: bool = ("cada jugador bota tres cartas" in ability_lower
		and "pon en juego una carta de un cementerio" in ability_lower)
	if is_quimera_voragh_mill_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_quimera_voragh_mill_and_revive(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Patrón especial de voragh el devorador: "puedes Destruir una de tus cartas para generar un Oro
	# para jugar Aliados" — costo de Destruir con objetivo (propio), efecto de Oro Virtual restringido.
	var is_voragh_devorador_pattern: bool = ("puedes destruir una de tus cartas para generar un oro para jugar aliados" in ability_lower)
	if is_voragh_devorador_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_voragh_devorador_destroy_own_for_gold(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_voragh_devorador_search_pattern: bool = ("busca en un castillo dos cartas y ponlas en el cementerio" in ability_lower)
	if is_voragh_devorador_search_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_voragh_devorador_search_to_cemetery(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_tenshi_z_annul_pattern: bool = ("puedes barajar una carta de tu mano para anular una carta" in ability_lower)
	if is_tenshi_z_annul_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_tenshi_z_shuffle_hand_to_annul(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_dyyavol_titan_pattern: bool = ("roba una carta y descarta una carta" in ability_lower
		and "ignis o tit" in ability_lower)
	if is_dyyavol_titan_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_dyyavol_titan_draw_discard_mill(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_jinete_peste_pattern: bool = ("busca en un castillo dos cartas de distinto nombre y destiérralas" in ability_lower)
	if is_jinete_peste_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_jinete_peste_search_banish_two(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	if "si está en tu destierro, puedes desterrar una carta de tu mano para barajarlo en tu castillo" in ability_lower:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._hand_cementerio_handler._activate_sandraudiga_shuffle_from_exile(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_sandraudiga_pattern: bool = ("puedes pagar un oro para desterrar este y otro aliado sacerdote de tu mano" in ability_lower)
	if is_sandraudiga_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._hand_cementerio_handler._activate_sandraudiga_banish_pair_and_peek(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_asmodeus_pattern: bool = ("genera un oro y destierra hasta dos cartas del fondo de un castillo" in ability_lower)
	if is_asmodeus_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_asmodeus_gold_and_banish_bottom(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_belcebu_pattern: bool = ("destierra tres cartas del fondo de un castillo y gana el control de hasta una carta" in ability_lower)
	if is_belcebu_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_belcebu_banish_bottom_and_steal(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	var is_cuerno_titan_pattern: bool = ("descartar una carta de tu mano para busca una carta titán en tu castillo" in ability_lower
		or "descartar una carta de tu mano para busca una carta titan en tu castillo" in ability_lower)
	if is_cuerno_titan_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_cuerno_titan_discard_search_cost_adjust(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Legión Paladín no tiene botón: EffectController.offer_prevention() la ofrece reactivamente (tag
	# "leave_play") cuando un Aliado propio está por salir del juego.

	# Patrón especial de Don de Amma: "Una vez por turno, puedes Desterrar un Oro con habilidad de tu
	# Reserva. Luego, busca un Oro en tu Castillo y ponlo en tu Reserva." — costo de Desterrar UNA
	# carta elegida entre los Oros-con-habilidad propios en Reserva (no necesariamente esta misma),
	# seguido de una búsqueda que no va a la mano — ActionPipeline no tiene ninguno de los dos
	# conceptos.
	var is_don_de_amma_pattern: bool = ("desterrar un oro" in ability_lower
		and "con habilidad" in ability_lower and "busca un oro" in ability_lower)
	if is_don_de_amma_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_don_de_amma(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Tesoro de los Césares: "Una vez por turno, puedes Barajar una carta de tu mano para nombrar una
	# carta. Esa carta cuesta un Oro adicional el próximo turno." Costo de Barajar (mano → mazo) +
	# nombrar cualquier carta + recargo desde el turno siguiente: ActionPipeline no tiene ninguno de
	# los tres. Depende de que parse_abilities() una la segunda oración a la habilidad anterior (si no,
	# "cuesta un oro adicional" no aparece en raw_text).
	var is_tesoro_cesares_pattern: bool = ("barajar una carta de tu mano" in ability_lower
		and "nombrar una carta" in ability_lower and "cuesta un oro adicional" in ability_lower)
	if is_tesoro_cesares_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_tesoro_cesares_name_tax(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Patrón especial de Miguel: "Una vez en tu turno, juega una carta de tu mano o de un Cementerio
	# reduciendo su coste en un Oro, hasta un mínimo de 0." — elegir entre mano Y Cementerio a la vez,
	# con descuento de -1/piso 0 aplicado solo a esa carta, no es nada que ActionPipeline sepa hacer
	# solo. Reusa GoldManager. play_card completo (fases, portador de Armas, Talismanes) con el mismo
	# mecanismo de descuento puntual que 'Muestra X para reducir el coste' (El Rey y el Verdugo, ya en
	# GoldManager.play_card).
	var is_miguel_pattern: bool = ("juega una carta de tu mano" in ability_lower
		and "cementerio" in ability_lower and "reduciendo su coste" in ability_lower)
	if is_miguel_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._search_handler._activate_miguel_discount_play(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	# Patrón especial de Tyet: "Puedes pagar este Oro para que un Oro pierda su habilidad este turno y
	# muévelo al Oro Pagado." Costo = esta misma carta (CostType.SELF_AS_GOLD, ActionPipeline no lo
	# conoce). Efecto sobre OTRO Oro elegido: silencio temporal (KeywordManager.silence_card(...,
	# "turn"), se autolimpia solo al empezar el próximo turno) + mover a Oro Pagado.
	var is_tyet_pattern: bool = (("pagar este oro" in ability_lower or "puedes pagarlo" in ability_lower)
		and "pierda su habilidad" in ability_lower and "oro pagado" in ability_lower)
	if is_tyet_pattern:
		btn.pressed.connect(func():
			_inspector.close_card_inspection()
			await _inspector._hand_cementerio_handler._activate_tyet_silence_and_pay(card_for_glow, captured)
		)
		panel.add_child(btn)
		return true

	return false
