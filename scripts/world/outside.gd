extends Control

# Corporate Theater — Outside (Street Scene)
# HD-2D inspired noir street at 2AM.
# Runs inside the desktop AppWindow (PRESET_FULL_RECT).
# Three parallax layers, player silhouette, rain, neon signs, minimap.

const LOCATIONS_PATH   := "res://data/world/locations.json"
const DIALOGUE_SCRIPT  := "res://scripts/world/dialogue_system.gd"

# ── Interior scene paths ──────────────────────────────────────────────────────
const CAFE_SCENE       := "res://scenes/world/cafe_interior.tscn"
const BAR_SCENE        := "res://scenes/world/bar_interior.tscn"
const APARTMENT_SCENE  := "res://scenes/world/apartment_interior.tscn"

# ── World constants ───────────────────────────────────────────────────────────
const WORLD_WIDTH      := 2400.0   # total scrollable width in world-space px
const FLOOR_Y_FRAC     := 0.78     # walkable floor as fraction of control height
const PLAYER_SPEED     := 280.0
const CAMERA_LERP      := 6.0
const INTERACT_RADIUS  := 80.0     # px to trigger enter prompt

# ── Parallax multipliers (0 = fixed, 1 = moves with camera) ──────────────────
const PAR_FAR   := 0.15
const PAR_MID   := 0.45
const PAR_NEAR  := 0.85

# ── Rain ──────────────────────────────────────────────────────────────────────
const RAIN_COUNT := 60
const RAIN_SPEED := 420.0
const RAIN_ANGLE := deg_to_rad(15.0)

# ── State ─────────────────────────────────────────────────────────────────────
var _locations: Array = []           # Array of Dictionaries from locations.json
var _player_x: float = 200.0        # world-space x
var _camera_x: float = 0.0          # current camera offset (world x of left edge)
var _size: Vector2 = Vector2.ZERO
var _floor_y: float = 0.0
var _rain: Array = []                # Array of Vector2 (screen-space, refreshes)
var _player_walk_t: float = 0.0
var _player_moving: bool = false
var _near_location_id: String = ""
var _prompt_alpha: float = 0.0
var _in_dialogue: bool = false
var _entering_scene: bool = false    # prevent double-trigger
var _player_dir: int = 1             # 1 = right, -1 = left

# ── Tilt-shift canvas layer ───────────────────────────────────────────────────
var _canvas_layer: CanvasLayer
var _tilt_top: ColorRect
var _tilt_bot: ColorRect

# ── Enter prompt label ────────────────────────────────────────────────────────
var _prompt_label: Label

# ── Minimap ───────────────────────────────────────────────────────────────────
var _minimap: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_size = get_rect().size
	if _size == Vector2.ZERO:
		await get_tree().process_frame
		_size = get_rect().size

	_floor_y = _size.y * FLOOR_Y_FRAC

	_load_locations()
	_init_rain()
	_build_tilt_shift()
	_build_prompt_label()
	_build_minimap()


func _load_locations() -> void:
	if not FileAccess.file_exists(LOCATIONS_PATH):
		return
	var file := FileAccess.open(LOCATIONS_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var root: Dictionary = json.data
		_locations = root.get("locations", []) as Array


func _init_rain() -> void:
	_rain.clear()
	for i in RAIN_COUNT:
		_rain.append(Vector2(randf() * _size.x, randf() * _size.y))


func _build_tilt_shift() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10
	add_child(_canvas_layer)

	var grad_h := _size.y * 0.22

	_tilt_top = ColorRect.new()
	_tilt_top.position = Vector2(0, 0)
	_tilt_top.size = Vector2(_size.x, grad_h)
	_tilt_top.color = Color(0, 0, 0, 0.55)
	_canvas_layer.add_child(_tilt_top)

	_tilt_bot = ColorRect.new()
	_tilt_bot.position = Vector2(0, _size.y - grad_h)
	_tilt_bot.size = Vector2(_size.x, grad_h)
	_tilt_bot.color = Color(0, 0, 0, 0.55)
	_canvas_layer.add_child(_tilt_bot)


func _build_prompt_label() -> void:
	_prompt_label = Label.new()
	_prompt_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.modulate.a = 0.0
	# Positioned at 88% height
	_prompt_label.set_anchor_and_offset(SIDE_LEFT, 0.0, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_RIGHT, 1.0, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_TOP, 0.88, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_BOTTOM, 0.88, 24.0)
	add_child(_prompt_label)


func _build_minimap() -> void:
	_minimap = Control.new()
	_minimap.set_anchor_and_offset(SIDE_RIGHT, 1.0, -12.0)
	_minimap.set_anchor_and_offset(SIDE_LEFT, 1.0, -172.0)
	_minimap.set_anchor_and_offset(SIDE_TOP, 1.0, -96.0)
	_minimap.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -12.0)
	_minimap.draw.connect(_draw_minimap)
	add_child(_minimap)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _in_dialogue:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_go_back_to_desktop()
		elif (key.keycode == KEY_E or key.keycode == KEY_ENTER) and _near_location_id != "":
			get_viewport().set_input_as_handled()
			_try_enter(_near_location_id)


