extends Node2D
## Rocket Race: launch from Earth, fly past the planets, dodge the asteroids.

const Obstacle := preload("res://obstacle.gd")
const Station := preload("res://station.gd")
const Rocket := preload("res://rocket.gd")
const PlanetNode := preload("res://planet.gd")
const StarLayer := preload("res://star_layer.gd")
const ScoreboardService := preload("res://scoreboard_service.gd")
const ModInfo := preload("res://mods.gd")
const ModIcon := preload("res://mod_icon.gd")
## How many of your best runs the local scoreboard keeps.
const LOCAL_RUNS_KEPT := 8
const SAVE_PATH := "user://save.cfg"

## MENU -> READY (on the launch pad, waiting for Space/tap) -> INTRO (liftoff) -> PLAYING
## -> (DOCKED at a station, then back to PLAYING) -> OVER
enum State { MENU, READY, INTRO, PLAYING, DOCKED, OVER }
enum Difficulty { EASY, NORMAL, HARD }

## [spawn interval multiplier, fall speed multiplier] per difficulty.
const DIFFICULTY_TUNING := {
	Difficulty.EASY: [1.4, 0.75],
	Difficulty.NORMAL: [1.0, 1.0],
	Difficulty.HARD: [0.7, 1.3],
}

## Seconds spent flying past each planet before the next level (at normal speed;
## boosting gets you through it sooner).
const LEVEL_DURATION := 26.0
## Forward speed while boosting (1.0 = normal) and how quickly speed eases in/out (per second).
const FORWARD_BOOST := 1.8
const FORWARD_EASE := 2.5
## Launch intro length (liftoff, climb through the sky, into space).
const INTRO_DURATION := 3.6

## One entry per level, in order. After the last one, levels continue as "Deep Space".
const PLANETS := [
	{"name": "The Moon", "color": Color(0.78, 0.78, 0.8), "rock": Color(0.5, 0.5, 0.53), "style": "craters", "radius": 150.0},
	{"name": "Mars", "color": Color(0.86, 0.42, 0.24), "rock": Color(0.62, 0.32, 0.22), "style": "polar", "radius": 165.0},
	{"name": "Jupiter", "color": Color(0.86, 0.72, 0.54), "rock": Color(0.6, 0.5, 0.4), "style": "bands", "radius": 250.0, "spot": Color(0.78, 0.33, 0.22)},
	{"name": "Saturn", "color": Color(0.92, 0.82, 0.56), "rock": Color(0.62, 0.56, 0.4), "style": "rings", "radius": 190.0},
	{"name": "Uranus", "color": Color(0.56, 0.86, 0.9), "rock": Color(0.42, 0.6, 0.66), "style": "plain", "radius": 175.0},
	{"name": "Neptune", "color": Color(0.26, 0.42, 0.92), "rock": Color(0.34, 0.4, 0.62), "style": "bands", "radius": 175.0, "spot": Color(0.1, 0.16, 0.45)},
]

const STATION_SPEED := 110.0
## Hull repaired when docking at a station.
const STATION_REPAIR := 0.25
## Nav beacon scale: how many metres one screen pixel represents.
const METERS_PER_PIXEL := 6.0
const INVULNERABLE_TIME := 1.3

## Seconds each rotating tip stays up, and how long an urgent (context) tip stays up.
const TIP_TIME := 8.0
const URGENT_TIP_TIME := 9.0

const SKY_BLUE := Color(0.36, 0.62, 0.95)
const SPACE_DARK := Color(0.03, 0.03, 0.08)

@export var start_spawn_interval: float = 0.95
@export var min_spawn_interval: float = 0.25
@export var start_fall_speed: float = 220.0

## Saved to disk (user://save.cfg), so they survive closing the game/page.
static var best_score: float = 0.0
static var difficulty: Difficulty = Difficulty.NORMAL
## Your best runs on this device: [{score, level, date}], best first. Saved to disk.
static var local_runs: Array = []
## Set by "Play Again" so the reloaded scene skips the menu.
static var skip_menu: bool = false

var state: State = State.MENU
var score: float = 0.0
var level: int = 1
var level_time: float = 0.0
var spawn_timer: float = 0.0
var intro_time: float = 0.0
var ready_time: float = 0.0  # seconds spent waiting on the launch pad
var smoke: Array[Vector4] = []  # x, y (relative to ground), x velocity, age
var clock: float = 0.0

# Background: scrolling star/nebula layers and the current planet are separate nodes that
# draw once and then just move (much cheaper than redrawing everything every frame).
var bg_layers: Array = []
var planet_node: Node2D
var _planet_level: int = 0
## Current forward flight speed: 1.0 normally, up to FORWARD_BOOST while boosting.
var forward_speed: float = 1.0

# Ship computer tips (bottom right).
var _tip_index: int = -1
var _tip_timer: float = 0.0
var _tips_triggered: Dictionary = {}  # context tips already shown this run
var _tip_tween: Tween

# Ship modifications (this run only). Two slots; "" = empty.
var mods: Array[String] = ["", ""]
var hull_max: float = 1.0  # 1.0 = 100%; Reinforced Hull raises it
var missile_ammo: int = 0
var missile_cooldown: float = 0.0
var missiles: Array[Dictionary] = []  # {pos, vel, target, age}
var missile_button: TouchScreenButton
var radar_overlay: Control
var _radar_had_blips: bool = false
# Station docking menu.
var _dock_station: Area2D = null
var _dock_step: String = ""  # "service" -> "mod" -> "replace"
var _offer: Array[String] = []
var _pending_mod: String = ""
var _mod_panel_key: String = ""  # what the mod panel currently shows (redraw only on change)
var _last_space: float = -1.0
var _drew_dynamic: bool = false
# Last values shown on the HUD, so labels are only touched when something changes.
var _shown_score: int = -1
var _shown_level: int = -1
var glow_tex: GradientTexture2D
var shade_tex: GradientTexture2D
## Detached booster pods tumbling away: {pos, vel, rot, spin, age}.
var pods: Array[Dictionary] = []
## Level number that already got its refuel station (one per qualifying level).
var station_level: int = 0
var boost_button: TouchScreenButton
var _toast_tween: Tween

## Hull integrity (ship health): 1.0 = 100%. Asteroids damage it; stations repair it.
var hull: float = 1.0
var invulnerable: float = 0.0  # seconds of hit recovery left (ship blinks)
var shake: float = 0.0  # screen shake time left
var fragments: Array[Dictionary] = []  # asteroid chunks / impact flashes
var station_node: Area2D = null
var station_docked: bool = false
## Phones/tablets (native or in a mobile browser) get touch hints.
var touch_ui: bool = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

@onready var rocket: Area2D = $Rocket
@onready var obstacles: Node2D = $Obstacles
@onready var score_label: Label = $UI/Root/ScoreLabel
@onready var level_label: Label = $UI/Root/LevelLabel
@onready var level_banner: Label = $UI/Root/LevelBanner
@onready var launch_prompt: Label = $UI/Root/LaunchPrompt
@onready var tip_panel: PanelContainer = $UI/Root/TipPanel
@onready var tip_title: Label = $UI/Root/TipPanel/VBox/TipTitle
@onready var tip_text: Label = $UI/Root/TipPanel/VBox/TipText
@onready var cockpit: Control = $UI/Root/Cockpit
@onready var dashboard: GridContainer = $UI/Root/Dashboard
@onready var caution_light: Control = $UI/Root/Dashboard/CautionBox/CautionLight
@onready var caution_label: Label = $UI/Root/Dashboard/CautionBox/CautionLabel
@onready var fuel_label: Label = $UI/Root/Dashboard/FuelBox/FuelLabel
@onready var boost_bar: ProgressBar = $UI/Root/Dashboard/FuelBox/BoostBar
@onready var hull_label: Label = $UI/Root/Dashboard/HullBox/HullLabel
@onready var hull_bar: ProgressBar = $UI/Root/Dashboard/HullBox/HullBar
@onready var nav_title: Label = $UI/Root/Dashboard/NavBox/NavTitle
@onready var nav_value: Label = $UI/Root/Dashboard/NavBox/NavValue
@onready var toast_label: Label = $UI/Root/ToastLabel

@onready var menu: Control = $UI/Root/Menu
@onready var best_label: Label = $UI/Root/Menu/Panel/VBox/BestLabel
@onready var start_button: Button = $UI/Root/Menu/Panel/VBox/StartButton
@onready var settings_button: Button = $UI/Root/Menu/Panel/VBox/SettingsButton
@onready var quit_button: Button = $UI/Root/Menu/Panel/VBox/QuitButton
@onready var hint_label: Label = $UI/Root/Menu/Panel/VBox/HintLabel

