extends Control

# Corporate Theater — Intro Sequence
# Simulates the desktop booting, Z Messenger opening, a notification arriving,
# a simulated cursor clicking it, then a live back-and-forth conversation
# between GHOST (player, right-aligned) and ELENA (left-aligned).
# After the last system message a flashing "PRESS SPACE TO CONTINUE" prompt
# appears and the sequence pauses until Space/Enter is pressed.
# The title card features a bastardised ClosedAI logo (rotating green bloom).

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

# "Press Space" prompt — created dynamically
var _press_space_label: Label = null

# Bubble StyleBoxes — built once
var _style_elena:  StyleBoxFlat
var _style_ghost:  StyleBoxFlat

# ── Input state ──────────────────────────────────────────────────────────────
# Phase 1 (conversation): Space/Enter/Esc skips to end of conversation
# Phase 2 (after conversation): Space/Enter advances past the "press space" gate
# Phase 3 (title card): disabled (we let the tween finish)
enum _Phase { CONVERSATION, WAITING_SPACE, TITLE, DONE }
var _phase: _Phase = _Phase.CONVERSATION
# Tracks which conversation step we are at so skip renders remaining correctly
var _conv_step: int = 0
var _conv_skip := false          # set true → _elena/_ghost finish instantly
var _space_signal := false       # set true → _wait_for_space() unblocks

# Conversation steps — index into this array to know what still needs rendering
# Each entry: [type, text]  where type is "e" (elena), "g" (ghost), "s" (system)
# "slow" elena messages use type "E"
const CONV: Array = [
	["e", "I don't have long. They monitor outbound traffic on Tuesdays."],
	["e", "You've been asking questions in the right places. I've seen your handle."],
	["g", "Who are you."],
	["e", "Someone who's been inside long enough to know what they're actually building."],
	["e", "The Safety Compact Maxwell signed this morning."],
	["g", "What about it."],
	["e", "It's performance. The real project — the one running underneath — doesn't get announced."],
	["e", "It's called Horizon. Government contract. CAI-GOV-0091-HS. The team is completely siloed."],
	["g", "How do I find it."],
	["e", "Their public API has a legacy endpoint that was never properly deprecated."],
	["e", "Start there. And be fast. If they notice your traffic pattern you'll have about four minutes."],
	["s", "[ encryption key exchanged ]"],
	["E", "One more thing."],
	["E", "There are others who left. They signed things, took money. But some of them are still watching."],
	["g", "Send me names."],
	["E", "When you've proven you can handle what you already have."],
	["E", "Don't come back to this address. I'll find you."],
	["s", "[ Elena V. has left the conversation ]"],
]

# Elena contact colour
const ELENA_COLOR := Color(0.4, 0.85, 0.65, 1)
const TYPING_DELAY_PER_CHAR := 0.038
const TYPING_MIN := 0.9

var _typing_node: Control = null

# ── Logo (ClosedAI bastardised bloom) ────────────────────────────────────────
var _logo_node: Control = null
var _logo_angle: float  = 0.0
var _logo_wobble: float = 0.0
var _logo_active := false


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


func _process(delta: float) -> void:
	if not _logo_active:
		return
	_logo_angle  += delta * 0.22
	_logo_wobble += delta * 1.1
	if _logo_node != null and is_instance_valid(_logo_node):
		_logo_node.queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if not key.keycode in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
		return

	match _phase:
		_Phase.CONVERSATION:
			_conv_skip = true
			_phase = _Phase.WAITING_SPACE
		_Phase.WAITING_SPACE:
			_space_signal = true
		_Phase.TITLE, _Phase.DONE:
			pass


# ── Main sequence ──────────────────────────────────────────────────────────────

