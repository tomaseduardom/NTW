class_name GameSceneLoader
## GameSceneLoader — carga de Main.tscn en segundo plano (la pide MainMenu._ready()). Cambiar de escena
## mientras esa carga sigue en curso cargaba los mismos recursos (fuentes, Card.tscn...) a la vez desde
## dos hilos: algunos preload fallaban y sus scripts quedaban rotos en caché (RemoteMirrorController sin
## compilar: el Remoto se quedaba en la pantalla de carga). Todo cambio de escena desde los menús espera
## aquí a que termine.

const GAME_SCENE := "res://scenes/game/Main.tscn"


static func request() -> void:
	if ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(GAME_SCENE)


static func wait_idle(tree: SceneTree) -> void:
	while ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame


static func change_scene(tree: SceneTree, path: String) -> void:
	"""change_scene_to_file() después de que termine la carga en segundo plano."""
	await wait_idle(tree)
	tree.change_scene_to_file(path)


static func go_to_game(tree: SceneTree) -> void:
	"""Usa la escena ya cargada en segundo plano; si todavía está cargando, espera a que termine en vez
	de empezar de nuevo."""
	await wait_idle(tree)
	if ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_LOADED:
		var packed := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
		if packed:
			tree.change_scene_to_packed(packed)
			return
	tree.change_scene_to_file(GAME_SCENE)