@onready var scoreboard_button: Button = $UI/Root/Menu/Panel/VBox/ScoreboardButton
@onready var scoreboard: Control = $UI/Root/Scoreboard
@onready var online_caution: PanelContainer = $UI/Root/Scoreboard/Panel/VBox/OnlineCaution
@onready var online_lamp: Control = $UI/Root/Scoreboard/Panel/VBox/OnlineCaution/HBox/CautionLamp
@onready var online_status: Label = $UI/Root/Scoreboard/Panel/VBox/OnlineCaution/HBox/OnlineStatus
@onready var online_list: GridContainer = $UI/Root/Scoreboard/Panel/VBox/OnlineList
@onready var local_list: GridContainer = $UI/Root/Scoreboard/Panel/VBox/LocalList
@onready var scoreboard_back: Button = $UI/Root/Scoreboard/Panel/VBox/BackButton
var scoreboard_service: Node

@onready var settings: Control = $UI/Root/Settings
@onready var difficulty_option: OptionButton = $UI/Root/Settings/Panel/VBox/DifficultyRow/DifficultyOption
@onready var fullscreen_check: CheckButton = $UI/Root/Settings/Panel/VBox/FullscreenCheck
@onready var reset_button: Button = $UI/Root/Settings/Panel/VBox/ResetButton
@onready var back_button: Button = $UI/Root/Settings/Panel/VBox/BackButton

@onready var game_over: Control = $UI/Root/GameOver
@onready var result_label: Label = $UI/Root/GameOver/Panel/VBox/ResultLabel
@onready var game_over_title: Label = $UI/Root/GameOver/Panel/VBox/Title

@onready var mod_panel: PanelContainer = $UI/Root/ModPanel
@onready var mod_slots: Array = [$UI/Root/ModPanel/VBox/Slot1, $UI/Root/ModPanel/VBox/Slot2]
@onready var station_menu: Control = $UI/Root/StationMenu
@onready var station_title: Label = $UI/Root/StationMenu/Panel/VBox/Title
@onready var station_subtitle: Label = $UI/Root/StationMenu/Panel/VBox/Subtitle
@onready var station_options: HBoxContainer = $UI/Root/StationMenu/Panel/VBox/Options
@onready var station_footer: Button = $UI/Root/StationMenu/Panel/VBox/Footer
@onready var play_again_button: Button = $UI/Root/GameOver/Panel/VBox/PlayAgainButton
@onready var menu_button: Button = $UI/Root/GameOver/Panel/VBox/MenuButton


func _ready() -> void:
	randomize()
	Obstacle.world_speed = 1.0  # static: reset in case a previous run ended mid-boost
	_make_textures()
	_make_background()
	_bake_asteroid_atlas()  # runs over the next couple of frames, while the menu is up
	_load_save()
	_setup_boost_input()
	_make_boost_button()
	_make_missile_button()
	_make_radar_overlay()
	station_footer.pressed.connect(_on_station_footer)
	_update_layout()
	get_window().size_changed.connect(_update_layout)
	rocket.booster_lost.connect(_on_booster_lost)
	fuel_label.text = "BOOST FUEL" if touch_ui else "BOOST FUEL  [W / Shift]"
	dashboard.visible = false

	var size := get_viewport_rect().size
	rocket.position = Vector2(size.x / 2.0, size.y - rocket.bottom_gap)
	rocket.area_entered.connect(_on_rocket_hit)

	# Menu
	start_button.pressed.connect(_go_to_pad)
	scoreboard_button.pressed.connect(_open_scoreboard)
	scoreboard_back.pressed.connect(_show_menu)
	scoreboard_service = ScoreboardService.new()
	add_child(scoreboard_service)
	scoreboard_service.top_scores_loaded.connect(_on_online_scores)
	scoreboard_service.top_scores_failed.connect(_on_online_failed)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	# A web page can't close its own tab, so Quit would only freeze the game there.
	quit_button.visible = not OS.has_feature("web")
	hint_label.text = ("Hold and drag to steer\nHold BOOST to fly faster" if touch_ui
		else "Move: Left / Right or A / D\nBoost: W or Shift  ·  Missile: Space")

	# Settings
	difficulty_option.add_item("Easy", Difficulty.EASY)
	difficulty_option.add_item("Normal", Difficulty.NORMAL)
	difficulty_option.add_item("Hard", Difficulty.HARD)
	difficulty_option.select(difficulty_option.get_item_index(difficulty))
	difficulty_option.item_selected.connect(_on_difficulty_selected)
	fullscreen_check.button_pressed = _is_fullscreen()
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_show_menu)

	# Game over
	play_again_button.pressed.connect(_on_play_again)
	menu_button.pressed.connect(func() -> void: get_tree().reload_current_scene())

	level_banner.visible = false
	launch_prompt.visible = false
	if skip_menu:
		skip_menu = false
		_show_menu()
		_go_to_pad()
	else:
		_show_menu()


func _process(delta: float) -> void:
	clock += delta
	_update_smoke(delta)
	_update_pods(delta)
	_update_fragments(delta)
	_update_damage_effects(delta)
	_update_background()
	_update_missiles(delta)
	rocket.missile_count = missile_ammo  # missiles shown on the rocket's launch rails
	_update_mod_panel()
	_update_radar()
	if state == State.READY or state == State.PLAYING or state == State.DOCKED or state == State.OVER:
		_update_dashboard()

	match state:
		State.READY:
			ready_time += delta
			launch_prompt.modulate.a = 0.55 + 0.45 * absf(sin(clock * 3.0))
		State.INTRO:
			_update_intro(delta)
		State.PLAYING:
			_update_playing(delta)

	_update_tips(delta)

	# Only redraw this node's own layer (Earth, clouds, smoke, debris) while something there
	# is actually moving, plus one final frame to clear it.
	var dynamic := state == State.INTRO or not smoke.is_empty() or not fragments.is_empty() \
		or not pods.is_empty() or not missiles.is_empty()
	if dynamic or _drew_dynamic:
		queue_redraw()
	_drew_dynamic = dynamic


func _unhandled_input(event: InputEvent) -> void:
	# Missile Pod mod: Space fires.
	if state == State.PLAYING and event.is_action_pressed("missile"):
		get_viewport().set_input_as_handled()
		_fire_missile()
		return
	# On the launch pad: Space (or a tap/click) launches when the player is ready.
	if state != State.READY or ready_time < 0.25:
		return
	var key_launch: bool = event is InputEventKey and event.pressed and not event.echo \
		and (event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_ENTER)
	var touch_launch: bool = event is InputEventScreenTouch and event.pressed
	if key_launch or touch_launch:
		get_viewport().set_input_as_handled()
		_launch()


## Use a tall base resolution on portrait screens (phones) so things aren't tiny.
func _update_layout() -> void:
	var window := get_window()
	var portrait := window.size.y > window.size.x
	window.content_scale_size = Vector2i(648, 1152) if portrait else Vector2i(1152, 648)

	# Cockpit console: one row of instruments on wide screens, two rows on phones.
	var console_height := 118.0 if portrait else 70.0
	cockpit.dash_height = console_height
	dashboard.columns = 2 if portrait else 4
	dashboard.offset_top = -console_height + 14.0
	rocket.bottom_gap = console_height + 65.0
	_position_boost_button()
	_position_tip_panel(console_height)
	# Ship mods panel mirrors the tips panel on the left side.
	mod_panel.offset_bottom = tip_panel.offset_bottom
	mod_panel.offset_top = mod_panel.offset_bottom - 1.0
	mod_panel.offset_right = mod_panel.offset_left + (230.0 if portrait else 250.0)
	for layer in bg_layers:
		layer.build(get_viewport_rect().size)
	_planet_level = 0  # re-place the planet for the new size
	queue_redraw()


# --- Screens -----------------------------------------------------------------

func _show_menu() -> void:
	state = State.MENU
	rocket.active = false
	rocket.flame_on = false
	best_label.text = "Best: %d" % int(best_score)
	score_label.visible = false
	level_label.visible = false
	dashboard.visible = false
	boost_button.visible = false
	missile_button.visible = false
	station_menu.visible = false
	settings.visible = false
	scoreboard.visible = false
	game_over.visible = false
	launch_prompt.visible = false
	menu.visible = true
	start_button.grab_focus()
	queue_redraw()


func _open_scoreboard() -> void:
	menu.visible = false
	scoreboard.visible = true
	scoreboard_back.grab_focus()
	_fill_local_scores()
	# Global list: asks the online service (reports "offline" until a server is hooked up).
	online_list.visible = false
	if scoreboard_service.is_configured():
		online_lamp.on = false
		_set_online_status("Connecting to scoreboard server…", Color(0.9, 0.85, 0.5))
	scoreboard_service.fetch_top(8)


func _fill_local_scores() -> void:
	_clear_grid(local_list)
	if local_runs.is_empty():
		_grid_row(local_list, ["", "No runs yet. Go fly!", "", ""], Color(0.65, 0.68, 0.75))
		return
	_grid_row(local_list, ["#", "SCORE", "REACHED", "DATE"], Color(0.55, 0.6, 0.7))
	for i in local_runs.size():
		var run: Dictionary = local_runs[i]
		var lvl := int(run.get("level", 1))
		var color := Color(1, 0.85, 0.45) if i == 0 else Color(0.9, 0.92, 1)
		_grid_row(local_list, ["%d" % (i + 1), "%d" % int(run.get("score", 0)),
			"Lvl %d · %s" % [lvl, _planet(lvl)["name"]], str(run.get("date", ""))], color)


