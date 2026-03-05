extends Control

# Corporate Theater — DialogueSystem (RPG style)
#
# Full-screen overlay drawn entirely via _draw() to match the iso scene aesthetic.
# Layout (bottom 38% of screen):
#
#   ┌─────────────────────────────────────────────────────────────┐
#   │ [SPEAKER NAME TAB]                                          │
#   ├──────────────┬──────────────────────────────────────────────┤
#   │              │  dialogue text (typewriter)                  │
#   │  NPC face    │                                              │
#   │  portrait    │  > choice 1                                  │
#   │              │  > choice 2                                  │
#   └──────────────┴──────────────────────────────────────────────┘
#
# The portrait is drawn procedurally using the NPC accent colour.
# Choice selection: keyboard 1/2/3 or UP/DOWN + ENTER, or mouse click.

signal dialogue_finished

const DIALOGUES_PATH  := "res://data/world/dialogues.json"
const TYPEWRITER_SPD  := 0.028   # seconds per character

# ── Layout (fractions of screen height / width) ───────────────────────────────
const PANEL_H_FRAC    := 0.38    # panel takes bottom 38 % of screen
const PORTRAIT_W_FRAC := 0.18    # portrait column width
const NAME_TAB_H      := 32.0    # speaker nameplate height above panel

# ── State ─────────────────────────────────────────────────────────────────────
var _dialogues: Dictionary = {}
var _npc_id: String = ""
var _npc_color: Color = Color(0.48, 0.72, 1.0)
var _npc_name: String = ""

var _current_node: Dictionary = {}
var _current_node_id: String = ""

var _full_text: String = ""
var _shown_chars: int = 0
var _tw_timer: float = 0.0
var _tw_done: bool = false

var _choices: Array = []        # Array of {text, next}
var _choice_sel: int = 0        # currently highlighted choice index
var _choices_visible: bool = false

var _size: Vector2 = Vector2.ZERO
var _time: float = 0.0

# Portrait animation
var _portrait_blink: float = 0.0
var _portrait_talk_t: float = 0.0
var _portrait_bob: float = 0.0


# ── Helpers ───────────────────────────────────────────────────────────────────

func _str(v: Variant) -> String:
	if v == null: return ""
	return str(v)


# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_dialogues()
	_size = get_rect().size
	if _size == Vector2.ZERO:
		await get_tree().process_frame
		_size = get_rect().size


func _load_dialogues() -> void:
	if not FileAccess.file_exists(DIALOGUES_PATH):
		return
	var f := FileAccess.open(DIALOGUES_PATH, FileAccess.READ)
	var j := JSON.new()
	if j.parse(f.get_as_text()) == OK:
		_dialogues = (j.data as Dictionary).get("dialogues", {}) as Dictionary


# ── Public API ────────────────────────────────────────────────────────────────

func start(npc_id: String, npc_color_hex: String) -> void:
	_npc_id       = npc_id
	_npc_color    = Color.from_string(npc_color_hex, Color(0.48, 0.72, 1.0))

	var npc_data: Dictionary = _dialogues.get(npc_id, {}) as Dictionary
	if npc_data.is_empty():
		emit_signal("dialogue_finished")
		return

	# Derive display name from first node's speaker field
	var nodes: Dictionary = npc_data.get("nodes", {}) as Dictionary
	var start_node_id := ""
	if GameState.has_met(npc_id):
		start_node_id = _str(npc_data.get("already_met_node"))
	else:
		var req := _str(npc_data.get("requires_digital_clue"))
		if req != "" and not (req in GameState.discovered_clues):
			emit_signal("dialogue_finished")
			return
		start_node_id = _str(npc_data.get("start_node"))

	if start_node_id == "":
		emit_signal("dialogue_finished")
		return

	# Grab speaker name from first node
	var first: Dictionary = nodes.get(start_node_id, {}) as Dictionary
	_npc_name = _str(first.get("speaker"))
	if _npc_name == "": _npc_name = npc_id

	_show_node(start_node_id)


