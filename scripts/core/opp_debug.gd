extends Button

# Debug button to test opponent playing cards from their hand
# Set the button's text to "Draw" or "Swap" to determine which card to play

func _ready() -> void:
	connect("pressed", Callable(self, "_on_button_pressed"))

func _on_button_pressed() -> void:
	var button_text = text.to_lower()
	
	var opp_ai = get_node_or_null("/root/OppAiMananager")
	if not opp_ai:
		return
	
	# Determine which card type to play based on button text
	if "draw" in button_text:
		if opp_ai.has_method("play_draw_card"):
			opp_ai.play_draw_card()
	elif "swap" in button_text:
		if opp_ai.has_method("play_swap_card"):
			opp_ai.play_swap_card()
	elif "peek deck" in button_text:
		if opp_ai.has_method("play_peek_deck_card"):
			opp_ai.play_peek_deck_card()
	elif "peek hand" in button_text:
		if opp_ai.has_method("play_peek_hand_card"):
			opp_ai.play_peek_hand_card()
	else:
		pass
