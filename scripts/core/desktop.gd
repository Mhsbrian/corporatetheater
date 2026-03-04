extends Control

@onready var btn_terminal: Button = $Taskbar/TaskbarItems/BtnTerminal
@onready var btn_browser: Button = $Taskbar/TaskbarItems/BtnBrowser
@onready var btn_phone: Button = $Taskbar/TaskbarItems/BtnPhone
@onready var btn_network: Button = $Taskbar/TaskbarItems/BtnNetwork
@onready var clock_label: Label = $Taskbar/TaskbarItems/ClockLabel
@onready var window_area: Control = $WindowArea

# Preload sub-scenes (to be created)
# const TerminalScene = preload("res://scenes/ui/terminal.tscn")
# const BrowserScene  = preload("res://scenes/ui/browser.tscn")
# const PhoneScene    = preload("res://scenes/ui/phone.tscn")
# const NetworkScene  = preload("res://scenes/world/network_map.tscn")

var _active_window: Control = null


func _ready() -> void:
	btn_terminal.pressed.connect(func(): _open_window("terminal"))
	btn_browser.pressed.connect(func(): _open_window("browser"))
	btn_phone.pressed.connect(func(): _open_window("phone"))
	btn_network.pressed.connect(func(): _open_window("network"))


func _process(_delta: float) -> void:
	_update_clock()


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [t.hour, t.minute]


func _open_window(type: String) -> void:
	# Clear existing window
	if _active_window:
		_active_window.queue_free()
		_active_window = null

	match type:
		"terminal":
			_show_placeholder("TERMINAL", Color(0.2, 1, 0.4, 1))
		"browser":
			_show_placeholder("NEXUS BROWSER", Color(0.4, 0.7, 1, 1))
		"phone":
			_show_placeholder("iSPHERE", Color(0.8, 0.6, 1, 1))
		"network":
			_show_placeholder("NETWORK MAP", Color(1, 0.6, 0.2, 1))


func _show_placeholder(title: String, color: Color) -> void:
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(800, 500)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.text = "[ %s ]\n\nComing soon." % title
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	panel.add_child(label)
	window_area.add_child(panel)
	_active_window = panel
