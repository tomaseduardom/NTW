extends RefCounted
## ZoneSelfTriggers — disparadores de la propia carta al llegar a una zona que ninguna entrada puntual reconoce:
## "Cuando sea puesto en tu Destierro (por la habilidad de un Aliado (Sacerdote)), <efecto>" (LimitedEventTriggers,
## evento "self_exiled") y "Cuando sea barajado desde tu mano (por la habilidad de un Aliado que controles), <efecto>"
## (Deck170Patterns.on_shuffled_from_hand). El efecto lo resuelve EffectInterpreter sobre un sustituto de la carta (sus
## datos y su zona van en metas, para "puedes jugarlo..."); si no compila, no se hace nada (como antes).
## Se usa con preload. Solo corre en el Anfitrión (quien lo llama ya lo revisa).

const EXILE_RX := "cuando (?:este aliado |esta carta )?sea puesto en tu destierro(?<ally> por la habilidad de un aliado(?: (?<race>[a-z]+))?)?, (?<eff>[^.]+)"
const SHUFFLE_RX := "cuando sea barajado desde tu mano(?<ally> por la habilidad de un aliado que controles)?, (?<eff>[^.]+)"


static func _norm(t) -> String:
	return load("res://scripts/core/effects/triggers/CemeteryTriggers.gd").normalize(str(t))


## Texto del efecto si el disparador le corresponde; "" si no (o si la causa no es la que pide el texto).
static func exile_effect(data: Dictionary, by_ally: bool, ally_race: String) -> String:
	var m := RegEx.create_from_string(EXILE_RX).search(_norm(data.get("habilidad", "")))
	if m == null:
		return ""
	if not m.get_string("ally").is_empty():
		if not by_ally:
			return ""
		if not m.get_string("race").is_empty() and not (m.get_string("race").substr(0, 5) in _norm(ally_race)):
			return ""
	if m.get_string("eff").strip_edges() == "nombra una carta":
		return ""  # brujo de salamanca: el nombre lo usa una regla mientras está en el Destierro (no implementada)
	return m.get_string("eff")


static func shuffle_effect(data: Dictionary, pid: int) -> String:
	var m := RegEx.create_from_string(SHUFFLE_RX).search(_norm(data.get("habilidad", "")))
	if m == null:
		return ""
	if not m.get_string("ally").is_empty():
		var ctx: Dictionary = load("res://scripts/core/effects/EffectContext.gd").current()
		var src = ctx.get("card") if not ctx.is_empty() else null
		if not (src is Node and is_instance_valid(src) and src.get("card_type") == Constants.CardType.ALIADO
				and int(src.get("controller_id") if src.get("controller_id") != null else -1) == pid):
			return ""
	return m.get_string("eff")


## Resuelve 'effect' con el compilador sobre un sustituto de 'data' (de 'owner', en 'zone'). false si no compiló.
static func run(data: Dictionary, owner: int, zone: String, effect: String) -> bool:
	var main := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")
	if not main or effect.is_empty():
		return false
	var proxy: Node = main._create_card(data.duplicate(), false)
	proxy.visible = false
	main.add_child(proxy)
	proxy.owner_id = owner
	proxy.controller_id = owner
	proxy.set_meta("zone_data", data)
	proxy.set_meta("zone", zone)
	var done: bool = await TriggerSystem._effect_interpreter.try_execute(proxy, effect, owner)
	if is_instance_valid(proxy):
		proxy.queue_free()
	return done
