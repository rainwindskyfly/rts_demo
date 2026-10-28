class_name OreField
extends Node2D
## A mineable ore deposit.
##
## The visual is a cluster of procedurally generated rock polygons. The number
## of visible rocks shrinks as the field is drained, so depletion is readable
## at a glance without any textures.

var amount: int = 0
var max_amount: int = 0
var is_home: bool = false

var _rocks: Array[Polygon2D] = []
var _rock_scale: Array[float] = []
var _rng := RandomNumberGenerator.new()


func setup(p_amount: int, p_home: bool) -> void:
	amount = p_amount
	max_amount = p_amount
	is_home = p_home
	_rng.seed = int(p_amount) * 7919 + int(position.x) + int(position.y)
	_build_rocks()
	_refresh_visual()


func _build_rocks() -> void:
	for child in get_children():
		child.queue_free()
	_rocks.clear()
	_rock_scale.clear()

	var count := 9
	for i in count:
		var rock := Polygon2D.new()
		var radius := _rng.randf_range(6.0, 13.0)
		var sides := 5 + _rng.randi_range(0, 3)
		var points := PackedVector2Array()
		for s in sides:
			var angle := TAU * float(s) / float(sides) + _rng.randf_range(-0.25, 0.25)
			var r := radius * _rng.randf_range(0.72, 1.15)
			points.append(Vector2(cos(angle) * r, sin(angle) * r))
		rock.polygon = points
		rock.position = Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(-14.0, 14.0))
		var shade := _rng.randf_range(0.32, 0.52)
		rock.color = Color(shade, shade * 1.02, shade * 1.12)
		add_child(rock)
		_rocks.append(rock)
		_rock_scale.append(1.0)


func _refresh_visual() -> void:
	var ratio := 0.0
	if max_amount > 0:
		ratio = float(amount) / float(max_amount)
	var visible_count := 0
	if ratio > 0.0:
		visible_count = maxi(1, int(ceil(float(_rocks.size()) * ratio)))
	for i in _rocks.size():
		var rock := _rocks[i]
		if i < visible_count:
			rock.visible = true
			var scale := lerpf(0.55, 1.0, ratio)
			rock.scale = Vector2(scale, scale)
		else:
			rock.visible = false


## Removes up to `request` ore and returns how much was actually taken.
func extract(request: int) -> int:
	if amount <= 0 or request <= 0:
		return 0
	var taken := mini(request, amount)
	amount -= taken
	_refresh_visual()
	return taken


func remaining() -> int:
	return amount


func is_depleted() -> bool:
	return amount <= 0
