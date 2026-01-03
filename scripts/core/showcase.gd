extends Node2D

signal control_button_pressed(effect_type: String)
signal cancel_button_pressed()

@onready var control_button = $BG/buttons/ControlButton
@onready var cancel_button = $BG/buttons/CancelButton
@onready var separator = $BG/buttons/HSeparator
@onready var reference_rect = $BG/ReferenceRect
@onready var bg = $BG

var current_effect_type: String = ""

func _ready() -> void:
	# Hide by default
	visible = false

	# Ensure showcase renders above all other canvas items
	# Disable relative z and set a very high absolute z-index
	z_as_relative = false
	z_index = 4096
	if bg is CanvasItem:
		bg.z_as_relative = false
		bg.z_index = 4096
	if control_button is CanvasItem:
		control_button.z_as_relative = false
		control_button.z_index = 4096
	if cancel_button is CanvasItem:
		cancel_button.z_as_relative = false
		cancel_button.z_index = 4096
	if separator is CanvasItem:
		separator.z_as_relative = false
		separator.z_index = 4096
	if reference_rect is CanvasItem:
		reference_rect.z_as_relative = false
		reference_rect.z_index = 4096
	
	# Connect button signals
	control_button.pressed.connect(_on_control_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)

# Configure showcase for different effect types
func show_for_effect(effect_type: String) -> void:
	visible = true
	current_effect_type = effect_type

	
	match effect_type:
		"Swap":
			control_button.text = "OKAY"
			control_button.visible = true
			cancel_button.visible = false
			separator.visible = false  # Hide separator when only one button
		
		"PeekDeck":
			control_button.text = "DRAW"
			control_button.visible = true
			cancel_button.visible = true
			separator.visible = true  # Show separator between buttons
		
		"PeekHand":
			control_button.text = "SWAP"
			control_button.visible = true
			cancel_button.visible = true
			separator.visible = true  # Show separator between buttons

func hide_showcase() -> void:
	visible = false
	current_effect_type = ""
	# Clear any displayed cards
	for child in reference_rect.get_children():
		child.queue_free()

func _on_control_button_pressed() -> void:
	control_button_pressed.emit(current_effect_type)

func _on_cancel_button_pressed() -> void:
	cancel_button_pressed.emit()
