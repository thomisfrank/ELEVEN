extends Node

var selection_data_global = null  # Store selection data for _input handling

# Helpers for coordinating background state during selection mode
func _set_background_selection():
	var bg = get_tree().get_first_node_in_group("background")
	if bg and bg.has_method("set_background_state") and "BackgroundState" in bg:
		bg.set_background_state(bg.BackgroundState.SELECTION)

func _set_background_draw():
	var bg = get_tree().get_first_node_in_group("background")
	if bg and bg.has_method("set_background_state") and "BackgroundState" in bg:
		bg.set_background_state(bg.BackgroundState.DRAW)

func _set_background_default():
	var bg = get_tree().get_first_node_in_group("background")
	if bg and bg.has_method("set_background_state") and "BackgroundState" in bg:
		bg.set_background_state(bg.BackgroundState.DEFAULT)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


# Handle input during selection mode
func _input(event: InputEvent) -> void:
	if not selection_data_global:
		return
	
	# Don't handle input if showcase is visible (let buttons work)
	if selection_data_global.has("showcase"):
		var showcase = selection_data_global.get("showcase")
		if showcase and showcase.visible:
			return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Consume the event to prevent CardManager from handling it
		get_viewport().set_input_as_handled()
		
		# Check which card was clicked
		if "selection_cards" in selection_data_global:
			var mouse_pos = get_viewport().get_mouse_position()
			for card_data in selection_data_global["selection_cards"]:
				var card = card_data["card"]
				var area = card_data["area"]
				# Check if mouse is over this card's area
				var collision_shape = area.get_node_or_null("CollisionShape2D")
				if collision_shape:
					var shape = collision_shape.shape
					var _transform = area.global_transform * collision_shape.transform
					if shape and shape.has_method("collide") or shape is RectangleShape2D:
						# Simple bounds check for rectangle
						var card_global_pos = card.global_position
						var half_size = Vector2(250, 350)  # Approximate card size
						if mouse_pos.x >= card_global_pos.x - half_size.x and \
						   mouse_pos.x <= card_global_pos.x + half_size.x and \
						   mouse_pos.y >= card_global_pos.y - half_size.y and \
						   mouse_pos.y <= card_global_pos.y + half_size.y:
							pass
						# Store selected card in selection_data
						selection_data_global["selected_card"] = card
						_handle_card_selection(card, selection_data_global["showcase"])
						return


# Simple draw effect - draws a card from deck to target hand
func draw_effect(deck_node: Node, target_hand: Node = null, anim_duration: float = 0.15) -> void:
	if deck_node == null:
		return

	if target_hand == null:
		return

	# Determine if this is player or opponent hand
	var is_player_hand = target_hand.name == "player_hand"
	var face_up = is_player_hand  # Player cards face up, opponent cards face down
	var interactive = is_player_hand  # Player cards interactive, opponent not
	

	# Draw the card (deck.draw_card returns the card node or null)
	var card = null
	if deck_node.has_method("draw_card"):
		card = deck_node.draw_card(target_hand, face_up, interactive)
	
	if card == null:
		return

	# Wait for the draw animation to finish
	await get_tree().create_timer(anim_duration).timeout
	
	# Lock the newly drawn card
	if card:
		var card_colors = _get_card_colors(card)
		card.set_locked(true, card_colors)


# Enter selection mode to let a hand choose a card from the opposite hand
func enter_selection_mode(target_hand: Node, swap_card: Node, _discard_pile: Node, root_scene: Node) -> void:

	# Update background to selection state
	_set_background_selection()
	
	# Disable CardManager dragging during selection mode
	var card_manager = get_node_or_null("/root/CardManager")
	if card_manager:
		card_manager.selection_mode_active = true
	
	# Enable hovering for cards in the target hand
	var hand_array = target_hand.opponent_hand if target_hand.name == "opp_hand" else target_hand.player_hand
	
	var showcase = root_scene.get_node_or_null("Showcase")
	if not showcase:
		return
	
	# Determine source hand (who played the swap card) - it's the opposite of target_hand
	var player_hand = root_scene.get_node_or_null("player_hand")
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	var source_hand = opp_hand if target_hand == player_hand else player_hand
	
	# Store selection context for callbacks
	var selection_data = {
		"target_hand": target_hand,  # Hand we're selecting from
		"source_hand": source_hand,  # Hand that played the swap card
		"swap_card": swap_card,
		"hand_array": hand_array,
		"root_scene": root_scene,
		"showcase": showcase,
		"selected_card": null  # Will be set when user clicks a card
	}
	
	# Store globally for _input handling
	selection_data_global = selection_data
	
	# Connect showcase buttons
	if not showcase.is_connected("control_button_pressed", _on_showcase_control_pressed):
		showcase.control_button_pressed.connect(_on_showcase_control_pressed)
	if not showcase.is_connected("cancel_button_pressed", _on_showcase_cancel_pressed):
		showcase.cancel_button_pressed.connect(_on_showcase_cancel_pressed)
	
	# Connect hover and click events for each card in the hand
	var _connected_count = 0
	for card in hand_array:
		if not card:
			continue

		# Raise z-index to ensure card is on top during selection
		card.z_index = 200

		# Ensure Control nodes ignore input so Area2D gets events
		if card.has_node("Frame"):
			var frame = card.get_node("Frame")
			if "mouse_filter" in frame and frame.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if frame.has_node("back"):
				var back = frame.get_node("back")
				if "mouse_filter" in back and back.mouse_filter != Control.MOUSE_FILTER_IGNORE:
					back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if frame.has_node("front"):
				var front = frame.get_node("front")
				if "mouse_filter" in front and front.mouse_filter != Control.MOUSE_FILTER_IGNORE:
					front.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Connect hover signals to show/hide Selection node
		if card.has_signal("hovered"):
			if not card.is_connected("hovered", Callable(self, "_on_selection_card_hovered")):
				card.connect("hovered", Callable(self, "_on_selection_card_hovered"))
		if card.has_signal("hovered_off"):
			if not card.is_connected("hovered_off", Callable(self, "_on_selection_card_hovered_off")):
				card.connect("hovered_off", Callable(self, "_on_selection_card_hovered_off"))

		# Ensure Area2D emits mouse signals and is pickable
		if card.has_node("Area2D"):
			var area = card.get_node("Area2D")
			if not area.is_connected("mouse_entered", Callable(card, "_on_area_2d_mouse_entered")):
				area.connect("mouse_entered", Callable(card, "_on_area_2d_mouse_entered"))
			if not area.is_connected("mouse_exited", Callable(card, "_on_area_2d_mouse_exited")):
				area.connect("mouse_exited", Callable(card, "_on_area_2d_mouse_exited"))

			if area.has_node("CollisionShape2D"):
				var collision_shape = area.get_node("CollisionShape2D")
				collision_shape.disabled = false
			area.monitoring = true
			area.monitorable = true
			area.input_pickable = true

			# Connect gui_input for cards
			if card.has_signal("gui_input"):
				if not card.is_connected("gui_input", Callable(self, "_on_selection_card_gui_input")):
					card.connect("gui_input", Callable(self, "_on_selection_card_gui_input").bind(card, showcase, selection_data))
			else:
				# Store card reference for manual click detection
				if not "selection_cards" in selection_data:
					selection_data["selection_cards"] = []
				selection_data["selection_cards"].append({"card": card, "area": area})

		_connected_count += 1
	
	# If opponent played Swap, trigger AI selection automatically
	if source_hand == opp_hand:
		var ai_manager = get_node_or_null("/root/OppAiMananager")
		if ai_manager and ai_manager.has_method("ai_select_card_from_player_hand"):
			ai_manager.ai_select_card_from_player_hand(true)  # true = auto-confirm for Swap


