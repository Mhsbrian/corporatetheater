extends Control

# Corporate Theater — Outside (Isometric Street Scene)
#
# Visual target: Final Fantasy Tactics / HD-2D isometric diorama.
# A raised city block viewed from ~30° above, 45° to the side.
# Everything drawn with _draw() using isometric projection math.
#
# Grid layout (gy = depth, 0 = farthest back):
#   gy 0        back alley (narrow, shadowed)
#   gy 1-3      buildings row A (tallest, set back)
#   gy 4        buildings row B (mid-height, shop fronts)
#   gy 5        back sidewalk (raised gz=1.2)
#   gy 6-7      road (two lanes, gz=0)
#   gy 8-9      front sidewalk (raised gz=1.0, player walks here)
#   gy 10-11    near kerb / platform edge

const LOCATIONS_PATH  := "res://data/world/locations.json"
const CAFE_SCENE      := "res://scenes/world/cafe_interior.tscn"
const BAR_SCENE       := "res://scenes/world/bar_interior.tscn"
const APARTMENT_SCENE := "res://scenes/world/apartment_interior.tscn"

# ── Isometric projection ─────────────────────────────────────────────────────
const TILE_W  := 80.0
const TILE_H  := 40.0
const TILE_Z  := 40.0

# Grid dimensions — expanded for a much busier block
const GRID_COLS := 34
const GRID_ROWS := 12
const WALK_ROW  := 8    # player walks front sidewalk

# Elevation constants
const GZ_STREET    := 0.0
const GZ_SIDEWALK  := 1.0
const GZ_BACK_SW   := 1.2

# ── Camera / player ───────────────────────────────────────────────────────────
const PLAYER_SPEED  := 5.0
const CAMERA_LERP   := 5.5
const INTERACT_DIST := 1.6

var _player_gx: float  = 4.0
var _camera_offset: float = 0.0
var _target_cam: float = 0.0
var _player_walk_t: float = 0.0
var _player_moving: bool = false
var _player_dir: int = 1

var _origin: Vector2 = Vector2.ZERO
var _size: Vector2   = Vector2.ZERO

# ── Scene data ────────────────────────────────────────────────────────────────
var _locations: Array = []
var _near_location_id: String = ""
var _prompt_alpha: float = 0.0
var _entering_scene: bool = false

# ── Pedestrians ───────────────────────────────────────────────────────────────
# Each: {gx, dir, walk_t, speed, col_idx}
var _peds: Array = []
const PED_ROW := 5.5    # back sidewalk gy

# ── Rain ──────────────────────────────────────────────────────────────────────
const RAIN_COUNT := 160
var _rain: Array = []

# ── Ambient ───────────────────────────────────────────────────────────────────
var _time: float = 0.0
var _neon_flicker: float = 1.0
var _flicker_timer: float = 0.0

# Seeded window states — computed once, never flicker
var _bg_win_states: Array = []   # Array[bool]
const BG_WIN_COUNT := 400

# ── UI ────────────────────────────────────────────────────────────────────────
var _prompt_label: Label
var _esc_label: Label
var _minimap_ctrl: Control


# ── Helpers ───────────────────────────────────────────────────────────────────

func _str(v: Variant) -> String:
	if v == null: return ""
	return str(v)

func iso(gx: float, gy: float, gz: float = 0.0) -> Vector2:
	var sx := (gx - gy) * (TILE_W * 0.5)
	var sy := (gx + gy) * (TILE_H * 0.5) - gz * TILE_Z
	return _origin + Vector2(sx, sy)

