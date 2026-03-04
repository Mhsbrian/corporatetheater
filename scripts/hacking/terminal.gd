extends Control

# Corporate Theater — Terminal Engine
# Simulates a hacker CLI. Nodes, files, and access gates tied to GameState clues.

@onready var output: RichTextLabel = $VBox/Output
@onready var input: LineEdit = $VBox/InputRow/Input
@onready var prompt_label: Label = $VBox/InputRow/Prompt

const MAX_HISTORY := 50
var _history: Array[String] = []
var _history_index: int = -1
var _current_node: String = "localhost"
var _connected_nodes: Array[String] = ["localhost"]

# Command registry
var _commands: Dictionary = {}

# ── Network Definition ─────────────────────────────────────────────────────────
# Each node: { "desc", "requires_clue" (optional), "files": { name: { "requires_clue", "content", "unlocks_clue" } } }

const NETWORK: Dictionary = {
	"localhost": {
		"desc": "your local machine — ghost operative terminal",
		"files": {
			"notes.txt": {
				"content": "Things I know so far:\n  - ClosedAI signed with Project Clear Sky\n  - Someone inside reached out\n  - Elena says there's a legacy API endpoint\n  Target: closedai-pub.net",
				"unlocks_clue": ""
			},
			"connections.log": {
				"content": "recent connections:\n  [none]",
				"unlocks_clue": ""
			}
		}
	},
	"closedai-pub.net": {
		"desc": "ClosedAI public infrastructure — marketing, PR, API gateway",
		"files": {
			"robots.txt": {
				"content": "User-agent: *\nDisallow: /api/v1/internal/\nDisallow: /api/v1/research/\nDisallow: /horizon/\nDisallow: /.well-known/\n\n# note: legacy endpoints were deprecated Q3 2023\n# note: not all legacy routes were removed from production",
				"unlocks_clue": ""
			},
			"api-changelog.txt": {
				"content": "API CHANGELOG — closedai-pub.net\n\nv2.1 — rate limits applied to /generate endpoints\nv2.0 — client authentication required for batch processing\nv1.9 — 'research/shared' path deprecated (access removed from docs)\n\nnote: v1.x endpoints remain active for legacy partner compatibility",
				"unlocks_clue": ""
			},
			"research_shared_index.json": {
				"requires_clue": "clue_api_endpoint",
				"content": "{\n  \"endpoint\": \"/api/v1/research/shared\",\n  \"status\": \"active (undocumented)\",\n  \"last_modified\": \"2024-08-14\",\n  \"contents\": [\n    \"eval_framework_summary_v3.pdf\",\n    \"safety_eval_gap_analysis_INTERNAL.txt\",\n    \"partner_integration_notes.txt\"\n  ],\n  \"auth_required\": false,\n  \"note\": \"legacy permissions not updated — world-readable\"\n}",
				"unlocks_clue": "clue_api_endpoint"
			},
			"safety_eval_gap_analysis_INTERNAL.txt": {
				"requires_clue": "clue_api_endpoint",
				"content": "SAFETY EVALUATION — INTERNAL GAP ANALYSIS\nClassification: INTERNAL — NOT FOR DISTRIBUTION\nPrepared by: Research Safety Team\nDate: 2024-06-02\n\nSection 3.4 — Persuasion and Behavioral Influence\n\n'Current evaluation suite does not include assessment of\nsubtle behavioral influence or systematic opinion shaping.\nOutputs are evaluated for factual accuracy and direct harm.\nIndirect, longitudinal influence effects are not currently\nwithin scope of evaluation priorities as defined by\nexecutive mandate (see memo: MH-EVL-2024-03-11).'\n\n[ cross-reference with Elena V. report — identical language ]\n[ this is the memo that suppressed her concern ]",
				"unlocks_clue": "clue_internal_safety_suppression"
			},
			"partner_integration_notes.txt": {
				"requires_clue": "clue_api_endpoint",
				"content": "PARTNER INTEGRATION — CONFIDENTIAL\n\nClient ID: client_horizon_gen\nIntegration type: batch generation\nVolume tier: NATIONAL (highest)\nContent type: social-formatted text\nDistribution: third-party platform injection\nReview level: NONE — auto-approved\n\nContact: [REDACTED]\nContract: CAI-GOV-0091-HS\n\n[ this is the same contract Priya found ]",
				"unlocks_clue": "clue_horizon_contract_confirmed"
			}
		}
	},
	"closedai-internal.net": {
		"desc": "ClosedAI internal network — restricted",
		"requires_clue": "clue_api_endpoint",
		"files": {
			"manifest.txt": {
				"requires_clue": "clue_internal_safety_suppression",
				"content": "INTERNAL SYSTEM MANIFEST\nclosedai-internal.net // restricted access\n\nActive projects:\n  - VEIL model serving cluster [horizon subnet only]\n  - Safety eval pipeline [research-only]\n  - Horizon integration bridge [clearsky-relay.gov/bridge]\n  - Market monitoring daemon [CLASSIFIED]\n\nInfrastructure note: Horizon subnet is air-gapped from\npublic systems. Access requires government clearance token.",
				"unlocks_clue": "clue_veil_model"
			},
			"market_monitor_excerpt.log": {
				"requires_clue": "clue_internal_safety_suppression",
				"content": "MARKET MONITORING DAEMON — LOG EXCERPT\n2024-09-14 03:22:11 UTC\n\nTarget: Vertex Mind\nAction: regulatory_flag_escalation\nStatus: COMPLETED — Chapter 11 filing confirmed\n\nTarget: Parallax AI\nAction: key_personnel_departure_facilitated\nStatus: COMPLETED — CEO departure announced\n\nTarget: NeuralForge\nAction: narrative_suppression_activated\nStatus: IN PROGRESS — press coverage declining\n\n[ ref: Market Capture Phase 3 — see internal brief ]",
				"unlocks_clue": "clue_market_capture_evidence"
			}
		}
	},
	"clearsky-relay.gov": {
		"desc": "Project Clear Sky government relay node — classified infrastructure",
		"requires_clue": "clue_clearsky_partnership",
		"files": {
			"readme.txt": {
				"content": "CLEAR SKY RELAY NODE\nAccess restricted to authorized personnel.\n\nThis relay facilitates data exchange between\nProject Clear Sky (GOV) and approved contractors.\n\nUnauthorized access is a federal offense under 18 U.S.C. § 1030.\n\n[ you're already here — too late for warnings ]",
				"unlocks_clue": ""
			},
			"bridge_config.txt": {
				"requires_clue": "clue_clearsky_depth",
				"content": "HORIZON BRIDGE CONFIGURATION\n\nSource: clearsky-relay.gov/bridge\nDestination: closedai-internal.net/horizon\nProtocol: encrypted tunnel, key rotation every 72h\nData types: behavioral profiles, content distribution, target lists\nVolume: ~14M records/day\nClassification: PROGRAM BLACK\n\nAuthorizing authority: [CLASSIFIED]\nCivilian contractor: ClosedAI Inc. (CAI-GOV-0091-HS)\n\n[ 14 million records per day ]\n[ this is already running on the population ]",
				"unlocks_clue": "clue_soft_stabilization"
			}
		}
	}
}

