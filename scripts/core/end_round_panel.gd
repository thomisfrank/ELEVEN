extends Panel

# Track grand totals across rounds
var player_grand_total: int = 0
var opponent_grand_total: int = 0

# Track best (lowest) hand per player across the game
var player_best_hand_score: int = 9999
var opponent_best_hand_score: int = 9999
var player_best_hand_cards: Array = []
var opponent_best_hand_cards: Array = []

# Store cards to discard when round ends
var player_cards_to_discard: Array = []
var opp_cards_to_discard: Array = []


func _ready() -> void:
	# Start hidden, will be shown when round ends
	visible = false
	
	# Hide the OKAY button initially
	var okay_button = get_node_or_null("VBoxContainer/Button")
	if okay_button:
		okay_button.visible = false
		okay_button.pressed.connect(_on_okay_button_pressed)


func show_end_round_screen(player_cards: Array = [], opp_cards: Array = []) -> void:
	# Store cards for discarding later
	player_cards_to_discard = player_cards
	opp_cards_to_discard = opp_cards
	
	# Clear any previous round data first
	_clear_panel()
	
	# Get the screen size to calculate starting position
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Get the panel's original/default position from scene
	# If this is the first time, store it. If not, reset to it.
	if not has_meta("original_position"):
		set_meta("original_position", position.y)
	var original_y = get_meta("original_position")
	
	# Start the panel at the bottom of the screen
	position.y = viewport_size.y
	
	# Show the panel
	visible = true
	
	# Play end round panel sound
	SoundManager.play_end_round_panel()
	
	# Animate the panel scrolling up from the bottom to its original position
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", original_y, 0.8)
	await tween.finished
	
	# Display the round number
	var gm = get_node_or_null("/root/GameManager")
	print("[END_ROUND] GameManager: ", gm)
	if gm:
		print("[END_ROUND] Current round: ", gm.current_round if "current_round" in gm else "NO current_round")
		var current_round = gm.current_round if "current_round" in gm else 1
		# Update the round counter labels with two-digit format
		var round_str = str(current_round).pad_zeros(2)
		var r_value_1 = get_node_or_null("VBoxContainer/ROUND_COUNTER/R Value 1")
		var r_value_2 = get_node_or_null("VBoxContainer/ROUND_COUNTER/R Value 2")
		
		print("[END_ROUND] Round string: ", round_str)
		print("[END_ROUND] R Value 1: ", r_value_1)
		print("[END_ROUND] R Value 2: ", r_value_2)
		
		if r_value_1:
			r_value_1.text = round_str[0]
			print("[END_ROUND] Set R Value 1 to: ", round_str[0])
		if r_value_2:
			r_value_2.text = round_str[1]
			print("[END_ROUND] Set R Value 2 to: ", round_str[1])
	
	# Wait a brief moment before filling hands
	await get_tree().create_timer(0.2).timeout
	
	# Fill player's end round hand slots with captured cards
	var player_end_hand = get_node_or_null("VBoxContainer/PlayerEndRoundHand")
	if player_end_hand and player_cards.size() > 0:
		for i in range(min(4, player_cards.size())):
			var slot = player_end_hand.get_node_or_null("hand_slot_%d" % (i + 1))
			if slot and player_cards[i]:
				await _fill_slot_with_card(slot, player_cards[i])
				await get_tree().create_timer(0.08).timeout  # Quick delay between cards
	
	# Fill opponent's end round hand slots with captured cards
	var opp_end_hand = get_node_or_null("VBoxContainer/OppEndRoundHand")
	if opp_end_hand and opp_cards.size() > 0:
		for i in range(min(4, opp_cards.size())):
			var slot = opp_end_hand.get_node_or_null("hand_slot_%d" % (i + 1))
			if slot and opp_cards[i]:
				await _fill_slot_with_card(slot, opp_cards[i])
				await get_tree().create_timer(0.08).timeout  # Quick delay between cards
	
	# Calculate hand values
	var player_score = _calculate_hand_value(player_cards)
	var opp_score = _calculate_hand_value(opp_cards)

	# Track each side's best (lowest) hand for end-game display
	if player_cards.size() > 0 and player_score < player_best_hand_score:
		player_best_hand_score = player_score
		player_best_hand_cards = player_cards.duplicate()
	if opp_cards.size() > 0 and opp_score < opponent_best_hand_score:
		opponent_best_hand_score = opp_score
		opponent_best_hand_cards = opp_cards.duplicate()
	
	# Wait a moment after revealing hands
	await get_tree().create_timer(0.5).timeout
	
	# Animate scores counting up
	await _animate_score_count_up("VBoxContainer/PlayerScoreScreen", player_score)
	await _animate_score_count_up("VBoxContainer/OppScoreScreen", opp_score)
	
	# Wait a moment before revealing winner
	await get_tree().create_timer(0.5).timeout
	
	# Determine winner (LOWEST score wins)
	var winner_text = ""
	
	if player_score < opp_score:
		winner_text = "YOU"
		player_grand_total += player_score
		SoundManager.play_round_win()
	elif opp_score < player_score:
		winner_text = "OPPONENT"
		opponent_grand_total += opp_score
		SoundManager.play_round_lost()
	else:
		# Tie - no one gets points
		winner_text = "TIE"
		SoundManager.play_round_tie()
	
	print("[END_ROUND] Winner: ", winner_text, " Player score: ", player_score, " Opp score: ", opp_score)
	
	# Display winner - make sure the result screen is visible
	var result_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN")
	if result_screen:
		result_screen.visible = true
	
	var winner_label = get_node_or_null("VBoxContainer/RESULT_SCREEN/Round goes to/WINNER")
	print("[END_ROUND] Winner label: ", winner_label)
	if winner_label:
		winner_label.visible = true
		winner_label.text = winner_text
		print("[END_ROUND] Set winner text to: ", winner_text)
	
	# Wait a moment before showing grand total
	await get_tree().create_timer(0.5).timeout
	
	# Determine which grand total to display (the winner's)
	var grand_total_to_show = 0
	if winner_text == "YOU":
		grand_total_to_show = player_grand_total
	elif winner_text == "OPPONENT":
		grand_total_to_show = opponent_grand_total
	# For tie, show 0 or don't update
	
	# Animate grand total counting up
	await _animate_grand_total(grand_total_to_show)
	
	# Wait a moment then reveal the OKAY button
	await get_tree().create_timer(0.5).timeout
	var okay_button = get_node_or_null("VBoxContainer/Button")
	if okay_button:
		okay_button.visible = true