func _show_node(node_id: String) -> void:
	var npc_data: Dictionary = _dialogues.get(_npc_id, {}) as Dictionary
	var nodes: Dictionary = npc_data.get("nodes", {}) as Dictionary
	_current_node    = nodes.get(node_id, {}) as Dictionary
	_current_node_id = node_id

	if _current_node.is_empty():
		_finish()
		return

	_full_text     = _str(_current_node.get("text"))
	_shown_chars   = 0
	_tw_timer      = 0.0
	_tw_done       = false
	_choices_visible = false
	_choices.clear()
	_choice_sel    = 0

	# Update name from node if present
	var sp := _str(_current_node.get("speaker"))
	if sp != "": _npc_name = sp

	queue_redraw()


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_size = get_rect().size
	_time += delta

	# Portrait animation
	_portrait_blink = maxf(0.0, _portrait_blink - delta)
	if not _tw_done:
		_portrait_talk_t += delta * 8.0
	_portrait_bob = sin(_time * 1.6) * 2.0

	# Typewriter
	if not _tw_done and _full_text != "":
		_tw_timer += delta
		while _tw_timer >= TYPEWRITER_SPD and _shown_chars < _full_text.length():
			_tw_timer -= TYPEWRITER_SPD
			_shown_chars += 1
		if _shown_chars >= _full_text.length():
			_tw_done = true
			_choices = _current_node.get("choices", []) as Array
			_choices_visible = true
			_choice_sel = 0

	queue_redraw()


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_SPACE, KEY_ENTER:
				get_viewport().set_input_as_handled()
				if not _tw_done:
					_shown_chars = _full_text.length()
					_tw_done = true
					_choices = _current_node.get("choices", []) as Array
					_choices_visible = true
					_choice_sel = 0
				elif _choices_visible and _choices.size() > 0:
					_commit_choice(_choice_sel)
				elif _tw_done and _choices.size() == 0:
					_finish()
			KEY_UP, KEY_W:
				if _choices_visible and _choices.size() > 0:
					get_viewport().set_input_as_handled()
					_choice_sel = (_choice_sel - 1 + _choices.size()) % _choices.size()
			KEY_DOWN, KEY_S:
				if _choices_visible and _choices.size() > 0:
					get_viewport().set_input_as_handled()
					_choice_sel = (_choice_sel + 1) % _choices.size()
			KEY_1, KEY_KP_1:
				if _choices_visible and _choices.size() >= 1:
					get_viewport().set_input_as_handled()
					_commit_choice(0)
			KEY_2, KEY_KP_2:
				if _choices_visible and _choices.size() >= 2:
					get_viewport().set_input_as_handled()
					_commit_choice(1)
			KEY_3, KEY_KP_3:
				if _choices_visible and _choices.size() >= 3:
					get_viewport().set_input_as_handled()
					_commit_choice(2)
			KEY_ESCAPE:
				# Don't let ESC close the interior while dialogue is open
				get_viewport().set_input_as_handled()

	# Mouse click on choices
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _choices_visible:
			var mpos := mb.position
			var hit := _choice_hit_test(mpos)
			if hit >= 0:
				get_viewport().set_input_as_handled()
				_commit_choice(hit)

	if event is InputEventMouseMotion and _choices_visible:
		var hit := _choice_hit_test((event as InputEventMouseMotion).position)
		if hit >= 0:
			_choice_sel = hit


func _commit_choice(idx: int) -> void:
	if idx < 0 or idx >= _choices.size(): return
	var c: Dictionary = _choices[idx] as Dictionary
	var next := _str(c.get("next"))
	_choices_visible = false
	_choices.clear()
	if next == "":
		_finish()
	else:
		_show_node(next)


# ── Hit-test: returns choice index under screen pos, or -1 ───────────────────

# We store choice rects during _draw for hit-testing
var _choice_rects: Array = []   # Array of Rect2

func _choice_hit_test(pos: Vector2) -> int:
	for i in _choice_rects.size():
		if _choice_rects[i].has_point(pos):
			return i
	return -1


