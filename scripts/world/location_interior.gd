extends Control

# Corporate Theater — LocationInterior (Isometric)
#
# Full isometric room matching the outside scene's visual language.
# Shared by all 3 interiors; location_id drives layout, palette, NPC, objects.
#
# Coordinate system identical to outside.gd:
#   iso(gx, gy, gz) -> Vector2 screen position
#   gz = elevation (0 = floor level)
#
# Room layout (grid coords, all rooms are ROOM_W x ROOM_D tiles):
#   Back wall along gy=0, front open at gy=ROOM_D
#   Player enters from front-left (gx~1, gy~ROOM_D-1)
#   NPC stands near back at a location-specific position
#
# Interaction objects are defined per room type.
# Player walks left/right (gx), and forward/back (gy) on the floor.
# Pressing E near an object or NPC triggers action.

const LOCATIONS_PATH  := "res://data/world/locations.json"
const OUTSIDE_SCENE   := "res://scenes/world/outside.tscn"
const DIALOGUE_SCRIPT := "res://scripts/world/dialogue_system.gd"

@export var location_id: String = ""

# ── Iso constants (match outside.gd) ─────────────────────────────────────────
const TILE_W := 80.0
const TILE_H := 40.0
const TILE_Z := 40.0

# ── Room grid ─────────────────────────────────────────────────────────────────
const ROOM_W := 10    # tiles wide
const ROOM_D := 8     # tiles deep

# ── Player movement ───────────────────────────────────────────────────────────
const PLAYER_SPEED   := 3.8
const INTERACT_DIST  := 1.3

# ── State ─────────────────────────────────────────────────────────────────────
var _loc: Dictionary = {}
var _size: Vector2 = Vector2.ZERO
var _origin: Vector2 = Vector2.ZERO

var _player_gx: float = 1.5
var _player_gy: float = 6.5
var _player_walk_t: float = 0.0
var _player_moving: bool = false
var _player_dir: int = 1

var _time: float = 0.0
var _neon_flicker: float = 1.0
var _flicker_t: float = 0.0

# Objects the player can interact with (populated per room type)
# Each entry: { id, gx, gy, label, examined }
var _objects: Array = []
var _npc_gx: float = 7.0
var _npc_gy: float = 2.0
var _npc_walk_t: float = 0.0

var _near_id: String = ""    # id of nearest interactable (object or "npc")
var _prompt_alpha: float = 0.0
var _dialogue_active: bool = false
var _entering_outside: bool = false

# Examine overlay
var _examine_text: String = ""
var _examine_timer: float = 0.0

# Ambient smoke/dust
var _particles: Array = []
const DUST_COUNT := 18

# Rain on windows (static positions, refreshed rarely)
var _window_rain: Array = []

# ── UI ────────────────────────────────────────────────────────────────────────
var _prompt_label: Label
var _hint_label: Label
var _examine_label: Label


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

func draw_tile(gx: float, gy: float, gz: float, col: Color) -> void:
	draw_colored_polygon(tile_top(gx, gy, gz), col)

func box_front(gx: float, gy: float, gz_bot: float, gz_top: float) -> PackedVector2Array:
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

func draw_iso_box(gx: float, gy: float, w: float, d: float,
		gz_bot: float, gz_top: float,
		top_c: Color, front_c: Color, right_c: Color) -> void:
	# Right face
	var rf := PackedVector2Array()
	rf.append(iso(gx + w, gy,     gz_bot))
	rf.append(iso(gx + w, gy,     gz_top))
	rf.append(iso(gx + w, gy + d, gz_top))
	rf.append(iso(gx + w, gy + d, gz_bot))
	draw_colored_polygon(rf, right_c)
	# Front face
	var ff := PackedVector2Array()
	ff.append(iso(gx,     gy + d, gz_bot))
	ff.append(iso(gx,     gy + d, gz_top))
	ff.append(iso(gx + w, gy + d, gz_top))
	ff.append(iso(gx + w, gy + d, gz_bot))
	draw_colored_polygon(ff, front_c)
	# Top face
	var tp := PackedVector2Array()
	tp.append(iso(gx,     gy,     gz_top))
	tp.append(iso(gx + w, gy,     gz_top))
	tp.append(iso(gx + w, gy + d, gz_top))
	tp.append(iso(gx,     gy + d, gz_top))
	draw_colored_polygon(tp, top_c)

func iso_line(ax: float, ay: float, az: float,
			  bx: float, by: float, bz: float,
			  col: Color, w: float = 1.0) -> void:
	draw_line(iso(ax, ay, az), iso(bx, by, bz), col, w)