func _calculate_hand_value(cards: Array) -> int:
	"""Calculate the total value of all cards in the hand"""
	var total = 0
	print("[END_ROUND] Calculating value for ", cards.size(), " cards")
	for card in cards:
		if card and "value" in card:
			var value = card.value
			print("[END_ROUND] Card has value: ", value)
			# Convert to int if it's a string
			if value is String:
				total += int(value)
			else:
				total += value
		else:
			print("[END_ROUND] Card missing value property: ", card)
	print("[END_ROUND] Total calculated: ", total)
	return total


func _animate_score_count_up(score_screen_path: String, final_score: int) -> void:
	"""Animate the score display counting up from 0 to final_score"""
	print("[END_ROUND] Animating score for: ", score_screen_path, " Final score: ", final_score)
	var score_screen = get_node_or_null(score_screen_path)
	if not score_screen:
		print("[END_ROUND] Score screen not found: ", score_screen_path)
		return
	
	# Get the three score value labels
	var score_value_1 = score_screen.get_node_or_null("score_value_1")
	var score_value_2 = score_screen.get_node_or_null("score_value_2")
	var score_value_3 = score_screen.get_node_or_null("score_value_3")
	
	print("[END_ROUND] Labels found: ", score_value_1, " ", score_value_2, " ", score_value_3)
	
	if not score_value_1 or not score_value_2 or not score_value_3:
		print("[END_ROUND] One or more score labels not found")
		return
	
	# Animate counting from 0 to final_score
	var duration = 1.0  # 1 second animation
	var steps = 30  # Number of update steps
	var step_time = duration / steps
	
	for i in range(steps + 1):
		var current_value = int(float(final_score) * float(i) / float(steps))
		var value_str = str(current_value).pad_zeros(3)  # Ensure 3 digits
		
		# Split into individual digits
		score_value_1.text = value_str[0]
		score_value_2.text = value_str[1]
		score_value_3.text = value_str[2]
		
		SoundManager.play_point_beep()
		
		if i < steps:
			await get_tree().create_timer(step_time).timeout


