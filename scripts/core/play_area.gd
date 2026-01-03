extends Node2D

var card_in_slot = false

func _ready() -> void:
	# Connect Area2D body_entered so cards dropped into the play area trigger effects.
	if has_node("Guide/Area2D"):
		var area = $Guide/Area2D
		# Listen for both body_entered (PhysicsBody2D) and area_entered (Area2D) so cards
		# implemented with either type will be detected.
		area.connect("body_entered", Callable(self, "_on_area_body_entered"))
		area.connect("area_entered", Callable(self, "_on_area_body_entered"))
	else:
		pass


func _on_area_body_entered(body: Node) -> void:
	# Strict behavior: only read the `suit` property from the incoming node.
	if body == null:
		return

	# The Area2D signal may pass an Area2D child of the card; walk up the
	# parent chain to find the card node that exposes the `suit` property.
	var suit: String = ""
	var card_node: Node = null
	var probe: Node = body
	while probe != null:
		if probe.has_method("get"):
			var maybe = probe.get("suit")
			if maybe != null:
				suit = str(maybe)
				card_node = probe
				break
		probe = probe.get_parent()

	if suit == "":
		return
	
	# Check whose turn it is - only allow player cards during player's turn
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		var current_turn = gm.get("current_turn_player")
		var owner_hand = card_node.get("owner_hand") if card_node else null
		
		# If it's the opponent's turn and this is a player card, reject it
		if current_turn == 1 and owner_hand and owner_hand.name == "player_hand":
			if owner_hand.has_method("add_card_to_hand"):
				owner_hand.add_card_to_hand(card_node, 0.15)
			return
		
		# If it's the player's turn and this is an opponent card, reject it
		if current_turn == 0 and owner_hand and owner_hand.name == "opp_hand":
			if owner_hand.has_method("add_card_to_hand"):
				owner_hand.add_card_to_hand(card_node, 0.15)
			return
	
	# Check if card is locked - reject locked cards
	if card_node and "locked" in card_node and card_node.locked:
		# Return card to owner's hand if it was dragged
		if card_node and "owner_hand" in card_node and card_node.owner_hand:
			var hand_owner = card_node.owner_hand
			if hand_owner.has_method("add_card_to_hand"):
				hand_owner.add_card_to_hand(card_node, 0.15)
		return
	var em = get_node_or_null("/root/EffectsManager")
	if em == null:
		return
	if not em.has_method("run_suit"):
		return
	em.run_suit(suit, card_node if card_node != null else body)


func clear_play_area() -> void:
	"""Remove all cards currently sitting in the play area."""
	for child in get_children():
		if child.is_in_group("cards"):
			child.queue_free()
	card_in_slot = false