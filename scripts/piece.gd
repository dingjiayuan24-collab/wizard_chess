class_name Piece
extends Node2D

enum Type { KING, QUEEN, ROOK, BISHOP, KNIGHT, PAWN }
enum Team { HUMAN, DEMON }

@export var type: Type
@export var team: Team
var board_pos: Vector2i
var has_moved: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func set_state(state: String) -> void:
	if sprite.animation != state:
		sprite.play(state)


func play_attack() -> void:
	set_state("attack")
	await sprite.animation_finished


func die() -> void:
	set_state("death")
	await sprite.animation_finished
	queue_free()


func tween_to_position(world_pos: Vector2, duration: float) -> void:
	set_state("run")
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", world_pos, duration)
	await tw.finished
