extends Node
## Autoload "Sfx": fire-and-forget sound effects. Missing sound files are silently ignored, so
## gameplay code can call Sfx.play() before the audio exists. OWNER: orchestrator (audio pass).
##
##   Sfx.play("hit_flesh", enemy.global_position)   # positional (3D)
##   Sfx.play_ui("ui_click")                        # non-positional
##
## Files: res://assets/audio/<id>.wav (or .ogg). Sound ids are listed in docs/ARCHITECTURE.md §17.

const AUDIO_DIR := "res://assets/audio/"
const POOL_2D := 12
const POOL_3D := 24
const MAX_SAME_ID := 4          # concurrent voices of one id
const MIN_INTERVAL := 0.03      # seconds between two starts of the same id

var master_volume_db := 0.0
var _streams: Dictionary = {}     # id -> AudioStream or null
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _last_play: Dictionary = {}   # id -> msec


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 12.0
		p3.max_distance = 60.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_players_3d.append(p3)


## Play a sound. With a Vector3 position it is positional, otherwise it is played as UI audio.
func play(id: String, position: Variant = null, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var stream := _get_stream(id)
	if stream == null or not _may_play(id):
		return
	var pitch := 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	if position is Vector3:
		var p3 := _free_player_3d()
		if p3 == null:
			return
		p3.stream = stream
		p3.global_position = position
		p3.volume_db = volume_db + master_volume_db
		p3.pitch_scale = pitch
		p3.set_meta("sfx_id", id)
		p3.play()
	else:
		var p := _free_player_2d()
		if p == null:
			return
		p.stream = stream
		p.volume_db = volume_db + master_volume_db
		p.pitch_scale = pitch
		p.set_meta("sfx_id", id)
		p.play()


func play_ui(id: String, volume_db: float = 0.0) -> void:
	play(id, null, volume_db, 0.0)


func has_sound(id: String) -> bool:
	return _get_stream(id) != null


func _get_stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var stream: AudioStream = null
	for ext in [".wav", ".ogg"]:
		var path: String = AUDIO_DIR + id + ext
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			break
	_streams[id] = stream
	return stream


func _may_play(id: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(id, -100000)) < int(MIN_INTERVAL * 1000.0):
		return false
	var active := 0
	for p in _players_3d:
		if p.playing and p.get_meta("sfx_id", "") == id:
			active += 1
	for p in _players_2d:
		if p.playing and p.get_meta("sfx_id", "") == id:
			active += 1
	if active >= MAX_SAME_ID:
		return false
	_last_play[id] = now
	return true


func _free_player_2d() -> AudioStreamPlayer:
	for p in _players_2d:
		if not p.playing:
			return p
	return null


func _free_player_3d() -> AudioStreamPlayer3D:
	for p in _players_3d:
		if not p.playing:
			return p
	return null