func tile_top(gx: float, gy: float, gz: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(iso(gx,       gy + 0.5, gz))
	pts.append(iso(gx + 0.5, gy,       gz))
	pts.append(iso(gx + 1.0, gy + 0.5, gz))
	pts.append(iso(gx + 0.5, gy + 1.0, gz))
	return pts

func box_left(gx: float, gy: float, gz_bot: float, gz_top: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(iso(gx,       gy + 1.0, gz_bot))
	pts.append(iso(gx,       gy + 1.0, gz_top))
	pts.append(iso(gx + 1.0, gy + 1.0, gz_top))
	pts.append(iso(gx + 1.0, gy + 1.0, gz_bot))
	return pts

func box_right(gx: float, gy: float, gz_bot: float, gz_top: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(iso(gx + 1.0, gy,       gz_bot))
	pts.append(iso(gx + 1.0, gy,       gz_top))
	pts.append(iso(gx + 1.0, gy + 1.0, gz_top))
	pts.append(iso(gx + 1.0, gy + 1.0, gz_bot))
	return pts

func draw_iso_box(gx: float, gy: float, gz_bot: float, gz_top: float,
		top_col: Color, left_col: Color, right_col: Color) -> void:
	# Right face
	var rf := PackedVector2Array()
	rf.append(iso(gx + 1.0, gy,       gz_bot))
	rf.append(iso(gx + 1.0, gy,       gz_top))
	rf.append(iso(gx + 1.0, gy + 1.0, gz_top))
	rf.append(iso(gx + 1.0, gy + 1.0, gz_bot))
	draw_colored_polygon(rf, right_col)
	draw_colored_polygon(box_left(gx, gy, gz_bot, gz_top), left_col)
	draw_colored_polygon(tile_top(gx, gy, gz_top), top_col)

func draw_iso_box_w(gx: float, gy: float, w: float, d: float,
		gz_bot: float, gz_top: float,
		top_col: Color, left_col: Color, right_col: Color) -> void:
	# Right face
	var rf := PackedVector2Array()
	rf.append(iso(gx + w, gy,     gz_bot))
	rf.append(iso(gx + w, gy,     gz_top))
	rf.append(iso(gx + w, gy + d, gz_top))
	rf.append(iso(gx + w, gy + d, gz_bot))
	draw_colored_polygon(rf, right_col)
	# Left / front face
	var lf := PackedVector2Array()
	lf.append(iso(gx,     gy + d, gz_bot))
	lf.append(iso(gx,     gy + d, gz_top))
	lf.append(iso(gx + w, gy + d, gz_top))
	lf.append(iso(gx + w, gy + d, gz_bot))
	draw_colored_polygon(lf, left_col)
	# Top face
	var tp := PackedVector2Array()
	tp.append(iso(gx,     gy,     gz_top))
	tp.append(iso(gx + w, gy,     gz_top))
	tp.append(iso(gx + w, gy + d, gz_top))
	tp.append(iso(gx,     gy + d, gz_top))
	draw_colored_polygon(tp, top_col)

func draw_tile(gx: float, gy: float, gz: float, col: Color) -> void:
	draw_colored_polygon(tile_top(gx, gy, gz), col)

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
	_init_pedestrians()
	_init_bg_windows()
	_build_ui()
	_recalc_origin()


func _load_locations() -> void:
	if not FileAccess.file_exists(LOCATIONS_PATH): return
	var file := FileAccess.open(LOCATIONS_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_locations = (json.data as Dictionary).get("locations", []) as Array


func _init_rain() -> void:
	_rain.clear()
	for i in RAIN_COUNT:
		_rain.append({
			"pos":   Vector2(randf_range(0.0, 1920.0), randf_range(0.0, 1080.0)),
			"len":   randf_range(10.0, 24.0),
			"speed": randf_range(320.0, 560.0),
			"alpha": randf_range(0.10, 0.22)
		})


func _init_pedestrians() -> void:
	_peds.clear()
	var ped_colors := [0, 1, 2, 3, 4]
	for i in 5:
		_peds.append({
			"gx":     randf_range(2.0, float(GRID_COLS) - 2.0),
			"dir":    1 if i % 2 == 0 else -1,
			"walk_t": randf_range(0.0, TAU),
			"speed":  randf_range(1.2, 2.2),
			"col":    ped_colors[i % ped_colors.size()]
		})


func _init_bg_windows() -> void:
	_bg_win_states.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in BG_WIN_COUNT:
		_bg_win_states.append(rng.randf() > 0.48)


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
	_esc_label.add_theme_color_override("font_color", Color(0.30, 0.30, 0.42, 1.0))
	_esc_label.add_theme_font_size_override("font_size", 11)
	_esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_esc_label.text = "[ ESC ] desktop   [ ← → / A D ] move   [ E ] enter"
	_esc_label.set_anchor_and_offset(SIDE_LEFT,   0.0,  8.0)
	_esc_label.set_anchor_and_offset(SIDE_RIGHT,  1.0, -8.0)
	_esc_label.set_anchor_and_offset(SIDE_TOP,    1.0, -22.0)
	_esc_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -4.0)
	add_child(_esc_label)

	_minimap_ctrl = Control.new()
	_minimap_ctrl.set_anchor_and_offset(SIDE_RIGHT,  1.0, -10.0)
	_minimap_ctrl.set_anchor_and_offset(SIDE_LEFT,   1.0, -210.0)
	_minimap_ctrl.set_anchor_and_offset(SIDE_TOP,    0.0,  10.0)
	_minimap_ctrl.set_anchor_and_offset(SIDE_BOTTOM, 0.0,  62.0)
	_minimap_ctrl.draw.connect(_draw_minimap)
	add_child(_minimap_ctrl)


func _recalc_origin() -> void:
	_size = get_rect().size
	if _size == Vector2.ZERO: return
	var center_gx := GRID_COLS * 0.5
	var center_gy := GRID_ROWS * 0.5
	var sx := (center_gx - center_gy) * (TILE_W * 0.5)
	var sy := (center_gx + center_gy) * (TILE_H * 0.5)
	var screen_target := Vector2(_size.x * 0.5 - _camera_offset, _size.y * 0.40)
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
	if _size == Vector2.ZERO: return
	_time += delta
	_update_neon_flicker(delta)
	_handle_movement(delta)
	_update_camera(delta)
	_update_rain(delta)
	_update_pedestrians(delta)
	_update_prompt(delta)
	_recalc_origin()
	queue_redraw()
	_minimap_ctrl.queue_redraw()


func _update_neon_flicker(delta: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(0.06, 0.45)
		_neon_flicker = randf_range(0.78, 1.0)


func _handle_movement(delta: float) -> void:
	var move := 0
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): move -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): move += 1
	_player_moving = move != 0
	if move != 0:
		_player_dir = move
		_player_gx = clampf(_player_gx + move * PLAYER_SPEED * delta, 1.0, float(GRID_COLS) - 2.0)
		_player_walk_t += delta * 5.0
	_near_location_id = ""
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx: float = _loc_grid_x(d)
		if abs(_player_gx - lx) < INTERACT_DIST:
			_near_location_id = _str(d.get("id"))
			break


func _loc_grid_x(d: Dictionary) -> float:
	# Map locations.json street_x (480–1700) → grid cols 3–28
	var raw: float = d.get("street_x", 480.0)
	return remap(raw, 480.0, 1700.0, 3.0, 28.0)


func _update_camera(delta: float) -> void:
	var player_screen_x: float = (_player_gx - float(WALK_ROW)) * (TILE_W * 0.5)
	_target_cam = player_screen_x
	_camera_offset = lerpf(_camera_offset, _target_cam, CAMERA_LERP * delta)


func _update_rain(delta: float) -> void:
	for r in _rain:
		r["pos"] = r["pos"] + Vector2(3.5, r["speed"]) * delta
		if r["pos"].y > _size.y + 20.0:
			r["pos"] = Vector2(randf_range(-100.0, _size.x + 100.0), -24.0)


func _update_pedestrians(delta: float) -> void:
	for p in _peds:
		p["gx"]     = p["gx"] + float(p["dir"]) * float(p["speed"]) * delta
		p["walk_t"] = p["walk_t"] + delta * 5.5
		if p["gx"] > float(GRID_COLS) - 1.0:
			p["dir"] = -1
		elif p["gx"] < 1.0:
			p["dir"] = 1


func _update_prompt(delta: float) -> void:
	var want: float = 1.0 if _near_location_id != "" else 0.0
	_prompt_alpha = lerpf(_prompt_alpha, want, 8.0 * delta)
	_prompt_label.modulate.a = _prompt_alpha
	if _near_location_id != "":
		var loc := _get_location(_near_location_id)
		var ep  := _str(loc.get("enter_prompt"))
		_prompt_label.text = ep if ep != "" else "[ E ] enter"
	else:
		_prompt_label.text = ""


func _get_location(loc_id: String) -> Dictionary:
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		if _str(d.get("id")) == loc_id: return d
	return {}


# ══════════════════════════════════════════════════════════════════════════════
# DRAW
# Painter order: sky → background → ground → buildings → street props →
#                facades → pedestrians → player → rain → vignette
# ══════════════════════════════════════════════════════════════════════════════

func _draw() -> void:
	if _size == Vector2.ZERO or _origin == Vector2.ZERO: return
	_draw_sky()
	_draw_fog_layers()
	_draw_ground_platform()
	_draw_alley()
	_draw_buildings()
	_draw_overhead_cables()
	_draw_street_details()
	_draw_location_facades()
	_draw_pedestrians()
	_draw_player()
	_draw_rain()
	_draw_tilt_shift()


# ── Sky ───────────────────────────────────────────────────────────────────────

func _draw_sky() -> void:
	draw_rect(Rect2(0, 0, _size.x, _size.y), Color(0.018, 0.016, 0.032, 1.0))

	# Horizon warmth band
	var hor_y := _origin.y + (GRID_COLS + GRID_ROWS) * TILE_H * 0.35
	for i in 18:
		var t := float(i) / 18.0
		draw_rect(Rect2(0.0, hor_y - i * 9.0, _size.x, 9.0),
				Color(0.10, 0.04, 0.14, 0.06 * (1.0 - t)))

	# Large atmospheric glow blobs
	var glows := [
		[0.10, 0.26, 380.0, 95.0,  Color(0.10, 0.03, 0.18, 0.16)],
		[0.32, 0.20, 300.0, 75.0,  Color(0.14, 0.05, 0.08, 0.14)],
		[0.55, 0.24, 420.0, 100.0, Color(0.04, 0.08, 0.22, 0.18)],
		[0.76, 0.18, 260.0, 65.0,  Color(0.12, 0.03, 0.14, 0.15)],
		[0.92, 0.28, 200.0, 55.0,  Color(0.06, 0.05, 0.18, 0.12)],
	]
	for g in glows:
		_draw_ellipse(_size.x * g[0], _size.y * g[1], g[2], g[3], g[4])

	# Distant billboard (top-left quadrant)
	_draw_bg_billboard()

	# Background skyline
	_draw_bg_skyline()


func _draw_bg_billboard() -> void:
	# A large ClosedAI billboard looming in the distance
	var bx := _size.x * 0.08
	var by := _size.y * 0.10
	var bw := 160.0; var bh := 70.0
	draw_rect(Rect2(bx, by, bw, bh), Color(0.05, 0.04, 0.08, 0.9))
	draw_rect(Rect2(bx, by, bw, 2.0), Color(0.20, 0.08, 0.35, 0.7))
	draw_rect(Rect2(bx, by + bh - 2.0, bw, 2.0), Color(0.20, 0.08, 0.35, 0.7))
	# Text lines
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(bx + 8, by + 22), "CLOSEDAI",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.75, 0.28, 0.90, 0.85 * _neon_flicker))
	draw_string(font, Vector2(bx + 8, by + 40), "TRUSTED. SAFE. INEVITABLE.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.40, 0.38, 0.52, 0.55))
	# Support pylons
	draw_line(Vector2(bx + 30, by + bh), Vector2(bx + 30, by + bh + 40),
			Color(0.08, 0.07, 0.12, 0.7), 2.0)
	draw_line(Vector2(bx + bw - 30, by + bh), Vector2(bx + bw - 30, by + bh + 40),
			Color(0.08, 0.07, 0.12, 0.7), 2.0)


func _draw_bg_skyline() -> void:
	var sky_y_base: float = _origin.y + 5.0
	# [x_frac, w_frac, height, color]
	var buildings := [
		[0.02, 0.04, 200.0, Color(0.04, 0.04, 0.07)],
		[0.07, 0.05, 260.0, Color(0.05, 0.04, 0.09)],
		[0.13, 0.06, 180.0, Color(0.04, 0.03, 0.07)],
		[0.20, 0.04, 300.0, Color(0.05, 0.04, 0.08)],
		[0.25, 0.07, 220.0, Color(0.04, 0.04, 0.07)],
		[0.33, 0.05, 350.0, Color(0.06, 0.04, 0.09)],  # tall spire
		[0.39, 0.04, 210.0, Color(0.04, 0.04, 0.07)],
		[0.44, 0.06, 280.0, Color(0.05, 0.04, 0.08)],
		[0.51, 0.05, 190.0, Color(0.04, 0.03, 0.07)],
		[0.57, 0.07, 330.0, Color(0.05, 0.04, 0.09)],
		[0.65, 0.05, 240.0, Color(0.04, 0.04, 0.07)],
		[0.71, 0.06, 200.0, Color(0.05, 0.04, 0.08)],
		[0.78, 0.04, 270.0, Color(0.04, 0.03, 0.08)],
		[0.83, 0.07, 180.0, Color(0.04, 0.04, 0.07)],
		[0.91, 0.05, 250.0, Color(0.05, 0.04, 0.09)],
		[0.97, 0.04, 160.0, Color(0.04, 0.04, 0.07)],
	]
	var win_idx := 0
	for b in buildings:
		var bx: float = _size.x * b[0]
		var bw: float = _size.x * b[1]
		var bh: float = b[2]
		var by: float = sky_y_base - bh
		var bc: Color = b[3]
		draw_rect(Rect2(bx, by, bw, bh), bc)
		# Window grid — uses pre-seeded states, no randf() per frame
		var wx := bx + 4.0
		while wx < bx + bw - 8.0:
			var wy := by + 6.0
			while wy < by + bh - 6.0:
				if win_idx < _bg_win_states.size() and _bg_win_states[win_idx]:
					var warm := (win_idx % 3) != 0
					var wc := Color(0.45, 0.38, 0.22, 0.55) if warm else Color(0.28, 0.36, 0.60, 0.50)
					draw_rect(Rect2(wx, wy, 5.0, 8.0), wc)
				win_idx += 1
				wy += 15.0
			wx += 13.0
		# Rooftop antenna dot (comm tower)
		if bh > 260.0:
			draw_circle(Vector2(bx + bw * 0.5, by - 8.0), 2.0,
					Color(0.9, 0.2, 0.2, 0.6 + 0.4 * sin(_time * 1.8 + b[0] * 10.0)))


func _draw_fog_layers() -> void:
	# Layered atmospheric fog bands — drawn after sky, before ground
	for i in 6:
		var t := float(i) / 6.0
		var fy := _origin.y - 40.0 + t * 120.0
		draw_rect(Rect2(0, fy, _size.x, 20.0),
				Color(0.06, 0.05, 0.10, 0.04 * (1.0 - t)))


# ── Ground platform ───────────────────────────────────────────────────────────

func _draw_ground_platform() -> void:
	for gy in GRID_ROWS:
		for gx in GRID_COLS:
			_draw_ground_tile(gx, gy)
	_draw_platform_edge()


func _draw_ground_tile(gx: int, gy: int) -> void:
	# Zone classification
	var is_front_sw := gy >= WALK_ROW - 1 and gy < GRID_ROWS - 1  # front sidewalk
	var is_road     := gy >= 6 and gy < WALK_ROW - 1              # 2-lane road
	var is_back_sw  := gy == 5                                     # back sidewalk
	var is_alley    := gy <= 1                                     # back alley zone

	if is_front_sw:
		# Concrete pavement with subtle variation and tile joints
		var t := 0.45 + 0.12 * sin(float(gx) * 0.8 + float(gy) * 1.5)
		var col := Color(0.09, 0.08, 0.12).lerp(Color(0.13, 0.12, 0.17), t)
		draw_tile(gx, gy, GZ_SIDEWALK, col)
		# Tile joints (every 2 tiles)
		if gx % 2 == 0:
			var edge := PackedVector2Array()
			edge.append(iso(gx + 1.0, float(gy),       GZ_SIDEWALK + 0.002))
			edge.append(iso(gx + 1.0, float(gy) + 1.0, GZ_SIDEWALK + 0.002))
			draw_polyline(edge, Color(0.06, 0.05, 0.09, 0.35), 0.8)
		# Curb drop face
		if gy == WALK_ROW - 1:
			var cf := PackedVector2Array()
			cf.append(iso(float(gx),       float(gy) + 1.0, GZ_SIDEWALK))
			cf.append(iso(float(gx) + 1.0, float(gy) + 1.0, GZ_SIDEWALK))
			cf.append(iso(float(gx) + 1.0, float(gy) + 1.0, GZ_STREET))
			cf.append(iso(float(gx),       float(gy) + 1.0, GZ_STREET))
			draw_colored_polygon(cf, Color(0.07, 0.06, 0.10, 1.0))

	elif is_road:
		# Wet dark asphalt with reflective sheen
		var wet := 0.35 + 0.18 * sin(float(gx) * 1.2) * cos(float(gy) * 0.85)
		var col := Color(0.048, 0.048, 0.068).lerp(Color(0.075, 0.068, 0.095), wet)
		draw_tile(gx, gy, GZ_STREET, col)
		# Puddle reflections
		if (gx * 5 + gy * 7) % 11 == 0:
			_draw_puddle(float(gx) + 0.5, float(gy) + 0.5)
		# Lane divider (dashed white between gy 6 and 7)
		if gy == 6 and gx % 3 == 0:
			var lpts := PackedVector2Array()
			lpts.append(iso(float(gx) + 0.2, float(gy) + 1.0, 0.001))
			lpts.append(iso(float(gx) + 0.8, float(gy) + 1.0, 0.001))
			lpts.append(iso(float(gx) + 0.8, float(gy) + 1.1, 0.001))
			lpts.append(iso(float(gx) + 0.2, float(gy) + 1.1, 0.001))
			draw_colored_polygon(lpts, Color(0.20, 0.18, 0.14, 0.45))

	elif is_back_sw:
		var t := 0.4 + 0.10 * sin(float(gx) * 0.9 + 0.5)
		draw_tile(gx, gy, GZ_BACK_SW, Color(0.08, 0.07, 0.11).lerp(Color(0.11, 0.10, 0.15), t))
		# Back-sidewalk drop face
		if gy == 5:
			var cf := PackedVector2Array()
			cf.append(iso(float(gx),       6.0, GZ_BACK_SW))
			cf.append(iso(float(gx) + 1.0, 6.0, GZ_BACK_SW))
			cf.append(iso(float(gx) + 1.0, 6.0, GZ_STREET))
			cf.append(iso(float(gx),       6.0, GZ_STREET))
			draw_colored_polygon(cf, Color(0.06, 0.05, 0.09, 1.0))

	elif is_alley:
		# Alley ground — damp, mossy, darker
		var t := 0.3 + 0.15 * sin(float(gx) * 1.3 + float(gy))
		draw_tile(gx, gy, GZ_STREET,
				Color(0.035, 0.040, 0.042).lerp(Color(0.050, 0.055, 0.058), t))
	else:
		# Mid zone (gy 2–4) — service road / loading area
		draw_tile(gx, gy, GZ_STREET, Color(0.042, 0.040, 0.058, 1.0))


func _draw_puddle(gx: float, gy: float) -> void:
	var sc := 0.30
	var pts := PackedVector2Array()
	pts.append(iso(gx - sc, gy,      GZ_STREET))
	pts.append(iso(gx,      gy - sc, GZ_STREET))
	pts.append(iso(gx + sc, gy,      GZ_STREET))
	pts.append(iso(gx,      gy + sc, GZ_STREET))
	var alpha := 0.14 + 0.07 * sin(_time * 1.3 + gx * 0.7 + gy * 0.9)
	draw_colored_polygon(pts, Color(0.18, 0.22, 0.38, alpha))
	# Neon colour tint from nearest location
	var nearest_col := _nearest_neon_color(gx)
	draw_colored_polygon(pts, Color(nearest_col.r, nearest_col.g, nearest_col.b,
			alpha * 0.35 * _neon_flicker))


func _nearest_neon_color(gx: float) -> Color:
	var best_dist := 999.0
	var best_col  := Color(0.3, 0.4, 0.6)
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx := _loc_grid_x(d)
		var dist := abs(gx - lx)
		if dist < best_dist:
			best_dist = dist
			var sc_str := _str(d.get("sign_color")) if d.get("sign_color") != null else "#6688aa"
			best_col = Color.html(sc_str)
	return best_col


func _draw_platform_edge() -> void:
	var edge_gy := float(GRID_ROWS)
	for gx in GRID_COLS:
		var pts := PackedVector2Array()
		pts.append(iso(float(gx),       edge_gy, GZ_STREET))
		pts.append(iso(float(gx),       edge_gy, -1.8))
		pts.append(iso(float(gx) + 1.0, edge_gy, -1.8))
		pts.append(iso(float(gx) + 1.0, edge_gy, GZ_STREET))
		draw_colored_polygon(pts, Color(0.030, 0.025, 0.044, 1.0))
		iso_line(float(gx), edge_gy, GZ_STREET, float(gx) + 1.0, edge_gy, GZ_STREET,
				Color(0.07, 0.06, 0.10, 0.5), 1.0)


# ── Alley ─────────────────────────────────────────────────────────────────────

func _draw_alley() -> void:
	# Dumpsters in the back alley
	_draw_dumpster(3.0,  0.5)
	_draw_dumpster(12.5, 0.3)
	_draw_dumpster(22.0, 0.5)
	_draw_dumpster(30.5, 0.3)
	# Stacked crates
	_draw_crate_stack(7.0, 1.2)
	_draw_crate_stack(18.5, 0.8)
	_draw_crate_stack(26.0, 1.2)
	# Puddle under dumpster
	for dx in [3.5, 13.0, 22.5, 31.0]:
		var pp := PackedVector2Array()
		for i in 6:
			var a := TAU * float(i) / 6.0
			pp.append(iso(dx + cos(a) * 0.28, 1.0 + sin(a) * 0.14, 0.001))
		draw_colored_polygon(pp, Color(0.04, 0.06, 0.04, 0.45))


func _draw_dumpster(gx: float, gy: float) -> void:
	var gz := GZ_STREET
	var body_top  := Color(0.10, 0.14, 0.10, 1.0)
	var body_front := Color(0.07, 0.10, 0.07, 1.0)
	var body_right := Color(0.05, 0.08, 0.05, 1.0)
	draw_iso_box_w(gx, gy, 0.9, 0.6, gz, gz + 0.65, body_top, body_front, body_right)
	# Lid
	draw_iso_box_w(gx - 0.05, gy - 0.05, 1.0, 0.70, gz + 0.65, gz + 0.72,
			Color(0.12, 0.16, 0.12, 1.0), Color(0.09, 0.12, 0.09, 1.0), Color(0.07, 0.10, 0.07, 1.0))
	# Rust streak
	var rp := iso(gx + 0.5, gy + 0.6, gz + 0.40)
	draw_rect(Rect2(rp.x - 1, rp.y - 8, 2, 12), Color(0.18, 0.08, 0.04, 0.35))
	# Overflow bag on side
	var bp := iso(gx + 0.9, gy + 0.55, gz + 0.1)
	draw_circle(bp, 6.0, Color(0.06, 0.06, 0.08, 0.9))
	draw_circle(iso(gx + 0.9, gy + 0.55, gz + 0.38), 3.5, Color(0.08, 0.08, 0.10, 0.8))


func _draw_crate_stack(gx: float, gy: float) -> void:
	var gz := GZ_STREET
	var c_top   := Color(0.14, 0.11, 0.07, 1.0)
	var c_front := Color(0.10, 0.08, 0.05, 1.0)
	var c_right := Color(0.08, 0.06, 0.04, 1.0)
	# Bottom crate
	draw_iso_box_w(gx, gy, 0.7, 0.7, gz, gz + 0.5, c_top, c_front, c_right)
	# Top crate (slightly offset)
	draw_iso_box_w(gx + 0.05, gy + 0.05, 0.6, 0.6, gz + 0.5, gz + 0.95,
			c_top.lightened(0.08), c_front.lightened(0.05), c_right.lightened(0.04))
	# Wood grain lines on front face
	for li in 3:
		iso_line(gx, gy + 0.7, gz + float(li) * 0.16 + 0.08,
				gx + 0.7, gy + 0.7, gz + float(li) * 0.16 + 0.08,
				c_front.lightened(0.15), 0.7)


# ── Buildings ─────────────────────────────────────────────────────────────────
# Three rows, each with different setback depth (gy) and height range.
# Row A (gy=1): towers, 5–9 units tall
# Row B (gy=3): mid-rise office/residential, 3–5 units
# Row C (gy=4): ground-floor commercial (shop fronts), 2–3 units

# Format: [gx, gy, w, h, top_hex, left_hex, right_hex, has_shop_front]
const BUILDINGS := [
	# ── Row A — towers ─────────────────────────────────────────────────────
	[0,  1, 3, 7, "12101a", "0d0b14", "0f0d17", false],
	[3,  1, 2, 5, "0f0e15", "0b0a11", "0d0c13", false],
	[5,  1, 4, 9, "160f20", "0f0b17", "12101c", false],  # purple glass tower
	[9,  1, 2, 5, "0e0d13", "0a0911", "0c0b12", false],
	[11, 1, 3, 7, "110f18", "0c0b14", "0e0d16", false],
	[14, 1, 2, 4, "0d0c12", "090910", "0b0a12", false],
	[16, 1, 4, 8, "130f1b", "0e0b15", "100d18", false],  # second glass tower
	[20, 1, 2, 5, "0f0e15", "0b0a11", "0d0c13", false],
	[22, 1, 3, 6, "111019", "0c0c15", "0e0e17", false],
	[25, 1, 2, 4, "0e0d13", "0a0a11", "0c0b13", false],
	[27, 1, 4, 7, "140e1c", "0f0a15", "110c18", false],
	[31, 1, 3, 5, "100f16", "0c0b12", "0e0d14", false],
	# ── Row B — mid-rise ───────────────────────────────────────────────────
	[1,  3, 2, 4, "0d0c12", "090910", "0b0a12", false],
	[4,  3, 3, 3, "0f0e14", "0b0a11", "0d0c13", true],
	[8,  3, 2, 4, "0e0d13", "0a0911", "0c0b12", false],
	[11, 3, 3, 3, "100f15", "0c0b12", "0e0d14", true],
	[15, 3, 2, 3, "0d0c12", "090910", "0b0a12", false],
	[18, 3, 3, 4, "0e0d14", "0a0a11", "0c0b13", true],
	[22, 3, 2, 3, "0f0e14", "0b0a11", "0d0c13", false],
	[25, 3, 3, 4, "0d0c12", "090910", "0b0a12", true],
	[29, 3, 2, 3, "100f15", "0c0b12", "0e0d14", false],
	[32, 3, 2, 4, "0e0d13", "0a0911", "0c0b12", false],
]


func _draw_buildings() -> void:
	var sorted := BUILDINGS.duplicate()
	sorted.sort_custom(func(a, b): return (a[0] + a[1]) < (b[0] + b[1]))
	for b in sorted:
		var gx: int    = b[0]
		var gy: int    = b[1]
		var w: int     = b[2]
		var h: int     = b[3]
		var top_c      := Color.html("#" + b[4])
		var left_c     := Color.html("#" + b[5])
		var right_c    := Color.html("#" + b[6])
		var shop: bool = b[7]
		_draw_building(gx, gy, w, h, top_c, left_c, right_c, shop)


func _draw_building(gx: int, gy: int, w: int, h: int,
		top_c: Color, left_c: Color, right_c: Color, has_shop: bool) -> void:
	var gz_base := GZ_SIDEWALK
	var gz_top  := gz_base + float(h)

	# Right face
	var rf := PackedVector2Array()
	rf.append(iso(gx + w, gy,     gz_base))
	rf.append(iso(gx + w, gy,     gz_top))
	rf.append(iso(gx + w, gy + 2, gz_top))
	rf.append(iso(gx + w, gy + 2, gz_base))
	draw_colored_polygon(rf, right_c)

	# Front face (left face)
	var lf := PackedVector2Array()
	lf.append(iso(gx,     gy + 2, gz_base))
	lf.append(iso(gx,     gy + 2, gz_top))
	lf.append(iso(gx + w, gy + 2, gz_top))
	lf.append(iso(gx + w, gy + 2, gz_base))
	draw_colored_polygon(lf, left_c)

	# Top face
	var tp := PackedVector2Array()
	tp.append(iso(gx,     gy,     gz_top))
	tp.append(iso(gx + w, gy,     gz_top))
	tp.append(iso(gx + w, gy + 2, gz_top))
	tp.append(iso(gx,     gy + 2, gz_top))
	draw_colored_polygon(tp, top_c)

	# Horizontal ledge lines on front face (every 2 floors)
	for fl in range(2, h, 2):
		var lz := gz_base + float(fl)
		iso_line(float(gx), float(gy) + 2.0, lz, float(gx + w), float(gy) + 2.0, lz,
				left_c.lightened(0.12), 0.8)

	# Windows
	_draw_building_windows(gx, gy, w, h, gz_base, left_c)
	# Right-face windows (visible on rightmost buildings)
	_draw_right_face_windows(gx, gy, w, h, gz_base, right_c)

	# Fire escapes on taller buildings
	if h >= 5:
		_draw_fire_escape(gx + w, gy, gz_base, gz_top, right_c)

	# Rooftop details
	_draw_rooftop(gx, gy, w, gz_top, top_c)

	# Ground-floor shop front (awning + lit display window)
	if has_shop:
		_draw_shop_front(gx, gy + 2, w, gz_base)


func _draw_building_windows(gx: int, gy: int, w: int, h: int,
		gz_base: float, wall_col: Color) -> void:
	var WPAD_X := 0.15
	var WPAD_Z := 0.18
	var WIN_W  := 0.30
	var WIN_H  := 0.42
	for wx_i in w:
		var wx := float(gx + wx_i)
		for wz_i in h:
			var wz := gz_base + float(wz_i) + WPAD_Z
			var seed := int(wx * 7 + float(wz_i) * 3 + float(gy) * 11) % 6
			var is_lit := seed > 0

			var tl := iso(wx + WPAD_X,        float(gy) + 2.0, wz + WIN_H)
			var tr := iso(wx + WPAD_X + WIN_W, float(gy) + 2.0, wz + WIN_H)
			var br := iso(wx + WPAD_X + WIN_W, float(gy) + 2.0, wz)
			var bl := iso(wx + WPAD_X,         float(gy) + 2.0, wz)
			var pts := PackedVector2Array()
			pts.append(tl); pts.append(tr); pts.append(br); pts.append(bl)

			if is_lit:
				var warm := (int(wx * 3 + float(wz_i) * 7) % 3) != 0
				var wc: Color
				if warm:
					wc = Color(0.58, 0.46, 0.24, 0.88)
				else:
					wc = Color(0.28, 0.40, 0.68, 0.82)
				if (int(wx + float(wz_i) * 2 + float(gy)) % 5) == 0:
					wc.a *= _neon_flicker
				draw_colored_polygon(pts, wc)
				# Soft bloom on wall around window
				for g in 2:
					var ga := 0.04 - float(g) * 0.015
					draw_colored_polygon(pts, Color(wc.r, wc.g, wc.b, ga))
			else:
				draw_colored_polygon(pts, Color(0.03, 0.03, 0.05, 0.92))
			draw_polyline(pts, wall_col.lightened(0.18), 0.7, false)


func _draw_right_face_windows(gx: int, gy: int, w: int, h: int,
		gz_base: float, wall_col: Color) -> void:
	var WPAD_Z := 0.22; var WIN_H := 0.38
	for wz_i in h:
		var wz := gz_base + float(wz_i) + WPAD_Z
		var seed := int(float(gx) * 11 + float(wz_i) * 5 + float(gy) * 7) % 6
		if seed == 0: continue  # dark window
		var tl := iso(float(gx + w), float(gy) + 0.2, wz + WIN_H)
		var tr := iso(float(gx + w), float(gy) + 0.8, wz + WIN_H)
		var br := iso(float(gx + w), float(gy) + 0.8, wz)
		var bl := iso(float(gx + w), float(gy) + 0.2, wz)
		var pts := PackedVector2Array()
		pts.append(tl); pts.append(tr); pts.append(br); pts.append(bl)
		var warm := (int(float(gx) * 4 + float(wz_i) * 9) % 3) != 0
		var wc := Color(0.50, 0.40, 0.20, 0.70) if warm else Color(0.24, 0.36, 0.60, 0.65)
		draw_colored_polygon(pts, wc)
		draw_polyline(pts, wall_col.lightened(0.14), 0.6, false)


func _draw_shop_front(gx: int, gy: int, w: int, gz_base: float) -> void:
	# Awning over ground floor
	var aw_col := Color(0.18, 0.12, 0.08, 1.0)
	var awning := PackedVector2Array()
	awning.append(iso(float(gx),       float(gy), gz_base + 1.6))
	awning.append(iso(float(gx + w),   float(gy), gz_base + 1.6))
	awning.append(iso(float(gx + w),   float(gy), gz_base + 1.2))
	awning.append(iso(float(gx),       float(gy), gz_base + 1.2))
	draw_colored_polygon(awning, aw_col)
	# Awning stripes
	for si in w:
		iso_line(float(gx + si) + 0.3, float(gy), gz_base + 1.6,
				float(gx + si) + 0.3, float(gy), gz_base + 1.2,
				Color(0.25, 0.16, 0.10, 0.6), 1.5)
	# Awning fringe (screen-space dots along bottom edge)
	var fringe_y := iso(float(gx), float(gy), gz_base + 1.2)
	var fringe_end := iso(float(gx + w), float(gy), gz_base + 1.2)
	var steps := int((fringe_end.x - fringe_y.x) / 8.0)
	for fi in steps:
		var fx := fringe_y.x + float(fi) * 8.0
		var fy_pos := lerp(fringe_y.y, fringe_end.y, float(fi) / float(maxf(steps, 1)))
		draw_circle(Vector2(fx, fy_pos + 3.0), 2.0, aw_col.lightened(0.15))

	# Lit display window
	var win_gz_bot := gz_base + 0.3
	var win_gz_top := gz_base + 1.1
	for wi in w:
		var wx := float(gx + wi)
		var tl := iso(wx + 0.1, float(gy), win_gz_top)
		var tr := iso(wx + 0.9, float(gy), win_gz_top)
		var br := iso(wx + 0.9, float(gy), win_gz_bot)
		var bl := iso(wx + 0.1, float(gy), win_gz_bot)
		var pts := PackedVector2Array()
		pts.append(tl); pts.append(tr); pts.append(br); pts.append(bl)
		var shop_hue := fmod(float(gx) * 0.17, 1.0)
		var shop_col := Color.from_hsv(shop_hue, 0.35, 0.45, 0.70)
		draw_colored_polygon(pts, shop_col)
		for g in 3:
			draw_colored_polygon(pts, Color(shop_col.r, shop_col.g, shop_col.b,
					0.07 - float(g) * 0.02))
		draw_polyline(pts, Color(0.20, 0.18, 0.24, 0.5), 0.8, false)


func _draw_fire_escape(gx: int, gy: int, gz_base: float, gz_top: float,
		_face_col: Color) -> void:
	var rail_col := Color(0.20, 0.18, 0.24, 0.80)
	var plat_col := Color(0.14, 0.13, 0.18, 0.90)
	var num_land := clampi(int((gz_top - gz_base) / 1.4), 2, 5)
	var ex := float(gx)
	var ey := float(gy) + 0.15

	for li in num_land:
		var lz := gz_base + float(li + 1) * ((gz_top - gz_base) / float(num_land + 1))
		# Platform
		var pf := PackedVector2Array()
		pf.append(iso(ex,        ey,        lz))
		pf.append(iso(ex,        ey + 0.40, lz))
		pf.append(iso(ex + 0.40, ey + 0.40, lz))
		pf.append(iso(ex + 0.40, ey,        lz))
		draw_colored_polygon(pf, plat_col)
		draw_polyline(pf, rail_col, 1.0, true)
		# Railing posts
		for pi in 3:
			iso_line(ex + float(pi) * 0.18, ey, lz,
					ex + float(pi) * 0.18, ey, lz + 0.28, rail_col, 1.0)
		iso_line(ex, ey, lz + 0.28, ex + 0.40, ey, lz + 0.28, rail_col, 0.8)
		# Stair run
		if li > 0:
			var lz_prev := gz_base + float(li) * ((gz_top - gz_base) / float(num_land + 1))
			iso_line(ex + 0.05, ey + 0.35, lz,  ex + 0.30, ey, lz_prev, rail_col, 1.5)
			iso_line(ex + 0.18, ey + 0.35, lz,  ex + 0.43, ey, lz_prev, rail_col, 0.9)
		elif li == 0:
			iso_line(ex + 0.12, ey + 0.30, gz_base, ex + 0.12, ey, lz, rail_col, 1.5)


func _draw_rooftop(gx: int, gy: int, w: int, gz_top: float, top_c: Color) -> void:
	var fgy := float(gy)
	# HVAC box
	var rx := float(gx) + float(w) * 0.5 - 0.4
	draw_iso_box_w(rx, fgy, 0.8, 0.6, gz_top, gz_top + 0.45,
			top_c.lightened(0.1), top_c.darkened(0.12), top_c)
	# Main antenna
	iso_line(rx + 0.3, fgy + 0.3, gz_top + 0.45,
			rx + 0.3, fgy + 0.3, gz_top + 1.4, Color(0.20, 0.20, 0.32, 0.75), 1.5)
	# Antenna cross-bar
	iso_line(rx + 0.3 - 0.2, fgy + 0.3, gz_top + 1.1,
			rx + 0.3 + 0.2, fgy + 0.3, gz_top + 1.1, Color(0.20, 0.20, 0.32, 0.60), 1.0)
	# Warning light on tallest antennas
	if gz_top > 8.0:
		var wlp := iso(rx + 0.3, fgy + 0.3, gz_top + 1.4)
		var blink := 0.5 + 0.5 * sin(_time * 1.4 + float(gx) * 0.8)
		draw_circle(wlp, 3.5, Color(0.9, 0.2, 0.15, 0.55 + 0.45 * blink))

	# AC unit on wider buildings
	if w >= 3:
		var ax := float(gx) + 0.5
		draw_iso_box_w(ax, fgy + 0.15, 0.85, 0.55, gz_top, gz_top + 0.38,
				top_c.darkened(0.06), top_c.darkened(0.22), top_c.darkened(0.14))
		var afp := iso(ax + 0.42, fgy + 0.15, gz_top + 0.39)
		for fi in 5:
			draw_line(afp + Vector2(-10 + fi * 4, -7), afp + Vector2(-10 + fi * 4, 7),
					Color(0.06, 0.06, 0.10, 0.55), 0.8)
		iso_line(ax + 0.7, fgy + 0.45, gz_top + 0.38,
				ax + 0.7, fgy + 0.45, gz_top + 0.72, Color(0.14, 0.14, 0.20, 0.65), 1.5)

	# Water tower on very tall buildings
	if gz_top > 9.0 and w >= 4:
		var tx := float(gx) + float(w) * 0.75
		_draw_water_tower(tx, fgy + 0.3, gz_top)


func _draw_water_tower(gx: float, gy: float, gz: float) -> void:
	var wood := Color(0.16, 0.10, 0.06, 1.0)
	var wood_d := wood.darkened(0.25)
	# Tank body (cylinder approximated as iso box)
	draw_iso_box_w(gx - 0.3, gy, 0.6, 0.6, gz, gz + 0.9,
			wood.lightened(0.05), wood, wood_d)
	# Conical top (triangle on top face)
	var cone := PackedVector2Array()
	cone.append(iso(gx,       gy,       gz + 0.9))
	cone.append(iso(gx + 0.6, gy,       gz + 0.9))
	cone.append(iso(gx + 0.3, gy + 0.3, gz + 1.3))
	draw_colored_polygon(cone, wood.lightened(0.10))
	# Support legs (4 poles)
	for li in [[0.1, 0.1], [0.5, 0.1], [0.1, 0.5], [0.5, 0.5]]:
		iso_line(gx - 0.3 + li[0], gy + li[1], gz,
				gx - 0.3 + li[0] * 1.4, gy + li[1] * 1.4, gz - 0.6,
				Color(0.10, 0.08, 0.05, 0.8), 1.5)


# ── Overhead cables ───────────────────────────────────────────────────────────

func _draw_overhead_cables() -> void:
	# Cables strung between lamp posts and buildings across the street
	# Each cable: slight sag curve (3-point polyline)
	var cable_col := Color(0.08, 0.08, 0.12, 0.55)
	var lamp_gxs := [2.5, 6.5, 10.5, 14.5, 18.5, 22.5, 26.5, 30.5]
	for i in lamp_gxs.size() - 1:
		var ax: float = lamp_gxs[i]
		var bx: float = lamp_gxs[i + 1]
		var gz_top := GZ_SIDEWALK + 3.5
		var sag := 0.3  # sag in gz units
		var a_pt := iso(ax, float(WALK_ROW) - 0.5, gz_top)
		var b_pt := iso(bx, float(WALK_ROW) - 0.5, gz_top)
		var mid  := iso((ax + bx) * 0.5, float(WALK_ROW) - 0.5, gz_top - sag)
		# Draw as two-segment sag
		draw_line(a_pt, mid, cable_col, 0.9)
		draw_line(mid, b_pt, cable_col, 0.9)
		# Secondary power cable slightly offset
		var a2 := iso(ax + 0.1, float(WALK_ROW) - 0.4, gz_top - 0.15)
		var m2 := iso((ax + bx) * 0.5 + 0.1, float(WALK_ROW) - 0.4, gz_top - 0.15 - sag * 0.8)
		var b2 := iso(bx + 0.1, float(WALK_ROW) - 0.4, gz_top - 0.15)
		draw_line(a2, m2, cable_col.lightened(0.05), 0.7)
		draw_line(m2, b2, cable_col.lightened(0.05), 0.7)


# ── Street details ────────────────────────────────────────────────────────────

func _draw_street_details() -> void:
	# Lamp posts
	var lamp_gxs := [2.5, 6.5, 10.5, 14.5, 18.5, 22.5, 26.5, 30.5]
	for lx in lamp_gxs:
		_draw_lamp_post(lx, float(WALK_ROW) - 1.0)

	# Manhole covers + steam vents
	for gx in [5, 11, 17, 23, 29]:
		_draw_manhole(float(gx) + 0.5, 6.5)
		_draw_steam_vent(float(gx) + 0.5, 6.5)

	# Parked cars — more variety
	_draw_parked_car(6.5,  6.2, Color(0.07, 0.09, 0.13, 1.0))
	_draw_parked_car(13.0, 6.3, Color(0.10, 0.07, 0.08, 1.0))
	_draw_parked_car(20.5, 6.2, Color(0.06, 0.08, 0.10, 1.0))
	_draw_parked_car(27.0, 6.3, Color(0.09, 0.08, 0.06, 1.0))

	# Trash bags on front sidewalk
	for tg in [[1.5, 8.5], [8.0, 8.6], [15.5, 8.5], [24.0, 8.6], [32.0, 8.5]]:
		_draw_trash_bags(tg[0], tg[1])

	# Newspaper stands
	for nx in [4.0, 12.0, 20.5, 28.5]:
		_draw_news_stand(nx, float(WALK_ROW) - 0.8)

	# Bus stop shelter
	_draw_bus_stop(9.5, float(WALK_ROW) - 0.5)

	# Phone box
	_draw_phone_box(17.5, float(WALK_ROW) - 0.5)

	# Bollards along curb edge
	for bx in [2.0, 4.0, 7.0, 9.0, 13.0, 16.0, 19.0, 23.0, 25.0, 29.0, 31.5]:
		_draw_bollard(bx, float(WALK_ROW) - 0.05)

	# Grated drain on road edge
	for dx in [3.5, 9.5, 16.5, 23.5, 30.5]:
		_draw_drain_grate(dx, 5.9)


func _draw_lamp_post(gx: float, gy: float) -> void:
	var base_gz := GZ_SIDEWALK
	# Post
	iso_line(gx, gy + 0.5, base_gz, gx, gy + 0.5, base_gz + 4.0,
			Color(0.16, 0.14, 0.22, 1.0), 2.5)
	# Curved arm
	iso_line(gx, gy + 0.5, base_gz + 4.0, gx + 0.5, gy + 0.5, base_gz + 4.0,
			Color(0.16, 0.14, 0.22, 1.0), 1.5)
	iso_line(gx + 0.5, gy + 0.5, base_gz + 4.0, gx + 0.5, gy + 0.5, base_gz + 3.8,
			Color(0.16, 0.14, 0.22, 1.0), 1.5)
	# Lamp housing
	var head := iso(gx + 0.5, gy + 0.5, base_gz + 3.8)
	draw_iso_box_w(gx + 0.3, gy + 0.3, 0.4, 0.4, base_gz + 3.6, base_gz + 3.8,
			Color(0.14, 0.13, 0.18, 1.0), Color(0.10, 0.09, 0.14, 1.0), Color(0.08, 0.08, 0.12, 1.0))
	# Glow halos
	for g in 8:
		var ga := 0.10 - float(g) * 0.011
		var gr := 10.0 + float(g) * 14.0
		draw_circle(head, gr, Color(0.62, 0.58, 0.85, ga))
	draw_circle(head, 6.0, Color(0.88, 0.84, 0.98, 0.92))
	# Light cone on street
	var p1 := iso(gx - 0.6, gy + 2.0, GZ_STREET)
	var p2 := iso(gx + 1.4, gy + 2.0, GZ_STREET)
	var cone_pts := PackedVector2Array()
	cone_pts.append(head); cone_pts.append(p1); cone_pts.append(p2)
	draw_colored_polygon(cone_pts, Color(0.42, 0.40, 0.62, 0.035))


func _draw_manhole(gx: float, gy: float) -> void:
	var pts := PackedVector2Array()
	var r := 0.24
	for i in 10:
		var a := TAU * float(i) / 10.0
		pts.append(iso(gx + cos(a) * r, gy + sin(a) * r * 0.5, 0.002))
	draw_colored_polygon(pts, Color(0.065, 0.065, 0.095, 1.0))
	# Radial grille lines
	for i in 4:
		var a := TAU * float(i) / 4.0
		iso_line(gx, gy, 0.002, gx + cos(a) * r, gy + sin(a) * r * 0.5, 0.002,
				Color(0.09, 0.09, 0.13, 1.0), 0.8)


func _draw_steam_vent(gx: float, gy: float) -> void:
	for i in 6:
		var t := fmod(_time * 0.55 + float(i) * 0.38, 1.0)
		var sz := 1.5 + t * 5.0
		var alpha := (1.0 - t) * 0.09
		var offset_x := sin(_time * 1.1 + float(i)) * 0.05
		var offset_y := cos(_time * 0.8 + float(i) * 1.2) * 0.03
		var sp := iso(gx + offset_x, gy + offset_y, 0.04 + t * 0.70)
		draw_circle(sp, sz, Color(0.72, 0.74, 0.82, alpha))


func _draw_parked_car(gx: float, gy: float, body_col: Color) -> void:
	var cw := 2.0; var cd := 1.0; var ch := 0.75

	# Car body — right face
	var rf := PackedVector2Array()
	rf.append(iso(gx + cw, gy,       GZ_STREET))
	rf.append(iso(gx + cw, gy,       ch))
	rf.append(iso(gx + cw, gy + cd,  ch))
	rf.append(iso(gx + cw, gy + cd,  GZ_STREET))
	draw_colored_polygon(rf, body_col.darkened(0.18))

	# Front face
	var lf := PackedVector2Array()
	lf.append(iso(gx,      gy + cd, GZ_STREET))
	lf.append(iso(gx,      gy + cd, ch))
	lf.append(iso(gx + cw, gy + cd, ch))
	lf.append(iso(gx + cw, gy + cd, GZ_STREET))
	draw_colored_polygon(lf, body_col)

	# Top
	var tp := PackedVector2Array()
	tp.append(iso(gx,      gy,      ch))
	tp.append(iso(gx + cw, gy,      ch))
	tp.append(iso(gx + cw, gy + cd, ch))
	tp.append(iso(gx,      gy + cd, ch))
	draw_colored_polygon(tp, body_col.lightened(0.06))

	# Roof (raised cabin)
	var rc_inset := 0.25
	var rr := PackedVector2Array()
	rr.append(iso(gx + rc_inset,      gy + rc_inset * 0.5,  ch))
	rr.append(iso(gx + cw - rc_inset, gy + rc_inset * 0.5,  ch))
	rr.append(iso(gx + cw - rc_inset, gy + cd - rc_inset * 0.5, ch))
	rr.append(iso(gx + rc_inset,      gy + cd - rc_inset * 0.5, ch))
	draw_colored_polygon(rr, body_col.darkened(0.10))
	# Roof top
	var rt := PackedVector2Array()
	rt.append(iso(gx + rc_inset,      gy + rc_inset * 0.5,  ch + 0.28))
	rt.append(iso(gx + cw - rc_inset, gy + rc_inset * 0.5,  ch + 0.28))
	rt.append(iso(gx + cw - rc_inset, gy + cd - rc_inset * 0.5, ch + 0.28))
	rt.append(iso(gx + rc_inset,      gy + cd - rc_inset * 0.5, ch + 0.28))
	draw_colored_polygon(rt, body_col.lightened(0.04))

	# Windshield
	var wf := PackedVector2Array()
	wf.append(iso(gx + 0.3, gy + cd, ch + 0.04))
	wf.append(iso(gx + 0.3, gy + cd, ch + 0.26))
	wf.append(iso(gx + 1.7, gy + cd, ch + 0.26))
	wf.append(iso(gx + 1.7, gy + cd, ch + 0.04))
	draw_colored_polygon(wf, Color(0.14, 0.20, 0.32, 0.55))

	# Taillights
	for side in [0.12, cw - 0.28]:
		var tl_pts := PackedVector2Array()
		tl_pts.append(iso(gx + side,        gy + cd, 0.14))
		tl_pts.append(iso(gx + side,        gy + cd, 0.38))
		tl_pts.append(iso(gx + side + 0.16, gy + cd, 0.38))
		tl_pts.append(iso(gx + side + 0.16, gy + cd, 0.14))
		draw_colored_polygon(tl_pts, Color(0.92, 0.10, 0.06, 0.82))
		# Glow
		draw_colored_polygon(tl_pts, Color(0.92, 0.10, 0.06, 0.15))

	# Headlights (front)
	for side in [0.12, cw - 0.28]:
		var hl := iso(gx + side + 0.08, gy + GZ_STREET, 0.22)
		draw_circle(hl, 5.0, Color(0.75, 0.75, 0.60, 0.40))


func _draw_trash_bags(gx: float, gy: float) -> void:
	var gz_sw := GZ_SIDEWALK
	var bag_c := Color(0.055, 0.055, 0.075, 1.0)
	# Three bags of varying size
	var bags := [
		[gx,        gy,        gz_sw, 0.38, 0.30],
		[gx + 0.30, gy + 0.12, gz_sw, 0.32, 0.25],
		[gx + 0.55, gy + 0.05, gz_sw, 0.28, 0.28],
	]
	for bg in bags:
		var bx: float = bg[0]; var by: float = bg[1]; var bz: float = bg[2]
		var bw: float = bg[3]; var bh: float = bg[4]
		var b := PackedVector2Array()
		b.append(iso(bx,      by,       bz))
		b.append(iso(bx + bw, by,       bz))
		b.append(iso(bx + bw, by,       bz + bh))
		b.append(iso(bx,      by,       bz + bh))
		draw_colored_polygon(b, bag_c.lightened(randf_range(0.0, 0.06)))
	# Tie-off knots
	draw_circle(iso(gx + 0.18, gy, gz_sw + 0.38), 2.5, bag_c.lightened(0.18))
	draw_circle(iso(gx + 0.45, gy + 0.12, gz_sw + 0.26), 2.0, bag_c.lightened(0.14))


func _draw_news_stand(gx: float, gy: float) -> void:
	var gz_sw := GZ_SIDEWALK
	var metal   := Color(0.12, 0.12, 0.17, 1.0)
	var metal_d := metal.darkened(0.25)
	draw_iso_box_w(gx, gy, 0.65, 0.55, gz_sw, gz_sw + 1.0,
			metal.lightened(0.05), metal, metal_d)
	var fp := iso(gx + 0.32, gy + 0.55, gz_sw + 0.55)
	draw_rect(Rect2(fp.x - 11, fp.y - 9, 22, 18), Color(0.32, 0.30, 0.20, 0.85))
	for hi in 4:
		draw_rect(Rect2(fp.x - 9, fp.y - 6 + hi * 4, 18, 2), Color(0.09, 0.09, 0.13, 0.55))
	draw_rect(Rect2(fp.x - 2, fp.y + 9, 4, 2), metal_d)
	for li in [[0.06, 0.06], [0.52, 0.06], [0.06, 0.44], [0.52, 0.44]]:
		iso_line(gx + li[0], gy + li[1], gz_sw,
				gx + li[0], gy + li[1], gz_sw - 0.18, metal_d, 1.0)


func _draw_bus_stop(gx: float, gy: float) -> void:
	var gz := GZ_SIDEWALK
	var glass_c := Color(0.15, 0.22, 0.32, 0.35)
	var frame_c := Color(0.18, 0.17, 0.24, 1.0)
	# Back panel (glass)
	var back := PackedVector2Array()
	back.append(iso(gx,        gy, gz + 0.1))
	back.append(iso(gx,        gy, gz + 2.4))
	back.append(iso(gx + 2.2,  gy, gz + 2.4))
	back.append(iso(gx + 2.2,  gy, gz + 0.1))
	draw_colored_polygon(back, glass_c)
	draw_polyline(back, frame_c, 1.5, false)
	# Side panel
	var side := PackedVector2Array()
	side.append(iso(gx + 2.2, gy,       gz + 0.1))
	side.append(iso(gx + 2.2, gy,       gz + 2.4))
	side.append(iso(gx + 2.2, gy + 0.8, gz + 2.4))
	side.append(iso(gx + 2.2, gy + 0.8, gz + 0.1))
	draw_colored_polygon(side, glass_c.lightened(0.05))
	draw_polyline(side, frame_c, 1.2, false)
	# Roof
	var roof := PackedVector2Array()
	roof.append(iso(gx - 0.1,  gy - 0.1, gz + 2.4))
	roof.append(iso(gx + 2.3,  gy - 0.1, gz + 2.4))
	roof.append(iso(gx + 2.3,  gy + 0.9, gz + 2.4))
	roof.append(iso(gx - 0.1,  gy + 0.9, gz + 2.4))
	draw_colored_polygon(roof, frame_c)
	# Ad poster inside
	var pp := iso(gx + 0.8, gy, gz + 1.4)
	draw_rect(Rect2(pp.x - 16, pp.y - 20, 32, 40), Color(0.08, 0.06, 0.12, 0.8))
	draw_rect(Rect2(pp.x - 14, pp.y - 2, 28, 4), Color(0.55, 0.20, 0.80, 0.35))
	draw_string(ThemeDB.fallback_font, Vector2(pp.x - 12, pp.y + 3),
			"CLOSEDAI", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.3, 0.9, 0.6))
	# Bench
	draw_iso_box_w(gx + 0.2, gy + 0.05, 1.8, 0.5, gz, gz + 0.42,
			Color(0.12, 0.11, 0.16, 1.0), Color(0.09, 0.08, 0.12, 1.0), Color(0.07, 0.07, 0.10, 1.0))


