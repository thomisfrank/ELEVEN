extends Node2D

var player_deck = []
const CARD_DRAW_SPEED = .15

# Configuration for visual stacking (don't render all cards)
var max_visual_cards: int = 32  # Don't render all cards, just the top N
var thickness: float = 4.5     # Lower = flatter stack
var x_tilt: float = 1.8       # Horizontal tilt per visual index
var hand_count = 4 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Load the deck composition from JSON and instantiate card scenes
	_load_deck_from_json()
	# Shuffle the deck once after loading so draw order is randomized at game start
	shuffle_deck()
	$CardCount.text = str(player_deck.size())
	$CardCount.visible = true


func draw_card(target_hand: Node = null, face_up: bool = true, interactive: bool = true):
	# Draw the top card from the deck and return it. If the deck is empty,
	# make the deck uninteractable/visually empty and return null.
	if player_deck.size() == 0:
		# Disable collisions so deck is not interactable
		if has_node("Area2D/CollisionShape2D"):
			$Area2D/CollisionShape2D.disabled = true
		# Optionally hide the reference rect so the deck looks empty
		if has_node("ReferenceRect"):
			$ReferenceRect.visible = false
		return null

	# Remove and return the top card (index 0)
	var card_drawn = player_deck[0]
	player_deck.remove_at(0)

	# If the card was a visible child of the deck, detach it so callers
	# can reparent it (e.g. add to hand or CardManager). Don't free it here.
	if card_drawn is Node and card_drawn.get_parent() == self:
		remove_child(card_drawn)

	# After removing, if the deck is now empty update visuals/collision
	if player_deck.size() == 0:
		if has_node("Area2D/CollisionShape2D"):
			$Area2D/CollisionShape2D.disabled = true
		if has_node("ReferenceRect"):
			$ReferenceRect.visible = false
			$CardCount.visible = false

	$CardCount.text = str(player_deck.size())
	if card_drawn is Node:
		# Prefer the autoload CardManager if available, otherwise find in the scene
		var cm = get_node_or_null("/root/CardManager")
		if not cm:
			cm = get_tree().get_root().get_node_or_null("CardManager")
		if cm:
			# Place the card at the deck's global position so it appears to come from the deck
			card_drawn.global_position = self.global_position
			cm.add_child(card_drawn)
			# Temporarily raise the card above other items while it animates into the hand
			_temporarily_raise_card(card_drawn, CARD_DRAW_SPEED, 1000)
			card_drawn.name = "Card"
			card_drawn.scale = Vector2(.5, .5)
			# Set interaction for the card being moved to hand according to caller preference
			if card_drawn.has_node("Area2D/CollisionShape2D"):
				card_drawn.get_node("Area2D/CollisionShape2D").disabled = not interactive
			if card_drawn.has_node("Area2D"):
				card_drawn.get_node("Area2D").monitoring = interactive

			# Add to the requested hand (if provided) or the default player hand.
			var ph: Node = null
			if target_hand != null:
				ph = target_hand
			else:
				ph = get_node_or_null("../player_hand")
			if ph:
				var added = ph.add_card_to_hand(card_drawn, CARD_DRAW_SPEED)
				if not added:
					# Hand rejected the card (likely full). Revert the move: put card back into logical deck
					# Remove from current parent (CardManager) before adding to deck
					if card_drawn.get_parent():
						card_drawn.get_parent().remove_child(card_drawn)
					# Reparent back to the deck so visuals/stack remain consistent and position it at the deck
					card_drawn.global_position = self.global_position
					add_child(card_drawn)
					# Put it back at the top of the logical deck
					player_deck.insert(0, card_drawn)
					# Restore deck visual state on the card (show back, hide front, disable its Area2D)
					if card_drawn.has_node("Frame/back"):
						card_drawn.get_node("Frame/back").visible = true
					if card_drawn.has_node("Frame/front"):
						card_drawn.get_node("Frame/front").visible = false
					if card_drawn.has_node("Area2D/CollisionShape2D"):
						card_drawn.get_node("Area2D/CollisionShape2D").disabled = true
					if card_drawn.has_node("Area2D"):
						card_drawn.get_node("Area2D").monitoring = false
				else:
					# Hand accepted the card; flip it while it moves into position
					# Only flip to front when requested (opponent hands stay face-down)
					if face_up and card_drawn.has_method("flip_to_front"):
						card_drawn.flip_to_front(CARD_DRAW_SPEED)

	return card_drawn

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass




func _load_deck_from_json() -> void:
	var deck_file_path: String = "res://scripts/CardData/deck.json"
	var file := FileAccess.open(deck_file_path, FileAccess.ModeFlags.READ)
	if file == null:
		push_error("deck.gd: Unable to open %s" % deck_file_path)
		return
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	var deck_array: Array = []
	# JSON.parse_string may return the parsed value directly (Array/Dictionary)
	# or a parser-result dictionary with keys 'error' and 'result'. Handle both.
	if parsed is Array:
		deck_array = parsed
	elif parsed is Dictionary:
		# If this looks like a parser result, use result+error; otherwise assume it's the actual JSON object
		if parsed.has("error") and parsed.has("result"):
			if parsed.get("error", OK) != OK:
				push_error("deck.gd: JSON parse error: %s" % parsed.get("error_string", "unknown"))
				return
			deck_array = parsed.get("result", [])
		else:
			# Unexpected: deck.json should be an array, but we got an object
			push_error("deck.gd: deck.json root must be an array")
			return
	else:
		push_error("deck.gd: failed to parse deck.json")
		return

	# Preload the card scene used for instancing
	var card_scene := preload("res://scenes/core/card.tscn")

	# mapping suits to code textures
	var code_map := {
		"Draw": "res://assets/codes/draw_code.png",
		"Swap": "res://assets/codes/swap_code.png",
		"PeekHand": "res://assets/codes/peek_hand_code.png",
		"PeekDeck": "res://assets/codes/peek_deck_code.png"
	}

	var deck_size: int = deck_array.size()
	for i in range(deck_size):
		var card_name = deck_array[i]
		var card_json_path: String = "res://scripts/CardData/%s.json" % card_name
		var data = _load_card_json(card_json_path)
		if data == null:
			continue

		# instantiate the card scene and apply data (we keep the instance in player_deck)
		var card_instance = card_scene.instantiate()
		card_instance.name = data.get("name", card_name)

		# Ensure the runtime card node exposes its suit so other systems can read it via get("suit").
		# The JSON contains a 'suit' field; store it on the instance for strict lookups.
		_apply_card_data_to_instance(card_instance, data, code_map)
		if data.has("suit"):
			card_instance.set("suit", str(data.get("suit")))
		else:
			# Fallback: use the card name (e.g., "Draw_2") to preserve compatibility.
			card_instance.set("suit", str(card_name))

		player_deck.append(card_instance)

		# Only render the top N cards to simulate stack height and avoid rendering all cards
		if i > deck_size - max_visual_cards:
			var visual_index: int = i - (deck_size - max_visual_cards)

			# 1. Use negative Y to stack UPWARD
			# 2. Use the configured thickness to flatten or spread the stack
			var y_offset: float = -sqrt(float(visual_index)) * thickness
			var x_offset: float = visual_index * x_tilt

			card_instance.position = Vector2(x_offset, y_offset)
			card_instance.z_index = i

			# Add visible card to scene tree so it renders
			add_child(card_instance)

			# By default we want the deck to show the backs of cards.
			if card_instance.has_node("Frame/back"):
				card_instance.get_node("Frame/back").visible = true
			if card_instance.has_node("Frame/front"):
				card_instance.get_node("Frame/front").visible = false

			# Disable Area2D so cards in the deck don't respond to input
			if card_instance.has_node("Area2D/CollisionShape2D"):
				card_instance.get_node("Area2D/CollisionShape2D").disabled = true
			if card_instance.has_node("Area2D"):
				var area = card_instance.get_node("Area2D")
				# turn off area monitoring so it won't detect overlaps or input
				area.monitoring = false
		else:
			# Non-visual cards remain in `player_deck` but are not added to the scene tree.
			# This keeps memory/state but avoids rendering many nodes.
			pass


func shuffle_deck() -> void:
	# Shuffle the logical deck using a RandomNumberGenerator (Fisher–Yates)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := player_deck.size()
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		# swap i and j
		var tmp = player_deck[i]
		player_deck[i] = player_deck[j]
		player_deck[j] = tmp

	$CardCount.text = str(player_deck.size())

	# Remove any existing card children (we'll re-add the top visual cards)
	var to_remove := []
	for c in get_children():
		if c and c.is_in_group("cards"):
			to_remove.append(c)
	for c in to_remove:
		remove_child(c)

	# Re-add the top N visual cards and apply the same visual/state setup used in load
	var deck_size: int = player_deck.size()
	for i in range(deck_size):
		if i > deck_size - max_visual_cards:
			var visual_index: int = i - (deck_size - max_visual_cards)
			var card_instance = player_deck[i]
			# position and z_index similar to _load_deck_from_json
			var y_offset: float = -sqrt(float(visual_index)) * thickness
			var x_offset: float = visual_index * x_tilt
			card_instance.position = Vector2(x_offset, y_offset)
			card_instance.z_index = i
			add_child(card_instance)
			# Ensure back/front visibility and disable interaction as deck visuals expect
			if card_instance.has_node("Frame/back"):
				card_instance.get_node("Frame/back").visible = true
			if card_instance.has_node("Frame/front"):
				card_instance.get_node("Frame/front").visible = false
			if card_instance.has_node("Area2D/CollisionShape2D"):
				card_instance.get_node("Area2D/CollisionShape2D").disabled = true
			if card_instance.has_node("Area2D"):
				card_instance.get_node("Area2D").monitoring = false