func _draw_ellipse_iso(gx: float, gy: float, gz: float,
		rx: float, ry_tile: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(iso(gx + cos(a) * rx, gy + sin(a) * ry_tile, gz))
	draw_colored_polygon(pts, col)


# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	if location_id == "" and has_meta("location_id"):
		location_id = str(get_meta("location_id"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_size = get_rect().size
	if _size == Vector2.ZERO:
		await get_tree().process_frame
		_size = get_rect().size
	_recalc_origin()
	_load_location()
	_setup_room()
	_init_particles()
	_build_ui()


func _load_location() -> void:
	if not FileAccess.file_exists(LOCATIONS_PATH):
		return
	var file := FileAccess.open(LOCATIONS_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var locs: Array = (json.data as Dictionary).get("locations", []) as Array
	for l in locs:
		var d: Dictionary = l as Dictionary
		if _str(d.get("id")) == location_id:
			_loc = d
			return


func _recalc_origin() -> void:
	_size = get_rect().size
	if _size == Vector2.ZERO:
		return
	# Center the room grid on screen, shifted up a bit for headroom
	var cx := (float(ROOM_W) * 0.5 - float(ROOM_D) * 0.5) * (TILE_W * 0.5)
	var cy := (float(ROOM_W) * 0.5 + float(ROOM_D) * 0.5) * (TILE_H * 0.5)
	_origin = Vector2(_size.x * 0.5 - cx, _size.y * 0.44 - cy)


func _setup_room() -> void:
	var itype := _str(_loc.get("interior_type"))
	_objects.clear()
	match itype:
		"cafe":       _setup_cafe()
		"bar":        _setup_bar()
		"apartment":  _setup_apartment()
	# Store NPC as interactable target
	_npc_gx = 7.0; _npc_gy = 2.5
	_window_rain.clear()
	for i in 24:
		_window_rain.append({
			"x": randf(), "y": randf_range(0.05, 0.85),
			"len": randf_range(0.04, 0.12), "speed": randf_range(0.03, 0.09)
		})


func _setup_cafe() -> void:
	_npc_gx = 6.5; _npc_gy = 2.0
	_objects = [
		{ "id": "menu",      "gx": 2.0, "gy": 4.5, "label": "[ E ] read menu",
		  "examine": "Handwritten menu. Tonight's special: black coffee, no questions asked." },
		{ "id": "newspaper", "gx": 4.5, "gy": 5.0, "label": "[ E ] pick up newspaper",
		  "examine": "CNX TECH: 'ClosedAI Safety Compact Wins UN Endorsement.' Page 1." },
		{ "id": "payphone",  "gx": 0.8, "gy": 3.0, "label": "[ E ] check payphone",
		  "examine": "Dead. Receiver off the hook. A torn note inside the coin return: 'CAI-IR'. Your pulse quickens." },
		{ "id": "ashtray",   "gx": 3.5, "gy": 4.8, "label": "[ E ] examine ashtray",
		  "examine": "A ceramic ashtray. Three cigarettes. Two lipstick marks, one clean — someone left mid-smoke." },
		{ "id": "cctv",      "gx": 8.5, "gy": 0.8, "label": "[ E ] look at camera",
		  "examine": "CCTV dome. Red light blinking. It's been rotated to face this table specifically." },
	]


func _setup_bar() -> void:
	_npc_gx = 7.0; _npc_gy = 2.0
	_objects = [
		{ "id": "tv",       "gx": 8.2, "gy": 1.0, "label": "[ E ] watch TV",
		  "examine": "Muted news ticker. '...HORIZON INITIATIVE EXPANDS TO 14 CITIES...' Then static." },
		{ "id": "jukebox",  "gx": 0.8, "gy": 1.5, "label": "[ E ] jukebox",
		  "examine": "An old Wurlitzer. Playing track 7: silence. Someone pulled the record." },
		{ "id": "napkin",   "gx": 3.0, "gy": 5.0, "label": "[ E ] read napkin",
		  "examine": "A napkin with a diagram. Nodes and edges. One node circled: VEIL. Handwriting is shaking." },
		{ "id": "bottle",   "gx": 5.5, "gy": 5.2, "label": "[ E ] examine bottle",
		  "examine": "Cheap whiskey. Half empty. The label has a bar code sticker over it — ClosedAI internal label." },
		{ "id": "door_back","gx": 8.8, "gy": 0.5, "label": "[ E ] back door",
		  "examine": "Locked. Damp marks on the frame. Someone went through here recently — and left fast." },
	]


func _setup_apartment() -> void:
	_npc_gx = 6.0; _npc_gy = 2.5
	_objects = [
		{ "id": "monitor",   "gx": 7.5, "gy": 1.5, "label": "[ E ] check monitor",
		  "examine": "Three open terminals. One tab: an SSH session to a host named 'horizon-relay-09'. Connection closed." },
		{ "id": "whiteboard","gx": 1.0, "gy": 1.0, "label": "[ E ] read whiteboard",
		  "examine": "A whiteboard covered in erasures. Through the smears: 'INTAKE → HASH → VEIL_TARGET_DB'. Arrow down: 'ZERO CONSENT'." },
		{ "id": "printouts", "gx": 4.5, "gy": 5.0, "label": "[ E ] examine printouts",
		  "examine": "Stacked paper. API response logs. Every entry: client_id='horizon_gen', output_type='social_narrative'. Hundreds of them." },
		{ "id": "burner",    "gx": 2.5, "gy": 4.5, "label": "[ E ] burner phone",
		  "examine": "A burner phone, battery out. SIM card taped under the desk with a number: +1-202-555-0191." },
		{ "id": "window_lock","gx": 9.2, "gy": 0.8, "label": "[ E ] window",
		  "examine": "Reinforced window lock, new. Rope ladder coiled underneath. She planned an exit route." },
	]


func _init_particles() -> void:
	_particles.clear()
	for i in DUST_COUNT:
		_particles.append({
			"gx": randf_range(0.5, float(ROOM_W) - 0.5),
			"gy": randf_range(0.5, float(ROOM_D) - 0.5),
			"gz": randf_range(0.1, 2.5),
			"vz": randf_range(0.02, 0.08),
			"alpha": randf_range(0.03, 0.10),
			"r": randf_range(1.5, 3.5),
		})


func _build_ui() -> void:
	_prompt_label = Label.new()
	_prompt_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75, 1.0))
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.modulate.a = 0.0
	_prompt_label.set_anchor_and_offset(SIDE_LEFT,   0.0,  0.0)
	_prompt_label.set_anchor_and_offset(SIDE_RIGHT,  1.0,  0.0)
	_prompt_label.set_anchor_and_offset(SIDE_TOP,    0.84, 0.0)
	_prompt_label.set_anchor_and_offset(SIDE_BOTTOM, 0.84, 26.0)
	add_child(_prompt_label)

	_hint_label = Label.new()
	_hint_label.add_theme_color_override("font_color", Color(0.30, 0.30, 0.42, 1.0))
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.text = "[ ESC ] leave   [ arrows / WASD ] move   [ E ] interact"
	_hint_label.set_anchor_and_offset(SIDE_LEFT,   0.0,  8.0)
	_hint_label.set_anchor_and_offset(SIDE_RIGHT,  1.0, -8.0)
	_hint_label.set_anchor_and_offset(SIDE_TOP,    1.0, -22.0)
	_hint_label.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -4.0)
	add_child(_hint_label)

	_examine_label = Label.new()
	_examine_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.85, 1.0))
	_examine_label.add_theme_font_size_override("font_size", 12)
	_examine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_examine_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_examine_label.modulate.a = 0.0
	_examine_label.set_anchor_and_offset(SIDE_LEFT,   0.15, 0.0)
	_examine_label.set_anchor_and_offset(SIDE_RIGHT,  0.85, 0.0)
	_examine_label.set_anchor_and_offset(SIDE_TOP,    0.87, 0.0)
	_examine_label.set_anchor_and_offset(SIDE_BOTTOM, 0.98, 0.0)
	add_child(_examine_label)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_return_outside()
			KEY_E, KEY_ENTER:
				if _near_id != "":
					get_viewport().set_input_as_handled()
					_interact(_near_id)


func _return_outside() -> void:
	if _entering_outside: return
	_entering_outside = true
	var parent := get_parent()
	if parent == null: return
	var res := load(OUTSIDE_SCENE)
	if res == null: return
	var o: Control = res.instantiate()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(o)
	queue_free()


func _interact(id: String) -> void:
	if id == "npc":
		_start_dialogue()
		return
	for obj in _objects:
		if obj["id"] == id:
			_examine_text = obj["examine"] as String
			_examine_timer = 4.5
			return


# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_size = get_rect().size
	if _size == Vector2.ZERO: return
	_time += delta
	_recalc_origin()
	_update_flicker(delta)

	if not _dialogue_active:
		_handle_movement(delta)

	_update_proximity()
	_update_particles(delta)
	_update_window_rain(delta)
	_update_examine(delta)

	queue_redraw()


func _update_flicker(delta: float) -> void:
	_flicker_t -= delta
	if _flicker_t <= 0.0:
		_flicker_t = randf_range(0.06, 0.40)
		_neon_flicker = randf_range(0.80, 1.0)


func _handle_movement(delta: float) -> void:
	var mx := 0; var my := 0
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): mx -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): mx += 1
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): my -= 1
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): my += 1

	_player_moving = (mx != 0 or my != 0)
	if _player_moving:
		if mx != 0: _player_dir = mx
		_player_walk_t += delta * 5.5
		_player_gx = clampf(_player_gx + mx * PLAYER_SPEED * delta, 0.3, float(ROOM_W) - 0.8)
		_player_gy = clampf(_player_gy + my * PLAYER_SPEED * delta, 0.3, float(ROOM_D) - 0.5)


