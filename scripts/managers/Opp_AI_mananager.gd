extends Node

@export var think_delay_min: float = 0.3
@export var think_delay_max: float = 0.8
@export var min_action_score: float = 0.5
@export var decision_margin: float = 1.0

var _ai_turn_active: bool = false
var known_player_card_values: Dictionary = {}
var last_selected_player_card: Node = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("turn_started"):
		gm.connect("turn_started", Callable(self, "_on_turn_started"))


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_turn_started(player: int) -> void:
	# Only act on opponent turns; keep the AI fair and paced.
	if player != 1:
		return
	if _ai_turn_active:
		return
	_ai_turn_active = true
	await _wait_for_end_round_panel()
	await get_tree().create_timer(randf_range(think_delay_min, think_delay_max)).timeout
	await _take_turn()
	_ai_turn_active = false


func _take_turn() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if not gm:
		return
	while gm.current_turn_player == 1 and gm.actions_left > 0:
		var card_to_play = _choose_best_action_card()
		if not card_to_play:
			gm.pass_turn()
			return
		var played = await play_card_from_hand(card_to_play)
		if not played:
			gm.pass_turn()
			return
		await _wait_for_effects_to_settle()
		await get_tree().create_timer(randf_range(think_delay_min, think_delay_max)).timeout


# Play a card from opponent's hand to the play area
func play_card_from_hand(card: Node) -> bool:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return false
	
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	var play_area = root_scene.get_node_or_null("PlayArea")
	
	if not opp_hand or not play_area:
		return false
	
	if play_area.card_in_slot:
		return false
	
	if not card:
		return false
	
	# Don't play locked cards
	if "locked" in card and card.locked:
		return false
	
	
	# Play touch sound when AI picks up card
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_card_touch"):
		sound_manager.play_card_touch()
	
	# Set z-index high so card is visible above play area during animation
	card.z_index = 100
	
	# Set scale to match player cards
	card.scale = Vector2(.5, .5)
	
	# Flip card to front
	if card.has_method("flip_to_front"):
		card.flip_to_front(0.2)
	
	# Animate card moving FROM current position TO play area
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", play_area.position, 0.5)
	await tween.finished
	
	# Note: play_card_played sound is handled by effects_manager, not here
	
	# Remove from hand FIRST (exact same order as player)
	if opp_hand.has_method("remove_card_from_hand"):
		opp_hand.remove_card_from_hand(card)
	
	# Trigger play area effect (exact same as player)
	if play_area.has_method("_on_area_body_entered"):
		play_area._on_area_body_entered(card)
	
	# Disable collision and mark slot (exact same as player)
	if card.has_node("Area2D/CollisionShape2D"):
		card.get_node("Area2D/CollisionShape2D").disabled = true
	play_area.card_in_slot = true
	
	return true


# Play a Draw card from opponent's hand (for testing/AI)
func play_draw_card() -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	if not opp_hand:
		return
	
	# Find an unlocked Draw card in opponent's hand
	var draw_card = null
	for card in opp_hand.opponent_hand:
		if card and "suit" in card and card.suit == "Draw":
			# Skip locked cards
			if "locked" in card and card.locked:
				continue
			draw_card = card
			break
	
	if not draw_card:
		return
	
	await play_card_from_hand(draw_card)


# Play a Swap card from opponent's hand (for testing/AI)
func play_swap_card() -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	if not opp_hand:
		return
	
	# Find an unlocked Swap card in opponent's hand
	var swap_card = null
	for card in opp_hand.opponent_hand:
		if card and "suit" in card and card.suit == "Swap":
			# Skip locked cards
			if "locked" in card and card.locked:
				continue
			swap_card = card
			break
	
	if not swap_card:
		return
	
	await play_card_from_hand(swap_card)
	
	# After playing swap card, AI needs to select a card from player's hand
	# Wait a bit for selection mode to activate
	await get_tree().create_timer(0.5).timeout
	await ai_select_card_from_player_hand()