# Nodes that can be connected to from current node (adjacency)
const NODE_ROUTES: Dictionary = {
	"localhost": ["closedai-pub.net", "clearsky-relay.gov"],
	"closedai-pub.net": ["closedai-internal.net", "localhost"],
	"closedai-internal.net": ["closedai-pub.net", "clearsky-relay.gov", "localhost"],
	"clearsky-relay.gov": ["localhost", "closedai-internal.net"]
}


func _ready() -> void:
	_register_commands()
	_print_banner()
	input.grab_focus()
	input.text_submitted.connect(_on_command_submitted)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP:
				_history_navigate(-1)
			KEY_DOWN:
				_history_navigate(1)


# ── Command Registration ──────────────────────────────────────────────────────

func _register_commands() -> void:
	_commands["help"]    = _cmd_help
	_commands["clear"]   = _cmd_clear
	_commands["scan"]    = _cmd_scan
	_commands["connect"] = _cmd_connect
	_commands["whoami"]  = _cmd_whoami
	_commands["ls"]      = _cmd_ls
	_commands["read"]    = _cmd_read
	_commands["cat"]     = _cmd_read   # alias
	_commands["exit"]    = _cmd_exit
	_commands["status"]  = _cmd_status


# ── Input Handling ────────────────────────────────────────────────────────────

func _on_command_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_add_to_history(trimmed)
	_print_line("> " + trimmed, Color(0.2, 1, 0.4, 1))
	_parse_command(trimmed)
	input.clear()
	input.grab_focus()


func _parse_command(raw: String) -> void:
	var parts := raw.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)

	if _commands.has(cmd):
		_commands[cmd].call(args)
	else:
		_print_error("command not found: %s  (type 'help' for commands)" % cmd)