func _draw_phone_box(gx: float, gy: float) -> void:
	var gz := GZ_SIDEWALK
	var body_c  := Color(0.08, 0.14, 0.10, 1.0)
	var body_d  := body_c.darkened(0.3)
	var glass_c := Color(0.10, 0.22, 0.14, 0.45)
	draw_iso_box_w(gx, gy, 0.7, 0.7, gz, gz + 2.6,
			body_c.lightened(0.05), body_c, body_d)
	# Glass door face
	var gf := PackedVector2Array()
	gf.append(iso(gx,       gy + 0.7, gz + 0.2))
	gf.append(iso(gx,       gy + 0.7, gz + 2.3))
	gf.append(iso(gx + 0.7, gy + 0.7, gz + 2.3))
	gf.append(iso(gx + 0.7, gy + 0.7, gz + 0.2))
	draw_colored_polygon(gf, glass_c)
	draw_polyline(gf, body_c.lightened(0.2), 1.2, false)
	# Interior glow (phone in use)
	var glow_p := iso(gx + 0.35, gy + 0.7, gz + 1.2)
	draw_circle(glow_p, 12.0, Color(0.10, 0.35, 0.15, 0.08 * _neon_flicker))
	draw_circle(glow_p, 5.0,  Color(0.15, 0.55, 0.22, 0.12 * _neon_flicker))


