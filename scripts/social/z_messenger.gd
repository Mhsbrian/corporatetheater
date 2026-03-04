extends Control

# Corporate Theater — Z Messenger
# Direct messages with ClosedAI insiders who are cracking.
# Conversation trees branch based on player choices.
# Clues are unlocked through dialogue.

signal clue_discovered(clue_id: String)
signal contact_unlocked(contact_id: String)

const MESSENGER_DATA_PATH := "res://data/posts/z_messenger.json"

@onready var contact_list: VBoxContainer = $Split/ContactPanel/Scroll/ContactList
@onready var chat_header_name: Label = $Split/ChatPanel/Header/Name
@onready var chat_header_status: Label = $Split/ChatPanel/Header/Status
@onready var chat_header_role: Label = $Split/ChatPanel/Header/Role
@onready var messages_container: VBoxContainer = $Split/ChatPanel/MessagesScroll/Messages
@onready var choices_container: VBoxContainer = $Split/ChatPanel/ChoicesPanel/Choices
@onready var empty_state: Label = $Split/ChatPanel/EmptyState
@onready var messages_scroll: ScrollContainer = $Split/ChatPanel/MessagesScroll

var _contacts: Array = []
var _active_contact: Dictionary = {}
var _active_conversation_id: String = ""
var _discovered_clues: Array[String] = []
var _unlocked_contacts: Array[String] = ["elena_vasquez"]
var _conversation_states: Dictionary = {}


func _ready() -> void:
	_load_contacts()
	_build_contact_list()


func _load_contacts() -> void:
	if not FileAccess.file_exists(MESSENGER_DATA_PATH):
		return
	var file := FileAccess.open(MESSENGER_DATA_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_contacts = json.data.get("contacts", [])


func _build_contact_list() -> void:
	for child in contact_list.get_children():
		child.queue_free()

	for contact in _contacts:
		var contact_id: String = contact.get("id", "")
		var is_unlocked: bool = contact_id in _unlocked_contacts

		var btn := _build_contact_button(contact, is_unlocked)
		contact_list.add_child(btn)


func _build_contact_button(contact: Dictionary, is_unlocked: bool) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	# Avatar dot
	var dot := ColorRect.new()
	var av_color := Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)
	dot.color = av_color if is_unlocked else Color(0.25, 0.25, 0.3, 1)
	dot.custom_minimum_size = Vector2(10, 10)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_lbl := Label.new()
	name_lbl.text = contact.get("display_name", "") if is_unlocked else "[ LOCKED ]"
	name_lbl.add_theme_color_override("font_color",
		Color(0.88, 0.88, 0.92, 1) if is_unlocked else Color(0.3, 0.3, 0.35, 1))
	name_lbl.add_theme_font_size_override("font_size", 12)

	var handle_lbl := Label.new()
	handle_lbl.text = contact.get("handle", "") if is_unlocked else "unlock through investigation"
	handle_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	handle_lbl.add_theme_font_size_override("font_size", 10)

	vbox.add_child(name_lbl)
	vbox.add_child(handle_lbl)
	hbox.add_child(dot)
	hbox.add_child(vbox)
	panel.add_child(hbox)

	if is_unlocked:
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_open_contact(contact)
		)

	return panel


func _open_contact(contact: Dictionary) -> void:
	_active_contact = contact
	empty_state.visible = false
	chat_header_name.text = contact.get("display_name", "")
	chat_header_status.text = "● " + contact.get("status", "offline")
	chat_header_role.text = contact.get("role", "")

	var status_color := Color(0.3, 0.8, 0.4, 1) if contact.get("status") == "online" else Color(0.5, 0.5, 0.3, 1)
	chat_header_status.add_theme_color_override("font_color", status_color)

	_clear_messages()
	_clear_choices()

	var contact_id: String = contact.get("id", "")
	var saved_state: String = _conversation_states.get(contact_id, "")

	if saved_state == "":
		# Start fresh — find the trigger:"start" conversation
		var start_conv := _find_conversation(contact, "start")
		if start_conv:
			await _play_conversation(contact, start_conv)
	else:
		# Resume from saved state
		var conv := _find_conversation_by_id(contact, saved_state)
		if conv:
			_show_choices(contact, conv)


func _find_conversation(contact: Dictionary, trigger: String) -> Dictionary:
	for conv in contact.get("conversations", []):
		if conv.get("trigger", "") == trigger:
			return conv
	return {}


func _find_conversation_by_id(contact: Dictionary, id: String) -> Dictionary:
	for conv in contact.get("conversations", []):
		if conv.get("id", "") == id:
			return conv
	return {}