# ── Commands ──────────────────────────────────────────────────────────────────

func _cmd_help(_args: Array) -> void:
	_print_line("available commands:", Color(0.8, 0.8, 0.8, 1))
	_print_line("  help              show this message", Color(0.55, 0.55, 0.55, 1))
	_print_line("  clear             clear output", Color(0.55, 0.55, 0.55, 1))
	_print_line("  whoami            show current identity", Color(0.55, 0.55, 0.55, 1))
	_print_line("  status            show investigation progress", Color(0.55, 0.55, 0.55, 1))
	_print_line("  scan              scan network for reachable nodes", Color(0.55, 0.55, 0.55, 1))
	_print_line("  connect <node>    connect to a network node", Color(0.55, 0.55, 0.55, 1))
	_print_line("  ls                list files on current node", Color(0.55, 0.55, 0.55, 1))
	_print_line("  read <file>       read a file (alias: cat)", Color(0.55, 0.55, 0.55, 1))
	_print_line("  exit              disconnect from current node", Color(0.55, 0.55, 0.55, 1))


func _cmd_clear(_args: Array) -> void:
	output.clear()


func _cmd_whoami(_args: Array) -> void:
	_print_line("ghost@" + _current_node, Color(0.2, 1, 0.4, 1))
	_print_line("  identity: GHOST — unaffiliated operative", Color(0.45, 0.45, 0.55, 1))
	_print_line("  clearance: none (social engineering only)", Color(0.45, 0.45, 0.55, 1))


func _cmd_status(_args: Array) -> void:
	var clues := GameState.discovered_clues
	var contacts := GameState.unlocked_contacts
	_print_line("investigation status:", Color(0.8, 0.8, 0.8, 1))
	_print_line("  clues logged:     %d" % clues.size(), Color(0.2, 0.85, 0.5, 1))
	_print_line("  contacts active:  %d" % contacts.size(), Color(0.2, 0.85, 0.5, 1))
	_print_line("  nodes accessed:   %d" % _connected_nodes.size(), Color(0.2, 0.85, 0.5, 1))
	if "clue_api_endpoint" in clues:
		_print_line("  [!] API endpoint known — closedai-pub.net accessible", Color(0.9, 0.7, 0.2, 1))
	if "clue_veil_model" in clues:
		_print_line("  [!!] VEIL model confirmed — internal evidence obtained", Color(1.0, 0.3, 0.3, 1))


func _cmd_scan(_args: Array) -> void:
	_print_line("scanning from %s..." % _current_node, Color(0.5, 0.7, 1, 1))
	var routes: Array = NODE_ROUTES.get(_current_node, [])
	for node in routes:
		var node_data: Dictionary = NETWORK.get(node, {})
		var req_clue: String = node_data.get("requires_clue", "")
		if req_clue == "" or req_clue in GameState.discovered_clues:
			var desc: String = node_data.get("desc", "unknown")
			var known: bool = node in _connected_nodes
			var tag: String = "[visited]" if known else "[new]"
			_print_line("  %s  %s — %s" % [tag, node, desc], Color(0.7, 0.9, 0.5, 1))
		else:
			_print_line("  [?]  %s — unreachable (insufficient access)" % node, Color(0.45, 0.45, 0.5, 1))
	if routes.is_empty():
		_print_line("  no reachable nodes from here.", Color(0.45, 0.45, 0.5, 1))


func _cmd_connect(args: Array) -> void:
	if args.is_empty():
		_print_error("usage: connect <target>")
		return
	var target: String = args[0].to_lower()

	if not NETWORK.has(target):
		_print_error("unknown host: %s" % target)
		return

	if target == _current_node:
		_print_line("already connected to %s." % target, Color(0.6, 0.6, 0.6, 1))
		return

	var routes: Array = NODE_ROUTES.get(_current_node, [])
	if target not in routes:
		_print_error("no route to %s from %s" % [target, _current_node])
		return

	var node_data: Dictionary = NETWORK.get(target, {})
	var req_clue: String = node_data.get("requires_clue", "")
	if req_clue != "" and req_clue not in GameState.discovered_clues:
		_print_line("connecting to %s..." % target, Color(0.5, 0.7, 1, 1))
		_print_line("  connection refused. no known entry point.", Color(1, 0.35, 0.35, 1))
		_print_line("  [ find more information before attempting this node ]", Color(0.4, 0.4, 0.5, 1))
		return

	_print_line("connecting to %s..." % target, Color(0.5, 0.7, 1, 1))
	_print_line("  establishing tunnel...", Color(0.4, 0.5, 0.65, 1))
	_print_line("  connected.", Color(0.2, 1, 0.4, 1))
	_current_node = target
	if target not in _connected_nodes:
		_connected_nodes.append(target)
	_update_prompt()
	_print_line("  %s" % node_data.get("desc", ""), Color(0.45, 0.55, 0.7, 1))
	_print_line("  type 'ls' to list files.", Color(0.35, 0.35, 0.45, 1))