# ── DRAW ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _size == Vector2.ZERO: return
	var W := _size.x
	var H := _size.y

	# ── Scene dim overlay ──
	draw_rect(Rect2(0, 0, W, H), Color(0.0, 0.0, 0.05, 0.55))

	# ── Panel geometry ──
	var ph: float     = H * PANEL_H_FRAC                   # panel height
	var py: float     = H - ph                              # panel top y
	var port_w: float = W * PORTRAIT_W_FRAC                # portrait column width
	var text_x: float = port_w + 28.0                      # text region left
	var text_w: float = W - text_x - 24.0                  # text region width

	# ── Main panel background ──
	_draw_panel_bg(0.0, py, W, ph)

	# ── Speaker name tab ──
	_draw_name_tab(port_w * 0.5 - 4.0, py - NAME_TAB_H, port_w + 80.0, NAME_TAB_H)

	# ── Portrait ──
	_draw_portrait(0.0, py, port_w, ph)

	# ── Separator line ──
	var sep_x := port_w + 10.0
	draw_line(Vector2(sep_x, py + 10.0), Vector2(sep_x, py + ph - 10.0),
			_npc_color.darkened(0.5), 1.0)

	# ── Dialogue text ──
	_draw_text_region(text_x, py + 16.0, text_w, ph - 20.0)

	# ── Scanline + corner accents ──
	_draw_scanlines(0.0, py, W, ph)
	_draw_corner_accents(0.0, py, W, ph)


func _draw_panel_bg(x: float, y: float, w: float, h: float) -> void:
	# Dark base
	draw_rect(Rect2(x, y, w, h), Color(0.03, 0.03, 0.06, 0.97))
	# Top border glow line
	draw_line(Vector2(x, y), Vector2(x + w, y),
			Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.70), 2.0)
	# Subtle inner gradient (two thin rects)
	draw_rect(Rect2(x, y, w, 24.0),
			Color(_npc_color.r * 0.06, _npc_color.g * 0.06, _npc_color.b * 0.08, 0.40))
	draw_rect(Rect2(x, y + h - 4.0, w, 4.0), Color(0.0, 0.0, 0.0, 0.6))


func _draw_name_tab(x: float, y: float, w: float, h: float) -> void:
	# Background
	draw_rect(Rect2(x, y, w, h + 4.0), Color(0.03, 0.03, 0.06, 0.97))
	# Top accent
	draw_line(Vector2(x, y), Vector2(x + w, y),
			Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.60), 1.5)
	# Left accent
	draw_line(Vector2(x, y), Vector2(x, y + h + 4.0),
			Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.35), 1.0)
	# Speaker name text
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(x + 10.0, y + h * 0.72),
			_npc_name.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.95))
	# Small accent diamond
	var dx := x + w - 12.0
	var dy := y + h * 0.5
	var pts := PackedVector2Array()
	pts.append(Vector2(dx - 5, dy))
	pts.append(Vector2(dx, dy - 4))
	pts.append(Vector2(dx + 5, dy))
	pts.append(Vector2(dx, dy + 4))
	draw_colored_polygon(pts, Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.7))


func _draw_portrait(x: float, y: float, w: float, h: float) -> void:
	# Portrait background with subtle gradient
	draw_rect(Rect2(x, y, w, h),
			Color(_npc_color.r * 0.04, _npc_color.g * 0.04, _npc_color.b * 0.06, 1.0))

	# NPC figure — procedural character drawn in screen space
	var cx := x + w * 0.5
	var cy := y + h * 0.82  # feet level
	_draw_npc_portrait(cx, cy)

	# Subtle glow halo behind the figure
	for g in 5:
		var ga := 0.06 - float(g) * 0.01
		draw_circle(Vector2(cx, cy - h * 0.32),
				(w * 0.38 + float(g) * 12.0),
				Color(_npc_color.r, _npc_color.g, _npc_color.b, ga))

	# Right-side soft fade toward separator
	for i in 8:
		var fa := 0.18 - float(i) * 0.02
		draw_rect(Rect2(x + w - 8.0 + float(i), y, 1.0, h),
				Color(0.03, 0.03, 0.06, fa))