func _update_proximity() -> void:
	_near_id = ""
	# Check NPC
	var dnpc := Vector2(_player_gx - _npc_gx, _player_gy - _npc_gy).length()
	if dnpc < INTERACT_DIST:
		_near_id = "npc"
		return
	# Check objects
	for obj in _objects:
		var ox: float = obj["gx"]
		var oy: float = obj["gy"]
		var d := Vector2(_player_gx - ox, _player_gy - oy).length()
		if d < INTERACT_DIST:
			_near_id = obj["id"] as String
			return

	var want := 1.0 if _near_id != "" else 0.0
	_prompt_alpha = lerpf(_prompt_alpha, want, 10.0 * get_process_delta_time())

	if _near_id == "npc":
		_prompt_label.text = "[ E ] talk"
	elif _near_id != "":
		for obj in _objects:
			if obj["id"] == _near_id:
				_prompt_label.text = obj["label"] as String
				break
	else:
		_prompt_label.text = ""

	_prompt_label.modulate.a = _prompt_alpha


func _update_particles(delta: float) -> void:
	for p in _particles:
		p["gz"] = p["gz"] + p["vz"] * delta
		if p["gz"] > 3.0:
			p["gz"] = 0.05
			p["gx"] = randf_range(0.5, float(ROOM_W) - 0.5)
			p["gy"] = randf_range(0.5, float(ROOM_D) - 0.5)


func _update_window_rain(delta: float) -> void:
	for r in _window_rain:
		r["y"] = r["y"] + r["speed"] * delta
		if r["y"] > 0.95:
			r["y"] = randf_range(0.0, 0.15)
			r["x"] = randf()


func _update_examine(delta: float) -> void:
	if _examine_timer > 0.0:
		_examine_timer -= delta
		_examine_label.text = _examine_text
		_examine_label.modulate.a = minf(_examine_timer, 1.0)
	else:
		_examine_label.modulate.a = 0.0


# ── DRAW ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _size == Vector2.ZERO or _loc.is_empty():
		return

	var itype := _str(_loc.get("interior_type"))
	if itype == "": itype = "cafe"

	_draw_ceiling_and_walls(itype)
	_draw_floor(itype)
	_draw_room_objects(itype)
	_draw_particles()
	_draw_npc()
	_draw_player()
	_draw_tilt_shift()


# ── Ceiling / Walls ───────────────────────────────────────────────────────────

func _draw_ceiling_and_walls(itype: String) -> void:
	var pal := _palette(itype)

	# Back wall (gy=0 face) — tall slab behind all tiles
	var wall_top_gz := 4.5
	var ff := PackedVector2Array()
	ff.append(iso(0,        0.0, 0.0))
	ff.append(iso(0,        0.0, wall_top_gz))
	ff.append(iso(ROOM_W,   0.0, wall_top_gz))
	ff.append(iso(ROOM_W,   0.0, 0.0))
	draw_colored_polygon(ff, pal.wall_back)

	# Left wall (gx=0 face)
	var lw := PackedVector2Array()
	lw.append(iso(0.0, 0.0,      0.0))
	lw.append(iso(0.0, 0.0,      wall_top_gz))
	lw.append(iso(0.0, ROOM_D,   wall_top_gz))
	lw.append(iso(0.0, ROOM_D,   0.0))
	draw_colored_polygon(lw, pal.wall_left)

	# Ceiling slab
	var ceil := PackedVector2Array()
	ceil.append(iso(0,      0.0,    wall_top_gz))
	ceil.append(iso(ROOM_W, 0.0,    wall_top_gz))
	ceil.append(iso(ROOM_W, ROOM_D, wall_top_gz))
	ceil.append(iso(0,      ROOM_D, wall_top_gz))
	draw_colored_polygon(ceil, pal.ceiling)

	# Wall trim / baseboard along back wall
	iso_line(0, 0.0, 0.25, ROOM_W, 0.0, 0.25, pal.trim, 1.5)
	iso_line(0, 0.0, wall_top_gz - 0.2, ROOM_W, 0.0, wall_top_gz - 0.2, pal.trim, 1.0)
	# Left wall trim
	iso_line(0.0, 0.0, 0.25, 0.0, ROOM_D, 0.25, pal.trim, 1.5)

	# Back wall windows
	_draw_back_wall_windows(itype, pal, wall_top_gz)

	# Overhead lights / hanging fixture
	_draw_ceiling_lights(itype, pal, wall_top_gz)


func _draw_back_wall_windows(itype: String, pal: RefCounted, wall_top_gz: float) -> void:
	# 2 windows in back wall, showing dark rainy night outside
	var win_positions := [2.5, 6.5] if itype != "bar" else [7.5]
	for wx in win_positions:
		var ww := 1.4; var wh := 1.8; var wgz := 1.2
		# Window recess (dark blue-black outside view)
		var wp := PackedVector2Array()
		wp.append(iso(wx,      0.0, wgz))
		wp.append(iso(wx,      0.0, wgz + wh))
		wp.append(iso(wx + ww, 0.0, wgz + wh))
		wp.append(iso(wx + ww, 0.0, wgz))
		draw_colored_polygon(wp, Color(0.02, 0.03, 0.06, 1.0))

		# Night sky glow
		var glow_c := Color(0.04, 0.06, 0.14, 0.6)
		draw_colored_polygon(wp, glow_c)

		# Window frame
		draw_polyline(wp, pal.trim.lightened(0.2), 2.0, true)
		# Cross bar
		iso_line(wx, 0.0, wgz + wh * 0.5, wx + ww, 0.0, wgz + wh * 0.5, pal.trim, 1.5)
		iso_line(wx + ww * 0.5, 0.0, wgz, wx + ww * 0.5, 0.0, wgz + wh, pal.trim, 1.5)

		# Rain streaks (screen-space, mapped to window face)
		var tl := iso(wx,      0.0, wgz + wh)
		var br := iso(wx + ww, 0.0, wgz)
		var win_w_px := (br.x - tl.x)
		var win_h_px := (br.y - tl.y)
		for r in _window_rain:
			var rx: float = tl.x + r["x"] * win_w_px
			var ry: float = tl.y + r["y"] * win_h_px
			var rlen: float = r["len"] * win_h_px
			draw_line(Vector2(rx, ry), Vector2(rx + 1.5, ry + rlen),
					Color(0.15, 0.2, 0.35, 0.5), 0.8)

		# Outside city glow bleed
		var glow_top := iso(wx,      0.0, wgz + wh * 0.6)
		var glow_bot := iso(wx + ww, 0.0, wgz)
		for g in 4:
			var ga := 0.08 - float(g) * 0.016
			draw_rect(Rect2(glow_top.x - g, glow_top.y - g,
					glow_bot.x - glow_top.x + g * 2,
					glow_bot.y - glow_top.y + g * 2),
					Color(0.08, 0.10, 0.25, ga))


