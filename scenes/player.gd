extends CharacterBody3D

const SPEED := 5.5
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 4.8
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := 1.5  # ~86 Grad
const FALL_LIMIT := -50.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D = $Body
@onready var facing_mesh: MeshInstance3D = $Facing
@onready var name_label: Label3D = $NameLabel

var peer_id := 1
var is_local := false

var _spawn_position := Vector3.ZERO


func _enter_tree() -> void:
	peer_id = str(name).to_int()
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	is_local = is_multiplayer_authority()

	if is_local:
		var assigned := Net.take_spawn_position()
		if assigned.is_finite():
			position = assigned

	_spawn_position = position

	camera.current = is_local
	name_label.visible = not is_local
	facing_mesh.visible = not is_local
	body_mesh.set_surface_override_material(0, _player_material())

	_refresh_label()
	Net.players_changed.connect(_refresh_label)

	set_physics_process(is_local)
	set_process_unhandled_input(is_local)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	if position.y < FALL_LIMIT:
		position = _spawn_position
		velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clampf(
			camera_pivot.rotation.x - motion.relative.y * MOUSE_SENSITIVITY,
			-PITCH_LIMIT, PITCH_LIMIT)


func apply_spawn_position(spawn: Vector3) -> void:
	position = spawn
	velocity = Vector3.ZERO
	_spawn_position = spawn


func _refresh_label() -> void:
	name_label.text = Net.player_display_name(peer_id)


# Farbe aus der Peer-ID, damit sich die Figuren beim Testen unterscheiden.
func _player_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(fmod(float(peer_id) * 0.381966, 1.0), 0.55, 0.9)
	return material
