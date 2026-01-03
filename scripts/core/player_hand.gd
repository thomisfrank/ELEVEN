extends Node2D


const card_scene_path = "res://scenes/core/card.tscn"

var player_hand = []
var center_screen_x
@export var CARD_WIDTH = 200
@export var HAND_Y_POSITION = 890
const MAX_HAND_SIZE = 4
const DEFAULT_CARD_MOVE_SPEED = 0.1

# Wave animation settings
var wave_enabled: bool = true
var wave_time: float = 0.0
@export var wave_amplitude: float = 8.0  # How far cards bob up/down
@export var wave_frequency: float = 1.5  # Speed of the wave
@export var wave_phase_shift: float = 1.0  # Phase difference between cards

# HandHelpers is available via its `class_name HandHelpers` and provides static helpers.

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	center_screen_x = get_viewport().get_visible_rect().size.x / 2.0

	

func add_card_to_hand(card_node, speed) -> bool:
	# Guard: only add actual card instances (they join group "cards" in card.gd)
	if not card_node or not card_node.is_in_group("cards"):
		return false

	# Play sound when card is added to hand
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_card_touch"):
		sound_manager.play_card_touch()

	# If node isn't already in hand, enforce max size
	if card_node not in player_hand:
		if player_hand.size() >= MAX_HAND_SIZE:
			return false
		player_hand.insert(0, card_node)
		# Reparent card into this hand so interaction state follows
		var parent = card_node.get_parent()
		if parent and parent != self:
			parent.remove_child(card_node)
			add_child(card_node)
		elif not parent:
			add_child(card_node)
		# Mark this card as owned by this hand
		if "owner_hand" in card_node:
			card_node.owner_hand = self
		# Ensure player cards are interactive
		_enable_card_interaction(card_node, true)
		update_hand_positions(speed)
	else:
		animate_card_to_position(card_node, card_node.position_in_hand, DEFAULT_CARD_MOVE_SPEED)
	return true


func _enable_card_interaction(card_node: Node, enabled: bool) -> void:
	# Toggle Area2D and mouse pickability for the card
	if not card_node:
		return
	if card_node.has_node("Area2D"):
		var area = card_node.get_node("Area2D")
		area.monitoring = enabled
		area.monitorable = enabled
		area.input_pickable = enabled
		if area.has_node("CollisionShape2D"):
			area.get_node("CollisionShape2D").disabled = not enabled
	# Make sure frame and its children ignore mouse so Area2D gets the events
	if card_node.has_node("Frame"):
		var frame = card_node.get_node("Frame")
		if "mouse_filter" in frame:
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if frame.has_node("front") and "mouse_filter" in frame.get_node("front"):
			frame.get_node("front").mouse_filter = Control.MOUSE_FILTER_IGNORE
		if frame.has_node("back") and "mouse_filter" in frame.get_node("back"):
			frame.get_node("back").mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_hand_positions(speed):
	# Filter out any non-card nodes that may have leaked into the hand list
	var filtered_hand := []
	for c in player_hand:
		if c and c.is_in_group("cards"):
			filtered_hand.append(c)
	player_hand = filtered_hand

	# Play sound for each card moving during relayout
	var sound_manager = get_node_or_null("/root/SoundManager")
	for i in range(player_hand.size()):
		# get new card position based on index
		var new_position = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		var card = player_hand[i]
		# Defensive: ensure the object supports the expected property
		if card and card.is_in_group("cards"):
			card.position_in_hand = new_position
			animate_card_to_position(card, new_position, speed)
			# Play sound for card movement
			if sound_manager and sound_manager.has_method("play_card_touch"):
				sound_manager.play_card_touch()
			# Small delay between each card sound
			await get_tree().create_timer(0.05).timeout
		else:
			pass

func calculate_card_position(index):
	var total_width = (player_hand.size() - 1) * CARD_WIDTH
	var x_offset = center_screen_x + index * CARD_WIDTH - total_width / 2.0
	return x_offset

func animate_card_to_position(card_node, new_position, speed: float = 0.1):
	# Simple local tween to move a card to its target position.
	# This does not rely on the removed HandHelpers.
	if not card_node:
		return
	var tree := get_tree()
	var tween = tree.create_tween()
	tween.tween_property(card_node, "global_position", new_position, speed)
	# We don't need to await here; caller can continue. If awaiting is required by logic, callers should await.


# Idle/wave behavior removed — no-op placeholders retained in case other code calls them.
func start_idle_for_card(_card, _index := 0) -> void:
	return


func stop_idle_for_card(_card) -> void:
	return

func remove_card_from_hand(card_node):
	# Remove the card from the logical hand if present and update positions.
	if card_node in player_hand:
		# stop any idle loop for this card
		stop_idle_for_card(card_node)
		player_hand.erase(card_node)
		update_hand_positions(DEFAULT_CARD_MOVE_SPEED) 

func shuffle_hand():
	"""Shuffle the hand array and reposition all cards"""
	if player_hand.size() <= 1:
		return
	
	# Shuffle the array
	player_hand.shuffle()
	
	# Reposition all cards with animation
	update_hand_positions(0.3)

func discard_all() -> void:
	"""Discard all cards from the hand to the discard pile"""
	# Get discard pile reference
	var root_scene = get_tree().get_current_scene()
	var discard_pile = root_scene.get_node_or_null("DiscardPile")
	var sound_manager = get_node_or_null("/root/SoundManager")
	
	print("[DISCARD] Player discard_all called. Hand size: ", player_hand.size())
	print("[DISCARD] Discard pile: ", discard_pile)
	
	# Make a copy of the array since we'll be modifying it
	var cards_to_discard = player_hand.duplicate()
	
	# Stop idle animations and send cards to discard pile
	for card in cards_to_discard:
		if card:
			print("[DISCARD] Moving card to discard pile: ", card.name)
			print("[DISCARD] Card current parent BEFORE: ", card.get_parent().name if card.get_parent() else "null")
			stop_idle_for_card(card)
			
			# FORCE remove from current parent
			if card.get_parent():
				card.get_parent().remove_child(card)
			
			if discard_pile and discard_pile.has_method("accept_card"):
				discard_pile.accept_card(card)
				print("[DISCARD] Card parent AFTER accept_card: ", card.get_parent().name if card.get_parent() else "null")
				# Play discard sound
				if sound_manager and sound_manager.has_method("play_card_touch"):
					sound_manager.play_card_touch()
			else:
				print("[DISCARD] No discard pile or accept_card method, freeing card")
				card.queue_free()
			await get_tree().create_timer(0.05).timeout  # Small delay between cards
	
	# Clear the hand
	player_hand.clear()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not wave_enabled:
		return
	
	wave_time += delta
	
	# Apply wave motion to each card in hand
	for i in range(player_hand.size()):
		var card = player_hand[i]
		if not card or not card.is_in_group("cards"):
			continue
		
		# Skip if card is being hovered or dragged
		if "_is_currently_hovered" in card and card._is_currently_hovered:
			continue
		var card_manager = get_node_or_null("/root/CardManager")
		if card_manager and card_manager.get("card_being_dragged") == card:
			continue
		
		# Calculate wave offset for this card
		var phase = i * wave_phase_shift
		var wave_offset = sin((wave_time * wave_frequency) + phase) * wave_amplitude
		
		# Apply offset to the card's y position
		if "position_in_hand" in card:
			var target_y = card.position_in_hand.y + wave_offset
			card.global_position.y = target_y
