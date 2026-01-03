extends Node2D

# --- CONFIGURATION ---
@export var odd_row_speed: float = -50.0  # Odd rows scroll left (negative)
@export var even_row_speed: float = 50.0  # Even rows scroll right (positive)
@export var duplicate_offset: float = 1920.0  # Distance between original and duplicate
@export var transition_duration: float = 0.5  # Time to transition between states

# Background states
enum BackgroundState {
	DEFAULT,
	SELECTION,
	SWAP,
	DRAW,
	WIN,
	LOSE,
	TIE,
	PLAYER_TURN,
	OPP_TURN
}

# State colors and textures
var state_colors = {
	BackgroundState.DEFAULT: Color(0.182569, 0.31332907, 0.3653379, 1),
	BackgroundState.SELECTION: Color(0.905882, 0.580392, 0.235294, 1),  # E7943C
	BackgroundState.SWAP: Color(0.748235, 0.470588, 0.192157, 1),  # BF7831
	BackgroundState.DRAW: Color(0.690196, 0.447059, 0.203922, 1),  # B07234
	BackgroundState.WIN: Color(0.117647, 0.650980, 0.117647, 1),   # 1EA61E
	BackgroundState.LOSE: Color(0.662745, 0.309804, 0.305882, 1),  # a94f4e
	BackgroundState.TIE: Color(0.317647, 0.352941, 0.392157, 1),    # 515A64
	BackgroundState.PLAYER_TURN: Color("#402BB1"),  # Player turn
	BackgroundState.OPP_TURN: Color("#282562")      # Opponent turn
}

var state_textures = {}

func _init():
	# Initialize textures (using load instead of preload to avoid path issues)
	state_textures = {
		BackgroundState.DEFAULT: load("res://assets/icons/background_icons/logo.png"),
		BackgroundState.SELECTION: load("res://assets/icons/background_icons/selection.png"),
		BackgroundState.SWAP: load("res://assets/icons/background_icons/SWAP_.png"),
		BackgroundState.DRAW: load("res://assets/icons/background_icons/DRAW_.png"),
		BackgroundState.WIN: load("res://assets/icons/background_icons/WINNER!.png"),
		BackgroundState.LOSE: load("res://assets/icons/background_icons/LOSER!.png"),
		BackgroundState.TIE: load("res://assets/icons/background_icons/TIE.png"),
		BackgroundState.PLAYER_TURN: load("res://assets/icons/background_icons/turn change- PLAYER.png"),
		BackgroundState.OPP_TURN: load("res://assets/icons/background_icons/turn change- OPP.png")
	}

# Reference to background container
@onready var logo_bg: ColorRect = $logoBG
var scrolling_rows: Array = []
var current_state: BackgroundState = BackgroundState.DEFAULT
var input_blocked: bool = false
@export var turn_change_duration: float = 3.0  # Duration to show turn change state

func _ready() -> void:
	# Add to background group for easy access
	add_to_group("background")
	
	# CRITICAL: Set mouse filter to IGNORE so cards can receive hover events
	if logo_bg:
		logo_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create scrolling row pairs for seamless effect
	create_scrolling_rows()

func create_scrolling_rows():
	# Get original logo lines
	var original_lines = []
	for child in logo_bg.get_children():
		if child.name.begins_with("logo_line"):
			original_lines.append(child)
	
	# For each original line, create a duplicate for seamless scrolling
	for i in range(original_lines.size()):
		var original = original_lines[i]
		var copy = original.duplicate()
		copy.name = original.name + "_duplicate"
		logo_bg.add_child(copy)
		
		# Position duplicate based on scroll direction
		var row_number = i + 1
		var is_odd_row = row_number % 2 == 1
		
		if is_odd_row:  # Odd rows scroll left
			copy.position.x = original.position.x + duplicate_offset
		else:  # Even rows scroll right
			copy.position.x = original.position.x - duplicate_offset
		
		# Store both original and duplicate for processing
		scrolling_rows.append({
			"original": original,
			"duplicate": copy,
			"row_number": row_number
		})
	