func _play_conversation(contact: Dictionary, conv: Dictionary) -> void:
	_clear_choices()
	var contact_id: String = contact.get("id", "")
	_conversation_states[contact_id] = conv.get("id", "")

	for msg in conv.get("messages", []):
		var delay: float = msg.get("delay", 1.0)
		await get_tree().create_timer(delay * 0.6).timeout

		if msg.get("is_attachment", false):
			_add_attachment_bubble(msg, contact)
		elif msg.get("from", "") == "player":
			_add_player_bubble(msg.get("text", ""))
		else:
			_add_contact_bubble(msg.get("text", ""), contact)

		_scroll_to_bottom()

	# Check for clues unlocked by this conversation
	var unlocks: String = conv.get("unlocks_clue", "")
	if unlocks != "" and unlocks not in _discovered_clues:
		_discovered_clues.append(unlocks)
		emit_signal("clue_discovered", unlocks)
		_add_system_bubble("[ CLUE DISCOVERED: " + unlocks + " ]")

	var unlocks_contact: String = conv.get("unlocks_contact", "")
	if unlocks_contact != "" and unlocks_contact not in _unlocked_contacts:
		_unlocked_contacts.append(unlocks_contact)
		emit_signal("contact_unlocked", unlocks_contact)
		_build_contact_list()
		_add_system_bubble("[ NEW CONTACT AVAILABLE ]")

	# Show player choices
	_show_choices(contact, conv)


func _show_choices(contact: Dictionary, conv: Dictionary) -> void:
	_clear_choices()
	var choices: Array = conv.get("player_choices", [])

	if choices.is_empty():
		return

	for choice in choices:
		var btn := Button.new()
		btn.text = choice.get("text", "")
		btn.flat = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 1))
		btn.add_theme_font_size_override("font_size", 12)

		var next_id: String = choice.get("leads_to", "")
		var choice_text: String = choice.get("text", "")
		var unlocks_clue: String = choice.get("unlocks_clue", "")
		var unlocks_contact_id: String = choice.get("unlocks_contact", "")

		btn.pressed.connect(func():
			_clear_choices()
			_add_player_bubble(choice_text)
			_scroll_to_bottom()

			if unlocks_clue != "" and unlocks_clue not in _discovered_clues:
				_discovered_clues.append(unlocks_clue)
				emit_signal("clue_discovered", unlocks_clue)

			if unlocks_contact_id != "" and unlocks_contact_id not in _unlocked_contacts:
				_unlocked_contacts.append(unlocks_contact_id)
				emit_signal("contact_unlocked", unlocks_contact_id)
				_build_contact_list()

			if next_id != "":
				var next_conv := _find_conversation_by_id(contact, next_id)
				if next_conv:
					await _play_conversation(contact, next_conv)
		)
		choices_container.add_child(btn)


# ── Bubble Builders ───────────────────────────────────────────────────────────

func _add_contact_bubble(text: String, contact: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var dot := ColorRect.new()
	dot.color = Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var bubble := _make_bubble(text, Color(0.09, 0.09, 0.14, 1),
		Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY),
		Color(0.82, 0.82, 0.88, 1), false)

	row.add_child(dot)
	row.add_child(bubble)
	messages_container.add_child(row)


func _add_player_bubble(text: String) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	var bubble := _make_bubble(text, Color(0.08, 0.14, 0.10, 1),
		Color(0.2, 1, 0.4, 0.6), Color(0.88, 0.95, 0.88, 1), true)

	row.add_child(bubble)
	messages_container.add_child(row)


func _add_system_bubble(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	lbl.add_theme_font_size_override("font_size", 10)
	messages_container.add_child(lbl)


func _add_attachment_bubble(msg: Dictionary, contact: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var dot := ColorRect.new()
	dot.color = Color.from_string(contact.get("avatar_color", "#888"), Color.GRAY)
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.07, 1)
	style.border_width_left = 2
	style.border_color = Color(0.2, 1, 0.4, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(200, 0)

	var vbox := VBoxContainer.new()
	var icon_lbl := Label.new()
	icon_lbl.text = "📎 " + msg.get("text", "[file]")
	icon_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6, 1))
	icon_lbl.add_theme_font_size_override("font_size", 11)

	var clue_lbl := Label.new()
	clue_lbl.text = "[ click to examine ]"
	clue_lbl.add_theme_color_override("font_color", Color(0.4, 0.6, 0.4, 1))
	clue_lbl.add_theme_font_size_override("font_size", 10)

	vbox.add_child(icon_lbl)
	vbox.add_child(clue_lbl)
	panel.add_child(vbox)

	var clue_id: String = msg.get("attachment_clue", "")
	if clue_id != "":
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				if clue_id not in _discovered_clues:
					_discovered_clues.append(clue_id)
					emit_signal("clue_discovered", clue_id)
					_add_system_bubble("[ EVIDENCE COLLECTED: " + clue_id + " ]")
		)

	row.add_child(dot)
	row.add_child(panel)
	messages_container.add_child(row)


func _make_bubble(text: String, bg: Color, border: Color, font_color: Color, is_player: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if is_player:
		style.border_width_right = 2
	else:
		style.border_width_left = 2
	style.border_color = border
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6 if is_player else 0
	style.corner_radius_bottom_right = 0 if is_player else 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(80, 0)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(100, 0)
	panel.add_child(lbl)
	return panel


func _clear_messages() -> void:
	for child in messages_container.get_children():
		child.queue_free()


func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	messages_scroll.scroll_vertical = messages_scroll.get_v_scroll_bar().max_value


func unlock_contact(contact_id: String) -> void:
	if contact_id not in _unlocked_contacts:
		_unlocked_contacts.append(contact_id)
		_build_contact_list()