func _draw_bollard(gx: float, gy: float) -> void:
	var gz := GZ_SIDEWALK
	iso_line(gx, gy, gz, gx, gy, gz + 0.55, Color(0.18, 0.16, 0.24, 0.8), 3.0)
	# Top cap
	var tp := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0
		tp.append(iso(gx + cos(a) * 0.08, gy + sin(a) * 0.04, gz + 0.55))
	draw_colored_polygon(tp, Color(0.22, 0.20, 0.30, 0.9))
	# Reflective band
	iso_line(gx - 0.06, gy, gz + 0.32, gx + 0.06, gy, gz + 0.32,
			Color(0.65, 0.60, 0.80, 0.6), 1.5)


func _draw_drain_grate(gx: float, gy: float) -> void:
	# Rectangular grate on road edge
	var pts := PackedVector2Array()
	pts.append(iso(gx - 0.15, gy,        0.001))
	pts.append(iso(gx + 0.15, gy,        0.001))
	pts.append(iso(gx + 0.15, gy + 0.22, 0.001))
	pts.append(iso(gx - 0.15, gy + 0.22, 0.001))
	draw_colored_polygon(pts, Color(0.055, 0.055, 0.08, 1.0))
	for li in 3:
		iso_line(gx - 0.13, gy + float(li) * 0.07 + 0.03,  0.001,
				gx + 0.13, gy + float(li) * 0.07 + 0.03, 0.001,
				Color(0.08, 0.08, 0.11, 1.0), 0.7)


