class_name Pathfinder
extends RefCounted
## Grid A* pathfinding over the whole map.
##
## Why not `NavigationRegion2D` + `NavigationAgent2D`? The navigation server has a
## map-synchronisation timing window where a freshly spawned agent receives no
## path and silently stands still. For a one-night demo that failure mode is
## unacceptable, so the demo uses its own deterministic grid instead: every
## query returns a path or an explicit failure, and the behaviour is identical
## in a headless test run.
##
## The grid is 30 px cells (80 x 45 = 3600 cells for the 2400 x 1350 map), so a
## full A* expansion is cheap enough to run for every unit order.

const CELL_SIZE: float = 30.0
const AGENT_RADIUS: float = 16.0

static var _width: int = 0
static var _height: int = 0
static var _blocked: PackedByteArray = PackedByteArray()
static var _ready: bool = false

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## Builds the walkability grid. `obstacles` is an Array of Dictionary with
## "pos" (Vector2) and "radius" (float) keys.
static func setup(map_size: Vector2, obstacles: Array) -> void:
	_width = maxi(1, int(ceil(map_size.x / CELL_SIZE)))
	_height = maxi(1, int(ceil(map_size.y / CELL_SIZE)))
	_blocked = PackedByteArray()
	_blocked.resize(_width * _height)
	_blocked.fill(0)

	for obstacle in obstacles:
		var centre: Vector2 = obstacle["pos"]
		var radius: float = float(obstacle["radius"]) + AGENT_RADIUS
		var min_x := maxi(0, int(floor((centre.x - radius) / CELL_SIZE)))
		var max_x := mini(_width - 1, int(ceil((centre.x + radius) / CELL_SIZE)))
		var min_y := maxi(0, int(floor((centre.y - radius) / CELL_SIZE)))
		var max_y := mini(_height - 1, int(ceil((centre.y + radius) / CELL_SIZE)))
		for cy in range(min_y, max_y + 1):
			for cx in range(min_x, max_x + 1):
				var centre_of_cell := cell_to_world(Vector2i(cx, cy))
				if centre_of_cell.distance_to(centre) <= radius:
					_blocked[cy * _width + cx] = 1

	_ready = true


static func is_ready() -> bool:
	return _ready


## Marks (or clears) a circular area as unwalkable. Used by buildings, which
## are placed during the match and therefore cannot be part of the static
## obstacle list.
static func set_blocked_circle(centre: Vector2, radius: float, blocked: bool) -> void:
	if not _ready:
		return
	var min_x := maxi(0, int(floor((centre.x - radius) / CELL_SIZE)))
	var max_x := mini(_width - 1, int(ceil((centre.x + radius) / CELL_SIZE)))
	var min_y := maxi(0, int(floor((centre.y - radius) / CELL_SIZE)))
	var max_y := mini(_height - 1, int(ceil((centre.y + radius) / CELL_SIZE)))
	for cy in range(min_y, max_y + 1):
		for cx in range(min_x, max_x + 1):
			if cell_to_world(Vector2i(cx, cy)).distance_to(centre) <= radius:
				_blocked[cy * _width + cx] = 1 if blocked else 0


static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * CELL_SIZE, (float(cell.y) + 0.5) * CELL_SIZE)


static func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.y / CELL_SIZE)))


static func is_blocked_world(pos: Vector2) -> bool:
	if not _ready:
		return false
	var cell := world_to_cell(pos)
	if not _in_bounds(cell):
		return true
	return _blocked[cell.y * _width + cell.x] == 1


