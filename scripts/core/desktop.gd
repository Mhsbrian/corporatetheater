extends Control

# Corporate Theater — Desktop
# Central hub. Powered by GameState for all persistence.
# Z feed links navigate browser. Clues auto-populate Notes.

@onready var btn_terminal: Button = $Taskbar/TaskbarItems/BtnTerminal
@onready var btn_browser: Button = $Taskbar/TaskbarItems/BtnBrowser
@onready var btn_messenger: Button = $Taskbar/TaskbarItems/BtnMessenger
@onready var btn_notes: Button = $Taskbar/TaskbarItems/BtnNotes
@onready var btn_network: Button = $Taskbar/TaskbarItems/BtnNetwork
@onready var btn_go_outside: Button = $Taskbar/TaskbarItems/BtnGoOutside
@onready var clock_label: Label = $Taskbar/TaskbarItems/ClockLabel
@onready var notification_bar: Label = $Taskbar/TaskbarItems/NotificationBar
@onready var app_window: Control = $MainArea/AppWindow
@onready var z_feed_container: VBoxContainer = $MainArea/ZPanel/ScrollContainer/ZFeed
@onready var notes_badge: Label = $Taskbar/TaskbarItems/BtnNotes/Badge

const POST_DATA_PATH    := "res://data/posts/z_posts.json"
const TERMINAL_SCENE   := "res://scenes/ui/terminal.tscn"
const BROWSER_SCENE    := "res://scenes/ui/browser.tscn"
const MESSENGER_SCENE  := "res://scenes/ui/z_messenger.tscn"
const NOTES_SCENE      := "res://scenes/ui/notes.tscn"
const NETMAP_SCENE     := "res://scenes/ui/network_map.tscn"
const OUTSIDE_SCENE    := "res://scenes/world/outside.tscn"

var _feed_posts: Array = []
var _feed_index: int = 0
var _active_app: String = ""
var _active_browser: Control = null
var _notes_unseen: int = 0


func _ready() -> void:
	GameState.load_save()

	btn_terminal.pressed.connect(func(): _launch_app("terminal"))
	btn_browser.pressed.connect(func(): _launch_app("browser"))
	btn_messenger.pressed.connect(func(): _launch_app("messenger"))
	btn_notes.pressed.connect(func(): _launch_app("notes"))
	btn_network.pressed.connect(func(): _launch_app("network"))
	btn_go_outside.pressed.connect(func(): _launch_app("outside"))

	GameState.clue_added.connect(_on_clue_added)
	GameState.browser_navigate.connect(_on_browser_navigate)
	GameState.contact_unlocked.connect(_on_contact_unlocked)

	_refresh_outside_button()

	_load_feed()
	_render_feed()
	_start_feed_ticker()
	_update_notes_badge()

	if not GameState.get_messages("elena_vasquez").is_empty():
		_show_notification("conversation history restored")
	else:
		_show_notification("new message from [ UNKNOWN ] — check Z messages")


func _process(_delta: float) -> void:
	_update_clock()


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [t.hour, t.minute]


# ── Clue / Notes Badge ────────────────────────────────────────────────────────

func _on_contact_unlocked(contact_id: String) -> void:
	_show_notification("new contact unlocked: " + contact_id.replace("_", " "))
	AudioManager.play_contact_unlock()


func _on_clue_added(note: Dictionary) -> void:
	_notes_unseen += 1
	_update_notes_badge()
	_show_notification("evidence logged: " + note.get("title", ""))
	AudioManager.play_clue_sting()
	_refresh_outside_button()


func _refresh_outside_button() -> void:
	btn_go_outside.disabled = false
	btn_go_outside.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8, 1.0))


func _update_notes_badge() -> void:
	var total := GameState.notes.size()
	if total == 0:
		notes_badge.visible = false
	else:
		notes_badge.visible = true
		notes_badge.text = str(total)


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
	var timer := Timer.new()
	timer.wait_time = 20.0
	timer.autostart = true
	timer.timeout.connect(_tick_feed)
	add_child(timer)


func _tick_feed() -> void:
	if _feed_posts.is_empty():
		return
	_feed_index = (_feed_index + 1) % _feed_posts.size()
	var post: Dictionary = _feed_posts[_feed_index]
	var card := _build_post_card(post)
	card.modulate.a = 0.0
	z_feed_container.add_child(card)
	z_feed_container.move_child(card, 0)
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.6)
	if z_feed_container.get_child_count() > 8:
		z_feed_container.get_child(z_feed_container.get_child_count() - 1).queue_free()
	_show_notification(post.get("handle", "") + " posted on Z")


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
	author.text = post.get("author", "") + (" ✓" if post.get("verified", false) else "")
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

	var bottom_row := HBoxContainer.new()

	var stats := Label.new()
	stats.text = "\u2665 %s   \u2B6F %s" % [post.get("likes", "0"), post.get("reposts", "0")]
	stats.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45, 1))
	stats.add_theme_font_size_override("font_size", 10)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Link button if post has a link_to field
	var link_site: String = post.get("link_site", "")
	var link_article: String = post.get("link_article", "")
	if link_site != "":
		var link_btn := Button.new()
		link_btn.text = "read →"
		link_btn.flat = true
		link_btn.add_theme_color_override("font_color", Color(0.4, 0.65, 1.0, 1))
		link_btn.add_theme_font_size_override("font_size", 10)
		link_btn.pressed.connect(func():
			_launch_app("browser")
			await get_tree().process_frame
			GameState.navigate_browser(link_site, link_article)
		)
		bottom_row.add_child(stats)
		bottom_row.add_child(link_btn)
	else:
		bottom_row.add_child(stats)

	vbox.add_child(header)
	vbox.add_child(content)
	vbox.add_child(bottom_row)
	card.add_child(vbox)
	return card


# ── Browser Navigation ────────────────────────────────────────────────────────

func _on_browser_navigate(url: String, article_id: String) -> void:
	_launch_app("browser")
	await get_tree().process_frame
	if _active_browser and is_instance_valid(_active_browser):
		_active_browser.navigate_to_url(url, article_id)


# ── App Launcher ──────────────────────────────────────────────────────────────

func _launch_app(app: String) -> void:
	# "outside" is a full-screen scene that self-destructs; always allow relaunch
	if _active_app == app and app != "outside":
		return
	_active_app = app
	_active_browser = null

	for child in app_window.get_children():
		child.queue_free()

	if app == "notes":
		_notes_unseen = 0
		_update_notes_badge()

	var scene_path: String = ({
		"terminal": TERMINAL_SCENE,
		"browser": BROWSER_SCENE,
		"messenger": MESSENGER_SCENE,
		"notes": NOTES_SCENE,
		"network": NETMAP_SCENE,
		"outside": OUTSIDE_SCENE
	} as Dictionary).get(app, "") as String

	if scene_path != "":
		var scene := load(scene_path)
		if scene:
			var node: Control = scene.instantiate()
			node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			app_window.add_child(node)
			if app == "browser":
				_active_browser = node
	else:
		_show_placeholder(app)


func _show_placeholder(app: String) -> void:
	var label := Label.new()
	label.text = "[ %s ]\n\ncoming soon." % app.to_upper()
	label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.3, 1))
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_window.add_child(label)


# ── Notification ──────────────────────────────────────────────────────────────

func _show_notification(text: String) -> void:
	notification_bar.text = "  //  " + text
	notification_bar.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(notification_bar, "modulate:a", 0.0, 1.2)