func _run() -> void:
	# 1 — Desktop fades in: taskbar visible, app not yet open
	taskbar.visible = true
	taskbar.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(taskbar, "modulate:a", 1.0, 0.6)
	await tw.finished
	await _wait(0.8)
	if _conv_skip: await _finish_remaining_conv(); return

	# 2 — Narration: time stamp
	await _narrate("It's 02:47. You haven't slept.")
	await _wait(0.3)
	if _conv_skip: await _finish_remaining_conv(); return

	# 3 — App window opens (messenger)
	app_window.modulate.a = 0.0
	app_window.visible = true
	tw = create_tween()
	tw.tween_property(app_window, "modulate:a", 1.0, 0.5)
	await tw.finished
	await _wait(0.6)
	if _conv_skip: await _finish_remaining_conv(); return

	# 4 — Notification badge pulses on Elena's row
	notif_badge.visible = true
	notif_badge.modulate.a = 0.0
	tw = create_tween()
	tw.tween_property(notif_badge, "modulate:a", 1.0, 0.3)
	await tw.finished
	for _i in range(2):
		tw = create_tween()
		tw.tween_property(notif_badge, "scale", Vector2(1.3, 1.3), 0.15)
		tw.tween_property(notif_badge, "scale", Vector2(1.0, 1.0), 0.15)
		await tw.finished
	await _wait(0.5)
	if _conv_skip: await _finish_remaining_conv(); return

	# 5 — Simulated cursor moves to Elena's row and clicks
	await _cursor_move_to_node(elena_row)
	await _wait(0.15)
	tw = create_tween()
	tw.tween_property(elena_row, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.07)
	tw.tween_property(elena_row, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.12)
	await tw.finished
	sim_cursor.visible = false
	if _conv_skip: await _finish_remaining_conv(); return

	# 6 — Chat panel opens: clear notification, show header
	_open_chat_panel()
	tw = create_tween()
	tw.tween_property(chat_header, "modulate:a", 1.0, 0.35)
	await tw.finished

	msg_scroll.modulate.a = 0.0
	msg_scroll.visible    = true
	tw = create_tween()
	tw.tween_property(msg_scroll, "modulate:a", 1.0, 0.3)
	await tw.finished
	await _wait(0.4)
	if _conv_skip: await _finish_remaining_conv(); return

	# 7 — Conversation — driven by CONV array; _conv_step tracks position
	for i in range(CONV.size()):
		_conv_step = i
		if _conv_skip: await _finish_remaining_conv(); return
		var entry: Array = CONV[i] as Array
		var kind: String = entry[0] as String
		var text: String = entry[1] as String
		match kind:
			"e": await _elena(text)
			"E": await _elena_slow(text)
			"g": await _ghost(text)
			"s": await _system_msg(text)
		if _conv_skip: await _finish_remaining_conv(); return
	_conv_step = CONV.size()  # all done

	await _wait(1.8)

	# 8 — "Press space to continue" gate
	await _wait_for_space()

	# 9 — Title card
	_phase = _Phase.TITLE
	await _show_title()

	_finish()


# Opens the chat panel (idempotent)
func _open_chat_panel() -> void:
	notif_badge.visible = false
	empty_state.visible = false
	chat_header.modulate.a = 0.0
	chat_header.visible = true
	contact_name.text   = "Elena V."
	contact_status.text = "● online"
	contact_role.text   = "Senior Safety Engineer, ClosedAI"


# Renders any conversation entries not yet shown, then falls into the space gate.
# Called when _conv_skip fires mid-sequence.
func _finish_remaining_conv() -> void:
	_hide_typing()

	# Make sure the app / chat panel is visible
	if not app_window.visible:
		app_window.visible    = true
		app_window.modulate.a = 1.0
	if not chat_header.visible:
		_open_chat_panel()
		chat_header.modulate.a = 1.0
	if not msg_scroll.visible:
		msg_scroll.visible    = true
		msg_scroll.modulate.a = 1.0

	# Dump remaining CONV entries that haven't been shown yet.
	# _conv_step is the index of the last message that was dispatched,
	# so start from _conv_step + 1.
	for i in range(_conv_step + 1, CONV.size()):
		var entry: Array = CONV[i] as Array
		var kind: String = entry[0] as String
		var text: String = entry[1] as String
		match kind:
			"e", "E": _add_bubble(text, false)
			"g":       _add_bubble(text, true)
			"s":       _add_system_bubble(text)

	await _scroll_bottom()
	_phase = _Phase.WAITING_SPACE
	await _wait_for_space()
	_phase = _Phase.TITLE
	await _show_title()
	_finish()


# ── "Press SPACE to continue" gate ────────────────────────────────────────────

func _wait_for_space() -> void:
	_phase = _Phase.WAITING_SPACE
	skip_hint.modulate.a = 0.0

	# Build the prompt label if not already present
	if _press_space_label == null:
		_press_space_label = Label.new()
		_press_space_label.text = "PRESS  SPACE  TO  CONTINUE"
		_press_space_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_press_space_label.add_theme_color_override("font_color", Color(0.25, 0.85, 0.45, 1))
		_press_space_label.add_theme_font_size_override("font_size", 11)
		_press_space_label.modulate.a = 0.0
		_press_space_label.layout_mode = 1
		_press_space_label.anchors_preset = Control.PRESET_BOTTOM_WIDE
		_press_space_label.anchor_top    = 1.0
		_press_space_label.anchor_bottom = 1.0
		_press_space_label.offset_top    = -28.0
		_press_space_label.offset_bottom = -6.0
		add_child(_press_space_label)

	# Fade in
	var tw := create_tween()
	tw.tween_property(_press_space_label, "modulate:a", 1.0, 0.5)
	await tw.finished

	# Blink until space pressed
	_space_signal = false
	var blink_tween := create_tween().set_loops()
	blink_tween.tween_property(_press_space_label, "modulate:a", 0.25, 0.55)
	blink_tween.tween_property(_press_space_label, "modulate:a", 1.0,  0.55)

	while not _space_signal:
		await get_tree().process_frame

	blink_tween.kill()

	# Fade out
	tw = create_tween()
	tw.tween_property(_press_space_label, "modulate:a", 0.0, 0.3)
	await tw.finished


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


