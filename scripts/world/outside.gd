extends Control

# Corporate Theater — Outside (Isometric Street Scene)
#
# Visual target: Final Fantasy Tactics / HD-2D isometric diorama.
# A raised city block platform viewed from ~30° above and 45° to the side.
# Everything drawn with _draw() using isometric projection math.
#
# Coordinate system:
#   World grid:  (gx, gy) integer tile coordinates
#   Iso screen:  iso_to_screen(gx, gy, gz) → Vector2
#   gz = elevation (0 = street level, 1 = raised sidewalk, etc.)
#
# Camera pans horizontally by shifting the iso origin.
# Player moves left/right along the walkable row (gy = WALK_ROW).

const LOCATIONS_PATH  := "res://data/world/locations.json"
const CAFE_SCENE      := "res://scenes/world/cafe_interior.tscn"
const BAR_SCENE       := "res://scenes/world/bar_interior.tscn"
const APARTMENT_SCENE := "res://scenes/world/apartment_interior.tscn"

# ── Isometric projection ─────────────────────────────────────────────────────
# Standard 2:1 diamond tiles.
const TILE_W  := 80.0   # full tile width  (px)
const TILE_H  := 40.0   # full tile height (px) = TILE_W / 2
const TILE_Z  := 40.0   # height of one elevation unit (px)

# Grid dimensions
const GRID_COLS := 22   # tiles wide
const GRID_ROWS := 10   # tiles deep
const WALK_ROW  := 6    # the row the player walks on (front-ish)

# ── Camera / player ───────────────────────────────────────────────────────────
const PLAYER_SPEED   := 4.5   # tiles per second
const CAMERA_LERP    := 5.0
const INTERACT_DIST  := 1.4   # tiles

var _player_gx: float  = 3.0   # world-space grid x (float for smooth movement)
var _camera_offset: float = 0.0  # additional x shift in screen pixels
var _target_cam: float = 0.0
var _player_walk_t: float = 0.0
var _player_moving: bool = false
var _player_dir: int = 1

# ── ISO origin — where tile (0,0,0) maps to on screen ────────────────────────
# Adjusted in _process() based on screen size and camera.
var _origin: Vector2 = Vector2.ZERO
var _size: Vector2 = Vector2.ZERO

# ── Scene data ────────────────────────────────────────────────────────────────
var _locations: Array = []
var _near_location_id: String = ""
var _prompt_alpha: float = 0.0
var _entering_scene: bool = false

# ── Rain ──────────────────────────────────────────────────────────────────────
const RAIN_COUNT := 80
var _rain: Array = []   # Array of {pos: Vector2, len: float, speed: float}

# ── Ambient animation ─────────────────────────────────────────────────────────
var _time: float = 0.0
var _neon_flicker: float = 1.0
var _flicker_timer: float = 0.0

# ── UI nodes ─────────────────────────────────────────────────────────────────
var _prompt_label: Label
var _esc_label: Label
var _minimap_ctrl: Control


# ── Helpers ───────────────────────────────────────────────────────────────────

func _str(v: Variant) -> String:
	if v == null: return ""
	return str(v)


# Convert isometric grid coords to screen position.
# gx=right, gy=forward(into screen), gz=up
func iso(gx: float, gy: float, gz: float = 0.0) -> Vector2:
	var sx := (gx - gy) * (TILE_W * 0.5)
	var sy := (gx + gy) * (TILE_H * 0.5) - gz * TILE_Z
	return _origin + Vector2(sx, sy)


# Top-face diamond of a tile at (gx,gy,gz)
func tile_top(gx: float, gy: float, gz: float) -> PackedVector2Array:
	var c := iso(gx + 0.5, gy + 0.5, gz)
	var pts := PackedVector2Array()
	pts.append(iso(gx,       gy + 0.5, gz))   # left
	pts.append(iso(gx + 0.5, gy,       gz))   # top
	pts.append(iso(gx + 1.0, gy + 0.5, gz))   # right
	pts.append(iso(gx + 0.5, gy + 1.0, gz))   # bottom
	return pts