func _draw_npc_portrait(cx: float, feet_y: float) -> void:
	# Scale the character to portrait column
	var scale := _size.x * PORTRAIT_W_FRAC / 160.0   # normalise to ~160px wide column
	scale = clampf(scale, 0.8, 1.4)

	var s  := scale
	var bob := _portrait_bob * s
	var talk_bob: float = sin(_portrait_talk_t) * 1.5 * s if not _tw_done else 0.0
	var total_bob := bob + talk_bob
	var flip := 1.0   # faces right (toward text)

	var cloth := _npc_color.darkened(0.45)
	var body  := Color(0.08, 0.08, 0.12, 1.0)
	var skin  := Color(
		clampf(_npc_color.r * 0.55 + 0.22, 0.28, 0.72),
		clampf(_npc_color.g * 0.30 + 0.28, 0.28, 0.65),
		clampf(_npc_color.b * 0.15 + 0.22, 0.20, 0.58),
		1.0)

	# ── Shoes ──
	draw_rect(Rect2(cx - 9*s*flip, feet_y - 6*s, 11*s, 6*s), body)
	draw_rect(Rect2(cx + 1*s*flip, feet_y - 5*s, 10*s, 5*s), body)

	# ── Legs ──
	var ll := cloth.lightened(0.10)
	draw_rect(Rect2(cx - 10*s*flip, feet_y - 28*s + total_bob, 9*s, 24*s), ll)
	draw_rect(Rect2(cx + 2*s*flip,  feet_y - 27*s + total_bob, 9*s, 23*s), cloth)
	draw_rect(Rect2(cx - 8*s*flip,  feet_y - 18*s + total_bob, 5*s, 4*s),
			ll.lightened(0.15))

	# ── Belt ──
	draw_rect(Rect2(cx - 13*s, feet_y - 31*s + total_bob, 26*s, 4*s), body.lightened(0.1))

	# ── Jacket ──
	draw_rect(Rect2(cx - 13*s, feet_y - 60*s + total_bob, 26*s, 31*s), cloth)
	# Lapels
	var lpx := cx - 13*s*flip
	var lp := PackedVector2Array()
	lp.append(Vector2(lpx,          feet_y - 60*s + total_bob))
	lp.append(Vector2(lpx + 7*s*flip, feet_y - 60*s + total_bob))
	lp.append(Vector2(cx,           feet_y - 47*s + total_bob))
	draw_colored_polygon(lp, cloth.darkened(0.25))
	# Collar
	draw_rect(Rect2(cx - 5*s, feet_y - 60*s + total_bob, 10*s, 6*s),
			cloth.lightened(0.08))

	# ── Arms ──
	draw_rect(Rect2(cx - 21*s*flip, feet_y - 57*s + total_bob, 8*s, 22*s), cloth)
	draw_rect(Rect2(cx + 13*s*flip, feet_y - 57*s + total_bob, 8*s, 22*s), cloth)
	# Hands
	draw_circle(Vector2(cx - 17*s*flip, feet_y - 37*s + total_bob), 5*s, skin)
	draw_circle(Vector2(cx + 17*s*flip, feet_y - 37*s + total_bob), 5*s, skin)

	# ── Neck ──
	draw_rect(Rect2(cx - 4*s, feet_y - 67*s + total_bob, 8*s, 8*s), skin)

	# ── Head ──
	draw_circle(Vector2(cx, feet_y - 79*s + total_bob), 13*s, skin)
	# Hair
	draw_rect(Rect2(cx - 13*s, feet_y - 94*s + total_bob, 26*s, 10*s), body)
	draw_rect(Rect2(cx - 13*s, feet_y - 90*s + total_bob, 26*s,  6*s), body.lightened(0.08))
	# Eyes (facing right)
	var ey := feet_y - 80*s + total_bob
	draw_rect(Rect2(cx + 2*s*flip, ey, 5*s, 4*s), Color(0.06, 0.06, 0.10, 1.0))
	draw_rect(Rect2(cx - 7*s*flip, ey, 5*s, 4*s), Color(0.18, 0.18, 0.28, 1.0))

	# Blink (white rect flashes over eye for 0.08s)
	if _portrait_blink > 0.0:
		draw_rect(Rect2(cx + 2*s*flip, ey, 5*s, 4*s), Color(skin.r, skin.g, skin.b, _portrait_blink / 0.08))
		draw_rect(Rect2(cx - 7*s*flip, ey, 5*s, 4*s), Color(skin.r, skin.g, skin.b, _portrait_blink / 0.08))

	# Mouth — slight open when talking
	var mouth_y := feet_y - 73*s + total_bob
	var mouth_open := maxf(0.0, sin(_portrait_talk_t * 1.2)) * 3.0 * s if not _tw_done else 1.0 * s
	draw_rect(Rect2(cx - 4*s, mouth_y, 8*s, 2*s + mouth_open),
			Color(body.r, body.g, body.b, 0.75))

	# Accent item — a small badge / lapel pin glint
	draw_circle(Vector2(cx - 7*s*flip, feet_y - 52*s + total_bob),
			2.5*s, Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.85))


