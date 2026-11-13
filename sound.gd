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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus make sounds while the game is paused
	_make_buses()
	# Every button in the game clicks.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton:
			n.pressed.connect(play.bind("click")))
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	_music.volume_db = -6.0
	add_child(_music)
	_build_sounds()
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


func _build_sounds() -> void:
	_sounds["click"] = _wav(_tone(0.05, 900, 700, "tri", 0.002, 0.35))
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
	return _wav(out, true, MUSIC_RATE)