# Left face of a box (gx,gy) with given height in units
func box_left(gx: float, gy: float, gz_bot: float, gz_top: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(iso(gx,       gy + 1.0, gz_bot))
	pts.append(iso(gx,       gy + 1.0, gz_top))
	pts.append(iso(gx + 0.5, gy + 0.5, gz_top))  # nope — wrong, use full tile
	pts.append(iso(gx + 0.5, gy + 0.5, gz_bot))
	# left face: from (gx, gy+1) to (gx+1, gy+1) bottom edge
	# Actually: left face of a 1-wide box spans gx → gx+1, front edge gy+1
	var pts2 := PackedVector2Array()
	pts2.append(iso(gx,       gy + 1.0, gz_bot))
	pts2.append(iso(gx,       gy + 1.0, gz_top))
	pts2.append(iso(gx + 1.0, gy + 1.0, gz_top))
	pts2.append(iso(gx + 1.0, gy + 1.0, gz_bot))
	return pts2


# Right face of a box
func box_right(gx: float, gy: float, gz_bot: float, gz_top: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(iso(gx + 1.0, gy,       gz_bot))
	pts.append(iso(gx + 1.0, gy,       gz_top))
	pts.append(iso(gx + 1.0, gy + 1.0, gz_top))
	pts.append(iso(gx + 1.0, gy + 1.0, gz_bot))
	return pts


# Draw a filled iso box (top + left face + right face) with painter's algo colors
func draw_iso_box(gx: float, gy: float, gz_bot: float, gz_top: float,
		top_col: Color, left_col: Color, right_col: Color) -> void:
	# Right face (drawn first — it's "further" in painter's algo for left-to-right reading)
	draw_colored_polygon(box_right(gx, gy, gz_bot, gz_top), right_col)
	# Left face
	draw_colored_polygon(box_left(gx, gy, gz_bot, gz_top), left_col)
	# Top face
	draw_colored_polygon(tile_top(gx, gy, gz_top), top_col)


# Draw a flat tile (just the top diamond) at elevation gz
func draw_tile(gx: float, gy: float, gz: float, col: Color) -> void:
	draw_colored_polygon(tile_top(gx, gy, gz), col)


# Draw an iso line (e.g. wall edge, rail)
func iso_line(gx0: float, gy0: float, gz0: float,
			  gx1: float, gy1: float, gz1: float, col: Color, w: float = 1.0) -> void:
	draw_line(iso(gx0, gy0, gz0), iso(gx1, gy1, gz1), col, w)


# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_size = get_rect().size
	if _size == Vector2.ZERO:
		await get_tree().process_frame
		_size = get_rect().size

	_load_locations()
	_init_rain()
	_build_ui()
	_recalc_origin()


func _load_locations() -> void:
	if not FileAccess.file_exists(LOCATIONS_PATH):
		return
	var file := FileAccess.open(LOCATIONS_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_locations = (json.data as Dictionary).get("locations", []) as Array


func _init_rain() -> void:
	_rain.clear()
	for i in RAIN_COUNT:
		_rain.append({
			"pos": Vector2(randf_range(0.0, 1920.0), randf_range(0.0, 1080.0)),
			"len": randf_range(8.0, 18.0),
			"speed": randf_range(280.0, 480.0)
		})


func _build_ui() -> void:
	_prompt_label = Label.new()
	_prompt_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75, 1.0))
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.modulate.a = 0.0
	_prompt_label.set_anchor_and_offset(SIDE_LEFT,   0.0,  0.0)
	_prompt_label.set_anchor_and_offset(SIDE_RIGHT,  1.0,  0.0)
	_prompt_label.set_anchor_and_offset(SIDE_TOP,    0.86, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_BOTTOM, 0.86, 26.0)
	add_child(_prompt_label)

	_esc_label = Label.new()
	_esc_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45, 1.0))
	_esc_label.add_theme_font_size_override("font_size", 11)
	_esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_esc_label.text = "[ ESC ] back to desktop   [ arrows / WASD ] move"
	_esc_label.set_anchor_and_offset(SIDE_LEFT,   0.0, 8.0)
	_esc_label.set_anchor_and_offset(SIDE_RIGHT,  1.0, -8.0)
	_esc_label.set_anchor_and_offset(SIDE_TOP,    1.0, -22.0)
	_esc_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -4.0)
	add_child(_esc_label)

	_minimap_ctrl = Control.new()
	_minimap_ctrl.set_anchor_and_offset(SIDE_RIGHT,  1.0, -10.0)
	_minimap_ctrl.set_anchor_and_offset(SIDE_LEFT,   1.0, -200.0)
	_minimap_ctrl.set_anchor_and_offset(SIDE_TOP,    0.0,  10.0)
	_minimap_ctrl.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  60.0)
	_minimap_ctrl.draw.connect(_draw_minimap)
	add_child(_minimap_ctrl)


# Re-center the iso origin so the grid is nicely visible
func _recalc_origin() -> void:
	_size = get_rect().size
	if _size == Vector2.ZERO:
		return
	# We want tile (GRID_COLS/2, 0) to appear near the horizontal center, upper-middle of screen
	# Standard iso origin formula: place (0,0,0) so the grid center lands at screen center
	var center_gx := GRID_COLS * 0.5
	var center_gy := GRID_ROWS * 0.5
	var sx := (center_gx - center_gy) * (TILE_W * 0.5)
	var sy := (center_gx + center_gy) * (TILE_H * 0.5)
	# Origin = screen_target - computed_offset
	var screen_target := Vector2(_size.x * 0.5 - _camera_offset, _size.y * 0.38)
	_origin = screen_target - Vector2(sx, sy)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			queue_free()
		elif (key.keycode == KEY_E or key.keycode == KEY_ENTER) and _near_location_id != "":
			get_viewport().set_input_as_handled()
			_try_enter(_near_location_id)


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_size = get_rect().size
	if _size == Vector2.ZERO:
		return

	_time += delta
	_update_neon_flicker(delta)
	_handle_movement(delta)
	_update_camera(delta)
	_update_rain(delta)
	_update_prompt(delta)
	_recalc_origin()

	queue_redraw()
	_minimap_ctrl.queue_redraw()


func _update_neon_flicker(delta: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(0.05, 0.35)
		_neon_flicker = randf_range(0.82, 1.0)


func _handle_movement(delta: float) -> void:
	var move := 0
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): move -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): move += 1

	_player_moving = move != 0
	if move != 0:
		_player_dir = move
		_player_gx = clampf(_player_gx + move * PLAYER_SPEED * delta, 1.0, float(GRID_COLS - 2))
		_player_walk_t += delta * 5.0

	# Proximity check — compare world gx against location grid_x
	_near_location_id = ""
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx: float = _loc_grid_x(d)
		if abs(_player_gx - lx) < INTERACT_DIST:
			_near_location_id = _str(d.get("id"))
			break


func _loc_grid_x(d: Dictionary) -> float:
	# locations.json street_x is in range 480–1700; map to grid 2–18
	var raw: float = d.get("street_x", 480.0)
	return remap(raw, 480.0, 1700.0, 2.0, 18.0)


func _update_camera(delta: float) -> void:
	# Keep player roughly centered
	var player_screen_x: float = (_player_gx - float(WALK_ROW)) * (TILE_W * 0.5)
	_target_cam = player_screen_x - 0.0   # we'll offset origin by this
	_camera_offset = lerpf(_camera_offset, _target_cam, CAMERA_LERP * delta)


func _update_rain(delta: float) -> void:
	for r in _rain:
		r["pos"] = r["pos"] + Vector2(2.5, r["speed"]) * delta
		if r["pos"].y > _size.y:
			r["pos"] = Vector2(randf_range(0.0, _size.x), -20.0)


func _update_prompt(delta: float) -> void:
	var want: float = 1.0 if _near_location_id != "" else 0.0
	_prompt_alpha = lerpf(_prompt_alpha, want, 8.0 * delta)
	_prompt_label.modulate.a = _prompt_alpha
	if _near_location_id != "":
		var loc := _get_location(_near_location_id)
		var ep := _str(loc.get("enter_prompt"))
		_prompt_label.text = ep if ep != "" else "[ E ] enter"
	else:
		_prompt_label.text = ""


