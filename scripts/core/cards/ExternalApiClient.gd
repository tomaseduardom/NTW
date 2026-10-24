extends Node
## ExternalApiClient — cliente de la API de cartas/mazos de ShadowForge. El frontend
## (shadow-forge-deck.vercel.app) es Angular; el backend es Django/DRF en
## https://iterva.pythonanywhere.com/api.
## CREDENCIALES: la contraseña nunca se guarda (ni en el código ni en disco). La pantalla de login
## (ShadowForgeLogin.gd) la pasa con save_credentials(), queda solo en memoria mientras dura el login
## y se borra al terminar. En disco queda solo el token (user://shadowforge_token.json), que se reusa
## hasta que vence (7 días) o da 401: entonces hay que volver a iniciar sesión.
## El archivo viejo user://shadowforge_credentials.json (contraseña en texto plano) se usa una última
## vez para entrar si no hay token y se borra al arrancar.
## Respuestas: cartas con myl_id, name, cost, damage, ability, race, type, image_url; mazos en
## /api/decks/* (ver cada función).

signal login_succeeded
signal login_failed(reason: String)
signal decks_received(decks: Array)
signal decks_failed(reason: String)
signal cards_received(edicion: String, cards: Array)
signal cards_failed(edicion: String, reason: String)
# ("que te conectes con tu cuenta de shadowforge y salgan tus mazos privados... mazos públicos
# también"): señales nuevas para la pantalla de login real y el buscador de mazos públicos — ver
# ShadowForgeLogin.gd y DeckSelector.gd.
signal public_decks_received(results: Array, count: int)
signal public_decks_failed(reason: String)
signal public_deck_detail_received(deck_data: Dictionary)
signal public_deck_detail_failed(reason: String)
signal profile_received(profile: Dictionary)
signal profile_failed(reason: String)
# ("que el botón mis mazos te muestre los mazos privados y públicos"):
# fetch_my_decks/fetch_public_decks solo traen datos resumidos por mazo (sin "entries") — señales
# separadas de las de mazos públicos para poder distinguir qué llamada resolvió qué, ver
# DeckSelector._resolve_deck_entries.
signal my_deck_detail_received(deck_data: Dictionary)
signal my_deck_detail_failed(reason: String)

const API_BASE: String = "https://iterva.pythonanywhere.com/api"
const CREDENTIALS_PATH: String = "user://shadowforge_credentials.json"
const TOKEN_PATH: String = "user://shadowforge_token.json"

var _token: String = ""
## Solo en memoria, hasta el próximo login() (ver save_credentials()).
var _pending_username: String = ""
var _pending_password: String = ""
var _is_logging_in: bool = false


func _ready() -> void:
	_load_saved_token()
	_migrate_plaintext_credentials()
	print("[ExternalApiClient] Inicializado (token guardado: %s)" % (not _token.is_empty()))


# =============================================================================
# CREDENCIALES Y TOKEN (persistidos en user://, nunca en el repo)
# =============================================================================
func _migrate_plaintext_credentials() -> void:
	"""Versiones anteriores guardaban la contraseña en texto plano: se lee una última vez (para entrar
	si todavía no hay token), se sobrescribe y se borra."""
	if not FileAccess.file_exists(CREDENTIALS_PATH):
		return
	var file = FileAccess.open(CREDENTIALS_PATH, FileAccess.READ)
	var json = JSON.parse_string(file.get_as_text()) if file else null
	if file:
		file.close()
	_wipe_credentials_file()
	if _token.is_empty() and json is Dictionary and str(json.get("username", "")) != "" \
			and str(json.get("password", "")) != "":
		save_credentials(str(json.username), str(json.password))
		login()


func _wipe_credentials_file() -> void:
	if not FileAccess.file_exists(CREDENTIALS_PATH):
		return
	var file = FileAccess.open(CREDENTIALS_PATH, FileAccess.WRITE)
	if file:
		file.store_string("{}")
		file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CREDENTIALS_PATH))
	print("[ExternalApiClient] Se borró el archivo de credenciales en texto plano")


