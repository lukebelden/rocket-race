extends Node

const Pilots := preload("res://scripts/ui/pilots.gd")
## Player profile (autoload "Profile"): guest or account, levels, credits, unlocks, loadout.
##
## Single player ("sp") and multiplayer ("mp") are separate tracks: each has its own XP and
## level, credits, owned items and hangar loadout, and its shop unlocks follow that mode's
## level. The animal pilot is shared.
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
const TRACK_NAMES := {"sp": "Single Player", "mp": "Multiplayer"}

var catalog: Dictionary = {}
## "" (not chosen yet), "guest" or "account"
var mode: String = ""
var token: String = ""
var username: String = ""
## Account email (for password resets).
var email: String = ""
## {character, sp: track, mp: track, stats}; track = {xp, credits, owned: {ships, mods, designs, finishes, decor},
## loadout: {ship, design, mods, finish, decor}}
var data: Dictionary = {}
## Admin accounts are the dev team: they can pick dev-only pilots (the Penguin).
var is_dev: bool = false
## Restricted pilots (e.g. Titan) an admin has given this account access to.
var granted_pilots: Array = []
## Set for brand-new players: the game shows the "choose your pilot" screen once.
var needs_pilot_pick: bool = false


func _ready() -> void:
	var file := FileAccess.open("res://catalog.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			catalog = parsed
	data = new_profile()
	_load()


# --- Rules (same as server/progress.js) ------------------------------------------------

func new_track() -> Dictionary:
	return {"xp": 0, "credits": 0,
		"owned": {"ships": ["small"], "mods": [], "designs": ["classic"], "finishes": ["none"], "decor": []},
		"loadout": {"ship": "small", "design": "classic", "mods": [], "finish": "none", "decor": []}}


## Shop item kinds: ships, mods, paint (designs), hull finishes, hangar decorations.
const KINDS := ["ships", "mods", "designs", "finishes", "decor"]


## How many decorations fit in the hangar.
func decor_slots() -> int:
	return int(catalog.get("decor_slots", 4))


## This mode's hull finish ({} for none / unknown).
func finish(t: String) -> Dictionary:
	return item("finishes", str(loadout(t).get("finish", "none")))


func new_profile() -> Dictionary:
	return {"character": "falcon", "sp": new_track(), "mp": new_track(),
		"stats": {"sp_runs": 0, "sp_best": 0, "mp_races": 0, "mp_wins": 0, "mp_best": 0}}


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


func track(t: String) -> Dictionary:
	return data[t]


func level(t: String) -> int:
	return int(level_info(int(data[t]["xp"]))["level"])


func sp_level() -> int:
	return level("sp")


func mp_level() -> int:
	return level("mp")


func credits(t: String) -> int:
	return int(data[t].get("credits", 0))


func shop_open(t: String) -> bool:
	return level(t) >= int(catalog.get("shop_level", 2))


func items(kind: String) -> Array:
	return catalog.get(kind, [])


func item(kind: String, id: String) -> Dictionary:
	for it in items(kind):
		if it["id"] == id:
			return it
	return {}


func owns(t: String, kind: String, id: String) -> bool:
	return data[t]["owned"][kind].has(id)


func loadout(t: String) -> Dictionary:
	return data[t]["loadout"]


func ship(t: String) -> Dictionary:
	return item("ships", str(loadout(t)["ship"]))


func design(t: String) -> Dictionary:
	return item("designs", str(loadout(t)["design"]))


func character() -> String:
	return Pilots.id_of(str(data.get("character", Pilots.DEFAULT)))


## Pilots you can pick: everyone gets the normal ones; dev-only pilots only for devs.
func characters() -> Array:
	return items("characters").filter(func(c) -> bool: return can_fly(str(c.get("id", ""))))


## Restricted pilots need an admin account or access given on the admin page.
func can_fly(id: String) -> bool:
	var it := item("characters", id)
	return not it.is_empty() and (is_dev or not bool(it.get("dev", false)) or granted_pilots.has(id))


func character_name(id: String) -> String:
	return str(item("characters", id).get("name", id.capitalize()))


func is_guest() -> bool:
	return mode == "guest"


func is_account() -> bool:
	return mode == "account" and token != ""


func display_name() -> String:
	return username if is_account() else "Guest"


func _grant(t: String, xp: int, credit: int) -> Dictionary:
	var tr: Dictionary = data[t]
	var before := level(t)
	tr["xp"] = int(tr["xp"]) + xp
	var after := level(t)
	var bonus := 0
	for lv in range(before + 1, after + 1):
		bonus += int(catalog["rewards"]["level_up_credits"]) * lv
	tr["credits"] = int(tr["credits"]) + credit + bonus
	return {"track": t, "xp": xp, "credits": credit + bonus, "level_up_credits": bonus,
		"level_before": before, "level_after": after}


func _clean_loadout(tr: Dictionary, want: Dictionary) -> Dictionary:
	var owned: Dictionary = tr["owned"]
	var ship_id := str(want.get("ship", "small"))
	if not owned["ships"].has(ship_id):
		ship_id = "small"
	var slots := int(item("ships", ship_id).get("slots", 1))
	var mods: Array = []
	for id in want.get("mods", []):
		if owned["mods"].has(id) and not mods.has(id) and mods.size() < slots:
			mods.append(id)
	var design_id := str(want.get("design", "classic"))
	if not owned["designs"].has(design_id):
		design_id = "classic"
	var finish_id := str(want.get("finish", "none"))
	if not owned["finishes"].has(finish_id):
		finish_id = "none"
	var decor: Array = []
	for id in want.get("decor", []):
		if owned["decor"].has(id) and not decor.has(id) and decor.size() < decor_slots():
			decor.append(id)
	return {"ship": ship_id, "design": design_id, "mods": mods, "finish": finish_id, "decor": decor}


## Accept a profile from the server or disk (also upgrades the older single-wallet shape).
func _clean_profile(src: Dictionary) -> Dictionary:
	if src.has("owned") and not (src.get("sp", {}) as Dictionary).has("owned"):
		src = {"character": Pilots.id_of(str(src.get("loadout", {}).get("character", Pilots.DEFAULT))),
			"sp": {"xp": src.get("sp", {}).get("xp", 0), "credits": src.get("credits", 0),
				"owned": src["owned"], "loadout": src.get("loadout", {})},
			"mp": {"xp": src.get("mp", {}).get("xp", 0)}, "stats": src.get("stats", {})}
	var p := new_profile()
	if not item("characters", str(src.get("character", ""))).is_empty():
		p["character"] = str(src["character"])
	for t in ["sp", "mp"]:
		var s = src.get(t, {})
		if not s is Dictionary:
			continue
		var tr: Dictionary = p[t]
		tr["xp"] = int(s.get("xp", 0))
		tr["credits"] = int(s.get("credits", 0))
		var owned = s.get("owned", {})
		if owned is Dictionary:
			for kind in KINDS:
				for id in owned.get(kind, []):
					if not item(kind, str(id)).is_empty() and not tr["owned"][kind].has(str(id)):
						tr["owned"][kind].append(str(id))
		tr["loadout"] = _clean_loadout(tr, s.get("loadout", {}) if s.get("loadout") is Dictionary else {})
	var stats = src.get("stats", {})
	if stats is Dictionary:
		for key in p["stats"].keys():
			p["stats"][key] = int(stats.get(key, 0))
	return p


# --- Actions (guest: local; account: server) ----------------------------------------------

func start_guest() -> void:
	mode = "guest"
	token = ""
	username = ""
	needs_pilot_pick = true
	_save()
	changed.emit()


## Single-player run over. Returns the reward (also emitted as `rewarded`).
func report_run(score: int, lvl: int) -> Dictionary:
	if is_account():
		var res := await _api("POST", "/api/run", {"score": score, "level": lvl})
		if res.has("error"):
			return {}
		_apply_server_profile(res["profile"])
		rewarded.emit(res["reward"])
		return res["reward"]
	var r := catalog["rewards"] as Dictionary
	data["stats"]["sp_runs"] = int(data["stats"]["sp_runs"]) + 1
	data["stats"]["sp_best"] = maxi(int(data["stats"]["sp_best"]), score)
	var reward := _grant("sp", score + int(r["xp_per_level_reached"]) * lvl,
		score / int(r["score_per_credit"]) + int(r["credits_per_level_reached"]) * lvl)
	_save()
	changed.emit()
	rewarded.emit(reward)
	return reward


## Race rewards come from the server over the race connection (see net.gd).
func apply_race_reward(reward: Dictionary, profile: Dictionary) -> void:
	_apply_server_profile(profile)
	rewarded.emit(reward)


## Buy in one mode's shop. Returns "" on success or an error message.
func buy(t: String, kind: String, id: String) -> String:
	if is_account():
		var res := await _api("POST", "/api/buy", {"track": t, "kind": kind, "id": id})
		if res.has("error"):
			return str(res["error"])
		_apply_server_profile(res["profile"])
		return ""
	var it := item(kind, id)
	var mode_name: String = TRACK_NAMES[t]
	if it.is_empty():
		return "That item doesn't exist."
	if owns(t, kind, id):
		return "You already own that."
	if not shop_open(t):
		return "The %s shop opens at %s level %d." % [mode_name, mode_name, int(catalog["shop_level"])]
	if level(t) < int(it["level"]):
		return "Unlocks at %s level %d." % [mode_name, int(it["level"])]
	if credits(t) < int(it["price"]):
		return "Not enough credits."
	data[t]["credits"] = credits(t) - int(it["price"])
	data[t]["owned"][kind].append(id)
	_save()
	changed.emit()
	return ""


## Change one mode's ship / design / fitted mods. Anything not owned is dropped.
func set_loadout(t: String, changes: Dictionary) -> void:
	var want := (loadout(t) as Dictionary).duplicate(true)
	want.merge(changes, true)
	data[t]["loadout"] = _clean_loadout(data[t], want)
	changed.emit()
	if is_account():
		var body: Dictionary = (data[t]["loadout"] as Dictionary).duplicate()
		body["track"] = t
		var res := await _api("POST", "/api/loadout", body)
		if not res.has("error"):
			_apply_server_profile(res["profile"])
	else:
		_save()


func set_character(id: String) -> void:
	var it := item("characters", id)
	if it.is_empty() or not can_fly(id):
		return
	data["character"] = id
	changed.emit()
	if is_account():
		var res := await _api("POST", "/api/character", {"character": id})
		if not res.has("error"):
			_apply_server_profile(res["profile"])
	else:
		_save()


## Returns "" on success or an error message. Signing up keeps your guest progress.
## The email is used for password resets.
func signup(user: String, password: String, mail: String) -> String:
	var guest := data.duplicate(true) if is_guest() else {}
	var res := await _api("POST", "/api/signup", {"username": user, "password": password, "email": mail, "guest": guest}, false)
	var err := _logged_in(res)
	if err == "":
		needs_pilot_pick = true
	return err


## Log in with a username or the account's email.
func login(user: String, password: String) -> String:
	var res := await _api("POST", "/api/login", {"username": user, "password": password}, false)
	return _logged_in(res)


func logout() -> void:
	if is_account():
		_api("POST", "/api/logout", {})
	_forget_login()


func _forget_login() -> void:
	is_dev = false
	granted_pilots = []
	mode = ""
	token = ""
	username = ""
	email = ""
	data = new_profile()
	_save()
	changed.emit()


# --- Account security --------------------------------------------------------------------

## Email a 6-digit reset code to the account (username or email). The server answers the
## same whether or not the account exists. Returns "" or an error (e.g. too many tries).
func forgot_password(login_name: String) -> String:
	var res := await _api("POST", "/api/forgot", {"login": login_name}, false)
	return str(res.get("error", ""))


## Set a new password with the emailed code; logs you in. Returns "" or an error.
func reset_password(login_name: String, code: String, password: String) -> String:
	var res := await _api("POST", "/api/reset", {"login": login_name, "code": code, "password": password}, false)
	return _logged_in(res)


## Other devices get signed out; this one stays logged in. Returns "" or an error.
func change_password(current: String, password: String) -> String:
	var res := await _api("POST", "/api/account/password", {"current": current, "password": password})
	if res.has("error"):
		return str(res["error"])
	token = str(res.get("token", token))
	_apply_server_profile(res["profile"])
	return ""


func change_email(password: String, mail: String) -> String:
	var res := await _api("POST", "/api/account/email", {"password": password, "email": mail})
	if res.has("error"):
		return str(res["error"])
	_apply_server_profile(res["profile"])
	return ""


## Deletes the account for good (needs the password), then logs out. Returns "" or an error.
func delete_account(password: String) -> String:
	var res := await _api("POST", "/api/account/delete", {"password": password})
	if res.has("error"):
		return str(res["error"])
	_forget_login()
	return ""


## Problem report: category "bug", "player", "suggestion" or "other". Guests can report too.
func send_report(category: String, message: String, target: String) -> String:
	var platform := "%s %s · %dx%d" % [OS.get_name(), "web" if OS.has_feature("web") else "app",
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	var res := await _api("POST", "/api/report", {"category": category, "message": message,
		"target": target, "platform": platform}, is_account())
	return str(res.get("error", ""))


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


## Global top pilots: mode "sp" (best score) or "mp" (win rate). {rows} or {error}.
func leaderboard(board: String) -> Dictionary:
	return await _api("GET", "/api/leaderboard?mode=" + board, {}, false)


func _logged_in(res: Dictionary) -> String:
	if res.has("error"):
		return str(res["error"])
	mode = "account"
	token = str(res["token"])
	_apply_server_profile(res["profile"])
	return ""


func _apply_server_profile(profile: Dictionary) -> void:
	username = str(profile.get("username", username))
	email = str(profile.get("email", email))
	is_dev = bool(profile.get("admin", false))
	granted_pilots = profile.get("pilots", []) if profile.get("pilots") is Array else []
	data = _clean_profile(profile)
	_save()
	changed.emit()


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
	email = str(cfg.get_value("profile", "email", ""))
	var saved = cfg.get_value("profile", "data", {})
	if saved is Dictionary:
		data = _clean_profile(saved)
	if mode == "account" and token == "":
		mode = ""


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "mode", mode)
	cfg.set_value("profile", "token", token)
	cfg.set_value("profile", "username", username)
	cfg.set_value("profile", "email", email)
	cfg.set_value("profile", "data", data)
	cfg.save(SAVE_PATH)
