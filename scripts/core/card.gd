extends Node2D

signal hovered
signal hovered_off

var position_in_hand
var suit: String = ""  # Card suit (Draw, Swap, PeekHand, PeekDeck)
var value = 0  # Card point value for scoring
var owner_hand: Node = null  # Which hand owns this card (player_hand or opp_hand)
var locked: bool = false  # Whether this card is locked and cannot be played
var description: String = ""  # Card description text
var _hover_timer: float = 0.0  # Timer for hover duration
var _is_currently_hovered: bool = false  # Whether card is currently hovered
var _hover_timer_active: bool = false  # Whether timer is counting

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_to_group("cards")
	# Ensure the locked overlay does not intercept mouse/hover input
	if has_node("Frame/locked") and "mouse_filter" in get_node("Frame/locked"):
		get_node("Frame/locked").mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_locked_visual()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# Track hover timer if hovering
	if _is_currently_hovered and _hover_timer_active:
		_hover_timer += _delta
		if _hover_timer >= 1.0:
			_show_card_description()
			_hover_timer_active = false



func _on_area_2d_mouse_exited() -> void:
	_is_currently_hovered = false
	_hover_timer = 0.0
	_hover_timer_active = false
	emit_signal("hovered_off", self)
	# Hide description when unhovered
	var game_panel = get_tree().get_current_scene().get_node_or_null("GamePanel")
	if game_panel:
		var desc_label = game_panel.get_node_or_null("card_desc_screen/card_description")
		if desc_label:
			desc_label.visible = false
			desc_label.text = ""


func _on_area_2d_mouse_entered() -> void:
	_is_currently_hovered = true
	_hover_timer = 0.0
	# Only show face-up cards' descriptions
	if has_node("Frame/front") and get_node("Frame/front").visible:
		_hover_timer_active = true
	emit_signal("hovered", self)


func _on_area_2d_input_event(_viewport, event, _shape_idx) -> void:
	# Handle touch input from the Area2D so mobile devices can trigger hover-like feedback.
	# InputEventScreenTouch: pressed -> hovered, released -> hovered_off
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_currently_hovered = true
			_hover_timer = 0.0
			# Only show face-up cards' descriptions
			if has_node("Frame/front") and get_node("Frame/front").visible:
				_hover_timer_active = true
			emit_signal("hovered", self)
		else:
			_is_currently_hovered = false
			_hover_timer = 0.0
			_hover_timer_active = false
			emit_signal("hovered_off", self)
			# Hide description when unhovered
			var game_panel = get_tree().get_current_scene().get_node_or_null("GamePanel")
			if game_panel:
				var desc_label = game_panel.get_node_or_null("card_desc_screen/card_description")
				if desc_label:
					desc_label.visible = false
					desc_label.text = ""
	# Also handle mouse button events routed through the Area2D to avoid missing clicks
	elif event is InputEventMouseButton:
		# For mouse press/release, keep existing behavior (emit hover on press, off on release)
		if event.pressed:
			emit_signal("hovered", self)
		else:
			emit_signal("hovered_off", self)


func flip_to_front(duration: float = 0.2) -> void:
	# Simple flip animation: scale X to 0, swap front/back, scale X back to original.
	# Only run if front/back frames exist.
	if not (has_node("Frame/back") and has_node("Frame/front")):
		return
	var back = get_node("Frame/back")
	var front = get_node("Frame/front")
	# If front already visible, nothing to do
	if front.visible:
		return
	# Check if node is in the scene tree
	if not is_inside_tree():
		# If not in tree, just swap visibility without animation
		back.visible = false
		front.visible = true
		update_locked_visual()
		return
	var old_scale = scale
	var half = max(0.01, duration / 2.0)
	# First half: squash X to 0
	var t = get_tree().create_tween()
	t.tween_property(self, "scale", Vector2(0, old_scale.y), half)
	# Wait until finished
	await t.finished
	# Swap visibility
	back.visible = false
	front.visible = true
	# Update locked visibility when flipping to front
	update_locked_visual()
	# Check again if still in tree before second tween
	if not is_inside_tree():
		return
	# Second half: restore scale
	var t2 = get_tree().create_tween()
	t2.tween_property(self, "scale", old_scale, half)
	# do not await here; let it play out while callers continue

func flip_to_back(duration: float = 0.2) -> void:
	# Simple flip animation: scale X to 0, swap front/back, scale X back to original.
	# Only run if front/back frames exist.
	if not (has_node("Frame/back") and has_node("Frame/front")):
		return
	var back = get_node("Frame/back")
	var front = get_node("Frame/front")
	# If back already visible, nothing to do
	if back.visible:
		return
	var old_scale = scale
	var half = max(0.01, duration / 2.0)
	# First half: squash X to 0
	var t = get_tree().create_tween()
	t.tween_property(self, "scale", Vector2(0, old_scale.y), half)
	# Wait until finished
	await t.finished
	# Swap visibility
	front.visible = false
	back.visible = true
	# Hide locked overlay when flipping to back
	if has_node("Frame/locked"):
		get_node("Frame/locked").visible = false
	# Second half: restore scale
	var t2 = get_tree().create_tween()
	t2.tween_property(self, "scale", old_scale, half)
	# do not await here; let it play out while callers continue

func update_locked_visual() -> void:
	"""Show/hide locked overlay based on locked state"""
	if not has_node("Frame/locked"):
		return
	
	var locked_node = get_node("Frame/locked")
	# Only show locked overlay if the card is locked AND front is visible
	var front_visible = false
	if has_node("Frame/front"):
		front_visible = get_node("Frame/front").visible
	
	locked_node.visible = locked and front_visible

func set_locked(is_locked: bool, card_colors: Dictionary = {}) -> void:
	"""Lock or unlock this card"""
	locked = is_locked
	update_locked_visual()
	
	# Update lock shader colors to match card
	if locked and card_colors and has_node("Frame/locked/Lock"):
		var lock_sprite = get_node("Frame/locked/Lock")
		if lock_sprite.material:
			# Duplicate the material to make it unique for this card instance
			lock_sprite.material = lock_sprite.material.duplicate()
			
			if "color_a" in card_colors:
				lock_sprite.material.set_shader_parameter("color_a", Color(card_colors["color_a"][0], card_colors["color_a"][1], card_colors["color_a"][2], card_colors["color_a"][3]))
			if "color_b" in card_colors:
				lock_sprite.material.set_shader_parameter("color_b", Color(card_colors["color_b"][0], card_colors["color_b"][1], card_colors["color_b"][2], card_colors["color_b"][3]))
			if "color_c" in card_colors:
				lock_sprite.material.set_shader_parameter("color_c", Color(card_colors["color_c"][0], card_colors["color_c"][1], card_colors["color_c"][2], card_colors["color_c"][3]))


func _show_card_description() -> void:
	"""Display card description in game panel with typing animation"""
	if description == "":
		return
	
	var game_panel = get_tree().get_current_scene().get_node_or_null("GamePanel")
	if not game_panel:
		return
	
	var desc_label = game_panel.get_node_or_null("card_desc_screen/card_description")
	if not desc_label:
		return
	
	# Show the label and make it visible
	desc_label.visible = true
	desc_label.text = ""
	
	# Typing animation: reveal text character by character (quick and snappy)
	for i in range(description.length()):
		desc_label.text = description.substr(0, i + 1)
		SoundManager.play_typing()
		await get_tree().create_timer(0.02).timeout  # 20ms per character for snappy feel
	
	# If hover ended before typing finished, hide it
	if not _is_currently_hovered:
		desc_label.visible = false
		desc_label.text = ""