# Enter selection mode for PeekHand - similar to Swap but tracks the effect type
func enter_selection_mode_peek_hand(target_hand: Node, peek_card: Node, discard_pile: Node, root_scene: Node) -> void:

	# Update background to selection state
	_set_background_selection()
	
	# Disable CardManager dragging during selection mode
	var card_manager = get_node_or_null("/root/CardManager")
	if card_manager:
		card_manager.selection_mode_active = true
	
	# Enable hovering for cards in the target hand
	var hand_array = target_hand.opponent_hand if target_hand.name == "opp_hand" else target_hand.player_hand
	
	var showcase = root_scene.get_node_or_null("Showcase")
	if not showcase:
		return
	
	# Determine source hand (who played the peek card) - it's the opposite of target_hand
	var player_hand = root_scene.get_node_or_null("player_hand")
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	var source_hand = opp_hand if target_hand == player_hand else player_hand
	
	# Store selection context for callbacks
	var selection_data = {
		"effect_type": "PeekHand",  # Track that this is PeekHand, not Swap
		"target_hand": target_hand,  # Hand we're selecting from
		"source_hand": source_hand,  # Hand that played the peek card
		"peek_card": peek_card,
		"discard_pile": discard_pile,
		"hand_array": hand_array,
		"root_scene": root_scene,
		"showcase": showcase,
		"selected_card": null  # Will be set when user clicks a card
	}
	
	# Store globally for _input handling
	selection_data_global = selection_data
	
	# Connect showcase buttons
	if not showcase.is_connected("control_button_pressed", _on_showcase_control_pressed):
		showcase.control_button_pressed.connect(_on_showcase_control_pressed)
	if not showcase.is_connected("cancel_button_pressed", _on_showcase_cancel_pressed):
		showcase.cancel_button_pressed.connect(_on_showcase_cancel_pressed)
	
	# Connect hover and click events for each card in the hand
	var _connected_count = 0
	for card in hand_array:
		if not card:
			continue

		# Raise z-index to ensure card is on top during selection
		card.z_index = 200

		# Ensure Control nodes ignore input so Area2D gets events
		if card.has_node("Frame"):
			var frame = card.get_node("Frame")
			if "mouse_filter" in frame and frame.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if frame.has_node("back"):
				var back = frame.get_node("back")
				if "mouse_filter" in back and back.mouse_filter != Control.MOUSE_FILTER_IGNORE:
					back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if frame.has_node("front"):
				var front = frame.get_node("front")
				if "mouse_filter" in front and front.mouse_filter != Control.MOUSE_FILTER_IGNORE:
					front.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Connect hover signals to show/hide Selection node
		if card.has_signal("hovered"):
			if not card.is_connected("hovered", Callable(self, "_on_selection_card_hovered")):
				card.connect("hovered", Callable(self, "_on_selection_card_hovered"))
		if card.has_signal("hovered_off"):
			if not card.is_connected("hovered_off", Callable(self, "_on_selection_card_hovered_off")):
				card.connect("hovered_off", Callable(self, "_on_selection_card_hovered_off"))

		# Ensure Area2D emits mouse signals and is pickable
		if card.has_node("Area2D"):
			var area = card.get_node("Area2D")
			if not area.is_connected("mouse_entered", Callable(card, "_on_area_2d_mouse_entered")):
				area.connect("mouse_entered", Callable(card, "_on_area_2d_mouse_entered"))
			if not area.is_connected("mouse_exited", Callable(card, "_on_area_2d_mouse_exited")):
				area.connect("mouse_exited", Callable(card, "_on_area_2d_mouse_exited"))

			if area.has_node("CollisionShape2D"):
				var collision_shape = area.get_node("CollisionShape2D")
				collision_shape.disabled = false
			area.monitoring = true
			area.monitorable = true
			area.input_pickable = true

			# Connect gui_input for cards
			if card.has_signal("gui_input"):
				if not card.is_connected("gui_input", Callable(self, "_on_selection_card_gui_input")):
					card.connect("gui_input", Callable(self, "_on_selection_card_gui_input").bind(card, showcase, selection_data))
			else:
				# Store card reference for manual click detection
				if not "selection_cards" in selection_data:
					selection_data["selection_cards"] = []
				selection_data["selection_cards"].append({"card": card, "area": area})

		_connected_count += 1
	
	# If opponent played PeekHand, trigger AI selection and decision automatically
	if source_hand == opp_hand:
		var ai_manager = get_node_or_null("/root/OppAiMananager")
		if ai_manager and ai_manager.has_method("ai_select_card_from_player_hand"):
			# First select a card (don't auto-confirm)
			await ai_manager.ai_select_card_from_player_hand(false)
			# Then make the swap/cancel decision
			if ai_manager.has_method("ai_peek_hand_action"):
				await ai_manager.ai_peek_hand_action()
		# Watchdog: if AI fails to resolve, auto-cancel after a short delay.
		_ai_peek_hand_watchdog()


