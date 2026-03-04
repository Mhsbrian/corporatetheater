extends Control

# Corporate Theater — NEXUS Browser
# Simulates a dark-web-adjacent browser with curated news sites.
# Player reads articles, comments, discovers clues embedded in text.

const SITES_DATA_PATH := "res://data/news/browser_sites.json"

@onready var address_bar: LineEdit = $Chrome/HBox/AddressBar
@onready var site_list: VBoxContainer = $MainArea/SidePanel/SideScroll/SiteList
@onready var content_area: ScrollContainer = $MainArea/ContentArea
@onready var content_body: VBoxContainer = $MainArea/ContentArea/Body
@onready var status_bar: Label = $StatusPanel/StatusBar

var _sites: Array = []
var _current_site: Dictionary = {}
var _current_article: Dictionary = {}


func _ready() -> void:
	_load_sites()
	_apply_gamestate_unlocks()
	_build_site_list()
	_show_home()
	address_bar.text_submitted.connect(_on_address_submitted)
	GameState.clue_added.connect(_on_clue_added)


func _load_sites() -> void:
	if not FileAccess.file_exists(SITES_DATA_PATH):
		return
	var file := FileAccess.open(SITES_DATA_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_sites = json.data.get("sites", [])


func _apply_gamestate_unlocks() -> void:
	for site in _sites:
		var req: String = site.get("unlock_clue", "")
		if req != "" and req in GameState.discovered_clues:
			site["locked"] = false


func _on_clue_added(clue: Dictionary) -> void:
	var clue_id: String = clue.get("clue_id", "")
	var did_unlock := false
	for site in _sites:
		if site.get("unlock_clue", "") == clue_id and site.get("locked", false):
			site["locked"] = false
			did_unlock = true
	if did_unlock:
		_build_site_list()
		_show_darkpulse_notification()


func _build_site_list() -> void:
	for child in site_list.get_children():
		child.queue_free()

	for site in _sites:
		var locked: bool = site.get("locked", false)
		var btn := Button.new()
		btn.text = ("🔒 " if locked else "  ") + site.get("name", "")
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var col := Color.from_string(site.get("color", "#888888"), Color.GRAY)
		if locked:
			col = Color(0.3, 0.3, 0.3, 1)
		btn.add_theme_color_override("font_color", col)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_font_size_override("font_size", 12)
		if not locked:
			btn.pressed.connect(func(): _navigate_to_site(site))
		else:
			btn.tooltip_text = "[ LOCKED ] Discover the unlock clue to access this site."
		site_list.add_child(btn)


func _navigate_to_site(site: Dictionary) -> void:
	_current_site = site
	_current_article = {}
	address_bar.text = site.get("url", "")
	_set_status("connected to " + site.get("url", ""))
	_render_site_home(site)


func _render_site_home(site: Dictionary) -> void:
	_clear_content()

	# Site header
	_add_header(site.get("name", ""), site.get("color", "#ffffff"))
	_add_label(site.get("tagline", ""), Color(0.5, 0.5, 0.5, 1), 11)
	_add_divider()

	# Article list
	for article in site.get("articles", []):
		var btn := _make_article_button(article, site)
		content_body.add_child(btn)
		_add_spacer(4)


func _make_article_button(article: Dictionary, site: Dictionary) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var headline := Button.new()
	headline.text = article.get("headline", "")
	headline.flat = true
	headline.alignment = HORIZONTAL_ALIGNMENT_LEFT
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0, 1))
	headline.add_theme_color_override("font_hover_color", Color.WHITE)
	headline.add_theme_font_size_override("font_size", 13)
	headline.pressed.connect(func(): _open_article(article, site))

	var meta := Label.new()
	meta.text = "  by %s  ·  %s" % [article.get("author", ""), article.get("timestamp", "")]
	meta.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5, 1))
	meta.add_theme_font_size_override("font_size", 10)

	container.add_child(headline)
	container.add_child(meta)
	return container


func _open_article(article: Dictionary, site: Dictionary) -> void:
	_current_article = article
	address_bar.text = site.get("url", "") + "/" + article.get("id", "")
	_set_status("reading — " + article.get("headline", ""))
	GameState.mark_article_visited(article.get("id", ""))

	# Discover any clue tied to reading this article
	var article_clue: String = article.get("unlocks_clue", "")
	if article_clue != "" and article_clue not in GameState.discovered_clues:
		GameState.discover_clue(article_clue)

	_clear_content()

	# Back button
	var back := Button.new()
	back.text = "← back to " + site.get("name", "")
	back.flat = true
	back.add_theme_color_override("font_color", Color.from_string(site.get("color", "#888"), Color.GRAY))
	back.add_theme_font_size_override("font_size", 11)
	back.pressed.connect(func(): _render_site_home(site))
	content_body.add_child(back)
	_add_spacer(8)

	# Headline
	_add_header(article.get("headline", ""), "#ffffff")
	_add_label("by %s  ·  %s" % [article.get("author", ""), article.get("timestamp", "")],
		Color(0.45, 0.45, 0.55, 1), 11)
	_add_divider()

	# Body text — split into paragraphs
	var body_text: String = article.get("body", "")
	for para in body_text.split("\n\n"):
		if para.strip_edges() == "":
			continue
		_add_body_text(para.strip_edges())
		_add_spacer(6)

	# Comments
	var comments: Array = article.get("comments", [])
	if not comments.is_empty():
		_add_divider()
		_add_label("COMMENTS (%d)" % comments.size(), Color(0.4, 0.4, 0.55, 1), 11)
		_add_spacer(6)
		for comment in comments:
			_render_comment(comment, 0)