# ── Location facades ──────────────────────────────────────────────────────────

func _draw_location_facades() -> void:
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx: float = _loc_grid_x(d)
		var sign_col := Color.html(_str(d.get("sign_color")) if d.get("sign_color") != null else "#ffffff")
		var glow_col := Color.html(_str(d.get("sign_glow"))  if d.get("sign_glow")  != null else "#888888")
		var sign_text: String = _str(d.get("sign_text"))
		var uc: String = _str(d.get("unlock_clue"))
		var locked: bool = uc != "" and not (uc in GameState.discovered_clues)

		_draw_doorway(lx, 5.0, locked)
		_draw_neon_sign(lx, 5.0, sign_text, sign_col, glow_col, locked)

		var loc_id := _str(d.get("id"))
		if loc_id == _near_location_id:
			_draw_proximity_indicator(lx, float(WALK_ROW))


func _draw_doorway(gx: float, gy: float, locked: bool) -> void:
	var dw := 0.7; var dh := 2.0; var gz := GZ_BACK_SW
	var door_col := Color(0.035, 0.035, 0.055, 1.0) if locked else Color(0.06, 0.055, 0.085, 1.0)
	var frame_col := Color(0.09, 0.08, 0.13, 1.0)

	# Door opening
	var lf := PackedVector2Array()
	lf.append(iso(gx - dw * 0.5, gy, gz))
	lf.append(iso(gx - dw * 0.5, gy, gz + dh))
	lf.append(iso(gx + dw * 0.5, gy, gz + dh))
	lf.append(iso(gx + dw * 0.5, gy, gz))
	draw_colored_polygon(lf, door_col)
	draw_polyline(lf, frame_col.lightened(0.20), 1.2, false)

	# Doorknob
	draw_circle(iso(gx + dw * 0.18, gy, gz + dh * 0.44), 2.2, Color(0.52, 0.42, 0.22, 0.9))

	# Door number plate
	var np := iso(gx, gy, gz + dh * 0.82)
	draw_rect(Rect2(np.x - 8, np.y - 5, 16, 10), Color(0.06, 0.05, 0.09, 0.9))
	draw_rect(Rect2(np.x - 8, np.y - 5, 16, 10), Color(0.25, 0.22, 0.32, 0.3))

	# Steps (2 steps down to back sidewalk level)
	for s in 2:
		var sz := gz - float(s) * 0.50
		var sf := PackedVector2Array()
		var off := float(s) * 0.12
		sf.append(iso(gx - dw * 0.5 - off, gy + float(s) * 0.18, sz))
		sf.append(iso(gx + dw * 0.5 + off, gy + float(s) * 0.18, sz))
		sf.append(iso(gx + dw * 0.5 + off, gy + float(s + 1) * 0.18, sz - 0.50))
		sf.append(iso(gx - dw * 0.5 - off, gy + float(s + 1) * 0.18, sz - 0.50))
		draw_colored_polygon(sf, Color(0.07, 0.06, 0.10, 1.0))
		# Step edge highlight
		iso_line(gx - dw * 0.5 - off, gy + float(s) * 0.18, sz,
				gx + dw * 0.5 + off, gy + float(s) * 0.18, sz,
				Color(0.12, 0.11, 0.16, 0.5), 0.8)


