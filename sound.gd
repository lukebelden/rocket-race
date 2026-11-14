extends Node
## Sound effects and music (autoload "Sound"). Everything is synthesised in code at startup,
## so there are no audio files. Volumes go through three buses: Master, Music, Effects
## (Settings screen sliders, saved by game.gd).

const RATE := 22050
## Music only has low notes, so it is made at a lower rate (half the work at startup).
const MUSIC_RATE := 11025
const BUS_MUSIC := "Music"
const BUS_SFX := "Effects"

var _sounds: Dictionary = {}  # name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _next_player := 0
var _engine: AudioStreamPlayer
var _engine_target := 0.0  # 0 = silent, 1 = cruising, 1.6 = boosting
var _engine_level := 0.0
var _engine_seen := 0.0  # seconds since the game last asked for the engine
## Music plays in menus only: the game switches it off on the launch pad and in flight.
var _music_on := true
var _music_level := 1.0
const MUSIC_DB := -2.0


## Menu music on / off (fades, and picks up where it left off).
func music(on: bool) -> void:
	_music_on = on


## Called every frame by the game while the rocket flies: on = engine running.
func engine(on: bool, boosting := false) -> void:
	_engine_target = (1.6 if boosting else 1.0) if on else 0.0
	_engine_seen = 0.0


func _process(delta: float) -> void:
	_music_level = move_toward(_music_level, 1.0 if _music_on else 0.0, delta * 1.2)
	if _music and _music.stream:
		var silent := _music_level <= 0.01
		if _music.stream_paused != silent:
			_music.stream_paused = silent
		_music.volume_db = MUSIC_DB + linear_to_db(maxf(_music_level, 0.001))
	# The game stops asking when paused / on menus: fade the rumble out.
	_engine_seen += delta
	if _engine_seen > 0.2 or get_tree().paused:
		_engine_target = 0.0
	_engine_level = move_toward(_engine_level, _engine_target, delta * 2.5)
	if _engine_level <= 0.01:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.volume_db = linear_to_db(_engine_level * 0.5)
	_engine.pitch_scale = 0.85 + 0.25 * _engine_level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus make sounds while the game is paused
	_make_buses()
	# Every button in the game clicks: ones added from now on, plus the main scene's own
	# buttons (those are already in the tree before this autoload starts listening).
	get_tree().node_added.connect(_hook_button)
	_hook_all.call_deferred(get_tree().root)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	_music.volume_db = MUSIC_DB
	add_child(_music)
	_build_sounds()
	# Engine rumble: a looping player the game turns up/down every frame while flying.
	_engine = AudioStreamPlayer.new()
	_engine.bus = BUS_SFX
	_engine.stream = _wav(_engine_loop(), true)
	_engine.volume_db = -60.0
	add_child(_engine)
	# Music takes a moment to synthesise: do it after the first frames so startup stays quick.
	await get_tree().process_frame
	await get_tree().process_frame
	_music.stream = _make_music()
	_music.play()


# --- Volume ------------------------------------------------------------------------------

func _make_buses() -> void:
	for bus in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


## volume: 0.0 (silent) .. 1.0 (full). bus: "Master", "Music" or "Effects".
func set_volume(bus: String, volume: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, volume <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.001)))


## Give a button its click + hover sounds (once: buttons moved to a new parent are
## "added" again).
func _hook_button(n: Node) -> void:
	if not n is BaseButton or n.has_meta("_sound_hooked"):
		return
	n.set_meta("_sound_hooked", true)
	n.pressed.connect(play.bind("click"))
	# Soft tick when the mouse moves onto a button (or keyboard focus lands on it).
	n.mouse_entered.connect(_hover.bind(n))
	n.focus_entered.connect(func() -> void:
		if _keyboard_nav:  # arrows / Tab / gamepad, not a click or a menu opening
			_hover(n))


func _hook_all(node: Node) -> void:
	_hook_button(node)
	for child in node.get_children():
		_hook_all(child)


## Hover tick: only for buttons you can press, and never twice within a blink (mouse
## enter + focus arriving together, or sweeping fast across a row of buttons).
var _last_hover := 0
var _keyboard_nav := false


