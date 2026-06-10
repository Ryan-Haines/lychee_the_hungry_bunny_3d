class_name GameAudio
extends Node

# All audio is synthesized at startup - no asset files.
# SFX are pre-baked AudioStreamWAV buffers; music is a 16-step sequencer
# whose pattern, scale and tempo follow the current game mood.

const MIX_RATE := 22050

const MOOD_BPM = {
	"calm": 92.0,
	"sneaky": 100.0,
	"urgent": 150.0,
	"human": 84.0,
	"night": 70.0,
	"zoomie": 126.0,
}

const SCALE_MAJOR_PENT = [0, 2, 4, 7, 9]
const SCALE_MINOR_PENT = [0, 3, 5, 7, 10]

var sounds := {}
var pluck_stream: AudioStreamWAV
var bass_stream: AudioStreamWAV
var sfx_pool: Array[AudioStreamPlayer] = []
var music_pool: Array[AudioStreamPlayer] = []

var mood := "calm"
var step := 0
var step_acc := 0.0


func _ready() -> void:
	_build_sounds()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_pool.append(p)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		music_pool.append(p)


func sfx(sound_name: String, vol := 1.0, jitter := 0.08) -> void:
	if not sounds.has(sound_name):
		return
	var p := _grab(sfx_pool)
	p.stream = sounds[sound_name]
	p.volume_db = linear_to_db(clampf(vol, 0.05, 1.5))
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.play()


func set_mood(m: String) -> void:
	if m == mood or not MOOD_BPM.has(m):
		return
	mood = m
	step = 0
	step_acc = 0.0


func _process(delta: float) -> void:
	# Music keeps its own clock so poop-time slow motion doesn't drag the beat.
	step_acc += delta / maxf(Engine.time_scale, 0.05)
	var spb: float = 60.0 / MOOD_BPM[mood] / 2.0  # 8th notes
	while step_acc >= spb:
		step_acc -= spb
		_play_step(step)
		step = (step + 1) % 16


# --- sequencer ---------------------------------------------------------------

func _play_step(s: int) -> void:
	match mood:
		"calm":
			# Cozy major pentatonic noodling over a slow root-fifth bass.
			if s == 0:
				_note(bass_stream, 45, 36, 0.5)
			elif s == 8:
				_note(bass_stream, 45, 43, 0.45)
			if s % 2 == 0 and randf() < 0.4:
				var off: int = SCALE_MAJOR_PENT[randi() % 5]
				_note(pluck_stream, 69, 72 + off + (12 if randf() < 0.25 else 0), 0.2)
		"sneaky":
			# Syncopated minor bass: there is evidence on the floor.
			var bass_steps := {0: 33, 6: 33, 8: 36, 14: 38}
			if bass_steps.has(s):
				_note(bass_stream, 45, bass_steps[s], 0.5)
			if s % 4 == 2 and randf() < 0.35:
				_note(pluck_stream, 69, 69 + SCALE_MINOR_PENT[randi() % 5], 0.14)
		"urgent":
			# Driving octave bass and descending runs: find the litter box NOW.
			if s % 2 == 0:
				_note(bass_stream, 45, 33 + (12 if (s / 2) % 2 == 1 else 0), 0.55)
			if randf() < 0.55:
				_note(pluck_stream, 69, 81 - SCALE_MINOR_PENT[(15 - s) % 5], 0.18)
		"human":
			# Sparse and low. The human is looking.
			if s == 0:
				_note(bass_stream, 45, 31, 0.5)
			if s == 10 and randf() < 0.6:
				_note(pluck_stream, 69, 79, 0.12)  # nervous tritone blip
		"night":
			# Lullaby.
			if s == 0:
				_note(bass_stream, 45, 36, 0.32)
			if s % 4 == 0 and randf() < 0.7:
				_note(pluck_stream, 69, 72 + [0, 4, 7, 9][randi() % 4], 0.14)
		"zoomie":
			# Bouncy evening energy.
			if s % 4 == 0:
				_note(bass_stream, 45, 38 + (7 if (s / 4) % 2 == 1 else 0), 0.5)
			if s % 2 == 0 and randf() < 0.6:
				_note(pluck_stream, 69, 74 + SCALE_MAJOR_PENT[randi() % 5] + 12, 0.18)


func _note(stream: AudioStreamWAV, base_midi: int, midi: int, vol: float) -> void:
	var p := _grab(music_pool)
	p.stream = stream
	p.pitch_scale = pow(2.0, float(midi - base_midi) / 12.0)
	p.volume_db = linear_to_db(clampf(vol, 0.03, 1.0))
	p.play()