func _ai_peek_hand_watchdog() -> void:
	await get_tree().create_timer(3.0).timeout
	if not selection_data_global:
		return
	if selection_data_global.get("effect_type", "") != "PeekHand":
		return
	var root_scene = get_tree().get_current_scene()
	var opp_hand = root_scene.get_node_or_null("opp_hand") if root_scene else null
	if selection_data_global.get("source_hand") == opp_hand:
		_on_showcase_cancel_pressed()


# Dispatcher to run the effect associated with a suit when a card is played
func run_suit(suit: String, _card: Node) -> void:
	if suit == null or suit == "":
		return
	
	# Expect the main scene to expose Deck, player_hand and DiscardPile nodes.
	var root_scene = get_tree().get_current_scene()
	if root_scene == null:
		return

	var deck = root_scene.get_node_or_null("Deck")
	var player_hand = root_scene.get_node_or_null("player_hand")
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	var discard_pile = root_scene.get_node_or_null("DiscardPile")
	
	# Determine which hand played the card by checking owner_hand property
	var target_hand = player_hand  # Default to player
	if _card and "owner_hand" in _card and _card.get("owner_hand") != null:
		target_hand = _card.get("owner_hand")
	else:
		pass
	
	# CONSUME AN ACTION IMMEDIATELY WHEN CARD EFFECT STARTS
	# This prevents the opponent from playing multiple cards before the action is used up
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("perform_action"):
		gm.perform_action()
	
	match suit:
		"Draw":
			if deck and player_hand and opp_hand and discard_pile:
				# Play card placement sound
				var sound_manager = get_node_or_null("/root/SoundManager")
				if sound_manager and sound_manager.has_method("play_card_played"):
					sound_manager.play_card_played()
				
				# Wait for placement sound to finish
				await get_tree().create_timer(0.4).timeout
				
				# Draw a card from deck to the hand that played the card
				await draw_effect(deck, target_hand)
				
				# Wait a moment after drawing before discarding
				await get_tree().create_timer(0.3).timeout
				
				# Discard the played Draw card (with sound)
				if _card and is_instance_valid(_card):
					if discard_pile.has_method("accept_card"):
						if sound_manager and sound_manager.has_method("play_card_touch"):
							sound_manager.play_card_touch()
						discard_pile.accept_card(_card)
						# Clear the play area so another card can be played
						var play_area = root_scene.get_node_or_null("PlayArea")
						if play_area:
							play_area.card_in_slot = false
						
							# Shuffle only the hand that drew the new card
							await get_tree().create_timer(0.2).timeout
							if target_hand.has_method("shuffle_hand"):
								target_hand.shuffle_hand()
					else:
						pass
				
				# Effect complete - check if turn should end
				if gm and gm.has_method("check_and_end_turn_if_needed"):
					gm.check_and_end_turn_if_needed()
			else:
				return
		"Swap":
			if player_hand and opp_hand and discard_pile:
				# Play card placement sound
				var sound_manager = get_node_or_null("/root/SoundManager")
				if sound_manager and sound_manager.has_method("play_card_played"):
					sound_manager.play_card_played()
				
				# Wait for placement sound to finish
				await get_tree().create_timer(0.4).timeout
				
				# Determine which hand is the opposite of the one that played
				var opposite_hand = opp_hand if target_hand == player_hand else player_hand
				
				# Enter selection mode on the opposite hand
				enter_selection_mode(opposite_hand, _card, discard_pile, root_scene)
			else:
				return
		"PeekDeck":
			# Preview the top deck card and allow player to draw or cancel
			if deck and player_hand and opp_hand and discard_pile:
				# Change background state for draw action
				_set_background_draw()
				
				# Play card placement sound
				var sound_manager3 = get_node_or_null("/root/SoundManager")
				if sound_manager3 and sound_manager3.has_method("play_card_played"):
					sound_manager3.play_card_played()

				# Wait for placement sound to finish
				await get_tree().create_timer(0.4).timeout

				# Prepare showcase
				var showcase2 = root_scene.get_node_or_null("Showcase")
				if not showcase2:
					return

				# Display the top deck card in the showcase reference rect
				if deck.player_deck.size() > 0:
					var top_card = deck.player_deck[0]
					if top_card and top_card.has_node("Frame") and showcase2.has_node("BG/ReferenceRect"):
						# Clear any existing display
						var ref_rect2 = showcase2.get_node("BG/ReferenceRect")
						for child in ref_rect2.get_children():
							if child.name == "CardDisplay":
								child.queue_free()
						# Duplicate the full frame
						var frame_dup = top_card.get_node("Frame").duplicate()
						frame_dup.name = "CardDisplay"
						frame_dup.visible = true
						# Ensure the preview draws above everything
						if frame_dup is CanvasItem:
							frame_dup.z_as_relative = false
							frame_dup.z_index = 4096
						
						# Show face-up for player, face-down for opponent
						var is_player = target_hand == player_hand
						if frame_dup.has_node("front"):
							frame_dup.get_node("front").visible = is_player
						if frame_dup.has_node("back"):
							frame_dup.get_node("back").visible = not is_player
						
						ref_rect2.add_child(frame_dup)
						frame_dup.position = Vector2.ZERO
						frame_dup.scale = Vector2(1.0, 1.0)

				# Configure and show showcase for PeekDeck
				if showcase2.has_method("show_for_effect"):
					showcase2.show_for_effect("PeekDeck")
				else:
					showcase2.visible = true
				
				var control_btn = showcase2.get_node_or_null("BG/buttons/ControlButton")
				var cancel_btn = showcase2.get_node_or_null("BG/buttons/CancelButton")
				if control_btn:
					control_btn.disabled = false
				if cancel_btn:
					cancel_btn.disabled = false
				# If opponent is acting, disable player input on showcase buttons.
				if target_hand == opp_hand:
					if control_btn:
						control_btn.disabled = true
					if cancel_btn:
						cancel_btn.disabled = true

				# Store context and connect buttons
				var selection_data = {
					"effect_type": "PeekDeck",
					"peek_card": _card,
					"target_hand": target_hand,
					"deck": deck,
					"discard_pile": discard_pile,
					"root_scene": root_scene,
					"showcase": showcase2
				}
				selection_data_global = selection_data

				if not showcase2.is_connected("control_button_pressed", _on_showcase_control_pressed):
					showcase2.control_button_pressed.connect(_on_showcase_control_pressed)
				if not showcase2.is_connected("cancel_button_pressed", _on_showcase_cancel_pressed):
					showcase2.cancel_button_pressed.connect(_on_showcase_cancel_pressed)
				
				# If opponent played PeekDeck, trigger AI decision automatically
				if target_hand == opp_hand:
					var ai_manager = get_node_or_null("/root/OppAiMananager")
					if ai_manager and ai_manager.has_method("ai_peek_deck_action"):
						await ai_manager.ai_peek_deck_action()
			else:
				return
		"PeekHand":
			# Peek at opponent's hand and allow player to swap or cancel
			if player_hand and opp_hand and discard_pile:
				# Play card placement sound
				var sound_manager_ph = get_node_or_null("/root/SoundManager")
				if sound_manager_ph and sound_manager_ph.has_method("play_card_played"):
					sound_manager_ph.play_card_played()
				
				# Wait for placement sound to finish
				await get_tree().create_timer(0.4).timeout
				
				# Determine which hand is the opposite of the one that played
				var opposite_hand = opp_hand if target_hand == player_hand else player_hand
				
				# Enter selection mode on the opposite hand for PeekHand (same as Swap visually)
				enter_selection_mode_peek_hand(opposite_hand, _card, discard_pile, root_scene)
			else:
				return
		_:
			return


