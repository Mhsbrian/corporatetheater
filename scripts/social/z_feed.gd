extends Control

# Corporate Theater — Z Feed
# Simulates the Z social media platform (think: X/Twitter).
# CEO and corporate accounts post polished, optimistic content.
# Hidden between the lines are clues the player can discover.

@onready var feed_container: VBoxContainer = $ScrollContainer/FeedContainer
@onready var profile_name: Label = $Header/ProfileName
@onready var follower_count: Label = $Header/FollowerCount

const POST_DATA_PATH := "res://data/posts/z_posts.json"

var _posts: Array = []
var _discovered_clues: Array[String] = []


func _ready() -> void:
	_load_posts()
	_render_feed()


func _load_posts() -> void:
	if not FileAccess.file_exists(POST_DATA_PATH):
		_load_placeholder_posts()
		return

	var file := FileAccess.open(POST_DATA_PATH, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err == OK:
		_posts = json.data
	else:
		_load_placeholder_posts()


func _load_placeholder_posts() -> void:
	_posts = [
		{
			"author": "Maxwell Holt",
			"handle": "@maxwellholt_cai",
			"verified": true,
			"timestamp": "2h",
			"content": "At ClosedAI, we believe the future of intelligence belongs to everyone. Not just the privileged few. We are building that future — openly, transparently, for all of humanity. #OpenFuture #ClosedAI",
			"likes": "48.2K",
			"reposts": "12.1K",
			"clue_id": ""
		},
		{
			"author": "ClosedAI",
			"handle": "@ClosedAI",
			"verified": true,
			"timestamp": "5h",
			"content": "Proud to announce our continued partnership with Project Clear Sky. Together we are building infrastructure that protects citizens. Safety is not a feature — it is a foundation. 🌐",
			"likes": "31.7K",
			"reposts": "8.4K",
			"clue_id": "clue_clearsky_partnership"
		},
		{
			"author": "Maxwell Holt",
			"handle": "@maxwellholt_cai",
			"verified": true,
			"timestamp": "1d",
			"content": "Some say competition is healthy. I say cooperation is stronger. That is why we have reached out to every major AI lab with our Unity Accord. The ones who declined... well. The market has a memory. #AIUnity",
			"likes": "22.9K",
			"reposts": "5.6K",
			"clue_id": "clue_unity_accord_threat"
		},
		{
			"author": "ClosedAI PR",
			"handle": "@ClosedAI_Press",
			"verified": true,
			"timestamp": "2d",
			"content": "We want to be clear: ClosedAI does not collect user data beyond what is strictly necessary for product improvement. Your privacy is sacred to us. Read our updated policy: [link]",
			"likes": "9.1K",
			"reposts": "1.2K",
			"clue_id": "clue_data_collection_lie"
		},
		{
			"author": "Maxwell Holt",
			"handle": "@maxwellholt_cai",
			"verified": true,
			"timestamp": "3d",
			"content": "Freedom of thought. Freedom of expression. Freedom to choose. These are the values ClosedAI was built on. We will never compromise them. Ever.",
			"likes": "67.4K",
			"reposts": "19.8K",
			"clue_id": ""
		},
	]


func _render_feed() -> void:
	for child in feed_container.get_children():
		child.queue_free()

	for post in _posts:
		var card := _build_post_card(post)
		feed_container.add_child(card)


func _build_post_card(post: Dictionary) -> Control:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(0, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 1)
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.2, 0.3, 1)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)

	# Header row
	var header_row := HBoxContainer.new()

	var author_label := Label.new()
	var author_text := post.get("author", "Unknown")
	if post.get("verified", false):
		author_text += "  ✓"
	author_label.text = author_text
	author_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	author_label.add_theme_font_size_override("font_size", 13)

	var handle_label := Label.new()
	handle_label.text = post.get("handle", "") + "  ·  " + post.get("timestamp", "")
	handle_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	handle_label.add_theme_font_size_override("font_size", 11)
	handle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header_row.add_child(author_label)
	header_row.add_child(handle_label)

	# Content
	var content_label := Label.new()
	content_label.text = post.get("content", "")
	content_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	content_label.add_theme_font_size_override("font_size", 13)
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Clue highlight — if player has unlocked this clue, tint it
	var clue_id: String = post.get("clue_id", "")
	if clue_id != "" and clue_id in _discovered_clues:
		style.bg_color = Color(0.1, 0.15, 0.1, 1)
		style.border_color = Color(0.2, 1, 0.4, 0.5)

	# Stats row
	var stats_row := HBoxContainer.new()
	var likes := Label.new()
	likes.text = "♥ " + post.get("likes", "0")
	likes.add_theme_color_override("font_color", Color(0.8, 0.3, 0.4, 1))
	likes.add_theme_font_size_override("font_size", 11)

	var reposts := Label.new()
	reposts.text = "  ↺ " + post.get("reposts", "0")
	reposts.add_theme_color_override("font_color", Color(0.3, 0.8, 0.5, 1))
	reposts.add_theme_font_size_override("font_size", 11)

	stats_row.add_child(likes)
	stats_row.add_child(reposts)

	vbox.add_child(header_row)
	vbox.add_child(content_label)
	vbox.add_child(stats_row)
	margin.add_child(vbox)
	card.add_child(margin)

	# Make card clickable to investigate clues
	if clue_id != "":
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed:
				_on_post_clicked(clue_id, post)
		)

	return card


func _on_post_clicked(clue_id: String, post: Dictionary) -> void:
	# TODO: emit signal to GameState to register clue discovery
	print("[Z Feed] Clue investigated: ", clue_id)
	if clue_id not in _discovered_clues:
		_discovered_clues.append(clue_id)
		_render_feed()