func _animate_grand_total(final_total: int) -> void:
	"""Animate the grand total display counting up"""
	var score_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN/NEW_SCORE/score_screen")
	if not score_screen:
		return
	
	# Get the three score value labels
	var new_score_v1 = score_screen.get_node_or_null("new_score_v")
	var new_score_v2 = score_screen.get_node_or_null("new_score_v2")
	var new_score_v3 = score_screen.get_node_or_null("new_score_v3")
	
	if not new_score_v1 or not new_score_v2 or not new_score_v3:
		return
	
	# Animate counting from 0 to final_total
	var duration = 1.0  # 1 second animation
	var steps = 30  # Number of update steps
	var step_time = duration / steps
	
	for i in range(steps + 1):
		var current_value = int(float(final_total) * float(i) / float(steps))
		var value_str = str(current_value).pad_zeros(3)  # Ensure 3 digits
		
		# Split into individual digits
		new_score_v1.text = value_str[0]
		new_score_v2.text = value_str[1]
		new_score_v3.text = value_str[2]
		
		SoundManager.play_point_beep()
		
		if i < steps:
			await get_tree().create_timer(step_time).timeout


func _fill_slot_with_card(slot: Node, card: Node) -> void:
	# Remove any existing card display in this slot
	for child in slot.get_children():
		child.queue_free()
	
	# Duplicate the entire Frame like showcase does
	if card.has_node("Frame"):
		var card_frame = card.get_node("Frame")
		var card_display = card_frame.duplicate()
		card_display.name = "CardDisplay"
		card_display.visible = true
		
		# Make sure front is visible and back is hidden
		if card_display.has_node("front"):
			card_display.get_node("front").visible = true
		if card_display.has_node("back"):
			card_display.get_node("back").visible = false
		
		# Hide locked overlay
		if card_display.has_node("locked"):
			card_display.get_node("locked").visible = false
		
		# Add to slot
		slot.add_child(card_display)
		
		# Play card sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager and sound_manager.has_method("play_card_touch"):
			sound_manager.play_card_touch()
		
		# Position and scale exactly like showcase - at origin with 0.5 scale
		card_display.position = Vector2.ZERO
		
		# Animate: start from scale 0, pop to 0.5 scale with bouncy effect
		card_display.scale = Vector2.ZERO
		var tween = get_tree().create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(card_display, "scale", Vector2(0.5, 0.5), 0.25)
		await tween.finished

func _on_okay_button_pressed() -> void:
	"""Handle OKAY button press - animate panel down and hide it"""
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Play close panel sound
	SoundManager.play_close_end_round_panel()
	
	# Discard all cards from both hands to the discard pile
	var root = get_tree().get_current_scene()
	var discard_pile = root.get_node_or_null("DiscardPile")
	
	if discard_pile and discard_pile.has_method("accept_card"):
		# Discard player cards
		for card in player_cards_to_discard:
			if card:
				# Remove from current parent
				if card.get_parent():
					card.get_parent().remove_child(card)
				discard_pile.accept_card(card)
				await get_tree().create_timer(0.03).timeout
		
		# Discard opponent cards (flip face up first)
		for card in opp_cards_to_discard:
			if card:
				# Flip to front while still in scene tree
				if card.has_method("flip_to_front"):
					await card.flip_to_front(0.2)
				# Remove from current parent
				if card.get_parent():
					card.get_parent().remove_child(card)
				discard_pile.accept_card(card)
				await get_tree().create_timer(0.03).timeout
	
	# Clear the stored card arrays
	player_cards_to_discard.clear()
	opp_cards_to_discard.clear()
	
	# Animate panel scrolling down off screen with bounce
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", viewport_size.y, 0.6)
	await tween.finished
	
	# Hide the panel and reset button visibility for next time
	visible = false
	var okay_button = get_node_or_null("VBoxContainer/Button")
	if okay_button:
		okay_button.visible = false
	
	# Hide result screen for next round
	var result_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN")
	if result_screen:
		result_screen.visible = false
	
	# Update scores in GamePanel before exiting
	var game_panel = root.get_node_or_null("GamePanel")
	if game_panel:
		var player_info = game_panel.get_node_or_null("Player_Info_Panel")
		var opp_info = game_panel.get_node_or_null("Opp_Info_Panel")
		
		if player_info and player_info.has_method("update_score"):
			player_info.update_score(player_grand_total)
		if opp_info and opp_info.has_method("update_score"):
			opp_info.update_score(opponent_grand_total)
	
	# Check if game is over and show EndGamePanel
	var gm = get_node_or_null("/root/GameManager")
	if gm and "game_over" in gm and gm.game_over:
		# Wait 0.25 seconds
		await get_tree().create_timer(0.25).timeout
		
		var game_winner_text = ""
		if player_grand_total > opponent_grand_total:
			game_winner_text = "YOU"
		elif opponent_grand_total > player_grand_total:
			game_winner_text = "OPPONENT"
		else:
			game_winner_text = "TIE"

		var round_count = gm.current_round if "current_round" in gm else 1
		var winning_total = max(player_grand_total, opponent_grand_total)
		var winning_hand_cards: Array = []
		if game_winner_text == "YOU":
			winning_hand_cards = player_best_hand_cards
		elif game_winner_text == "OPPONENT":
			winning_hand_cards = opponent_best_hand_cards
		elif game_winner_text == "TIE":
			if player_best_hand_score <= opponent_best_hand_score:
				winning_hand_cards = player_best_hand_cards
			else:
				winning_hand_cards = opponent_best_hand_cards

		# Show the EndGamePanel with same animation
		var end_game_panel = root.get_node_or_null("EndGamePanel")
		if end_game_panel and end_game_panel.has_method("show_end_game_screen"):
			await end_game_panel.show_end_game_screen(round_count, game_winner_text, winning_total, winning_hand_cards)
		elif end_game_panel:
			_show_end_game_panel(end_game_panel)


