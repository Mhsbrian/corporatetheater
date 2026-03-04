extends Control

# Corporate Theater — Intro Sequence
# Simulates the desktop booting, Z Messenger opening, a notification arriving,
# a simulated cursor clicking it, then a live back-and-forth conversation
# between GHOST (player, right-aligned) and ELENA (left-aligned).
# Uses the exact same bubble style as the real messenger.

const DESKTOP_SCENE := "res://scenes/ui/desktop.tscn"

# App chrome
@onready var app_window:     Control         = $AppWindow
@onready var taskbar:        Panel           = $Taskbar
@onready var elena_row:      PanelContainer  = $AppWindow/Split/ContactPanel/ContactList/ElenaRow
@onready var notif_badge:    PanelContainer  = $AppWindow/Split/ContactPanel/ContactList/ElenaRow/NotifBadge
@onready var empty_state:    Label           = $AppWindow/Split/ChatPanel/EmptyState
@onready var chat_header:    Panel           = $AppWindow/Split/ChatPanel/ChatHeader
@onready var contact_name:   Label           = $AppWindow/Split/ChatPanel/ChatHeader/HeaderVBox/ContactName
@onready var contact_status: Label           = $AppWindow/Split/ChatPanel/ChatHeader/HeaderVBox/ContactStatus
@onready var contact_role:   Label           = $AppWindow/Split/ChatPanel/ChatHeader/HeaderVBox/ContactRole
@onready var msg_scroll:     ScrollContainer = $AppWindow/Split/ChatPanel/MessagesScroll
@onready var msg_container:  VBoxContainer   = $AppWindow/Split/ChatPanel/MessagesScroll/Messages

# Simulated cursor
@onready var sim_cursor:     Control         = $SimCursor

# Narration / title / overlay
@onready var narration_bar:  CenterContainer = $NarrationBar
@onready var narration_label: Label          = $NarrationBar/NarrationLabel
@onready var title_layer:    CenterContainer = $TitleLayer
@onready var title_label:    Label           = $TitleLayer/TitleVBox/TitleLabel
@onready var subtitle_label: Label           = $TitleLayer/TitleVBox/SubtitleLabel
@onready var skip_hint:      Label           = $SkipHint
@onready var overlay:        ColorRect       = $Overlay

# Bubble StyleBoxes — built once
var _style_elena:  StyleBoxFlat
var _style_ghost:  StyleBoxFlat
var _style_system: StyleBoxFlat

var _skip_requested := false

# Elena contact colour
const ELENA_COLOR := Color(0.4, 0.85, 0.65, 1)
const TYPING_DELAY_PER_CHAR := 0.038
const TYPING_MIN := 0.9

var _typing_node: Control = null


func _ready() -> void:
	_build_styles()
	overlay.modulate.a = 1.0
	app_window.visible = false
	taskbar.visible    = false
	narration_bar.visible = false
	title_layer.visible   = false
	sim_cursor.visible    = false
	skip_hint.modulate.a  = 0.0

	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, 1.8)
	await tw.finished
	skip_hint.modulate.a = 0.35
	await get_tree().create_timer(0.4).timeout
	_run()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
			_skip_requested = true
			_finish()


# ── Styles ─────────────────────────────────────────────────────────────────────

func _build_styles() -> void:
	_style_elena = StyleBoxFlat.new()
	_style_elena.bg_color           = Color(0.09, 0.09, 0.14, 1)
	_style_elena.border_width_left  = 2
	_style_elena.border_color       = ELENA_COLOR
	_style_elena.corner_radius_top_right    = 10
	_style_elena.corner_radius_bottom_left  = 10
	_style_elena.corner_radius_bottom_right = 10
	_style_elena.content_margin_left   = 14
	_style_elena.content_margin_right  = 16
	_style_elena.content_margin_top    = 9
	_style_elena.content_margin_bottom = 9

	_style_ghost = StyleBoxFlat.new()
	_style_ghost.bg_color           = Color(0.08, 0.15, 0.10, 1)
	_style_ghost.border_width_right = 2
	_style_ghost.border_color       = Color(0.2, 0.85, 0.45, 0.7)
	_style_ghost.corner_radius_top_left     = 10
	_style_ghost.corner_radius_bottom_left  = 10
	_style_ghost.corner_radius_bottom_right = 10
	_style_ghost.content_margin_left   = 16
	_style_ghost.content_margin_right  = 14
	_style_ghost.content_margin_top    = 9
	_style_ghost.content_margin_bottom = 9

	_style_system = StyleBoxFlat.new()
	_style_system.bg_color            = Color(0.0, 0.0, 0.0, 0.0)
	_style_system.content_margin_left = 0
	_style_system.content_margin_right = 0