func _get_location(loc_id: String) -> Dictionary:
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		if _str(d.get("id")) == loc_id:
			return d
	return {}


# ── DRAW ──────────────────────────────────────────────────────────────────────
# Painter's algorithm: draw back-to-front.
# Tile order: increasing gy (rows from back to front), increasing gx within row.

func _draw() -> void:
	if _size == Vector2.ZERO or _origin == Vector2.ZERO:
		return

	_draw_sky()
	_draw_ground_platform()
	_draw_buildings()
	_draw_street_details()
	_draw_location_facades()
	_draw_player()
	_draw_rain()
	_draw_tilt_shift()


# ── Sky ───────────────────────────────────────────────────────────────────────

func _draw_sky() -> void:
	# Very dark blue-black gradient (top) fading to slightly lighter near horizon
	draw_rect(Rect2(0, 0, _size.x, _size.y), Color(0.02, 0.02, 0.04, 1.0))
	# Subtle horizon warmth
	var hor_y := _origin.y + (GRID_COLS + GRID_ROWS) * TILE_H * 0.5
	for i in 12:
		var t := float(i) / 12.0
		var alpha := 0.07 * (1.0 - t)
		draw_rect(Rect2(0.0, hor_y - i * 8.0, _size.x, 8.0),
				Color(0.08, 0.04, 0.12, alpha))

	# Distant city glow blobs (background mood)
	_draw_bg_city_glow()


func _draw_bg_city_glow() -> void:
	# A few large soft blobs suggesting a city skyline far behind
	var glows := [
		[0.15, 0.28, 320.0, 80.0, Color(0.08, 0.03, 0.15, 0.18)],
		[0.40, 0.24, 280.0, 70.0, Color(0.12, 0.05, 0.08, 0.15)],
		[0.65, 0.26, 360.0, 90.0, Color(0.04, 0.08, 0.18, 0.20)],
		[0.85, 0.22, 220.0, 60.0, Color(0.1,  0.03, 0.12, 0.14)],
	]
	for g in glows:
		var cx: float = _size.x * g[0]
		var cy: float = _size.y * g[1]
		var rx: float = g[2]
		var ry: float = g[3]
		var col: Color = g[4]
		_draw_ellipse(cx, cy, rx, ry, col)

	# Background skyscraper silhouettes (very dim)
	_draw_bg_skyline()


func _draw_bg_skyline() -> void:
	# Rough building blocks in the far background (no isometric — just screen rects)
	var sky_y_base: float = _origin.y - 10.0
	var buildings := [
		[0.05,  0.15, 0.06, 180.0, Color(0.04, 0.04, 0.07, 1.0)],
		[0.12,  0.10, 0.07, 230.0, Color(0.05, 0.04, 0.08, 1.0)],
		[0.20,  0.13, 0.09, 200.0, Color(0.04, 0.03, 0.07, 1.0)],
		[0.30,  0.08, 0.05, 260.0, Color(0.05, 0.04, 0.08, 1.0)],
		[0.38,  0.12, 0.06, 210.0, Color(0.04, 0.04, 0.07, 1.0)],
		[0.47,  0.07, 0.08, 280.0, Color(0.05, 0.03, 0.08, 1.0)],
		[0.57,  0.11, 0.07, 220.0, Color(0.04, 0.04, 0.07, 1.0)],
		[0.66,  0.09, 0.06, 250.0, Color(0.05, 0.04, 0.09, 1.0)],
		[0.75,  0.14, 0.09, 190.0, Color(0.04, 0.03, 0.07, 1.0)],
		[0.86,  0.10, 0.07, 240.0, Color(0.05, 0.04, 0.08, 1.0)],
		[0.93,  0.12, 0.05, 200.0, Color(0.04, 0.04, 0.07, 1.0)],
	]
	for b in buildings:
		var bx: float = _size.x * b[0]
		var bw: float = _size.x * b[2]
		var bh: float = b[3]
		var by: float = sky_y_base - bh
		var bc: Color = b[4]
		draw_rect(Rect2(bx, by, bw, bh), bc)
		# Window grid
		var wx := bx + 5.0
		while wx < bx + bw - 10.0:
			var wy := by + 8.0
			while wy < by + bh - 8.0:
				if randf() > 0.55:
					var wc := Color(0.35, 0.3, 0.45, randf_range(0.3, 0.7))
					draw_rect(Rect2(wx, wy, 5.0, 8.0), wc)
				wy += 16.0
			wx += 14.0


# ── Ground platform ───────────────────────────────────────────────────────────

func _draw_ground_platform() -> void:
	# The "diorama" raised city block.
	# Layer 0 = underground/curb sides (visible on front edge)
	# Layer 1 = street level

	# Draw all tiles back-to-front (gy 0..GRID_ROWS-1, gx 0..GRID_COLS-1)
	for gy in GRID_ROWS:
		for gx in GRID_COLS:
			_draw_ground_tile(gx, gy)

	# Front-edge drop wall (makes it look like a raised platform)
	_draw_platform_edge()


func _draw_ground_tile(gx: int, gy: int) -> void:
	var is_sidewalk := (gy <= 2 or gy >= GRID_ROWS - 2)
	var is_street   := not is_sidewalk

	if is_sidewalk:
		# Raised sidewalk: gz=1, slightly lighter
		var t := 0.5 + 0.08 * sin(gx * 0.7 + gy * 1.3)   # subtle variation
		draw_tile(gx, gy, 1.0, Color(0.09, 0.08, 0.12, 1.0).lerp(Color(0.12, 0.11, 0.16, 1.0), t))
		# Sidewalk edge (where sidewalk meets street)
		if gy == 2:
			var pts := PackedVector2Array()
			pts.append(iso(gx,       gy + 1.0, 1.0))
			pts.append(iso(gx + 1.0, gy + 1.0, 1.0))
			pts.append(iso(gx + 1.0, gy + 1.0, 0.0))
			pts.append(iso(gx,       gy + 1.0, 0.0))
			draw_colored_polygon(pts, Color(0.07, 0.06, 0.1, 1.0))
	else:
		# Street: gz=0, dark wet asphalt
		var wet := 0.4 + 0.12 * sin(gx * 1.1) * cos(gy * 0.9)  # wet sheen variation
		var base_col := Color(0.055, 0.055, 0.075, 1.0)
		var tile_col := base_col.lerp(Color(0.08, 0.07, 0.10, 1.0), wet)

		# Lane markings
		if gx == GRID_COLS / 2 and gy >= 3 and gy <= GRID_ROWS - 3:
			tile_col = Color(0.10, 0.09, 0.12, 1.0)

		draw_tile(gx, gy, 0.0, tile_col)

		# Puddle reflections (selected tiles)
		if (gx + gy * 3) % 7 == 0:
			_draw_puddle_on_tile(gx, gy)


