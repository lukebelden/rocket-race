extends Node
## Online scoreboard client. Ready to hook up to a server later (e.g. a Vercel serverless
## function + database) - until API_URL is filled in it simply reports "offline".
##
## ─── How to connect it later ─────────────────────────────────────────────────────────────
## 1. Deploy an endpoint at  <API_URL>/api/scores  (Vercel: an `api/scores.js` file in the repo)
## 2. Put its base address below, e.g.  const API_URL := "https://rocket-dodge.vercel.app"
## 3. Re-export the game. That's it - submitting and the global list start working.
##
## The endpoint must accept/return JSON:
##   GET  /api/scores?limit=10
##        -> 200  [ {"name": "ACE", "score": 1234, "level": 5}, ... ]   (best first)
##   POST /api/scores   body: {"name": "ACE", "score": 1234, "level": 5}
##        -> 200  {"rank": 12}
## If the game is served from a different domain than the API, the endpoint must also send
## CORS headers (Access-Control-Allow-Origin) so browsers allow the request.
## Server side should validate: name length/characters, plausible score for the level,
## and rate-limit submissions (scores from a browser game can always be faked).

signal top_scores_loaded(rows: Array)
signal top_scores_failed(reason: String)
signal score_submitted(rank: int)
signal score_submit_failed(reason: String)

## Leave empty until the server exists.
const API_URL := ""
const TIMEOUT := 8.0

var _fetch: HTTPRequest
var _submit: HTTPRequest


func _ready() -> void:
	_fetch = HTTPRequest.new()
	_fetch.timeout = TIMEOUT
	_fetch.request_completed.connect(_on_fetch_done)
	add_child(_fetch)
	_submit = HTTPRequest.new()
	_submit.timeout = TIMEOUT
	_submit.request_completed.connect(_on_submit_done)
	add_child(_submit)


func is_configured() -> bool:
	return API_URL != ""


## Ask for the global top scores. Answers with top_scores_loaded or top_scores_failed.
func fetch_top(limit: int = 10) -> void:
	if not is_configured():
		top_scores_failed.emit.call_deferred("offline")
		return
	_fetch.cancel_request()
	var err := _fetch.request("%s/api/scores?limit=%d" % [API_URL, limit])
	if err != OK:
		top_scores_failed.emit("request error %d" % err)


## Send a finished run. Answers with score_submitted or score_submit_failed.
func submit(player_name: String, score: int, level: int) -> void:
	if not is_configured():
		score_submit_failed.emit.call_deferred("offline")
		return
	var body := JSON.stringify({"name": player_name.strip_edges().left(12), "score": score, "level": level})
	var err := _submit.request("%s/api/scores" % API_URL, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body)
	if err != OK:
		score_submit_failed.emit("request error %d" % err)


func _on_fetch_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		top_scores_failed.emit("no connection" if result != HTTPRequest.RESULT_SUCCESS else "server error %d" % code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Array:
		top_scores_loaded.emit(data)
	else:
		top_scores_failed.emit("bad response")


func _on_submit_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		score_submit_failed.emit("no connection" if result != HTTPRequest.RESULT_SUCCESS else "server error %d" % code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	score_submitted.emit(int(data.get("rank", 0)) if data is Dictionary else 0)
