extends RefCounted
## MatchReset — deja en cero el estado de partida al empezar cada partida (Main._ready(), antes de
## crear los módulos y cargar mazos). Los autoloads sobreviven al cambio de escena: sin esto, lo que
## quedó a medias en la partida anterior (una ventana de prioridad, la cola de animaciones, una
## resolución del Cementerio, modificadores, el historial) seguía vivo en la siguiente.
## - AUTOLOADS: cada variable de script vuelve a su valor inicial (reset_vars()). No se tocan las que
##   guardan objetos (submódulos, nodos, RegEx): se crean una vez en _ready() y siguen sirviendo.
## - SUBMODULES: submódulos de esos autoloads que guardan estado de partida (mismo reset).
## - KEEP: variables que se arman en _ready() y no son estado de partida.
## - Si un autoload llena en _ready() algo que sí es de partida (índices vacíos por tipo), define
##   _after_match_reset() y lo vuelve a armar ahí.
## - STATIC_SCRIPTS: scripts con 'static var' de partida; cada uno tiene su static reset_match().
## Fuera a propósito: configuración (GameSettings), cartas (CardDatabase, CardFactory,
## UniversalCardParser), mazos elegidos antes de la escena (DeckLoader), la sesión de red
## (NetworkClient) y la UI global de carga (MatchLoadingOverlay). Los cachés por texto de carta
## (KeywordParser, KeywordAuras, SilenceAuras._spec_cache...) se conservan: no dependen de la partida.
## Se usa con preload / load.

const AUTOLOADS := ["GameState", "GameManager", "TurnManager", "RuleState", "PriorityManager", "BattleManager",
	"EffectController", "TriggerSystem", "CardEffectSystem", "ActionModule", "AnimationQueue", "CombatLog",
	"ContinuousEffectManager", "KeywordManager", "CardManager", "PaymentManager", "ActionPipeline",
	"DamageManager", "SelectionManager", "UIManager"]

const SUBMODULES := {
	"SelectionManager": ["_dialogs"],
	"TriggerSystem": ["_cemetery_triggers", "_oro_patterns", "_totem_patterns", "_buffs", "_restrictions"],
	"CombatLog": ["_detailed_play"],
	"PaymentManager": ["_exhumar", "_x_cost"],
}

const KEEP := {
	"EffectController": ["_prevention_registry"],  # tabla de prevenciones armada en _ready()
	"UIManager": ["_is_ready"],  # referencias de la UI ya conectadas
	"TriggerSystem._totem_patterns": ["_metropolitan_signal_connected"],  # la señal sigue conectada
}

const STATIC_SCRIPTS := [
	"res://scripts/core/effects/continuous/SilenceAuras.gd",
	"res://scripts/core/cards/KeywordAuras.gd",
	"res://scripts/core/cards/StrengthAuras.gd",
	"res://scripts/core/effects/EffectContext.gd",
	"res://scripts/core/effects/mechanics/ProtectionRules.gd",
	"res://scripts/core/effects/mechanics/RevealedCards.gd",
	"res://scripts/core/effects/triggers/LimitedEventTriggers.gd",
	"res://scripts/core/game/PhaseStartWindow.gd",
	"res://scripts/ui/hud/BoardChoice.gd",
]


static func reset_all() -> int:
	"""Devuelve cuántas variables volvieron a su valor inicial (para el registro y las pruebas)."""
	var root := (Engine.get_main_loop() as SceneTree).root
	var count := 0
	for name in AUTOLOADS:
		var node: Node = root.get_node_or_null(name)
		if not node:
			continue
		count += reset_vars(node, KEEP.get(name, []))
		if node.has_method("_after_match_reset"):
			node._after_match_reset()
		for sub_name in SUBMODULES.get(name, []):
			var sub = node.get(sub_name)
			if sub is Object and is_instance_valid(sub):
				count += reset_vars(sub, KEEP.get("%s.%s" % [name, sub_name], []))
	for path in STATIC_SCRIPTS:
		load(path).reset_match()
	return count


static func reset_vars(obj: Object, keep: Array = []) -> int:
	"""Cada variable de script (que no guarde un objeto) vuelve al valor que tiene una instancia
	recién creada del mismo script: inicializadores y _init(), sin _ready() (Godot no da el valor
	por defecto de las variables no exportadas)."""
	var script: Script = obj.get_script()
	if script == null or not script.can_instantiate():
		return 0
	var fresh: Object = script.new()
	var count := 0
	for prop in script.get_script_property_list():
		if not (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var prop_name: String = prop.name
		if prop_name in keep:
			continue
		var cur = obj.get(prop_name)
		if cur is Object:
			continue
		var def = fresh.get(prop_name)
		if def is Object:
			continue
		# En el lugar: así un Array tipado sigue tipado.
		if cur is Array:
			cur.clear()
			if def is Array:
				cur.append_array(def.duplicate(true))
		elif cur is Dictionary:
			cur.clear()
			if def is Dictionary:
				cur.merge(def.duplicate(true))
		else:
			obj.set(prop_name, def)
		count += 1
	if fresh is Node:
		fresh.free()
	return count