func _on_online_scores(rows: Array) -> void:
	_set_online_status("ONLINE · Global top pilots", Color(0.45, 1, 0.6))
	online_lamp.on = false
	_clear_grid(online_list)
	_grid_row(online_list, ["#", "NAME", "SCORE", "LEVEL"], Color(0.55, 0.6, 0.7))
	for i in rows.size():
		var row = rows[i]
		if row is Dictionary:
			_grid_row(online_list, ["%d" % (i + 1), str(row.get("name", "?")).left(12),
				"%d" % int(row.get("score", 0)), "Lvl %d" % int(row.get("level", 1))], Color(0.9, 0.92, 1))
	online_list.visible = true


## Online scoreboard not available: blinking caution lamp + notice, while your local runs
## still show below.
func _on_online_failed(reason: String) -> void:
	online_lamp.on = true
	if reason == "offline":
		_set_online_status("CAUTION: Online scoreboard unavailable at this time.\nGlobal rankings are coming soon. Your own best runs are below.", Color(1, 0.8, 0.45))
	else:
		_set_online_status("CAUTION: Can't reach the scoreboard server right now (%s).\nPlease try again later." % reason, Color(1, 0.6, 0.45))
	online_list.visible = false


func _set_online_status(text: String, color: Color) -> void:
	online_status.text = text
	online_status.add_theme_color_override("font_color", color)


func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


func _grid_row(grid: GridContainer, cells: Array, color: Color) -> void:
	for text in cells:
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", color)
		grid.add_child(label)


## Remember a finished run on this device (keeps your best few).
func _record_run() -> void:
	local_runs.append({"score": int(score), "level": level, "date": Time.get_date_string_from_system()})
	local_runs.sort_custom(func(a, b) -> bool: return int(a["score"]) > int(b["score"]))
	if local_runs.size() > LOCAL_RUNS_KEPT:
		local_runs.resize(LOCAL_RUNS_KEPT)


func _open_settings() -> void:
	menu.visible = false
	settings.visible = true
	back_button.grab_focus()


## Start pressed: the rocket waits on the launch pad until the player presses Space / taps.
func _go_to_pad() -> void:
	state = State.READY
	ready_time = 0.0
	menu.visible = false
	settings.visible = false
	rocket.active = false
	rocket.flame_on = false
	# Pre-flight: the console powers up while you get ready.
	dashboard.visible = true
	launch_prompt.text = "TAP TO LAUNCH" if touch_ui else "PRESS SPACE TO LAUNCH"
	launch_prompt.visible = true
	start_button.release_focus()
	queue_redraw()


## Liftoff: play the launch intro, then the game begins.
func _launch() -> void:
	state = State.INTRO
	intro_time = 0.0
	launch_prompt.visible = false
	menu.visible = false
	settings.visible = false
	rocket.active = false
	rocket.flame_power = 0.2
	rocket.flame_on = true


func _start_playing() -> void:
	state = State.PLAYING
	rocket.active = true
	rocket.flame_power = 1.0
	rocket.velocity_x = 0.0
	rocket.position.x = get_viewport_rect().size.x / 2.0
	level = 1
	level_time = 0.0
	spawn_timer = 0.5
	score_label.visible = true
	level_label.visible = true
	dashboard.visible = true
	boost_button.visible = touch_ui
	missile_button.visible = touch_ui and mods.has("missile")
	_update_hud()
	_show_level_banner()


func _on_play_again() -> void:
	skip_menu = true
	get_tree().reload_current_scene()


# --- Launch intro ------------------------------------------------------------

func _update_intro(delta: float) -> void:
	intro_time += delta
	var size := get_viewport_rect().size
	var t := intro_time

	# 0 - 0.9s: engine ignites, smoke billows, the rocket rumbles on the pad.
	rocket.flame_power = lerpf(0.2, 1.6, clampf(t / 0.9, 0.0, 1.0))
	var shake := 3.0 if t < 1.4 else 0.0
	rocket.position.x = size.x / 2.0 + randf_range(-shake, shake)
	if t < 1.8 and randf() < delta * 40.0:
		smoke.append(Vector4(
			rocket.position.x + randf_range(-10.0, 10.0),
			rocket.position.y + 40.0 - _ground_offset(),
			randf_range(-160.0, 160.0), 0.0))

	if intro_time >= INTRO_DURATION:
		_start_playing()


## Climb progress after liftoff: 0 on the pad, 1 when the intro ends.
func _intro_rise() -> float:
	match state:
		State.MENU, State.READY:
			return 0.0
		State.INTRO:
			return clampf((intro_time - 0.9) / (INTRO_DURATION - 0.9), 0.0, 1.0)
	return 1.0


## How far the ground (pad, Earth, smoke) has sunk below the rocket.
func _ground_offset() -> float:
	var rise := _intro_rise()
	return 50.0 * rise + 450.0 * smoothstep(0.65, 1.0, rise)


## Clouds rush past faster and faster as the rocket accelerates.
func _cloud_scroll() -> float:
	var rise := _intro_rise()
	return rise * rise * get_viewport_rect().size.y * 2.2


## 0 = blue sky on Earth, 1 = deep space.
func _space_amount() -> float:
	match state:
		State.MENU, State.READY:
			return 0.0
		State.INTRO:
			return smoothstep(1.0, INTRO_DURATION - 0.4, intro_time)
	return 1.0


# --- Levels ------------------------------------------------------------------

func _planet(lvl: int) -> Dictionary:
	if lvl <= PLANETS.size():
		return PLANETS[lvl - 1]
	# Past Neptune: endless "Deep Space" levels with strange recoloured planets.
	var base: Dictionary = PLANETS[(lvl - 1) % PLANETS.size()].duplicate()
	var hue_shift := fmod(lvl * 0.37, 1.0)
	var c: Color = base["color"]
	base["color"] = Color.from_hsv(fmod(c.h + hue_shift, 1.0), clampf(c.s + 0.2, 0.0, 1.0), c.v)
	base["name"] = "Deep Space"
	return base


func _update_playing(delta: float) -> void:
	# Boosting flies you forward faster: the whole world (asteroids, stations, stars, the
	# planet) rushes past quicker, levels go by sooner, and score (= distance) climbs faster.
	# The speed eases in and out instead of jumping.
	# Bigger Thruster mod raises the cruising speed; boosting multiplies on top of it.
	var cruise := ModInfo.THRUSTER_SPEED if mods.has("thruster") else 1.0
	var target_speed := cruise * (FORWARD_BOOST if rocket.boosting else 1.0)
	forward_speed = move_toward(forward_speed, target_speed, FORWARD_EASE * delta)
	Obstacle.world_speed = forward_speed
	var travelled := delta * forward_speed

	# Healing Panel mod: slow hull repair over time.
	if mods.has("healing") and hull < hull_max:
		hull = minf(hull + ModInfo.HEAL_PER_SECOND * delta, hull_max)
	missile_cooldown = maxf(missile_cooldown - delta, 0.0)

	score += travelled * 10.0
	level_time += travelled
	if level_time >= LEVEL_DURATION:
		level += 1
		level_time = 0.0
		_show_level_banner()
	_update_hud()

	# Refuel station on every even level (2, 4, 6, ...), a few seconds into the level.
	if _is_station_level(level) and station_level != level and level_time >= 3.0:
		_spawn_station()

	# Asteroids are spaced by distance, so flying faster means meeting them more often.
	spawn_timer -= travelled
	if spawn_timer <= 0.0:
		_spawn_obstacle()
		var tuning: Array = DIFFICULTY_TUNING[difficulty]
		# Each level is busier; it also ramps up a little within the level.
		var interval := start_spawn_interval - (level - 1) * 0.1 - level_time * 0.004
		spawn_timer = maxf(min_spawn_interval, interval) * tuning[0]


func _show_level_banner() -> void:
	level_banner.text = "LEVEL %d\n%s" % [level, String(_planet(level)["name"]).to_upper()]
	level_banner.visible = true
	level_banner.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(level_banner, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.8)
	tween.tween_property(level_banner, "modulate:a", 0.0, 0.6)


func _update_hud() -> void:
	# Only touch the labels when the number actually changes (re-setting text every frame
	# makes Godot re-layout the label every frame).
	if int(score) != _shown_score:
		_shown_score = int(score)
		score_label.text = "Score: %d" % _shown_score
	if level != _shown_level:
		_shown_level = level
		level_label.text = "Level %d · %s" % [level, _planet(level)["name"]]


# --- Ship computer tips --------------------------------------------------------