func _grab(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return pool[randi() % pool.size()]


# --- sound bank ---------------------------------------------------------------

func _build_sounds() -> void:
	sounds["hop"] = _wav(_sweep(190, 115, 0.09, 0.45, 4.5, 0.05))
	sounds["land"] = _wav(_sweep(150, 85, 0.07, 0.32, 5.0, 0.25))
	sounds["eat"] = _wav(_crunch())
	sounds["drink"] = _wav(_concat([
		_sweep(330, 430, 0.06, 0.3, 2.0), _silence(0.06),
		_sweep(380, 510, 0.06, 0.3, 2.0), _silence(0.05),
		_sweep(430, 590, 0.06, 0.28, 2.0),
	]))
	# Slide-whistle down, then a thud. The dramatic flop deserves it.
	sounds["flop"] = _wav(_concat([
		_sweep(950, 280, 0.32, 0.3, 2.0),
		_sweep(130, 70, 0.12, 0.55, 4.0, 0.3),
	]))
	sounds["binky"] = _wav(_sweep(480, 980, 0.16, 0.3, 2.5))
	sounds["knock"] = _wav(_sweep(260, 170, 0.07, 0.6, 6.0, 0.12))
	sounds["plop"] = _wav(_concat([
		_sweep(420, 90, 0.13, 0.55, 3.0), _silence(0.05),
		_sweep(300, 80, 0.09, 0.35, 4.0),
	]))
	sounds["pee"] = _wav(_trickle(1.0))
	sounds["boop"] = _wav(_sweep(340, 250, 0.08, 0.4, 4.0))
	sounds["ding"] = _wav(_ding(880.0, 0.3))
	sounds["buzz"] = _wav(_buzz())
	sounds["alert"] = _wav(_concat([
		_sweep(700, 700, 0.09, 0.4, 1.5), _silence(0.04),
		_sweep(940, 940, 0.12, 0.4, 2.0),
	]))
	sounds["rattle"] = _wav(_concat([
		_sweep(420, 300, 0.05, 0.5, 5.0, 0.4), _silence(0.04),
		_sweep(380, 280, 0.05, 0.45, 5.0, 0.4), _silence(0.05),
		_sweep(440, 320, 0.06, 0.5, 5.0, 0.4),
	]))
	var thud := _sweep(95, 58, 0.11, 0.55, 5.0, 0.2)
	sounds["steps"] = _wav(_concat([thud, _silence(0.22), thud, _silence(0.22), thud]))
	sounds["bust"] = _wav(_bust())
	sounds["fanfare"] = _wav(_concat([
		_pluck(523.25, 0.12), _pluck(659.25, 0.12), _pluck(784.0, 0.12), _pluck(1046.5, 0.4),
	]))
	pluck_stream = _wav(_pluck(440.0, 0.45))
	bass_stream = _wav(_pluck(110.0, 0.55))


# --- synthesis ---------------------------------------------------------------

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	wav.data = bytes
	return wav


func _sweep(f0: float, f1: float, dur: float, amp: float, decay: float, noise := 0.0) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / float(n)
		phase += TAU * lerpf(f0, f1, k) / MIX_RATE
		var s := sin(phase)
		if noise > 0.0:
			s = lerpf(s, randf() * 2.0 - 1.0, noise)
		out[i] = s * amp * exp(-decay * k)
	return out


func _pluck(freq: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / float(n)
		phase += TAU * freq / MIX_RATE
		var s := sin(phase) + 0.4 * sin(phase * 2.0) + 0.15 * sin(phase * 3.0)
		out[i] = s * 0.5 * exp(-5.0 * k)
	return out


func _ding(freq: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var k := float(i) / float(n)
		p1 += TAU * freq / MIX_RATE
		p2 += TAU * freq * 2.4 / MIX_RATE
		out[i] = (sin(p1) * 0.7 + sin(p2) * 0.3) * 0.5 * exp(-7.0 * k)
	return out


func _buzz() -> PackedFloat32Array:
	var n := int(0.18 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / float(n)
		phase += TAU * 110.0 / MIX_RATE
		var s := 1.0 if fmod(phase, TAU) < PI else -1.0
		out[i] = s * 0.25 * exp(-5.0 * k)
	return out


func _crunch() -> PackedFloat32Array:
	var n := int(0.08 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var k := float(i) / float(n)
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.45)
		out[i] = lp * 0.9 * exp(-5.0 * k)
	return out


func _trickle(dur: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var k := float(i) / float(n)
		var v := randf() * 2.0 - 1.0
		lp = lerpf(lp, v, 0.25)
		var hp := v - lp
		var env := minf(k * 8.0, 1.0) * minf((1.0 - k) * 4.0, 1.0)
		var wobble := 0.7 + 0.3 * sin(TAU * 8.0 * k * dur) * sin(TAU * 2.3 * k * dur)
		out[i] = hp * 0.35 * env * wobble
	return out


func _bust() -> PackedFloat32Array:
	var n := int(0.9 * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	var p3 := 0.0
	for i in n:
		var k := float(i) / float(n)
		p1 += TAU * 98.0 / MIX_RATE
		p2 += TAU * 104.0 / MIX_RATE
		p3 += TAU * 49.0 / MIX_RATE
		out[i] = (sin(p1) * 0.35 + sin(p2) * 0.35 + sin(p3) * 0.3) * 0.6 * exp(-2.5 * k)
	return out


func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * MIX_RATE))
	return out


func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part in parts:
		out.append_array(part)
	return out