func _handle_card_selection(card: Node, showcase: Node) -> void:
	if showcase:
		# Set high z-index to ensure it's on top
		showcase.z_index = 1000
		
		# Configure showcase based on effect type
		if showcase.has_method("show_for_effect"):
			# Check if this is PeekHand or Swap based on selection_data_global
			var effect_type = selection_data_global.get("effect_type", "Swap") if selection_data_global else "Swap"
			showcase.show_for_effect(effect_type)
			# Block player input on opponent showcases; AI will trigger the action.
			var control_btn = showcase.get_node_or_null("BG/buttons/ControlButton")
			var cancel_btn = showcase.get_node_or_null("BG/buttons/CancelButton")
			if control_btn:
				control_btn.disabled = false
			if cancel_btn:
				cancel_btn.disabled = false
			if selection_data_global and selection_data_global.get("source_hand") == get_tree().get_current_scene().get_node_or_null("opp_hand"):
				if control_btn:
					control_btn.disabled = true
				if cancel_btn:
					cancel_btn.disabled = true
		else:
			showcase.visible = true
		
		
		# Clone the entire card's Frame (including the white border) into the showcase
		if card.has_node("Frame") and showcase.has_node("BG/ReferenceRect"):
			var card_frame = card.get_node("Frame")
			var reference_rect = showcase.get_node("BG/ReferenceRect")
			
			
			# Remove any existing card display
			for child in reference_rect.get_children():
				if child.name == "CardDisplay":
					child.queue_free()
			
			# Duplicate the entire frame
			var card_display = card_frame.duplicate()
			card_display.name = "CardDisplay"
			card_display.visible = true
			
			# Make sure front is visible and back is hidden
			if card_display.has_node("front"):
				card_display.get_node("front").visible = true
			if card_display.has_node("back"):
				card_display.get_node("back").visible = false
			
			reference_rect.add_child(card_display)
			
			
			# Position it at the origin of ReferenceRect (which is 500x700)
			card_display.position = Vector2.ZERO
			card_display.scale = Vector2(1.0, 1.0)  # Reset scale to normal
			
		else:
			pass
	
	# DON'T clear selection_data_global or re-enable dragging yet
	# Wait for user to click OKAY or CANCEL button


