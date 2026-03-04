extends Control

# Corporate Theater — Intro Sequence
# Left panel: Z live feed scrolling in.
# Right panel: Z Messenger chrome with real chat bubbles.
# Narration appears as a subtle caption bar at the bottom.

const INTRO_DATA_PATH := "res://data/lore/intro_sequence.json"
const DESKTOP_SCENE   := "res://scenes/ui/desktop.tscn"

# Feed
@onready var feed_container: VBoxContainer  = $HSplit/FeedPanel/FeedLayer/ScrollContainer/Feed
@onready var feed_scroll: ScrollContainer   = $HSplit/FeedPanel/FeedLayer/ScrollContainer

# Messenger
@onready var contact_name:   Label          = $HSplit/MessengerPanel/MsgVBox/MsgHeader/HeaderVBox/ContactName
@onready var contact_status: Label          = $HSplit/MessengerPanel/MsgVBox/MsgHeader/HeaderVBox/ContactStatus
@onready var msg_container:  VBoxContainer  = $HSplit/MessengerPanel/MsgVBox/MsgScroll/MsgContainer
@onready var msg_scroll:     ScrollContainer = $HSplit/MessengerPanel/MsgVBox/MsgScroll

# Narration / title / overlay
@onready var narration_label:  Label      = $NarrationLayer/NarrationLabel
@onready var title_label:      Label      = $TitleLayer/TitleVBox/TitleLabel
@onready var subtitle_label:   Label      = $TitleLayer/TitleVBox/SubtitleLabel
@onready var skip_hint:        Label      = $SkipHint
@onready var overlay:          ColorRect  = $Overlay

# Bubble style resources — built once, reused
var _style_ghost:   StyleBoxFlat
var _style_unknown: StyleBoxFlat
var _style_system:  StyleBoxFlat

var _sequence: Array = []
var _step: int = 0
var _skip_requested: bool = false


func _ready() -> void:
	_build_styles()
	_load_sequence()
	_reset_ui()
	await get_tree().create_timer(0.6).timeout
	_play_next()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
			_skip_requested = true
			_finish()


# ── Style builders ─────────────────────────────────────────────────────────────

func _build_styles() -> void:
	_style_ghost = StyleBoxFlat.new()
	_style_ghost.bg_color          = Color(0.10, 0.18, 0.10, 1)
	_style_ghost.border_width_left = 2
	_style_ghost.border_color      = Color(0.2, 0.85, 0.35, 0.7)
	_style_ghost.corner_radius_top_left     = 10
	_style_ghost.corner_radius_top_right    = 10
	_style_ghost.corner_radius_bottom_right = 10
	_style_ghost.corner_radius_bottom_left  = 2
	_style_ghost.content_margin_left   = 12
	_style_ghost.content_margin_right  = 12
	_style_ghost.content_margin_top    = 8
	_style_ghost.content_margin_bottom = 8

	_style_unknown = StyleBoxFlat.new()
	_style_unknown.bg_color           = Color(0.14, 0.09, 0.09, 1)
	_style_unknown.border_width_right = 2
	_style_unknown.border_color       = Color(0.85, 0.3, 0.3, 0.7)
	_style_unknown.corner_radius_top_left     = 10
	_style_unknown.corner_radius_top_right    = 10
	_style_unknown.corner_radius_bottom_left  = 10
	_style_unknown.corner_radius_bottom_right = 2
	_style_unknown.content_margin_left   = 12
	_style_unknown.content_margin_right  = 12
	_style_unknown.content_margin_top    = 8
	_style_unknown.content_margin_bottom = 8

	_style_system = StyleBoxFlat.new()
	_style_system.bg_color          = Color(0.06, 0.06, 0.11, 1)
	_style_system.border_width_top    = 1
	_style_system.border_width_bottom = 1
	_style_system.border_color        = Color(0.15, 0.15, 0.3, 1)
	_style_system.content_margin_left   = 14
	_style_system.content_margin_right  = 14
	_style_system.content_margin_top    = 6
	_style_system.content_margin_bottom = 6