func _go_back_to_desktop() -> void:
	# The outside scene lives inside AppWindow — just queue_free ourselves
	queue_free()


# ── Update ────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _in_dialogue:
		return

	_size = get_rect().size
	if _size == Vector2.ZERO:
		return
	_floor_y = _size.y * FLOOR_Y_FRAC

	_handle_movement(delta)
	_update_camera(delta)
	_update_rain(delta)
	_update_prompt(delta)

	queue_redraw()
	_minimap.queue_redraw()


func _handle_movement(delta: float) -> void:
	var move := 0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		move -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		move += 1

	_player_moving = move != 0
	if move != 0:
		_player_dir = move
		_player_x = clampf(_player_x + move * PLAYER_SPEED * delta, 0.0, WORLD_WIDTH)
		_player_walk_t += delta * 6.0

	# Check proximity to locations
	_near_location_id = ""
	for loc in _locations:
		var loc_dict: Dictionary = loc as Dictionary
		var lx: float = loc_dict.get("street_x", 0.0) as float
		if abs(_player_x - lx) < INTERACT_RADIUS:
			_near_location_id = loc_dict.get("id", "") as String
			break


func _update_camera(delta: float) -> void:
	var half_w: float = _size.x * 0.5
	var target_cam: float = clampf(_player_x - half_w, 0.0, WORLD_WIDTH - _size.x)
	_camera_x = lerpf(_camera_x, target_cam, CAMERA_LERP * delta)


func _update_rain(delta: float) -> void:
	var dx := sin(RAIN_ANGLE) * RAIN_SPEED * delta
	var dy := cos(RAIN_ANGLE) * RAIN_SPEED * delta
	for i in _rain.size():
		var drop: Vector2 = _rain[i]
		drop.x += dx
		drop.y += dy
		if drop.y > _size.y or drop.x > _size.x:
			drop = Vector2(randf() * _size.x, randf() * -10.0)
		_rain[i] = drop


func _update_prompt(delta: float) -> void:
	var target_alpha: float = 1.0 if _near_location_id != "" else 0.0
	_prompt_alpha = lerpf(_prompt_alpha, target_alpha, 8.0 * delta)
	_prompt_label.modulate.a = _prompt_alpha

	if _near_location_id != "":
		var loc: Dictionary = _get_location(_near_location_id)
		_prompt_label.text = loc.get("enter_prompt", "[ E ] enter") as String
	else:
		_prompt_label.text = ""


func _get_location(loc_id: String) -> Dictionary:
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		if d.get("id", "") as String == loc_id:
			return d
	return {}


# ── Draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _size == Vector2.ZERO:
		return
	_draw_sky()
	_draw_far_layer()
	_draw_mid_layer()
	_draw_near_layer()
	_draw_rain_layer()
	_draw_player()
	_draw_location_signs()


func _draw_sky() -> void:
	# Deep night gradient (top → bottom)
	draw_rect(Rect2(0, 0, _size.x, _size.y), Color(0.03, 0.03, 0.06, 1.0))
	# Subtle horizon glow
	var h_y: float = _floor_y - 60.0
	for i in 8:
		var t: float = float(i) / 8.0
		draw_rect(
			Rect2(0, h_y + t * 60.0, _size.x, 8.0),
			Color(0.1, 0.05, 0.15, 0.06 * (1.0 - t))
		)


