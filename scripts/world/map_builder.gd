class_name MapBuilder
extends Node2D
## Builds the playable world: terrain, grid, obstacles and ore fields.
##
## Everything is procedural — there is not a single image file in the project.
## Obstacles double as the pathfinding grid's blocked cells, which is what
## makes units route around them instead of walking straight into them.

const GROUND_COLOR: Color = Color(0.20, 0.27, 0.19)
const VOID_COLOR: Color = Color(0.08, 0.09, 0.08)
const GRID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.035)
const BORDER_COLOR: Color = Color(0.45, 0.55, 0.42, 0.55)
const ORE_ROCK_COLOR: Color = Color(0.42, 0.45, 0.50)


func build(config: GameConfig, ore_root: Node2D) -> void:
	var map_size := config.map_size

	# Backdrop behind the map so panning past the edge never shows the window bg.
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([
		Vector2(-600, -600), Vector2(map_size.x + 600, -600),
		Vector2(map_size.x + 600, map_size.y + 600), Vector2(-600, map_size.y + 600),
	])
	backdrop.color = VOID_COLOR
	add_child(backdrop)

	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(map_size.x, 0), Vector2(map_size.x, map_size.y), Vector2(0, map_size.y),
	])
	ground.color = GROUND_COLOR
	add_child(ground)

	# Grid lines every 60 px.
	var step := 60.0
	var x := step
	while x < map_size.x:
		_add_line(Vector2(x, 0), Vector2(x, map_size.y), GRID_COLOR, 1.0)
		x += step
	var y := step
	while y < map_size.y:
		_add_line(Vector2(0, y), Vector2(map_size.x, y), GRID_COLOR, 1.0)
		y += step

	# Map border.
	var border := Line2D.new()
	border.width = 3.0
	border.default_color = BORDER_COLOR
	border.closed = true
	border.points = PackedVector2Array([
		Vector2.ZERO, Vector2(map_size.x, 0), Vector2(map_size.x, map_size.y), Vector2(0, map_size.y),
	])
	add_child(border)

	# Obstacles: a physics body plus an irregular rock silhouette.
	for obstacle in config.obstacles:
		var centre: Vector2 = obstacle["pos"]
		var radius: float = obstacle["radius"]

		var body := StaticBody2D.new()
		body.position = centre
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = radius
		shape.shape = circle
		body.add_child(shape)
		add_child(body)

		var rock := Polygon2D.new()
		rock.polygon = _blob_polygon(radius, centre)
		rock.color = Color(0.13, 0.16, 0.12)
		rock.position = centre
		add_child(rock)

		var rim := Polygon2D.new()
		rim.polygon = _blob_polygon(radius * 0.82, centre)
		rim.color = Color(0.18, 0.22, 0.17)
		rim.position = centre
		add_child(rim)

	# Ore fields.
	for entry in config.ore_fields:
		var ore := OreField.new()
		ore.position = entry["pos"]
		ore.setup(int(entry["amount"]), bool(entry["home"]))
		ore_root.add_child(ore)
		Game.ore_fields.append(ore)

	# The pathfinding grid is derived from the exact same obstacle list.
	Pathfinder.setup(map_size, config.obstacles)


func _add_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = width
	line.default_color = color
	add_child(line)


## Builds an irregular closed polygon so obstacles do not look like circles.
static func _blob_polygon(radius: float, seed_centre: Vector2) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_centre.x) * 7919 + int(seed_centre.y) * 104729 + int(radius)
	var sides := 11
	var points := PackedVector2Array()
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		var r := radius * rng.randf_range(0.84, 1.12)
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return points
