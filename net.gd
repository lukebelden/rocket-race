extends Node
## Multiplayer connection (autoload "Net"). Talks JSON over a WebSocket to server/index.js.
## Stays alive across scene reloads, so a race can start by reloading the game scene.

signal connected
signal disconnected
signal room_updated(room: Dictionary)
signal error(message: String)
signal race_started(course_seed: int, countdown: float)
signal rival_state(id: int, data: Dictionary)
signal rival_done(kind: String, data: Dictionary)  # kind = "crashed" or "finished"
signal rival_left(id: int)
signal results(ranking: Array)

## Used when the game isn't running in a browser (editor / desktop builds).
## In a browser the game connects back to whatever site served it (same host, /ws).
const DESKTOP_URL := "ws://localhost:8080/ws"
## How often we report our own flight to the room.
const SEND_INTERVAL := 0.1

var _socket: WebSocketPeer
var _was_open := false
var _connecting := false

## Latest room info from the server: {code, you, host, phase, min, max, players: [{id, name, color}]}.
var room: Dictionary = {}
var my_id: int = 0


func server_url() -> String:
	if OS.has_feature("web"):
		var protocol = JavaScriptBridge.eval("window.location.protocol", true)
		var host = JavaScriptBridge.eval("window.location.host", true)
		if host is String and host != "":
			return ("wss://" if protocol == "https:" else "ws://") + host + "/ws"
	return DESKTOP_URL


func is_online() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func in_room() -> bool:
	return is_online() and not room.is_empty()


func is_host() -> bool:
	return in_room() and int(room.get("host", -1)) == my_id


func connect_to_server() -> void:
	if _socket and _socket.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]:
		if is_online():
			connected.emit()
		return
	_socket = WebSocketPeer.new()
	_was_open = false
	_connecting = true
	var err := _socket.connect_to_url(server_url())
	if err != OK:
		_connecting = false
		_socket = null
		error.emit("Can't reach the race server.")


func disconnect_from_server() -> void:
	if _socket:
		_socket.close()
	room = {}


func send(msg: Dictionary) -> void:
	if is_online():
		_socket.send_text(JSON.stringify(msg))


func create_room(player_name: String) -> void:
	send({"t": "create", "name": player_name})


func join_room(code: String, player_name: String) -> void:
	send({"t": "join", "code": code.strip_edges().to_upper(), "name": player_name})


func leave_room() -> void:
	send({"t": "leave"})
	room = {}


func start_race() -> void:
	send({"t": "start"})


## Player info (name, color) for an id in the current room, or {}.
func player(id: int) -> Dictionary:
	for p in room.get("players", []):
		if int(p.get("id", -1)) == id:
			return p
	return {}


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			_connecting = false
			# Multiplayer needs an account: identify ourselves before anything else.
			send({"t": "auth", "token": Profile.token})
			connected.emit()
		while _socket.get_available_packet_count() > 0:
			# A race start reloads the game scene at the end of this frame. Leave any
			# messages after it for next frame, so the new race scene gets them.
			if _on_packet(_socket.get_packet().get_string_from_utf8()) == "start":
				break
	elif state == WebSocketPeer.STATE_CLOSED:
		var had_connection := _was_open
		_socket = null
		room = {}
		_was_open = false
		if _connecting:
			_connecting = false
			error.emit("Can't reach the race server.")
		if had_connection:
			disconnected.emit()


## Handles one server message; returns its type.
func _on_packet(text: String) -> String:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary:
		return ""
	var kind := str(msg.get("t", ""))
	match kind:
		"hello":
			my_id = int(msg.get("id", 0))
		"auth_failed":
			error.emit(str(msg.get("msg", "Log in to play multiplayer.")))
		"reward":
			if msg.get("reward") is Dictionary and msg.get("profile") is Dictionary:
				Profile.apply_race_reward(msg["reward"], msg["profile"])
		"room":
			room = msg
			my_id = int(msg.get("you", my_id))
			room_updated.emit(room)
		"left_room":
			room = {}
			room_updated.emit(room)
		"error":
			error.emit(str(msg.get("msg", "Something went wrong.")))
		"start":
			race_started.emit(int(msg.get("seed", 1)), float(msg.get("countdown", 3)))
		"state":
			rival_state.emit(int(msg.get("id", 0)), msg)
		"crashed", "finished":
			rival_done.emit(str(msg["t"]), msg)
		"left":
			rival_left.emit(int(msg.get("id", 0)))
		"results":
			var ranking = msg.get("ranking", [])
			results.emit(ranking if ranking is Array else [])
	return kind
