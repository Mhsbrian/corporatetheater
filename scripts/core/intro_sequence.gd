extends Control

# Corporate Theater — Intro Sequence
# Plays an animated narrative intro: feed posts scroll in, characters speak,
# narration fades in/out. Drives the player into the story before the desktop loads.

signal intro_finished

const INTRO_DATA_PATH := "res://data/lore/intro_sequence.json"
const DESKTOP_SCENE := "res://scenes/ui/desktop.tscn"

@onready var skyline: ColorRect = $Skyline
@onready var feed_layer: VBoxContainer = $FeedLayer/ScrollContainer/Feed
@onready var narration_label: Label = $NarrationLayer/NarrationLabel
@onready var char_left: Control = $CharacterLayer/CharLeft
@onready var char_right: Control = $CharacterLayer/CharRight
@onready var char_left_name: Label = $CharacterLayer/CharLeft/Name
@onready var char_left_text: Label = $CharacterLayer/CharLeft/Text
@onready var char_right_name: Label = $CharacterLayer/CharRight/Name
@onready var char_right_text: Label = $CharacterLayer/CharRight/Text
@onready var skip_hint: Label = $SkipHint
@onready var title_label: Label = $TitleLayer/TitleLabel
@onready var subtitle_label: Label = $TitleLayer/SubtitleLabel
@onready var overlay: ColorRect = $Overlay

var _sequence: Array = []
var _step: int = 0
var _playing: bool = false
var _skip_requested: bool = false


func _ready() -> void:
	_load_sequence()
	_reset_ui()
	await get_tree().create_timer(0.5).timeout
	_play_next()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
			_skip_requested = true
			_finish()


func _load_sequence() -> void:
	if not FileAccess.file_exists(INTRO_DATA_PATH):
		push_error("Intro sequence data not found.")
		return
	var file := FileAccess.open(INTRO_DATA_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_sequence = json.data


func _reset_ui() -> void:
	narration_label.modulate.a = 0.0
	char_left.modulate.a = 0.0
	char_right.modulate.a = 0.0
	title_label.modulate.a = 0.0
	subtitle_label.modulate.a = 0.0
	overlay.modulate.a = 1.0
	skip_hint.modulate.a = 0.0
	char_left.visible = true
	char_right.visible = true

	# Fade in from black
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 1.5)
	tween.tween_callback(func(): skip_hint.modulate.a = 0.5)


func _play_next() -> void:
	if _skip_requested or _step >= _sequence.size():
		_finish()
		return

	var step: Dictionary = _sequence[_step]
	_step += 1
	_playing = true

	match step.get("type", ""):
		"narration":
			await _show_narration(step)
		"feed_post":
			await _show_feed_post(step)
		"character":
			await _show_character(step)
		"system":
			await _show_system_message(step)
		"end":
			await get_tree().create_timer(step.get("delay", 1.0)).timeout
			_finish()
			return

	_playing = false
	_play_next()


# ── Step Renderers ────────────────────────────────────────────────────────────

func _show_narration(step: Dictionary) -> void:
	var is_title: bool = step.get("is_title", false)
	var text: String = step.get("text", "")
	var delay: float = step.get("delay", 1.5)

	if is_title:
		title_label.text = text
		subtitle_label.text = ""
		var tween := create_tween().set_parallel(false)
		tween.tween_property(title_label, "modulate:a", 1.0, 0.6)
		await tween.finished
		await get_tree().create_timer(delay).timeout
		# Wait for subtitle (next narration step handles it)
	else:
		# Check if title is visible — if so this is the subtitle
		if title_label.modulate.a > 0.5:
			subtitle_label.text = text
			var tween := create_tween()
			tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.5)
			await tween.finished
			await get_tree().create_timer(delay + 0.5).timeout
			# Fade both out
			var tween2 := create_tween().set_parallel(true)
			tween2.tween_property(title_label, "modulate:a", 0.0, 1.0)
			tween2.tween_property(subtitle_label, "modulate:a", 0.0, 1.0)
			await tween2.finished
		else:
			narration_label.text = text
			var tween := create_tween().set_parallel(false)
			tween.tween_property(narration_label, "modulate:a", 1.0, 0.4)
			await tween.finished
			await get_tree().create_timer(delay).timeout
			tween = create_tween()
			tween.tween_property(narration_label, "modulate:a", 0.0, 0.4)
			await tween.finished


