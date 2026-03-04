extends Control

# Corporate Theater — Z Messenger
# Realistic paced DM conversations with ClosedAI insiders.
# Typing indicators, natural delays, branching choices, clue triggers.

signal clue_discovered(clue_id: String)
signal contact_unlocked(contact_id: String)

const MESSENGER_DATA_PATH := "res://data/posts/z_messenger.json"
const TYPING_DELAY_PER_CHAR := 0.045  # seconds per character — feels like real typing
const TYPING_INDICATOR_MIN := 1.2     # minimum "typing..." time before message appears
const READ_PAUSE := 0.6               # pause after message appears before next one

@onready var contact_list: VBoxContainer = $Split/ContactPanel/Scroll/ContactList
@onready var chat_header_name: Label = $Split/ChatPanel/Header/Name
@onready var chat_header_status: Label = $Split/ChatPanel/Header/Status
@onready var chat_header_role: Label = $Split/ChatPanel/Header/Role
@onready var messages_container: VBoxContainer = $Split/ChatPanel/MessagesScroll/Messages
@onready var choices_container: VBoxContainer = $Split/ChatPanel/ChoicesPanel/Choices
@onready var choices_label: Label = $Split/ChatPanel/ChoicesPanel/ChoicesLabel
@onready var empty_state: Label = $Split/ChatPanel/EmptyState
@onready var messages_scroll: ScrollContainer = $Split/ChatPanel/MessagesScroll
@onready var chat_panel: Control = $Split/ChatPanel
@onready var header_panel: Panel = $Split/ChatPanel/Header

var _contacts: Array = []
var _active_contact: Dictionary = {}
var _discovered_clues: Array[String] = []
var _unlocked_contacts: Array[String] = ["elena_vasquez"]
var _conversation_states: Dictionary = {}
var _typing_indicator: Control = null
var _is_playing: bool = false


func _ready() -> void:
	_load_contacts()
	_build_contact_list()
	header_panel.visible = false
	choices_label.visible = false


func _load_contacts() -> void:
	if not FileAccess.file_exists(MESSENGER_DATA_PATH):
		return
	var file := FileAccess.open(MESSENGER_DATA_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_contacts = json.data.get("contacts", [])


# ── Contact List ──────────────────────────────────────────────────────────────

func _build_contact_list() -> void:
	for child in contact_list.get_children():
		child.queue_free()

	for contact in _contacts:
		var is_unlocked: bool = contact.get("id", "") in _unlocked_contacts
		contact_list.add_child(_build_contact_row(contact, is_unlocked))


func _build_contact_row(contact: Dictionary, is_unlocked: bool) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 1)
	style.border_width_bottom = 1
	style.border_color = Color(0.1, 0.1, 0.18, 1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	# Avatar circle (colored dot as placeholder)
	var avatar := ColorRect.new()
	var av_col := Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)
	avatar.color = av_col if is_unlocked else Color(0.2, 0.2, 0.25, 1)
	avatar.custom_minimum_size = Vector2(32, 32)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = contact.get("display_name", "") if is_unlocked else "???"
	name_lbl.add_theme_color_override("font_color",
		Color(0.92, 0.92, 0.96, 1) if is_unlocked else Color(0.3, 0.3, 0.38, 1))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_unlocked and contact.get("status", "") == "online":
		var online_dot := Label.new()
		online_dot.text = "●"
		online_dot.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 1))
		online_dot.add_theme_font_size_override("font_size", 10)
		name_row.add_child(name_lbl)
		name_row.add_child(online_dot)
	else:
		name_row.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = contact.get("handle", "") if is_unlocked else "[ locked contact ]"
	sub_lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.5, 1))
	sub_lbl.add_theme_font_size_override("font_size", 10)

	vbox.add_child(name_row)
	vbox.add_child(sub_lbl)
	hbox.add_child(avatar)
	hbox.add_child(vbox)
	panel.add_child(hbox)

	if is_unlocked:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if not _is_playing:
					_open_contact(contact)
		)

	return panel


# ── Conversation Flow ─────────────────────────────────────────────────────────

func _open_contact(contact: Dictionary) -> void:
	_active_contact = contact
	empty_state.visible = false
	header_panel.visible = true

	chat_header_name.text = contact.get("display_name", "")
	chat_header_role.text = contact.get("role", "")

	var online: bool = contact.get("status", "") == "online"
	chat_header_status.text = "● online" if online else "● away"
	chat_header_status.add_theme_color_override("font_color",
		Color(0.3, 0.85, 0.4, 1) if online else Color(0.65, 0.55, 0.2, 1))

	_clear_messages()
	_clear_choices()

	var contact_id: String = contact.get("id", "")
	var saved_state: String = _conversation_states.get(contact_id, "")

	if saved_state == "":
		var start_conv := _find_conversation(contact, "start")
		if not start_conv.is_empty():
			await _play_conversation(contact, start_conv)
	else:
		var conv := _find_conversation_by_id(contact, saved_state)
		if not conv.is_empty():
			_show_choices(contact, conv)


