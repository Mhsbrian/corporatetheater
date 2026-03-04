extends Control

# Corporate Theater — Z Messenger
# All state persisted via GameState autoload.
# Messages are remembered across sessions.

const MESSENGER_DATA_PATH := "res://data/posts/z_messenger.json"
const TYPING_DELAY_PER_CHAR := 0.042
const TYPING_INDICATOR_MIN := 1.0
const READ_PAUSE := 0.5

@onready var contact_list: VBoxContainer = $Split/ContactPanel/Scroll/ContactList
@onready var chat_header_name: Label = $Split/ChatPanel/Header/Name
@onready var chat_header_status: Label = $Split/ChatPanel/Header/Status
@onready var chat_header_role: Label = $Split/ChatPanel/Header/Role
@onready var messages_container: VBoxContainer = $Split/ChatPanel/MessagesScroll/Messages
@onready var choices_container: VBoxContainer = $Split/ChatPanel/ChoicesPanel/Choices
@onready var choices_label: Label = $Split/ChatPanel/ChoicesPanel/ChoicesLabel
@onready var empty_state: Label = $Split/ChatPanel/EmptyState
@onready var messages_scroll: ScrollContainer = $Split/ChatPanel/MessagesScroll
@onready var header_panel: Panel = $Split/ChatPanel/Header

var _contacts: Array = []
var _active_contact: Dictionary = {}
var _typing_indicator: Control = null
var _is_playing: bool = false


func _ready() -> void:
	_load_contacts()
	_build_contact_list()
	header_panel.visible = false
	choices_label.visible = false
	GameState.contact_unlocked.connect(_on_contact_unlocked)


func _load_contacts() -> void:
	if not FileAccess.file_exists(MESSENGER_DATA_PATH):
		return
	var file := FileAccess.open(MESSENGER_DATA_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_contacts = json.data.get("contacts", [])


func _on_contact_unlocked(_contact_id: String) -> void:
	_build_contact_list()


# ── Contact List ──────────────────────────────────────────────────────────────

func _build_contact_list() -> void:
	for child in contact_list.get_children():
		child.queue_free()
	for contact in _contacts:
		var is_unlocked: bool = contact.get("id", "") in GameState.unlocked_contacts
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
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4, 1))
		dot.add_theme_font_size_override("font_size", 10)
		name_row.add_child(name_lbl)
		name_row.add_child(dot)
	else:
		name_row.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = contact.get("handle", "") if is_unlocked else "[ locked contact ]"
	sub_lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.5, 1))
	sub_lbl.add_theme_font_size_override("font_size", 10)

	# Show unread indicator if there are saved messages
	var has_history: bool = not GameState.get_messages(contact.get("id", "")).is_empty()
	if is_unlocked and has_history:
		var hist_dot := Label.new()
		hist_dot.text = "  ◉"
		hist_dot.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0, 0.6))
		hist_dot.add_theme_font_size_override("font_size", 9)
		sub_lbl.text += hist_dot.text

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

	# Replay saved message history instantly (no delays)
	var history := GameState.get_messages(contact_id)
	if not history.is_empty():
		for msg in history:
			if msg.get("from", "") == "player":
				_add_player_bubble(msg.get("text", ""), false)
			elif msg.get("from", "") == "system":
				_add_system_message(msg.get("text", ""))
			else:
				_add_contact_bubble(msg.get("text", ""), contact, false)
		await _scroll_to_bottom()

		# Restore choices from last saved conversation
		var saved_conv_id := GameState.get_conversation_state(contact_id)
		if saved_conv_id != "":
			var conv := _find_conversation_by_id(contact, saved_conv_id)
			if not conv.is_empty():
				_show_choices(contact, conv)
		return

	# No history — start fresh
	var start_conv := _find_conversation(contact, "start")
	if not start_conv.is_empty():
		await _play_conversation(contact, start_conv)


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

	var contact_id: String = contact.get("id", "")
	GameState.save_conversation_state(contact_id, conv.get("id", ""))

	for msg in conv.get("messages", []):
		var text: String = msg.get("text", "")
		var from: String = msg.get("from", "contact")

		if from == "player":
			_add_player_bubble(text, true)
			GameState.append_message(contact_id, "player", text)
			await _scroll_to_bottom()
			await get_tree().create_timer(0.4).timeout
			continue

		# Typing indicator with realistic delay
		var typing_time: float = clampf(text.length() * TYPING_DELAY_PER_CHAR, TYPING_INDICATOR_MIN, 4.5)
		_show_typing_indicator(contact)
		await _scroll_to_bottom()
		await get_tree().create_timer(typing_time).timeout
		_hide_typing_indicator()

		if msg.get("is_attachment", false):
			_add_attachment_bubble(msg, contact)
			GameState.append_message(contact_id, "attachment", text)
		else:
			_add_contact_bubble(text, contact, true)
			GameState.append_message(contact_id, contact_id, text)

		await _scroll_to_bottom()
		await get_tree().create_timer(READ_PAUSE).timeout

	# Conversation-level unlocks
	var unlocks_clue: String = conv.get("unlocks_clue", "")
	if unlocks_clue != "":
		GameState.discover_clue(unlocks_clue)
		var sys_text: String = "[ clue logged: " + (GameState.CLUE_DEFINITIONS.get(unlocks_clue, {}) as Dictionary).get("title", unlocks_clue) as String + " ]"
		_add_system_message(sys_text)
		GameState.append_message(contact_id, "system", sys_text)

	var unlocks_contact: String = conv.get("unlocks_contact", "")
	if unlocks_contact != "":
		GameState.unlock_contact(unlocks_contact)
		var sys_text := "[ new contact available ]"
		_add_system_message(sys_text)
		GameState.append_message(contact_id, "system", sys_text)

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
		choices_container.add_child(_make_choice_button(choice, contact))


