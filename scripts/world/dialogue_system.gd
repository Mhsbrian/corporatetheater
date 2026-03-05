extends Control

# Corporate Theater — DialogueSystem
# Octopath Traveler-style dialogue overlay.
# Instantiated as a child of outside.gd or location_interior.gd.
# Call start(npc_id, npc_color) to begin.
# Emits dialogue_finished when the tree ends.

signal dialogue_finished

const DIALOGUES_PATH := "res://data/world/dialogues.json"
const TYPEWRITER_SPEED := 0.03   # seconds per character

# ── Layout constants ──────────────────────────────────────────────────────────

const LETTERBOX_H := 80.0        # height of each black bar
const PORTRAIT_SIZE := 80.0
const TEXT_BOX_H := 160.0

# ── State ─────────────────────────────────────────────────────────────────────

var _dialogues: Dictionary = {}
var _npc_id: String = ""
var _npc_color: Color = Color(0.5, 0.8, 1.0)
var _current_node_id: String = ""
var _current_node: Dictionary = {}
var _typewriter_timer: float = 0.0
var _typewriter_index: int = 0
var _full_text: String = ""
var _typewriter_done: bool = false

# ── Nodes (built in _build_ui) ────────────────────────────────────────────────

var _top_bar: ColorRect
var _bot_bar: ColorRect
var _portrait_rect: ColorRect
var _speaker_label: Label
var _text_label: Label
var _choices_container: VBoxContainer
var _tint_overlay: ColorRect


func _ready() -> void:
	_load_dialogues()
	_build_ui()
	mouse_filter = Control.MOUSE_FILTER_STOP


# Safe string coercion — JSON nulls come in as null, not ""
func _str(v: Variant) -> String:
	if v == null:
		return ""
	return str(v)


func _load_dialogues() -> void:
	if not FileAccess.file_exists(DIALOGUES_PATH):
		return
	var file := FileAccess.open(DIALOGUES_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var root: Dictionary = json.data
		_dialogues = root.get("dialogues", {}) as Dictionary


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Atmosphere tint (subtle purple-black overlay over the scene)
	_tint_overlay = ColorRect.new()
	_tint_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint_overlay.color = Color(0.0, 0.0, 0.08, 0.65)
	add_child(_tint_overlay)

	# Top letterbox bar
	_top_bar = ColorRect.new()
	_top_bar.set_anchor_and_offset(SIDE_LEFT, 0.0, 0.0)
	_top_bar.set_anchor_and_offset(SIDE_RIGHT, 1.0, 0.0)
	_top_bar.set_anchor_and_offset(SIDE_TOP, 0.0, 0.0)
	_top_bar.set_anchor_and_offset(SIDE_BOTTOM, 0.0, LETTERBOX_H)
	_top_bar.color = Color(0.0, 0.0, 0.0, 1.0)
	add_child(_top_bar)

	# Bottom letterbox bar (holds portrait + speaker + text + choices)
	_bot_bar = ColorRect.new()
	_bot_bar.set_anchor_and_offset(SIDE_LEFT, 0.0, 0.0)
	_bot_bar.set_anchor_and_offset(SIDE_RIGHT, 1.0, 0.0)
	_bot_bar.set_anchor_and_offset(SIDE_TOP, 1.0, -(TEXT_BOX_H + LETTERBOX_H))
	_bot_bar.set_anchor_and_offset(SIDE_BOTTOM, 1.0, 0.0)
	_bot_bar.color = Color(0.0, 0.0, 0.0, 0.92)
	add_child(_bot_bar)

	# Portrait (colored rect, left side of bot bar)
	_portrait_rect = ColorRect.new()
	_portrait_rect.set_anchor_and_offset(SIDE_LEFT, 0.0, 20.0)
	_portrait_rect.set_anchor_and_offset(SIDE_RIGHT, 0.0, 20.0 + PORTRAIT_SIZE)
	_portrait_rect.set_anchor_and_offset(SIDE_TOP, 1.0, -(TEXT_BOX_H + LETTERBOX_H - 20.0))
	_portrait_rect.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -(LETTERBOX_H - 20.0 + (TEXT_BOX_H - PORTRAIT_SIZE - 20.0)))
	_portrait_rect.color = _npc_color
	add_child(_portrait_rect)

	# Speaker name label (above portrait / top-left of bot bar)
	_speaker_label = Label.new()
	_speaker_label.set_anchor_and_offset(SIDE_LEFT, 0.0, 20.0)
	_speaker_label.set_anchor_and_offset(SIDE_RIGHT, 0.5, 0.0)
	_speaker_label.set_anchor_and_offset(SIDE_TOP, 1.0, -(TEXT_BOX_H + LETTERBOX_H + 2.0))
	_speaker_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -(TEXT_BOX_H + LETTERBOX_H - 22.0))
	_speaker_label.add_theme_color_override("font_color", _npc_color)
	_speaker_label.add_theme_font_size_override("font_size", 13)
	_speaker_label.text = ""
	add_child(_speaker_label)

	# Main text label
	_text_label = Label.new()
	_text_label.set_anchor_and_offset(SIDE_LEFT, 0.0, PORTRAIT_SIZE + 36.0)
	_text_label.set_anchor_and_offset(SIDE_RIGHT, 1.0, -20.0)
	_text_label.set_anchor_and_offset(SIDE_TOP, 1.0, -(TEXT_BOX_H + LETTERBOX_H - 16.0))
	_text_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -(LETTERBOX_H + 56.0))
	_text_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92, 1.0))
	_text_label.add_theme_font_size_override("font_size", 13)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.text = ""
	add_child(_text_label)

	# Choices container (bottom of bot bar)
	_choices_container = VBoxContainer.new()
	_choices_container.set_anchor_and_offset(SIDE_LEFT, 0.0, PORTRAIT_SIZE + 36.0)
	_choices_container.set_anchor_and_offset(SIDE_RIGHT, 1.0, -20.0)
	_choices_container.set_anchor_and_offset(SIDE_TOP, 1.0, -(LETTERBOX_H + 54.0))
	_choices_container.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -12.0)
	_choices_container.add_theme_constant_override("separation", 4)
	add_child(_choices_container)