func _load_saved_token() -> void:
	if not FileAccess.file_exists(TOKEN_PATH):
		return
	var file = FileAccess.open(TOKEN_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	if json is Dictionary and String(json.get("token", "")) != "":
		_token = json.token
		print("[ExternalApiClient] Token cargado desde user://shadowforge_token.json")


func _save_token(token: String) -> void:
	_token = token
	var file = FileAccess.open(TOKEN_PATH, FileAccess.WRITE)
	if not file:
		push_error("[ExternalApiClient] No se pudo guardar el token")
		return
	file.store_string(JSON.stringify({"token": token, "saved_at": Time.get_unix_time_from_system()}))
	file.close()
	print("[ExternalApiClient] Token guardado")


func is_authenticated() -> bool:
	return not _token.is_empty()


func save_credentials(username: String, password: String) -> void:
	"""Credenciales para el próximo login() (ShadowForgeLogin.gd). Solo en memoria: login() las usa y
	borra la contraseña al terminar, salga bien o mal."""
	_pending_username = username
	_pending_password = password


func logout() -> void:
	"""Cierra sesión: borra el token guardado y las credenciales en disco,
	limpia el estado en memoria. La próxima llamada autenticada vuelve a
	pedir login (con credenciales vacías, así que falla hasta que el
	jugador inicie sesión de nuevo desde ShadowForgeLogin.gd)."""
	_token = ""
	_remove_token_file()
	save_credentials("", "")
	_wipe_credentials_file()
	print("[ExternalApiClient] Sesión cerrada")


func _remove_token_file() -> void:
	if FileAccess.file_exists(TOKEN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TOKEN_PATH))