func _draw_neon_sign(gx: float, gy: float, text: String,
		sign_col: Color, glow_col: Color, locked: bool) -> void:
	var gz_sign := GZ_BACK_SW + 2.6
	var sign_w  := 1.5; var sign_h := 0.6

	var sc := sign_col if not locked else Color(0.14, 0.13, 0.19, 1.0)
	var gc := glow_col if not locked else Color(0.05, 0.05, 0.07, 1.0)

	if not locked:
		# Multi-layer soft glow bloom
		for g in 7:
			var ga  := 0.11 - float(g) * 0.013
			var exp := float(g) * 0.14
			var gp  := PackedVector2Array()
			gp.append(iso(gx - sign_w * 0.5 - exp, gy, gz_sign - exp * 0.4))
			gp.append(iso(gx + sign_w * 0.5 + exp, gy, gz_sign - exp * 0.4))
			gp.append(iso(gx + sign_w * 0.5 + exp, gy, gz_sign + sign_h + exp * 0.4))
			gp.append(iso(gx - sign_w * 0.5 - exp, gy, gz_sign + sign_h + exp * 0.4))
			draw_colored_polygon(gp, Color(gc.r, gc.g, gc.b, ga * _neon_flicker))

	# Sign backing plate
	var sp := PackedVector2Array()
	sp.append(iso(gx - sign_w * 0.5, gy, gz_sign))
	sp.append(iso(gx + sign_w * 0.5, gy, gz_sign))
	sp.append(iso(gx + sign_w * 0.5, gy, gz_sign + sign_h))
	sp.append(iso(gx - sign_w * 0.5, gy, gz_sign + sign_h))
	draw_colored_polygon(sp, Color(0.025, 0.025, 0.040, 0.95))

	# Neon tube outline (double line for tube thickness)
	draw_polyline(sp, Color(sc.r, sc.g, sc.b, 0.55 * _neon_flicker), 2.5, false)
	draw_polyline(sp, Color(sc.r * 0.6, sc.g * 0.6, sc.b * 0.6, 0.35), 4.5, false)

	# Sign text
	var text_pos := iso(gx, gy, gz_sign + sign_h * 0.58)
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, text_pos - Vector2(tw * 0.5, 0.0),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(sc.r, sc.g, sc.b, _neon_flicker))

	# Reflection smear on wet back sidewalk
	if not locked:
		for rx_off in [-0.4, -0.1, 0.2, 0.5]:
			var alpha := 0.10 * _neon_flicker * (0.7 + 0.3 * sin(_time * 2.0 + rx_off))
			var r1 := iso(gx + rx_off - 0.06, gy + 0.6, GZ_BACK_SW + 0.002)
			var r2 := iso(gx + rx_off + 0.06, gy + 0.6, GZ_BACK_SW + 0.002)
			var r3 := iso(gx + rx_off + 0.08, gy + 1.2, GZ_BACK_SW + 0.002)
			var r4 := iso(gx + rx_off - 0.08, gy + 1.2, GZ_BACK_SW + 0.002)
			var rpts := PackedVector2Array()
			rpts.append(r1); rpts.append(r2); rpts.append(r3); rpts.append(r4)
			draw_colored_polygon(rpts, Color(sc.r, sc.g, sc.b, alpha))


