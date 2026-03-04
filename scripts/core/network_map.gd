extends Control

# Corporate Theater — Network Map
# Visual node graph of the hacking network.
# Node states driven by GameState discovered_clues.

const NODE_DEFS: Array = [
	{
		"id": "localhost",
		"label": "LOCALHOST",
		"sublabel": "ghost operative terminal",
		"requires_clue": "",
		"color": Color(0.2, 1.0, 0.4, 1),
		"pos_frac": Vector2(0.15, 0.5)
	},
	{
		"id": "closedai-pub.net",
		"label": "CLOSEDAI-PUB",
		"sublabel": "closedai-pub.net",
		"requires_clue": "",
		"color": Color(0.4, 0.7, 1.0, 1),
		"pos_frac": Vector2(0.42, 0.28)
	},
	{
		"id": "closedai-internal.net",
		"label": "CLOSEDAI-INT",
		"sublabel": "closedai-internal.net",
		"requires_clue": "clue_api_endpoint",
		"color": Color(1.0, 0.45, 0.2, 1),
		"pos_frac": Vector2(0.68, 0.28)
	},
	{
		"id": "clearsky-relay.gov",
		"label": "CLEARSKY-RELAY",
		"sublabel": "clearsky-relay.gov",
		"requires_clue": "clue_clearsky_partnership",
		"color": Color(0.9, 0.3, 0.3, 1),
		"pos_frac": Vector2(0.55, 0.72)
	}
]

const EDGES: Array = [
	["localhost", "closedai-pub.net"],
	["localhost", "clearsky-relay.gov"],
	["closedai-pub.net", "closedai-internal.net"],
	["closedai-internal.net", "clearsky-relay.gov"]
]

@onready var info_panel: PanelContainer = $GraphArea/InfoPanel
@onready var info_title: Label = $GraphArea/InfoPanel/VBox/Title
@onready var info_sub: Label = $GraphArea/InfoPanel/VBox/Sub
@onready var info_status: Label = $GraphArea/InfoPanel/VBox/Status
@onready var info_close: Button = $GraphArea/InfoPanel/VBox/CloseBtn
@onready var graph_area: Control = $GraphArea

var _node_positions: Dictionary = {}  # id -> Vector2 (absolute px)
var _selected_node: String = ""
var _node_click_regions: Array = []  # [{id, rect}]


func _ready() -> void:
	info_panel.visible = false
	info_close.pressed.connect(func(): info_panel.visible = false)
	GameState.clue_added.connect(func(_clue): _rebuild())
	graph_area.draw.connect(_on_graph_area_draw)
	graph_area.gui_input.connect(_on_graph_area_gui_input)
	graph_area.resized.connect(_rebuild)
	await get_tree().process_frame
	_rebuild()


func _rebuild() -> void:
	_compute_positions()
	_build_click_regions()
	graph_area.queue_redraw()


func _compute_positions() -> void:
	var sz := graph_area.size
	for nd in NODE_DEFS:
		var frac: Vector2 = nd["pos_frac"]
		_node_positions[nd["id"]] = Vector2(sz.x * frac.x, sz.y * frac.y)


func _build_click_regions() -> void:
	_node_click_regions.clear()
	for nd in NODE_DEFS:
		var pos: Vector2 = _node_positions.get(nd["id"], Vector2.ZERO)
		var accessible := _is_accessible(nd)
		var w := 140.0 if accessible else 120.0
		var h := 44.0
		_node_click_regions.append({
			"id": nd["id"],
			"rect": Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h)
		})


func _is_accessible(nd: Dictionary) -> bool:
	var req: String = nd.get("requires_clue", "")
	return req == "" or req in GameState.discovered_clues


func _is_visited(nd: Dictionary) -> bool:
	# "visited" = the node was connected to in the terminal (we track by clues found there)
	# Use discovered clues from that node as a proxy
	match nd["id"]:
		"localhost":
			return true
		"closedai-pub.net":
			return "clue_api_endpoint" in GameState.discovered_clues or \
				   "clue_internal_safety_suppression" in GameState.discovered_clues or \
				   "clue_horizon_contract_confirmed" in GameState.discovered_clues
		"closedai-internal.net":
			return "clue_veil_model" in GameState.discovered_clues or \
				   "clue_market_capture_evidence" in GameState.discovered_clues
		"clearsky-relay.gov":
			return "clue_soft_stabilization" in GameState.discovered_clues
	return false


