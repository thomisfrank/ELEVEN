extends Node

# AudioStreamPlayer nodes for different types of sounds
@onready var sfx_players: Array[AudioStreamPlayer] = []
@onready var ui_player: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var ambiance_player: AudioStreamPlayer = AudioStreamPlayer.new()
const MAX_SFX_PLAYERS = 10

# Sound effect resources
var card_touch_sounds: Array[AudioStream] = []
var card_played_sound: AudioStream
var card_hover_sound: AudioStream
var turn_change_sound: AudioStream
var end_round_panel_sound: AudioStream
var close_end_round_panel_sound: AudioStream
var end_game_panel_sound: AudioStream
var point_beep_sound: AudioStream
var round_win_sound: AudioStream
var round_lost_sound: AudioStream
var round_tie_sound: AudioStream
var pass_sound: AudioStream
var typing_sound: AudioStream

# Volume controls
@export var master_volume: float = 1.0
@export var sfx_volume: float = 0.7
@export var ui_volume: float = 0.5
@export var ambiance_volume: float = 0.3

# Sound variation settings
var last_card_touch_index: int = -1

func _ready():
	add_to_group("sound_manager")
    
	# Create multiple SFX players for simultaneous sounds
	for i in range(MAX_SFX_PLAYERS):
		var player = AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % i
		sfx_players.append(player)
		add_child(player)
    
	# Add other audio players as children
	add_child(ui_player)
	add_child(ambiance_player)
    
	ui_player.name = "UIPlayer"
	ambiance_player.name = "AmbiancePlayer"
    
	load_sound_effects()
	update_volumes()

func load_sound_effects():
	# Load card touch sounds (CardTouch00-09)
	for i in range(10):
		var sound_path = ""
		for ext in [".wav", ".mp3", ".ogg"]:
			var test_path = "res://assets/sounds/sfx/CardTouch%02d%s" % [i, ext]
			if ResourceLoader.exists(test_path):
				sound_path = test_path
				break
		if sound_path != "":
			var sound = load(sound_path) as AudioStream
			if sound:
				card_touch_sounds.append(sound)

	# Load card played sound
	for ext in [".wav", ".mp3", ".ogg"]:
		var test_path = "res://assets/sounds/sfx/CardPlayed%s" % ext
		if ResourceLoader.exists(test_path):
			var loaded = load(test_path) as AudioStream
			if loaded:
				card_played_sound = loaded
				break

	# Load other sound effects
	turn_change_sound = load_sound_file("TurnChange")
	end_round_panel_sound = load_sound_file("EndRoundPanel")
	close_end_round_panel_sound = load_sound_file("CloseEndRoundPanel")
	end_game_panel_sound = load_sound_file("EndGamePanel")
	point_beep_sound = load_sound_file("PointBeep")
	round_win_sound = load_sound_file("RoundWin")
	round_lost_sound = load_sound_file("RoundLost")
	round_tie_sound = load_sound_file("RoundTie")
	pass_sound = load_sound_file("pass")
	typing_sound = load_sound_file("Typing00")

func load_sound_file(filename: String) -> AudioStream:
	for ext in [".wav", ".mp3", ".ogg"]:
		var test_path = "res://assets/sounds/sfx/" + filename + ext
		if ResourceLoader.exists(test_path):
			var sound = load(test_path) as AudioStream
			if sound:
				return sound
	return null

func update_volumes():
	for player in sfx_players:
		player.volume_db = linear_to_db(master_volume * sfx_volume)
	ui_player.volume_db = linear_to_db(master_volume * ui_volume)
	ambiance_player.volume_db = linear_to_db(master_volume * ambiance_volume)

func get_available_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	return sfx_players[0]

func play_card_hover():
	if card_touch_sounds.is_empty():
		return
	var sound_index = randi() % card_touch_sounds.size()
	if sound_index == last_card_touch_index and card_touch_sounds.size() > 1:
		sound_index = (sound_index + 1) % card_touch_sounds.size()
	last_card_touch_index = sound_index
	var player = get_available_sfx_player()
	player.stream = card_touch_sounds[sound_index]
	player.play()

func play_card_touch():
	play_card_hover()

func play_card_played():
	if card_played_sound:
		var player = get_available_sfx_player()
		player.stream = card_played_sound
		player.play()

func play_card_draw():
	play_card_touch()

func play_card_place():
	if card_played_sound:
		var player = get_available_sfx_player()
		player.stream = card_played_sound
		player.play()

func play_ui_click():
	play_card_touch()

func play_turn_change():
	if turn_change_sound:
		var player = get_available_sfx_player()
		player.stream = turn_change_sound
		player.play()

func play_end_round_panel():
	if end_round_panel_sound:
		ui_player.stream = end_round_panel_sound
		ui_player.play()

func play_close_end_round_panel():
	if close_end_round_panel_sound:
		ui_player.stream = close_end_round_panel_sound
		ui_player.play()

func play_end_game_panel():
	if end_game_panel_sound:
		ui_player.stream = end_game_panel_sound
		ui_player.play()

func play_point_beep():
	if point_beep_sound:
		ui_player.stream = point_beep_sound
		ui_player.play()

func play_round_win():
	if round_win_sound:
		var player = get_available_sfx_player()
		player.stream = round_win_sound
		player.play()

func play_round_lost():
	if round_lost_sound:
		var player = get_available_sfx_player()
		player.stream = round_lost_sound
		player.play()

func play_round_tie():
	if round_tie_sound:
		var player = get_available_sfx_player()
		player.stream = round_tie_sound
		player.play()

func play_pass():
	if pass_sound:
		var player = get_available_sfx_player()
		player.stream = pass_sound
		player.play()

func play_typing():
	if typing_sound:
		var player = get_available_sfx_player()
		player.stream = typing_sound
		player.play()

func set_master_volume(volume: float):
	master_volume = clamp(volume, 0.0, 1.0)
	update_volumes()

func set_sfx_volume(volume: float):
	sfx_volume = clamp(volume, 0.0, 1.0)
	update_volumes()

func set_ui_volume(volume: float):
	ui_volume = clamp(volume, 0.0, 1.0)
	update_volumes()

func stop_all_sounds():
	for player in sfx_players:
		player.stop()
	ui_player.stop()
	ambiance_player.stop()

func is_sound_playing() -> bool:
	for player in sfx_players:
		if player.playing:
			return true
	return ui_player.playing or ambiance_player.playing