# =============================================================================
# LOGIN
# =============================================================================
func login() -> void:
	"""Inicia sesión con las credenciales que pasó save_credentials() (solo en memoria).
	Si ya hay un login en curso, no hace nada — quien llamó login() debe
	escuchar login_succeeded/login_failed (ver _authed_request) en vez de
	asumir que esta llamada en particular resuelve su propia petición.
	Sin contraseña en memoria (p.ej. el token venció): falla y hay que volver a iniciar sesión."""
	if _is_logging_in:
		return

	var username: String = _pending_username
	var password: String = _pending_password
	_pending_password = ""

	if username.is_empty() or password.is_empty():
		var msg = "Inicia sesión en ShadowForge para ver tus mazos"
		push_warning("[ExternalApiClient] %s" % msg)
		emit_signal("login_failed", msg)
		return

	_is_logging_in = true
	var http = HTTPRequest.new()
	add_child(http)
	# Subido de 15s a 30s — ver nota completa en _authed_request (el mismo backend gratuito puede
	# tardar en "despertar").
	http.timeout = 30.0
	var body = JSON.stringify({"username": username, "password": password})
	http.request_completed.connect(_on_login_completed.bind(http))

	var err = http.request(
		API_BASE + "/external/token/",
		["Content-Type: application/json", "Accept: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_is_logging_in = false
		http.queue_free()
		emit_signal("login_failed", "No se pudo conectar (error %d)" % err)


func _on_login_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	_is_logging_in = false

	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("login_failed", "Error de conexión (%d)" % result)
		return

	var json = JSON.parse_string(body.get_string_from_utf8())

	if code != 200 or json == null:
		var msg = "Error HTTP %d" % code
		if json is Dictionary:
			msg = str(json.get("error", json.get("detail", msg)))
		emit_signal("login_failed", msg)
		return

	# El nombre exacto del campo del token no está confirmado — se prueban
	# las variantes más comunes en DRF (token / access / access_token / key).
	var token: String = ""
	if json is Dictionary:
		for key in ["token", "access", "access_token", "key"]:
			if json.has(key) and json[key] is String and not String(json[key]).is_empty():
				token = json[key]
				break

	if token.is_empty():
		push_error("[ExternalApiClient] Login OK pero no se reconoció el campo del token. Respuesta: %s" % JSON.stringify(json))
		emit_signal("login_failed", "Respuesta sin token reconocible (ver Output)")
		return

	_save_token(token)
	print("[ExternalApiClient] Login exitoso")
	emit_signal("login_succeeded")


# =============================================================================
# PETICIÓN GENÉRICA AUTENTICADA (reintenta login una vez si el token venció)
# =============================================================================
func _authed_request(path: String, on_success: Callable, on_failure: Callable, retried: bool = false) -> void:
	if not is_authenticated():
		# Conexiones one-shot: cada llamador espera a que ESTE intento de login
		# resuelva (éxito o fracaso), en vez de encolarse en un array que un
		# login fallido podía vaciar sin avisarle a nadie — ese era el bug:
		# con credenciales vacías, la petición se quedaba colgada para siempre
		# en vez de caer al fallback (ver DeckSelector._load_local_fallback).
		var retry := func(): _authed_request(path, on_success, on_failure, retried)
		var fail := func(reason: String): on_failure.call(reason)
		login_succeeded.connect(retry, CONNECT_ONE_SHOT)
		login_failed.connect(fail, CONNECT_ONE_SHOT)
		if not _is_logging_in:
			login()
		return

	var http = HTTPRequest.new()
	add_child(http)
	# Timeout de 60 s: el backend gratuito de PythonAnywhere puede tardar en "despertar" tras estar
	# inactivo (arquitectura.md §13.15/§13.16). Ver también DeckSelector._resolve_deck_entries().
	http.timeout = 60.0
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()

			if code == 401 and not retried:
				print("[ExternalApiClient] Token vencido (401): hay que volver a iniciar sesión")
				_token = ""
				_remove_token_file()
				var retry := func(): _authed_request(path, on_success, on_failure, true)
				var fail := func(reason: String): on_failure.call(reason)
				login_succeeded.connect(retry, CONNECT_ONE_SHOT)
				login_failed.connect(fail, CONNECT_ONE_SHOT)
				login()
				return

			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				on_failure.call("Error HTTP %d" % code)
				return

			var json = JSON.parse_string(body.get_string_from_utf8())
			if json == null:
				on_failure.call("Respuesta no es JSON válido")
				return

			on_success.call(json)
	)

	var err = http.request(API_BASE + path, ["Authorization: Bearer %s" % _token, "Accept: application/json"])
	if err != OK:
		http.queue_free()
		on_failure.call("No se pudo conectar (error %d)" % err)


# =============================================================================
# MAZOS
# =============================================================================
func fetch_my_decks() -> void:
	"""Mazos propios del jugador logueado (privados y públicos que haya creado): GET /api/decks/my/ →
	{results: [...], count: N} (paginación DRF)."""
	var on_success := func(json):
		var raw_results = json.get("results") if json is Dictionary else null
		var decks: Array = raw_results if raw_results is Array else []
		if not raw_results is Array:
			push_warning("[ExternalApiClient] /decks/my/ respondió sin 'results' (o no es un Array). JSON crudo (primeros 800 chars): %s" % JSON.stringify(json).substr(0, 800))
		emit_signal("decks_received", decks)
	var on_failure := func(reason): emit_signal("decks_failed", reason)
	_authed_request("/decks/my/", on_success, on_failure)


func fetch_my_deck_entries(deck_id: int) -> void:
	"""Uno de TUS mazos completo (con .entries[]): GET /api/decks/my/{id}/, con Bearer
	(_authed_request(), se reautentica si el token venció). Se espera el mismo formato que
	fetch_public_deck_entries() (.entries[].card_detail.myl_id + .quantity, .name)."""
	var on_success := func(json): emit_signal("my_deck_detail_received", json if json is Dictionary else {})
	var on_failure := func(reason): emit_signal("my_deck_detail_failed", reason)
	_authed_request("/decks/my/%d/" % deck_id, on_success, on_failure)


func fetch_public_decks(search: String = "", page: int = 1, formato: String = "", raza: String = "", ordering: String = "recent") -> void:
	"""Busca/lista mazos públicos, paginado: GET
	/api/decks/public/?search=&page=&format=&race=&ordering= → {results: [...], count: N}. No
	requiere login; se manda el Bearer si ya hay uno, como fetch_cards()."""
	var query := PackedStringArray()
	if not search.is_empty():
		query.append("search=" + search.uri_encode())
	if page > 1:
		query.append("page=%d" % page)
	if not formato.is_empty():
		query.append("format=" + formato.uri_encode())
	if not raza.is_empty():
		query.append("race=" + raza.uri_encode())
	if not ordering.is_empty():
		query.append("ordering=" + ordering.uri_encode())
	var qs := "?" + "&".join(query) if not query.is_empty() else ""

	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = 60.0  # ver nota en _authed_request()
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				emit_signal("public_decks_failed", "Error HTTP %d" % code)
				return
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json == null or not json is Dictionary:
				emit_signal("public_decks_failed", "Respuesta no es JSON válido")
				return
			var raw_results = json.get("results")
			if not raw_results is Array:
				push_warning("[ExternalApiClient] /decks/public/ respondió sin 'results' (o no es un Array). JSON crudo (primeros 800 chars): %s" % JSON.stringify(json).substr(0, 800))
			emit_signal("public_decks_received", raw_results if raw_results is Array else [], int(json.get("count", 0)))
	)
	var headers := ["Accept: application/json"]
	if not _token.is_empty():
		headers.append("Authorization: Bearer %s" % _token)
	var err = http.request(API_BASE + "/decks/public/" + qs, headers)
	if err != OK:
		http.queue_free()
		emit_signal("public_decks_failed", "No se pudo conectar (error %d)" % err)