# ── Main sequence ──────────────────────────────────────────────────────────────

func _run() -> void:
	if _skip_requested: return

	# 1 — Desktop fades in: taskbar visible, app not yet open
	taskbar.visible = true
	taskbar.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(taskbar, "modulate:a", 1.0, 0.6)
	await tw.finished
	await _wait(0.8)
	if _skip_requested: return

	# 2 — Narration: time stamp
	await _narrate("It's 02:47. You haven't slept.")
	await _wait(0.3)
	if _skip_requested: return

	# 3 — App window opens (messenger)
	app_window.modulate.a = 0.0
	app_window.visible = true
	tw = create_tween()
	tw.tween_property(app_window, "modulate:a", 1.0, 0.5)
	await tw.finished
	await _wait(0.6)
	if _skip_requested: return

	# 4 — Notification badge pulses on Elena's row
	notif_badge.visible = true
	notif_badge.modulate.a = 0.0
	tw = create_tween()
	tw.tween_property(notif_badge, "modulate:a", 1.0, 0.3)
	await tw.finished
	# Pulse twice
	for _i in range(2):
		tw = create_tween()
		tw.tween_property(notif_badge, "scale", Vector2(1.3, 1.3), 0.15)
		tw.tween_property(notif_badge, "scale", Vector2(1.0, 1.0), 0.15)
		await tw.finished
	await _wait(0.5)
	if _skip_requested: return

	# 5 — Simulated cursor moves to Elena's row and clicks
	await _cursor_move_to_node(elena_row)
	await _wait(0.15)
	# Flash the row to simulate click
	tw = create_tween()
	tw.tween_property(elena_row, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.07)
	tw.tween_property(elena_row, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
	await tw.finished
	sim_cursor.visible = false
	if _skip_requested: return

	# 6 — Chat panel opens: clear notification, show header
	notif_badge.visible = false
	empty_state.visible = false
	chat_header.modulate.a = 0.0
	chat_header.visible = true
	contact_name.text   = "Elena V."
	contact_status.text = "● online"
	contact_role.text   = "Senior Safety Engineer, ClosedAI"
	tw = create_tween()
	tw.tween_property(chat_header, "modulate:a", 1.0, 0.35)
	await tw.finished

	msg_scroll.modulate.a = 0.0
	msg_scroll.visible    = true
	tw = create_tween()
	tw.tween_property(msg_scroll, "modulate:a", 1.0, 0.3)
	await tw.finished
	await _wait(0.4)
	if _skip_requested: return

	# 7 — Conversation plays out
	await _elena("I don't have long. They monitor outbound traffic on Tuesdays.")
	if _skip_requested: return
	await _elena("You've been asking questions in the right places. I've seen your handle.")
	if _skip_requested: return
	await _ghost("Who are you.")
	if _skip_requested: return
	await _elena("Someone who's been inside long enough to know what they're actually building.")
	if _skip_requested: return
	await _elena("The Safety Compact Maxwell signed this morning.")
	if _skip_requested: return
	await _ghost("What about it.")
	if _skip_requested: return
	await _elena("It's performance. The real project — the one running underneath — doesn't get announced.")
	if _skip_requested: return
	await _elena("It's called Horizon. Government contract. CAI-GOV-0091-HS. The team is completely siloed.")
	if _skip_requested: return
	await _ghost("How do I find it.")
	if _skip_requested: return
	await _elena("Their public API has a legacy endpoint that was never properly deprecated.")
	if _skip_requested: return
	await _elena("Start there. And be fast. If they notice your traffic pattern you'll have about four minutes.")
	if _skip_requested: return
	await _system_msg("[ encryption key exchanged ]")
	await _elena("One more thing.")
	if _skip_requested: return
	await _elena("There are others who left. They signed things, took money. But some of them are still watching.")
	if _skip_requested: return
	await _ghost("Send me names.")
	if _skip_requested: return
	await _elena("When you've proven you can handle what you already have.")
	if _skip_requested: return
	await _elena("Don't come back to this address. I'll find you.")
	if _skip_requested: return
	await _system_msg("[ Elena V. has left the conversation ]")
	await _wait(1.2)
	if _skip_requested: return

	# 8 — Title card
	await _show_title()
	if _skip_requested: return

	_finish()


# ── Conversation helpers ───────────────────────────────────────────────────────

func _elena(text: String) -> void:
	var typing_time := clampf(text.length() * TYPING_DELAY_PER_CHAR, TYPING_MIN, 4.0)
	_show_typing()
	await _scroll_bottom()
	await _wait(typing_time)
	_hide_typing()
	_add_bubble(text, false)
	await _scroll_bottom()
	await _wait(0.45)


func _ghost(text: String) -> void:
	# Ghost replies appear instantly (player action)
	await _wait(0.3)
	_add_bubble(text, true)
	await _scroll_bottom()
	await _wait(0.6)


func _system_msg(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.28, 0.28, 0.42, 1))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_container.add_child(lbl)
	await _scroll_bottom()
	await _wait(0.6)