func _find_conversation(contact: Dictionary, trigger: String) -> Dictionary:
	for conv in contact.get("conversations", []):
		if conv.get("trigger", "") == trigger:
			return conv
	return {}


func _find_conversation_by_id(contact: Dictionary, conv_id: String) -> Dictionary:
	for conv in contact.get("conversations", []):
		if conv.get("id", "") == conv_id:
			return conv
	return {}


func _play_conversation(contact: Dictionary, conv: Dictionary) -> void:
	_is_playing = true
	_clear_choices()
	choices_label.visible = false
	_conversation_states[contact.get("id", "")] = conv.get("id", "")

	for msg in conv.get("messages", []):
		var text: String = msg.get("text", "")
		var from: String = msg.get("from", "contact")

		if from == "player":
			_add_player_bubble(text)
			await _scroll_to_bottom()
			await get_tree().create_timer(0.4).timeout
			continue

		# Calculate realistic typing time based on message length
		var char_count: int = text.length()
		var typing_time: float = max(TYPING_INDICATOR_MIN, char_count * TYPING_DELAY_PER_CHAR)
		typing_time = min(typing_time, 4.5)  # cap at 4.5s

		# Show typing indicator
		_show_typing_indicator(contact)
		await _scroll_to_bottom()
		await get_tree().create_timer(typing_time).timeout
		_hide_typing_indicator()

		# Show message
		if msg.get("is_attachment", false):
			_add_attachment_bubble(msg, contact)
		else:
			_add_contact_bubble(text, contact)

		await _scroll_to_bottom()
		await get_tree().create_timer(READ_PAUSE).timeout

	# Fire conversation-level clue/contact unlocks
	var unlocks_clue: String = conv.get("unlocks_clue", "")
	if unlocks_clue != "" and unlocks_clue not in _discovered_clues:
		_discovered_clues.append(unlocks_clue)
		emit_signal("clue_discovered", unlocks_clue)
		_add_system_message("[ clue discovered ]")

	var unlocks_contact: String = conv.get("unlocks_contact", "")
	if unlocks_contact != "" and unlocks_contact not in _unlocked_contacts:
		_unlocked_contacts.append(unlocks_contact)
		emit_signal("contact_unlocked", unlocks_contact)
		_build_contact_list()
		_add_system_message("[ new contact available ]")

	_is_playing = false
	_show_choices(contact, conv)


func _show_choices(contact: Dictionary, conv: Dictionary) -> void:
	_clear_choices()
	var choices: Array = conv.get("player_choices", [])

	if choices.is_empty():
		choices_label.visible = false
		return

	choices_label.visible = true

	for choice in choices:
		var btn := _make_choice_button(choice, contact)
		choices_container.add_child(btn)


func _make_choice_button(choice: Dictionary, contact: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = choice.get("text", "")
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0, 1))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1))

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.10, 0.14, 1)
	style_normal.border_width_left = 2
	style_normal.border_color = Color(0.2, 0.45, 0.7, 0.6)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.10, 0.14, 0.20, 1)
	style_hover.border_width_left = 2
	style_hover.border_color = Color(0.3, 0.6, 1.0, 0.9)
	style_hover.corner_radius_top_left = 4
	style_hover.corner_radius_top_right = 4
	style_hover.corner_radius_bottom_left = 4
	style_hover.corner_radius_bottom_right = 4
	style_hover.content_margin_left = 12
	style_hover.content_margin_right = 12
	style_hover.content_margin_top = 8
	style_hover.content_margin_bottom = 8
	btn.add_theme_stylebox_override("hover", style_hover)

	var next_id: String = choice.get("leads_to", "")
	var choice_text: String = choice.get("text", "")
	var unlocks_clue: String = choice.get("unlocks_clue", "")
	var unlocks_contact_id: String = choice.get("unlocks_contact", "")

	btn.pressed.connect(func():
		if _is_playing:
			return
		_clear_choices()
		choices_label.visible = false
		_add_player_bubble(choice_text)

		# Fire choice-level unlocks immediately
		if unlocks_clue != "" and unlocks_clue not in _discovered_clues:
			_discovered_clues.append(unlocks_clue)
			emit_signal("clue_discovered", unlocks_clue)

		if unlocks_contact_id != "" and unlocks_contact_id not in _unlocked_contacts:
			_unlocked_contacts.append(unlocks_contact_id)
			emit_signal("contact_unlocked", unlocks_contact_id)
			_build_contact_list()

		await _scroll_to_bottom()

		if next_id != "":
			var next_conv := _find_conversation_by_id(contact, next_id)
			if not next_conv.is_empty():
				await _play_conversation(contact, next_conv)
	)

	return btn


