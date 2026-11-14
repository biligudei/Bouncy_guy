extends CharacterBody2D

@export var normal_speed := 300.0
@export var roll_speed := 550.0

# Jump only works in roll mode. More negative = higher jump.
@export var roll_jump_velocity := -600.0
# Below 1.0 means less gravity in roll mode, so the jump lasts longer.
@export var roll_gravity_scale := 0.8

# --- Bounce (roll mode only) ---
# Bounce height = distance you fell x this number.
# Below 1.0 = each bounce is lower than the last, so bounces fade out.
@export var bounce_multiplier := 0.9
# Ignore tiny drops so you don't bounce from small bumps.
@export var bounce_min_fall := 10.0
# Safety cap so bounces can't launch you off the map.
@export var max_bounce_height := 800.0

# --- Charge bounce (hold E while falling in roll mode) ---
# Extra multiplier at full charge (1.7 = 70% higher bounce).
@export var charge_max_multiplier := 1.8
# Seconds of holding E (while falling) to reach full charge.
@export var charge_max_time := 1.0
# You can let go of E up to this many seconds before landing and still get the boost.
@export var charge_release_grace := 0.15

# --- Hunger settings ---
@onready var hunger_bar: Range = $Camera2D/HungerBar
@export var max_hunger := 100.0
@export var hunger_tick_time := 1.0
@export var hunger_drain_amount := 1.0
@export var respawn_delay := 2.0

# If the player falls below this Y position, they die.
@export var death_y := -114.0

# --- Level timer ---
@export var time_limit := 180.0       # 3 minutes
@export var win_restart_delay := 3.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var hunger := 0.0
var foods_eaten := 0
var _hunger_timer := 0.0
var _dead := false
var _won := false
var _time_left := 0.0
var _peak_y := 0.0   # highest point reached during the current airtime

var _charge_time := 0.0
var _release_timer := 0.0

var _facing := "right"
var _rolling := false
var _transitioning := false

var _death_layer: CanvasLayer
var _win_layer: CanvasLayer
var _time_bar: ProgressBar
var _time_label: Label
var _food_label: Label

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Make sure the transition animations play once and then finish.
	for anim in ["roll_in_right", "roll_in_left", "roll_out_right", "roll_out_left"]:
		if animated_sprite.sprite_frames.has_animation(anim):
			animated_sprite.sprite_frames.set_animation_loop(anim, false)
		else:
			push_warning("Missing animation: " + anim)

	_death_layer = _make_overlay(Color(0.8, 0.0, 0.0, 0.6))
	_win_layer = _make_overlay(Color(0.0, 0.5, 0.1, 0.6))
	_create_timer_ui()
	_create_food_counter()

	hunger = max_hunger
	if hunger_bar:
		hunger_bar.max_value = max_hunger
	_update_hunger_bar()

	_time_left = time_limit
	_update_timer_ui()
	_peak_y = global_position.y


func _physics_process(delta: float) -> void:
	# Frozen while dead or after winning.
	if _dead or _won:
		return

	# Fell out of bounds.
	if global_position.y > death_y:
		_die("YOU DIED")
		return

	# Level countdown.
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_update_timer_ui()
		_die("TIME'S UP")
		return
	_update_timer_ui()

	# Shift toggles roll mode (only on the ground, and not mid-transition).
	if Input.is_action_just_pressed("roll") and is_on_floor() and not _transitioning:
		_toggle_roll()

	# Hunger only drains while in roll mode.
	if _rolling and not _transitioning:
		_hunger_timer += delta
		if _hunger_timer >= hunger_tick_time:
			_hunger_timer -= hunger_tick_time
			_change_hunger(-hunger_drain_amount)
			if _dead:
				return

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

	_update_charge(delta)

	var was_on_floor := is_on_floor()
	move_and_slide()
	_handle_bounce(was_on_floor)
	_update_animation(direction)


# ---------------- Charge ----------------

func _update_charge(delta: float) -> void:
	var holding := Input.is_action_pressed("charge")

	if _rolling and not is_on_floor():
		if holding:
			_release_timer = 0.0
			# Energy only builds while moving downward.
			if velocity.y > 0.0:
				_charge_time = minf(_charge_time + delta, charge_max_time)
		elif _charge_time > 0.0:
			# Let go too early: the stored energy fades after a short grace window.
			_release_timer += delta
			if _release_timer > charge_release_grace:
				_charge_time = 0.0
	elif not _rolling:
		_charge_time = 0.0

	# Tint the sprite yellow-orange as energy builds up.
	var ratio := clampf(_charge_time / charge_max_time, 0.0, 1.0)
	animated_sprite.modulate = Color.WHITE.lerp(Color(1.0, 0.75, 0.3), ratio)


# ---------------- Bounce ----------------