func _draw_puddle_on_tile(gx: int, gy: int) -> void:
	# A slightly brighter sub-diamond inside the tile (reflection effect)
	var cx := float(gx) + 0.5
	var cy := float(gy) + 0.5
	var scale := 0.35
	var pts := PackedVector2Array()
	pts.append(iso(cx - scale, cy,       0.0))
	pts.append(iso(cx,         cy - scale, 0.0))
	pts.append(iso(cx + scale, cy,       0.0))
	pts.append(iso(cx,         cy + scale, 0.0))
	# Pulse with time
	var alpha := 0.12 + 0.06 * sin(_time * 1.5 + gx + gy)
	draw_colored_polygon(pts, Color(0.15, 0.18, 0.28, alpha))


func _draw_platform_edge() -> void:
	# Front and side walls of the raised platform — makes it look like a diorama
	var edge_gy := float(GRID_ROWS)
	var edge_gz := 0.0
	var drop_gz := -1.5   # below the street

	# Front edge (left face along gy = GRID_ROWS)
	for gx in GRID_COLS:
		var pts := PackedVector2Array()
		pts.append(iso(gx,       edge_gy, edge_gz))
		pts.append(iso(gx,       edge_gy, drop_gz))
		pts.append(iso(gx + 1.0, edge_gy, drop_gz))
		pts.append(iso(gx + 1.0, edge_gy, edge_gz))
		draw_colored_polygon(pts, Color(0.035, 0.03, 0.05, 1.0))
		# Edge highlight line
		iso_line(gx, edge_gy, edge_gz, gx + 1.0, edge_gy, edge_gz,
				Color(0.08, 0.07, 0.12, 0.6), 1.0)


# ── Buildings ─────────────────────────────────────────────────────────────────
# Building layout: two rows of buildings, back of the grid.
# Each building occupies several tiles.

const BUILDINGS := [
	# [gx, gy_front, width, height_units, top_col_hex, left_col_hex, right_col_hex]
	[0,  0, 3, 5, "111018", "0c0c15", "0e0e18"],   # tall left anchor
	[3,  0, 2, 3, "0f0f14", "0b0b12", "0d0d14"],
	[5,  0, 3, 6, "130f1a", "0e0b14", "100d17"],   # purple-tinted tower
	[8,  0, 2, 4, "0c0c12", "090910", "0b0b12"],
	[10, 0, 3, 5, "0f0e15", "0b0a11", "0d0c13"],
	[13, 0, 2, 3, "111018", "0c0c15", "0e0e17"],
	[15, 0, 3, 6, "100f16", "0c0b12", "0e0d14"],
	[18, 0, 2, 4, "0e0e14", "0a0a11", "0c0c13"],
	[20, 0, 2, 5, "120f18", "0d0b14", "0f0d16"],
	# second row (slightly shorter, different depth)
	[1,  1, 2, 3, "0d0c12", "090910", "0b0a12"],
	[4,  1, 3, 4, "0f0e14", "0b0a11", "0d0c13"],
	[9,  1, 2, 3, "0e0d13", "0a0911", "0c0b12"],
	[14, 1, 2, 4, "100f15", "0c0b12", "0e0d14"],
	[19, 1, 2, 3, "0d0c12", "090910", "0b0a12"],
]


func _draw_buildings() -> void:
	# Sort back to front (painter's): higher gy_front row first (they're closer)
	# Our buildings are at gy 0–1, so gy=0 is drawn first (further back)
	# Within same gy, draw lower gx first? Actually iso painter's order:
	# draw in order of (gx + gy) ascending for proper overlap.
	var sorted := BUILDINGS.duplicate()
	sorted.sort_custom(func(a, b): return (a[0] + a[1]) < (b[0] + b[1]))

	for b in sorted:
		var gx: int = b[0]
		var gy_front: int = b[1]
		var w: int = b[2]
		var h: int = b[3]  # height in elevation units
		var top_c   := Color.html("#" + b[4])
		var left_c  := Color.html("#" + b[5])
		var right_c := Color.html("#" + b[6])

		_draw_building(gx, gy_front, w, h, top_c, left_c, right_c)


func _draw_building(gx: int, gy: int, w: int, h: int,
		top_c: Color, left_c: Color, right_c: Color) -> void:

	var gz_base := 1.0   # sidewalk height
	var gz_top  := gz_base + h

	# Right face: spans gx to gx+w, front face at gy
	var rf := PackedVector2Array()
	rf.append(iso(gx + w, gy,     gz_base))
	rf.append(iso(gx + w, gy,     gz_top))
	rf.append(iso(gx + w, gy + 1, gz_top))  # depth=1 tile for right face
	rf.append(iso(gx + w, gy + 1, gz_base))
	draw_colored_polygon(rf, right_c)

	# Left face: front wall (gy side, full width)
	var lf := PackedVector2Array()
	lf.append(iso(gx,     gy + 1, gz_base))
	lf.append(iso(gx,     gy + 1, gz_top))
	lf.append(iso(gx + w, gy + 1, gz_top))
	lf.append(iso(gx + w, gy + 1, gz_base))
	draw_colored_polygon(lf, left_c)

	# Top face: w × 1 tile (we only show 1 tile deep)
	var tp := PackedVector2Array()
	tp.append(iso(gx,     gy,     gz_top))
	tp.append(iso(gx + w, gy,     gz_top))
	tp.append(iso(gx + w, gy + 1, gz_top))
	tp.append(iso(gx,     gy + 1, gz_top))
	draw_colored_polygon(tp, top_c)

	# Windows on the front face
	_draw_building_windows(gx, gy, w, h, gz_base, left_c)

	# Rooftop details
	_draw_rooftop(gx, gy, w, gz_top, top_c)