## General tips, rotated every few seconds.
func _general_tips() -> Array[String]:
	var boost_key := "the BOOST button" if touch_ui else "W or Shift"
	return [
		"Hold %s to boost: you fly and score faster, but asteroids come at you quicker too." % boost_key,
		"Your booster can be refilled at refuel stations. One appears on every even level (2, 4, 6...).",
		"If your booster runs completely dry it detaches, and you can't get it back.",
		"Dock at a station to choose: refuel the booster OR repair 25% hull, then pick a ship mod.",
		"Your ship has 2 mod slots. Stations offer 2 random mods; when both slots are full you swap one out.",
		"The Missile Pod holds 5 missiles (fire with %s) and reloads automatically every time you dock." % ("the MISSILE button" if touch_ui else "Space"),
		"Bigger asteroids do more hull damage. Small ones only scratch.",
		"Orange-glowing asteroids don't fall straight: they sway or drift sideways.",
		"The NAV BEACON shows the range to the next refuel station.",
		"Your ship glides. Let go a little early and drift into the gap.",
		"MASTER CAUTION blinks when booster fuel is running low.",
		"After a hit your ship blinks: you can't be damaged again for a moment.",
	]


## Context tips jump the queue the first time their situation happens in a run.
func _context_tip() -> String:
	if state == State.READY:
		return _once("pad", "Pre-flight check: all systems go. Launch when you're ready.")
	if state != State.PLAYING:
		return ""
	# In priority order; each one fires only once per run (or once per station).
	var tip := ""
	if not rocket.has_booster:
		tip = _once("booster_lost", "Booster lost. It can't be recovered, but refuel stations can still repair your hull.")
	if tip == "" and rocket.has_booster and rocket.fuel < 0.25:
		tip = _once("fuel_low", "Fuel low! Refill at a refuel station. If it runs out, the booster drops off for good.")
	if tip == "" and hull <= 0.5:
		tip = _once("hull_low", "Hull damaged. Dock at a refuel station to repair 25%.")
	if tip == "" and station_level == level and is_instance_valid(station_node) and not station_node.used:
		tip = _once("station_%d" % level, "Station in range: fly into it to dock. Choose fuel or hull repair, then a ship mod.")
	if tip == "" and level == 2:
		tip = _once("wobble", "From here on, orange-glowing asteroids sway and drift sideways. Watch them closely.")
	return tip


func _once(key: String, text: String) -> String:
	if _tips_triggered.has(key):
		return ""
	_tips_triggered[key] = true
	return text


func _update_tips(delta: float) -> void:
	var active := state == State.READY or state == State.PLAYING
	if tip_panel.visible != active:
		tip_panel.visible = active
	if not active:
		return
	var urgent := _context_tip()
	if urgent != "":
		_show_tip(urgent, true)
		_tip_timer = URGENT_TIP_TIME
		return
	_tip_timer -= delta
	if _tip_timer <= 0.0:
		var tips := _general_tips()
		_tip_index = (_tip_index + 1) % tips.size()
		_show_tip(tips[_tip_index], false)
		_tip_timer = TIP_TIME


func _show_tip(text: String, urgent: bool) -> void:
	tip_title.text = "SHIP COMPUTER · ALERT" if urgent else "SHIP COMPUTER · TIP"
	tip_title.add_theme_color_override("font_color", Color(1, 0.65, 0.35) if urgent else Color(0.45, 0.8, 1))
	tip_text.text = text
	# Quick fade-in so a new tip catches the eye without being distracting.
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()
	tip_panel.modulate.a = 0.0
	_tip_tween = create_tween()
	_tip_tween.tween_property(tip_panel, "modulate:a", 1.0, 0.35)


func _position_tip_panel(console_height: float) -> void:
	# Above the rocket's flight row (and above the BOOST button on phones), right side.
	var lift := 160.0 if touch_ui else 110.0
	tip_panel.offset_bottom = -(console_height + lift)
	tip_panel.offset_top = tip_panel.offset_bottom - 1.0  # grows upward to fit the text


# --- Booster -----------------------------------------------------------------

## Keyboard keys: boost = W or Shift, missile = Space.
func _setup_boost_input() -> void:
	if InputMap.has_action("boost"):
		return
	# Boost: W or Shift.
	InputMap.add_action("boost")
	for key in [KEY_W, KEY_SHIFT]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event("boost", event)
	# Missile Pod mod: Space fires a missile (Space also launches from the pad).
	InputMap.add_action("missile")
	for key in [KEY_SPACE]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event("missile", event)