func _handle_bounce(was_on_floor: bool) -> void:
	if is_on_floor():
		# Just landed this frame.
		if not was_on_floor and _rolling:
			# Distance fallen from the highest point of this airtime
			# (works after jumps AND after dropping off ledges).
			var fall_distance := global_position.y - _peak_y
			if fall_distance > bounce_min_fall:
				var bounce_height := minf(fall_distance * bounce_multiplier, max_bounce_height)

				# Stored energy boost: scales from 1.0x up to charge_max_multiplier.
				var charge_ratio := clampf(_charge_time / charge_max_time, 0.0, 1.0)
				bounce_height *= lerpf(1.0, charge_max_multiplier, charge_ratio)

				var g := gravity * roll_gravity_scale
				# Speed needed to rise exactly that high.
				velocity.y = -sqrt(2.0 * g * bounce_height)

		# Energy is used up (or lost) on landing.
		_charge_time = 0.0
		_release_timer = 0.0
		animated_sprite.modulate = Color.WHITE
		_peak_y = global_position.y
	else:
		# In the air: remember the highest point (smaller Y = higher).
		_peak_y = minf(_peak_y, global_position.y)


# ---------------- Hunger / Food ----------------

# Called by the food Areas.
func add_hunger(amount: float) -> void:
	if _dead or _won:
		return
	foods_eaten += 1
	_update_food_counter()
	_change_hunger(amount)


func _change_hunger(amount: float) -> void:
	hunger = clamp(hunger + amount, 0.0, max_hunger)
	_update_hunger_bar()
	if hunger <= 0.0:
		_die("YOU DIED")


func _update_hunger_bar() -> void:
	if hunger_bar:
		hunger_bar.value = hunger


# ---------------- Food counter UI ----------------

func _create_food_counter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	_food_label = Label.new()
	# Top-right corner of the screen.
	_food_label.anchor_left = 1.0
	_food_label.anchor_right = 1.0
	_food_label.offset_left = -260
	_food_label.offset_right = -16
	_food_label.offset_top = 10
	_food_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_food_label.add_theme_font_size_override("font_size", 28)
	_food_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_food_label.add_theme_constant_override("outline_size", 6)
	_food_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_food_label)

	_update_food_counter()


func _update_food_counter() -> void:
	if _food_label:
		_food_label.text = "Food: " + str(foods_eaten)


# ---------------- Timer UI ----------------

func _create_timer_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	_time_bar = ProgressBar.new()
	_time_bar.max_value = time_limit
	_time_bar.value = time_limit
	_time_bar.show_percentage = false
	# Top-center of the screen, 40% of the screen width.
	_time_bar.anchor_left = 0.3
	_time_bar.anchor_right = 0.7
	_time_bar.offset_top = 10
	_time_bar.offset_bottom = 36
	layer.add_child(_time_bar)

	_time_label = Label.new()
	_time_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_bar.add_child(_time_label)


func _update_timer_ui() -> void:
	if _time_bar == null:
		return
	_time_bar.value = _time_left
	_time_label.text = "TIME " + _format_time(_time_left)
	# Turn red in the last 30 seconds.
	_time_bar.modulate = Color(1.0, 0.4, 0.4) if _time_left <= 30.0 else Color.WHITE


func _format_time(t: float) -> String:
	var total := int(ceil(t))
	var minutes := floori(total / 60.0)
	return "%d:%02d" % [minutes, total % 60]


# ---------------- Death / Win ----------------

func _die(reason: String = "YOU DIED") -> void:
	if _dead or _won:
		return
	_dead = true
	velocity = Vector2.ZERO
	animated_sprite.pause()
	(_death_layer.get_node("Text") as Label).text = reason
	_death_layer.visible = true

	await get_tree().create_timer(respawn_delay).timeout
	get_tree().reload_current_scene()


# Called by the goal Area2D.
func reach_goal() -> void:
	if _dead or _won:
		return
	_won = true
	velocity = Vector2.ZERO
	animated_sprite.pause()
	(_win_layer.get_node("Text") as Label).text = "YOU WIN!\nTime left: " + _format_time(_time_left) + "\nFood eaten: " + str(foods_eaten)
	_win_layer.visible = true

	await get_tree().create_timer(win_restart_delay).timeout
	get_tree().reload_current_scene()


# Builds a full-screen colored overlay with big centered text (hidden by default).
func _make_overlay(color: Color) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)

	var label := Label.new()
	label.name = "Text"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 96)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)

	layer.visible = false
	return layer


# ---------------- Rolling / animation ----------------

func _toggle_roll() -> void:
	_transitioning = true
	var anim := ("roll_out_" if _rolling else "roll_in_") + _facing

	if animated_sprite.sprite_frames.has_animation(anim):
		animated_sprite.play(anim)
		await animated_sprite.animation_finished

	_rolling = not _rolling
	_transitioning = false


func _update_animation(direction: float) -> void:
	if _transitioning:
		return

	if _rolling:
		if direction != 0 or not is_on_floor():
			animated_sprite.play("roll_" + _facing)
		else:
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
