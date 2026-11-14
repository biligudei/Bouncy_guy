extends CharacterBody2D

# Horizontal movement speed in pixels per second.
@export var speed := 300.0
#made for idkkkk

# Pulls the character down so it stays on the ground (platformer style).
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# Which way the character last faced: "right" or "left".
var _facing := "right"

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _physics_process(delta: float) -> void:
	# Apply gravity while in the air.
	if not is_on_floor():
		velocity.y += gravity * delta

	# -1 for left, 1 for right, 0 for neither (also works with analog sticks).
	var direction := Input.get_axis("left", "right")
	velocity.x = direction * speed

	move_and_slide()
	_update_animation(direction)


func _update_animation(direction: float) -> void:
	if direction > 0:
		_facing = "right"
		animated_sprite.play("walk_right")
	elif direction < 0:
		_facing = "left"
		animated_sprite.play("walk_left")
	else:
		animated_sprite.play("idle_" + _facing)
