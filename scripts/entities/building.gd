class_name Building
extends Combatant
## A static structure: HQ, Barracks or Refinery.
##
## Buildings handle two independent timers:
##   * construction — health grows from 0 to max over `build_time`;
##   * production  — a FIFO queue of unit archetypes.
##
## A building only functions once construction finishes.

var stats: BuildingStats = null
var kind: int = 0

## 0 while under construction, 1 when finished.
var build_progress: float = 0.0
var finished: bool = false

## Each entry is {"stats": UnitStats, "remaining": float}.
var production_queue: Array[Dictionary] = []

var _body_polygon: Polygon2D = null
var _progress_bar: Node2D = null
var _blocked_radius: float = 0.0


func setup(p_stats: BuildingStats, p_faction: int, position_override: Vector2 = Vector2.INF) -> void:
	stats = p_stats
	faction = p_faction
	kind = p_stats.kind
	armor_class = p_stats.armor
	max_health = p_stats.max_health
	health = p_stats.max_health
	if position_override != Vector2.INF:
		global_position = position_override


func _ready() -> void:
	super._ready()
	if stats == null:
		stats = Game.config.hq_stats
		max_health = stats.max_health
		health = p_stats_health_on_completion()

	add_to_group("player_buildings" if faction == FACTION_PLAYER else "enemy_buildings")
	add_to_group("deposit_points")
	if faction == FACTION_PLAYER:
		add_to_group("player_deposits")
	else:
		add_to_group("enemy_deposits")
	Game.register_building(self, faction == FACTION_PLAYER)

	collision_layer = 1  # part of the static world
	collision_mask = 0

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	_blocked_radius = stats.size.x * 0.35 + 2.0
	circle.radius = _blocked_radius
	shape.shape = circle
	add_child(shape)

	var visual := Node2D.new()
	visual.name = "Visual"
	add_child(visual)

	_body_polygon = Polygon2D.new()
	_body_polygon.polygon = _rect_polygon(stats.size)
	_body_polygon.color = stats.color
	visual.add_child(_body_polygon)

	# A darker roof block makes the footprint readable at a glance.
	var roof := Polygon2D.new()
	roof.polygon = _rect_polygon(stats.size * 0.55)
	roof.color = stats.color.lightened(0.25)
	roof.position = Vector2(0, -stats.size.y * 0.12)
	visual.add_child(roof)

	health_bar = HealthBar.new()
	health_bar.offset_y = -(stats.size.y * 0.5 + 12.0)
	health_bar.bar_width = maxf(24.0, stats.size.x)
	add_child(health_bar)
	health_bar.set_ratio(1.0)

	z_index = 5
	Pathfinder.set_blocked_circle(global_position, _blocked_radius, true)


func p_stats_health_on_completion() -> float:
	return stats.max_health


static func _rect_polygon(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])


func deposit_radius() -> float:
	return stats.deposit_radius


func is_player_building() -> bool:
	return faction == FACTION_PLAYER


func can_accept_order() -> bool:
	return finished and production_queue.size() < stats.queue_size


## Queues one unit for production. Returns false when the queue is full.
func enqueue(unit_stats: UnitStats) -> bool:
	if not finished or production_queue.size() >= stats.queue_size:
		return false
	production_queue.append({"stats": unit_stats, "remaining": unit_stats.build_time})
	return true


func _process(delta: float) -> void:
	super._process(delta)
	if not alive:
		return

	if not finished:
		if stats.build_time > 0.0:
			build_progress = minf(1.0, build_progress + delta / stats.build_time)
			health = max_health * build_progress
			if health_bar != null:
				health_bar.set_ratio(build_progress)
			if build_progress >= 1.0:
				_finish_construction()
		else:
			_finish_construction()
		return

	if production_queue.is_empty():
		return
	var entry: Dictionary = production_queue[0]
	entry["remaining"] = float(entry["remaining"]) - delta
	if float(entry["remaining"]) <= 0.0:
		production_queue.pop_front()
		_spawn_unit(entry["stats"])


func _finish_construction() -> void:
	if finished:
		return
	finished = true
	build_progress = 1.0
	health = max_health
	if health_bar != null:
		health_bar.set_ratio(1.0)
	Events.building_ready.emit(self)


func _spawn_unit(unit_stats: UnitStats) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spawned := Unit.new()
	# `setup` MUST run before the node enters the tree: `_ready` registers the
	# unit in the faction registries and groups, and it can only do that
	# correctly once the faction is known.
	spawned.setup(unit_stats, faction, _spawn_position())
	parent.add_child(spawned)
	if faction == FACTION_PLAYER:
		Game.stat_units_built += 1
	Events.order_issued.emit({"type": "produce", "building": self, "unit": unit_stats.display_name})


func _spawn_position() -> Vector2:
	# Try a ring of offsets around the building until one is not blocked.
	for i in 8:
		var angle := TAU * float(i) / 8.0 + randf() * 0.3
		var candidate := global_position + Vector2(cos(angle), sin(angle)) * (stats.size.x * 0.5 + 28.0)
		if not Pathfinder.is_blocked_world(candidate):
			return candidate
	return global_position + Vector2(stats.size.x, 0)


func _on_died(_source: Node) -> void:
	Game.unregister_building(self, faction == FACTION_PLAYER)
	Pathfinder.set_blocked_circle(global_position, _blocked_radius, false)
	production_queue.clear()
	Events.building_destroyed.emit(self)


func _draw() -> void:
	if not finished:
		# Construction outline.
		draw_arc(Vector2.ZERO, stats.size.x * 0.5 + 4.0, 0.0, TAU, 28, Color(0.95, 0.85, 0.35, 0.85), 2.0, true)
		# Progress arc.
		var radius := stats.size.x * 0.5 + 10.0
		draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * build_progress, 32, Color(0.35, 0.85, 0.95, 0.95), 3.0, true)