# Showcase button handlers
func _on_showcase_control_pressed(effect_type: String) -> void:
	
	if effect_type == "Swap" and selection_data_global:
		# Perform the swap
		var selected_card = selection_data_global.get("selected_card")
		var swap_card = selection_data_global.get("swap_card")
		var target_hand = selection_data_global.get("target_hand")  # Hand we selected from
		var source_hand = selection_data_global.get("source_hand")  # Hand that played the swap
		
		
		if selected_card and swap_card and target_hand and source_hand:
			
			# Play swap sound for first card
			var sound_manager = get_node_or_null("/root/SoundManager")
			if sound_manager and sound_manager.has_method("play_card_touch"):
				sound_manager.play_card_touch()
			
			# Move selected card from target_hand to source_hand and lock it
			target_hand.remove_card_from_hand(selected_card)
			source_hand.add_card_to_hand(selected_card, 0.3)
			# Flip card based on destination hand
			if source_hand.name == "player_hand":
				selected_card.flip_to_front(0.3)
			else:
				selected_card.flip_to_back(0.3)
			# Lock the incoming card
			var card_colors = _get_card_colors(selected_card)
			selected_card.set_locked(true, card_colors)
			
			# Play sound for second card swap
			await get_tree().create_timer(0.15).timeout
			if sound_manager and sound_manager.has_method("play_card_touch"):
				sound_manager.play_card_touch()
			
			# Move swap card to target_hand (unlocked - opponent can play it)
			target_hand.add_card_to_hand(swap_card, 0.3)
			# Flip card based on destination hand
			if target_hand.name == "player_hand":
				swap_card.flip_to_front(0.3)
			else:
				swap_card.flip_to_back(0.3)
			
			# Cleanup selection mode on all cards
			_cleanup_selection_mode()
			
			# Hide showcase
			var showcase = selection_data_global.get("showcase")
			if showcase and showcase.has_method("hide_showcase"):
				showcase.hide_showcase()
			
			# Clear the play area
			var root_scene = get_tree().get_current_scene()
			if root_scene:
				var play_area = root_scene.get_node_or_null("PlayArea")
				if play_area and play_area.has_method("clear_play_area"):
					play_area.clear_play_area()
			
			# Shuffle both hands after swap completes
			await get_tree().create_timer(0.2).timeout
			var player_hand = root_scene.get_node_or_null("player_hand")
			var opp_hand = root_scene.get_node_or_null("opp_hand")
			if player_hand and player_hand.has_method("shuffle_hand"):
				player_hand.shuffle_hand()
			if opp_hand and opp_hand.has_method("shuffle_hand"):
				opp_hand.shuffle_hand()
			
			# Re-enable CardManager dragging and clear selection mode
			var card_manager = get_node_or_null("/root/CardManager")
			if card_manager:
				card_manager.selection_mode_active = false
			
			selection_data_global = null
			# Return background to default after selection completes
			_set_background_default()
			
			# Effect complete - check if turn should end
			var gm_swap = get_node_or_null("/root/GameManager")
			if gm_swap and gm_swap.has_method("check_and_end_turn_if_needed"):
				gm_swap.check_and_end_turn_if_needed()
	
	elif effect_type == "PeekDeck" and selection_data_global:
		# Handle PeekDeck draw action
		var deck_node = selection_data_global.get("deck")
		var target_hand2 = selection_data_global.get("target_hand")
		var played_peek_card = selection_data_global.get("peek_card")
		var discard_pile2 = selection_data_global.get("discard_pile")
		var root_scene2 = selection_data_global.get("root_scene")
		var showcase3 = selection_data_global.get("showcase")
		
		if deck_node and target_hand2 and played_peek_card and discard_pile2 and root_scene2:
			# Draw a card for the acting hand
			await draw_effect(deck_node, target_hand2)

			# Short delay then discard the played PeekDeck card
			await get_tree().create_timer(0.3).timeout
			var sound_manager4 = get_node_or_null("/root/SoundManager")
			if sound_manager4 and sound_manager4.has_method("play_card_touch"):
				sound_manager4.play_card_touch()
			if is_instance_valid(played_peek_card) and discard_pile2.has_method("accept_card"):
				# Remove from any parent and reset to root scale before discarding
				if played_peek_card.get_parent():
					played_peek_card.get_parent().remove_child(played_peek_card)
				played_peek_card.scale = Vector2(0.5, 0.5)
				discard_pile2.accept_card(played_peek_card)

			# Clear the play area slot
			var play_area2 = root_scene2.get_node_or_null("PlayArea")
			if play_area2 and play_area2.has_method("clear_play_area"):
				play_area2.clear_play_area()

			# Shuffle only the acting hand
			await get_tree().create_timer(0.2).timeout
			if target_hand2.has_method("shuffle_hand"):
				target_hand2.shuffle_hand()

			# Hide showcase and cleanup
			if showcase3 and showcase3.has_method("hide_showcase"):
				showcase3.hide_showcase()
			selection_data_global = null

			# Reset background state back to default
			_set_background_default()

			# Effect complete - check if turn should end
			var gm_pd = get_node_or_null("/root/GameManager")
			if gm_pd and gm_pd.has_method("check_and_end_turn_if_needed"):
				gm_pd.check_and_end_turn_if_needed()

			# Consume one action
		var _gm3 = get_node_or_null("/root/GameManager")
	
	elif effect_type == "PeekHand" and selection_data_global:
		# Handle PeekHand swap action
		var selected_card = selection_data_global.get("selected_card")
		var peek_card = selection_data_global.get("peek_card")
		var target_hand = selection_data_global.get("target_hand")  # Hand we selected from
		var source_hand = selection_data_global.get("source_hand")  # Hand that played the peek
		var discard_pile_ph = selection_data_global.get("discard_pile")
		var root_scene_ph = selection_data_global.get("root_scene")
		
		if selected_card and peek_card and target_hand and source_hand and discard_pile_ph and root_scene_ph:
			
			# Play swap sound for first card
			var sound_manager_ph = get_node_or_null("/root/SoundManager")
			if sound_manager_ph and sound_manager_ph.has_method("play_card_touch"):
				sound_manager_ph.play_card_touch()
			
			# Move selected card from target_hand to source_hand and lock it
			target_hand.remove_card_from_hand(selected_card)
			source_hand.add_card_to_hand(selected_card, 0.3)
			# Flip card based on destination hand
			if source_hand.name == "player_hand":
				selected_card.flip_to_front(0.3)
			else:
				selected_card.flip_to_back(0.3)
			# Lock the incoming card
			var card_colors_ph = _get_card_colors(selected_card)
			selected_card.set_locked(true, card_colors_ph)
			
			# Short delay then give the PeekHand card to target_hand
			await get_tree().create_timer(0.3).timeout
			var sound_manager_ph2 = get_node_or_null("/root/SoundManager")
			if sound_manager_ph2 and sound_manager_ph2.has_method("play_card_touch"):
				sound_manager_ph2.play_card_touch()
			if is_instance_valid(peek_card):
				# Remove from any parent
				if peek_card.get_parent():
					peek_card.get_parent().remove_child(peek_card)
				# Add to target_hand
				target_hand.add_card_to_hand(peek_card, 0.3)
				# Flip card based on destination hand
				if target_hand.name == "player_hand":
					peek_card.flip_to_front(0.3)
				else:
					peek_card.flip_to_back(0.3)
			
			# Cleanup selection mode on all cards
			_cleanup_selection_mode()
			
			# Hide showcase
			var showcase_ph = selection_data_global.get("showcase")
			if showcase_ph and showcase_ph.has_method("hide_showcase"):
				showcase_ph.hide_showcase()
			
			# Clear the play area
			var play_area_ph = root_scene_ph.get_node_or_null("PlayArea")
			if play_area_ph and play_area_ph.has_method("clear_play_area"):
				play_area_ph.clear_play_area()
			
			# Shuffle both hands after swap completes
			await get_tree().create_timer(0.2).timeout
			var player_hand_ph = root_scene_ph.get_node_or_null("player_hand")
			var opp_hand_ph = root_scene_ph.get_node_or_null("opp_hand")
			if player_hand_ph and player_hand_ph.has_method("shuffle_hand"):
				player_hand_ph.shuffle_hand()
			if opp_hand_ph and opp_hand_ph.has_method("shuffle_hand"):
				opp_hand_ph.shuffle_hand()
			
			# Re-enable CardManager dragging and clear selection mode
			var card_manager_ph = get_node_or_null("/root/CardManager")
			if card_manager_ph:
				card_manager_ph.selection_mode_active = false
			
			selection_data_global = null
			# Return background to default after selection completes
			_set_background_default()
			
			# Effect complete - check if turn should end
			var gm_ph = get_node_or_null("/root/GameManager")
			if gm_ph and gm_ph.has_method("check_and_end_turn_if_needed"):
				gm_ph.check_and_end_turn_if_needed()
		else:
			# Missing data - cleanup and hide showcase
			_cleanup_selection_mode()
			var showcase_ph = selection_data_global.get("showcase") if selection_data_global else null
			if showcase_ph and showcase_ph.has_method("hide_showcase"):
				showcase_ph.hide_showcase()
			var card_manager_ph = get_node_or_null("/root/CardManager")
			if card_manager_ph:
				card_manager_ph.selection_mode_active = false
			selection_data_global = null
			_set_background_default()

	if selection_data_global and selection_data_global.get("effect_type", "") == "Swap":
		# Existing cleanup for Swap selection mode
		_cleanup_selection_mode()
		_set_background_default()
		var showcase_a = selection_data_global.get("showcase")
		if showcase_a and showcase_a.has_method("hide_showcase"):
			showcase_a.hide_showcase()
		var card_manager_a = get_node_or_null("/root/CardManager")
		if card_manager_a:
			card_manager_a.selection_mode_active = false
		selection_data_global = null
		
		# Effect complete - check if turn should end
		var gm_cancel_swap = get_node_or_null("/root/GameManager")
		if gm_cancel_swap and gm_cancel_swap.has_method("check_and_end_turn_if_needed"):
			gm_cancel_swap.check_and_end_turn_if_needed()
		return

	# Handle PeekDeck cancel: return played card to hand, lock it, relayout
	if selection_data_global and selection_data_global.get("effect_type", "") == "PeekDeck":
		var played_peek_card2 = selection_data_global.get("peek_card")
		var target_hand3 = selection_data_global.get("target_hand")
		var root_scene3 = selection_data_global.get("root_scene")
		var showcase_b = selection_data_global.get("showcase")

		# Hide showcase
		if showcase_b and showcase_b.has_method("hide_showcase"):
			showcase_b.hide_showcase()

		if played_peek_card2 and target_hand3 and root_scene3:
			# Return card to the acting hand
			if target_hand3.has_method("add_card_to_hand"):
				target_hand3.add_card_to_hand(played_peek_card2, 0.3)
				# Flip orientation based on destination hand
				if target_hand3.name == "player_hand" and played_peek_card2.has_method("flip_to_front"):
					played_peek_card2.flip_to_front(0.3)
				elif played_peek_card2.has_method("flip_to_back"):
					played_peek_card2.flip_to_back(0.3)

			# Lock the returned card with its colors
			var card_colors2 = _get_card_colors(played_peek_card2)
			played_peek_card2.set_locked(true, card_colors2)

			# Clear play area slot
			var play_area3 = root_scene3.get_node_or_null("PlayArea")
			if play_area3 and play_area3.has_method("clear_play_area"):
				play_area3.clear_play_area()

			# Relayout the acting hand
			await get_tree().create_timer(0.2).timeout
			if target_hand3.has_method("shuffle_hand"):
				target_hand3.shuffle_hand()

		# Reset background state back to default
		_set_background_default()
		
		# Effect complete - check if turn should end
		var gm_cancel_pd = get_node_or_null("/root/GameManager")
		if gm_cancel_pd and gm_cancel_pd.has_method("check_and_end_turn_if_needed"):
			gm_cancel_pd.check_and_end_turn_if_needed()
		
		# Do NOT consume action on cancel
		selection_data_global = null
		return

	# Handle PeekHand cancel: return played card to hand, lock it, relayout
	if selection_data_global and selection_data_global.get("effect_type", "") == "PeekHand":
		var played_peek_hand_card = selection_data_global.get("peek_card")
		var source_hand_c = selection_data_global.get("source_hand")
		var root_scene_c = selection_data_global.get("root_scene")
		var showcase_c = selection_data_global.get("showcase")

		# Hide showcase
		if showcase_c and showcase_c.has_method("hide_showcase"):
			showcase_c.hide_showcase()

		if played_peek_hand_card and source_hand_c and root_scene_c:
			# Return card to the source hand
			if source_hand_c.has_method("add_card_to_hand"):
				source_hand_c.add_card_to_hand(played_peek_hand_card, 0.3)
				# Flip orientation based on destination hand
				if source_hand_c.name == "player_hand" and played_peek_hand_card.has_method("flip_to_front"):
					played_peek_hand_card.flip_to_front(0.3)
				elif played_peek_hand_card.has_method("flip_to_back"):
					played_peek_hand_card.flip_to_back(0.3)

			# Lock the returned card with its colors
			var card_colors_c = _get_card_colors(played_peek_hand_card)
			played_peek_hand_card.set_locked(true, card_colors_c)

			# Clear play area slot
			var play_area_c = root_scene_c.get_node_or_null("PlayArea")
			if play_area_c and play_area_c.has_method("clear_play_area"):
				play_area_c.clear_play_area()

			# Cleanup selection mode
			_cleanup_selection_mode()

			# Relayout both hands
			await get_tree().create_timer(0.2).timeout
			var player_hand_c = root_scene_c.get_node_or_null("player_hand")
			var opp_hand_c = root_scene_c.get_node_or_null("opp_hand")
			if player_hand_c and player_hand_c.has_method("shuffle_hand"):
				player_hand_c.shuffle_hand()
			if opp_hand_c and opp_hand_c.has_method("shuffle_hand"):
				opp_hand_c.shuffle_hand()

		# Reset background state back to default
		_set_background_default()
		
		# Re-enable CardManager dragging
		var card_manager_c = get_node_or_null("/root/CardManager")
		if card_manager_c:
			card_manager_c.selection_mode_active = false
		
		# Effect complete - check if turn should end
		var gm_cancel_ph = get_node_or_null("/root/GameManager")
		if gm_cancel_ph and gm_cancel_ph.has_method("check_and_end_turn_if_needed"):
			gm_cancel_ph.check_and_end_turn_if_needed()
		
		# Do NOT consume action on cancel
		selection_data_global = null
		return

	# Fallback: if no context, just hide showcase
	var showcase_fallback = get_tree().get_current_scene().get_node_or_null("Showcase")
	if showcase_fallback and showcase_fallback.has_method("hide_showcase"):
		showcase_fallback.hide_showcase()