func _draw_ceiling_lights(itype: String, pal: RefCounted, wall_top_gz: float) -> void:
	# Hanging light fixtures casting a cone down
	var light_positions := []
	match itype:
		"cafe":      light_positions = [[3.0, 3.0], [7.0, 3.0]]
		"bar":       light_positions = [[2.0, 3.5], [5.0, 3.5], [8.0, 3.5]]
		"apartment": light_positions = [[5.0, 3.0]]

	for lp in light_positions:
		var lgx: float = lp[0]; var lgy: float = lp[1]
		var hang_gz := wall_top_gz - 0.4

		# Cord from ceiling
		iso_line(lgx, lgy, wall_top_gz, lgx, lgy, hang_gz, pal.trim, 1.0)

		# Shade box
		draw_iso_box(lgx - 0.2, lgy - 0.2, 0.4, 0.4,
				hang_gz - 0.3, hang_gz,
				pal.light_shade, pal.light_shade.darkened(0.2), pal.light_shade.darkened(0.35))

		# Light bulb glow (screen space)
		var lpos := iso(lgx, lgy, hang_gz - 0.3)
		for g in 7:
			var ga := 0.10 - float(g) * 0.012
			var gr := 14.0 + g * 22.0
			draw_circle(lpos, gr, Color(pal.light_color.r, pal.light_color.g, pal.light_color.b, ga))
		draw_circle(lpos, 5.0, Color(1.0, 0.95, 0.8, 0.95))

		# Light cone on floor (very faint)
		var cone_pts := PackedVector2Array()
		cone_pts.append(lpos)
		cone_pts.append(iso(lgx - 1.2, lgy + 1.2, 0.01))
		cone_pts.append(iso(lgx + 1.2, lgy + 1.2, 0.01))
		draw_colored_polygon(cone_pts,
				Color(pal.light_color.r, pal.light_color.g, pal.light_color.b, 0.05))


# ── Floor ─────────────────────────────────────────────────────────────────────

func _draw_floor(itype: String) -> void:
	var pal := _palette(itype)
	for gy in ROOM_D:
		for gx in ROOM_W:
			_draw_floor_tile(gx, gy, itype, pal)


func _draw_floor_tile(gx: int, gy: int, itype: String, pal: RefCounted) -> void:
	var checker := (gx + gy) % 2 == 0
	var base: Color = pal.floor_a if checker else pal.floor_b

	# Subtle depth darkening toward back
	var depth := float(gy) / float(ROOM_D)
	var tile_c := base.darkened(depth * 0.18)

	draw_tile(gx, gy, 0.0, tile_c)

	# Floor grout lines (thin border on each tile)
	var pts := tile_top(gx, gy, 0.0)
	draw_polyline(pts, pal.grout, 0.6, true)

	# Puddle reflections near front
	if gy >= ROOM_D - 3 and (gx * 3 + gy * 7) % 9 == 0:
		var sc := tile_top(float(gx) + 0.15, float(gy) + 0.15, 0.002)
		# shrink polygon
		var center := Vector2.ZERO
		for p in sc: center += p
		center /= sc.size()
		var shrunk := PackedVector2Array()
		for p in sc: shrunk.append(center.lerp(p, 0.55))
		var pulse := 0.06 + 0.03 * sin(_time * 1.8 + gx + gy)
		draw_colored_polygon(shrunk, Color(pal.light_color.r, pal.light_color.g,
				pal.light_color.b, pulse))

	# Area rug (cafe and apartment)
	if itype == "cafe" and gx >= 2 and gx <= 6 and gy >= 3 and gy <= 6:
		draw_tile(gx, gy, 0.001, Color(0.12, 0.08, 0.06, 0.55))
	if itype == "apartment" and gx >= 3 and gx <= 7 and gy >= 2 and gy <= 5:
		draw_tile(gx, gy, 0.001, Color(0.05, 0.09, 0.07, 0.50))


# ── Room objects ──────────────────────────────────────────────────────────────

func _draw_room_objects(itype: String) -> void:
	var pal := _palette(itype)
	match itype:
		"cafe":      _draw_cafe_objects(pal)
		"bar":       _draw_bar_objects(pal)
		"apartment": _draw_apartment_objects(pal)

	# Draw interactable object indicators
	_draw_object_markers()


func _draw_object_markers() -> void:
	for obj in _objects:
		var ox: float = obj["gx"]; var oy: float = obj["gy"]
		var d := Vector2(_player_gx - ox, _player_gy - oy).length()
		if d < INTERACT_DIST * 2.2:
			var pulse := 0.4 + 0.35 * sin(_time * 3.5)
			var pts := PackedVector2Array()
			var r := 0.22 * (1.0 - d / (INTERACT_DIST * 2.2)) * pulse
			pts.append(iso(ox - r, oy,     0.01))
			pts.append(iso(ox,     oy - r * 0.5, 0.01))
			pts.append(iso(ox + r, oy,     0.01))
			pts.append(iso(ox,     oy + r * 0.5, 0.01))
			draw_colored_polygon(pts, Color(0.6, 0.9, 1.0, 0.3 * pulse))
			draw_polyline(pts, Color(0.5, 0.85, 1.0, 0.7 * pulse), 1.0, true)


func _draw_cafe_objects(pal: RefCounted) -> void:
	# Counter / bar along right side
	draw_iso_box(7.5, 1.0, 2.0, 5.5, 0.0, 1.0,
			pal.furniture_top, pal.furniture_front, pal.furniture_right)
	# Counter top edge highlight
	iso_line(7.5, 1.0, 1.0, 9.5, 1.0, 1.0, pal.furniture_top.lightened(0.2), 1.5)
	iso_line(7.5, 6.5, 1.0, 9.5, 6.5, 1.0, pal.furniture_top.lightened(0.2), 1.5)

	# Espresso machine on counter
	draw_iso_box(8.2, 1.3, 0.8, 0.7, 1.0, 2.1,
			Color(0.3, 0.28, 0.22, 1.0), Color(0.22, 0.20, 0.16, 1.0), Color(0.18, 0.16, 0.12, 1.0))
	# Machine display glow
	var mpos := iso(8.6, 1.3, 1.8)
	draw_rect(Rect2(mpos.x - 8, mpos.y - 5, 16, 10), Color(0.0, 0.4, 0.6, 0.7))
	for g in 3:
		draw_rect(Rect2(mpos.x - 8 - g, mpos.y - 5 - g, 16 + g*2, 10 + g*2),
				Color(0.0, 0.4, 0.6, 0.15 - g * 0.04))

	# Tip jar on counter
	_draw_cylinder_iso(8.0, 5.8, 1.0, 0.25, 0.4, Color(0.35, 0.45, 0.30, 0.7))

	# Table 1 (left side, middle)
	draw_iso_box(1.5, 3.5, 1.8, 1.2, 0.0, 0.85,
			pal.furniture_top, pal.furniture_front, pal.furniture_right)
	# Chairs around table 1
	_draw_chair_iso(1.2, 5.0, pal)
	_draw_chair_iso(2.5, 5.0, pal)
	_draw_chair_iso(1.2, 3.2, pal)
	# Cup on table 1
	_draw_cylinder_iso(2.2, 4.0, 0.85, 0.15, 0.25, Color(0.6, 0.55, 0.4, 0.9))

	# Table 2 (center front)
	draw_iso_box(4.0, 4.5, 1.8, 1.2, 0.0, 0.85,
			pal.furniture_top, pal.furniture_front, pal.furniture_right)
	_draw_chair_iso(3.8, 5.9, pal)
	_draw_chair_iso(5.1, 5.9, pal)
	# Newspaper on table 2
	draw_iso_box(4.5, 5.0, 0.7, 0.4, 0.85, 0.92, Color(0.55, 0.52, 0.44, 1.0),
			Color(0.45, 0.42, 0.36, 1.0), Color(0.40, 0.38, 0.32, 1.0))

	# Payphone on left wall
	draw_iso_box(0.0, 2.5, 0.5, 0.8, 0.0, 2.2,
			Color(0.20, 0.18, 0.14, 1.0), Color(0.15, 0.13, 0.10, 1.0), Color(0.10, 0.09, 0.07, 1.0))
	# Payphone screen glow
	var ph := iso(0.0, 2.9, 1.4)
	draw_rect(Rect2(ph.x, ph.y - 8, 18, 14), Color(0.0, 0.15, 0.0, 0.8))

	# Floor ashtray
	draw_iso_box(3.2, 4.8, 0.3, 0.3, 0.0, 0.12,
			Color(0.20, 0.18, 0.18, 1.0), Color(0.15, 0.13, 0.13, 1.0), Color(0.12, 0.10, 0.10, 1.0))

	# CCTV camera on back-right corner (screen space)
	var cam_pos := iso(8.5, 0.8, 3.8)
	draw_circle(cam_pos, 7.0, Color(0.12, 0.10, 0.10, 1.0))
	draw_circle(cam_pos, 3.5, Color(0.05, 0.04, 0.04, 1.0))
	var blink_a := 0.5 + 0.5 * sin(_time * 2.2)
	draw_circle(cam_pos + Vector2(5, -3), 2.5, Color(0.9, 0.1, 0.1, blink_a))

	# Ambient: steam wisps from coffee cups
	for i in 3:
		var sx := 2.2 + float(i) * 0.08; var sy := 4.0
		var sp := iso(sx, sy, 0.85 + float(i) * 0.3 + sin(_time * 1.5 + i) * 0.1)
		draw_circle(sp, 3.0 - float(i) * 0.5,
				Color(0.7, 0.7, 0.8, 0.07 - float(i) * 0.02))