func _add_bubble(text: String, is_ghost: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(80, 0)
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", _style_ghost if is_ghost else _style_elena)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color",
		Color(0.88, 0.96, 0.88, 1) if is_ghost else Color(0.86, 0.86, 0.92, 1))
	bubble.add_child(lbl)

	# Ghost right-aligned, Elena left-aligned
	if is_ghost:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		var avatar := _make_avatar()
		row.add_child(avatar)
		row.add_child(bubble)
		row.add_child(spacer)

	row.modulate.a = 0.0
	msg_container.add_child(row)
	var tw := create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.2)


func _make_avatar() -> Control:
	var c := ColorRect.new()
	c.color = ELENA_COLOR
	c.custom_minimum_size = Vector2(6, 6)
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return c


func _show_typing() -> void:
	if _typing_node != null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var avatar := _make_avatar()
	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.09, 0.09, 0.14, 1)
	style.border_width_left = 2
	style.border_color      = ELENA_COLOR
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14; style.content_margin_right = 14
	style.content_margin_top  = 9;  style.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", style)

	var dots := Label.new()
	dots.text = "···"
	dots.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6, 1))
	dots.add_theme_font_size_override("font_size", 18)
	bubble.add_child(dots)

	row.add_child(avatar)
	row.add_child(bubble)
	msg_container.add_child(row)
	_typing_node = row

	var tw := create_tween().set_loops()
	tw.tween_callback(func(): if is_instance_valid(dots): dots.text = "·  ")
	tw.tween_interval(0.3)
	tw.tween_callback(func(): if is_instance_valid(dots): dots.text = "·· ")
	tw.tween_interval(0.3)
	tw.tween_callback(func(): if is_instance_valid(dots): dots.text = "···")
	tw.tween_interval(0.3)
	row.set_meta("tween", tw)


func _hide_typing() -> void:
	if _typing_node == null:
		return
	if _typing_node.has_meta("tween"):
		(_typing_node.get_meta("tween") as Tween).kill()
	_typing_node.queue_free()
	_typing_node = null


# ── Cursor simulation ──────────────────────────────────────────────────────────

func _cursor_move_to_node(target: Control) -> void:
	sim_cursor.visible = true
	# Start from bottom-right of screen
	if sim_cursor.position == Vector2.ZERO:
		sim_cursor.position = Vector2(get_viewport_rect().size.x * 0.75, get_viewport_rect().size.y * 0.85)

	# Target: centre of the contact row
	await get_tree().process_frame
	var dest := target.global_position + target.size * 0.5

	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(sim_cursor, "position", dest, 0.55)
	await tw.finished


# ── Narration ──────────────────────────────────────────────────────────────────

func _narrate(text: String, duration: float = 2.2) -> void:
	narration_bar.visible   = true
	narration_label.text    = text
	narration_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(narration_label, "modulate:a", 1.0, 0.4)
	await tw.finished
	await _wait(duration)
	tw = create_tween()
	tw.tween_property(narration_label, "modulate:a", 0.0, 0.4)
	await tw.finished


func _show_title() -> void:
	# Fade desktop to black first
	var tw := create_tween()
	tw.tween_property(app_window, "modulate:a", 0.0, 0.8)
	tw.tween_property(taskbar,    "modulate:a", 0.0, 0.8)
	await tw.finished

	title_layer.visible   = true
	title_label.text      = "CORPORATE THEATER"
	subtitle_label.text   = "the performance is about to begin."
	title_label.modulate.a    = 0.0
	subtitle_label.modulate.a = 0.0

	tw = create_tween()
	tw.tween_property(title_label, "modulate:a", 1.0, 0.8)
	await tw.finished
	await _wait(0.5)
	tw = create_tween()
	tw.tween_property(subtitle_label, "modulate:a", 1.0, 0.6)
	await tw.finished
	await _wait(2.8)

	tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(title_label,    "modulate:a", 0.0, 0.8)
	tw.tween_property(subtitle_label, "modulate:a", 0.0, 0.8)
	await tw.finished


# ── Finish ─────────────────────────────────────────────────────────────────────

func _finish() -> void:
	skip_hint.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 1.0)
	await tw.finished
	get_tree().change_scene_to_file(DESKTOP_SCENE)


func _scroll_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	msg_scroll.scroll_vertical = msg_scroll.get_v_scroll_bar().max_value


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
