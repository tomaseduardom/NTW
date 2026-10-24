extends RefCounted
## RevealedCards — cartas mostradas del Castillo:
## - shuffle_back(): lo mostrado que el efecto no mueve vuelve al Castillo y se Baraja (regla general;
##   las cartas que dicen otra cosa, como sable corto o gurzil, mueven todo ellas mismas).
## - record(): el grupo de cartas mostradas queda en el historial (ActionLogDrawer, enlace "Ver
##   cartas" que abre RevealWindow en modo mostrar). En línea el Anfitrión se lo manda al Remoto
##   ({"op":"reveal_log"}), que lo agrega a su propio historial.
## Se usa con preload / load.

static var _groups: Dictionary = {}  # id -> {title, owner, cards}
static var _next_id: int = 1


static func reset_match() -> void:
	"""MatchReset: los grupos eran del historial de la partida anterior (_next_id sigue subiendo)."""
	_groups = {}


static func record(owner: int, cards: Array, title: String) -> void:
	"""owner: jugador cuyas cartas se mostraron (del lado de este cliente)."""
	if cards.is_empty():
		return
	var shown: Array = []
	for d in cards:
		if d is Dictionary:
			var c: Dictionary = d.duplicate()
			c["esta_oculta"] = false
			shown.append(c)
	_add(owner, shown, title)
	if NetworkClient.room_code != "" and NetworkClient.is_host:
		NetworkClient.send_message({"op": "reveal_log", "owner": 1 - owner, "title": title, "cards": shown})


static func on_network(data: Dictionary) -> void:
	"""Remoto: grupo mandado por el Anfitrión (owner ya viene del lado del Remoto)."""
	var cards: Array = []
	if data.get("cards") is Array:
		for d in data.get("cards"):
			if d is Dictionary:
				cards.append(d)
	_add(int(data.get("owner", 1)), cards.slice(0, 60), str(data.get("title", "")).left(80))


static func group(id: int) -> Dictionary:
	return _groups.get(id, {})


static func shuffle_back(main: Node, owner: int, rest: Array, title: String) -> void:
	"""Devuelve al Castillo de 'owner' las cartas mostradas que quedaron y lo Baraja."""
	var deck: Array = CardManager.get_deck(owner)
	for d in rest:
		if d is Dictionary:
			d["esta_oculta"] = true
			deck.append(d)
	CardManager.shuffle_deck(owner)
	AnimationQueue.queue_shuffle(owner, "Barajar mazo (%s)" % title)
	if main and main.get("_zone_manager"):
		main._zone_manager._update_castillo_counts()


static func _add(owner: int, shown: Array, title: String) -> void:
	if shown.is_empty():
		return
	var id := _next_id
	_next_id += 1
	_groups[id] = {"title": title, "owner": owner, "cards": shown}
	# El historial guarda hasta 500 entradas; los grupos más viejos que eso ya no tienen enlace.
	if _groups.size() > 200:
		_groups.erase(_groups.keys().min())
	var who := "mostraste" if owner == 0 else "tu oponente mostró"
	var log_node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("CombatLog")
	if log_node:
		log_node.add_entry("reveal", "[b]%s[/b]: %s %d carta(s) · [url=reveal:%d][color=#E0BC47]Ver cartas[/color][/url]" % [
			title, who, shown.size(), id], {"reveal_id": id})
