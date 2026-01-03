extends ColorRect

var winning_cards_to_show: Array = []


func _ready() -> void:
	visible = false
	var okay_button = get_node_or_null("VBoxContainer/Button")
	if okay_button:
		okay_button.visible = false
		okay_button.pressed.connect(_on_okay_button_pressed)


func show_end_game_screen(round_count: int, winner_text: String, winning_score: int, winning_cards: Array = []) -> void:
	winning_cards_to_show = winning_cards
	_clear_panel()

	var viewport_size = get_viewport().get_visible_rect().size
	if not has_meta("original_position"):
		set_meta("original_position", position.y)
	var original_y = get_meta("original_position")

	position.y = viewport_size.y
	visible = true

	SoundManager.play_end_game_panel()

	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", original_y, 0.8)
	await tween.finished

	_set_round_counter(round_count)

	await get_tree().create_timer(0.2).timeout
	_fill_end_game_hand(winning_cards_to_show)

	await get_tree().create_timer(0.1).timeout
	await _animate_score_count_up("VBoxContainer/End GameScoreScreen", winning_score)

	await get_tree().create_timer(0.5).timeout
	var result_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN")
	if result_screen:
		result_screen.visible = true
	if winner_text == "YOU":
		SoundManager.play_round_win()
	elif winner_text == "OPPONENT":
		SoundManager.play_round_lost()
	elif winner_text == "TIE":
		SoundManager.play_round_tie()
	_set_winner_text(winner_text)

	await get_tree().create_timer(0.5).timeout
	await _animate_final_score(winning_score)

	await get_tree().create_timer(0.5).timeout
	var okay_button = get_node_or_null("VBoxContainer/Button")
	if okay_button:
		okay_button.visible = true


func _set_round_counter(round_count: int) -> void:
	var round_str = str(round_count).pad_zeros(2)
	var r_value_1 = get_node_or_null("VBoxContainer/ROUND_COUNTER/R Value 1")
	var r_value_2 = get_node_or_null("VBoxContainer/ROUND_COUNTER/R Value 2")
	if r_value_1:
		r_value_1.text = round_str[0]
	if r_value_2:
		r_value_2.text = round_str[1]


func _set_winner_text(winner_text: String) -> void:
	var winner_label = get_node_or_null("VBoxContainer/WinnerRevealScreen/winner")
	if winner_label:
		winner_label.text = winner_text


func _animate_score_count_up(score_screen_path: String, final_score: int) -> void:
	var score_screen = get_node_or_null(score_screen_path)
	if not score_screen:
		return

	var score_value_1 = score_screen.get_node_or_null("score_value_1")
	var score_value_2 = score_screen.get_node_or_null("score_value_2")
	var score_value_3 = score_screen.get_node_or_null("score_value_3")
	if not score_value_1 or not score_value_2 or not score_value_3:
		return

	var duration = 1.0
	var steps = 30
	var step_time = duration / steps

	for i in range(steps + 1):
		var current_value = int(float(final_score) * float(i) / float(steps))
		var value_str = str(current_value).pad_zeros(3)
		score_value_1.text = value_str[0]
		score_value_2.text = value_str[1]
		score_value_3.text = value_str[2]
		SoundManager.play_point_beep()
		if i < steps:
			await get_tree().create_timer(step_time).timeout


func _animate_final_score(final_score: int) -> void:
	var score_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN/FINAL_SCORE/score_screen")
	if not score_screen:
		return

	var new_score_v1 = score_screen.get_node_or_null("new_score_v")
	var new_score_v2 = score_screen.get_node_or_null("new_score_v2")
	var new_score_v3 = score_screen.get_node_or_null("new_score_v3")
	if not new_score_v1 or not new_score_v2 or not new_score_v3:
		return

	var duration = 1.0
	var steps = 30
	var step_time = duration / steps

	for i in range(steps + 1):
		var current_value = int(float(final_score) * float(i) / float(steps))
		var value_str = str(current_value).pad_zeros(3)
		new_score_v1.text = value_str[0]
		new_score_v2.text = value_str[1]
		new_score_v3.text = value_str[2]
		SoundManager.play_point_beep()
		if i < steps:
			await get_tree().create_timer(step_time).timeout


func _fill_end_game_hand(cards: Array) -> void:
	var end_game_hand = get_node_or_null("VBoxContainer/EndGameHand")
	if not end_game_hand:
		return
	for i in range(min(4, cards.size())):
		var slot = end_game_hand.get_node_or_null("hand_slot_%d" % (i + 1))
		if slot and cards[i]:
			await _fill_slot_with_card(slot, cards[i])
			await get_tree().create_timer(0.08).timeout


func _fill_slot_with_card(slot: Node, card: Node) -> void:
	# Duplicate the card frame and place it in the slot with a quick pop.
	if not card.has_node("Frame"):
		return

	var card_frame = card.get_node("Frame")
	var card_display = card_frame.duplicate()
	card_display.name = "CardDisplay"
	card_display.visible = true

	if card_display.has_node("front"):
		card_display.get_node("front").visible = true
	if card_display.has_node("back"):
		card_display.get_node("back").visible = false
	if card_display.has_node("locked"):
		card_display.get_node("locked").visible = false

	slot.add_child(card_display)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_card_touch"):
		sound_manager.play_card_touch()
	card_display.position = Vector2.ZERO
	card_display.scale = Vector2.ZERO
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(card_display, "scale", Vector2(0.5, 0.5), 0.25)
	await tween.finished


func _clear_panel() -> void:
	var end_game_hand = get_node_or_null("VBoxContainer/EndGameHand")
	if end_game_hand:
		for i in range(1, 5):
			var slot = end_game_hand.get_node_or_null("hand_slot_%d" % i)
			if slot:
				for child in slot.get_children():
					if child.name == "CardDisplay":
						child.queue_free()

	var score_screen = get_node_or_null("VBoxContainer/End GameScoreScreen")
	if score_screen:
		var score_value_1 = score_screen.get_node_or_null("score_value_1")
		var score_value_2 = score_screen.get_node_or_null("score_value_2")
		var score_value_3 = score_screen.get_node_or_null("score_value_3")
		if score_value_1:
			score_value_1.text = "0"
		if score_value_2:
			score_value_2.text = "0"
		if score_value_3:
			score_value_3.text = "0"

	var winner_label = get_node_or_null("VBoxContainer/WinnerRevealScreen/winner")
	if winner_label:
		winner_label.text = ""

	var result_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN")
	if result_screen:
		result_screen.visible = false

	var final_score_screen = get_node_or_null("VBoxContainer/RESULT_SCREEN/FINAL_SCORE/score_screen")
	if final_score_screen:
		var new_score_v1 = final_score_screen.get_node_or_null("new_score_v")
		var new_score_v2 = final_score_screen.get_node_or_null("new_score_v2")
		var new_score_v3 = final_score_screen.get_node_or_null("new_score_v3")
		if new_score_v1:
			new_score_v1.text = "0"
		if new_score_v2:
			new_score_v2.text = "0"
		if new_score_v3:
			new_score_v3.text = "0"

	var okay_button = get_node_or_null("VBoxContainer/Button")
	if okay_button:
		okay_button.visible = false


func _on_okay_button_pressed() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var tween = get_tree().create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position:y", viewport_size.y, 0.6)
	await tween.finished
	visible = false
	get_tree().reload_current_scene()