# ── Typing Indicator ──────────────────────────────────────────────────────────

func _show_typing_indicator(contact: Dictionary) -> void:
	if _typing_indicator != null:
		return

	var row := HBoxContainer.new()
	row.name = "TypingRow"
	row.add_theme_constant_override("separation", 8)

	var avatar := ColorRect.new()
	avatar.color = Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)
	avatar.custom_minimum_size = Vector2(8, 8)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.14, 1)
	style.border_width_left = 2
	style.border_color = Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style)

	var dots := Label.new()
	dots.text = "···"
	dots.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 1))
	dots.add_theme_font_size_override("font_size", 16)
	bubble.add_child(dots)

	row.add_child(avatar)
	row.add_child(bubble)
	messages_container.add_child(row)
	_typing_indicator = row

	# Animate the dots
	var tween := create_tween().set_loops()
	tween.tween_callback(func(): dots.text = "·  ")
	tween.tween_interval(0.3)
	tween.tween_callback(func(): dots.text = "·· ")
	tween.tween_interval(0.3)
	tween.tween_callback(func(): dots.text = "···")
	tween.tween_interval(0.3)
	row.set_meta("tween", tween)


func _hide_typing_indicator() -> void:
	if _typing_indicator == null:
		return
	if _typing_indicator.has_meta("tween"):
		(_typing_indicator.get_meta("tween") as Tween).kill()
	_typing_indicator.queue_free()
	_typing_indicator = null


# ── Bubble Builders ───────────────────────────────────────────────────────────

func _add_contact_bubble(text: String, contact: Dictionary) -> void:
	var av_color := Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Avatar
	var avatar := ColorRect.new()
	avatar.color = av_color
	avatar.custom_minimum_size = Vector2(8, 8)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Bubble — left aligned, max 65% width
	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.14, 1)
	style.border_width_left = 2
	style.border_color = av_color
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.86, 0.86, 0.92, 1))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_child(lbl)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Small spacer so bubble takes ~85% of width
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(60, 0)

	row.add_child(avatar)
	row.add_child(bubble)
	row.add_child(spacer)
	messages_container.add_child(row)


func _add_player_bubble(text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END

	# Small spacer on left so bubble takes ~85% of width
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(60, 0)

	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.15, 0.10, 1)
	style.border_width_right = 2
	style.border_color = Color(0.2, 0.85, 0.45, 0.7)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 0.88, 1))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_child(lbl)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(spacer)
	row.add_child(bubble)
	messages_container.add_child(row)


func _add_system_message(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.28, 0.28, 0.4, 1))
	lbl.add_theme_font_size_override("font_size", 10)
	messages_container.add_child(lbl)


func _add_attachment_bubble(msg: Dictionary, contact: Dictionary) -> void:
	var av_color := Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var avatar := ColorRect.new()
	avatar.color = av_color
	avatar.custom_minimum_size = Vector2(8, 8)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.08, 1)
	style.border_width_left = 2
	style.border_color = Color(0.2, 0.85, 0.45, 0.6)
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", style)
	bubble.custom_minimum_size = Vector2(220, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var file_lbl := Label.new()
	file_lbl.text = "  " + msg.get("text", "[file]")
	file_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65, 1))
	file_lbl.add_theme_font_size_override("font_size", 12)

	var tap_lbl := Label.new()
	tap_lbl.text = "  tap to examine"
	tap_lbl.add_theme_color_override("font_color", Color(0.35, 0.55, 0.4, 1))
	tap_lbl.add_theme_font_size_override("font_size", 10)

	vbox.add_child(file_lbl)
	vbox.add_child(tap_lbl)
	bubble.add_child(vbox)

	var clue_id: String = msg.get("attachment_clue", "")
	if clue_id != "":
		bubble.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		bubble.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if clue_id not in _discovered_clues:
					_discovered_clues.append(clue_id)
					emit_signal("clue_discovered", clue_id)
					tap_lbl.text = "  evidence collected"
					tap_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1))
		)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	row.add_child(avatar)
	row.add_child(bubble)
	row.add_child(spacer)
	messages_container.add_child(row)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _clear_messages() -> void:
	_hide_typing_indicator()
	for child in messages_container.get_children():
		child.queue_free()


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	messages_scroll.scroll_vertical = messages_scroll.get_v_scroll_bar().max_value


func unlock_contact(contact_id: String) -> void:
	if contact_id not in _unlocked_contacts:
		_unlocked_contacts.append(contact_id)
		_build_contact_list()
