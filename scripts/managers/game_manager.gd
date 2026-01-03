extends Node


# Players
const PLAYER := 0
const OPP := 1

# Track which player will go first this round. -1 means not yet decided.
var first_player: int = -1

# The winner of the last round. If set to PLAYER or OPP, the next round
# will let that same side go first.
var last_round_winner: int = -1

# Round counter for display
var current_round: int = 0
var game_over: bool = false

# Optional signal to notify other systems when a round starts and who goes first.
signal round_started(first_player)

# Turn/Action configuration
const ACTIONS_PER_TURN := 2

# Current turn state
var current_turn_player: int = -1
var actions_left: int = 0
var turns_taken_in_round: int = 0

# Turn and round signals
@warning_ignore("unused_signal")
signal turn_started(player)
signal action_performed(player, actions_left)
signal turn_ended(player)
signal round_ended()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Decide who goes first for the initial round (random) or use the
	# last round winner if that has been set by other game logic.
	round_managment()


func round_managment() -> void:
	# Check if there are enough cards left in the deck for another round
	# Skip this check on the first round (current_round == 0) since deck isn't loaded yet
	var root_scene = get_tree().get_current_scene()
	
	if current_round > 0:
		if root_scene:
			var deck_node = root_scene.get_node_or_null("Deck")
			if deck_node and deck_node.has_method("get") and "player_deck" in deck_node:
				var deck_size = deck_node.player_deck.size()
				print("[GAME_MANAGER] Cards remaining in deck: ", deck_size)
				
				# If 11 or fewer cards remain, end the game instead of starting a new round
				if deck_size <= 11:
					print("[GAME_MANAGER] Not enough cards for another round. Ending game.")
				end_game()
	# Increment round counter
	current_round += 1
	
	# If a last round winner exists, they go first this round.
	if last_round_winner == PLAYER or last_round_winner == OPP:
		first_player = last_round_winner
	else:
		# At game start choose randomly between PLAYER and OPP.
		randomize()
		first_player = int(randi() % 2)

	# Notify other nodes that a round has started and who goes first.

	# Give the scene a short moment to finish initializing so hand/deck nodes exist.
	# This avoids race conditions without adding fallbacks.
	await get_tree().create_timer(0.05).timeout

	# Animate round number with sound
	var game_panel = get_tree().get_current_scene().get_node_or_null("GamePanel")
	var sound_manager = get_tree().get_first_node_in_group("sound_manager")
	if sound_manager and sound_manager.has_method("play_turn_change"):
		sound_manager.play_turn_change()
	if game_panel and game_panel.has_method("set_round_number"):
		await game_panel.set_round_number(current_round)
	elif game_panel and game_panel.has_method("animate_text"):
		await game_panel.animate_text("Round %d" % current_round, 2.0)

	# Notify other nodes that a round has started and who goes first.
	emit_signal("round_started", first_player)
	# At the start of the round, draw initial hands for both players.
	# Attempt to find the scene's Deck and hand nodes and draw `hand_count` cards each.
	if root_scene:
		var deck_node = root_scene.get_node_or_null("Deck")
		var player_hand_node = root_scene.get_node_or_null("player_hand")
		var opp_hand_node = root_scene.get_node_or_null("opp_hand")
		if deck_node and player_hand_node and opp_hand_node:
			# Determine how many cards to draw. Deck exposes `hand_count` as a config.
			var draw_count = 4
			# Safely attempt to read `hand_count` from the deck node. Use `get()` so
			# we don't call methods that may not exist on the script/resource object.
			if deck_node:
				var maybe_count = null
				# `get` will return the value or null if the property doesn't exist
				maybe_count = deck_node.get("hand_count")
				if maybe_count != null:
					draw_count = int(maybe_count)
			# Draw one card per side per iteration so visuals animate cleanly.
			for i in range(draw_count):
				# draw for player (face-up and interactive) then opp (face-down non-interactive)
				deck_node.draw_card(player_hand_node, true, true)
				# small stagger so animations don't fully overlap
				await get_tree().create_timer(0.05).timeout
				deck_node.draw_card(opp_hand_node, false, false)
				await get_tree().create_timer(0.05).timeout


	# Start turn management for this round
	await turn_management(first_player)


func set_last_round_winner(winner: int) -> void:
	# External callers should use this to inform the manager who won the round.
	if winner != PLAYER and winner != OPP:
		push_error("Invalid winner passed to set_last_round_winner: %s" % str(winner))
		return
	last_round_winner = winner


func turn_management(start_player: int) -> void:
	# Initialize round turn tracking and start the first turn
	if start_player != PLAYER and start_player != OPP:
		push_error("turn_management requires a valid start_player")
		return

	turns_taken_in_round = 0
	current_turn_player = start_player
	await start_turn(current_turn_player)


