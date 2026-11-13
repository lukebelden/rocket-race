extends Node
## Player profile (autoload "Profile"): guest or account, levels, credits, unlocks, loadout.
##
## Guests play single player only; their progress is saved on this device (user://profile.cfg).
## Accounts live on the server (server/accounts.js) - every change goes through the API, and
## signing up keeps your guest progress. Rules mirror server/progress.js; numbers come from
## res://catalog.json, which the server reads too.

signal changed
## A run/race paid out: {track, xp, credits, level_up_credits, level_before, level_after}
signal rewarded(reward: Dictionary)

const SAVE_PATH := "user://profile.cfg"
const DESKTOP_API := "http://localhost:8080"

var catalog: Dictionary = {}
## "" (not chosen yet), "guest" or "account"
var mode: String = ""
var token: String = ""
var username: String = ""
## {sp: {xp}, mp: {xp}, credits, owned: {ships, mods, designs}, loadout: {character, ship, design, mods}, stats}
var data: Dictionary = {}
## Last reward, shown on the game over screen.
var last_reward: Dictionary = {}


func _ready() -> void:
	var file := FileAccess.open("res://catalog.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			catalog = parsed
	data = new_profile()
	_load()


# --- Rules (same as server/progress.js) ------------------------------------------------

func new_profile() -> Dictionary:
	return {
		"sp": {"xp": 0}, "mp": {"xp": 0}, "credits": 0,
		"owned": {"ships": ["small"], "mods": [], "designs": ["classic"]},
		"loadout": {"character": "duck", "ship": "small", "design": "classic", "mods": []},
		"stats": {"sp_runs": 0, "sp_best": 0, "mp_races": 0, "mp_wins": 0},
	}


func xp_to_next(level: int) -> int:
	return int(catalog["levels"]["first"]) + int(catalog["levels"]["step"]) * (level - 1)


func max_level() -> int:
	return int(catalog["levels"]["max"])


## {level, into, need} for a total XP amount (need = 0 at the max level).
func level_info(xp: int) -> Dictionary:
	var level := 1
	var rem := maxi(xp, 0)
	while level < max_level() and rem >= xp_to_next(level):
		rem -= xp_to_next(level)
		level += 1
	return {"level": level, "into": rem, "need": 0 if level >= max_level() else xp_to_next(level)}


func sp_level() -> int:
	return int(level_info(int(data["sp"]["xp"]))["level"])


func mp_level() -> int:
	return int(level_info(int(data["mp"]["xp"]))["level"])


## The higher of the two levels decides what's unlocked.
func pilot_level() -> int:
	return maxi(sp_level(), mp_level())


func credits() -> int:
	return int(data.get("credits", 0))


func shop_open() -> bool:
	return pilot_level() >= int(catalog.get("shop_level", 2))


func items(kind: String) -> Array:
	return catalog.get(kind, [])


func item(kind: String, id: String) -> Dictionary:
	for it in items(kind):
		if it["id"] == id:
			return it
	return {}


func owns(kind: String, id: String) -> bool:
	return data["owned"][kind].has(id)


func loadout() -> Dictionary:
	return data["loadout"]


func ship() -> Dictionary:
	return item("ships", str(loadout()["ship"]))


func design() -> Dictionary:
	return item("designs", str(loadout()["design"]))


func character() -> String:
	return str(loadout()["character"])


func character_name(id: String) -> String:
	return str(item("characters", id).get("name", id.capitalize()))


func is_guest() -> bool:
	return mode == "guest"


func is_account() -> bool:
	return mode == "account" and token != ""


func display_name() -> String:
	return username if is_account() else "Guest"


func _grant(track: String, xp: int, credit: int) -> Dictionary:
	var before := int(level_info(int(data[track]["xp"]))["level"])
	data[track]["xp"] = int(data[track]["xp"]) + xp
	var after := int(level_info(int(data[track]["xp"]))["level"])
	var bonus := 0
	for lv in range(before + 1, after + 1):
		bonus += int(catalog["rewards"]["level_up_credits"]) * lv
	data["credits"] = credits() + credit + bonus
	return {"track": track, "xp": xp, "credits": credit + bonus, "level_up_credits": bonus,
		"level_before": before, "level_after": after}


func _clean_loadout(want: Dictionary) -> Dictionary:
	var owned: Dictionary = data["owned"]
	var ship_id := str(want.get("ship", "small"))
	if not owned["ships"].has(ship_id):
		ship_id = "small"
	var slots := int(item("ships", ship_id).get("slots", 1))
	var mods: Array = []
	for id in want.get("mods", []):
		if owned["mods"].has(id) and not mods.has(id) and mods.size() < slots:
			mods.append(id)
	var char_id := str(want.get("character", "duck"))
	if item("characters", char_id).is_empty():
		char_id = "duck"
	var design_id := str(want.get("design", "classic"))
	if not owned["designs"].has(design_id):
		design_id = "classic"
	return {"character": char_id, "ship": ship_id, "design": design_id, "mods": mods}


# --- Actions (guest: local; account: server) ----------------------------------------------

func start_guest() -> void:
	mode = "guest"
	token = ""
	username = ""
	_save()
	changed.emit()


## Single-player run over. Returns the reward (also emitted as `rewarded`).
func report_run(score: int, level: int) -> Dictionary:
	if is_account():
		var res := await _api("POST", "/api/run", {"score": score, "level": level})
		if res.has("error"):
			return {}
		_apply_server_profile(res["profile"])
		_reward(res["reward"])
		return res["reward"]
	var r := catalog["rewards"] as Dictionary
	data["stats"]["sp_runs"] = int(data["stats"]["sp_runs"]) + 1
	data["stats"]["sp_best"] = maxi(int(data["stats"]["sp_best"]), score)
	var reward := _grant("sp", score + int(r["xp_per_level_reached"]) * level,
		score / int(r["score_per_credit"]) + int(r["credits_per_level_reached"]) * level)
	_save()
	_reward(reward)
	return reward


## Race rewards come from the server over the race connection (see net.gd).
func apply_race_reward(reward: Dictionary, profile: Dictionary) -> void:
	_apply_server_profile(profile)
	_reward(reward)


## Returns "" on success or an error message.
func buy(kind: String, id: String) -> String:
	if is_account():
		var res := await _api("POST", "/api/buy", {"kind": kind, "id": id})
		if res.has("error"):
			return str(res["error"])
		_apply_server_profile(res["profile"])
		return ""
	var it := item(kind, id)
	if it.is_empty():
		return "That item doesn't exist."
	if owns(kind, id):
		return "You already own that."
	if not shop_open():
		return "The shop opens at level %d." % int(catalog["shop_level"])
	if pilot_level() < int(it["level"]):
		return "Unlocks at level %d." % int(it["level"])
	if credits() < int(it["price"]):
		return "Not enough credits."
	data["credits"] = credits() - int(it["price"])
	data["owned"][kind].append(id)
	_save()
	changed.emit()
	return ""


## Change pilot / ship / design / fitted mods. Anything not owned is dropped.
func set_loadout(changes: Dictionary) -> void:
	var want := (loadout() as Dictionary).duplicate(true)
	want.merge(changes, true)
	data["loadout"] = _clean_loadout(want)
	changed.emit()
	if is_account():
		var res := await _api("POST", "/api/loadout", data["loadout"])
		if not res.has("error"):
			_apply_server_profile(res["profile"])
	else:
		_save()


## Returns "" on success or an error message. Signing up keeps your guest progress.
func signup(user: String, password: String) -> String:
	var guest := data.duplicate(true) if is_guest() else {}
	var res := await _api("POST", "/api/signup", {"username": user, "password": password, "guest": guest}, false)
	return _logged_in(res)


func login(user: String, password: String) -> String:
	var res := await _api("POST", "/api/login", {"username": user, "password": password}, false)
	return _logged_in(res)


func logout() -> void:
	if is_account():
		_api("POST", "/api/logout", {})
	mode = ""
	token = ""
	username = ""
	data = new_profile()
	_save()
	changed.emit()


## Re-fetch the account (on startup). Returns false if the saved login has expired.
func refresh() -> bool:
	if not is_account():
		return true
	var res := await _api("GET", "/api/me", {})
	if res.has("profile"):
		_apply_server_profile(res["profile"])
		return true
	if int(res.get("_status", 0)) == 401:
		logout()
		return false
	return true  # offline: keep the cached copy


func _logged_in(res: Dictionary) -> String:
	if res.has("error"):
		return str(res["error"])
	mode = "account"
	token = str(res["token"])
	_apply_server_profile(res["profile"])
	return ""


func _apply_server_profile(profile: Dictionary) -> void:
	username = str(profile.get("username", username))
	var p := new_profile()
	for key in p.keys():
		if profile.has(key):
			p[key] = profile[key]
	data = p
	_save()
	changed.emit()


func _reward(reward: Dictionary) -> void:
	last_reward = reward
	rewarded.emit(reward)


# --- Server calls -------------------------------------------------------------------------

func api_base() -> String:
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String and origin.begins_with("http"):
			return origin
	return DESKTOP_API


## JSON request; returns the response, or {"error": ...} (with "_status" for HTTP errors).
func _api(method: String, path: String, body: Dictionary, auth := true) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if auth and token != "":
		headers.append("Authorization: Bearer " + token)
	var m := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var err := http.request(api_base() + path, headers, m, "" if method == "GET" else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"error": "Can't reach the server."}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Can't reach the server."}
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:
		return {"error": "Server error.", "_status": result[1]}
	if int(result[1]) >= 400:
		parsed["_status"] = result[1]
		if not parsed.has("error"):
			parsed["error"] = "Server error."
	return parsed


# --- Saving (this device) -------------------------------------------------------------------

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mode = str(cfg.get_value("profile", "mode", ""))
	token = str(cfg.get_value("profile", "token", ""))
	username = str(cfg.get_value("profile", "username", ""))
	var saved = cfg.get_value("profile", "data", {})
	if saved is Dictionary:
		var p := new_profile()
		for key in p.keys():
			if saved.has(key):
				p[key] = saved[key]
		data = p
		data["loadout"] = _clean_loadout(data["loadout"])
	if mode == "account" and token == "":
		mode = ""


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "mode", mode)
	cfg.set_value("profile", "token", token)
	cfg.set_value("profile", "username", username)
	cfg.set_value("profile", "data", data)
	cfg.save(SAVE_PATH)
