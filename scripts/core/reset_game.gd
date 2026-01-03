extends Button

# Reset game button - reloads the current scene to start fresh

func _ready() -> void:
	connect("pressed", Callable(self, "_on_button_pressed"))

func _on_button_pressed() -> void:
	# Reload the current scene
	get_tree().reload_current_scene()