func _make_choice_button(choice: Dictionary, contact: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = choice.get("text", "")
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0, 1))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1))

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.08, 0.10, 0.14, 1)
	sn.border_width_left = 2
	sn.border_color = Color(0.2, 0.45, 0.7, 0.6)
	for corner in ["corner_radius_top_left","corner_radius_top_right","corner_radius_bottom_left","corner_radius_bottom_right"]:
		sn.set(corner, 4)
	sn.content_margin_left = 12; sn.content_margin_right = 12
	sn.content_margin_top = 8; sn.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", sn)

	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0.10, 0.14, 0.20, 1)
	sh.border_width_left = 2
	sh.border_color = Color(0.3, 0.6, 1.0, 0.9)
	for corner in ["corner_radius_top_left","corner_radius_top_right","corner_radius_bottom_left","corner_radius_bottom_right"]:
		sh.set(corner, 4)
	sh.content_margin_left = 12; sh.content_margin_right = 12
	sh.content_margin_top = 8; sh.content_margin_bottom = 8
	btn.add_theme_stylebox_override("hover", sh)

	var next_id: String = choice.get("leads_to", "")
	var choice_text: String = choice.get("text", "")
	var unlocks_clue: String = choice.get("unlocks_clue", "")
	var unlocks_contact_id: String = choice.get("unlocks_contact", "")
	var contact_id: String = contact.get("id", "")

	btn.pressed.connect(func():
		if _is_playing:
			return
		_clear_choices()
		choices_label.visible = false
		_add_player_bubble(choice_text, true)
		GameState.append_message(contact_id, "player", choice_text)

		if unlocks_clue != "":
			GameState.discover_clue(unlocks_clue)
		if unlocks_contact_id != "":
			GameState.unlock_contact(unlocks_contact_id)

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
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14; style.content_margin_right = 14
	style.content_margin_top = 9; style.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", style)

	var dots := Label.new()
	dots.text = "···"
	dots.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 1))
	dots.add_theme_font_size_override("font_size", 18)
	bubble.add_child(dots)
	row.add_child(avatar)
	row.add_child(bubble)
	messages_container.add_child(row)
	_typing_indicator = row

	var tween := create_tween().set_loops()
	tween.tween_callback(func(): if is_instance_valid(dots): dots.text = "·  ")
	tween.tween_interval(0.3)
	tween.tween_callback(func(): if is_instance_valid(dots): dots.text = "·· ")
	tween.tween_interval(0.3)
	tween.tween_callback(func(): if is_instance_valid(dots): dots.text = "···")
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

func _add_contact_bubble(text: String, contact: Dictionary, _animate: bool = true) -> void:
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
	style.bg_color = Color(0.09, 0.09, 0.14, 1)
	style.border_width_left = 2
	style.border_color = av_color
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14; style.content_margin_right = 16
	style.content_margin_top = 9; style.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.86, 0.86, 0.92, 1))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_child(lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)

	row.add_child(avatar)
	row.add_child(bubble)
	row.add_child(spacer)
	messages_container.add_child(row)


func _add_player_bubble(text: String, _animate: bool = true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)

	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.15, 0.10, 1)
	style.border_width_right = 2
	style.border_color = Color(0.2, 0.85, 0.45, 0.7)
	style.corner_radius_top_left = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 16; style.content_margin_right = 14
	style.content_margin_top = 9; style.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 0.88, 1))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_child(lbl)

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
	style.content_margin_left = 14; style.content_margin_right = 16
	style.content_margin_top = 9; style.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", style)
	bubble.custom_minimum_size = Vector2(240, 0)

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
				if clue_id not in GameState.discovered_clues:
					GameState.discover_clue(clue_id)
					tap_lbl.text = "  evidence logged"
					tap_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1))
		)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)

	row.add_child(avatar)
	row.add_child(bubble)
	row.add_child(spacer)
	messages_container.add_child(row)


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