# AI selects a random card from player's hand during selection mode
func ai_select_card_from_player_hand(auto_confirm: bool = true) -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	
	var player_hand = root_scene.get_node_or_null("player_hand")
	if not player_hand:
		return
	
	var player_cards = player_hand.player_hand
	if player_cards.size() == 0:
		return

	_prune_known_player_cards(player_cards)
	
	# Simulate "thinking" - hover over each card one by one
	var sound_manager = get_node_or_null("/root/SoundManager")
	for card in player_cards:
		# Play hover sound for each card
		if sound_manager and sound_manager.has_method("play_card_hover"):
			sound_manager.play_card_hover()
		
		# Show selection highlight
		if card.has_node("Selection"):
			card.get_node("Selection").visible = true
		
		# Scale up card (hover effect) - snappy!
		var card_original_scale = card.scale
		var hover_tween = get_tree().create_tween()
		hover_tween.tween_property(card, "scale", card_original_scale * 1.1, 0.1)
		await hover_tween.finished
		
		# Hold for a moment
		await get_tree().create_timer(0.1).timeout
		
		# Scale back down - snappy!
		var unhover_tween = get_tree().create_tween()
		unhover_tween.tween_property(card, "scale", card_original_scale, 0.1)
		await unhover_tween.finished
		
		# Hide selection highlight
		if card.has_node("Selection"):
			card.get_node("Selection").visible = false
		
		# Short pause before next card
		await get_tree().create_timer(0.05).timeout
	
	var selected_card = _choose_player_card_for_selection(player_cards)
	
	
	# Show the selected card with highlight
	if selected_card.has_node("Selection"):
		selected_card.get_node("Selection").visible = true
	
	# Scale up the selected card
	var original_scale = selected_card.scale
	var select_tween = get_tree().create_tween()
	select_tween.tween_property(selected_card, "scale", original_scale * 1.1, 0.15)
	await select_tween.finished
	
	# Hold to show the choice
	await get_tree().create_timer(0.3).timeout
	
	# Get showcase reference
	var showcase = root_scene.get_node_or_null("Showcase")
	if not showcase:
		return
	
	# Store the selected card in selection_data_global (IMPORTANT!)
	var effects_manager = get_node_or_null("/root/EffectsManager")
	if effects_manager and "selection_data_global" in effects_manager and effects_manager.selection_data_global:
		effects_manager.selection_data_global["selected_card"] = selected_card
	else:
		pass

	# Remember the revealed card value for future decisions
	if "value" in selected_card:
		known_player_card_values[selected_card.get_instance_id()] = int(selected_card.value)
	last_selected_player_card = selected_card
	
	# Trigger the card selection to show in showcase
	if effects_manager and effects_manager.has_method("_handle_card_selection"):
		effects_manager._handle_card_selection(selected_card, showcase)
	
	# Wait to show the showcase
	await get_tree().create_timer(0.8).timeout
	
	# Auto-click OK button only if requested (for Swap, not for PeekHand)
	if auto_confirm and showcase and showcase.has_method("_on_control_button_pressed"):
		showcase._on_control_button_pressed()
	
	# Clean up - hide selection highlights and reset scale for ALL cards
	for card in player_cards:
		if card.has_node("Selection"):
			card.get_node("Selection").visible = false
		# Reset scale for the selected card
		if card == selected_card:
			var reset_tween = get_tree().create_tween()
			reset_tween.tween_property(card, "scale", original_scale, 0.15)


# Play a PeekDeck card from opponent's hand (for testing/AI)
func play_peek_deck_card() -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	if not opp_hand:
		return
	
	# Find an unlocked PeekDeck card in opponent's hand
	var peek_card = null
	for card in opp_hand.opponent_hand:
		if card and "suit" in card and card.suit == "PeekDeck":
			# Skip locked cards
			if "locked" in card and card.locked:
				continue
			peek_card = card
			break
	
	if not peek_card:
		return
	
	await play_card_from_hand(peek_card)
	
	# effects_manager will automatically call ai_peek_deck_action() when opponent plays PeekDeck