# ── Draw ──────────────────────────────────────────────────────────────────────

func _on_graph_area_draw() -> void:
	_compute_positions()
	_build_click_regions()

	var font := ThemeDB.fallback_font
	var font_size_main := 11
	var font_size_sub := 9

	# Draw edges first
	for edge in EDGES:
		var a: Vector2 = _node_positions.get(edge[0], Vector2.ZERO)
		var b: Vector2 = _node_positions.get(edge[1], Vector2.ZERO)
		var nd_a := _get_node_def(edge[0])
		var nd_b := _get_node_def(edge[1])
		var both_accessible := _is_accessible(nd_a) and _is_accessible(nd_b)
		var col := Color(0.2, 0.6, 0.35, 0.5) if both_accessible else Color(0.18, 0.18, 0.28, 0.3)
		graph_area.draw_line(a, b, col, 1.5)
		var mid := (a + b) * 0.5
		graph_area.draw_circle(mid, 2.5, col)

	# Draw nodes
	for nd in NODE_DEFS:
		var pos: Vector2 = _node_positions.get(nd["id"], Vector2.ZERO)
		var accessible := _is_accessible(nd)
		var visited := _is_visited(nd)
		var col: Color = nd["color"] if accessible else Color(0.3, 0.3, 0.38, 1)

		var w := 148.0
		var h := 48.0
		var rect := Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h)

		# Background
		var bg := Color(0.07, 0.09, 0.14, 1) if accessible else Color(0.04, 0.04, 0.07, 1)
		if nd["id"] == _selected_node:
			bg = Color(0.10, 0.14, 0.22, 1)
		graph_area.draw_rect(rect, bg)

		# Border
		var border_alpha := 0.75 if accessible else 0.3
		if nd["id"] == _selected_node:
			border_alpha = 1.0
		graph_area.draw_rect(rect, col * Color(1, 1, 1, border_alpha), false, 1.5)

		# Visited dot in top-left corner
		if visited:
			graph_area.draw_circle(Vector2(rect.position.x + 9, rect.position.y + 9), 3.5, col)

		# Main label centered
		var label_text: String = nd["label"]
		var label_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_main).x
		var label_x := pos.x - label_w * 0.5
		var label_y := pos.y - 3.0
		graph_area.draw_string(font, Vector2(label_x, label_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_main, col)

		# Sublabel (hostname) smaller, below
		var sub_text: String = nd["sublabel"]
		var sub_col := col * Color(1, 1, 1, 0.5)
		var sub_w := font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub).x
		var sub_x := pos.x - sub_w * 0.5
		graph_area.draw_string(font, Vector2(sub_x, pos.y + 13.0), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_sub, sub_col)


func _get_node_def(node_id: String) -> Dictionary:
	for nd in NODE_DEFS:
		if nd["id"] == node_id:
			return nd
	return {}


# ── Input ─────────────────────────────────────────────────────────────────────

func _on_graph_area_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for region in _node_click_regions:
			if region["rect"].has_point(event.position):
				_select_node(region["id"])
				return
		_selected_node = ""
		info_panel.visible = false
		graph_area.queue_redraw()


func _select_node(node_id: String) -> void:
	_selected_node = node_id
	graph_area.queue_redraw()

	var nd := _get_node_def(node_id)
	if nd.is_empty():
		return

	var accessible := _is_accessible(nd)
	var visited := _is_visited(nd)

	info_title.text = nd["label"]
	info_sub.text = nd["sublabel"]

	if not accessible:
		var req: String = nd.get("requires_clue", "")
		var clue_title: String = (GameState.CLUE_DEFINITIONS.get(req, {}) as Dictionary).get("title", req) as String
		info_status.text = "LOCKED\nRequires: %s" % clue_title
		info_status.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 1))
	elif visited:
		info_status.text = "ACCESSED\nFiles retrieved from this node."
		info_status.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4, 1))
	else:
		info_status.text = "REACHABLE\nNot yet accessed. Open terminal to connect."
		info_status.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 1))

	var col: Color = nd["color"] if accessible else Color(0.4, 0.4, 0.5, 1)
	info_title.add_theme_color_override("font_color", col)
	info_panel.visible = true


# ── Legend ────────────────────────────────────────────────────────────────────
# Legend is part of the scene (static labels in the .tscn)