func _input(event: InputEvent) -> void:
	# Remember whether the player is moving around menus with keys/gamepad or the mouse.
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var nav := event.is_action("ui_up") or event.is_action("ui_down") or event.is_action("ui_left") \
			or event.is_action("ui_right") or event.is_action("ui_focus_next") or event.is_action("ui_focus_prev")
		_keyboard_nav = nav and event.is_pressed()
	elif event is InputEventMouseButton or event is InputEventScreenTouch:
		_keyboard_nav = false


func _hover(button: BaseButton) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return
	var now := Time.get_ticks_msec()
	if now - _last_hover < 60:
		return
	_last_hover = now
	play("hover", randf_range(0.97, 1.03), -3.0)


func play(sound_name: String, pitch := 1.0, volume_db := 0.0) -> void:
	var stream: AudioStreamWAV = _sounds.get(sound_name)
	if stream == null:
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


# --- Synthesis -----------------------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop := false, rate := RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## A tone that slides from f0 to f1 Hz. wave: "sine", "square", "tri", "noise".
func _tone(length: float, f0: float, f1: float, wave := "sine", attack := 0.005, gain := 0.6) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var noise_hold := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		phase += f / RATE
		var s := 0.0
		match wave:
			"sine": s = sin(phase * TAU)
			"square": s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			"tri": s = 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
			"noise":
				# Sample-and-hold noise: "f" sets how rough it sounds.
				if fmod(phase, 1.0) < f / RATE:
					noise_hold = randf_range(-1.0, 1.0)
				s = noise_hold
		var env := minf(float(i) / maxf(attack * RATE, 1.0), 1.0) * pow(1.0 - t, 2.0)
		out[i] = s * env * gain
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset := 0.0) -> PackedFloat32Array:
	var start := int(offset * RATE)
	var out := a.duplicate()
	if out.size() < start + b.size():
		out.resize(start + b.size())
	for i in b.size():
		out[start + i] += b[i]
	return out


