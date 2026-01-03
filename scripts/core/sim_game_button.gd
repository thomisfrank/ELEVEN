extends Button

@export var debug_round_count: int = 7
@export var debug_winner_text: String = "YOU"
@export var debug_winning_score: int = 18
@export var use_deck_cards: bool = true
@export var cards_to_show: int = 4


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	var root = get_tree().get_current_scene()
	if not root:
		return

	var end_round_panel = root.get_node_or_null("END_ROUND_PANEL")
	if end_round_panel:
		end_round_panel.visible = false

	var end_game_panel = root.get_node_or_null("EndGamePanel")
	if not end_game_panel or not end_game_panel.has_method("show_end_game_screen"):
		return

	var round_count = debug_round_count
	var gm = get_node_or_null("/root/GameManager")
	if gm and "current_round" in gm and gm.current_round > 0:
		round_count = gm.current_round

	var cards: Array = []
	if use_deck_cards:
		var deck = root.get_node_or_null("Deck")
		if deck and "player_deck" in deck:
			for i in range(min(cards_to_show, deck.player_deck.size())):
				cards.append(deck.player_deck[i])

	end_game_panel.show_end_game_screen(round_count, debug_winner_text, debug_winning_score, cards)
