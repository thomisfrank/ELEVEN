extends Node

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_PLAY_AREA = 2
const DEFAULT_CARD_MOVE_SPEED = 0.1

var screen_size 
var card_being_dragged = null
var is_hovering_on_card = false
var player_hand_reference
var last_pointer_pos = Vector2()
var selection_mode_active = false  # Flag to disable dragging during selection mode

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	screen_size = get_viewport().get_visible_rect().size
	last_pointer_pos = get_viewport().get_mouse_position()
	await get_tree().create_timer(0.1).timeout
	var cards = get_tree().get_nodes_in_group("cards")
	for card in cards:
		# Register existing cards using the shared helper which avoids duplicate connects
		_register_card_node(card)
	# CardManager is a global singleton, so we must access player_hand from the current scene root
	player_hand_reference = get_tree().current_scene.get_node("player_hand")

	# Watch for cards that are instanced after CardManager's startup
	# (connect to the SceneTree node_added signal to register them as they appear)
	get_tree().connect("node_added", Callable(self, "_on_node_added"))

	# InputManager is an autoload (root-level). Resolve it from the scene root and connect safely.
	var root = get_tree().get_root()
	var input_manager = null
	if root.has_node("InputManager"):
		input_manager = root.get_node("InputManager")
	else:
		input_manager = root.find_node("InputManager", true, false)
	if input_manager:
		input_manager.connect("left_mouse_button_released", Callable(self, "_on_left_mouse_button_released"))
		# Also connect the clicked signal so it's used and handlers run when pressed
		if input_manager.has_signal("left_mouse_button_clicked"):
			input_manager.connect("left_mouse_button_clicked", Callable(self, "_on_left_mouse_button_clicked"))
		else:
			# If the InputManager for some reason doesn't provide the signal, skip
			pass
	else:
		# If InputManager isn't found, we skip connecting to avoid runtime errors.
		pass

func _on_card_hovered(card_node):
	# Play hover sound for every card hover (even during selection mode)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_card_hover"):
		sound_manager.play_card_hover()
	
	# Only do visual highlights if not in selection mode
	if selection_mode_active:
		return
	
	if !is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card_node,true)


func _on_card_hovered_off(card_node):
	if !card_being_dragged:
		#is_hovering_on_card = false
		highlight_card(card_node,false)
	# check if hovered off card and straight onto another card
	var new_card_hovered = raycast_check_for_card()
	if new_card_hovered:
		highlight_card(new_card_hovered,true)
	else:
		is_hovering_on_card = false

func highlight_card(card_node, hovered):
	if hovered:
		card_node.scale = Vector2(.6, .6)
		card_node.z_index = 2
	else:
		card_node.scale = Vector2(.5, .5)
		card_node.z_index = 1 



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if card_being_dragged:
		# Use the unified last_pointer_pos so touch and mouse both move the dragged card
		card_being_dragged.position = Vector2(
			clamp(last_pointer_pos.x, 0, screen_size.x),
			clamp(last_pointer_pos.y, 0, screen_size.y)
		)



func start_drag(card_node):
	if selection_mode_active:
		# selection mode active; ignore drag
		return
	# Prevent dragging locked cards
	if "locked" in card_node and card_node.locked:
		return
	card_being_dragged = card_node
	card_node.scale = Vector2(.65, .65)
	# Play touch sound when starting drag
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_card_touch"):
		sound_manager.play_card_touch()

func finish_drag():
	card_being_dragged.scale = Vector2(.5, .5)
	var play_area_found = raycast_check_for_play_area()
	if play_area_found and not play_area_found.card_in_slot:
		# CARD BEING DROPPED INTO PLAY AREA - For now, just snap to the play area's position
		card_being_dragged.position = play_area_found.position
		
		# Remove the card from the player's hand FIRST so the hand has space for draw effects
		if player_hand_reference and player_hand_reference.has_method("remove_card_from_hand"):
			player_hand_reference.remove_card_from_hand(card_being_dragged)
		
		# Trigger the play area's effect AFTER removing from hand
		if play_area_found.has_method("_on_area_body_entered"):
			play_area_found._on_area_body_entered(card_being_dragged)
		
		card_being_dragged.get_node("Area2D/CollisionShape2D").disabled = true
		play_area_found.card_in_slot = true
	else:
		# If the card's collision shape has been disabled it was just placed
		# into the play area -- don't add it back to the hand.
		var shape = null
		if card_being_dragged and card_being_dragged.has_node("Area2D/CollisionShape2D"):
			shape = card_being_dragged.get_node("Area2D/CollisionShape2D")
		if shape and shape.disabled:
			# Card collision disabled -> do not add back to hand
			pass
		else:
			# Play sound when card returns to hand
			var sound_manager = get_node_or_null("/root/SoundManager")
			if sound_manager and sound_manager.has_method("play_card_touch"):
				sound_manager.play_card_touch()
			
			if player_hand_reference and player_hand_reference.has_method("add_card_to_hand"):
				var added_back = player_hand_reference.add_card_to_hand(card_being_dragged, DEFAULT_CARD_MOVE_SPEED)
				if not added_back:
					pass
			else:
				# Fallback if player_hand_reference isn't available
				pass
	card_being_dragged = null



func _on_left_mouse_button_released():
	if card_being_dragged:
		finish_drag()


func _on_left_mouse_button_clicked():
	# Simple handler to demonstrate the clicked signal is received
	# (no-op to avoid prints in production)
	pass


func _on_node_added(node):
	# When new nodes are added to the scene tree, register card nodes so
	# hover signals get connected even if the card was instanced later.
	if not node:
		return
	# Some nodes are instanced as complex scenes; check the node and its children
	# If the node itself is a card in the 'cards' group, register it.
	# If a node exposes the hovered signal, register it immediately. This
	# catches cards that add themselves to the 'cards' group in their own _ready
	# (node_added is emitted before a node's _ready runs), as well as nodes
	# that simply declare the signal.
	if node.has_signal("hovered"):
		_register_card_node(node)
	# Also inspect children to catch nested card instances
	for child in node.get_children():
		if child and child.has_signal("hovered"):
			_register_card_node(child)


func _register_card_node(card):
	if not card:
		return
	# Avoid duplicate connects
	if card.has_signal("hovered") and not card.is_connected("hovered", Callable(self, "_on_card_hovered")):
		card.connect("hovered", Callable(self, "_on_card_hovered"))
	if card.has_signal("hovered_off") and not card.is_connected("hovered_off", Callable(self, "_on_card_hovered_off")):
		card.connect("hovered_off", Callable(self, "_on_card_hovered_off"))

func raycast_check_for_play_area():
	return raycast_check_for_play_area_at(get_viewport().get_mouse_position())


func raycast_check_for_play_area_at(position: Vector2):
	var space_state = get_viewport().get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = position
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_PLAY_AREA
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return result[0].collider.get_parent().get_parent()
	return null

func raycast_check_for_card():
	return raycast_check_for_card_at(get_viewport().get_mouse_position())


func raycast_check_for_card_at(position: Vector2):
	var space_state = get_viewport().get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = position
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		#return result[0].collider.get_parent()
		return get_card_with_highest_z_index(result)

	return null


func raycast_at_pointer(position: Vector2):
	# Compatibility wrapper used by InputManager
	# Delegates to the existing raycast_check_for_card_at implementation
	return raycast_check_for_card_at(position)


func get_card_with_highest_z_index(cards):
	#Assume the first card in cards array is the highest z index
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index

	#Loop through the rest of the cards checking for a higher z index
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card