## Returns a smoothed world-space path, or an empty array when unreachable.
static func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if not _ready:
		return empty

	var start := world_to_cell(from)
	var goal := world_to_cell(to)
	if not _in_bounds(start):
		start = _nearest_free(start)
		if start.x < 0:
			return empty
	if not _in_bounds(goal):
		goal = _nearest_free(goal)
		if goal.x < 0:
			return empty
	if _is_blocked(goal):
		var relaxed := _nearest_free(goal)
		if relaxed.x >= 0:
			goal = relaxed

	var total := _width * _height
	var g_score := PackedFloat32Array()
	g_score.resize(total)
	g_score.fill(INF)
	var came_from := PackedInt32Array()
	came_from.resize(total)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(total)
	closed.fill(0)

	var start_index := start.y * _width + start.x
	var goal_index := goal.y * _width + goal.x
	g_score[start_index] = 0.0

	# Binary heap of [f_score, cell_index] pairs.
	var heap: Array = [[_heuristic(start, goal), start_index]]

	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var current: int = top[1]
		if current == goal_index:
			break
		if closed[current] == 1:
			continue
		closed[current] = 1

		var cx := current % _width
		var cy := current / _width

		for offset in NEIGHBORS:
			var nx := cx + offset.x
			var ny := cy + offset.y
			if nx < 0 or ny < 0 or nx >= _width or ny >= _height:
				continue
			var neighbour_index := ny * _width + nx
			if _blocked[neighbour_index] == 1:
				continue
			# Do not cut corners diagonally past a blocked cell.
			if offset.x != 0 and offset.y != 0:
				if _blocked[cy * _width + nx] == 1 or _blocked[ny * _width + cx] == 1:
					continue

			var step := 1.0 if (offset.x == 0 or offset.y == 0) else 1.41421356
			var tentative := g_score[current] + step
			if tentative < g_score[neighbour_index]:
				g_score[neighbour_index] = tentative
				came_from[neighbour_index] = current
				_heap_push(heap, [_heuristic(Vector2i(nx, ny), goal), neighbour_index])

	if came_from[goal_index] == -1 and goal_index != start_index:
		return empty

	var cells: Array[Vector2i] = []
	var walker := goal_index
	while walker != -1:
		cells.append(Vector2i(walker % _width, walker / _width))
		walker = came_from[walker]
	cells.reverse()

	var world_path := PackedVector2Array()
	for cell in cells:
		world_path.append(cell_to_world(cell))
	return _smooth(world_path)


## String-pulling: drop waypoints that a straight line can skip.
static func _smooth(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	var result := PackedVector2Array()
	result.append(path[0])
	var anchor := 0
	var probe := 1
	while probe < path.size():
		if not _has_line_of_sight(world_to_cell(path[anchor]), world_to_cell(path[probe])):
			result.append(path[probe - 1])
			anchor = probe - 1
		probe += 1
	result.append(path[path.size() - 1])
	return result


static func _has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	# Bresenham line between two cells; every traversed cell must be free.
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx - dy
	var x := a.x
	var y := a.y
	while true:
		if _is_blocked(Vector2i(x, y)):
			return false
		if x == b.x and y == b.y:
			return true
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return true


static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Octile distance — admissible for 8-way movement.
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxf(dx, dy) + 0.41421356 * minf(dx, dy)


static func _is_blocked(cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return true
	return _blocked[cell.y * _width + cell.x] == 1


static func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height


## Spiral outwards from `cell` until a free cell is found.
static func _nearest_free(cell: Vector2i) -> Vector2i:
	if _in_bounds(cell) and not _is_blocked(cell):
		return cell
	for radius in range(1, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var candidate := Vector2i(cell.x + dx, cell.y + dy)
				if _in_bounds(candidate) and not _is_blocked(candidate):
					return candidate
	return Vector2i(-1, -1)


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if float(heap[parent][0]) <= float(heap[index][0]):
			break
		var tmp = heap[parent]
		heap[parent] = heap[index]
		heap[index] = tmp
		index = parent


static func _heap_pop(heap: Array) -> Array:
	var top = heap[0]
	var last = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if left < heap.size() and float(heap[left][0]) < float(heap[smallest][0]):
			smallest = left
		if right < heap.size() and float(heap[right][0]) < float(heap[smallest][0]):
			smallest = right
		if smallest == index:
			break
		var tmp = heap[smallest]
		heap[smallest] = heap[index]
		heap[index] = tmp
		index = smallest
	return top