func _draw_building_windows(gx: int, gy: int, w: int, h: int,
		gz_base: float, wall_col: Color) -> void:
	# Windows as small bright quads on the front face
	var WPAD_X := 0.18
	var WPAD_Z := 0.20
	var WIN_W  := 0.28
	var WIN_H  := 0.40   # in tile units

	for wx_i in w:
		var wx := float(gx + wx_i)
		for wz_i in h:
			var wz := gz_base + float(wz_i) + WPAD_Z
			# Skip some windows (dark)
			var seed := int(wx * 7 + wz_i * 3 + gy * 11) % 5
			var is_lit := seed != 0

			var tl := iso(wx + WPAD_X,        gy + 1.0, wz + WIN_H)
			var tr := iso(wx + WPAD_X + WIN_W, gy + 1.0, wz + WIN_H)
			var br := iso(wx + WPAD_X + WIN_W, gy + 1.0, wz)
			var bl := iso(wx + WPAD_X,         gy + 1.0, wz)

			var pts := PackedVector2Array()
			pts.append(tl); pts.append(tr); pts.append(br); pts.append(bl)

			if is_lit:
				# Warm amber or cool blue-white window
				var warm := (int(wx * 3 + wz_i * 7) % 3) != 0
				var wc := Color(0.55, 0.45, 0.25, 0.85) if warm else Color(0.3, 0.4, 0.65, 0.80)
				# Flicker some windows slightly
				if (int(wx + wz_i * 2 + gy) % 4) == 0:
					wc.a *= _neon_flicker
				draw_colored_polygon(pts, wc)
				# Window glow bleed onto wall
				draw_colored_polygon(pts, Color(wc.r, wc.g, wc.b, 0.06))
			else:
				draw_colored_polygon(pts, Color(0.04, 0.04, 0.06, 0.9))

			# Window frame
			draw_polyline(pts, Color(wall_col.r * 1.5, wall_col.g * 1.5, wall_col.b * 1.5, 0.5), 0.8, false)


func _draw_rooftop(gx: int, gy: int, w: int, gz_top: float, top_c: Color) -> void:
	# Water tower, HVAC boxes, antennas
	var rx := float(gx) + w * 0.5 - 0.3
	# HVAC box
	draw_iso_box(rx, float(gy), gz_top, gz_top + 0.4,
			top_c.lightened(0.1), top_c.darkened(0.1), top_c)
	# Antenna
	iso_line(rx + 0.2, float(gy) + 0.5, gz_top + 0.4,
			 rx + 0.2, float(gy) + 0.5, gz_top + 1.2,
			 Color(0.2, 0.2, 0.3, 0.8), 1.5)


# ── Street details ────────────────────────────────────────────────────────────

func _draw_street_details() -> void:
	# Street lamps, manhole covers, yellow road lines, fire hydrants

	# Lamp posts at regular intervals
	var lamp_gxs := [2.0, 5.5, 9.0, 12.5, 16.0, 19.5]
	var lamp_gy  := float(WALK_ROW) - 1.0   # back of walkable area

	for lx in lamp_gxs:
		_draw_lamp_post(lx, lamp_gy)

	# Street center dashed line
	for gx in range(0, GRID_COLS):
		if gx % 2 == 0:
			var pts := PackedVector2Array()
			pts.append(iso(gx + 0.2, 4.5, 0.001))
			pts.append(iso(gx + 0.8, 4.5, 0.001))
			pts.append(iso(gx + 0.8, 4.6, 0.001))
			pts.append(iso(gx + 0.2, 4.6, 0.001))
			draw_colored_polygon(pts, Color(0.18, 0.16, 0.12, 0.55))

	# Manhole covers
	for gx in [4, 10, 16]:
		_draw_manhole(float(gx) + 0.5, 4.5)

	# Parked car silhouette
	_draw_parked_car(7.0, 5.5)
	_draw_parked_car(14.0, 5.5)


func _draw_lamp_post(gx: float, gy: float) -> void:
	# Post
	var base_gz := 1.0  # sidewalk height
	iso_line(gx, gy + 0.5, base_gz, gx, gy + 0.5, base_gz + 3.5,
			Color(0.18, 0.16, 0.25, 1.0), 2.5)
	# Arm
	iso_line(gx, gy + 0.5, base_gz + 3.5, gx + 0.4, gy + 0.5, base_gz + 3.5,
			Color(0.18, 0.16, 0.25, 1.0), 1.5)
	# Lamp head
	var head := iso(gx + 0.4, gy + 0.5, base_gz + 3.5)
	# Glow halos
	for g in 6:
		var ga := 0.09 - float(g) * 0.013
		var gr := 8.0 + g * 12.0
		draw_circle(head, gr, Color(0.65, 0.60, 0.85, ga))
	draw_circle(head, 5.0, Color(0.85, 0.82, 0.95, 0.9))

	# Light cone projected onto street (very faint triangle)
	var p0 := head
	var p1 := iso(gx - 0.5, gy + 1.5, 0.0)
	var p2 := iso(gx + 1.2, gy + 1.5, 0.0)
	var light_pts := PackedVector2Array()
	light_pts.append(p0); light_pts.append(p1); light_pts.append(p2)
	draw_colored_polygon(light_pts, Color(0.4, 0.38, 0.55, 0.04))


func _draw_manhole(gx: float, gy: float) -> void:
	var pts := PackedVector2Array()
	var r := 0.22
	for i in 8:
		var a := TAU * float(i) / 8.0
		pts.append(iso(gx + cos(a) * r, gy + sin(a) * r * 0.5, 0.002))
	draw_colored_polygon(pts, Color(0.07, 0.07, 0.10, 1.0))
	# Cross lines
	iso_line(gx - r, gy, 0.002, gx + r, gy, 0.002, Color(0.10, 0.10, 0.14, 1.0), 1.0)
	iso_line(gx, gy - r * 0.5, 0.002, gx, gy + r * 0.5, 0.002, Color(0.10, 0.10, 0.14, 1.0), 1.0)