func _cmd_ls(_args: Array) -> void:
	var node_data: Dictionary = NETWORK.get(_current_node, {})
	var files: Dictionary = node_data.get("files", {})
	if files.is_empty():
		_print_line("no files.", Color(0.45, 0.45, 0.5, 1))
		return
	_print_line("files on %s:" % _current_node, Color(0.7, 0.7, 0.8, 1))
	for fname in files:
		var fdata: Dictionary = files[fname]
		var req: String = fdata.get("requires_clue", "")
		if req == "" or req in GameState.discovered_clues:
			var already_read: bool = "clue_%s" % fname in GameState.discovered_clues or fdata.get("unlocks_clue", "") in GameState.discovered_clues
			var tag: String = "  [read]" if already_read else "  [file]"
			_print_line("%s  %s" % [tag, fname], Color(0.55, 0.8, 0.65, 1))
		else:
			_print_line("  [???]  %s  (access restricted)" % fname, Color(0.35, 0.35, 0.4, 1))


func _cmd_read(args: Array) -> void:
	if args.is_empty():
		_print_error("usage: read <filename>")
		return
	var fname: String = args[0].to_lower()
	var node_data: Dictionary = NETWORK.get(_current_node, {})
	var files: Dictionary = node_data.get("files", {})

	if not files.has(fname):
		_print_error("file not found: %s" % fname)
		return

	var fdata: Dictionary = files[fname]
	var req: String = fdata.get("requires_clue", "")
	if req != "" and req not in GameState.discovered_clues:
		_print_error("permission denied: insufficient access level")
		return

	# Print content
	_print_line("", Color.WHITE)
	_print_line("── %s ──" % fname, Color(0.4, 0.6, 0.9, 1))
	for line in fdata.get("content", "").split("\n"):
		_print_line("  " + line, Color(0.78, 0.78, 0.85, 1))
	_print_line("──────────────────────────────────", Color(0.25, 0.25, 0.35, 1))
	_print_line("", Color.WHITE)

	# Unlock clue if applicable
	var unlocks: String = fdata.get("unlocks_clue", "")
	if unlocks != "" and unlocks not in GameState.discovered_clues:
		GameState.discover_clue(unlocks)
		var clue_title: String = GameState.CLUE_DEFINITIONS.get(unlocks, {}).get("title", unlocks)
		_print_line("  [ clue logged: %s ]" % clue_title, Color(0.85, 0.75, 0.2, 1))
		_print_line("", Color.WHITE)


func _cmd_exit(_args: Array) -> void:
	if _current_node == "localhost":
		_print_line("already at localhost.", Color(0.5, 0.5, 0.55, 1))
	else:
		_print_line("disconnected from %s." % _current_node, Color(0.5, 0.7, 1, 1))
		_current_node = "localhost"
		_update_prompt()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _print_banner() -> void:
	_print_line("", Color.WHITE)
	_print_line("  CORPORATE THEATER — TERMINAL v0.1", Color(0.2, 1, 0.4, 1))
	_print_line("  ghost operative // encrypted channel", Color(0.35, 0.55, 0.35, 1))
	_print_line("  type 'help' for available commands.", Color(0.35, 0.35, 0.35, 1))
	_print_line("", Color.WHITE)


func _print_line(text: String, color: Color = Color.WHITE) -> void:
	output.push_color(color)
	output.append_text(text + "\n")
	output.pop()


func _print_error(text: String) -> void:
	_print_line("error: " + text, Color(1, 0.3, 0.3, 1))


func _update_prompt() -> void:
	prompt_label.text = "ghost@%s $ " % _current_node


func _add_to_history(cmd: String) -> void:
	_history.push_front(cmd)
	if _history.size() > MAX_HISTORY:
		_history.pop_back()
	_history_index = -1


func _history_navigate(direction: int) -> void:
	_history_index = clamp(_history_index + direction, -1, _history.size() - 1)
	if _history_index == -1:
		input.text = ""
	else:
		input.text = _history[_history_index]
	input.caret_column = input.text.length()
