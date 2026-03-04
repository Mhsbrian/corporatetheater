extends Control

@onready var btn_new_game: Button = $CenterContainer/VBoxContainer/BtnNewGame
@onready var btn_continue: Button = $CenterContainer/VBoxContainer/BtnContinue
@onready var btn_quit: Button = $CenterContainer/VBoxContainer/BtnQuit
@onready var tagline: Label = $CenterContainer/VBoxContainer/Tagline

const INTRO_SCENE = "res://scenes/menus/intro_sequence.tscn"
const DESKTOP_SCENE = "res://scenes/ui/desktop.tscn"

var _taglines: Array[String] = [
	"the truth is behind the curtain.",
	"they said it was for you.",
	"transparency is a product.",
	"every post is a performance.",
	"freedom, curated by closedai.",
	"you are the last honest signal.",
]

func _ready() -> void:
	# Randomize tagline each launch
	tagline.text = _taglines[randi() % _taglines.size()]

	btn_new_game.pressed.connect(_on_new_game)
	btn_continue.pressed.connect(_on_continue)
	btn_quit.pressed.connect(_on_quit)

	# Disable continue if no save exists
	btn_continue.disabled = not _save_exists()


func _on_new_game() -> void:
	get_tree().change_scene_to_file(INTRO_SCENE)


func _on_continue() -> void:
	# TODO: load save state before transitioning
	get_tree().change_scene_to_file(DESKTOP_SCENE)


func _on_quit() -> void:
	get_tree().quit()


func _save_exists() -> bool:
	return FileAccess.file_exists("user://save.json")
