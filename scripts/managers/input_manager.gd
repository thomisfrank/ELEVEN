extends Node

signal left_mouse_button_clicked
signal left_mouse_button_released


const COLLISION_MASK_CARD = 1
const COLLISION_MASK_DECK = 4

var card_manager_reference
var deck_reference

func _ready() -> void:
	# Resolve references safely. Autoloads live under /root, while scene nodes live under the
	# current scene. Avoid calling `find_node` on objects that may not implement it.
	# Prefer the autoload CardManager at /root/CardManager.
	card_manager_reference = get_node_or_null("/root/CardManager")
	if not card_manager_reference:
		# fallback: try current scene (the main scene's children)
		if get_tree().current_scene and get_tree().current_scene.has_node("CardManager"):
			card_manager_reference = get_tree().current_scene.get_node("CardManager")

	# Deck lives in the main scene as a direct child named "Deck"; fetch from current_scene.
	deck_reference = null
	if get_tree().current_scene and get_tree().current_scene.has_node("Deck"):
		deck_reference = get_tree().current_scene.get_node("Deck")


func _input (event):
	# This manager delegates input actions to the CardManager singleton
	# so we don't duplicate the dragging/raycast logic or required vars.
	var root = get_tree().get_root()
	if not root.has_node("CardManager"):
		emit_signal("left_mouse_button_released")
		# If CardManager singleton isn't present, do nothing to avoid redlines
		return

	var card_manager = root.get_node("CardManager")

	# Desktop mouse press/release
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Emit a clicked signal when the left mouse button is pressed
			emit_signal("left_mouse_button_clicked")
			card_manager.last_pointer_pos = get_viewport().get_mouse_position()
			var card = card_manager.raycast_at_pointer(card_manager.last_pointer_pos)
			if card:
				card_manager.start_drag(card)
			else:
				# No card under pointer — try InputManager's raycast which detects deck/play_area
				raycast_at_pointer(card_manager.last_pointer_pos)

		else:
			emit_signal("left_mouse_button_released")
			if card_manager.card_being_dragged:
				card_manager.finish_drag()

	# Mouse movement updates pointer position for smoother dragging on desktop
	elif event is InputEventMouseMotion:
		card_manager.last_pointer_pos = event.position

	# Touch pressed/released on mobile
	elif event is InputEventScreenTouch:
		card_manager.last_pointer_pos = event.position
		if event.pressed:
			# Emit a clicked signal for touch presses as well
			emit_signal("left_mouse_button_clicked")
			var card = card_manager.raycast_at_pointer(card_manager.last_pointer_pos)
			if card:
				card_manager.start_drag(card)
			else:
				# No card under pointer — try InputManager's raycast which detects deck/play_area
				raycast_at_pointer(card_manager.last_pointer_pos)
		else:
			emit_signal("left_mouse_button_released")
			if card_manager.card_being_dragged:
				card_manager.finish_drag()

	# Touch drag updates pointer position immediately
	elif event is InputEventScreenDrag:
		card_manager.last_pointer_pos = event.position
		if card_manager.card_being_dragged:
			card_manager.card_being_dragged.position = Vector2(
				clamp(card_manager.last_pointer_pos.x, 0, card_manager.screen_size.x),
				clamp(card_manager.last_pointer_pos.y, 0, card_manager.screen_size.y)
			)

func raycast_at_pointer(position: Vector2):
	var space_state = get_viewport().get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = position
	parameters.collide_with_areas = true
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		var result_collision_mask = result[0].collider.collision_mask
		if result_collision_mask == COLLISION_MASK_CARD :
			#card clicked
			var card_found = card_manager_reference.get_card_with_highest_z_index(result)
			if card_found: # Make sure a card was actually found
				card_manager_reference.start_drag(card_found)
		elif result_collision_mask == COLLISION_MASK_DECK:
			#Deck clicked
			if deck_reference:
				deck_reference.draw_card()
			else:
				# Deck not found in scene tree; ignore to avoid runtime error
				pass