func _draw_parked_car(gx: float, gy: float) -> void:
	# Simple iso box for car body
	var cw := 1.8; var cd := 0.9; var ch := 0.7
	var body_col := Color(0.08, 0.10, 0.14, 1.0)

	# Car body
	var rf := PackedVector2Array()
	rf.append(iso(gx + cw, gy,      0.0))
	rf.append(iso(gx + cw, gy,      ch))
	rf.append(iso(gx + cw, gy + cd, ch))
	rf.append(iso(gx + cw, gy + cd, 0.0))
	draw_colored_polygon(rf, body_col.darkened(0.15))

	var lf := PackedVector2Array()
	lf.append(iso(gx,      gy + cd, 0.0))
	lf.append(iso(gx,      gy + cd, ch))
	lf.append(iso(gx + cw, gy + cd, ch))
	lf.append(iso(gx + cw, gy + cd, 0.0))
	draw_colored_polygon(lf, body_col)

	var tp := PackedVector2Array()
	tp.append(iso(gx,      gy,      ch))
	tp.append(iso(gx + cw, gy,      ch))
	tp.append(iso(gx + cw, gy + cd, ch))
	tp.append(iso(gx,      gy + cd, ch))
	draw_colored_polygon(tp, body_col.lightened(0.05))

	# Windshield glint
	var wf := PackedVector2Array()
	wf.append(iso(gx + 0.3, gy + cd, ch * 0.6))
	wf.append(iso(gx + 0.3, gy + cd, ch * 0.95))
	wf.append(iso(gx + 1.5, gy + cd, ch * 0.95))
	wf.append(iso(gx + 1.5, gy + cd, ch * 0.6))
	draw_colored_polygon(wf, Color(0.15, 0.20, 0.30, 0.55))

	# Taillights
	for side in [0.1, cw - 0.25]:
		var tl_pts := PackedVector2Array()
		tl_pts.append(iso(gx + side,        gy + cd, 0.15))
		tl_pts.append(iso(gx + side,        gy + cd, 0.35))
		tl_pts.append(iso(gx + side + 0.15, gy + cd, 0.35))
		tl_pts.append(iso(gx + side + 0.15, gy + cd, 0.15))
		draw_colored_polygon(tl_pts, Color(0.9, 0.1, 0.05, 0.8))


# ── Location facades (doors + neon signs) ─────────────────────────────────────

func _draw_location_facades() -> void:
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx: float = _loc_grid_x(d)
		var sign_col  := Color.html(_str(d.get("sign_color"))  if d.get("sign_color")  != null else "#ffffff")
		var glow_col  := Color.html(_str(d.get("sign_glow"))   if d.get("sign_glow")   != null else "#888888")
		var sign_text: String = _str(d.get("sign_text"))
		var uc: String = _str(d.get("unlock_clue"))
		var locked: bool = uc != "" and not (uc in GameState.discovered_clues)

		_draw_doorway(lx, 2.0, locked)
		_draw_neon_sign(lx, 2.0, sign_text, sign_col, glow_col, locked)

		# Proximity highlight (green ground indicator)
		var loc_id := _str(d.get("id"))
		if loc_id == _near_location_id:
			_draw_proximity_indicator(lx, float(WALK_ROW))


func _draw_doorway(gx: float, gy: float, locked: bool) -> void:
	# A recessed doorway on the front face of the building row
	# Door frame (left face of a short box representing door opening)
	var dw := 0.6; var dh := 1.8; var gz := 1.0
	var frame_col := Color(0.06, 0.05, 0.09, 1.0)
	var door_col  := Color(0.04, 0.04, 0.06, 1.0) if locked else Color(0.07, 0.06, 0.10, 1.0)

	# Door left face
	var lf := PackedVector2Array()
	lf.append(iso(gx - dw * 0.5, gy + 1.0, gz))
	lf.append(iso(gx - dw * 0.5, gy + 1.0, gz + dh))
	lf.append(iso(gx + dw * 0.5, gy + 1.0, gz + dh))
	lf.append(iso(gx + dw * 0.5, gy + 1.0, gz))
	draw_colored_polygon(lf, door_col)

	# Door frame border
	draw_polyline(lf, frame_col.lightened(0.15), 1.0, false)

	# Door knob
	var knob := iso(gx + dw * 0.15, gy + 1.0, gz + dh * 0.45)
	draw_circle(knob, 2.0, Color(0.5, 0.4, 0.2, 0.9))

	# Steps down from sidewalk to street
	for s in 2:
		var sz := gz - float(s) * 0.4
		var sf := PackedVector2Array()
		sf.append(iso(gx - dw * 0.5 - float(s) * 0.1, gy + 1.0 + float(s) * 0.15, sz))
		sf.append(iso(gx + dw * 0.5 + float(s) * 0.1, gy + 1.0 + float(s) * 0.15, sz))
		sf.append(iso(gx + dw * 0.5 + float(s) * 0.1, gy + 1.0 + float(s+1) * 0.15, sz - 0.4))
		sf.append(iso(gx - dw * 0.5 - float(s) * 0.1, gy + 1.0 + float(s+1) * 0.15, sz - 0.4))
		draw_colored_polygon(sf, Color(0.07, 0.06, 0.10, 1.0))