## Round on-screen BOOST button for phones (multi-touch: hold it while steering).
func _make_boost_button() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.62, 0.18, 0.85))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.78, Color(0.9, 0.4, 0.1, 0.8))
	gradient.add_point(0.8, Color(1, 1, 1, 0.9))
	gradient.add_point(0.9, Color(1, 1, 1, 0.9))
	gradient.add_point(0.92, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient

	var pressed_gradient := gradient.duplicate()
	pressed_gradient.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	var pressed_texture := texture.duplicate()
	pressed_texture.gradient = pressed_gradient

	boost_button = TouchScreenButton.new()
	boost_button.texture_normal = texture
	boost_button.texture_pressed = pressed_texture
	var shape := CircleShape2D.new()
	shape.radius = 64.0
	boost_button.shape = shape
	boost_button.shape_centered = true
	boost_button.pressed.connect(func() -> void: rocket.boost_button_held = true)
	boost_button.released.connect(func() -> void: rocket.boost_button_held = false)

	var label := Label.new()
	label.text = "BOOST"
	label.size = Vector2(128, 128)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boost_button.add_child(label)

	boost_button.visible = false
	$UI.add_child(boost_button)


func _position_boost_button() -> void:
	if boost_button == null:
		return
	var size := get_viewport_rect().size
	# Just above the console: BOOST bottom right, MISSILE (when fitted) bottom left.
	boost_button.position = Vector2(size.x - 128.0 - 30.0, size.y - cockpit.dash_height - 128.0 - 14.0)
	if missile_button:
		missile_button.position = Vector2(30.0, size.y - cockpit.dash_height - 128.0 - 14.0)
	# Touches starting on these buttons press them instead of steering.
	rocket.no_steer_rects.clear()
	rocket.no_steer_rects.append(Rect2(boost_button.position, Vector2(128, 128)).grow(16.0))
	if missile_button:
		rocket.no_steer_rects.append(Rect2(missile_button.position, Vector2(128, 128)).grow(16.0))


## Cockpit console instruments: master caution, boost fuel, hull integrity, nav beacon.
## Everything here only touches a UI node when its value actually changed: re-setting label
## text or theme colours every frame forces Godot to re-layout/redraw them every frame.
func _update_dashboard() -> void:
	# Boost fuel + MASTER CAUTION (lights up when the booster is low on fuel).
	var fuel: float = rocket.fuel
	if not is_equal_approx(boost_bar.value, fuel):
		boost_bar.value = fuel
	var low_fuel: bool = rocket.has_booster and fuel < 0.25
	caution_light.on = low_fuel
	_set_modulate(caution_label, Color(1.6, 1.2, 1.2) if low_fuel else Color.WHITE)
	if not rocket.has_booster:
		_set_label(fuel_label, "BOOSTER LOST", Color(1, 0.4, 0.35))
		_set_modulate(boost_bar, Color(1, 1, 1, 0.4))
	else:
		var color := Color(1.0, 0.25, 0.2) if low_fuel else Color(1.0, 0.6, 0.15)
		if rocket.boosting:
			color = color.lightened(0.3)
		_set_fill(boost_bar, color)
		_set_label(fuel_label, ("FUEL LOW" if low_fuel else "BOOST FUEL") + ("" if touch_ui else "  [W / Shift]"), Color(1, 0.75, 0.35))

	# Hull integrity: green -> yellow -> red, flashing when critical. The bar's full length
	# is the max hull (150% with the Reinforced Hull mod).
	if not is_equal_approx(hull_bar.max_value, hull_max):
		hull_bar.max_value = hull_max
	if not is_equal_approx(hull_bar.value, hull):
		hull_bar.value = hull
	var hull_color := Color(0.3, 0.9, 0.45) if hull > 0.6 else (Color(1.0, 0.8, 0.2) if hull > 0.3 else Color(1.0, 0.3, 0.25))
	_set_fill(hull_bar, hull_color)
	_set_label(hull_label, "HULL INTEGRITY  %d%%" % roundi(hull * 100.0), hull_color.lightened(0.2))
	var hull_alpha := 0.55 + 0.45 * absf(sin(clock * 6.0)) if hull <= 0.3 else 1.0
	_set_modulate(hull_bar, Color(1, 1, 1, hull_alpha))

	_update_nav_beacon()


func _set_label(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _set_fill(bar: ProgressBar, color: Color) -> void:
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if fill.bg_color != color:
		fill.bg_color = color


func _set_modulate(item: CanvasItem, color: Color) -> void:
	if item.modulate != color:
		item.modulate = color


## Refuel stations appear on every even level: 2, 4, 6, ...
func _is_station_level(lvl: int) -> bool:
	return lvl >= 2 and lvl % 2 == 0


## NAV BEACON: range to the refuel station on levels that have one, otherwise NOT TRACKING.
func _update_nav_beacon() -> void:
	var tracking := _is_station_level(level)
	var station_alive := is_instance_valid(station_node)
	var value := "NOT TRACKING"
	var color := Color(0.6, 0.65, 0.72)

	if tracking and station_level != level:
		# Beacon acquired: station not in visual range yet. Range = time until it appears
		# plus the distance it then has to travel down to us.
		var pixels := (3.0 - level_time) * STATION_SPEED + rocket.position.y + 90.0
		value = "RANGE " + _format_range(pixels)
		color = Color(0.5, 1.0, 0.65)
	elif tracking and station_alive and not station_node.used:
		var pixels: float = rocket.position.y - station_node.position.y
		if pixels > 0.0:
			value = "LOCKED  " + _format_range(pixels)
			color = Color(0.85, 1.0, 0.4)
		else:
			value = "PASSED - SIGNAL LOST"
			color = Color(1.0, 0.55, 0.4)
	elif tracking and station_docked:
		value = "DOCKED"
		color = Color(0.45, 0.85, 1.0)
	elif tracking:
		value = "SIGNAL LOST"
		color = Color(1.0, 0.55, 0.4)

	var next_level := level
	if not tracking or station_level == level:
		next_level += 1
		while not _is_station_level(next_level):
			next_level += 1
	var title := "NAV BEACON · " + ("STATION" if tracking and station_level != level or (station_alive and tracking) else "NEXT: LVL %d" % next_level)
	if nav_title.text != title:
		nav_title.text = title
	_set_label(nav_value, value, color)


func _format_range(pixels: float) -> String:
	var meters := maxf(pixels, 0.0) * METERS_PER_PIXEL
	return "%.1f km" % (meters / 1000.0) if meters >= 1000.0 else "%d m" % int(meters)


func _on_booster_lost(pod_positions: Array) -> void:
	for pos in pod_positions:
		var side := -1.0 if pos.x < rocket.position.x else 1.0
		pods.append({
			"pos": pos,
			"vel": Vector2(side * randf_range(90.0, 150.0) + rocket.velocity_x * 0.4, -40.0),
			"rot": rocket.rotation,
			"spin": side * randf_range(3.0, 6.0),
			"age": 0.0,
		})
	_show_toast("BOOSTER EMPTY - DETACHED!", Color(1, 0.45, 0.35))


func _update_pods(delta: float) -> void:
	for i in range(pods.size() - 1, -1, -1):
		var pod := pods[i]
		var vel: Vector2 = pod["vel"]
		vel.y += 420.0 * delta  # falls away behind the rocket
		pod["vel"] = vel
		pod["pos"] += vel * delta
		pod["rot"] += pod["spin"] * delta
		pod["age"] += delta
		if pod["age"] > 3.0:
			pods.remove_at(i)


func _spawn_station() -> void:
	station_level = level
	station_docked = false
	var station := Station.new()
	var size := get_viewport_rect().size
	station.fall_speed = STATION_SPEED
	station.position = Vector2(randf_range(140.0, size.x - 140.0), -90.0)
	obstacles.add_child(station)
	obstacles.move_child(station, 0)  # behind the asteroids
	station_node = station
	_show_toast("STATION IN VISUAL RANGE!", Color(0.45, 1, 0.6))


# --- Docking & ship mods -------------------------------------------------------

## Reaching a station: the ship comes to a full stop and docks. The world freezes while
## the station menu is open: choose fuel OR hull repair, then pick one of 2 random mods.
func _on_station_reached(station: Area2D) -> void:
	if station.used or state != State.PLAYING:
		return
	station.used = true
	station_docked = true
	_dock_station = station
	state = State.DOCKED

	# Full stop: forward flight, stars and asteroids all freeze.
	forward_speed = 0.0
	Obstacle.world_speed = 0.0
	obstacles.process_mode = Node.PROCESS_MODE_DISABLED
	rocket.active = false
	rocket.boost_button_held = false
	rocket.velocity_x = 0.0
	rocket.flame_power = 0.35
	boost_button.visible = false
	missile_button.visible = false
	missiles.clear()

	# Missile Pod reloads automatically at every station.
	var reloaded := mods.has("missile") and missile_ammo < ModInfo.MISSILE_AMMO
	if mods.has("missile"):
		missile_ammo = ModInfo.MISSILE_AMMO
	_show_toast("DOCKED" + ("  ·  MISSILES RELOADED" if reloaded else ""), Color(0.45, 1, 0.6))

	# The station glides in under the ship and locks on, then the menu opens.
	var tween := create_tween()
	tween.tween_property(station, "position", rocket.position + Vector2(0, 8), 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_open_station_service)


## Step 1: one service, fuel OR hull repair.
func _open_station_service() -> void:
	_dock_step = "service"
	station_menu.visible = true
	station_title.text = "DOCKED AT STATION"
	station_subtitle.text = "Choose ONE service:"
	_clear_options()
	var fuel_button := _option_button("", "REFUEL BOOSTER",
		"Fill the booster tank to 100%%  (now %d%%)." % roundi(rocket.fuel * 100.0) if rocket.has_booster
		else "Your booster is gone. It can't be refuelled.", Color(1, 0.65, 0.25), _pick_fuel)
	fuel_button.disabled = not rocket.has_booster
	var repair_button := _option_button("", "REPAIR HULL",
		"Repair +%d%% hull  (now %d%% of %d%%)." % [roundi(STATION_REPAIR * 100.0), roundi(hull * 100.0), roundi(hull_max * 100.0)],
		Color(0.45, 1, 0.6), _pick_repair)
	station_footer.visible = false
	(repair_button if fuel_button.disabled else fuel_button).grab_focus()


func _pick_fuel() -> void:
	rocket.refuel()
	_show_toast("BOOSTER REFUELED", Color(1, 0.75, 0.35))
	_open_station_mods()


func _pick_repair() -> void:
	hull = minf(hull + STATION_REPAIR, hull_max)
	_show_toast("HULL REPAIRED", Color(0.45, 1, 0.6))
	_open_station_mods()


## Step 2: the station offers 2 random mods (never ones already fitted). Pick one or skip.
func _open_station_mods() -> void:
	_dock_step = "mod"
	_offer = ModInfo.random_offer(mods)
	if _offer.is_empty():
		_undock()
		return
	var full := not mods.has("")
	station_title.text = "SHIP MODIFICATION"
	station_subtitle.text = "Pick one upgrade. Your ship has 2 mod slots%s." % (
		" (both are full: you'll choose one to replace)" if full else "")
	_clear_options()
	var first: Button = null
	for id in _offer:
		var info: Dictionary = ModInfo.MODS[id]
		var b := _option_button(id, info["name"], info["desc"], info["color"], _pick_mod.bind(id))
		if first == null:
			first = b
	station_footer.text = "Skip"
	station_footer.visible = true
	first.grab_focus()


func _pick_mod(id: String) -> void:
	var free_slot := mods.find("")
	if free_slot != -1:
		_install_mod(id, free_slot)
		_undock()
	else:
		_pending_mod = id
		_open_station_replace()


## Step 3 (only when both slots are full): choose which fitted mod to swap out.
func _open_station_replace() -> void:
	_dock_step = "replace"
	station_title.text = "BOTH SLOTS FULL"
	station_subtitle.text = "Replace which mod with %s?" % ModInfo.MODS[_pending_mod]["name"]
	_clear_options()
	var first: Button = null
	for slot in 2:
		var id := mods[slot]
		var info: Dictionary = ModInfo.MODS[id]
		var b := _option_button(id, "Remove " + String(info["name"]), "Slot %d. This mod is removed." % (slot + 1),
			info["color"], _pick_replace.bind(slot))
		if first == null:
			first = b
	station_footer.text = "Keep current mods"
	station_footer.visible = true
	first.grab_focus()


func _pick_replace(slot: int) -> void:
	_install_mod(_pending_mod, slot)
	_undock()


func _on_station_footer() -> void:
	_undock()


func _install_mod(id: String, slot: int) -> void:
	mods[slot] = id
	if id == "missile":
		missile_ammo = ModInfo.MISSILE_AMMO
	_apply_mods()
	_show_toast("MOD FITTED: " + String(ModInfo.MODS[id]["name"]).to_upper(), Color(0.45, 0.85, 1))


## Recalculate everything the fitted mods change.
func _apply_mods() -> void:
	rocket.mods.assign(mods)  # the rocket draws its fitted mods
	rocket.agility = ModInfo.RCS_AGILITY if mods.has("rcs") else 1.0
	var new_max := 1.0 + (ModInfo.HULL_BONUS if mods.has("hull") else 0.0)
	if new_max > hull_max:
		hull += new_max - hull_max  # fitting the reinforced hull adds the extra plating
	hull_max = new_max
	hull = minf(hull, hull_max)
	if not mods.has("missile"):
		missile_ammo = 0


## Leave the station: flight resumes (speed eases back up) with a moment of protection.
func _undock() -> void:
	station_menu.visible = false
	_dock_step = ""
	_clear_options()
	station_footer.release_focus()
	state = State.PLAYING
	obstacles.process_mode = Node.PROCESS_MODE_INHERIT
	rocket.active = true
	rocket.flame_power = 1.0
	invulnerable = INVULNERABLE_TIME
	boost_button.visible = touch_ui
	missile_button.visible = touch_ui and mods.has("missile")
	_position_boost_button()
	_tip_timer = 0.0  # drop the "station in range" alert, move on to the next tip


func _clear_options() -> void:
	for child in station_options.get_children():
		station_options.remove_child(child)
		child.queue_free()


## A big card-style button: optional mod icon, title and description.
func _option_button(mod_id: String, title: String, desc: String, color: Color, on_press: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 176 if mod_id != "" else 110)
	button.pressed.connect(on_press)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 10
	box.offset_right = -12
	box.offset_bottom = -10
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	if mod_id != "":
		var icon := ModIcon.new()
		icon.custom_minimum_size = Vector2(46, 46)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mod_id = mod_id
		box.add_child(icon)
	var name_label := Label.new()
	name_label.text = title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", color)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.84, 0.92))
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc_label)
	button.add_child(box)
	station_options.add_child(button)
	return button


## SHIP MODS panel (left): only rewritten when what it shows actually changes.
func _update_mod_panel() -> void:
	var show_panel := state == State.READY or state == State.PLAYING or state == State.DOCKED
	if mod_panel.visible != show_panel:
		mod_panel.visible = show_panel
	if not show_panel:
		return
	var key := "%s|%s|%d|%s|%s" % [mods[0], mods[1], missile_ammo, hull >= hull_max, touch_ui]
	if key == _mod_panel_key:
		return
	_mod_panel_key = key
	for slot in 2:
		var row: Control = mod_slots[slot]
		var id := mods[slot]
		row.get_node("Icon").mod_id = id
		var name_label: Label = row.get_node("Text/Name")
		var detail: Label = row.get_node("Text/Detail")
		if id == "":
			name_label.text = "Empty slot"
			name_label.add_theme_color_override("font_color", Color(0.6, 0.63, 0.7))
			detail.text = "Dock at a station to fit a mod"
			detail.add_theme_color_override("font_color", Color(0.5, 0.53, 0.6))
			continue
		var info: Dictionary = ModInfo.MODS[id]
		name_label.text = info["name"]
		name_label.add_theme_color_override("font_color", info["color"])
		var text := ""
		var color := Color(0.7, 0.74, 0.82)
		match id:
			"thruster": text = "+25% forward speed"
			"rcs": text = "+35% side-to-side speed"
			"radar": text = "Scanning ahead"
			"hull": text = "Max hull 150%"
			"healing": text = "Hull full" if hull >= hull_max else "Repairing hull…"
			"missile":
				if missile_ammo > 0:
					text = "MISSILES %d/%d%s" % [missile_ammo, ModInfo.MISSILE_AMMO, "" if touch_ui else "  [Space]"]
					color = Color(1, 0.75, 0.6)
				else:
					text = "EMPTY · reloads at stations"
					color = Color(1, 0.45, 0.4)
		detail.text = text
		detail.add_theme_color_override("font_color", color)


# --- Missile Pod mod -----------------------------------------------------------

func _make_missile_button() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.35, 0.3, 0.85))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.78, Color(0.75, 0.15, 0.12, 0.8))
	gradient.add_point(0.8, Color(1, 1, 1, 0.9))
	gradient.add_point(0.9, Color(1, 1, 1, 0.9))
	gradient.add_point(0.92, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient
	missile_button = TouchScreenButton.new()
	missile_button.texture_normal = texture
	var shape := CircleShape2D.new()
	shape.radius = 64.0
	missile_button.shape = shape
	missile_button.shape_centered = true
	missile_button.pressed.connect(func() -> void:
		if state == State.PLAYING:
			_fire_missile())
	var label := Label.new()
	label.text = "MISSILE"
	label.size = Vector2(128, 128)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	missile_button.add_child(label)
	missile_button.visible = false
	$UI.add_child(missile_button)


func _fire_missile() -> void:
	if not mods.has("missile"):
		return
	if missile_ammo <= 0:
		_show_toast("NO MISSILES  ·  RELOAD AT A STATION", Color(1, 0.5, 0.4))
		return
	if missile_cooldown > 0.0:
		return
	var target := _nearest_asteroid()
	if target == null:
		_show_toast("NO TARGET IN RANGE", Color(0.75, 0.78, 0.85))
		return
	missile_ammo -= 1
	missile_cooldown = ModInfo.MISSILE_COOLDOWN
	missiles.append({
		"pos": rocket.position + Vector2(0, -30),
		"vel": Vector2(rocket.velocity_x * 0.3, -520),
		"target": target,
		"age": 0.0,
	})


## Closest asteroid that's on screen and ahead of the ship.
func _nearest_asteroid() -> Area2D:
	var best: Area2D = null
	var best_dist := INF
	for child in obstacles.get_children():
		if child.get_script() != Obstacle or child.is_queued_for_deletion():
			continue
		if child.position.y < 0.0 or child.position.y > rocket.position.y - 20.0:
			continue
		var d: float = child.position.distance_squared_to(rocket.position)
		if d < best_dist:
			best_dist = d
			best = child
	return best


func _update_missiles(delta: float) -> void:
	for i in range(missiles.size() - 1, -1, -1):
		var m := missiles[i]
		m["age"] += delta
		var target = m["target"]
		if not is_instance_valid(target) or target.is_queued_for_deletion():
			target = _nearest_asteroid()
			m["target"] = target
		var pos: Vector2 = m["pos"]
		var vel: Vector2 = m["vel"]
		# Homing: steer the velocity toward the target, accelerating to full speed.
		var desired := Vector2(0, -1100)
		if target:
			desired = (target.position - pos).normalized() * 1100.0
		vel = vel.lerp(desired, clampf(7.0 * delta, 0.0, 1.0))
		pos += vel * delta
		m["pos"] = pos
		m["vel"] = vel
		var trail: PackedVector2Array = m.get("trail", PackedVector2Array())
		trail.append(pos)
		if trail.size() > 10:
			trail.remove_at(0)
		m["trail"] = trail
		if target and pos.distance_to(target.position) < target.radius:
			_shatter(target)
			target.queue_free()
			score += ModInfo.MISSILE_SCORE
			_show_toast("TARGET DESTROYED  +%d" % int(ModInfo.MISSILE_SCORE), Color(1, 0.75, 0.4))
			missiles.remove_at(i)
		elif m["age"] > 3.0 or pos.y < -120.0:
			missiles.remove_at(i)


# --- Radar mod -----------------------------------------------------------------

func _make_radar_overlay() -> void:
	radar_overlay = Control.new()
	radar_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	radar_overlay.draw.connect(_draw_radar)
	$UI/Root.add_child(radar_overlay)
	$UI/Root.move_child(radar_overlay, cockpit.get_index() + 1)  # just above the cockpit frame


func _update_radar() -> void:
	var on := mods.has("radar") and (state == State.PLAYING or state == State.DOCKED)
	if on or _radar_had_blips:
		radar_overlay.queue_redraw()
	_radar_had_blips = on


## Radar blips along the top of the window for asteroids that haven't come into view yet.
func _draw_radar() -> void:
	if not mods.has("radar") or not (state == State.PLAYING or state == State.DOCKED):
		return
	var top := 50.0 + 8.0  # just under the cockpit's top bar
	for child in obstacles.get_children():
		if child.get_script() != Obstacle:
			continue
		var y: float = child.position.y
		if y > 50.0:
			continue  # already visible
		var closeness := clampf(1.0 - (50.0 - y) / (ModInfo.RADAR_RANGE + 80.0), 0.15, 1.0)
		var color := Color(1, 0.55, 0.15) if child.tricky else Color(1, 0.3, 0.25)
		var x: float = child.position.x
		var w: float = clampf(child.radius * 0.5, 7.0, 16.0)
		radar_overlay.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w, top), Vector2(x + w, top), Vector2(x, top + w * 1.2)]), Color(color, closeness))
		radar_overlay.draw_rect(Rect2(x - w, top - 3, w * 2.0, 2), Color(color, closeness * 0.6))