func _draw_bar_objects(pal: RefCounted) -> void:
	# Long bar counter across back-right
	draw_iso_box(4.5, 0.5, 5.0, 2.5, 0.0, 1.1,
			pal.furniture_top, pal.furniture_front, pal.furniture_right)
	# Bar top brass rail
	iso_line(4.5, 3.0, 1.1, 9.5, 3.0, 1.1, Color(0.55, 0.45, 0.15, 1.0), 2.0)
	iso_line(4.5, 0.5, 1.1, 9.5, 0.5, 1.1, Color(0.55, 0.45, 0.15, 1.0), 1.5)

	# Bottles on shelf (back wall, varied heights and colors)
	var bottles := [
		[5.2, Color(0.25, 0.06, 0.04, 0.85)],
		[5.7, Color(0.08, 0.22, 0.08, 0.85)],
		[6.2, Color(0.30, 0.25, 0.05, 0.80)],
		[6.7, Color(0.18, 0.05, 0.05, 0.90)],
		[7.2, Color(0.05, 0.10, 0.28, 0.85)],
		[7.7, Color(0.22, 0.18, 0.04, 0.85)],
		[8.2, Color(0.08, 0.06, 0.22, 0.90)],
		[8.7, Color(0.28, 0.05, 0.08, 0.85)],
	]
	for b in bottles:
		var bx: float = b[0]; var bc: Color = b[1]
		_draw_bottle_iso(bx, 0.8, 2.2, bc)   # shelf at gz=2.2

	# Shelf backing board
	draw_iso_box(5.0, 0.0, 4.0, 0.15, 2.0, 2.3,
			pal.furniture_top.darkened(0.3), pal.furniture_front.darkened(0.3),
			pal.furniture_right.darkened(0.3))

	# Bar stools
	for i in 4:
		var sx := 5.0 + float(i) * 1.1
		_draw_barstool_iso(sx, 3.2, pal)

	# Jukebox (left corner)
	draw_iso_box(0.5, 1.0, 1.5, 1.5, 0.0, 2.5,
			Color(0.20, 0.10, 0.06, 1.0), Color(0.15, 0.08, 0.04, 1.0),
			Color(0.10, 0.06, 0.03, 1.0))
	# Jukebox chrome
	var jpos := iso(1.25, 1.0, 2.0)
	for g in 4:
		draw_rect(Rect2(jpos.x - 18 - g, jpos.y - g, 36 + g*2, 24 + g*2),
				Color(0.55, 0.30, 0.10, 0.12 - g * 0.025))
	draw_rect(Rect2(jpos.x - 18, jpos.y, 36, 24), Color(0.08, 0.05, 0.03, 0.9))
	# Color wheel lights
	for ci in 6:
		var ca := TAU * float(ci) / 6.0
		var cp := jpos + Vector2(cos(ca) * 12.0, sin(ca) * 6.0)
		var cc := Color.from_hsv(fmod(float(ci) / 6.0 + _time * 0.08, 1.0), 0.9, 0.8, 0.7)
		draw_circle(cp, 3.0, cc)

	# Bar table (center left)
	draw_iso_box(1.5, 4.0, 2.0, 1.5, 0.0, 0.9,
			pal.furniture_top, pal.furniture_front, pal.furniture_right)
	_draw_chair_iso(1.3, 5.7, pal)
	_draw_chair_iso(2.8, 5.7, pal)

	# Napkin on bar table
	draw_iso_box(2.0, 4.5, 0.5, 0.3, 0.9, 0.96,
			Color(0.50, 0.50, 0.46, 0.9), Color(0.40, 0.40, 0.36, 0.9), Color(0.35, 0.35, 0.32, 0.9))

	# TV screen on back wall
	var tv_p := iso(8.2, 0.0, 3.0)
	var tv_w := iso(9.2, 0.0, 3.0).x - tv_p.x
	var tv_h := iso(8.2, 0.0, 3.0).y - iso(8.2, 0.0, 4.2).y
	draw_rect(Rect2(tv_p.x, tv_p.y - tv_h, tv_w, tv_h), Color(0.05, 0.04, 0.08, 1.0))
	# TV static / news
	for ti in 8:
		var ty := tv_p.y - tv_h + float(ti) * (tv_h / 8.0)
		var noise_a := randf_range(0.03, 0.12) if fmod(_time * 4.0, 1.0) > 0.85 else 0.0
		draw_rect(Rect2(tv_p.x, ty, tv_w, tv_h / 8.0 - 1.0),
				Color(0.5, 0.5, 0.6, noise_a))
	draw_rect(Rect2(tv_p.x, tv_p.y - tv_h, tv_w, tv_h * 0.12),
			Color(0.06, 0.06, 0.12, 0.9))  # news ticker bar
	draw_string(ThemeDB.fallback_font, Vector2(tv_p.x + 2, tv_p.y - tv_h + 9),
			"...HORIZON EXPANDS...", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.9, 0.5, 0.8))

	# Back door (right wall)
	draw_iso_box(9.5, 0.3, 0.5, 1.5, 0.0, 2.0,
			Color(0.08, 0.06, 0.04, 1.0), Color(0.06, 0.04, 0.03, 1.0), Color(0.05, 0.04, 0.03, 1.0))


