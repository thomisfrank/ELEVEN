extends Control

func _ready() -> void:
	var btn = get_node_or_null("PassButton")
	if btn:
		btn.connect("pressed", Callable(self, "_on_pass_pressed"))

func _on_pass_pressed() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("pass_turn"):
		await gm.pass_turn()
