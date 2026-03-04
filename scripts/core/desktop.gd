extends Control

# Corporate Theater — Desktop
# The player's persistent online workspace.
# Left panel: live Z feed (always on, always scrolling).
# Right panel: active app window (terminal, browser, etc.)
# Bottom: taskbar with clock and app launchers.

@onready var taskbar_btns: HBoxContainer = $Taskbar/TaskbarItems
@onready var btn_terminal: Button = $Taskbar/TaskbarItems/BtnTerminal
@onready var btn_browser: Button = $Taskbar/TaskbarItems/BtnBrowser
@onready var btn_phone: Button = $Taskbar/TaskbarItems/BtnPhone
@onready var btn_network: Button = $Taskbar/TaskbarItems/BtnNetwork
@onready var clock_label: Label = $Taskbar/TaskbarItems/ClockLabel
@onready var app_window: Control = $MainArea/AppWindow
@onready var z_feed_container: VBoxContainer = $MainArea/ZPanel/ScrollContainer/ZFeed
@onready var notification_bar: Label = $NotificationBar

var _feed_posts: Array = []
var _feed_index: int = 0
var _active_app: String = ""

const POST_DATA_PATH := "res://data/posts/z_posts.json"
const TERMINAL_SCENE := "res://scenes/ui/terminal.tscn"


func _ready() -> void:
	btn_terminal.pressed.connect(func(): _launch_app("terminal"))
	btn_browser.pressed.connect(func(): _launch_app("browser"))
	btn_phone.pressed.connect(func(): _launch_app("phone"))
	btn_network.pressed.connect(func(): _launch_app("network"))

	_load_feed()
	_render_feed()
	_start_feed_ticker()
	_show_notification("new message from [ UNKNOWN ] — check your terminal")


func _process(_delta: float) -> void:
	_update_clock()


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [t.hour, t.minute]


# ── Z Feed ────────────────────────────────────────────────────────────────────

func _load_feed() -> void:
	if not FileAccess.file_exists(POST_DATA_PATH):
		return
	var file := FileAccess.open(POST_DATA_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_feed_posts = json.data


func _render_feed() -> void:
	for child in z_feed_container.get_children():
		child.queue_free()
	for post in _feed_posts:
		z_feed_container.add_child(_build_post_card(post))


func _start_feed_ticker() -> void:
	# Every 18 seconds, a new "live" post trickles in
	var timer := Timer.new()
	timer.wait_time = 18.0
	timer.autostart = true
	timer.timeout.connect(_tick_feed)
	add_child(timer)


func _tick_feed() -> void:
	if _feed_posts.is_empty():
		return
	# Cycle through posts as if they're live
	_feed_index = (_feed_index + 1) % _feed_posts.size()
	var post = _feed_posts[_feed_index]
	var card := _build_post_card(post)
	card.modulate.a = 0.0
	z_feed_container.add_child(card)
	z_feed_container.move_child(card, 0)

	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.6)

	# Remove oldest if too many
	if z_feed_container.get_child_count() > 8:
		var oldest := z_feed_container.get_child(z_feed_container.get_child_count() - 1)
		oldest.queue_free()

	_show_notification("@%s posted on Z" % post.get("handle", "").trim_prefix("@"))


func _build_post_card(post: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 1.0)
	style.border_width_left = 3
	style.border_color = Color.from_string(post.get("avatar_color", "#44ff88"), Color(0.2, 1, 0.4, 1))
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	var author := Label.new()
	var author_text: String = post.get("author", "")
	if post.get("verified", false):
		author_text += " ✓"
	author.text = author_text
	author.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	author.add_theme_font_size_override("font_size", 11)

	var handle := Label.new()
	handle.text = "  " + post.get("handle", "")
	handle.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	handle.add_theme_font_size_override("font_size", 10)
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	header.add_child(author)
	header.add_child(handle)

	var content := Label.new()
	content.text = post.get("content", "")
	content.add_theme_color_override("font_color", Color(0.80, 0.80, 0.86, 1))
	content.add_theme_font_size_override("font_size", 11)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var stats := Label.new()
	stats.text = "♥ %s   ↺ %s" % [post.get("likes", "0"), post.get("reposts", "0")]
	stats.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45, 1))
	stats.add_theme_font_size_override("font_size", 10)

	vbox.add_child(header)
	vbox.add_child(content)
	vbox.add_child(stats)
	card.add_child(vbox)
	return card


# ── App Launcher ──────────────────────────────────────────────────────────────

func _launch_app(app: String) -> void:
	if _active_app == app:
		return
	_active_app = app

	for child in app_window.get_children():
		child.queue_free()

	match app:
		"terminal":
			var scene := load(TERMINAL_SCENE)
			if scene:
				var node: Control = scene.instantiate()
				node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				app_window.add_child(node)
		_:
			_show_placeholder(app)


func _show_placeholder(app: String) -> void:
	var labels := {
		"browser": ["NEXUS BROWSER", Color(0.4, 0.7, 1, 1)],
		"phone": ["iSPHERE", Color(0.8, 0.6, 1, 1)],
		"network": ["NETWORK MAP", Color(1, 0.6, 0.2, 1)],
	}
	var info: Array = labels.get(app, ["UNKNOWN", Color.WHITE])
	var label := Label.new()
	label.text = "[ %s ]\n\ncoming soon." % info[0]
	label.add_theme_color_override("font_color", info[1])
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_window.add_child(label)


# ── Notification Bar ──────────────────────────────────────────────────────────

func _show_notification(text: String) -> void:
	notification_bar.text = "  //  " + text
	notification_bar.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(notification_bar, "modulate:a", 0.0, 1.0)
