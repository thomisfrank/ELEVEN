extends Panel

@export var is_player_panel: bool = true

const PLAYER := 0
const OPP := 1

var actions_per_turn: int = 2
var actions_left: int = 0

var _attr: Label
var _actions: Array

func _ready() -> void:
	_attr = get_node_or_null("Attribution")
	_actions = [
		get_node_or_null("Action 1"),
		get_node_or_null("Action 2")
	]

	if _attr:
		_attr.text = "Player" if is_player_panel else "Opponent"

	_set_actions(0)

	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.connect("turn_started", Callable(self, "_on_turn_started"))
		gm.connect("action_performed", Callable(self, "_on_action_performed"))
		gm.connect("turn_ended", Callable(self, "_on_turn_ended"))

func _set_actions(count_on: int) -> void:
	actions_left = count_on
	for i in range(_actions.size()):
		var panel = _actions[i]
		if panel == null:
			continue
		var on_node = panel.get_node_or_null("screen _on")
		var off_node = panel.get_node_or_null("screen _off")
		var on_visible = i < count_on
		if on_node:
			on_node.visible = on_visible
		if off_node:
			off_node.visible = not on_visible

func _on_turn_started(player: int) -> void:
	var my_side = PLAYER if is_player_panel else OPP
	if player == my_side:
		_set_actions(actions_per_turn)
	else:
		_set_actions(0)

func _on_action_performed(player: int, actions_left_signal: int) -> void:
	var my_side = PLAYER if is_player_panel else OPP
	if player == my_side:
		_set_actions(max(actions_left_signal, 0))

func _on_turn_ended(player: int) -> void:
	var my_side = PLAYER if is_player_panel else OPP
	if player == my_side:
		_set_actions(0)


func update_score(score: int) -> void:
	"""Update the score display with the given score value"""
	var score_screen = get_node_or_null("Score screen")
	if not score_screen:
		return
	
	var value_01 = score_screen.get_node_or_null("value 01")
	var value_02 = score_screen.get_node_or_null("value 02")
	var value_03 = score_screen.get_node_or_null("value 03")
	
	if value_01 and value_02 and value_03:
		var score_str = str(score).pad_zeros(3)  # Ensure 3 digits
		value_01.text = score_str[0]
		value_02.text = score_str[1]
		value_03.text = score_str[2]
		SoundManager.play_point_beep()