func _draw_proximity_indicator(gx: float, gy: float) -> void:
	var pulse := 0.55 + 0.45 * sin(_time * 3.2)
	var r := 0.28 * pulse
	var pts := PackedVector2Array()
	pts.append(iso(gx - r, gy + 0.5, 0.002))
	pts.append(iso(gx,     gy + 0.5 - r * 0.5, 0.002))
	pts.append(iso(gx + r, gy + 0.5, 0.002))
	pts.append(iso(gx,     gy + 0.5 + r * 0.5, 0.002))
	draw_colored_polygon(pts, Color(0.28, 1.0, 0.42, 0.32 * pulse))
	draw_polyline(pts, Color(0.38, 1.0, 0.52, 0.72 * pulse), 1.2, false)


# ── Pedestrians ───────────────────────────────────────────────────────────────

# Pedestrian accent palettes
const PED_ACCENTS := [
	Color(0.28, 0.38, 0.55),   # grey-blue coat
	Color(0.35, 0.22, 0.18),   # dark brown jacket
	Color(0.18, 0.30, 0.22),   # dark green coat
	Color(0.32, 0.28, 0.42),   # muted purple
	Color(0.20, 0.20, 0.28),   # charcoal
]

func _draw_pedestrians() -> void:
	# Sort back-to-front for painter's algo
	var sorted := _peds.duplicate()
	sorted.sort_custom(func(a, b): return float(a["gx"]) < float(b["gx"]))
	for p in _peds:
		_draw_pedestrian(p)


func _draw_pedestrian(p: Dictionary) -> void:
	var pgx: float = p["gx"]
	var pgy := PED_ROW
	var pos := iso(pgx, pgy, GZ_BACK_SW)
	var wt: float  = p["walk_t"]
	var dir: int   = p["dir"]
	var cidx: int  = p["col"]
	var acc := PED_ACCENTS[cidx % PED_ACCENTS.size()]
	var flip := float(dir)

	# Shadow
	var sh := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		sh.append(iso(pgx + cos(a) * 0.18, pgy + sin(a) * 0.09, GZ_BACK_SW + 0.01))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.35))

	# Scale down slightly from player
	var s := 0.80
	var bob  := sin(wt) * 1.8 * s
	var step1 :=  sin(wt) * 4.0 * s
	var step2 := -step1
	var arm_s := sin(wt) * 5.5 * s

	var body  := Color(0.08, 0.08, 0.12, 1.0)
	var cloth := acc.darkened(0.35)
	var skin  := Color(0.50, 0.38, 0.28, 1.0)

	# Shoes
	draw_rect(Rect2(pos.x - 6*s*flip, pos.y - 4*s, 7*s, 4*s), body)
	draw_rect(Rect2(pos.x + 1*s*flip, pos.y - 3*s, 6*s, 3*s), body)
	# Legs
	draw_rect(Rect2(pos.x - 7*s*flip, pos.y - 20*s + bob + step1, 6*s, 17*s), cloth.lightened(0.08))
	draw_rect(Rect2(pos.x + 2*s*flip, pos.y - 19*s + bob + step2, 6*s, 16*s), cloth)
	# Belt
	draw_rect(Rect2(pos.x - 8*s, pos.y - 22*s + bob, 16*s, 3*s), body.lightened(0.08))
	# Jacket
	draw_rect(Rect2(pos.x - 8*s, pos.y - 42*s + bob, 16*s, 22*s), cloth)
	# Arms
	draw_rect(Rect2(pos.x - 13*s*flip, pos.y - 39*s + bob + arm_s*flip, 5*s, 15*s), cloth)
	draw_rect(Rect2(pos.x +  8*s*flip, pos.y - 39*s + bob - arm_s*flip, 5*s, 15*s), cloth)
	# Neck + head
	draw_rect(Rect2(pos.x - 2*s, pos.y - 46*s + bob, 5*s, 5*s), skin)
	draw_circle(Vector2(pos.x, pos.y - 53*s + bob), 8*s, skin)
	# Hair
	draw_rect(Rect2(pos.x - 8*s, pos.y - 63*s + bob, 16*s, 6*s), body)


