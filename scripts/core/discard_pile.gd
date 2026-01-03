extends Node2D

signal card_snapped(card)

var card_in_slot = false

# Accept a card node and snap it into the discard pile immediately.
# This is intentionally simple: callers should invoke `accept_card(card)`
# when they want the card moved into the pile. The card is re-parented
# under the DiscardPile node and positioned to the Area2D guide.
func accept_card(card: Node) -> void:
	if card == null:
		return

	# Calculate target position BEFORE reparenting (using global coords)
	var target_global_pos = Vector2.ZERO
	if has_node("Guide/Area2D"):
		target_global_pos = get_node("Guide/Area2D").global_position
	elif has_node("Guide"):
		target_global_pos = get_node("Guide").global_position
	else:
		target_global_pos = global_position

	# If the card already belongs to this node, just snap its position.
	var was_parent = card.get_parent()
	if was_parent and was_parent != self:
		was_parent.remove_child(card)

	# Reparent to this discard pile so its local position is predictable.
	add_child(card)
	
	# Make sure card is visible
	card.visible = true

	# Unlock cards once they hit discard so they can be reused later.
	if card.has_method("set_locked"):
		card.set_locked(false)
	elif "locked" in card:
		card.locked = false
		if card.has_method("update_locked_visual"):
			card.update_locked_visual()
	
	# Now convert the global target position to local position
	card.global_position = target_global_pos

	# Set scale to 1.0 so parent's 0.5 scale renders cards at correct size
	card.scale = Vector2(1.0, 1.0)

	# Randomize rotation between -6 and 6 degrees for a loose stack look.
	# Use global helper functions available in this project runtime.
	card.rotation = deg_to_rad(randf_range(-6.0, 6.0))
	# Place newer cards on top visually (z_index increases) if the card is a Node2D.
	if card is Node2D:
		card.z_index = get_child_count()

	card_in_slot = true
	emit_signal("card_snapped", card)
	print("[DISCARD_PILE] Accepted card: ", card.name, " at position: ", card.global_position, " z_index: ", card.z_index)


func clear_pile() -> void:
	# Remove all card children (use queue_free to free memory). Keeps Guide and Area2D intact.
	var to_remove = []
	for c in get_children():
		# keep nodes that are part of the discard pile scene structure
		if c.name == "Guide":
			continue
		if c.name == "Area2D":
			continue
		# skip collision/collisionshape nodes that are under Guide
		if c is Node and c.get_owner() == self:
			to_remove.append(c)

	for r in to_remove:
		r.queue_free()

	card_in_slot = false