func _show_toast(text: String, color: Color) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", color)
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)


# --- Settings ----------------------------------------------------------------

func _on_difficulty_selected(index: int) -> void:
	difficulty = difficulty_option.get_item_id(index) as Difficulty
	_save()


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func _on_reset_pressed() -> void:
	best_score = 0.0
	local_runs.clear()
	_save()
	reset_button.text = "Best Score Reset!"
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(reset_button):
		reset_button.text = "Reset Best Score"


# --- Saving ------------------------------------------------------------------

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # No save yet: best score stays 0.
	var best = cfg.get_value("score", "best", 0.0)
	best_score = float(best) if best != null else 0.0
	var diff = cfg.get_value("settings", "difficulty", Difficulty.NORMAL)
	if diff is int and DIFFICULTY_TUNING.has(diff):
		difficulty = diff
	var runs = cfg.get_value("score", "runs", [])
	if runs is Array:
		local_runs = runs.filter(func(r) -> bool: return r is Dictionary and r.has("score"))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.set_value("settings", "difficulty", difficulty)
	cfg.set_value("score", "runs", local_runs)
	cfg.save(SAVE_PATH)


# --- Gameplay ----------------------------------------------------------------

func _spawn_obstacle() -> void:
	var size := get_viewport_rect().size
	var radius := randf_range(18.0, 46.0)
	var tuning: Array = DIFFICULTY_TUNING[difficulty]

	var rock := Obstacle.new()
	var speed := start_fall_speed + (level - 1) * 40.0 + level_time * 2.0 + randf_range(0.0, 140.0)
	rock.fall_speed = speed * tuning[1]
	rock.spin = randf_range(-2.0, 2.0)
	# Spawned a little above the window so the Radar mod can see them coming. (Without
	# radar this just means they arrive a moment later - nothing else changes.)
	rock.position = Vector2(randf_range(radius, size.x - radius), -radius - ModInfo.RADAR_RANGE)
	# Asteroids take on the colour of the planet you're passing.
	rock.setup(radius, _planet(level)["rock"])
	_make_tricky(rock)
	obstacles.add_child(rock)


