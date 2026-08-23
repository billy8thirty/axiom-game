extends Control

# Buttons werden hier per Code verbunden, die Szene hat keine
# [connection]-Blocke - ein umbenannter Button faellt so sofort auf.

@onready var singleplayer_button: Button = $CenterContainer/VBoxContainer/Singleplayer
@onready var multiplayer_button: Button = $CenterContainer/VBoxContainer/Multiplayer
@onready var test_scene_button: Button = $CenterContainer/VBoxContainer/TestScene
@onready var settings_button: Button = $CenterContainer/VBoxContainer/Settings
@onready var quit_button: Button = $CenterContainer/VBoxContainer/Quit
@onready var version_label: Label = $VersionLabel


func _ready() -> void:
	# Nach dem Verlassen einer Runde ist die Maus noch gefangen.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	version_label.text = "v%s" % Net.GAME_VERSION

	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	test_scene_button.pressed.connect(_on_test_scene_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	settings_button.disabled = true

	singleplayer_button.grab_focus()


func _on_singleplayer_pressed() -> void:
	Net.start_singleplayer()


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file(Net.BROWSER_SCENE)


func _on_test_scene_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/testScene.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