func _draw_far_layer() -> void:
	# Building silhouettes — far background
	var offset: float = _camera_x * PAR_FAR
	var bldgs := [
		[0,    160, 90,  240],
		[100,  100, 140, 300],
		[250,  130, 110, 270],
		[420,  80,  200, 320],
		[640,  110, 130, 290],
		[790,  140, 90,  260],
		[900,  70,  170, 330],
		[1100, 120, 120, 280],
		[1250, 90,  150, 310],
		[1420, 130, 100, 270],
		[1540, 60,  220, 340],
		[1800, 110, 130, 290],
		[1970, 140, 90,  260],
		[2100, 80,  180, 320],
	]
	var col := Color(0.07, 0.06, 0.10, 1.0)
	var win_col := Color(0.35, 0.3, 0.45, 0.5)
	for b in bldgs:
		var bx: float = b[0] - offset
		var by: float = _floor_y - b[3]
		var bw: float = b[2]
		var bh: float = b[3]
		draw_rect(Rect2(bx, by, bw, bh), col)
		# Windows
		var wx := bx + 8.0
		while wx < bx + bw - 14.0:
			var wy := by + 10.0
			while wy < by + bh - 10.0:
				if randf() > 0.45:
					draw_rect(Rect2(wx, wy, 8.0, 10.0), win_col)
				wy += 18.0
			wx += 18.0


func _draw_mid_layer() -> void:
	var offset: float = _camera_x * PAR_MID
	var floor_y := _floor_y

	# Street surface
	draw_rect(Rect2(0, floor_y, _size.x, _size.y - floor_y), Color(0.05, 0.05, 0.07, 1.0))

	# Sidewalk line
	draw_line(Vector2(0, floor_y), Vector2(_size.x, floor_y), Color(0.15, 0.14, 0.22, 1.0), 2.0)

	# Puddle reflections
	var puddles := [200.0, 550.0, 900.0, 1350.0, 1700.0, 2100.0]
	for px in puddles:
		var sx: float = px - offset
		draw_ellipse_at(sx, floor_y + 6.0, 38.0, 7.0, Color(0.12, 0.11, 0.18, 0.6))

	# Street lamps (mid layer)
	var lamp_xs := [120.0, 480.0, 840.0, 1200.0, 1560.0, 1920.0]
	for lx in lamp_xs:
		var sx: float = lx - offset
		# Pole
		draw_line(Vector2(sx, floor_y - 2.0), Vector2(sx, floor_y - 80.0), Color(0.25, 0.22, 0.32, 1.0), 3.0)
		# Arm
		draw_line(Vector2(sx, floor_y - 80.0), Vector2(sx + 18.0, floor_y - 80.0), Color(0.25, 0.22, 0.32, 1.0), 2.0)
		# Glow halo
		for g in 5:
			var ga: float = 0.07 - float(g) * 0.012
			draw_circle(Vector2(sx + 18.0, floor_y - 80.0), 12.0 + g * 9.0, Color(0.7, 0.65, 0.9, ga))
		# Lamp head
		draw_rect(Rect2(sx + 10.0, floor_y - 86.0, 16.0, 6.0), Color(0.6, 0.58, 0.75, 1.0))


func _draw_near_layer() -> void:
	var offset: float = _camera_x * PAR_NEAR
	var floor_y := _floor_y

	# Foreground pillars / dumpsters / fire hydrants
	var pillars := [60.0, 380.0, 720.0, 1050.0, 1380.0, 1710.0, 2040.0]
	for px in pillars:
		var sx: float = px - offset
		draw_rect(Rect2(sx - 8.0, floor_y - 30.0, 16.0, 30.0), Color(0.06, 0.06, 0.09, 1.0))

	var dumpsters := [250.0, 900.0, 1550.0]
	for dx in dumpsters:
		var sx: float = dx - offset
		draw_rect(Rect2(sx, floor_y - 28.0, 48.0, 28.0), Color(0.08, 0.14, 0.08, 1.0))
		draw_rect(Rect2(sx, floor_y - 34.0, 48.0, 8.0), Color(0.10, 0.17, 0.10, 1.0))


