extends CharacterBody2D

@export var normal_speed := 300.0
@export var roll_speed := 550.0

# Jump only works in roll mode. More negative = higher jump.
@export var roll_jump_velocity := -700.0
# Below 1.0 means less gravity in roll mode, so the jump lasts longer.
@export var roll_gravity_scale := 0.8

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var _facing := "right"
var _rolling := false        # true while in roll mode
var _transitioning := false  # true while roll_in / roll_out is playing

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Make sure the transition animations play once and then finish.
	for anim in ["roll_in_right", "roll_in_left", "roll_out_right", "roll_out_left"]:
		if animated_sprite.sprite_frames.has_animation(anim):
			animated_sprite.sprite_frames.set_animation_loop(anim, false)
		else:
			push_warning("Missing animation: " + anim)


func _physics_process(delta: float) -> void:
	# Shift toggles roll mode (only on the ground, and not mid-transition).
	if Input.is_action_just_pressed("roll") and is_on_floor() and not _transitioning:
		_toggle_roll()

	# Gravity (lighter in roll mode for a longer jump).
	if not is_on_floor():
		var g := gravity * (roll_gravity_scale if _rolling else 1.0)
		velocity.y += g * delta

	# Jump: only in roll mode.
	if _rolling and not _transitioning and is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = roll_jump_velocity

	# Horizontal movement, faster in roll mode.
	var direction := Input.get_axis("left", "right")
	var current_speed := roll_speed if _rolling else normal_speed
	velocity.x = direction * current_speed

	if direction > 0:
		_facing = "right"
	elif direction < 0:
		_facing = "left"

	move_and_slide()
	_update_animation(direction)


func _toggle_roll() -> void:
	_transitioning = true
	var anim := ("roll_out_" if _rolling else "roll_in_") + _facing

	# Only wait for the animation if it actually exists, otherwise we'd wait forever.
	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)
		await animated_sprite.animation_finished

	_rolling = not _rolling
	_transitioning = false


func _update_animation(direction: float) -> void:
	# Don't interrupt roll_in / roll_out.
	if _transitioning:
		return

	if _rolling:
		if direction != 0 or not is_on_floor():
			# Running or in the air.
			animated_sprite.play("roll_" + _facing)
		else:
			# Standing still.
			var idle_anim := "roll_idle_" + _facing
			if animated_sprite.sprite_frames.has_animation(idle_anim):
				animated_sprite.play(idle_anim)
			else:
				animated_sprite.play("roll_" + _facing)
	else:
		if direction != 0:
			animated_sprite.play("walk_" + _facing)
		else:
			animated_sprite.play("idle_" + _facing)
