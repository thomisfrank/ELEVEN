extends Node2D

@export var main_scene_path: String = "res://scenes/game/main.tscn"

@onready var play_button: Button = $PlayButton


func _ready() -> void:
	if play_button:
		play_button.pressed.connect(_on_play_pressed)


func _on_play_pressed() -> void:
	if main_scene_path != "":
		get_tree().change_scene_to_file(main_scene_path)