## From Level 2, some asteroids wobble side to side or fly diagonally (always still falling).
## Each level makes them more common and their movement wilder.
func _make_tricky(rock) -> void:
	if level < 2:
		return
	var steps := level - 2  # 0 on Level 2, 1 on Level 3, ...
	var chance := minf(0.25 + 0.1 * steps, 0.75)
	if randf() > chance:
		return

	rock.tricky = true
	var roll := randf()
	var sway := roll >= 0.35 or level < 3  # Level 2 only sways; diagonal drifters join from Level 3
	var diagonal := (level >= 3 and roll < 0.35) or (level >= 4 and roll > 0.75)
	if sway:
		rock.sway_amount = minf(randf_range(30.0, 60.0) + 14.0 * steps, 170.0)
		rock.sway_speed = minf(randf_range(1.4, 2.2) + 0.25 * steps, 4.5)
	if diagonal:
		var drift_speed := minf(randf_range(60.0, 110.0) + 22.0 * (level - 3), 260.0)
		rock.drift = drift_speed * (1.0 if randf() < 0.5 else -1.0)


## Background layers (far to near): faint nebulae, then three star layers. Nearer stars are
## bigger, brighter and scroll faster (parallax). Then the planet for the current level.
func _make_background() -> void:
	StarLayer.glow_tex = glow_tex
	PlanetNode.glow_tex = glow_tex
	PlanetNode.shade_tex = shade_tex
	Obstacle.glow_tex = glow_tex
	# [kind, count, speed, dot size range, brightness range, twinkle rate]
	var specs := [
		[StarLayer.Kind.NEBULA, 4, 6.0, Vector2.ZERO, Vector2.ZERO, 0.0],
		[StarLayer.Kind.STARS, 70, 22.0, Vector2(0.7, 1.1), Vector2(0.3, 0.55), 1.3],
		[StarLayer.Kind.STARS, 45, 55.0, Vector2(1.0, 1.6), Vector2(0.5, 0.8), 2.1],
		[StarLayer.Kind.STARS, 25, 110.0, Vector2(1.4, 2.1), Vector2(0.8, 1.0), 2.9],
	]
	for spec in specs:
		var layer := StarLayer.new()
		layer.kind = spec[0]
		layer.count = spec[1]
		layer.speed = spec[2]
		layer.size_range = spec[3]
		layer.brightness = spec[4]
		layer.twinkle_rate = spec[5]
		layer.show_behind_parent = true  # drawn behind Earth/smoke, which this node draws
		add_child(layer)
		move_child(layer, bg_layers.size())
		bg_layers.append(layer)
	planet_node = PlanetNode.new()
	planet_node.show_behind_parent = true
	planet_node.visible = false
	add_child(planet_node)
	move_child(planet_node, bg_layers.size())


## Renders 8 random asteroid shapes + the warning glow into one texture, once per session
## (see Obstacle.atlas for why). Uses an off-screen SubViewport, so it's done on the GPU.
func _bake_asteroid_atlas() -> void:
	if Obstacle.atlas:
		return  # already baked (kept across restarts)
	var cell := Obstacle.ATLAS_CELL
	var viewport := SubViewport.new()
	viewport.size = Vector2i(cell * Obstacle.ATLAS_COLUMNS, cell * 3)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var gray := Color(Obstacle.BAKE_GRAY, Obstacle.BAKE_GRAY, Obstacle.BAKE_GRAY)
	for i in Obstacle.ATLAS_ROCKS:
		var art := Obstacle.new()
		art.setup(Obstacle.BAKE_RADIUS, gray)
		art._color = gray  # no random shade: tint is applied per asteroid later
		art.position = Obstacle.atlas_region(i).get_center()
		art.monitoring = false
		art.monitorable = false
		art.set_process(false)
		viewport.add_child(art)
	var glow := Sprite2D.new()
	glow.texture = glow_tex
	glow.scale = Vector2.ONE * float(cell) / glow_tex.get_width()
	glow.position = Obstacle.atlas_region(Obstacle.ATLAS_GLOW_CELL).get_center()
	viewport.add_child(glow)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image and not image.is_empty():
		Obstacle.atlas = ImageTexture.create_from_image(image)


## Per frame the background only moves/fades nodes; nothing is redrawn.
func _update_background() -> void:
	var space := _space_amount()
	if space != _last_space:
		_last_space = space
		# Sky colour = the screen's clear colour: blue on Earth fading to black in space.
		RenderingServer.set_default_clear_color(SKY_BLUE.lerp(SPACE_DARK, space))
		for layer in bg_layers:
			layer.modulate.a = space
	# Stars streak faster during the climb out of the atmosphere.
	# ...and while boosting, stars stream past faster with your forward speed.
	var boost := 1.0 + 6.0 * space if state == State.INTRO else forward_speed
	for layer in bg_layers:
		layer.speed_scale = boost

	# The planet for the current level drifts slowly down past the rocket.
	var show_planet := state == State.PLAYING or state == State.DOCKED or state == State.OVER
	planet_node.visible = show_planet
	if show_planet:
		var planet := _planet(level)
		if _planet_level != level:
			_planet_level = level
			planet_node.data = planet
		var radius: float = planet["radius"]
		var size := get_viewport_rect().size
		var side := 0.2 if level % 2 == 1 else 0.8
		planet_node.position = Vector2(size.x * side,
			lerpf(-radius - 40.0, size.y + radius + 40.0, level_time / LEVEL_DURATION))


## Asteroid breaks into tumbling chunks plus a flash where it hit.
func _shatter(rock: Area2D) -> void:
	var color: Color = rock._color
	for i in 10:
		var dir := Vector2.from_angle(randf() * TAU)
		fragments.append({
			"pos": rock.position + dir * randf_range(0.0, 12.0),
			"vel": dir * randf_range(80.0, 260.0) + Vector2(0, 120),
			"size": randf_range(3.0, 8.0),
			"rot": randf() * TAU,
			"color": color,
			"age": 0.0,
		})
	fragments.append({"pos": rock.position, "flash": true, "age": 0.0})


func _update_fragments(delta: float) -> void:
	for i in range(fragments.size() - 1, -1, -1):
		var f := fragments[i]
		f["age"] += delta
		if f.has("vel"):
			f["pos"] += f["vel"] * delta
			f["rot"] += delta * 6.0
		if f["age"] > 0.9:
			fragments.remove_at(i)


## Hit recovery blink and screen shake.
func _update_damage_effects(delta: float) -> void:
	if invulnerable > 0.0:
		invulnerable = maxf(invulnerable - delta, 0.0)
		rocket.modulate.a = 0.3 if fmod(invulnerable, 0.2) < 0.1 else 1.0
		if invulnerable == 0.0:
			rocket.modulate.a = 1.0
	if shake > 0.0:
		shake = maxf(shake - delta, 0.0)
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 30.0
	elif position != Vector2.ZERO:
		position = Vector2.ZERO


func _update_smoke(delta: float) -> void:
	for i in range(smoke.size() - 1, -1, -1):
		var p := smoke[i]
		p.x += p.z * delta
		p.z *= 0.96
		p.y -= 10.0 * delta
		p.w += delta
		if p.w > 2.0:
			smoke.remove_at(i)
		else:
			smoke[i] = p