func _cleanup_selection_mode() -> void:
	"""Cleanup selection mode for both hands"""
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	var player_hand = root_scene.get_node_or_null("player_hand")
	
	# Clean up opponent hand
	var card_manager = get_node_or_null("/root/CardManager")
	if opp_hand and "opponent_hand" in opp_hand:
		for card in opp_hand.opponent_hand:
			if not card:
				continue
			
			# Hide Selection node
			if card.has_node("Selection"):
				card.get_node("Selection").visible = false
			
			# Disconnect selection hover signals (keep CardManager connections intact)
			if card.has_signal("hovered") and card.is_connected("hovered", Callable(self, "_on_selection_card_hovered")):
				card.disconnect("hovered", Callable(self, "_on_selection_card_hovered"))
			
			if card.has_signal("hovered_off") and card.is_connected("hovered_off", Callable(self, "_on_selection_card_hovered_off")):
				card.disconnect("hovered_off", Callable(self, "_on_selection_card_hovered_off"))
			
			# Reset visuals and collisions
			card.z_index = 0
			card.scale = Vector2(0.5, 0.5)
			
			# Disable Area2D collision
			if card.has_node("Area2D"):
				var area = card.get_node("Area2D")
				if area.has_node("CollisionShape2D"):
					area.get_node("CollisionShape2D").disabled = true
			
			# Ensure CardManager hover connects remain (re-register just in case)
			if card_manager and card_manager.has_method("_register_card_node"):
				card_manager._register_card_node(card)
	
	# Clean up player hand
	if player_hand and "player_hand" in player_hand:
		for card in player_hand.player_hand:
			if not card:
				continue
			
			# Hide Selection node
			if card.has_node("Selection"):
				card.get_node("Selection").visible = false
			
			# Disconnect selection hover signals (keep CardManager connections intact)
			if card.has_signal("hovered") and card.is_connected("hovered", Callable(self, "_on_selection_card_hovered")):
				card.disconnect("hovered", Callable(self, "_on_selection_card_hovered"))
			
			if card.has_signal("hovered_off") and card.is_connected("hovered_off", Callable(self, "_on_selection_card_hovered_off")):
				card.disconnect("hovered_off", Callable(self, "_on_selection_card_hovered_off"))
			
			# Reset visuals
			card.z_index = 0
			card.scale = Vector2(0.5, 0.5)
			
			# Ensure CardManager hover connects remain (re-register just in case)
			if card_manager and card_manager.has_method("_register_card_node"):
				card_manager._register_card_node(card)
	