func _draw_apartment_objects(pal: RefCounted) -> void:
	# Main desk (large, back right)
	draw_iso_box(6.0, 1.0, 3.5, 2.0, 0.0, 0.9,
			pal.furniture_top, pal.furniture_front, pal.furniture_right)

	# Monitor 1 (main)
	draw_iso_box(6.8, 1.2, 1.2, 0.5, 0.9, 2.2,
			Color(0.06, 0.06, 0.10, 1.0), Color(0.05, 0.05, 0.08, 1.0), Color(0.04, 0.04, 0.07, 1.0))
	# Monitor screen glow
	var ms1 := iso(7.4, 1.2, 1.9)
	var screen_c := Color(0.05, 0.45, 0.15, 1.0)
	var sw := iso(8.0, 1.2, 1.9).x - ms1.x
	var sh := ms1.y - iso(7.4, 1.2, 2.2).y
	draw_rect(Rect2(ms1.x, ms1.y - sh, sw, sh), screen_c)
	# Terminal text lines
	for li in 6:
		var line_y := ms1.y - sh + 4 + li * 10
		var line_w := randf_range(0.3, 0.85) * sw
		draw_rect(Rect2(ms1.x + 3, line_y, line_w, 6), Color(0.2, 0.9, 0.3, 0.6))
	for g in 5:
		draw_rect(Rect2(ms1.x - g, ms1.y - sh - g, sw + g*2, sh + g*2),
				Color(0.05, 0.45, 0.15, 0.08 - g * 0.014))

	# Monitor 2 (side)
	draw_iso_box(8.2, 1.0, 1.0, 0.5, 0.9, 2.0,
			Color(0.06, 0.06, 0.10, 1.0), Color(0.05, 0.05, 0.08, 1.0), Color(0.04, 0.04, 0.07, 1.0))
	var ms2 := iso(8.7, 1.0, 1.85)
	var sw2 := iso(9.2, 1.0, 1.85).x - ms2.x
	var sh2 := ms2.y - iso(8.7, 1.0, 2.0).y
	draw_rect(Rect2(ms2.x, ms2.y - sh2, sw2, sh2), Color(0.04, 0.12, 0.35, 1.0))
	for li in 4:
		draw_rect(Rect2(ms2.x + 2, ms2.y - sh2 + 3 + li * 8, randf_range(0.2, 0.6) * sw2, 5),
				Color(0.3, 0.5, 0.9, 0.5))

	# Keyboard
	draw_iso_box(6.8, 2.6, 1.5, 0.6, 0.9, 1.0,
			Color(0.12, 0.11, 0.15, 1.0), Color(0.09, 0.08, 0.12, 1.0), Color(0.08, 0.07, 0.10, 1.0))

	# Whiteboard on left wall
	draw_iso_box(0.0, 0.8, 0.1, 2.8, 1.2, 3.2,
			Color(0.20, 0.22, 0.20, 1.0), Color(0.16, 0.18, 0.16, 1.0), Color(0.14, 0.15, 0.14, 1.0))
	# Whiteboard content (screen space)
	var wbp := iso(0.0, 1.8, 2.8)
	draw_string(ThemeDB.fallback_font, wbp, "INTAKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.35, 0.80, 0.40, 0.7))
	draw_string(ThemeDB.fallback_font, wbp + Vector2(0, 14), "-> HASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.35, 0.80, 0.40, 0.5))
	draw_string(ThemeDB.fallback_font, wbp + Vector2(0, 28), "-> VEIL_DB", HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(0.90, 0.25, 0.25, 0.7))

	# Filing cabinet (left mid)
	draw_iso_box(0.5, 2.5, 1.2, 1.0, 0.0, 1.8,
			pal.furniture_top.lightened(0.05), pal.furniture_front, pal.furniture_right)
	# Drawer lines
	for di in 3:
		var dgz := 0.4 + float(di) * 0.45
		iso_line(0.5, 3.5, dgz, 1.7, 3.5, dgz, pal.furniture_top.lightened(0.2), 0.8)

	# Stack of printouts on floor
	draw_iso_box(4.0, 4.8, 1.0, 0.8, 0.0, 0.15,
			Color(0.50, 0.50, 0.46, 1.0), Color(0.40, 0.40, 0.36, 1.0), Color(0.35, 0.35, 0.32, 1.0))
	for pi in 4:
		iso_line(4.0, 4.8, 0.15 + float(pi) * 0.04, 5.0, 4.8, 0.15 + float(pi) * 0.04,
				Color(0.55, 0.55, 0.50, 0.5), 0.5)

	# Burner phone on small table
	draw_iso_box(2.0, 4.0, 1.0, 0.8, 0.0, 0.8,
			pal.furniture_top, pal.furniture_front, pal.furniture_right)
	draw_iso_box(2.2, 4.2, 0.6, 0.4, 0.8, 0.96,
			Color(0.08, 0.08, 0.10, 1.0), Color(0.06, 0.06, 0.08, 1.0), Color(0.05, 0.05, 0.07, 1.0))
	# Phone screen (off)
	var ph := iso(2.5, 4.2, 0.93)
	draw_rect(Rect2(ph.x - 5, ph.y - 3, 10, 6), Color(0.02, 0.02, 0.03, 1.0))

	# Rope ladder near window (coiled)
	for ri in 3:
		var rpts := PackedVector2Array()
		var rcx := 9.3; var rcy := 1.2 + float(ri) * 0.25
		for ri2 in 8:
			var ra := TAU * float(ri2) / 8.0
			rpts.append(iso(rcx + cos(ra) * 0.18, rcy + sin(ra) * 0.09, 0.02))
		draw_polyline(rpts, Color(0.35, 0.28, 0.15, 0.7), 1.5, true)

	# Chair at desk
	_draw_chair_iso(7.2, 3.2, _palette("apartment"))


# ── Character drawing helpers ─────────────────────────────────────────────────

func _draw_cylinder_iso(gx: float, gy: float, gz: float,
		rx: float, h: float, col: Color) -> void:
	# Top ellipse
	var top_pts := PackedVector2Array()
	var bot_pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		top_pts.append(iso(gx + cos(a) * rx, gy + sin(a) * rx * 0.5, gz + h))
		bot_pts.append(iso(gx + cos(a) * rx, gy + sin(a) * rx * 0.5, gz))
	draw_colored_polygon(top_pts, col)
	# Side (simple quad front half)
	var side := PackedVector2Array()
	side.append(iso(gx - rx, gy, gz))
	side.append(iso(gx - rx, gy, gz + h))
	side.append(iso(gx + rx, gy, gz + h))
	side.append(iso(gx + rx, gy, gz))
	draw_colored_polygon(side, col.darkened(0.3))


func _draw_chair_iso(gx: float, gy: float, pal: RefCounted) -> void:
	# Seat
	draw_iso_box(gx, gy, 0.7, 0.7, 0.0, 0.45,
			pal.furniture_top.lightened(0.1), pal.furniture_front, pal.furniture_right)
	# Back rest
	draw_iso_box(gx, gy, 0.7, 0.12, 0.45, 1.1,
			pal.furniture_top, pal.furniture_front.darkened(0.1), pal.furniture_right.darkened(0.1))
	# Legs
	for li in [[0.1, 0.1], [0.5, 0.1], [0.1, 0.5], [0.5, 0.5]]:
		iso_line(gx + li[0], gy + li[1], 0.0, gx + li[0], gy + li[1], -0.4,
				pal.furniture_right.darkened(0.2), 1.0)


func _draw_barstool_iso(gx: float, gy: float, pal: RefCounted) -> void:
	# Round seat
	_draw_cylinder_iso(gx + 0.35, gy + 0.35, 0.9, 0.3, 0.12, pal.furniture_top)
	# Pole
	iso_line(gx + 0.35, gy + 0.35, 0.0, gx + 0.35, gy + 0.35, 0.9,
			pal.furniture_right.darkened(0.2), 2.5)
	# Foot ring
	for i in 6:
		var a := TAU * float(i) / 6.0
		var a2 := TAU * float(i + 1) / 6.0
		iso_line(gx + 0.35 + cos(a) * 0.22, gy + 0.35 + sin(a) * 0.11, 0.4,
				gx + 0.35 + cos(a2) * 0.22, gy + 0.35 + sin(a2) * 0.11, 0.4,
				pal.furniture_right.darkened(0.15), 1.0)


func _draw_bottle_iso(gx: float, gy: float, gz: float, col: Color) -> void:
	_draw_cylinder_iso(gx, gy, gz, 0.12, 0.55, col)
	# Neck
	_draw_cylinder_iso(gx, gy, gz + 0.55, 0.06, 0.20, col.lightened(0.1))
	# Label
	var lpos := iso(gx, gy, gz + 0.25)
	draw_rect(Rect2(lpos.x - 5, lpos.y - 4, 10, 8), Color(0.85, 0.82, 0.70, 0.6))


# ── NPC ───────────────────────────────────────────────────────────────────────

func _draw_npc() -> void:
	if _loc.is_empty(): return
	var npc_hex := _str(_loc.get("npc_color"))
	if npc_hex == "": npc_hex = "#7b68ee"
	var npc_col := Color.html(npc_hex)

	var pos := iso(_npc_gx, _npc_gy, 0.0)
	var bob: float = sin(_npc_walk_t) * 1.8
	_npc_walk_t += get_process_delta_time() * 1.0

	# Shadow
	_draw_ellipse_iso(_npc_gx, _npc_gy, 0.005, 0.28, 0.12, Color(0, 0, 0, 0.5))

	_draw_detailed_character(pos, npc_col, bob, 1, false)


# ── Player ────────────────────────────────────────────────────────────────────

func _draw_player() -> void:
	var pos := iso(_player_gx, _player_gy, 0.0)
	var bob: float = sin(_player_walk_t) * 2.2 if _player_moving else 0.0
	_draw_ellipse_iso(_player_gx, _player_gy, 0.005, 0.25, 0.10, Color(0, 0, 0, 0.55))
	_draw_detailed_character(pos, Color(0.35, 0.35, 0.48, 1.0), bob, _player_dir, true)

	# Player position marker (small green triangle above head)
	var head := pos - Vector2(0, 68)
	var pulse := 0.7 + 0.3 * sin(_time * 2.5)
	draw_circle(head - Vector2(0, 8), 3.0, Color(0.3, 1.0, 0.4, pulse))


func _draw_detailed_character(pos: Vector2, accent: Color,
		bob: float, dir: int, is_player: bool) -> void:
	var flip := float(dir)
	var body  := Color(0.09, 0.09, 0.14, 1.0)
	var cloth := accent.darkened(0.55)
	var skin  := Color(0.55, 0.42, 0.32, 1.0) if is_player else Color(accent.r * 0.7, accent.g * 0.6, accent.b * 0.5, 1.0)

	# ── Shoes ──
	draw_rect(Rect2(pos.x - 7.0 * flip, pos.y - 5.0, 9.0, 5.0), body)
	draw_rect(Rect2(pos.x + 1.0 * flip, pos.y - 4.0, 8.0, 4.0), body)

	# ── Legs ──
	var step1: float = sin(_player_walk_t if is_player else _npc_walk_t) * 5.0 if _player_moving else 0.0
	var step2 := -step1
	# Left leg
	var ll_col := cloth.lightened(0.1)
	draw_rect(Rect2(pos.x - 8.0 * flip, pos.y - 24.0 + bob + step1, 7.0, 20.0), ll_col)
	# Right leg
	draw_rect(Rect2(pos.x + 2.0 * flip, pos.y - 23.0 + bob + step2, 7.0, 19.0), cloth)
	# Knee highlight
	draw_rect(Rect2(pos.x - 6.0 * flip, pos.y - 14.0 + bob + step1, 4.0, 3.0),
			ll_col.lightened(0.15))

	# ── Belt ──
	draw_rect(Rect2(pos.x - 10.0, pos.y - 26.0 + bob, 20.0, 3.0), body.lightened(0.1))

	# ── Jacket / torso ──
	draw_rect(Rect2(pos.x - 10.0, pos.y - 50.0 + bob, 20.0, 26.0), cloth)
	# Jacket lapels
	var lpx := pos.x - 10.0 * flip
	var lpts := PackedVector2Array()
	lpts.append(Vector2(lpx, pos.y - 50.0 + bob))
	lpts.append(Vector2(lpx + 5.0 * flip, pos.y - 50.0 + bob))
	lpts.append(Vector2(pos.x, pos.y - 38.0 + bob))
	draw_colored_polygon(lpts, cloth.darkened(0.2))
	# Collar
	draw_rect(Rect2(pos.x - 4.0, pos.y - 50.0 + bob, 8.0, 5.0), cloth.lightened(0.08))

	# ── Arms ──
	var arm_swing: float = sin(_player_walk_t if is_player else _npc_walk_t) * 7.0 if _player_moving else 0.0
	# Left arm
	draw_rect(Rect2(pos.x - 16.0 * flip, pos.y - 47.0 + bob + arm_swing * flip, 6.0, 18.0), cloth)
	# Right arm
	draw_rect(Rect2(pos.x + 10.0 * flip, pos.y - 47.0 + bob - arm_swing * flip, 6.0, 18.0), cloth)
	# Hands
	draw_circle(pos - Vector2(13.0 * flip, 30.0 - bob - arm_swing * flip), 4.0, skin)
	draw_circle(pos + Vector2(13.0 * flip, -30.0 + bob - arm_swing * flip), 4.0, skin)

	# ── Neck ──
	draw_rect(Rect2(pos.x - 3.0, pos.y - 55.0 + bob, 6.0, 6.0), skin)

	# ── Head ──
	draw_circle(pos - Vector2(0.0, 63.0 - bob), 10.0, skin)
	# Hair
	draw_rect(Rect2(pos.x - 10.0, pos.y - 76.0 + bob, 20.0, 8.0), body)
	draw_rect(Rect2(pos.x - 10.0, pos.y - 73.0 + bob, 20.0, 5.0), body.lightened(0.08))
	# Eyes
	var eye_y := pos.y - 64.0 + bob
	draw_rect(Rect2(pos.x + 2.0 * flip, eye_y, 4.0, 3.0), Color(0.06, 0.06, 0.10, 1.0))
	draw_rect(Rect2(pos.x - 6.0 * flip, eye_y, 4.0, 3.0), Color(0.15, 0.15, 0.22, 1.0))

	# ── Accent item (bag / accessory) ──
	if is_player:
		# Laptop bag strap
		draw_rect(Rect2(pos.x - 13.0 * flip, pos.y - 48.0 + bob, 4.0, 20.0),
				Color(0.18, 0.16, 0.12, 1.0))
		# Bag body
		draw_rect(Rect2(pos.x - 17.0 * flip, pos.y - 34.0 + bob, 14.0, 16.0),
				Color(0.14, 0.12, 0.10, 1.0))
	else:
		# NPC has a jacket pocket square
		draw_rect(Rect2(pos.x - 8.0 * flip, pos.y - 45.0 + bob, 5.0, 4.0),
				accent.lightened(0.4))


# ── Ambient particles ─────────────────────────────────────────────────────────

func _draw_particles() -> void:
	for p in _particles:
		var ppos := iso(p["gx"], p["gy"], p["gz"])
		draw_circle(ppos, p["r"], Color(1.0, 1.0, 1.0, p["alpha"]))


# ── Tilt shift ────────────────────────────────────────────────────────────────

func _draw_tilt_shift() -> void:
	draw_rect(Rect2(0, 0, _size.x, _size.y * 0.06), Color(0, 0, 0, 0.70))
	draw_rect(Rect2(0, _size.y * 0.91, _size.x, _size.y * 0.09), Color(0, 0, 0, 0.60))
	draw_rect(Rect2(0, 0, _size.x * 0.04, _size.y), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(_size.x * 0.96, 0, _size.x * 0.04, _size.y), Color(0, 0, 0, 0.35))


# ── Palette ───────────────────────────────────────────────────────────────────

func _palette(itype: String) -> RefCounted:
	var p := RefCounted.new()
	match itype:
		"cafe":
			p.set_meta("floor_a",        Color(0.14, 0.11, 0.08, 1.0))
			p.set_meta("floor_b",        Color(0.11, 0.09, 0.06, 1.0))
			p.set_meta("grout",          Color(0.08, 0.06, 0.04, 0.6))
			p.set_meta("wall_back",      Color(0.09, 0.07, 0.05, 1.0))
			p.set_meta("wall_left",      Color(0.07, 0.06, 0.04, 1.0))
			p.set_meta("ceiling",        Color(0.06, 0.05, 0.04, 1.0))
			p.set_meta("trim",           Color(0.22, 0.16, 0.10, 1.0))
			p.set_meta("furniture_top",  Color(0.20, 0.15, 0.09, 1.0))
			p.set_meta("furniture_front",Color(0.15, 0.11, 0.07, 1.0))
			p.set_meta("furniture_right",Color(0.12, 0.09, 0.05, 1.0))
			p.set_meta("light_color",    Color(0.90, 0.72, 0.40, 1.0))
			p.set_meta("light_shade",    Color(0.25, 0.18, 0.10, 1.0))
		"bar":
			p.set_meta("floor_a",        Color(0.10, 0.07, 0.06, 1.0))
			p.set_meta("floor_b",        Color(0.08, 0.05, 0.04, 1.0))
			p.set_meta("grout",          Color(0.05, 0.03, 0.03, 0.6))
			p.set_meta("wall_back",      Color(0.08, 0.05, 0.04, 1.0))
			p.set_meta("wall_left",      Color(0.06, 0.04, 0.03, 1.0))
			p.set_meta("ceiling",        Color(0.05, 0.03, 0.03, 1.0))
			p.set_meta("trim",           Color(0.30, 0.12, 0.08, 1.0))
			p.set_meta("furniture_top",  Color(0.18, 0.10, 0.06, 1.0))
			p.set_meta("furniture_front",Color(0.13, 0.07, 0.04, 1.0))
			p.set_meta("furniture_right",Color(0.10, 0.05, 0.03, 1.0))
			p.set_meta("light_color",    Color(0.85, 0.30, 0.15, 1.0))
			p.set_meta("light_shade",    Color(0.20, 0.08, 0.05, 1.0))
		"apartment":
			p.set_meta("floor_a",        Color(0.08, 0.10, 0.08, 1.0))
			p.set_meta("floor_b",        Color(0.06, 0.08, 0.06, 1.0))
			p.set_meta("grout",          Color(0.04, 0.05, 0.04, 0.6))
			p.set_meta("wall_back",      Color(0.07, 0.08, 0.07, 1.0))
			p.set_meta("wall_left",      Color(0.05, 0.07, 0.05, 1.0))
			p.set_meta("ceiling",        Color(0.04, 0.05, 0.04, 1.0))
			p.set_meta("trim",           Color(0.12, 0.18, 0.12, 1.0))
			p.set_meta("furniture_top",  Color(0.12, 0.14, 0.10, 1.0))
			p.set_meta("furniture_front",Color(0.09, 0.11, 0.08, 1.0))
			p.set_meta("furniture_right",Color(0.07, 0.09, 0.06, 1.0))
			p.set_meta("light_color",    Color(0.25, 0.90, 0.40, 1.0))
			p.set_meta("light_shade",    Color(0.08, 0.18, 0.08, 1.0))
		_:
			p.set_meta("floor_a",        Color(0.10, 0.10, 0.13, 1.0))
			p.set_meta("floor_b",        Color(0.08, 0.08, 0.11, 1.0))
			p.set_meta("grout",          Color(0.06, 0.06, 0.08, 0.6))
			p.set_meta("wall_back",      Color(0.07, 0.07, 0.10, 1.0))
			p.set_meta("wall_left",      Color(0.05, 0.05, 0.08, 1.0))
			p.set_meta("ceiling",        Color(0.04, 0.04, 0.06, 1.0))
			p.set_meta("trim",           Color(0.15, 0.15, 0.25, 1.0))
			p.set_meta("furniture_top",  Color(0.15, 0.15, 0.20, 1.0))
			p.set_meta("furniture_front",Color(0.11, 0.11, 0.16, 1.0))
			p.set_meta("furniture_right",Color(0.09, 0.09, 0.13, 1.0))
			p.set_meta("light_color",    Color(0.70, 0.70, 0.90, 1.0))
			p.set_meta("light_shade",    Color(0.15, 0.15, 0.22, 1.0))

	# Proxy property access via inner class trick — use a small wrapper
	return _PaletteWrapper.new(p)


class _PaletteWrapper extends RefCounted:
	var _data: RefCounted
	func _init(d: RefCounted) -> void: _data = d
	func _get(prop: StringName) -> Variant: return _data.get_meta(prop)


# ── Dialogue ──────────────────────────────────────────────────────────────────

func _start_dialogue() -> void:
	if _dialogue_active: return
	_dialogue_active = true
	_prompt_label.modulate.a = 0.0

	var npc_id: String = _str(_loc.get("npc_id"))
	var npc_color_hex: String = _str(_loc.get("npc_color"))
	if npc_color_hex == "": npc_color_hex = "#7b68ee"

	var dialogue_script: Script = load(DIALOGUE_SCRIPT)
	var dialogue: Control = Control.new()
	dialogue.set_script(dialogue_script)
	add_child(dialogue)
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue.dialogue_finished.connect(_on_dialogue_finished)
	dialogue.start(npc_id, npc_color_hex)


func _on_dialogue_finished() -> void:
	_dialogue_active = false
	for child in get_children():
		if child.has_signal("dialogue_finished"):
			child.queue_free()
			break