func _draw_neon_sign(gx: float, gy: float, text: String,
		sign_col: Color, glow_col: Color, locked: bool) -> void:
	var gz_sign := 1.0 + 2.2   # above doorway on the building face
	var sign_w  := 1.2
	var sign_h  := 0.5

	var sc := sign_col if not locked else Color(0.15, 0.14, 0.20, 1.0)
	var gc := glow_col if not locked else Color(0.06, 0.05, 0.08, 1.0)

	# Glow halos (multiple layers)
	if not locked:
		var flicker_sc := Color(sc.r, sc.g, sc.b, sc.a * _neon_flicker)
		for g in 5:
			var ga := 0.10 - float(g) * 0.016
			var exp := float(g) * 0.12
			var gp := PackedVector2Array()
			gp.append(iso(gx - sign_w * 0.5 - exp, gy + 1.0, gz_sign - exp * 0.5))
			gp.append(iso(gx + sign_w * 0.5 + exp, gy + 1.0, gz_sign - exp * 0.5))
			gp.append(iso(gx + sign_w * 0.5 + exp, gy + 1.0, gz_sign + sign_h + exp * 0.5))
			gp.append(iso(gx - sign_w * 0.5 - exp, gy + 1.0, gz_sign + sign_h + exp * 0.5))
			draw_colored_polygon(gp, Color(gc.r, gc.g, gc.b, ga * _neon_flicker))

	# Sign backing
	var sp := PackedVector2Array()
	sp.append(iso(gx - sign_w * 0.5, gy + 1.0, gz_sign))
	sp.append(iso(gx + sign_w * 0.5, gy + 1.0, gz_sign))
	sp.append(iso(gx + sign_w * 0.5, gy + 1.0, gz_sign + sign_h))
	sp.append(iso(gx - sign_w * 0.5, gy + 1.0, gz_sign + sign_h))
	draw_colored_polygon(sp, Color(0.03, 0.03, 0.05, 0.95))

	# Sign text (center of sign face, screen-space)
	var text_pos := iso(gx, gy + 1.0, gz_sign + sign_h * 0.55)
	draw_string(ThemeDB.fallback_font, text_pos - Vector2(text.length() * 4.0, 0.0),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, sc)

	# Neon tube border
	draw_polyline(sp, sc, 1.2, false)

	# Reflection on wet sidewalk below sign
	if not locked:
		var refl_gz := 1.001  # just above sidewalk
		var refl_alpha := 0.12 * _neon_flicker
		for rx_off in [-0.3, 0.0, 0.3]:
			var r1 := iso(gx + rx_off - 0.05, gy + 0.8, refl_gz)
			var r2 := iso(gx + rx_off + 0.05, gy + 0.8, refl_gz)
			var r3 := iso(gx + rx_off + 0.07, gy + 1.0, refl_gz)
			var r4 := iso(gx + rx_off - 0.07, gy + 1.0, refl_gz)
			var rpts := PackedVector2Array()
			rpts.append(r1); rpts.append(r2); rpts.append(r3); rpts.append(r4)
			draw_colored_polygon(rpts, Color(sc.r, sc.g, sc.b, refl_alpha))


func _draw_proximity_indicator(gx: float, gy: float) -> void:
	# Animated diamond on the ground in front of the door
	var pulse := 0.6 + 0.4 * sin(_time * 3.0)
	var pts := PackedVector2Array()
	var r := 0.25 * pulse
	pts.append(iso(gx - r, gy + 0.5, 0.002))
	pts.append(iso(gx,     gy + 0.5 - r * 0.5, 0.002))
	pts.append(iso(gx + r, gy + 0.5, 0.002))
	pts.append(iso(gx,     gy + 0.5 + r * 0.5, 0.002))
	draw_colored_polygon(pts, Color(0.3, 1.0, 0.4, 0.35 * pulse))
	draw_polyline(pts, Color(0.4, 1.0, 0.5, 0.7 * pulse), 1.0, false)


# ── Player ────────────────────────────────────────────────────────────────────

func _draw_player() -> void:
	var gy := float(WALK_ROW)
	var gz := 0.0   # street level (will be on top of the sidewalk when near buildings)
	# Detect if player is on sidewalk row
	if gy <= 2.0 or gy >= float(GRID_ROWS) - 2.0:
		gz = 1.0

	var pos := iso(_player_gx, gy + 0.5, gz)

	# Shadow ellipse on ground
	var shadow_pts := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0
		shadow_pts.append(iso(_player_gx + cos(a) * 0.25, gy + 0.5 + sin(a) * 0.12, gz + 0.01))
	draw_colored_polygon(shadow_pts, Color(0.0, 0.0, 0.0, 0.45))

	# Character is drawn in screen-space from the iso position
	_draw_character_sprite(pos)

	# Green indicator above head
	var head_pos := pos - Vector2(0, 52)
	var marker_alpha := 0.7 + 0.3 * sin(_time * 2.5)
	draw_circle(head_pos - Vector2(0, 8), 3.5, Color(0.3, 1.0, 0.4, marker_alpha))


func _draw_character_sprite(pos: Vector2) -> void:
	# A modern-looking silhouette: hoodie/jacket, slim legs.
	# All coords relative to pos (feet = pos)
	var body  := Color(0.10, 0.10, 0.16, 1.0)
	var acc   := Color(0.20, 0.20, 0.30, 1.0)   # highlight/collar
	var bob   := sin(_player_walk_t) * 2.0 if _player_moving else 0.0
	var flip  := -1.0 if _player_dir < 0 else 1.0

	# Legs
	var leg_sep := 4.0
	var leg_h   := 20.0
	var step1   :=  sin(_player_walk_t) * 5.0 if _player_moving else 0.0
	var step2   := -step1

	# Left leg
	draw_rect(Rect2(pos.x - leg_sep * flip - 3.0, pos.y - leg_h + bob + step1, 5.0, leg_h), body)
	# Right leg
	draw_rect(Rect2(pos.x + (leg_sep - 2.0) * flip - 2.0, pos.y - leg_h + bob + step2, 5.0, leg_h), body)

	# Torso (hoodie body)
	draw_rect(Rect2(pos.x - 8.0, pos.y - leg_h - 22.0 + bob, 16.0, 24.0), body)
	# Hood / collar accent
	draw_rect(Rect2(pos.x - 7.0, pos.y - leg_h - 22.0 + bob, 14.0, 5.0), acc)

	# Arms
	var arm_swing := sin(_player_walk_t) * 7.0 if _player_moving else 0.0
	# Left arm
	draw_rect(Rect2(pos.x - 14.0 * flip, pos.y - leg_h - 18.0 + bob + arm_swing * flip, 5.0, 15.0), body)
	# Right arm
	draw_rect(Rect2(pos.x + 9.0 * flip, pos.y - leg_h - 18.0 + bob - arm_swing * flip, 5.0, 15.0), body)

	# Head
	draw_circle(pos - Vector2(0.0, leg_h + 31.0 - bob), 8.0, body)
	# Face direction hint (small highlight)
	draw_circle(pos - Vector2(-3.0 * flip, leg_h + 32.0 - bob), 2.5, Color(0.25, 0.22, 0.35, 0.7))

	# Backpack / laptop bag hint
	draw_rect(Rect2(pos.x - 10.0 * flip - (5.0 if flip < 0 else 0.0),
			pos.y - leg_h - 18.0 + bob, 6.0, 14.0),
			Color(0.12, 0.12, 0.18, 1.0))