# --- STATE MANAGEMENT ---
func set_background_state(new_state: BackgroundState):
	if current_state == new_state:
		return
	
	current_state = new_state
	var target_color = state_colors[new_state]
	var target_texture = state_textures[new_state]
	
	# Animate background color change
	var tween = create_tween().set_parallel(true)
	tween.tween_property(logo_bg, "color", target_color, transition_duration)
	
	# Update all logo textures
	update_all_textures(target_texture)

func update_all_textures(new_texture: Texture2D):
	# Update textures in all scrolling rows
	for row_data in scrolling_rows:
		update_textures_in_line(row_data.original, new_texture)
		update_textures_in_line(row_data.duplicate, new_texture)

func update_textures_in_line(line_node: Node, new_texture: Texture2D):
	# Update all Sprite2D nodes in the line
	for child in line_node.get_children():
		if child is Sprite2D:
			child.texture = new_texture



func _process(delta: float) -> void:
	# Move each pair of rows
	for row_data in scrolling_rows:
		var original = row_data.original
		var copy = row_data.duplicate
		var row_number = row_data.row_number
		
		# Determine speed based on row number (1-indexed)
		var is_odd_row = row_number % 2 == 1
		var speed = odd_row_speed if is_odd_row else even_row_speed
		
		# Move both original and duplicate
		original.position.x += speed * delta
		copy.position.x += speed * delta
		
		# Handle wrapping
		if speed < 0:  # Moving left
			if original.position.x <= -duplicate_offset:
				original.position.x = copy.position.x + duplicate_offset
			if copy.position.x <= -duplicate_offset:
				copy.position.x = original.position.x + duplicate_offset
		else:  # Moving right
			if original.position.x >= duplicate_offset:
				original.position.x = copy.position.x - duplicate_offset
			if copy.position.x >= duplicate_offset:
				copy.position.x = original.position.x - duplicate_offset

# --- TURN CHANGE FUNCTIONALITY ---
func show_player_turn():
	"""Show player turn change state, block input, then return to default"""
	await show_turn_change(BackgroundState.PLAYER_TURN)

func show_opponent_turn():
	"""Show opponent turn change state, block input, then return to default"""
	await show_turn_change(BackgroundState.OPP_TURN)

func show_turn_change(turn_state: BackgroundState):
	"""Generic turn change handler with input blocking"""
	
	# Play turn change sound
	var sound_manager = get_tree().get_first_node_in_group("sound_manager")
	if sound_manager and sound_manager.has_method("play_turn_change"):
		sound_manager.play_turn_change()
	
	# Block all input
	input_blocked = true
	block_all_input(true)
	
	# Set the turn change state
	set_background_state(turn_state)
	
	# Wait for the specified duration
	await get_tree().create_timer(turn_change_duration).timeout
	
	# Return to default state
	set_background_state(BackgroundState.DEFAULT)
	
	# Unblock input
	input_blocked = false
	block_all_input(false)

func block_all_input(block: bool):
	"""Block/unblock all input across the game"""
	
	# Block game manager input
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and game_manager.has_method("set_cards_playable"):
		game_manager.set_cards_playable(not block)
	
	# Block AI manager input
	var ai_manager = get_tree().get_first_node_in_group("ai_manager")
	if ai_manager and ai_manager.has_method("set_ai_cards_playable"):
		ai_manager.set_ai_cards_playable(not block)
	
	# Block hand interactions
	var player_hand = get_tree().get_first_node_in_group("hand")
	if player_hand:
		for card in player_hand.get_cards():
			if card.has_method("set_input_blocked"):
				card.set_input_blocked(block)

func is_input_blocked() -> bool:
	"""Check if input is currently blocked"""
	return input_blocked