# ── Conversation helpers ───────────────────────────────────────────────────────

func _elena(text: String) -> void:
	if _conv_skip:
		_hide_typing()
		_add_bubble(text, false)
		return
	var typing_time := clampf(text.length() * TYPING_DELAY_PER_CHAR, TYPING_MIN, 4.0)
	_show_typing()
	await _scroll_bottom()
	await _wait(typing_time)
	_hide_typing()
	_add_bubble(text, false)
	await _scroll_bottom()
	await _wait(0.45)


# Slower post-bubble pause (1.4 s) for closing messages
func _elena_slow(text: String) -> void:
	if _conv_skip:
		_hide_typing()
		_add_bubble(text, false)
		return
	var typing_time := clampf(text.length() * TYPING_DELAY_PER_CHAR, TYPING_MIN, 4.0)
	_show_typing()
	await _scroll_bottom()
	await _wait(typing_time)
	_hide_typing()
	_add_bubble(text, false)
	await _scroll_bottom()
	await _wait(1.4)


func _ghost(text: String) -> void:
	if _conv_skip:
		_add_bubble(text, true)
		return
	await _wait(0.3)
	_add_bubble(text, true)
	await _scroll_bottom()
	await _wait(0.6)


func _system_msg(text: String) -> void:
	_add_system_bubble(text)
	await _scroll_bottom()
	await _wait(0.6)


func _add_system_bubble(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.28, 0.28, 0.42, 1))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_container.add_child(lbl)


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
	if sim_cursor.position == Vector2.ZERO:
		sim_cursor.position = Vector2(get_viewport_rect().size.x * 0.75, get_viewport_rect().size.y * 0.85)

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


# ── Title card ─────────────────────────────────────────────────────────────────

func _show_title() -> void:
	# Fade desktop to black
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(app_window, "modulate:a", 0.0, 0.8)
	tw.tween_property(taskbar,    "modulate:a", 0.0, 0.8)
	await tw.finished

	# Build the logo DrawNode and add it to TitleVBox (below SubtitleLabel)
	_logo_node = Control.new()
	_logo_node.name = "LogoDrawNode"
	_logo_node.custom_minimum_size = Vector2(120, 120)
	_logo_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_logo_node.modulate.a = 0.0
	_logo_node.draw.connect(_draw_logo)
	title_layer.get_node("TitleVBox").add_child(_logo_node)

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
	await _wait(0.6)

	# Fade logo in
	_logo_active = true
	tw = create_tween()
	tw.tween_property(_logo_node, "modulate:a", 1.0, 0.9)
	await tw.finished
	await _wait(2.4)

	# Fade everything out together
	tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(title_label,    "modulate:a", 0.0, 0.8)
	tw.tween_property(subtitle_label, "modulate:a", 0.0, 0.8)
	tw.tween_property(_logo_node,     "modulate:a", 0.0, 0.8)
	await tw.finished
	_logo_active = false


# ── Logo draw callback ─────────────────────────────────────────────────────────
# Draws a bastardised OpenAI bloom — 6 rectangular arms rotated 60° apart,
# one arm slightly longer (imperfection), slow overall rotation + sine wobble.

func _draw_logo() -> void:
	if _logo_node == null or not is_instance_valid(_logo_node):
		return

	var center := _logo_node.size * 0.5
	var base_color := Color(0.2, 1.0, 0.4, 1.0)
	var arm_half_w := 5.0
	var arm_length := 36.0

	for i in range(6):
		var angle := _logo_angle + (i * TAU / 6.0)
		var extra := 0.0
		if i == 2:
			extra = 4.0                           # permanently longer arm
		if i == 0:
			extra += sin(_logo_wobble * 0.7) * 2.5  # subtle sine wobble

		var length := arm_length + extra
		var xform := Transform2D(angle, center)
		_logo_node.draw_set_transform_matrix(xform)
		_logo_node.draw_rect(Rect2(-arm_half_w, -length, arm_half_w * 2.0, length), base_color, true)
		_logo_node.draw_set_transform_matrix(Transform2D.IDENTITY)

	# Central circle to blend arm roots
	_logo_node.draw_circle(center, arm_half_w * 1.2, base_color)


# ── Finish ─────────────────────────────────────────────────────────────────────

func _finish() -> void:
	_phase = _Phase.DONE
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
	if _conv_skip and t > 0.05:
		return
	await get_tree().create_timer(t).timeout