func fetch_public_deck_entries(deck_id: int) -> void:
	"""Trae un mazo público completo (con .entries[] para cargarlo de
	verdad) — GET /api/decks/public/{id}/, ya verificado en producción por
	tools/import_public_deck.ps1 (trae .entries[].card_detail.myl_id +
	.quantity, .name, .owner_username)."""
	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = 60.0  # ver nota en _authed_request()
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				emit_signal("public_deck_detail_failed", "Error HTTP %d" % code)
				return
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json == null or not json is Dictionary:
				emit_signal("public_deck_detail_failed", "Respuesta no es JSON válido")
				return
			emit_signal("public_deck_detail_received", json)
	)
	var headers := ["Accept: application/json"]
	if not _token.is_empty():
		headers.append("Authorization: Bearer %s" % _token)
	var err = http.request(API_BASE + "/decks/public/%d/" % deck_id, headers)
	if err != OK:
		http.queue_free()
		emit_signal("public_deck_detail_failed", "No se pudo conectar (error %d)" % err)


func fetch_my_profile() -> void:
	"""Perfil del usuario logueado (GET /api/auth/me/, AuthService real del
	sitio) — usado por ShadowForgeLogin.gd para mostrar 'conectado como X'."""
	var on_success := func(json): emit_signal("profile_received", json if json is Dictionary else {})
	var on_failure := func(reason): emit_signal("profile_failed", reason)
	_authed_request("/auth/me/", on_success, on_failure)


# =============================================================================
# CARTAS — algunas ediciones (imp, esc) responden sin autenticación; otras (pb, fx) devuelven 0 sin
# token: se manda el Bearer si hay uno.
# =============================================================================
func fetch_cards(edicion: String) -> void:
	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = 30.0
	http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				emit_signal("cards_failed", edicion, "Error HTTP %d" % code)
				return
			var json = JSON.parse_string(body.get_string_from_utf8())
			if json == null or not json is Dictionary:
				emit_signal("cards_failed", edicion, "Respuesta no es JSON válido")
				return
			var cards: Array = json.get("cards", [])
			emit_signal("cards_received", edicion, cards)
	)
	var headers := ["Accept: application/json"]
	if not _token.is_empty():
		headers.append("Authorization: Bearer %s" % _token)
	var err = http.request(API_BASE + "/external/cards/%s/" % edicion, headers)
	if err != OK:
		http.queue_free()
		emit_signal("cards_failed", edicion, "No se pudo conectar (error %d)" % err)
