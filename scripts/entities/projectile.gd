class_name Projectile
extends Node2D
## A tank shell in flight.
##
## The target is held as a plain `Node2D` and damaged through the duck-typed
## `take_damage` call. Keeping `Unit` out of this file breaks what would
## otherwise be a cyclic class dependency (Unit spawns Projectiles, and
## Projectile would reference Unit back).

@export var speed: float = 320.0
@export var damage: float = 24.0
@export var splash_radius: float = 0.0

var target: Node2D = null
## The unit that fired this shell, forwarded as the damage source so kills
## are credited correctly.
var shooter: Node = null
var direction: Vector2 = Vector2.RIGHT
var _life: float = 4.0


func launch(p_target: Node2D, p_damage: float, p_speed: float, from: Vector2, p_shooter: Node = null) -> void:
	target = p_target
	shooter = p_shooter
	damage = p_damage
	speed = p_speed
	global_position = from
	_life = 4.0
	if target != null:
		direction = (target.global_position - from).normalized()
	else:
		direction = Vector2.RIGHT
	rotation = direction.angle()
	queue_redraw()


func _ready() -> void:
	z_index = 20


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	if target != null and is_instance_valid(target):
		# Lead the target slightly so fast movers are still hit.
		var aim := target.global_position
		direction = direction.lerp((aim - global_position).normalized(), 6.0 * delta).normalized()
		if global_position.distance_to(aim) <= maxf(8.0, speed * delta + 10.0):
			_impact()
			return
	else:
		if global_position.distance_to(global_position + direction * 8.0) <= 0.5:
			pass

	global_position += direction * speed * delta
	rotation = direction.angle()


func _impact() -> void:
	if target != null and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(damage, shooter)
	_spawn_spark()
	queue_free()


func _spawn_spark() -> void:
	var spark := Line2D.new()
	spark.width = 3.0
	spark.default_color = Color(1.0, 0.85, 0.35, 0.9)
	spark.add_point(Vector2.ZERO)
	spark.add_point(direction * -12.0)
	get_parent().add_child(spark)
	spark.z_index = 21
	var tween := create_tween()
	tween.tween_property(spark, "modulate:a", 0.0, 0.18)
	tween.tween_callback(spark.queue_free)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 3.5, Color(1.0, 0.92, 0.55))
	draw_circle(Vector2.ZERO, 1.6, Color(1.0, 1.0, 0.9))
