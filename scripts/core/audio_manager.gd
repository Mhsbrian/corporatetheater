extends Node

# Corporate Theater — Audio Manager
# Procedural ambient audio using AudioStreamGenerator.
# No external audio files needed. Pure GDScript synthesis.

var _ambient_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _ambient_playback: AudioStreamGeneratorPlayback
var _sfx_playback: AudioStreamGeneratorPlayback

const SAMPLE_RATE := 44100.0
const BUFFER_SIZE := 4096

# Ambient oscillator state
var _time := 0.0
var _noise_amp := 0.012
var _base_freq := 55.0  # Low A — sub-bass drone
var _detune_freq := 55.0 * 1.0013  # Slight detuning for beating effect
var _lfo_phase := 0.0
var _lfo_rate := 0.07  # Very slow LFO

# SFX queue
var _sfx_queue: Array = []  # Array of callables that fill sfx buffer

var _enabled := true


func _ready() -> void:
	_setup_ambient()
	_setup_sfx()


func _setup_ambient() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = BUFFER_SIZE / SAMPLE_RATE

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = stream
	_ambient_player.volume_db = -24.0
	_ambient_player.bus = "Master"
	add_child(_ambient_player)
	_ambient_player.play()
	_ambient_playback = _ambient_player.get_stream_playback()


func _setup_sfx() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = 0.15

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.stream = stream
	_sfx_player.volume_db = -18.0
	_sfx_player.bus = "Master"
	add_child(_sfx_player)
	_sfx_player.play()
	_sfx_playback = _sfx_player.get_stream_playback()


func _process(_delta: float) -> void:
	if not _enabled:
		return
	_fill_ambient_buffer()
	_fill_sfx_buffer()


# ── Ambient Drone ─────────────────────────────────────────────────────────────

func _fill_ambient_buffer() -> void:
	if _ambient_playback == null:
		return
	var frames := _ambient_playback.get_frames_available()
	if frames <= 0:
		return

	for _i in range(frames):
		_time += 1.0 / SAMPLE_RATE

		# LFO for subtle volume modulation
		_lfo_phase += _lfo_rate / SAMPLE_RATE
		var lfo := sin(_lfo_phase * TAU) * 0.3 + 0.7

		# Two slightly detuned sine waves for chorus effect
		var s1 := sin(_time * _base_freq * TAU) * 0.4
		var s2 := sin(_time * _detune_freq * TAU) * 0.25
		# Third harmonic — very quiet
		var s3 := sin(_time * _base_freq * 2.0 * TAU) * 0.08

		# Noise floor (very quiet high-freq hiss)
		var noise := (randf() * 2.0 - 1.0) * _noise_amp

		var sample := (s1 + s2 + s3 + noise) * lfo * 0.6
		_ambient_playback.push_frame(Vector2(sample, sample))


# ── SFX ───────────────────────────────────────────────────────────────────────

func _fill_sfx_buffer() -> void:
	if _sfx_playback == null:
		return
	var frames := _sfx_playback.get_frames_available()
	if frames <= 0:
		return
	# Push silence when no SFX queued
	for _i in range(frames):
		_sfx_playback.push_frame(Vector2.ZERO)


# ── Public API ─────────────────────────────────────────────────────────────────

func play_clue_sting() -> void:
	# Short ascending blip — clue discovered
	_play_tone_burst([220.0, 330.0, 440.0], [0.06, 0.06, 0.10], -22.0)


func play_notification() -> void:
	# Very short double blip
	_play_tone_burst([330.0, 440.0], [0.05, 0.05], -26.0)


func play_terminal_keypress() -> void:
	# Single very short click
	_play_tone_burst([880.0], [0.015], -34.0)


func play_contact_unlock() -> void:
	# Slightly more dramatic — new contact
	_play_tone_burst([220.0, 277.0, 330.0, 440.0], [0.07, 0.07, 0.07, 0.14], -20.0)


func play_darkpulse_unlock() -> void:
	# Eerie descending — site unlocked
	_play_tone_burst([660.0, 550.0, 440.0, 330.0], [0.10, 0.10, 0.10, 0.20], -18.0)


func set_ambient_enabled(enabled: bool) -> void:
	_enabled = enabled
	_ambient_player.volume_db = -24.0 if enabled else -80.0


# ── Tone Generator ─────────────────────────────────────────────────────────────

func _play_tone_burst(freqs: Array, durations: Array, volume_db: float) -> void:
	# Create a new one-shot AudioStreamPlayer for the SFX to avoid conflicts
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE

	# Calculate total samples needed
	var total_duration := 0.0
	for d in durations:
		total_duration += d
	total_duration += 0.05  # Tail

	stream.buffer_length = total_duration + 0.1

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()

	var pb: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if pb == null:
		player.queue_free()
		return

	var t := 0.0
	var segment := 0
	var segment_t := 0.0
	var total_samples := int((total_duration + 0.05) * SAMPLE_RATE)

	for s in range(total_samples):
		t = s / SAMPLE_RATE
		# Find which segment we're in
		var acc := 0.0
		segment = freqs.size() - 1
		for i in range(freqs.size()):
			if t < acc + durations[i]:
				segment = i
				segment_t = t - acc
				break
			acc += durations[i]

		var freq: float = freqs[segment]
		var dur: float = durations[segment]
		# Envelope: quick attack, exponential decay
		var env := 1.0
		if segment_t < 0.005:
			env = segment_t / 0.005
		else:
			env = exp(-3.0 * (segment_t - 0.005) / dur)

		var sample := sin(t * freq * TAU) * env * 0.5
		pb.push_frame(Vector2(sample, sample))

	# Clean up after playback
	await get_tree().create_timer(total_duration + 0.1).timeout
	player.queue_free()