func _draw_text_region(x: float, y: float, w: float, h: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 15
	var line_h := 22.0
	var text_color := Color(0.88, 0.88, 0.92, 1.0)

	# ── Dialogue text (typewriter) ──
	var visible_text := _full_text.substr(0, _shown_chars)
	# Word-wrap manually by using draw_string with max_width
	var text_y := y + 10.0
	_draw_wrapped_text(visible_text, x, text_y, w, font_size, line_h, text_color)

	# Advance indicator (blinking ▼) when typewriter done and no choices or choices visible
	if _tw_done:
		var blink := (sin(_time * 4.5) + 1.0) * 0.5
		if _choices.size() == 0:
			draw_string(font, Vector2(x + w - 18.0, y + h - 28.0),
					"▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(0.6, 0.9, 1.0, 0.4 + blink * 0.5))

	# ── Choices ──
	_choice_rects.clear()
	if _choices_visible:
		var choice_start_y := y + h * 0.52
		for i in _choices.size():
			var c: Dictionary = _choices[i] as Dictionary
			var chosen := (i == _choice_sel)
			var cy_pos := choice_start_y + float(i) * 30.0
			var rect := Rect2(x - 6.0, cy_pos - 3.0, w + 6.0, 26.0)
			_choice_rects.append(rect)

			# Highlight bar
			if chosen:
				draw_rect(rect,
						Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.12))
				draw_line(Vector2(rect.position.x, rect.position.y),
						Vector2(rect.position.x, rect.end.y),
						Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.85), 2.5)

			# Number badge
			var badge_col := Color(_npc_color.r, _npc_color.g, _npc_color.b,
					0.90 if chosen else 0.45)
			draw_string(font, Vector2(x, cy_pos + 16.0),
					str(i + 1) + ".",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, badge_col)

			# Choice text
			var choice_text_col := Color(1.0, 1.0, 1.0, 1.0) if chosen \
					else Color(0.65, 0.68, 0.78, 1.0)
			draw_string(font, Vector2(x + 20.0, cy_pos + 16.0),
					_str(c.get("text")),
					HORIZONTAL_ALIGNMENT_LEFT, int(w - 22.0), 13, choice_text_col)


func _draw_wrapped_text(text: String, x: float, y: float, max_w: float,
		font_size: int, line_h: float, col: Color) -> void:
	if text == "": return
	var font := ThemeDB.fallback_font
	# Split into words and re-wrap
	var words := text.split(" ")
	var line := ""
	var cy := y + line_h
	for word in words:
		var test := (line + " " + word).strip_edges()
		var tw := font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if tw > max_w and line != "":
			draw_string(font, Vector2(x, cy), line,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
			cy += line_h
			line = word
		else:
			line = test
	if line != "":
		draw_string(font, Vector2(x, cy), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_scanlines(x: float, y: float, w: float, h: float) -> void:
	# Very subtle CRT scanline effect
	var i := 0.0
	while i < h:
		draw_rect(Rect2(x, y + i, w, 1.0), Color(0.0, 0.0, 0.0, 0.06))
		i += 4.0


func _draw_corner_accents(x: float, y: float, w: float, _h: float) -> void:
	var ac := Color(_npc_color.r, _npc_color.g, _npc_color.b, 0.45)
	var L := 18.0
	# Top-left
	draw_line(Vector2(x, y), Vector2(x + L, y), ac, 1.5)
	draw_line(Vector2(x, y), Vector2(x, y + L), ac, 1.5)
	# Top-right
	draw_line(Vector2(x + w, y), Vector2(x + w - L, y), ac, 1.5)
	draw_line(Vector2(x + w, y), Vector2(x + w, y + L), ac, 1.5)


# ── Finish ────────────────────────────────────────────────────────────────────

func _finish() -> void:
	var on_complete_v = _current_node.get("on_complete")
	if on_complete_v != null and on_complete_v is Dictionary:
		var oc: Dictionary = on_complete_v as Dictionary
		var clue := _str(oc.get("discover_clue"))
		if clue != "": GameState.discover_clue(clue)
		var met := _str(oc.get("set_met"))
		if met != "": GameState.meet_contact_in_person(met)
	emit_signal("dialogue_finished")
