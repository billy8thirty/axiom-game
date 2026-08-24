extends VehicleBody3D

const STEER_SPEED = 1.5
const STEER_LIMIT = 0.4
const BRAKE_STRENGTH = 2.0
const PITCH_LIMIT = 1.5  # ~86 Grad
const MOUSE_SENSITIVITY = 0.0025

@export var engine_force_value := 400.0
@onready var camera_pivot: Node3D = $cameraPivot
@onready var spring_arm: SpringArm3D = $cameraPivot/SpringArm3D

var previous_speed := linear_velocity.length()
var _steer_target := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float):
	var fwd_mps := (linear_velocity * transform.basis).x

	_steer_target = Input.get_axis(&"ui_right", &"ui_left")
	_steer_target *= STEER_LIMIT

	# Automatically accelerate when using touch controls (reversing overrides acceleration).
	if DisplayServer.is_touchscreen_available() or Input.is_action_pressed(&"ui_up"):
		# Increase engine force at low speeds to make the initial acceleration faster.
		var speed := linear_velocity.length()
		if speed < 5.0 and not is_zero_approx(speed):
			engine_force = clampf(engine_force_value * 5.0 / speed, 0.0, 100.0)
		else:
			engine_force = engine_force_value

		if not DisplayServer.is_touchscreen_available():
			# Apply analog throttle factor for more subtle acceleration if not fully holding down the trigger.
			engine_force *= Input.get_action_strength(&"ui_up")
	else:
		engine_force = 0.0

	if Input.is_action_pressed(&"ui_down"):
		# Increase engine force at low speeds to make the initial reversing faster.
		var speed := linear_velocity.length()
		if speed < 5.0 and not is_zero_approx(speed):
			engine_force = -clampf(engine_force_value * BRAKE_STRENGTH * 5.0 / speed, 0.0, 100.0)
		else:
			engine_force = -engine_force_value * BRAKE_STRENGTH

		# Apply analog brake factor for more subtle braking if not fully holding down the trigger.
		engine_force *= Input.get_action_strength(&"ui_down")

	steering = move_toward(steering, _steer_target, STEER_SPEED * delta)

	previous_speed = linear_velocity.length()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		camera_pivot.rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		spring_arm.rotation.x = clampf(
			spring_arm.rotation.x - motion.relative.y * MOUSE_SENSITIVITY,
			-PITCH_LIMIT, PITCH_LIMIT)