## Scale a sound so its loudest point is `peak` (they were all made at different levels,
## and several were too quiet to hear on laptop / phone speakers).
func _norm(samples: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var top := 0.0
	for s in samples:
		top = maxf(top, absf(s))
	if top < 0.0001:
		return samples
	var k := peak / top
	var out := samples.duplicate()
	for i in out.size():
		out[i] *= k
	return out


## Seamless 2-second rocket rumble: deep filtered noise plus a low throb.
func _engine_loop() -> PackedFloat32Array:
	var n := 2 * RATE
	var fade := int(0.25 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var lp := 0.0
	var lp2 := 0.0
	for i in raw.size():
		lp += (randf_range(-1.0, 1.0) - lp) * 0.06
		lp2 += (lp - lp2) * 0.12
		var t := float(i) / RATE
		raw[i] = lp2 * 6.0 + 0.18 * sin(TAU * 48.0 * t) * (0.7 + 0.3 * sin(TAU * 3.0 * t))
	# Crossfade the tail into the head so the loop has no click.
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
		if i < fade:
			var w := float(i) / fade
			out[i] = raw[i] * w + raw[n + i] * (1.0 - w)
	return _norm(out, 0.8)


func _build_sounds() -> void:
	_sounds["click"] = _wav(_tone(0.05, 900, 700, "tri", 0.002, 0.35))
	# Hover: a short, soft rising blip (quieter and higher than the click).
	_sounds["hover"] = _wav(_mix(_tone(0.035, 1500, 1900, "sine", 0.002, 0.3), _tone(0.03, 3000, 3600, "sine", 0.002, 0.08)))
	_sounds["beep"] = _wav(_tone(0.14, 660, 660, "square", 0.003, 0.18))
	_sounds["go"] = _wav(_tone(0.35, 990, 990, "square", 0.003, 0.2))
	_sounds["launch"] = _wav(_mix(_tone(1.6, 900, 300, "noise", 0.15, 0.45), _tone(1.6, 55, 90, "sine", 0.2, 0.5)))
	_sounds["boost"] = _wav(_tone(0.45, 1400, 3000, "noise", 0.05, 0.3))
	_sounds["impact"] = _wav(_mix(_tone(0.35, 2200, 400, "noise", 0.001, 0.6), _tone(0.3, 140, 50, "sine", 0.001, 0.7)))
	_sounds["explosion"] = _wav(_mix(_tone(1.2, 1600, 150, "noise", 0.001, 0.7), _tone(1.0, 90, 30, "sine", 0.001, 0.8)))
	_sounds["missile"] = _wav(_tone(0.4, 3000, 1200, "noise", 0.005, 0.35))
	_sounds["dock"] = _wav(_mix(_tone(0.25, 523, 523, "tri", 0.005, 0.4), _tone(0.4, 784, 784, "tri", 0.005, 0.4), 0.12))
	var chime := _tone(0.2, 523, 523, "tri", 0.004, 0.35)
	chime = _mix(chime, _tone(0.2, 659, 659, "tri", 0.004, 0.35), 0.1)
	chime = _mix(chime, _tone(0.45, 784, 784, "tri", 0.004, 0.35), 0.2)
	_sounds["level"] = _wav(chime)
	var fanfare := chime.duplicate()
	fanfare = _mix(fanfare, _tone(0.6, 1047, 1047, "square", 0.004, 0.18), 0.35)
	_sounds["levelup"] = _wav(fanfare)
	_sounds["coin"] = _wav(_mix(_tone(0.08, 988, 988, "square", 0.002, 0.15), _tone(0.3, 1319, 1319, "square", 0.002, 0.15), 0.07))
	_sounds["pause"] = _wav(_mix(_tone(0.12, 660, 660, "tri", 0.003, 0.3), _tone(0.18, 440, 440, "tri", 0.003, 0.3), 0.08))
	# Booster pods unlatching: metal clunk + hiss.
	_sounds["detach"] = _wav(_mix(_mix(_tone(0.18, 320, 120, "square", 0.001, 0.4), _tone(0.12, 180, 90, "sine", 0.001, 0.6)),
		_tone(0.5, 4000, 1500, "noise", 0.01, 0.25), 0.05))
	# Warning: two quick falling beeps (low fuel / hull damage).
	_sounds["alarm"] = _wav(_mix(_tone(0.13, 880, 880, "square", 0.003, 0.3), _tone(0.16, 660, 660, "square", 0.003, 0.3), 0.15))
	# Bring every effect up to the same, clearly audible level.
	var peaks := {"hover": 0.32, "click": 0.55, "beep": 0.6, "go": 0.65, "coin": 0.6, "pause": 0.6, "alarm": 0.6}
	for key in _sounds:
		var wav: AudioStreamWAV = _sounds[key]
		var samples := PackedFloat32Array()
		samples.resize(wav.data.size() / 2)
		for i in samples.size():
			samples[i] = wav.data.decode_s16(i * 2) / 32000.0
		_sounds[key] = _wav(_norm(samples, float(peaks.get(key, 0.9))))


## A calm 16-second space loop: slow pad chords plus a soft arpeggio.
func _make_music() -> AudioStreamWAV:
	var bar := 4.0  # seconds per chord
	# Am - F - C - G (root frequencies of each chord's notes)
	var chords := [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [261.63, 329.63, 392.0], [196.0, 246.94, 293.66]]
	var n := int(bar * chords.size() * MUSIC_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var step := 0.5  # arpeggio note length
	for i in n:
		var t := float(i) / MUSIC_RATE
		var ci := int(t / bar) % chords.size()
		var chord: Array = chords[ci]
		var in_bar := fmod(t, bar)
		# Pad: soft sine chord, swelling in and out over each bar (so the loop is seamless).
		var swell := sin(PI * in_bar / bar)
		var pad := 0.0
		for f in chord:
			pad += sin(TAU * f * 0.5 * t) + 0.3 * sin(TAU * f * t)
		pad *= 0.045 * (0.35 + 0.65 * swell)
		# Arpeggio: chord notes an octave up, each plucked and fading.
		var ai := int(in_bar / step)
		var note: float = chord[ai % chord.size()] * (2.0 if ai % 6 < 3 else 4.0)
		var at := fmod(in_bar, step)
		var arp := sin(TAU * note * t) * exp(-at * 6.0) * 0.06
		out[i] = pad + arp
	return _wav(_norm(out, 0.7), true, MUSIC_RATE)