# AI decides whether to draw or cancel on PeekDeck
func ai_peek_deck_action() -> void:
	# Small delay to ensure showcase is fully visible
	await get_tree().create_timer(0.2).timeout
	
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		print("[AI] No root scene found")
		return
	
	var showcase = root_scene.get_node_or_null("Showcase")
	if not showcase:
		print("[AI] No showcase found")
		return
	
	var start_time = Time.get_ticks_msec()
	while showcase and not showcase.visible:
		if Time.get_ticks_msec() - start_time > 2000:
			print("[AI] Showcase not visible")
			return
		await get_tree().create_timer(0.1).timeout
	
	# Simulate thinking delay (like other AI effects)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_card_hover"):
		sound_manager.play_card_hover()
	
	# Thinking pause
	await get_tree().create_timer(0.3).timeout
	
	# AI strategy: draw if the revealed top card is better than the PeekDeck card.
	var should_draw = false
	var effects_manager = get_node_or_null("/root/EffectsManager")
	var deck = root_scene.get_node_or_null("Deck")
	if effects_manager and effects_manager.selection_data_global and deck and "player_deck" in deck and deck.player_deck.size() > 0:
		var peek_card = effects_manager.selection_data_global.get("peek_card")
		var top_card = deck.player_deck[0]
		var peek_value = _get_card_value(peek_card)
		var top_value = _get_card_value(top_card)
		if top_value <= peek_value - decision_margin:
			should_draw = true
	else:
		# Fallback: slight bias toward drawing to keep things moving.
		should_draw = randf() < 0.6
	
	# Additional pause before deciding
	await get_tree().create_timer(0.5).timeout
	
	print("[AI] Making PeekDeck decision: ", "DRAW" if should_draw else "CANCEL")
	
	# Execute AI decision (no arguments—showcase has current_effect_type set)
	if should_draw:
		# Click DRAW button
		if showcase.has_method("_on_control_button_pressed"):
			showcase._on_control_button_pressed()
	else:
		# Click CANCEL button
		if showcase.has_method("_on_cancel_button_pressed"):
			showcase._on_cancel_button_pressed()

# Play a PeekHand card from opponent's hand (for testing/AI)
func play_peek_hand_card() -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	if not opp_hand:
		return
	
	# Find an unlocked PeekHand card in opponent's hand
	var peek_card = null
	for card in opp_hand.opponent_hand:
		if card and "suit" in card and card.suit == "PeekHand":
			# Skip locked cards
			if "locked" in card and card.locked:
				continue
			peek_card = card
			break
	
	if not peek_card:
		return
	
	await play_card_from_hand(peek_card)
	
	# After playing PeekHand card, AI needs to select a card from player's hand
	# Wait a bit for selection mode to activate
	await get_tree().create_timer(0.5).timeout
	await ai_select_card_from_player_hand(false)  # Don't auto-confirm, we'll decide in ai_peek_hand_action
	
	# After selection, AI decides: Swap or Cancel
	# Wait a bit for the decision
	await get_tree().create_timer(0.5).timeout
	await ai_peek_hand_action()


# AI decides whether to swap or cancel on PeekHand
func ai_peek_hand_action() -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	
	var showcase = root_scene.get_node_or_null("Showcase")
	if not showcase:
		return
	var start_time = Time.get_ticks_msec()
	while showcase and not showcase.visible:
		if Time.get_ticks_msec() - start_time > 2000:
			return
		await get_tree().create_timer(0.1).timeout
	
	# Simulate thinking delay
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_card_hover"):
		sound_manager.play_card_hover()
	
	# Thinking pause
	await get_tree().create_timer(0.3).timeout
	
	# AI strategy: swap only if the selected card improves the hand.
	var should_swap = false
	var effects_manager = get_node_or_null("/root/EffectsManager")
	if effects_manager and effects_manager.selection_data_global:
		var selected_card = effects_manager.selection_data_global.get("selected_card")
		var peek_card = effects_manager.selection_data_global.get("peek_card")
		var selected_value = _get_card_value(selected_card)
		var peek_value = _get_card_value(peek_card)
		if selected_value <= peek_value - decision_margin:
			should_swap = true
	else:
		should_swap = randf() < 0.5
	
	# Additional pause before deciding
	await get_tree().create_timer(0.5).timeout
	
	# Execute AI decision
	if should_swap:
		# Click SWAP button
		if showcase.has_method("_on_control_button_pressed"):
			showcase._on_control_button_pressed()
	else:
		# Click CANCEL button
		if showcase.has_method("_on_cancel_button_pressed"):
			showcase._on_cancel_button_pressed()