# ── Public API ────────────────────────────────────────────────────────────────

func start(npc_id: String, npc_color_hex: String) -> void:
	_npc_id = npc_id
	_npc_color = Color.from_string(npc_color_hex, Color(0.5, 0.8, 1.0))
	_portrait_rect.color = _npc_color
	_speaker_label.add_theme_color_override("font_color", _npc_color)

	var npc_data: Dictionary = _dialogues.get(npc_id, {}) as Dictionary
	if npc_data.is_empty():
		emit_signal("dialogue_finished")
		return

	var start_node_id: String = ""
	if GameState.has_met(npc_id):
		start_node_id = _str(npc_data.get("already_met_node"))
	else:
		# Check requires_digital_clue
		var req: String = _str(npc_data.get("requires_digital_clue"))
		if req != "" and not (req in GameState.discovered_clues):
			# Shouldn't get here if gating is correct, but bail gracefully
			emit_signal("dialogue_finished")
			return
		start_node_id = _str(npc_data.get("start_node"))

	if start_node_id == "":
		emit_signal("dialogue_finished")
		return

	_show_node(start_node_id)


func _show_node(node_id: String) -> void:
	var npc_data: Dictionary = _dialogues.get(_npc_id, {}) as Dictionary
	var nodes: Dictionary = npc_data.get("nodes", {}) as Dictionary
	_current_node = nodes.get(node_id, {}) as Dictionary
	_current_node_id = node_id

	if _current_node.is_empty():
		_finish()
		return

	# Clear choices
	for child in _choices_container.get_children():
		child.queue_free()

	_speaker_label.text = _str(_current_node.get("speaker"))
	_full_text = _str(_current_node.get("text"))
	_text_label.text = ""
	_typewriter_index = 0
	_typewriter_done = false
	_typewriter_timer = 0.0


func _process(delta: float) -> void:
	if _full_text == "":
		return
	if _typewriter_done:
		return

	_typewriter_timer += delta
	while _typewriter_timer >= TYPEWRITER_SPEED and _typewriter_index < _full_text.length():
		_typewriter_timer -= TYPEWRITER_SPEED
		_typewriter_index += 1
		_text_label.text = _full_text.substr(0, _typewriter_index)

	if _typewriter_index >= _full_text.length():
		_typewriter_done = true
		_show_choices()


func _show_choices() -> void:
	var choices: Array = _current_node.get("choices", []) as Array
	for choice in choices:
		var c: Dictionary = choice as Dictionary
		var btn := Button.new()
		btn.text = "> " + _str(c.get("text"))
		btn.flat = true
		btn.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		btn.add_theme_font_size_override("font_size", 12)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var next_id: String = _str(c.get("next"))
		btn.pressed.connect(func(): _on_choice(next_id))
		_choices_container.add_child(btn)


func _on_choice(next_id: String) -> void:
	# Clear choices immediately
	for child in _choices_container.get_children():
		child.queue_free()

	if next_id == "" or next_id == null:
		_finish()
		return

	_show_node(next_id)


func _finish() -> void:
	# Process on_complete from the last node shown
	var on_complete_v = _current_node.get("on_complete")
	if on_complete_v != null and on_complete_v is Dictionary:
		var on_complete: Dictionary = on_complete_v as Dictionary
		var clue_id: String = _str(on_complete.get("discover_clue"))
		if clue_id != "":
			GameState.discover_clue(clue_id)
		var met_id: String = _str(on_complete.get("set_met"))
		if met_id != "":
			GameState.meet_contact_in_person(met_id)

	emit_signal("dialogue_finished")


# ── Input — space/enter skips typewriter or advances if done ──────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _full_text == "":
		return
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
			if not _typewriter_done:
				# Skip to end
				_typewriter_index = _full_text.length()
				_text_label.text = _full_text
				_typewriter_done = true
				_show_choices()
			get_viewport().set_input_as_handled()