# ── Player ────────────────────────────────────────────────────────────────────

func _draw_player() -> void:
	var gy := float(WALK_ROW)
	var pos := iso(_player_gx, gy + 0.5, GZ_SIDEWALK)

	# Shadow
	var sh := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0
		sh.append(iso(_player_gx + cos(a) * 0.26, gy + 0.5 + sin(a) * 0.13, GZ_SIDEWALK + 0.01))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.48))

	_draw_character_sprite(pos)

	# Player indicator dot above head
	var head_pos := pos - Vector2(0, 82)
	var alpha := 0.65 + 0.35 * sin(_time * 2.8)
	# Outer ring
	for g in 3:
		draw_circle(head_pos, 6.0 + float(g) * 3.0, Color(0.3, 1.0, 0.4, 0.06 - float(g) * 0.015))
	draw_circle(head_pos, 4.0, Color(0.3, 1.0, 0.4, alpha))


func _draw_character_sprite(pos: Vector2) -> void:
	var bob := sin(_player_walk_t) * 2.4 if _player_moving else 0.0
	var flip := float(_player_dir)

	var body  := Color(0.08, 0.08, 0.13, 1.0)
	var cloth := Color(0.18, 0.16, 0.26, 1.0)
	var skin  := Color(0.55, 0.42, 0.32, 1.0)

	var step1 :=  sin(_player_walk_t) * 5.5 if _player_moving else 0.0
	var step2 := -step1
	var arm_swing := sin(_player_walk_t) * 7.5 if _player_moving else 0.0

	# Shoes
	draw_rect(Rect2(pos.x - 7*flip, pos.y - 5, 9, 5), body)
	draw_rect(Rect2(pos.x + 1*flip, pos.y - 4, 8, 4), body)
	# Legs
	var ll := cloth.lightened(0.10)
	draw_rect(Rect2(pos.x - 8*flip, pos.y - 24 + bob + step1, 7, 20), ll)
	draw_rect(Rect2(pos.x + 2*flip, pos.y - 23 + bob + step2, 7, 19), cloth)
	draw_rect(Rect2(pos.x - 6*flip, pos.y - 14 + bob + step1, 4, 3), ll.lightened(0.15))
	# Belt
	draw_rect(Rect2(pos.x - 10, pos.y - 26 + bob, 20, 3), body.lightened(0.10))
	# Jacket
	draw_rect(Rect2(pos.x - 10, pos.y - 50 + bob, 20, 26), cloth)
	# Lapels
	var lpts := PackedVector2Array()
	var lpx := pos.x - 10*flip
	lpts.append(Vector2(lpx,          pos.y - 50 + bob))
	lpts.append(Vector2(lpx + 5*flip, pos.y - 50 + bob))
	lpts.append(Vector2(pos.x,        pos.y - 38 + bob))
	draw_colored_polygon(lpts, cloth.darkened(0.22))
	draw_rect(Rect2(pos.x - 4, pos.y - 50 + bob, 8, 5), cloth.lightened(0.08))
	# Arms
	draw_rect(Rect2(pos.x - 16*flip, pos.y - 47 + bob + arm_swing*flip, 6, 18), cloth)
	draw_rect(Rect2(pos.x + 10*flip, pos.y - 47 + bob - arm_swing*flip, 6, 18), cloth)
	draw_circle(pos - Vector2(13*flip, 30 - bob - arm_swing*flip), 4, skin)
	draw_circle(pos + Vector2(13*flip, -30 + bob - arm_swing*flip), 4, skin)
	# Neck
	draw_rect(Rect2(pos.x - 3, pos.y - 55 + bob, 6, 6), skin)
	# Head
	draw_circle(pos - Vector2(0, 63 - bob), 10, skin)
	draw_rect(Rect2(pos.x - 10, pos.y - 76 + bob, 20, 8), body)
	draw_rect(Rect2(pos.x - 10, pos.y - 73 + bob, 20, 5), body.lightened(0.08))
	# Eyes
	var ey := pos.y - 64 + bob
	draw_rect(Rect2(pos.x + 2*flip, ey, 4, 3), Color(0.06, 0.06, 0.10, 1.0))
	draw_rect(Rect2(pos.x - 6*flip, ey, 4, 3), Color(0.15, 0.15, 0.22, 1.0))
	# Laptop bag
	draw_rect(Rect2(pos.x - 13*flip, pos.y - 48 + bob, 4, 20), Color(0.18, 0.16, 0.12, 1.0))
	draw_rect(Rect2(pos.x - 17*flip, pos.y - 34 + bob, 14, 16), Color(0.14, 0.12, 0.10, 1.0))
	# Bag clasp
	draw_rect(Rect2(pos.x - 14*flip, pos.y - 29 + bob, 6, 3), Color(0.28, 0.24, 0.18, 0.8))


# ── Rain ──────────────────────────────────────────────────────────────────────

func _draw_rain() -> void:
	for r in _rain:
		var p: Vector2 = r["pos"]
		var length: float = r["len"]
		var alpha: float  = r["alpha"]
		# Primary streak
		draw_line(p, p + Vector2(3.5, length),
				Color(0.50, 0.56, 0.76, alpha), 0.8)
		# Faint secondary (slightly offset for depth)
		draw_line(p + Vector2(1, 0), p + Vector2(4.5, length * 0.7),
				Color(0.40, 0.46, 0.66, alpha * 0.4), 0.5)


# ── Tilt-shift vignette ───────────────────────────────────────────────────────

func _draw_tilt_shift() -> void:
	# Top gradient (sky → scene transition)
	for i in 12:
		var t := 1.0 - float(i) / 12.0
		draw_rect(Rect2(0, float(i) * 8, _size.x, 9),
				Color(0.0, 0.0, 0.0, 0.65 * t * t))
	# Bottom gradient
	for i in 12:
		var t := 1.0 - float(i) / 12.0
		draw_rect(Rect2(0, _size.y - float(i) * 10, _size.x, 11),
				Color(0.0, 0.0, 0.0, 0.55 * t * t))
	# Side vignettes
	for i in 8:
		var t := 1.0 - float(i) / 8.0
		draw_rect(Rect2(float(i) * 8, 0, 9, _size.y),
				Color(0.0, 0.0, 0.0, 0.28 * t * t))
		draw_rect(Rect2(_size.x - float(i) * 8 - 9, 0, 9, _size.y),
				Color(0.0, 0.0, 0.0, 0.28 * t * t))


# ── Minimap ───────────────────────────────────────────────────────────────────

func _draw_minimap() -> void:
	var ms: Vector2 = _minimap_ctrl.get_rect().size
	if ms == Vector2.ZERO: return

	_minimap_ctrl.draw_rect(Rect2(0, 0, ms.x, ms.y), Color(0.018, 0.018, 0.032, 0.92))
	# Border
	_minimap_ctrl.draw_rect(Rect2(0, 0, ms.x, 1), Color(0.14, 0.12, 0.24, 1.0))
	_minimap_ctrl.draw_rect(Rect2(0, ms.y - 1, ms.x, 1), Color(0.14, 0.12, 0.24, 1.0))
	_minimap_ctrl.draw_rect(Rect2(0, 0, 1, ms.y), Color(0.14, 0.12, 0.24, 1.0))
	_minimap_ctrl.draw_rect(Rect2(ms.x - 1, 0, 1, ms.y), Color(0.14, 0.12, 0.24, 1.0))

	var pad   := 10.0
	var bar_y := ms.y * 0.50
	var map_w := ms.x - pad * 2.0
	# Street line
	_minimap_ctrl.draw_rect(Rect2(pad, bar_y - 1.5, map_w, 3.0), Color(0.09, 0.09, 0.16, 1.0))

	# Location markers
	for loc in _locations:
		var d: Dictionary = loc as Dictionary
		var lx := _loc_grid_x(d)
		var sc_str := _str(d.get("sign_color")) if d.get("sign_color") != null else "#aaaaaa"
		var sc := Color.html(sc_str)
		var uc: String = _str(d.get("unlock_clue"))
		var locked := uc != "" and not (uc in GameState.discovered_clues)
		var mx := pad + (lx / float(GRID_COLS)) * map_w
		var col := Color(sc.r, sc.g, sc.b, 0.28 if locked else 0.88)
		_minimap_ctrl.draw_rect(Rect2(mx - 3, bar_y - 6, 6, 12), col)
		if not locked:
			for g in 2:
				_minimap_ctrl.draw_rect(Rect2(mx - 3 - g, bar_y - 6 - g, 6 + g*2, 12 + g*2),
						Color(sc.r, sc.g, sc.b, 0.06 - float(g) * 0.025))

	# Player dot
	var px := pad + (_player_gx / float(GRID_COLS)) * map_w
	var blink := (sin(Time.get_ticks_msec() * 0.007) + 1.0) * 0.5
	_minimap_ctrl.draw_circle(Vector2(px, bar_y), 3.5,
			Color(0.2, 1.0, 0.45, 0.55 + blink * 0.45))

	_minimap_ctrl.draw_string(ThemeDB.fallback_font, Vector2(pad, ms.y - 5.0),
			"BLOCK 7 — 02:14AM", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.28, 0.28, 0.42, 0.80))


# ── Enter location ────────────────────────────────────────────────────────────

func _try_enter(loc_id: String) -> void:
	if _entering_scene: return
	var loc := _get_location(loc_id)
	if loc.is_empty(): return

	var uc: String = _str(loc.get("unlock_clue"))
	if uc != "" and not (uc in GameState.discovered_clues):
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
		"cafe":      scene_path = CAFE_SCENE
		"bar":       scene_path = BAR_SCENE
		"apartment": scene_path = APARTMENT_SCENE

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
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	draw_colored_polygon(pts, col)
