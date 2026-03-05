extends Control

# Corporate Theater — LocationInterior
# Shared script for all 3 interior scenes.
# Each scene sets export var location_id in the Inspector (or via set_meta before instantiation).
# Draws the room with _draw(), places NPC silhouette, triggers dialogue on E.

const LOCATIONS_PATH  := "res://data/world/locations.json"
const OUTSIDE_SCENE   := "res://scenes/world/outside.tscn"
const DIALOGUE_SCRIPT := "res://scripts/world/dialogue_system.gd"

@export var location_id: String = ""

# ── State ─────────────────────────────────────────────────────────────────────
var _loc: Dictionary = {}
var _size: Vector2 = Vector2.ZERO
var _floor_y: float = 0.0
var _npc_walk_t: float = 0.0

var _dialogue_active: bool = false
var _near_npc: bool = false
var _player_x: float = 0.0      # screen x of player (static, enters from left)

var _prompt_label: Label
var _prompt_alpha: float = 0.0

var _ambient_particles: Array = []
const DUST_COUNT := 22


func _ready() -> void:
	# Allow location_id to be passed via meta from outside.gd
	if location_id == "" and has_meta("location_id"):
		location_id = get_meta("location_id") as String

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_location()

	_size = get_rect().size
	if _size == Vector2.ZERO:
		await get_tree().process_frame
		_size = get_rect().size

	_floor_y = _size.y * 0.80
	_player_x = _size.x * 0.25
	_init_particles()
	_build_prompt()


