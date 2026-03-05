extends Node

# Corporate Theater — Audio Manager
# Procedural ambient audio using AudioStreamGenerator.
# Ambient drone fills buffer each _process frame (safe).
# SFX uses pre-baked AudioStreamWAV samples (no sync loop issues).

const SAMPLE_RATE := 44100.0

# Ambient oscillator state
var _time := 0.0
var _lfo_phase := 0.0
var _base_freq := 55.0
var _detune_freq := 55.0 * 1.0013
var _noise_amp := 0.012
var _lfo_rate := 0.07

var _ambient_player: AudioStreamPlayer = null
var _ambient_playback: AudioStreamGeneratorPlayback = null
var _enabled := true


func _ready() -> void:
	_setup_ambient()


func _setup_ambient() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = SAMPLE_RATE
	stream.buffer_length = 0.2  # 200ms buffer — safe for _process fill

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = stream
	_ambient_player.volume_db = -28.0
	add_child(_ambient_player)
	_ambient_player.play()
	# Defer playback grab so it's valid after play()
	_ambient_playback = _ambient_player.get_stream_playback()


func _process(_delta: float) -> void:
	if not _enabled or _ambient_playback == null:
		return
	_fill_ambient_buffer()


func _fill_ambient_buffer() -> void:
	var frames := _ambient_playback.get_frames_available()
	if frames <= 0:
		return
	for _i in range(frames):
		_time += 1.0 / SAMPLE_RATE
		_lfo_phase += _lfo_rate / SAMPLE_RATE

		var lfo: float = sin(_lfo_phase * TAU) * 0.25 + 0.75
		var s1: float = sin(_time * _base_freq * TAU) * 0.35
		var s2: float = sin(_time * _detune_freq * TAU) * 0.20
		var s3: float = sin(_time * _base_freq * 2.0 * TAU) * 0.06
		var noise := (randf() * 2.0 - 1.0) * _noise_amp
		var sample := (s1 + s2 + s3 + noise) * lfo * 0.55

		_ambient_playback.push_frame(Vector2(sample, sample))


# ── SFX — pre-baked WAV samples ───────────────────────────────────────────────

func play_clue_sting() -> void:
	_play_wav(_bake_tone_burst([220.0, 330.0, 440.0], [0.06, 0.06, 0.10]), -22.0)


func play_notification() -> void:
	_play_wav(_bake_tone_burst([330.0, 440.0], [0.05, 0.05]), -26.0)


func play_terminal_keypress() -> void:
	_play_wav(_bake_tone_burst([880.0], [0.015]), -34.0)


func play_contact_unlock() -> void:
	_play_wav(_bake_tone_burst([220.0, 277.0, 330.0, 440.0], [0.07, 0.07, 0.07, 0.14]), -20.0)


func play_darkpulse_unlock() -> void:
	_play_wav(_bake_tone_burst([660.0, 550.0, 440.0, 330.0], [0.10, 0.10, 0.10, 0.20]), -18.0)


func set_ambient_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _ambient_player:
		_ambient_player.volume_db = -28.0 if enabled else -80.0


# ── WAV baker ─────────────────────────────────────────────────────────────────

func _bake_tone_burst(freqs: Array, durations: Array) -> AudioStreamWAV:
	var total_dur := 0.0
	for d in durations:
		total_dur += d
	total_dur += 0.04  # Silence tail

	var num_samples := int(total_dur * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit mono

	for s in range(num_samples):
		var t := s / SAMPLE_RATE

		# Find segment
		var seg := freqs.size() - 1
		var seg_t := 0.0
		var acc := 0.0
		for i in range(freqs.size()):
			if t < acc + durations[i]:
				seg = i
				seg_t = t - acc
				break
			acc += durations[i]

		var freq: float = freqs[seg]
		var dur: float = durations[seg]

		# Envelope
		var env: float
		if seg_t < 0.005:
			env = seg_t / 0.005
		else:
			env = exp(-4.0 * (seg_t - 0.005) / maxf(dur, 0.001))

		var raw: float = sin(t * freq * TAU) * env * 0.45
		var pcm := int(clampf(raw, -1.0, 1.0) * 32767.0)

		# Little-endian 16-bit
		data[s * 2]     = pcm & 0xFF
		data[s * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = int(SAMPLE_RATE)
	wav.data = data
	return wav


func _play_wav(wav: AudioStreamWAV, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = wav
	player.volume_db = volume_db
	add_child(player)
	player.play()
	# Auto-free when done
	player.finished.connect(player.queue_free)
