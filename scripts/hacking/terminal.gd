extends Control

# Corporate Theater — Terminal Engine
# Simulates a hacker CLI. Player types commands to interact with the ClosedAI network.

@onready var output: RichTextLabel = $VBox/Output
@onready var input: LineEdit = $VBox/InputRow/Input
@onready var prompt_label: Label = $VBox/InputRow/Prompt

const MAX_HISTORY := 50
var _history: Array[String] = []
var _history_index: int = -1
var _current_node: String = "localhost"

# Command registry: command name -> callable
var _commands: Dictionary = {}


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
	_commands["exit"]    = _cmd_exit


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


# ── Built-in Commands ─────────────────────────────────────────────────────────

func _cmd_help(_args: Array) -> void:
	_print_line("available commands:", Color(0.8, 0.8, 0.8, 1))
	_print_line("  help              show this message", Color(0.6, 0.6, 0.6, 1))
	_print_line("  clear             clear terminal output", Color(0.6, 0.6, 0.6, 1))
	_print_line("  whoami            show current user", Color(0.6, 0.6, 0.6, 1))
	_print_line("  scan              scan current node for targets", Color(0.6, 0.6, 0.6, 1))
	_print_line("  connect <target>  connect to a network node", Color(0.6, 0.6, 0.6, 1))
	_print_line("  ls                list files on current node", Color(0.6, 0.6, 0.6, 1))
	_print_line("  read <file>       read a file", Color(0.6, 0.6, 0.6, 1))
	_print_line("  exit              disconnect from current node", Color(0.6, 0.6, 0.6, 1))


func _cmd_clear(_args: Array) -> void:
	output.clear()


func _cmd_whoami(_args: Array) -> void:
	_print_line("ghost@" + _current_node, Color(0.2, 1, 0.4, 1))


func _cmd_scan(_args: Array) -> void:
	_print_line("scanning local network...", Color(0.6, 0.8, 1, 1))
	# TODO: pull from GameState — nodes discovered by player
	_print_line("  [?] closedai-pub.net       — public facing, unprotected", Color(0.8, 0.8, 0.4, 1))
	_print_line("  [!] closedai-internal.net  — firewall detected", Color(1, 0.4, 0.4, 1))
	_print_line("  [?] clearsky-relay.gov     — government endpoint", Color(1, 0.5, 0.1, 1))


func _cmd_connect(args: Array) -> void:
	if args.is_empty():
		_print_error("usage: connect <target>")
		return
	var target: String = args[0]
	_print_line("connecting to %s..." % target, Color(0.6, 0.8, 1, 1))
	# TODO: route through GameState node access checks
	_print_line("access denied. authentication required.", Color(1, 0.3, 0.3, 1))


func _cmd_ls(_args: Array) -> void:
	# TODO: pull from GameState node file system
	_print_line("no files found on %s." % _current_node, Color(0.6, 0.6, 0.6, 1))


func _cmd_read(args: Array) -> void:
	if args.is_empty():
		_print_error("usage: read <filename>")
		return
	_print_error("file not found: %s" % args[0])


func _cmd_exit(_args: Array) -> void:
	if _current_node == "localhost":
		_print_line("already at localhost.", Color(0.6, 0.6, 0.6, 1))
	else:
		_print_line("disconnected from %s." % _current_node, Color(0.6, 0.6, 0.6, 1))
		_current_node = "localhost"
		_update_prompt()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _print_banner() -> void:
	_print_line("", Color.WHITE)
	_print_line("  CORPORATE THEATER — TERMINAL v0.1", Color(0.2, 1, 0.4, 1))
	_print_line("  ghost operative // encrypted channel", Color(0.4, 0.6, 0.4, 1))
	_print_line("  type 'help' for available commands.", Color(0.4, 0.4, 0.4, 1))
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
