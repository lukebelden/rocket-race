extends Node2D
## Rocket Dodge: launch from Earth, fly past the planets, dodge the asteroids.

const Obstacle := preload("res://obstacle.gd")
const Station := preload("res://station.gd")
const Rocket := preload("res://rocket.gd")
const PlanetNode := preload("res://planet.gd")
const StarLayer := preload("res://star_layer.gd")
const SAVE_PATH := "user://save.cfg"

## MENU -> READY (on the launch pad, waiting for Space/tap) -> INTRO (liftoff) -> PLAYING -> OVER
enum State { MENU, READY, INTRO, PLAYING, OVER }
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

@onready var settings: Control = $UI/Root/Settings
@onready var difficulty_option: OptionButton = $UI/Root/Settings/Panel/VBox/DifficultyRow/DifficultyOption
@onready var fullscreen_check: CheckButton = $UI/Root/Settings/Panel/VBox/FullscreenCheck
@onready var reset_button: Button = $UI/Root/Settings/Panel/VBox/ResetButton
@onready var back_button: Button = $UI/Root/Settings/Panel/VBox/BackButton

@onready var game_over: Control = $UI/Root/GameOver
@onready var result_label: Label = $UI/Root/GameOver/Panel/VBox/ResultLabel
@onready var game_over_title: Label = $UI/Root/GameOver/Panel/VBox/Title
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
	_update_layout()
	get_window().size_changed.connect(_update_layout)
	rocket.booster_lost.connect(_on_booster_lost)
	fuel_label.text = "BOOST FUEL" if touch_ui else "BOOST FUEL  [Shift]"
	dashboard.visible = false

	var size := get_viewport_rect().size
	rocket.position = Vector2(size.x / 2.0, size.y - rocket.bottom_gap)
	rocket.area_entered.connect(_on_rocket_hit)

	# Menu
	start_button.pressed.connect(_go_to_pad)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	# A web page can't close its own tab, so Quit would only freeze the game there.
	quit_button.visible = not OS.has_feature("web")
	hint_label.text = ("Hold and drag to steer\nHold BOOST to fly faster" if touch_ui
		else "Move: Left / Right or A / D\nBoost (fly faster): Shift or Space")

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
	if state == State.READY or state == State.PLAYING or state == State.OVER:
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
	var dynamic := state == State.INTRO or not smoke.is_empty() or not fragments.is_empty() or not pods.is_empty()
	if dynamic or _drew_dynamic:
		queue_redraw()
	_drew_dynamic = dynamic


func _unhandled_input(event: InputEvent) -> void:
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
	settings.visible = false
	game_over.visible = false
	launch_prompt.visible = false
	menu.visible = true
	start_button.grab_focus()
	queue_redraw()


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
	var target_speed := FORWARD_BOOST if rocket.boosting else 1.0
	forward_speed = move_toward(forward_speed, target_speed, FORWARD_EASE * delta)
	Obstacle.world_speed = forward_speed
	var travelled := delta * forward_speed

	score += travelled * 10.0
	level_time += travelled
	if level_time >= LEVEL_DURATION:
		level += 1
		level_time = 0.0
		_show_level_banner()
	_update_hud()

	# Refuel station after every two planets (Levels 3, 5, 7, ...), a few seconds into the level.
	if level >= 3 and (level - 1) % 2 == 0 and station_level != level and level_time >= 3.0:
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
	var boost_key := "the BOOST button" if touch_ui else "Shift / Space"
	return [
		"Hold %s to boost: you fly and score faster, but asteroids come at you quicker too." % boost_key,
		"Your booster can be refilled at refuel stations. One appears every two planets.",
		"If your booster runs completely dry it detaches, and you can't get it back.",
		"Refuel stations also repair 25% of your hull. Fly straight into one to dock.",
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
		tip = _once("station_%d" % level, "Station in range: fly into it to dock, refuel the booster and repair the hull.")
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

## Keyboard keys for boosting: Shift, Space, W or Up arrow.
func _setup_boost_input() -> void:
	if InputMap.has_action("boost"):
		return
	InputMap.add_action("boost")
	for key in [KEY_SHIFT, KEY_SPACE, KEY_W, KEY_UP]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event("boost", event)


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
	# Just above the console, bottom right.
	boost_button.position = Vector2(size.x - 128.0 - 30.0, size.y - cockpit.dash_height - 128.0 - 14.0)
	# Touches starting on the button boost instead of steering.
	rocket.no_steer_rect = Rect2(boost_button.position, Vector2(128, 128)).grow(16.0)


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
		_set_label(fuel_label, ("FUEL LOW" if low_fuel else "BOOST FUEL") + ("" if touch_ui else "  [Shift]"), Color(1, 0.75, 0.35))

	# Hull integrity: green -> yellow -> red, flashing when critical.
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


func _is_station_level(lvl: int) -> bool:
	return lvl >= 3 and (lvl - 1) % 2 == 0


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


## Docking at the station: repairs 25% hull and refills the booster (if you still have it).
func _on_station_reached(station: Area2D) -> void:
	if station.used:
		return
	station.used = true
	station_docked = true
	var repaired := minf(1.0 - hull, STATION_REPAIR)
	hull += repaired
	var parts: Array[String] = []
	parts.append("HULL +%d%%" % roundi(repaired * 100.0) if repaired > 0.0 else "HULL OK")
	parts.append("FUEL FULL" if rocket.refuel() else "NO BOOSTER")
	_show_toast("DOCKED:  " + "   ".join(parts), Color(0.45, 1, 0.6))


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


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.set_value("settings", "difficulty", difficulty)
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
	rock.position = Vector2(randf_range(radius, size.x - radius), -radius)
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
	var show_planet := state == State.PLAYING or state == State.OVER
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
	rocket.boost_button_held = false
	rocket.active = false
	rocket.modulate = Color(1.0, 0.4, 0.3)
	rocket.flame_on = false

	var new_best := score > best_score
	if new_best:
		best_score = score
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
