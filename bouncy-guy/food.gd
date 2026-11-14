extends Area2D

@export var hunger_restore := 20.0
@export var disappear_on_pickup := true
# Optional: only needed if the food's Sprite is NOT a child of this Area2D.
@export var node_to_remove: Node
# Drag your eating sound (.wav, .ogg or .mp3) here.
@export var eat_sound: AudioStream
@export var sound_volume_db := 0.0

var _used := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _used or not body.has_method("add_hunger"):
		return
	_used = true

	body.add_hunger(hunger_restore)
	_play_eat_sound()

	if disappear_on_pickup:
		set_deferred("monitoring", false)
		var target: Node = node_to_remove if node_to_remove else self
		target.queue_free()


func _play_eat_sound() -> void:
	if eat_sound == null:
		return
	# The sound player lives in the main scene, so it keeps playing
	# after the food is deleted, then removes itself.
	var player := AudioStreamPlayer.new()
	player.stream = eat_sound
	player.volume_db = sound_volume_db
	get_tree().current_scene.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