# Selection mode callbacks
func _on_selection_card_hovered(card: Node) -> void:
	if not card:
		return
	if card.has_node("Selection"):
		var selection = card.get_node("Selection")
		selection.visible = true
	else:
		pass
	
	# Also scale up the card slightly during selection hover
	if card:
		var hover_scale = card.scale * 1.15
		var tween = get_tree().create_tween()
		tween.tween_property(card, "scale", hover_scale, 0.1)


func _on_selection_card_hovered_off(card: Node) -> void:
	if not card:
		return
	if card.has_node("Selection"):
		var selection = card.get_node("Selection")
		selection.visible = false
	else:
		pass
	
	# Reset card scale
	if card:
		var normal_scale = Vector2(0.5, 0.5)
		var tween = get_tree().create_tween()
		tween.tween_property(card, "scale", normal_scale, 0.1)


func _on_selection_card_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, card: Node, showcase: Node, _selection_data: Dictionary) -> void:
	# Ignore mouse motion events
	if event is InputEventMouseMotion:
		return
	if event is InputEventMouseButton and event.pressed:
		if showcase:
			showcase.visible = true
			if showcase.has_method("show_card"):
				showcase.show_card(card)
			else:
				pass
		
		# Re-enable CardManager dragging after selection
		var card_manager = get_node_or_null("/root/CardManager")
		if card_manager:
			card_manager.selection_mode_active = false
		
	elif event is InputEventScreenTouch and event.pressed:
		if showcase:
			showcase.visible = true
			if showcase.has_method("show_card"):
				showcase.show_card(card)
			else:
				pass
		
		# Re-enable CardManager dragging after selection
		var card_manager = get_node_or_null("/root/CardManager")
		if card_manager:
			card_manager.selection_mode_active = false