func _choose_best_action_card() -> Node:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return null
	var opp_hand = root_scene.get_node_or_null("opp_hand")
	if not opp_hand or not "opponent_hand" in opp_hand:
		return null
	var best_card: Node = null
	var best_score: float = -INF
	for card in opp_hand.opponent_hand:
		if not card:
			continue
		if "locked" in card and card.locked:
			continue
		var score = _score_action_card(card)
		score += randf_range(-0.2, 0.2)  # small randomness so it's not perfect
		if score > best_score:
			best_score = score
			best_card = card
	if best_card and best_score >= min_action_score:
		return best_card
	return null


func _score_action_card(card: Node) -> float:
	var suit = str(card.get("suit")) if card and card.has_method("get") else ""
	var value = _get_card_value(card)
	var expected_deck = _expected_deck_value()
	var expected_player = _expected_player_card_value()
	match suit:
		"Draw":
			return value - expected_deck
		"Swap":
			return value - expected_player + 0.5
		"PeekDeck":
			return (value - expected_deck) * 0.8
		"PeekHand":
			return value - expected_player + 1.0
		_:
			return 0.0


func _expected_deck_value() -> float:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return 5.0
	var deck = root_scene.get_node_or_null("Deck")
	if not deck or not "player_deck" in deck or deck.player_deck.size() == 0:
		return 5.0
	var total = 0
	var count = 0
	for card in deck.player_deck:
		if card and "value" in card:
			total += int(card.value)
			count += 1
	return float(total) / float(count) if count > 0 else 5.0


func _expected_player_card_value() -> float:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return _expected_deck_value()
	var player_hand = root_scene.get_node_or_null("player_hand")
	if not player_hand or not "player_hand" in player_hand:
		return _expected_deck_value()
	var known_values: Array = []
	for card in player_hand.player_hand:
		if card and known_player_card_values.has(card.get_instance_id()):
			known_values.append(known_player_card_values[card.get_instance_id()])
	if known_values.size() > 0:
		known_values.sort()
		return float(known_values[0])
	return _expected_deck_value()


func _choose_player_card_for_selection(player_cards: Array) -> Node:
	var best_card: Node = null
	var best_value: int = 9999
	for card in player_cards:
		if card and known_player_card_values.has(card.get_instance_id()):
			var val = int(known_player_card_values[card.get_instance_id()])
			if val < best_value:
				best_value = val
				best_card = card
	if best_card:
		return best_card
	return player_cards[randi() % player_cards.size()]


func _prune_known_player_cards(player_cards: Array) -> void:
	var valid_ids: Dictionary = {}
	for card in player_cards:
		if card:
			valid_ids[card.get_instance_id()] = true
	for key in known_player_card_values.keys():
		if not valid_ids.has(key):
			known_player_card_values.erase(key)


func _get_card_value(card: Node) -> int:
	if not card:
		return 0
	if "value" in card:
		return int(card.value)
	return 0


func _wait_for_effects_to_settle() -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	var effects_manager = get_node_or_null("/root/EffectsManager")
	var play_area = root_scene.get_node_or_null("PlayArea")
	var showcase = root_scene.get_node_or_null("Showcase")
	var start_time = Time.get_ticks_msec()
	while true:
		var selection_active = effects_manager and effects_manager.selection_data_global != null
		var play_area_busy = play_area and play_area.card_in_slot
		var showcase_visible = showcase and showcase.visible
		if not selection_active and not play_area_busy and not showcase_visible:
			break
		if Time.get_ticks_msec() - start_time > 8000:
			break
		await get_tree().create_timer(0.1).timeout


func _wait_for_end_round_panel() -> void:
	var root_scene = get_tree().get_current_scene()
	if not root_scene:
		return
	var end_round_panel = root_scene.get_node_or_null("END_ROUND_PANEL")
	var start_time = Time.get_ticks_msec()
	while end_round_panel and end_round_panel.visible:
		if Time.get_ticks_msec() - start_time > 15000:
			break
		await get_tree().create_timer(0.1).timeout