func _load_location() -> void:
	if not FileAccess.file_exists(LOCATIONS_PATH):
		return
	var file := FileAccess.open(LOCATIONS_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var root: Dictionary = json.data
	var locs: Array = root.get("locations", []) as Array
	for l in locs:
		var d: Dictionary = l as Dictionary
		if d.get("id", "") as String == location_id:
			_loc = d
			return


func _init_particles() -> void:
	_ambient_particles.clear()
	for i in DUST_COUNT:
		_ambient_particles.append({
			"x": randf() * _size.x,
			"y": randf() * _size.y * 0.7,
			"speed": randf_range(6.0, 18.0),
			"alpha": randf_range(0.04, 0.14),
			"size": randf_range(1.0, 3.0)
		})


func _build_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.modulate.a = 0.0
	_prompt_label.set_anchor_and_offset(SIDE_LEFT, 0.0, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_RIGHT, 1.0, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_TOP, 0.82, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_BOTTOM, 0.82, 24.0)
	_prompt_label.text = "[ E ] talk"
	add_child(_prompt_label)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_return_outside()
		elif (key.keycode == KEY_E or key.keycode == KEY_ENTER) and _near_npc:
			get_viewport().set_input_as_handled()
			_start_dialogue()


func _return_outside() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var scene_res := load(OUTSIDE_SCENE)
	if scene_res == null:
		return
	var outside: Control = scene_res.instantiate()
	outside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(outside)
	queue_free()


# ── Update ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _dialogue_active:
		return

	_size = get_rect().size
	if _size == Vector2.ZERO:
		return
	_floor_y = _size.y * 0.80

	_npc_walk_t += delta * 1.2
	_update_particles(delta)

	# NPC is always at 60% of width
	var npc_sx: float = _size.x * 0.60
	_near_npc = abs(_player_x - npc_sx) < 140.0

	var target_alpha: float = 1.0 if _near_npc else 0.0
	_prompt_alpha = lerpf(_prompt_alpha, target_alpha, 8.0 * delta)
	_prompt_label.modulate.a = _prompt_alpha

	queue_redraw()


func _update_particles(delta: float) -> void:
	for p in _ambient_particles:
		p["y"] = p["y"] - p["speed"] * delta
		if p["y"] < 0.0:
			p["y"] = _floor_y * randf_range(0.9, 1.0)
			p["x"] = randf() * _size.x


# ── Draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _size == Vector2.ZERO or _loc.is_empty():
		return

	_draw_room()
	_draw_ambient_particles()
	_draw_npc()
	_draw_player_silhouette()


func _draw_room() -> void:
	var ambient_hex: String = _loc.get("ambient_color", "#050508") as String
	var light_hex: String   = _loc.get("ambient_light", "#ffffff22") as String
	var interior_type: String = _loc.get("interior_type", "cafe") as String
	var room_col := Color.from_string(ambient_hex, Color(0.02, 0.02, 0.03))
	var light_col := Color.from_string(light_hex, Color(1.0, 1.0, 1.0, 0.12))

	# Background fill
	draw_rect(Rect2(0, 0, _size.x, _size.y), room_col)

	# Ceiling
	draw_rect(Rect2(0, 0, _size.x, 40.0), Color(room_col.r * 0.6, room_col.g * 0.6, room_col.b * 0.6, 1.0))

	# Floor
	draw_rect(Rect2(0, _floor_y, _size.x, _size.y - _floor_y),
			Color(room_col.r * 1.3, room_col.g * 1.3, room_col.b * 1.3, 1.0))
	draw_line(Vector2(0, _floor_y), Vector2(_size.x, _floor_y),
			Color(room_col.r * 2.0, room_col.g * 2.0, room_col.b * 2.0, 1.0), 2.0)

	# Ambient light pool (overhead light)
	var lx: float = _size.x * 0.58
	for g in 8:
		var ga: float = light_col.a * (0.12 - float(g) * 0.013)
		var rad: float = 60.0 + g * 40.0
		draw_circle(Vector2(lx, _floor_y - 10.0), rad, Color(light_col.r, light_col.g, light_col.b, ga))

	# Windows (back wall)
	var win_count := 2
	var win_y: float = _size.y * 0.25
	var win_h: float = _size.y * 0.22
	var win_w: float = _size.x * 0.08
	for i in win_count:
		var wx: float = _size.x * (0.3 + i * 0.35)
		draw_rect(Rect2(wx, win_y, win_w, win_h), Color(0.04, 0.06, 0.12, 1.0))
		# Rain streaks on window
		for r in 6:
			var rx: float = wx + randf_range(4.0, win_w - 4.0)
			var ry: float = win_y + randf_range(0.0, win_h - 20.0)
			draw_line(Vector2(rx, ry), Vector2(rx + 2.0, ry + 15.0),
					Color(0.15, 0.2, 0.35, 0.4), 1.0)
		draw_rect(Rect2(wx - 2.0, win_y - 2.0, win_w + 4.0, 3.0), Color(0.12, 0.12, 0.18, 1.0))
		draw_rect(Rect2(wx - 2.0, win_y + win_h, win_w + 4.0, 3.0), Color(0.12, 0.12, 0.18, 1.0))

	# Type-specific furnishings
	match interior_type:
		"cafe":    _draw_cafe_furniture(room_col, light_col)
		"bar":     _draw_bar_furniture(room_col, light_col)
		"apartment": _draw_apartment_furniture(room_col, light_col)


func _draw_cafe_furniture(room_col: Color, _light_col: Color) -> void:
	# Tables + chairs (simple rects)
	var table_col := Color(room_col.r * 2.2, room_col.g * 1.8, room_col.b * 1.2, 1.0)
	var chair_col := Color(room_col.r * 1.6, room_col.g * 1.3, room_col.b * 0.9, 1.0)
	var tables := [_size.x * 0.15, _size.x * 0.75]
	for tx in tables:
		draw_rect(Rect2(tx - 30.0, _floor_y - 24.0, 60.0, 8.0), table_col)
		draw_rect(Rect2(tx - 4.0, _floor_y - 16.0, 8.0, 16.0), chair_col)
		draw_rect(Rect2(tx - 24.0, _floor_y - 10.0, 18.0, 10.0), chair_col)
		draw_rect(Rect2(tx + 6.0, _floor_y - 10.0, 18.0, 10.0), chair_col)
	# Counter (right side)
	draw_rect(Rect2(_size.x * 0.78, _floor_y - 40.0, _size.x * 0.18, 40.0),
			Color(room_col.r * 1.8, room_col.g * 1.4, room_col.b * 0.8, 1.0))


func _draw_bar_furniture(room_col: Color, _light_col: Color) -> void:
	# Long bar counter
	var bar_col := Color(room_col.r * 1.5, room_col.g * 0.8, room_col.b * 0.7, 1.0)
	draw_rect(Rect2(_size.x * 0.5, _floor_y - 44.0, _size.x * 0.46, 44.0), bar_col)
	draw_rect(Rect2(_size.x * 0.5, _floor_y - 52.0, _size.x * 0.46, 10.0),
			Color(bar_col.r * 1.3, bar_col.g * 1.1, bar_col.b * 1.0, 1.0))
	# Stools
	for i in 3:
		var sx: float = _size.x * (0.55 + i * 0.1)
		draw_rect(Rect2(sx - 8.0, _floor_y - 28.0, 16.0, 6.0), Color(0.15, 0.1, 0.1, 1.0))
		draw_rect(Rect2(sx - 2.0, _floor_y - 22.0, 4.0, 22.0), Color(0.1, 0.08, 0.08, 1.0))
	# Bottles on shelf
	for i in 5:
		var bx: float = _size.x * (0.78 + i * 0.03)
		draw_rect(Rect2(bx, _floor_y * 0.55, 6.0, 20.0),
				Color(0.3 + i * 0.05, 0.1, 0.1, 0.7))


func _draw_apartment_furniture(room_col: Color, _light_col: Color) -> void:
	# Desk + monitors
	var desk_col := Color(room_col.r * 2.0, room_col.g * 2.2, room_col.b * 1.8, 1.0)
	draw_rect(Rect2(_size.x * 0.52, _floor_y - 36.0, _size.x * 0.28, 36.0), desk_col)
	# Monitor glow
	draw_rect(Rect2(_size.x * 0.56, _floor_y - 70.0, 60.0, 42.0), Color(0.04, 0.12, 0.06, 1.0))
	for g in 4:
		draw_rect(Rect2(_size.x * 0.56 - g, _floor_y - 70.0 - g, 60.0 + g * 2.0, 42.0 + g * 2.0),
				Color(0.1, 0.8, 0.3, 0.06 - g * 0.012))
	# Filing boxes on floor
	draw_rect(Rect2(_size.x * 0.1, _floor_y - 28.0, 44.0, 28.0), Color(0.08, 0.1, 0.08, 1.0))
	draw_rect(Rect2(_size.x * 0.1, _floor_y - 52.0, 32.0, 24.0), Color(0.07, 0.09, 0.07, 1.0))


func _draw_ambient_particles() -> void:
	for p in _ambient_particles:
		draw_circle(Vector2(p["x"], p["y"]), p["size"], Color(1.0, 1.0, 1.0, p["alpha"]))


func _draw_npc() -> void:
	if _loc.is_empty():
		return
	var npc_col := Color.from_string(_loc.get("npc_color", "#7b68ee") as String, Color(0.5, 0.4, 1.0))
	var sx: float = _size.x * 0.60
	var sy: float = _floor_y
	var bob: float = sin(_npc_walk_t) * 1.2

	# Shadow
	_draw_ellipse_at(sx, sy, 13.0, 4.0, Color(0.0, 0.0, 0.0, 0.45))

	# Body (slightly tinted with npc color)
	var body_col := Color(npc_col.r * 0.25, npc_col.g * 0.25, npc_col.b * 0.35, 1.0)
	var accent := Color(npc_col.r * 0.6, npc_col.g * 0.6, npc_col.b * 0.7, 1.0)

	# Legs
	draw_rect(Rect2(sx - 7.0, sy - 20.0 + bob, 6.0, 20.0), body_col)
	draw_rect(Rect2(sx + 1.0, sy - 20.0 + bob * 0.8, 6.0, 20.0), body_col)
	# Torso
	draw_rect(Rect2(sx - 10.0, sy - 42.0 + bob, 20.0, 24.0), body_col)
	# Arms (relaxed at sides)
	draw_rect(Rect2(sx - 16.0, sy - 38.0, 6.0, 16.0), body_col)
	draw_rect(Rect2(sx + 10.0, sy - 38.0, 6.0, 16.0), body_col)
	# Head
	draw_circle(Vector2(sx, sy - 50.0 + bob), 9.0, body_col)
	# Accent strip on torso (color identity)
	draw_rect(Rect2(sx - 5.0, sy - 40.0 + bob, 10.0, 18.0), accent)


func _draw_player_silhouette() -> void:
	var sx: float = _player_x
	var sy: float = _floor_y
	var body_col := Color(0.08, 0.08, 0.12, 1.0)

	_draw_ellipse_at(sx, sy, 12.0, 3.5, Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(Rect2(sx - 6.0, sy - 18.0, 5.0, 18.0), body_col)
	draw_rect(Rect2(sx + 1.0, sy - 18.0, 5.0, 18.0), body_col)
	draw_rect(Rect2(sx - 9.0, sy - 40.0, 18.0, 24.0), body_col)
	draw_rect(Rect2(sx - 14.0, sy - 36.0, 5.0, 14.0), body_col)
	draw_rect(Rect2(sx + 9.0, sy - 36.0, 5.0, 14.0), body_col)
	draw_circle(Vector2(sx, sy - 48.0), 8.0, body_col)


func _draw_ellipse_at(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, col)


# ── Dialogue ──────────────────────────────────────────────────────────────────

func _start_dialogue() -> void:
	if _dialogue_active:
		return
	_dialogue_active = true
	_prompt_label.modulate.a = 0.0

	var npc_id: String = _loc.get("npc_id", "") as String
	var npc_color_hex: String = _loc.get("npc_color", "#7b68ee") as String

	var dialogue_script: Script = load(DIALOGUE_SCRIPT)
	var dialogue: Control = Control.new()
	dialogue.set_script(dialogue_script)
	add_child(dialogue)
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue.dialogue_finished.connect(_on_dialogue_finished)
	dialogue.start(npc_id, npc_color_hex)


func _on_dialogue_finished() -> void:
	_dialogue_active = false
	# Remove dialogue node (it will be a child)
	for child in get_children():
		if child.has_signal("dialogue_finished"):
			child.queue_free()
			break