func _load_card_json(path: String):
	# returns parsed JSON dictionary or null
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.ModeFlags.READ)
	if f == null:
		return null
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	# parsed may be the raw Dictionary/Array or a parser-result dict
	if parsed is Dictionary:
		# If this looks like a parser result (error/result), handle it
		if parsed.has("error") and parsed.has("result"):
			if parsed.get("error", OK) != OK:
				return null
			return parsed.get("result")
		# Otherwise it's the actual parsed JSON object
		return parsed
	elif parsed is Array:
		return parsed
	else:
		return null



func _apply_card_data_to_instance(card_node: Node, data: Dictionary, code_map: Dictionary) -> void:
	# Set title (use the suit if available)
	var title_node = card_node.get_node("Frame/front/card info/Title") if card_node.has_node("Frame/front/card info/Title") else null
	if title_node:
		title_node.text = str(data.get("suit", data.get("name", "")))

	# Set value label
	var value_node_path := "Frame/front/card info/HOLDER/decorative 2/Value"
	if card_node.has_node(value_node_path):
		var v = card_node.get_node(value_node_path)
		v.text = str(data.get("value", ""))
	
	# Store value as a property on the card node for score calculation
	if data.has("value"):
		card_node.set("value", data.get("value"))

	# Set icon texture (front). Try card_icons first, then background_icons
	var icon_fname: String = str(data.get("icon_path", ""))
	var icon_path1: String = "res://assets/icons/card_icons/%s" % icon_fname
	var icon_path2: String = "res://assets/icons/background_icons/%s" % icon_fname
	var chosen_icon_path: String = ""
	if FileAccess.file_exists(icon_path1):
		chosen_icon_path = icon_path1
	elif FileAccess.file_exists(icon_path2):
		chosen_icon_path = icon_path2
	if chosen_icon_path != "" and card_node.has_node("Frame/front/Icon"):
		var icon_node = card_node.get_node("Frame/front/Icon")
		icon_node.texture = load(chosen_icon_path)

	# Always set the back icon to the common logo (do not use suit icon on the back)
	var back_logo_path: String = "res://assets/icons/background_icons/logo.png"
	if card_node.has_node("Frame/back/Icon"):
		var back_icon = card_node.get_node("Frame/back/Icon")
		back_icon.texture = load(back_logo_path)

	# By default, show the back of the card and hide the front so non-visual
	# (not-yet-added) instances start face-down and will visibly flip when drawn.
	if card_node.has_node("Frame/back"):
		card_node.get_node("Frame/back").visible = true
	if card_node.has_node("Frame/front"):
		card_node.get_node("Frame/front").visible = false

	# Set code texture according to suit
	var suit: String = str(data.get("suit", "Draw"))
	var code_path: String = str(code_map.get(suit, code_map.get("Draw")))
	if card_node.has_node("Frame/front/Code") and code_path != "":
		var code_node = card_node.get_node("Frame/front/Code")
		code_node.texture = load(code_path)

	# Store the description from card data for hover tooltips
	if data.has("description"):
		card_node.description = str(data.get("description", ""))

	# Apply shader colors to the front of the card only so the back remains generic
	var ca = data.get("color_a", null)
	var cb = data.get("color_b", null)
	var cc = data.get("color_c", null)
	if ca != null and cb != null and cc != null:
		var color_a: Color = Color(ca[0], ca[1], ca[2], ca[3])
		var color_b: Color = Color(cb[0], cb[1], cb[2], cb[3])
		var color_c: Color = Color(cc[0], cc[1], cc[2], cc[3])
		# Prefer applying only to the front subtree so the back keeps the default shader colors
		if card_node.has_node("Frame/front"):
			_apply_colors_recursive(card_node.get_node("Frame/front"), color_a, color_b, color_c)
		else:
			_apply_colors_recursive(card_node, color_a, color_b, color_c)


func _apply_colors_recursive(node: Node, color_a: Color, color_b: Color, color_c: Color) -> void:
	# If node is a CanvasItem (Sprite2D, ColorRect, Label, Panel, etc.) it may have a 'material' property
	if node is CanvasItem:
		# Access the material property if present
		if "material" in node:
			var mat = node.material
			if mat and mat is ShaderMaterial:
				# duplicate material so we don't modify the shared instance
				var new_mat = mat.duplicate()
				node.material = new_mat
				new_mat.set_shader_parameter("color_a", color_a)
				new_mat.set_shader_parameter("color_b", color_b)
				new_mat.set_shader_parameter("color_c", color_c)

	# Recurse into children
	for child in node.get_children():
		_apply_colors_recursive(child, color_a, color_b, color_c)


func _temporarily_raise_card(card_node: CanvasItem, duration: float, temp_z: int = 1000) -> void:
	# Make the card render above other items while animating, then restore original values.
	if not card_node:
		return
	if not (card_node is CanvasItem):
		return
	# Save previous values
	var old_z: int = card_node.z_index
	var old_rel: bool = card_node.z_as_relative
	# Apply temporary raise
	card_node.z_as_relative = false
	card_node.z_index = temp_z
	# Wait for the duration, then restore if the node still exists
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(card_node):
		return
	card_node.z_index = old_z
	card_node.z_as_relative = old_rel