func _on_rocket_hit(area: Area2D) -> void:
	if state != State.PLAYING:
		return
	if area.get_script() == Station:
		_on_station_reached(area)
		return
	if invulnerable > 0.0:
		return  # still recovering from the last hit

	# Asteroid impact: bigger rocks do more hull damage. The rock shatters on impact.
	var rock_radius: float = area.radius
	var damage := remap(clampf(rock_radius, 18.0, 46.0), 18.0, 46.0, 0.15, 0.35)
	hull = maxf(hull - damage, 0.0)
	_shatter(area)
	area.queue_free()
	shake = 0.35
	if hull > 0.0:
		invulnerable = INVULNERABLE_TIME
		_show_toast("IMPACT!  HULL -%d%%" % roundi(damage * 100.0), Color(1, 0.45, 0.35))
		return
	_hull_breach()


## Hull reached 0%: game over.
func _hull_breach() -> void:
	state = State.OVER
	forward_speed = 1.0
	Obstacle.world_speed = 1.0
	game_over_title.text = "HULL BREACH!"
	boost_button.visible = false
	missile_button.visible = false
	rocket.boost_button_held = false
	rocket.active = false
	rocket.modulate = Color(1.0, 0.4, 0.3)
	rocket.flame_on = false

	var new_best := score > best_score
	if new_best:
		best_score = score
	_record_run()
	_save()

	result_label.text = "Score: %d\nReached Level %d · %s\n%s" % [
		int(score), level, _planet(level)["name"],
		"NEW BEST!" if new_best else "Best: %d" % int(best_score)]
	game_over.visible = true
	# Short delay so a key/finger still held from playing doesn't press a button by accident.
	play_again_button.disabled = true
	menu_button.disabled = true
	await get_tree().create_timer(0.6).timeout
	play_again_button.disabled = false
	menu_button.disabled = false
	play_again_button.grab_focus()


# --- Drawing -----------------------------------------------------------------

## This node only draws the "foreground" effects: Earth, clouds, smoke and debris.
## (Sky, stars, nebulae and planets are separate nodes that don't redraw every frame.)
func _draw() -> void:
	var size := get_viewport_rect().size
	var space := _space_amount()

	if space < 1.0:
		_draw_clouds(size, space)
		_draw_earth(size)

	for p in smoke:
		var age := p.w / 2.0
		var y := p.y + _ground_offset()
		draw_circle(Vector2(p.x, y), 10.0 + age * 40.0, Color(0.85, 0.85, 0.88, (1.0 - age) * 0.7))

	# Asteroid chunks and impact flashes.
	for f in fragments:
		var t: float = f["age"] / 0.9
		if f.has("flash"):
			draw_circle(f["pos"], 20.0 + t * 60.0, Color(1.0, 0.7, 0.3, (1.0 - t) * 0.5))
			draw_circle(f["pos"], 10.0 + t * 30.0, Color(1.0, 0.95, 0.8, (1.0 - t) * 0.7))
		else:
			var col: Color = f["color"]
			var sz: float = f["size"]
			draw_set_transform(f["pos"], f["rot"])
			draw_colored_polygon(PackedVector2Array([Vector2(-sz, -sz * 0.6), Vector2(sz, -sz * 0.3), Vector2(sz * 0.2, sz)]), Color(col, 1.0 - t))
	draw_set_transform(Vector2.ZERO)

	# Detached booster pods tumbling away.
	for pod in pods:
		draw_set_transform(pod["pos"], pod["rot"])
		Rocket.draw_pod(self, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO)

	# Homing missiles: fading exhaust trail, then the missile pointing where it's flying.
	for m in missiles:
		var trail: PackedVector2Array = m.get("trail", PackedVector2Array())
		if trail.size() >= 2:
			draw_polyline(trail, Color(1, 0.7, 0.35, 0.45), 3.0)
		var vel: Vector2 = m["vel"]
		draw_set_transform(m["pos"], vel.angle() + PI / 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-3, 10), Vector2(3, 10), Vector2(0, 19 + randf() * 6)]), Color(1, 0.7, 0.25))
		draw_rect(Rect2(-3, -8, 6, 18), Color(0.92, 0.93, 0.96))
		draw_colored_polygon(PackedVector2Array([Vector2(-3, -8), Vector2(3, -8), Vector2(0, -15)]), Color(1, 0.35, 0.3))
		draw_colored_polygon(PackedVector2Array([Vector2(-3, 4), Vector2(-7, 11), Vector2(-3, 10)]), Color(0.8, 0.25, 0.22))
		draw_colored_polygon(PackedVector2Array([Vector2(3, 4), Vector2(7, 11), Vector2(3, 10)]), Color(0.8, 0.25, 0.22))
	draw_set_transform(Vector2.ZERO)


func _draw_earth(size: Vector2) -> void:
	var offset := _ground_offset()
	var rise := _intro_rise()
	# Seen from the pad, Earth is a huge gentle curve; climbing, it shrinks into a ball.
	var radius := lerpf(size.x * 2.2, size.x * 0.5, smoothstep(0.0, 0.8, rise))
	# Ground surface sits just under the rocket's fins.
	var top: float = size.y - rocket.bottom_gap + 33.0 + offset
	if top - 40.0 > size.y:
		return
	var center := Vector2(size.x / 2.0, top + radius)

	draw_colored_polygon(_circle_points(center, radius + 28.0), Color(0.55, 0.8, 1.0, 0.35))  # atmosphere glow
	draw_colored_polygon(_circle_points(center, radius), Color(0.16, 0.42, 0.85))  # oceans
	# Continents: blobs just inside the surface, spread across the visible top of Earth.
	var land_size := minf(radius * 0.16, size.x * 0.09)
	for land in [[-0.42, 1.0], [-0.18, 1.3], [0.12, 0.9], [0.36, 1.2], [0.58, 0.8]]:
		# Angle offset scaled so blobs stay on screen whether Earth is huge or ball-sized.
		var angle: float = -PI / 2.0 + land[0] * minf(1.0, size.x * 0.9 / radius)
		var blob: float = land_size * land[1]
		var pos: Vector2 = center + Vector2.from_angle(angle) * (radius - blob * 1.05)
		draw_colored_polygon(_circle_points(pos, blob, 24), Color(0.25, 0.62, 0.3))
		draw_colored_polygon(_circle_points(pos + Vector2(blob * 0.6, blob * 0.3), blob * 0.6, 20), Color(0.28, 0.66, 0.33))

	# Launch pad and tower under the rocket.
	var pad_x := size.x / 2.0
	draw_rect(Rect2(pad_x - 60.0, top - 8.0, 120.0, 12.0), Color(0.4, 0.42, 0.45))
	draw_rect(Rect2(pad_x + 38.0, top - 90.0, 8.0, 84.0), Color(0.55, 0.3, 0.25))
	draw_rect(Rect2(pad_x + 20.0, top - 86.0, 26.0, 5.0), Color(0.55, 0.3, 0.25))


func _draw_clouds(size: Vector2, space: float) -> void:
	var offset := _cloud_scroll()
	var alpha := (1.0 - space) * 0.85
	for i in 7:
		var x := fmod(i * 233.0 + 90.0, size.x)
		var y := size.y - 260.0 - i * 170.0 + offset
		if y < -80.0 or y > size.y + 80.0:
			continue
		for puff in [Vector3(0, 0, 38), Vector3(-40, 10, 28), Vector3(42, 8, 30), Vector3(18, -16, 26)]:
			draw_circle(Vector2(x + puff.x, y + puff.y), puff.z, Color(1, 1, 1, alpha))


## Soft round glow (nebulae, planet halos) and sphere shading, made once at startup.
func _make_textures() -> void:
	var glow := Gradient.new()
	glow.set_color(0, Color(1, 1, 1, 1))
	glow.set_color(1, Color(1, 1, 1, 0))
	glow_tex = GradientTexture2D.new()
	glow_tex.width = 128
	glow_tex.height = 128
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.gradient = glow

	# Highlight near the top-left, fading to a dark shadow on the far (bottom-right) side.
	var shade := Gradient.new()
	shade.set_color(0, Color(1, 1, 1, 0.3))
	shade.set_color(1, Color(0, 0, 0, 0.8))
	shade.add_point(0.3, Color(1, 1, 1, 0.0))
	shade.add_point(0.62, Color(0, 0, 0, 0.25))
	shade_tex = GradientTexture2D.new()
	shade_tex.width = 256
	shade_tex.height = 256
	shade_tex.fill = GradientTexture2D.FILL_RADIAL
	shade_tex.fill_from = Vector2(0.33, 0.3)
	shade_tex.fill_to = Vector2(1.0, 0.95)
	shade_tex.gradient = shade


func _circle_points(c: Vector2, r: float, segments: int = 256) -> PackedVector2Array:
	return PlanetNode.circle_points(c, r, segments)