# ── Setup ──────────────────────────────────────────────────────────────────────

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
	title_label.modulate.a    = 0.0
	subtitle_label.modulate.a = 0.0
	skip_hint.modulate.a      = 0.0
	overlay.modulate.a        = 1.0
	contact_name.text         = ""
	contact_status.text       = ""

	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, 1.5)
	tween.tween_callback(func(): skip_hint.modulate.a = 0.4)


# ── Sequencer ─────────────────────────────────────────────────────────────────

func _play_next() -> void:
	if _skip_requested or _step >= _sequence.size():
		_finish()
		return

	var step: Dictionary = _sequence[_step]
	_step += 1

	match step.get("type", ""):
		"narration":
			await _show_narration(step)
		"feed_post":
			await _show_feed_post(step)
		"character":
			await _show_character_bubble(step)
		"system":
			await _show_system_bubble(step)
		"end":
			await get_tree().create_timer(step.get("delay", 1.0)).timeout
			_finish()
			return

	_play_next()


# ── Step handlers ──────────────────────────────────────────────────────────────

func _show_narration(step: Dictionary) -> void:
	var is_title: bool = step.get("is_title", false)
	var text: String   = step.get("text", "")
	var delay: float   = step.get("delay", 2.0)

	if is_title:
		title_label.text = text
		var tw := create_tween()
		tw.tween_property(title_label, "modulate:a", 1.0, 0.7)
		await tw.finished
		await get_tree().create_timer(delay).timeout
	else:
		# If title is showing, this is the subtitle
		if title_label.modulate.a > 0.5:
			subtitle_label.text = text
			var tw := create_tween()
			tw.tween_property(subtitle_label, "modulate:a", 1.0, 0.5)
			await tw.finished
			await get_tree().create_timer(delay).timeout
			var tw2 := create_tween()
			tw2.set_parallel(true)
			tw2.tween_property(title_label,    "modulate:a", 0.0, 1.0)
			tw2.tween_property(subtitle_label, "modulate:a", 0.0, 1.0)
			await tw2.finished
		else:
			narration_label.text = text
			var tw := create_tween()
			tw.tween_property(narration_label, "modulate:a", 1.0, 0.4)
			await tw.finished
			await get_tree().create_timer(delay).timeout
			tw = create_tween()
			tw.tween_property(narration_label, "modulate:a", 0.0, 0.5)
			await tw.finished


func _show_feed_post(step: Dictionary) -> void:
	var delay: float = step.get("delay", 1.5)
	var card := _build_feed_card(step)
	card.modulate.a  = 0.0
	card.position.x  = -40.0
	feed_container.add_child(card)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a",   1.0, 0.45)
	tw.tween_property(card, "position:x",   0.0, 0.35)
	await tw.finished

	# Keep only the last 5 posts; fade oldest
	if feed_container.get_child_count() > 5:
		var oldest: Control = feed_container.get_child(0)
		var fade := create_tween()
		fade.tween_property(oldest, "modulate:a", 0.0, 0.3)
		await fade.finished
		oldest.queue_free()

	await get_tree().create_timer(delay).timeout


func _show_character_bubble(step: Dictionary) -> void:
	var side: String  = step.get("side", "left")
	var name_text: String = step.get("name", "")
	var text: String  = step.get("text", "")
	var delay: float  = step.get("delay", 2.0)

	# Update messenger header on first message from each contact
	if contact_name.text != name_text:
		contact_name.text = name_text
		if side == "right":
			contact_status.text = "encrypted channel  ·  source unknown"
			contact_status.add_theme_color_override("font_color", Color(0.8, 0.35, 0.35, 1))
		else:
			contact_status.text = "online"
			contact_status.add_theme_color_override("font_color", Color(0.3, 0.75, 0.35, 1))

	var is_ghost: bool = side == "left"
	var bubble := _build_bubble(text, is_ghost)
	bubble.modulate.a = 0.0
	msg_container.add_child(bubble)

	# Scroll to bottom
	await get_tree().process_frame
	msg_scroll.scroll_vertical = int(msg_scroll.get_v_scroll_bar().max_value)

	# Typing delay then fade in
	await get_tree().create_timer(0.3).timeout
	var tw := create_tween()
	tw.tween_property(bubble, "modulate:a", 1.0, 0.35)
	await tw.finished

	await get_tree().create_timer(delay).timeout