func _clear_panel() -> void:
	"""Clear all cards and values from the previous round"""
	# Clear player hand slots
	var player_end_hand = get_node_or_null("VBoxContainer/PlayerEndRoundHand")
	if player_end_hand:
		for i in range(1, 5):
			var slot = player_end_hand.get_node_or_null("hand_slot_%d" % i)
			if slot:
				for child in slot.get_children():
					if child.name == "CardDisplay":
						child.queue_free()
	
	# Clear opponent hand slots
	var opp_end_hand = get_node_or_null("VBoxContainer/OppEndRoundHand")
	if opp_end_hand:
		for i in range(1, 5):
			var slot = opp_end_hand.get_node_or_null("hand_slot_%d" % i)
			if slot:
				for child in slot.get_children():
					if child.name == "CardDisplay":
						child.queue_free()
	
	# Reset player score display to 000
	var player_score_screen = get_node_or_null("VBoxContainer/PlayerScoreScreen")
	if player_score_screen:
		var score_value_1 = player_score_screen.get_node_or_null("score_value_1")
		var score_value_2 = player_score_screen.get_node_or_null("score_value_2")
		var score_value_3 = player_score_screen.get_node_or_null("score_value_3")
		if score_value_1:
			score_value_1.text = "0"
		if score_value_2:
			score_value_2.text = "0"
		if score_value_3:
			score_value_3.text = "0"
	
	# Reset opponent score display to 000
	var opp_score_screen = get_node_or_null("VBoxContainer/OppScoreScreen")
	if opp_score_screen:
		var score_value_1 = opp_score_screen.get_node_or_null("score_value_1")
		var score_value_2 = opp_score_screen.get_node_or_null("score_value_2")
		var score_value_3 = opp_score_screen.get_node_or_null("score_value_3")
		if score_value_1:
			score_value_1.text = "0"
		if score_value_2:
			score_value_2.text = "0"
		if score_value_3:
			score_value_3.text = "0"
	
	# Hide result screen
	var result_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN")
	if result_screen:
		result_screen.visible = false
	
	# Hide okay button
	var okay_button = get_node_or_null("VBoxContainer/Button")
	if okay_button:
		okay_button.visible = false
	
	# Clear winner text
	var winner_label = get_node_or_null("VBoxContainer/RESULT_SCREEN/Round goes to/WINNER")
	if winner_label:
		winner_label.text = ""
	
	# Clear grand total score display
	var score_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN/NEW_SCORE/score_screen")
	if score_screen:
		var new_score_v1 = score_screen.get_node_or_null("new_score_v")
		var new_score_v2 = score_screen.get_node_or_null("new_score_v2")
		var new_score_v3 = score_screen.get_node_or_null("new_score_v3")
		if new_score_v1:
			new_score_v1.text = "0"
		if new_score_v2:
			new_score_v2.text = "0"
		if new_score_v3:
			new_score_v3.text = "0"


func _show_end_game_panel(end_game_panel: Node) -> void:
	"""Show the end game panel with the same animation as end round panel"""
	# Get the screen size to calculate starting position
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Get or store the panel's original position
	if not end_game_panel.has_meta("original_position"):
		end_game_panel.set_meta("original_position", end_game_panel.position.y)
	var original_y = end_game_panel.get_meta("original_position")
	
	# Start the panel at the bottom of the screen
	end_game_panel.position.y = viewport_size.y
	
	# Show the panel
	end_game_panel.visible = true
	
	# Play end game panel sound
	SoundManager.play_end_game_panel()
	
	# Animate the panel scrolling up from the bottom to its original position
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(end_game_panel, "position:y", original_y, 0.8)
	await tween.finished