func _get_card_colors(card: Node) -> Dictionary:
	"""Extract color data from a card node"""
	var colors = {}
	
	# Check if card has color data from CardData
	if card.has_node("Frame/front/card info/Title"):
		var title = card.get_node("Frame/front/card info/Title")
		if title.material:
			colors["color_a"] = [
				title.material.get_shader_parameter("color_a").r,
				title.material.get_shader_parameter("color_a").g,
				title.material.get_shader_parameter("color_a").b,
				title.material.get_shader_parameter("color_a").a
			]
			colors["color_b"] = [
				title.material.get_shader_parameter("color_b").r,
				title.material.get_shader_parameter("color_b").g,
				title.material.get_shader_parameter("color_b").b,
				title.material.get_shader_parameter("color_b").a
			]
			colors["color_c"] = [
				title.material.get_shader_parameter("color_c").r,
				title.material.get_shader_parameter("color_c").g,
				title.material.get_shader_parameter("color_c").b,
				title.material.get_shader_parameter("color_c").a
			]
	
	return colors

func _on_showcase_cancel_pressed() -> void:
	if not selection_data_global:
		return
	_cancel_current_selection()


func _cancel_current_selection() -> void:
	# Cancel the current selection/peek and clean up state.
	if not selection_data_global:
		return

	if selection_data_global.get("effect_type", "") == "Swap":
		_cleanup_selection_mode()
		_set_background_default()
		var showcase_a = selection_data_global.get("showcase")
		if showcase_a and showcase_a.has_method("hide_showcase"):
			showcase_a.hide_showcase()
		var card_manager_a = get_node_or_null("/root/CardManager")
		if card_manager_a:
			card_manager_a.selection_mode_active = false
		selection_data_global = null

		var gm_cancel_swap = get_node_or_null("/root/GameManager")
		if gm_cancel_swap and gm_cancel_swap.has_method("check_and_end_turn_if_needed"):
			gm_cancel_swap.check_and_end_turn_if_needed()
		return

	if selection_data_global.get("effect_type", "") == "PeekDeck":
		var played_peek_card2 = selection_data_global.get("peek_card")
		var target_hand3 = selection_data_global.get("target_hand")
		var root_scene3 = selection_data_global.get("root_scene")
		var showcase_b = selection_data_global.get("showcase")

		if showcase_b and showcase_b.has_method("hide_showcase"):
			showcase_b.hide_showcase()

		if played_peek_card2 and target_hand3 and root_scene3:
			if target_hand3.has_method("add_card_to_hand"):
				target_hand3.add_card_to_hand(played_peek_card2, 0.3)
				if target_hand3.name == "player_hand" and played_peek_card2.has_method("flip_to_front"):
					played_peek_card2.flip_to_front(0.3)
				elif played_peek_card2.has_method("flip_to_back"):
					played_peek_card2.flip_to_back(0.3)

			var card_colors2 = _get_card_colors(played_peek_card2)
			played_peek_card2.set_locked(true, card_colors2)

			var play_area3 = root_scene3.get_node_or_null("PlayArea")
			if play_area3 and play_area3.has_method("clear_play_area"):
				play_area3.clear_play_area()

			await get_tree().create_timer(0.2).timeout
			if target_hand3.has_method("shuffle_hand"):
				target_hand3.shuffle_hand()

		_set_background_default()

		var gm_cancel_pd = get_node_or_null("/root/GameManager")
		if gm_cancel_pd and gm_cancel_pd.has_method("check_and_end_turn_if_needed"):
			gm_cancel_pd.check_and_end_turn_if_needed()

		selection_data_global = null
		return

	if selection_data_global.get("effect_type", "") == "PeekHand":
		var played_peek_hand_card = selection_data_global.get("peek_card")
		var source_hand_c = selection_data_global.get("source_hand")
		var root_scene_c = selection_data_global.get("root_scene")
		var showcase_c = selection_data_global.get("showcase")

		if showcase_c and showcase_c.has_method("hide_showcase"):
			showcase_c.hide_showcase()

		if played_peek_hand_card and source_hand_c and root_scene_c:
			if source_hand_c.has_method("add_card_to_hand"):
				source_hand_c.add_card_to_hand(played_peek_hand_card, 0.3)
				if source_hand_c.name == "player_hand" and played_peek_hand_card.has_method("flip_to_front"):
					played_peek_hand_card.flip_to_front(0.3)
				elif played_peek_hand_card.has_method("flip_to_back"):
					played_peek_hand_card.flip_to_back(0.3)

			var card_colors_c = _get_card_colors(played_peek_hand_card)
			played_peek_hand_card.set_locked(true, card_colors_c)

			var play_area_c = root_scene_c.get_node_or_null("PlayArea")
			if play_area_c and play_area_c.has_method("clear_play_area"):
				play_area_c.clear_play_area()

			_cleanup_selection_mode()

			await get_tree().create_timer(0.2).timeout
			var player_hand_c = root_scene_c.get_node_or_null("player_hand")
			var opp_hand_c = root_scene_c.get_node_or_null("opp_hand")
			if player_hand_c and player_hand_c.has_method("shuffle_hand"):
				player_hand_c.shuffle_hand()
			if opp_hand_c and opp_hand_c.has_method("shuffle_hand"):
				opp_hand_c.shuffle_hand()

		_set_background_default()

		var card_manager_c = get_node_or_null("/root/CardManager")
		if card_manager_c:
			card_manager_c.selection_mode_active = false

		var gm_cancel_ph = get_node_or_null("/root/GameManager")
		if gm_cancel_ph and gm_cancel_ph.has_method("check_and_end_turn_if_needed"):
			gm_cancel_ph.check_and_end_turn_if_needed()

		selection_data_global = null
		return

	var showcase_fallback = get_tree().get_current_scene().get_node_or_null("Showcase")
	if showcase_fallback and showcase_fallback.has_method("hide_showcase"):
		showcase_fallback.hide_showcase()