func _render_comment(comment: Dictionary, depth: int) -> void:
	var indent := depth * 20

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07 + depth * 0.015, 0.07 + depth * 0.015, 0.11, 1.0)
	style.border_width_left = 2 if depth > 0 else 0
	style.border_color = Color(0.2, 0.2, 0.35, 1)
	style.content_margin_left = 10 + indent
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	var user_row := HBoxContainer.new()
	var user_label := Label.new()
	user_label.text = comment.get("user", "anon")
	user_label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0, 1))
	user_label.add_theme_font_size_override("font_size", 11)

	var likes_label := Label.new()
	likes_label.text = "  ♥ %s" % str(comment.get("likes", 0))
	likes_label.add_theme_color_override("font_color", Color(0.5, 0.35, 0.5, 1))
	likes_label.add_theme_font_size_override("font_size", 10)
	likes_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	user_row.add_child(user_label)
	user_row.add_child(likes_label)

	var text_label := Label.new()
	text_label.text = comment.get("text", "")
	text_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84, 1))
	text_label.add_theme_font_size_override("font_size", 12)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	vbox.add_child(user_row)
	vbox.add_child(text_label)
	panel.add_child(vbox)
	content_body.add_child(panel)
	_add_spacer(2)

	# Replies
	for reply in comment.get("replies", []):
		_render_comment(reply, depth + 1)


func _show_home() -> void:
	_clear_content()
	address_bar.text = "nexus://home"
	_set_status("welcome to NEXUS")

	_add_header("NEXUS BROWSER", "#44ff88")
	_add_label("your window to the unfiltered world.", Color(0.4, 0.4, 0.5, 1), 12)
	_add_divider()
	_add_label("select a site from the sidebar.", Color(0.5, 0.5, 0.6, 1), 12)
	_add_spacer(12)
	_add_label("BOOKMARKS", Color(0.3, 0.3, 0.45, 1), 10)
	_add_spacer(4)

	for site in _sites:
		var locked: bool = site.get("locked", false)
		var row := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = Color.from_string(site.get("color", "#888"), Color.GRAY) if not locked else Color(0.3, 0.3, 0.3, 1)
		dot.custom_minimum_size = Vector2(8, 8)

		var lbl := Button.new()
		lbl.text = ("  [locked]  " if locked else "  ") + site.get("url", "")
		lbl.flat = true
		lbl.alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8, 1) if not locked else Color(0.3, 0.3, 0.3, 1))
		lbl.add_theme_font_size_override("font_size", 12)
		if not locked:
			lbl.pressed.connect(func(): _navigate_to_site(site))

		row.add_child(dot)
		row.add_child(lbl)
		content_body.add_child(row)


func _on_address_submitted(url: String) -> void:
	for site in _sites:
		if site.get("url", "") == url.strip_edges().to_lower():
			_navigate_to_site(site)
			return
	_set_status("could not resolve: " + url)


func _show_darkpulse_notification() -> void:
	# Brief system message in current content view
	var lbl := Label.new()
	lbl.text = "\n  [ new site unlocked — check sidebar ]\n"
	lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5, 0.8))
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_body.add_child(lbl)


# ── UI Helpers ────────────────────────────────────────────────────────────────

func _clear_content() -> void:
	for child in content_body.get_children():
		child.queue_free()


func _add_header(text: String, hex_color: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color.from_string(hex_color, Color.WHITE))
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_body.add_child(lbl)


func _add_label(text: String, color: Color, size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	content_body.add_child(lbl)


func _add_body_text(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.88, 1))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_body.add_child(lbl)


func _add_divider() -> void:
	var hr := ColorRect.new()
	hr.color = Color(0.15, 0.15, 0.25, 1)
	hr.custom_minimum_size = Vector2(0, 1)
	content_body.add_child(hr)
	_add_spacer(6)


func _add_spacer(height: int) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, height)
	content_body.add_child(sp)


func _set_status(text: String) -> void:
	status_bar.text = "  " + text


func navigate_to_url(url: String, article_id: String = "") -> void:
	# Called externally from desktop when Z feed links are clicked
	for site in _sites:
		if site.get("url", "") == url:
			if article_id != "":
				for article in site.get("articles", []):
					if article.get("id", "") == article_id:
						_open_article(article, site)
						return
			_navigate_to_site(site)
			return
	_set_status("could not resolve: " + url)
