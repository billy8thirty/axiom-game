extends Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_start_Game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/testScene.tscn")

func _on_button_2_pressed() -> void:
	pass # Replace with function body.

func _on_test_scene_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/testScene.tscn")



func _on_quit_pressed() -> void:
	get_tree().quit()