func _show_feed_post(step: Dictionary) -> void:
	var delay: float = step.get("delay", 1.0)
	var card := _build_feed_card(step)
	card.modulate.a = 0.0
	feed_layer.add_child(card)

	# Slide + fade in
	card.position.x = -60
	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.5)
	tween.tween_property(card, "position:x", 0.0, 0.4)
	await tween.finished
	await get_tree().create_timer(delay).timeout

	# Keep only last 4 posts visible, fade out old ones
	if feed_layer.get_child_count() > 4:
		var oldest: Control = feed_layer.get_child(0)
		var fade := create_tween()
		fade.tween_property(oldest, "modulate:a", 0.0, 0.3)
		await fade.finished
		oldest.queue_free()


func _show_character(step: Dictionary) -> void:
	var side: String = step.get("side", "left")
	var name_text: String = step.get("name", "")
	var text: String = step.get("text", "")
	var delay: float = step.get("delay", 1.5)

	var container: Control = char_left if side == "left" else char_right
	var name_label: Label = char_left_name if side == "left" else char_right_name
	var text_label: Label = char_left_text if side == "left" else char_right_text
	var other: Control = char_right if side == "left" else char_left

	name_label.text = name_text
	text_label.text = ""

	# Dim the other character
	if other.modulate.a > 0.1:
		var dim := create_tween()
		dim.tween_property(other, "modulate:a", 0.3, 0.2)

	# Fade in active character
	var tween := create_tween()
	tween.tween_property(container, "modulate:a", 1.0, 0.3)
	await tween.finished

	# Typewriter effect
	await _typewrite(text_label, text)
	await get_tree().create_timer(delay).timeout


func _show_system_message(step: Dictionary) -> void:
	var text: String = step.get("text", "")
	var delay: float = step.get("delay", 1.5)

	narration_label.text = "[ SYSTEM ] " + text
	narration_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1, 1.0))

	var tween := create_tween().set_parallel(false)
	tween.tween_property(narration_label, "modulate:a", 1.0, 0.3)
	await tween.finished
	await get_tree().create_timer(delay).timeout
	tween = create_tween()
	tween.tween_property(narration_label, "modulate:a", 0.0, 0.4)
	await tween.finished

	narration_label.remove_theme_color_override("font_color")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _typewrite(label: Label, text: String) -> void:
	label.text = ""
	for i in text.length():
		label.text += text[i]
		await get_tree().create_timer(0.025).timeout


func _build_feed_card(post: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 0.95)
	style.border_width_left = 3
	style.border_color = Color.from_string(post.get("avatar_color", "#44ff88"), Color(0.2, 1, 0.4, 1))
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()

	var dot := ColorRect.new()
	dot.color = Color.from_string(post.get("avatar_color", "#44ff88"), Color.GREEN)
	dot.custom_minimum_size = Vector2(10, 10)

	var author := Label.new()
	var author_text: String = post.get("author", "")
	if post.get("verified", false):
		author_text += "  ✓"
	author.text = author_text
	author.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1))
	author.add_theme_font_size_override("font_size", 12)

	var handle := Label.new()
	handle.text = "  " + post.get("handle", "")
	handle.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55, 1))
	handle.add_theme_font_size_override("font_size", 11)
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(dot)
	header.add_child(author)
	header.add_child(handle)

	var content := Label.new()
	content.text = post.get("content", "")
	content.add_theme_color_override("font_color", Color(0.82, 0.82, 0.88, 1))
	content.add_theme_font_size_override("font_size", 12)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var stats := Label.new()
	stats.text = "♥ %s   ↺ %s" % [post.get("likes", "0"), post.get("reposts", "0")]
	stats.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	stats.add_theme_font_size_override("font_size", 11)

	vbox.add_child(header)
	vbox.add_child(content)
	vbox.add_child(stats)
	card.add_child(vbox)
	return card


func _finish() -> void:
	skip_hint.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 1.0, 1.2)
	await tween.finished
	get_tree().change_scene_to_file(DESKTOP_SCENE)
