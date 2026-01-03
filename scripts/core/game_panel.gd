extends Panel

@onready var card_description = $card_desc_screen/card_description
@export var type_speed: float = 0.02  # Seconds per character

var current_round: int = 0  # Track the current round number


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Initialize deck count display
	_update_deck_count()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_update_deck_count()


func _update_deck_count() -> void:
	# Get the deck node and split the count into individual digits
	var root_scene = get_tree().get_current_scene()
	var deck = root_scene.get_node_or_null("Deck")
	if not deck:
		return
	
	var deck_size = 0
	if deck.has_node("CardCount"):
		var count_label = deck.get_node("CardCount")
		# CardCount is a RichTextLabel
		var count_text = count_label.text
		deck_size = int(count_text) if count_text.is_valid_int() else 0
	
	# Pad to 3 digits (e.g., 52 becomes "052")
	var count_str = str(deck_size).pad_zeros(3)
	
	# Assign each digit to the corresponding label under Labels/deck
	if has_node("Labels/deck/deck_count"):
		get_node("Labels/deck/deck_count").text = count_str[0]
		
	if has_node("Labels/deck/deck_count2"):
		get_node("Labels/deck/deck_count2").text = count_str[1]
		
	if has_node("Labels/deck/deck_count3"):
		get_node("Labels/deck/deck_count3").text = count_str[2]


func animate_text(text: String, hold_time: float = 2.0) -> void:
	"""Animate text with typewriter effect and hold it using the card_description label"""
	if not card_description:
		return
	
	# Clear previous text and show
	card_description.text = ""
	card_description.visible = true
	
	# Typewriter animation
	for i in range(len(text)):
		card_description.text = text.substr(0, i + 1)
		SoundManager.play_typing()
		await get_tree().create_timer(type_speed).timeout
	
	# Hold the text
	await get_tree().create_timer(hold_time).timeout
	
	# Fade out
	var tween = get_tree().create_tween()
	tween.tween_property(card_description, "modulate", Color.TRANSPARENT, 0.5)
	await tween.finished
	
	card_description.modulate = Color.WHITE
	card_description.text = ""
	
	# Type the round number back up
	await show_round_number()


func show_round_number() -> void:
	"""Type up the current round number"""
	if current_round <= 0:
		card_description.visible = false
		return
	
	var round_text = "ROUND %d" % current_round
	card_description.text = ""
	card_description.visible = true
	
	# Typewriter animation for round number
	for i in range(len(round_text)):
		card_description.text = round_text.substr(0, i + 1)
		SoundManager.play_typing()
		await get_tree().create_timer(type_speed).timeout


func set_round_number(round_num: int) -> void:
	"""Update the current round number and display it"""
	current_round = round_num
	await show_round_number()