func draw_ellipse_at(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw_rain_layer() -> void:
	var rain_col := Color(0.5, 0.55, 0.75, 0.22)
	var drop_len := 12.0
	var dx := sin(RAIN_ANGLE) * drop_len
	var dy := cos(RAIN_ANGLE) * drop_len
	for drop in _rain:
		var d: Vector2 = drop
		draw_line(d, d + Vector2(dx, dy), rain_col, 1.0)


func _draw_player() -> void:
	# Player screen position
	var sx: float = _player_x - _camera_x
	var sy: float = _floor_y

	# Shadow
	draw_ellipse_at(sx, sy, 14.0, 4.0, Color(0.0, 0.0, 0.0, 0.55))

	# Body bob when walking
	var bob: float = 0.0
	if _player_moving:
		bob = sin(_player_walk_t) * 2.5

	# Silhouette body
	var body_col := Color(0.08, 0.08, 0.12, 1.0)
	# Legs (two rects)
	var leg_w := 5.0
	var leg_h := 18.0
	draw_rect(Rect2(sx - 6.0, sy - leg_h + bob, leg_w, leg_h), body_col)
	draw_rect(Rect2(sx + 1.0, sy - leg_h + bob * 0.7, leg_w, leg_h), body_col)
	# Torso
	draw_rect(Rect2(sx - 9.0, sy - leg_h - 20.0 + bob, 18.0, 22.0), body_col)
	# Arms
	if _player_moving:
		var arm_swing: float = sin(_player_walk_t) * 6.0
		draw_rect(Rect2(sx - 15.0, sy - leg_h - 16.0 + arm_swing, 6.0, 14.0), body_col)
		draw_rect(Rect2(sx + 9.0, sy - leg_h - 16.0 - arm_swing, 6.0, 14.0), body_col)
	else:
		draw_rect(Rect2(sx - 14.0, sy - leg_h - 16.0, 5.0, 13.0), body_col)
		draw_rect(Rect2(sx + 9.0, sy - leg_h - 16.0, 5.0, 13.0), body_col)
	# Head
	draw_circle(Vector2(sx, sy - leg_h - 26.0 + bob), 8.0, body_col)


func _draw_location_signs() -> void:
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var world_x: float = d.get("street_x", 0.0) as float
		var sign_col := Color.from_string(d.get("sign_color", "#ffffff") as String, Color.WHITE)
		var glow_col := Color.from_string(d.get("sign_glow", "#888888") as String, Color.GRAY)
		var sign_text: String = d.get("sign_text", "") as String
		var unlock_clue: String = d.get("unlock_clue", "") as String
		var locked: bool = (unlock_clue != "" and unlock_clue != null and
				not (unlock_clue in GameState.discovered_clues))

		# Use mid-layer parallax for doors/signs (same as building facades)
		var sx: float = world_x - _camera_x * PAR_MID
		var floor_y := _floor_y

		# Door
		var door_col := Color(0.06, 0.06, 0.09, 1.0) if locked else Color(0.09, 0.09, 0.14, 1.0)
		draw_rect(Rect2(sx - 20.0, floor_y - 60.0, 40.0, 60.0), door_col)
		draw_rect(Rect2(sx - 20.0, floor_y - 60.0, 40.0, 2.0), Color(0.15, 0.14, 0.22, 1.0))

		# Sign box with glow
		if not locked:
			for g in 4:
				var ga: float = 0.08 - float(g) * 0.018
				draw_rect(Rect2(sx - 28.0 - g * 3.0, floor_y - 100.0 - g * 2.0,
						56.0 + g * 6.0, 24.0 + g * 4.0), Color(glow_col.r, glow_col.g, glow_col.b, ga))
			draw_rect(Rect2(sx - 28.0, floor_y - 100.0, 56.0, 24.0), Color(0.04, 0.04, 0.06, 1.0))
		else:
			# Dim sign for locked locations
			draw_rect(Rect2(sx - 28.0, floor_y - 100.0, 56.0, 24.0), Color(0.04, 0.04, 0.06, 1.0))
			sign_col = Color(0.2, 0.2, 0.25, 1.0)

		# Sign text (draw as colored line proxy — actual text via Label overlay would need CanvasLayer)
		# We use draw_string with a system font placeholder; fonts are available via theme
		draw_string(ThemeDB.fallback_font, Vector2(sx - 24.0, floor_y - 82.0),
				sign_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, sign_col)


# ── Minimap draw (called on _minimap Control) ─────────────────────────────────

func _draw_minimap() -> void:
	var ms: Vector2 = _minimap.get_rect().size
	if ms == Vector2.ZERO:
		return

	# Background
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.03, 0.03, 0.05, 0.88)
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_color = Color(0.15, 0.15, 0.25, 1.0)
	# draw_style_box not available on _draw signal callback; draw rect manually:
	_minimap.draw_rect(Rect2(0, 0, ms.x, ms.y), Color(0.03, 0.03, 0.05, 0.88))
	_minimap.draw_rect(Rect2(0, 0, ms.x, 1.0), Color(0.15, 0.15, 0.25, 1.0))
	_minimap.draw_rect(Rect2(0, ms.y - 1.0, ms.x, 1.0), Color(0.15, 0.15, 0.25, 1.0))
	_minimap.draw_rect(Rect2(0, 0, 1.0, ms.y), Color(0.15, 0.15, 0.25, 1.0))
	_minimap.draw_rect(Rect2(ms.x - 1.0, 0, 1.0, ms.y), Color(0.15, 0.15, 0.25, 1.0))

	var bar_y: float = ms.y * 0.5
	var bar_h: float = 4.0
	_minimap.draw_rect(Rect2(8.0, bar_y - bar_h * 0.5, ms.x - 16.0, bar_h),
			Color(0.12, 0.12, 0.18, 1.0))

	var map_w: float = ms.x - 16.0

	# Location markers
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx: float = d.get("street_x", 0.0) as float
		var sign_col := Color.from_string(d.get("sign_color", "#ffffff") as String, Color.WHITE)
		var unlock_clue: String = d.get("unlock_clue", "") as String
		var locked: bool = (unlock_clue != "" and unlock_clue != null and
				not (unlock_clue in GameState.discovered_clues))
		var mx: float = 8.0 + (lx / WORLD_WIDTH) * map_w
		var col := Color(sign_col.r, sign_col.g, sign_col.b, 0.35 if locked else 0.9)
		_minimap.draw_rect(Rect2(mx - 4.0, bar_y - 6.0, 8.0, 12.0), col)

	# Player dot (blinking green)
	var px: float = 8.0 + (_player_x / WORLD_WIDTH) * map_w
	var blink: float = (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
	_minimap.draw_circle(Vector2(px, bar_y), 4.0, Color(0.2, 1.0, 0.4, 0.6 + blink * 0.4))

	# Label
	_minimap.draw_string(ThemeDB.fallback_font, Vector2(8.0, ms.y - 4.0),
			"STREET MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.3, 0.45, 0.8))


# ── Enter location ────────────────────────────────────────────────────────────

func _try_enter(loc_id: String) -> void:
	if _entering_scene:
		return
	var loc: Dictionary = _get_location(loc_id)
	if loc.is_empty():
		return

	# Check unlock condition
	var unlock_clue: String = loc.get("unlock_clue", "") as String
	if unlock_clue != "" and unlock_clue != null:
		if not (unlock_clue in GameState.discovered_clues):
			_show_locked_message(loc)
			return

	_entering_scene = true
	var interior_type: String = loc.get("interior_type", "") as String
	var scene_path: String = ""
	match interior_type:
		"cafe":      scene_path = CAFE_SCENE
		"bar":       scene_path = BAR_SCENE
		"apartment": scene_path = APARTMENT_SCENE

	if scene_path == "":
		_entering_scene = false
		return

	# Load interior into parent (AppWindow), replacing this scene
	var parent: Node = get_parent()
	if parent == null:
		_entering_scene = false
		return

	var scene_res := load(scene_path)
	if scene_res == null:
		_entering_scene = false
		return

	var interior: Control = scene_res.instantiate()
	# Pass location id so interior knows which NPC to show
	interior.set_meta("location_id", loc_id)
	interior.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(interior)
	queue_free()


func _show_locked_message(loc: Dictionary) -> void:
	var name_str: String = loc.get("name", "location") as String
	# Temporarily flash the prompt label with a locked message
	_prompt_label.text = name_str + " — not yet accessible"
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	_prompt_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_callback(func():
		_prompt_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8, 1.0))
	)
