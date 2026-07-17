# AudioManager.gd
# All game audio (DEP-5). An autoload holding a small pool of one-shot SFX
# players and a two-player crossfading music bed whose track follows the current
# view. Volumes (master / SFX / music) live in SettingsManager, so they persist
# outside the run save and survive hard resets.
#
# How sounds get triggered:
#   - SFX via existing SIGNALS (no caller changes): harvest_completed ->
#     harvest tick, node_broken -> item pickup.
#   - SFX via a one-line play_sfx() call at the source: level-up (GameManager),
#     structure built (GroundsManager), combat hit (CombatView), UI nav click
#     (NavigationPanel).
#   - MUSIC follows view changes: AudioManager is in the "view_manager" group and
#     implements switch_view(), so Control's broadcast picks the right track.
#
# Assets: audio/sfx/<id>.wav (see Ids.SFX_*), audio/music/amb_<view>.wav.
# Talks to: Ids, SettingsManager, GameManager, GroundsManager (signals).
extends Node

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const SFX_VOICES := 6        ## overlapping one-shots before the pool wraps
const MUSIC_FADE := 1.2      ## crossfade seconds when the track changes
const SILENCE_DB := -60.0

## Which ambient track each view plays. Overlays (Grounds/Settings/book) don't
## switch views, so the music simply persists under them.
var _view_music := {
	Ids.VIEW_GRAVEYARD: "amb_graveyard",
	Ids.VIEW_INVENTORY: "amb_graveyard",
	Ids.VIEW_SHOP: "amb_graveyard",
	Ids.VIEW_FOREST: "amb_forest",
	Ids.VIEW_ALCHEMY: "amb_alchemy",
	Ids.VIEW_FORGE: "amb_quarry",
	Ids.VIEW_QUARRY: "amb_quarry",
	Ids.VIEW_COMBAT: "amb_combat",
}

var _sfx_streams: Dictionary = {}   # id -> AudioStream
var _sfx_players: Array = []        # pool of AudioStreamPlayer
var _sfx_next: int = 0

var _music_tracks: Dictionary = {}  # track_id -> AudioStream (loop-enabled)
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _music_key: String = ""

func _ready() -> void:
	add_to_group(Ids.GROUP_VIEW_MANAGER)  # receives switch_view broadcasts
	_load_sfx()
	_build_players()
	_connect_signals()

# --- Setup ---

func _load_sfx() -> void:
	for sfx_id in Ids.SFX_ALL:
		var path := SFX_DIR + sfx_id + ".wav"
		if ResourceLoader.exists(path):
			_sfx_streams[sfx_id] = load(path)
		elif OS.is_debug_build():
			push_warning("AudioManager: missing SFX asset " + path)

func _build_players() -> void:
	for i in range(SFX_VOICES):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_music_a.volume_db = SILENCE_DB
	_music_b.volume_db = SILENCE_DB
	add_child(_music_a)
	add_child(_music_b)
	_music_current = _music_a

## Free feedback with zero coupling: the sound-worthy events these managers
## already emit become audio without the emitters knowing AudioManager exists.
func _connect_signals() -> void:
	if not GameManager.harvest_completed.is_connected(_on_harvest_completed):
		GameManager.harvest_completed.connect(_on_harvest_completed)
	if not GameManager.node_broken.is_connected(_on_node_broken):
		GameManager.node_broken.connect(_on_node_broken)

func _on_harvest_completed(_node_id: String) -> void:
	play_sfx(Ids.SFX_HARVEST_TICK)

func _on_node_broken(_node_id: String) -> void:
	play_sfx(Ids.SFX_ITEM_PICKUP)

# --- SFX ---

## Plays a one-shot sound by id (see Ids.SFX_*). Round-robins a small player
## pool so rapid sounds overlap instead of cutting each other off. Unknown or
## unloaded ids are a no-op.
func play_sfx(sfx_id: String) -> void:
	var stream = _sfx_streams.get(sfx_id, null)
	if stream == null:
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = _sfx_db()
	player.play()

# --- Music ---

## Group "view_manager" hook: the same broadcast that switches views picks the
## ambient track. Named to match Control/TutorialManager.switch_view.
func switch_view(view_name: String) -> void:
	play_music(_view_music.get(view_name, "amb_graveyard"))

## Crossfades the ambient bed to `track_id` (audio/music/<track_id>.wav). A no-op
## if that track is already the one playing.
func play_music(track_id: String) -> void:
	if track_id == _music_key and _music_current.playing:
		return
	var stream = _music_tracks.get(track_id, null)
	if stream == null:
		var path := MUSIC_DIR + track_id + ".wav"
		if not ResourceLoader.exists(path):
			if OS.is_debug_build():
				push_warning("AudioManager: missing music asset " + path)
			return
		stream = load(path)
		_enable_loop(stream)
		_music_tracks[track_id] = stream
	_music_key = track_id

	var incoming: AudioStreamPlayer = _music_b if _music_current == _music_a else _music_a
	var outgoing: AudioStreamPlayer = _music_current
	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()
	_music_current = incoming

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(incoming, "volume_db", _music_db(), MUSIC_FADE)
	if outgoing.playing:
		tween.tween_property(outgoing, "volume_db", SILENCE_DB, MUSIC_FADE)
		tween.chain().tween_callback(outgoing.stop)

## Forces a loaded WAV to loop end-to-end regardless of its import setting.
func _enable_loop(stream) -> void:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)

# --- Volume (authoritative values persist in SettingsManager) ---

func set_master_volume(v: float) -> void:
	SettingsManager.master_volume = clampf(v, 0.0, 1.0)
	_apply_music_volume()
	SettingsManager.save_settings()

func set_sfx_volume(v: float) -> void:
	SettingsManager.sfx_volume = clampf(v, 0.0, 1.0)
	SettingsManager.save_settings()

## A one-shot preview of the current SFX level (used when a slider drag ends, so
## dragging doesn't machine-gun clicks).
func preview_sfx_level() -> void:
	play_sfx(Ids.SFX_UI_CLICK)

func set_music_volume(v: float) -> void:
	SettingsManager.music_volume = clampf(v, 0.0, 1.0)
	_apply_music_volume()
	SettingsManager.save_settings()

func _apply_music_volume() -> void:
	if _music_current and _music_current.playing:
		_music_current.volume_db = _music_db()

func _sfx_db() -> float:
	return _to_db(SettingsManager.master_volume * SettingsManager.sfx_volume)

func _music_db() -> float:
	return _to_db(SettingsManager.master_volume * SettingsManager.music_volume)

## Linear 0..1 to decibels, with a hard floor so 0 is truly silent (not -inf).
func _to_db(linear: float) -> float:
	if linear <= 0.001:
		return SILENCE_DB
	return linear_to_db(linear)