func _show_system_bubble(step: Dictionary) -> void:
	var text: String  = step.get("text", "")
	var delay: float  = step.get("delay", 2.0)

	var row := CenterContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_system)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.7, 1))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	panel.add_child(lbl)
	row.add_child(panel)
	row.modulate.a = 0.0
	msg_container.add_child(row)

	await get_tree().process_frame
	msg_scroll.scroll_vertical = int(msg_scroll.get_v_scroll_bar().max_value)

	var tw := create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.4)
	await tw.finished
	await get_tree().create_timer(delay).timeout


# ── Bubble builder ─────────────────────────────────────────────────────────────

func _build_bubble(text: String, is_ghost: bool) -> Control:
	# Row: spacer | bubble  (ghost = right-aligned) or  bubble | spacer (unknown = left)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(60, 0)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_ghost if is_ghost else _style_unknown)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var name_lbl := Label.new()
	name_lbl.text = "GHOST" if is_ghost else "[ UNKNOWN ]"
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color",
		Color(0.2, 0.85, 0.35, 0.8) if is_ghost else Color(0.85, 0.35, 0.35, 0.8))

	var text_lbl := Label.new()
	text_lbl.text = text
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.add_theme_font_size_override("font_size", 13)
	text_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92, 1))
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.custom_minimum_size = Vector2(180, 0)

	vbox.add_child(name_lbl)
	vbox.add_child(text_lbl)
	panel.add_child(vbox)

	if is_ghost:
		row.add_child(spacer)
		row.add_child(panel)
	else:
		row.add_child(panel)
		row.add_child(spacer)

	return row


# ── Feed card ──────────────────────────────────────────────────────────────────

func _build_feed_card(post: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.06, 0.06, 0.10, 1)
	style.border_width_left = 3
	style.border_color      = Color.from_string(post.get("avatar_color", "#44ff88"), Color(0.2, 1, 0.4, 1))
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 12
	style.content_margin_right  = 12
	style.content_margin_top    = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)

	# Author row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	var dot := ColorRect.new()
	dot.color = Color.from_string(post.get("avatar_color", "#44ff88"), Color.GREEN)
	dot.custom_minimum_size = Vector2(8, 8)

	var author := Label.new()
	var author_text: String = post.get("author", "")
	if post.get("verified", false):
		author_text += "  ✓"
	author.text = author_text
	author.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96, 1))
	author.add_theme_font_size_override("font_size", 11)

	var handle := Label.new()
	handle.text = post.get("handle", "")
	handle.add_theme_color_override("font_color", Color(0.38, 0.38, 0.5, 1))
	handle.add_theme_font_size_override("font_size", 10)
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(dot)
	header.add_child(author)
	header.add_child(handle)

	var content := Label.new()
	content.text = post.get("content", "")
	content.add_theme_color_override("font_color", Color(0.80, 0.80, 0.87, 1))
	content.add_theme_font_size_override("font_size", 11)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var stats := Label.new()
	stats.text = "♥ %s   ↺ %s" % [post.get("likes", "0"), post.get("reposts", "0")]
	stats.add_theme_color_override("font_color", Color(0.32, 0.32, 0.44, 1))
	stats.add_theme_font_size_override("font_size", 10)

	vbox.add_child(header)
	vbox.add_child(content)
	vbox.add_child(stats)
	card.add_child(vbox)
	return card


# ── Finish ─────────────────────────────────────────────────────────────────────

func _finish() -> void:
	skip_hint.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 1.2)
	await tw.finished
	get_tree().change_scene_to_file(DESKTOP_SCENE)