# ── Rain ──────────────────────────────────────────────────────────────────────

func _draw_rain() -> void:
	var rain_col := Color(0.45, 0.50, 0.70, 0.18)
	var dx := 2.5
	for r in _rain:
		var p: Vector2 = r["pos"]
		var length: float = r["len"]
		draw_line(p, p + Vector2(dx, length), rain_col, 0.8)


# ── Tilt-shift (depth-of-field simulation) ───────────────────────────────────

func _draw_tilt_shift() -> void:
	# Dark gradient overlay top and bottom to simulate DOF / lens vignette
	var grad_h := _size.y * 0.18
	# Top
	for i in 10:
		var t := float(i) / 10.0
		draw_rect(Rect2(0.0, grad_h * (1.0 - t) * 0.0, _size.x, grad_h / 10.0 + 1.0),
				Color(0.0, 0.0, 0.0, 0.0))
	# Simpler approach — just solid-ish dark bands
	draw_rect(Rect2(0, 0, _size.x, _size.y * 0.08), Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(0, _size.y * 0.88, _size.x, _size.y * 0.12), Color(0.0, 0.0, 0.0, 0.55))
	# Side vignette
	draw_rect(Rect2(0, 0, _size.x * 0.06, _size.y), Color(0.0, 0.0, 0.0, 0.3))
	draw_rect(Rect2(_size.x * 0.94, 0, _size.x * 0.06, _size.y), Color(0.0, 0.0, 0.0, 0.3))


# ── Minimap ───────────────────────────────────────────────────────────────────

func _draw_minimap() -> void:
	var ms: Vector2 = _minimap_ctrl.get_rect().size
	if ms == Vector2.ZERO:
		return

	_minimap_ctrl.draw_rect(Rect2(0, 0, ms.x, ms.y), Color(0.02, 0.02, 0.04, 0.90))
	_minimap_ctrl.draw_rect(Rect2(0, 0, ms.x, 1.0),  Color(0.12, 0.12, 0.22, 1.0))
	_minimap_ctrl.draw_rect(Rect2(0, ms.y - 1.0, ms.x, 1.0), Color(0.12, 0.12, 0.22, 1.0))
	_minimap_ctrl.draw_rect(Rect2(0, 0, 1.0, ms.y),   Color(0.12, 0.12, 0.22, 1.0))
	_minimap_ctrl.draw_rect(Rect2(ms.x - 1.0, 0, 1.0, ms.y), Color(0.12, 0.12, 0.22, 1.0))

	var pad := 10.0
	var bar_y := ms.y * 0.55
	var map_w := ms.x - pad * 2.0
	_minimap_ctrl.draw_rect(Rect2(pad, bar_y - 2.0, map_w, 4.0), Color(0.10, 0.10, 0.18, 1.0))

	# Location markers
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx: float = _loc_grid_x(d)
		var sc_str := _str(d.get("sign_color")) if d.get("sign_color") != null else "#aaaaaa"
		var sc := Color.html(sc_str)
		var uc: String = _str(d.get("unlock_clue"))
		var locked: bool = uc != "" and not (uc in GameState.discovered_clues)
		var mx: float = pad + (lx / float(GRID_COLS)) * map_w
		var col := Color(sc.r, sc.g, sc.b, 0.3 if locked else 0.85)
		_minimap_ctrl.draw_rect(Rect2(mx - 3.0, bar_y - 5.0, 6.0, 10.0), col)

	# Player dot
	var px: float = pad + (_player_gx / float(GRID_COLS)) * map_w
	var blink := (sin(Time.get_ticks_msec() * 0.007) + 1.0) * 0.5
	_minimap_ctrl.draw_circle(Vector2(px, bar_y), 3.5, Color(0.2, 1.0, 0.45, 0.6 + blink * 0.4))

	# Label
	_minimap_ctrl.draw_string(ThemeDB.fallback_font, Vector2(pad, ms.y - 5.0),
			"CITY BLOCK — 2AM", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.3, 0.45, 0.75))


# ── Enter location ────────────────────────────────────────────────────────────

func _try_enter(loc_id: String) -> void:
	if _entering_scene:
		return
	var loc := _get_location(loc_id)
	if loc.is_empty():
		return

	var uc: String = _str(loc.get("unlock_clue"))
	if uc != "" and not (uc in GameState.discovered_clues):
		# Flash locked message
		var name_str := _str(loc.get("name"))
		_prompt_label.text = (name_str if name_str != "" else "location") + " — not yet accessible"
		_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
		_prompt_label.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(2.2)
		tw.tween_callback(func():
			_prompt_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75, 1.0)))
		return

	_entering_scene = true
	var interior_type: String = _str(loc.get("interior_type"))
	var scene_path := ""
	match interior_type:
		"cafe":       scene_path = CAFE_SCENE
		"bar":        scene_path = BAR_SCENE
		"apartment":  scene_path = APARTMENT_SCENE

	if scene_path == "":
		_entering_scene = false
		return

	var parent := get_parent()
	if parent == null:
		_entering_scene = false
		return

	var res := load(scene_path)
	if res == null:
		_entering_scene = false
		return

	var interior: Control = res.instantiate()
	interior.set_meta("location_id", loc_id)
	interior.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(interior)
	queue_free()


# ── Utility ───────────────────────────────────────────────────────────────────

func _draw_ellipse(cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, col)
