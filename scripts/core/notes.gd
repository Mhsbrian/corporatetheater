extends Control

# Corporate Theater — GHOST Notes
# Auto-populated investigation journal.
# Clues are sorted into tabs by category.
# Each entry shows severity, source, summary.

@onready var tab_bar: HBoxContainer = $VBox/TabBar/TabButtons
@onready var entries_scroll: ScrollContainer = $VBox/EntriesScroll
@onready var entries_container: VBoxContainer = $VBox/EntriesScroll/Entries
@onready var detail_panel: Panel = $VBox/DetailPanel
@onready var detail_title: Label = $VBox/DetailPanel/VBox/Title
@onready var detail_meta: Label = $VBox/DetailPanel/VBox/Meta
@onready var detail_body: Label = $VBox/DetailPanel/VBox/Body
@onready var empty_label: Label = $VBox/EntriesScroll/Entries/EmptyLabel
@onready var count_label: Label = $VBox/Header/CountLabel

var _active_category: String = "all"
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	GameState.note_added.connect(_on_note_added)
	_build_tabs()
	_render_entries()
	detail_panel.visible = false


func _build_tabs() -> void:
	for child in tab_bar.get_children():
		child.queue_free()
	_tab_buttons.clear()

	var all_categories := ["all"] + GameState.CATEGORIES
	for cat in all_categories:
		var label: String = "ALL" if cat == "all" else GameState.CATEGORY_LABELS.get(cat, cat.to_upper()) as String
		var btn := _make_tab_btn(label, cat)
		tab_bar.add_child(btn)
		_tab_buttons[cat] = btn

	_highlight_tab(_active_category)


func _make_tab_btn(label: String, cat: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.65, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.85, 0.85, 1.0, 1))
	btn.pressed.connect(func():
		_active_category = cat
		_highlight_tab(cat)
		_render_entries()
	)
	return btn


func _highlight_tab(cat: String) -> void:
	for c in _tab_buttons:
		var btn: Button = _tab_buttons[c]
		if c == cat:
			btn.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6, 1))
		else:
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.65, 1))


func _on_note_added(_note: Dictionary) -> void:
	_build_tabs()
	_render_entries()


func _render_entries() -> void:
	for child in entries_container.get_children():
		child.queue_free()
	detail_panel.visible = false

	var all_notes: Array = GameState.notes
	var filtered: Array = []

	for note in all_notes:
		if _active_category == "all" or note.get("category", "") == _active_category:
			filtered.append(note)

	# Sort by severity: critical > high > medium > low
	var severity_order := {"critical": 0, "high": 1, "medium": 2, "low": 3}
	filtered.sort_custom(func(a, b):
		return severity_order.get(a.get("severity","low"), 3) < severity_order.get(b.get("severity","low"), 3)
	)

	count_label.text = "%d entries" % filtered.size()

	if filtered.is_empty():
		var lbl := Label.new()
		lbl.text = "no entries in this category yet.\nkeep digging."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.25, 0.25, 0.35, 1))
		lbl.add_theme_font_size_override("font_size", 12)
		entries_container.add_child(lbl)
		return

	for note in filtered:
		entries_container.add_child(_build_entry_card(note))


func _build_entry_card(note: Dictionary) -> Control:
	var severity: String = note.get("severity", "low")
	var sev_color := Color.from_string(
		GameState.SEVERITY_COLORS.get(severity, "#666688"), Color.GRAY)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 1)
	style.border_width_left = 3
	style.border_color = sev_color
	style.border_width_bottom = 1
	style.border_color_bottom = Color(0.1, 0.1, 0.18, 1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.09, 0.09, 0.14, 1)
	hover_style.border_width_left = 3
	hover_style.border_color = sev_color
	hover_style.content_margin_left = 14
	hover_style.content_margin_right = 14
	hover_style.content_margin_top = 10
	hover_style.content_margin_bottom = 10

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var top_row := HBoxContainer.new()

	var sev_label := Label.new()
	sev_label.text = severity.to_upper()
	sev_label.add_theme_color_override("font_color", sev_color)
	sev_label.add_theme_font_size_override("font_size", 9)
	sev_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cat_label := Label.new()
	cat_label.text = GameState.CATEGORY_LABELS.get(note.get("category", ""), "")
	cat_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.5, 1))
	cat_label.add_theme_font_size_override("font_size", 9)

	top_row.add_child(sev_label)
	top_row.add_child(cat_label)

	var title_lbl := Label.new()
	title_lbl.text = note.get("title", "")
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.94, 1))
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var source_lbl := Label.new()
	source_lbl.text = "source: " + note.get("source", "unknown")
	source_lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.5, 1))
	source_lbl.add_theme_font_size_override("font_size", 10)

	vbox.add_child(top_row)
	vbox.add_child(title_lbl)
	vbox.add_child(source_lbl)
	panel.add_child(vbox)

	# Click to show detail
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(note, sev_color)
	)

	return panel


func _show_detail(note: Dictionary, sev_color: Color) -> void:
	detail_panel.visible = true
	detail_title.text = note.get("title", "")
	detail_title.add_theme_color_override("font_color", sev_color)
	detail_meta.text = "%s  ·  %s  ·  logged %s" % [
		note.get("severity", "").to_upper(),
		note.get("source", ""),
		note.get("timestamp", "").substr(0, 16)
	]
	detail_body.text = note.get("summary", "")