func start_turn(player: int) -> void:
	# Called to begin a player's turn
	actions_left = ACTIONS_PER_TURN
	
	# Get background and game panel
	var background = get_tree().get_first_node_in_group("background")
	var game_panel = get_tree().get_current_scene().get_node_or_null("GamePanel")
	
	# Prepare player name for text
	var player_name = "Player's turn" if player == PLAYER else "Opponent's turn"
	
	# Play sound immediately (not async)
	SoundManager.play_turn_change()
	
	# Set background state immediately (not async, the transition is animated but doesn't block)
	if background:
		if player == PLAYER:
			background.set_background_state(background.BackgroundState.PLAYER_TURN)
		else:
			background.set_background_state(background.BackgroundState.OPP_TURN)
		# Block input
		background.input_blocked = true
		background.block_all_input(true)
	
	# Start text animation
	if game_panel and game_panel.has_method("animate_text"):
		game_panel.animate_text(player_name, 1.5)
	
	# Wait for turn change duration
	await get_tree().create_timer(background.turn_change_duration if background else 3.0).timeout
	
	# Return background to default and unblock input
	if background:
		background.set_background_state(background.BackgroundState.DEFAULT)
		background.input_blocked = false
		background.block_all_input(false)
	
	emit_signal("turn_started", player)


func perform_action() -> bool:
	# Called when the current actor plays a card (consumes one action)
	if current_turn_player != PLAYER and current_turn_player != OPP:
		push_error("No current turn player set")
		return false
	if actions_left <= 0:
		push_error("No actions left this turn")
		return false

	actions_left -= 1
	emit_signal("action_performed", current_turn_player, actions_left)
	# Don't call end_turn here - let the effect finish first
	return true


func check_and_end_turn_if_needed() -> void:
	# Called after a card effect completes to check if turn should end
	if actions_left <= 0:
		end_turn()


func pass_turn() -> void:
	# Passing consumes all remaining actions and ends the turn
	if current_turn_player != PLAYER and current_turn_player != OPP:
		push_error("No current turn player set")
		return

	if actions_left > 0:
		actions_left = 0
		# Optionally emit action_performed to indicate pass; keep simple and end turn.
	
	# Animate the pass message with sound
	var player_name = "Player" if current_turn_player == PLAYER else "Opponent"
	var game_panel = get_tree().get_current_scene().get_node_or_null("GamePanel")
	var sound_manager = get_tree().get_first_node_in_group("sound_manager")
	if sound_manager and sound_manager.has_method("play_pass"):
		sound_manager.play_pass()
	if game_panel and game_panel.has_method("animate_text"):
		await game_panel.animate_text("%s passed!" % player_name, 1.5)
	
	end_turn()


func end_turn() -> void:
	# End the current player's turn. After both players have taken a turn,
	# emit round_ended and stop; otherwise start the other player's turn.
	emit_signal("turn_ended", current_turn_player)
	turns_taken_in_round += 1

	if turns_taken_in_round >= 2:
		# Animate end of round with sound
		var game_panel = get_tree().get_current_scene().get_node_or_null("GamePanel")
		var sound_manager = get_tree().get_first_node_in_group("sound_manager")
		if sound_manager and sound_manager.has_method("play_turn_change"):
			sound_manager.play_turn_change()
		if game_panel and game_panel.has_method("animate_text"):
			await game_panel.animate_text("END ROUND", 2.0)
		
		# Capture current hands before discarding
		var root_scene = get_tree().get_current_scene()
		var player_hand_node = root_scene.get_node_or_null("player_hand")
		var opp_hand_node = root_scene.get_node_or_null("opp_hand")
		
		var player_cards = []
		var opp_cards = []
		
		if player_hand_node and "player_hand" in player_hand_node:
			player_cards = player_hand_node.player_hand.duplicate()
		if opp_hand_node and "opponent_hand" in opp_hand_node:
			opp_cards = opp_hand_node.opponent_hand.duplicate()
		
		# Show the end round panel with captured hand cards
		# The panel will handle discarding when OKAY button is pressed
		var end_round_panel = get_tree().get_current_scene().get_node_or_null("END_ROUND_PANEL")
		if end_round_panel and end_round_panel.has_method("show_end_round_screen"):
			await end_round_panel.show_end_round_screen(player_cards, opp_cards)
		
		# Clear the hands arrays (cards are already moved to discard pile by panel)
		# Also ensure no card nodes remain as children of the hand nodes
		if player_hand_node and "player_hand" in player_hand_node:
			for card in player_hand_node.player_hand:
				if card and card.get_parent() == player_hand_node:
					player_hand_node.remove_child(card)
			player_hand_node.player_hand.clear()
		if opp_hand_node and "opponent_hand" in opp_hand_node:
			for card in opp_hand_node.opponent_hand:
				if card and card.get_parent() == opp_hand_node:
					opp_hand_node.remove_child(card)
			opp_hand_node.opponent_hand.clear()
		
		emit_signal("round_ended")
		
		# Reset turn state
		current_turn_player = -1
		actions_left = 0
		turns_taken_in_round = 0
		
		# Start the next round
		print("[GAME_MANAGER] Starting next round after end round panel")
		await round_managment()
		return

	# Switch to the other player and start their turn
	current_turn_player = PLAYER if current_turn_player == OPP else OPP
	_start_next_turn()


func _start_next_turn() -> void:
	# Helper to start the next turn asynchronously from end_turn
	await start_turn(current_turn_player)


func end_game() -> void:
	"""Called when the game ends (not enough cards for another round)"""
	print("[GAME_MANAGER] Game ending - showing end game panel")
	game_over = true
	
	# Play end game sound
	SoundManager.play_end_game_panel()
	
	# End game panel will be shown by EndRoundPanel; wait for OKAY to restart.


func _fill_hand(_hand_node, _deck):
	# This helper is intentionally a noop now. Kept for compatibility with older calls.
	return


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
