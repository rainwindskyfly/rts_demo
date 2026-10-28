class_name Unit
extends Combatant
## A single movable combat unit or worker.
##
## Behaviour priority, highest first:
##   1. Worker state machine (mine → carry → deposit) for harvester units.
##   2. An explicit move / attack order issued by the player or the AI.
##   3. Auto-defence: acquire a nearby enemy and chase it.
##
## Movement uses the grid A* in `Pathfinder` rather than Godot's navigation
## server, which keeps path queries deterministic and free of the
## map-synchronisation race that silently strands freshly spawned agents.

enum WorkerState { IDLE, GO_MINE, MINING, GO_DEPOSIT, DEPOSIT }

var stats: UnitStats = null
var kind: int = 0

# --- selection ---
var selected: bool = false

# --- movement state ---
var move_goal: Vector2 = Vector2.ZERO
var has_move_order: bool = false
var action_text: String = "Idle"

var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _path_goal: Vector2 = Vector2.ZERO
var _path_valid: bool = false
var _has_path: bool = false
var _repath_cd: float = 0.0

# --- combat state ---
## Current attack target. Typed as `Combatant` so a unit can be ordered to
## attack a building as well as another unit.
var target: Combatant = null
var _attack_cd: float = 0.0
var _acquire_cd: float = 0.0
var _chase: bool = false

# --- worker state ---
var worker_state: int = WorkerState.IDLE
var harvest_target: OreField = null
var carried: int = 0
var _mining_cd: float = 0.0

var _separation_cd: float = 0.0
var _separation: Vector2 = Vector2.ZERO
var _body_polygon: Polygon2D = null
var _facing_polygon: Polygon2D = null


func setup(p_stats: UnitStats, p_faction: int, position_override: Vector2 = Vector2.INF) -> void:
	stats = p_stats
	faction = p_faction
	kind = p_stats.kind
	max_health = p_stats.max_health
	health = p_stats.max_health
	armor_class = GameConfig.unit_armor(kind)
	if position_override != Vector2.INF:
		# `setup` is called before the node enters the tree, so `position` is
		# used until the unit is parented.
		position = position_override


func _ready() -> void:
	super._ready()
	if stats == null:
		stats = Game.config.infantry_stats
		max_health = stats.max_health
		health = stats.max_health

	var group := "player_units" if faction == FACTION_PLAYER else "enemy_units"
	add_to_group(group)
	Game.register_unit(self, faction == FACTION_PLAYER)

	collision_layer = 2
	collision_mask = 1  # collide with the static world only; units separate softly

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = stats.radius
	shape.shape = circle
	add_child(shape)

	_visual = Node2D.new()
	_visual.name = "Visual"
	add_child(_visual)

	_body_polygon = Polygon2D.new()
	_body_polygon.polygon = _square_polygon(stats.body_size)
	_body_polygon.color = stats.color
	_visual.add_child(_body_polygon)

	_facing_polygon = Polygon2D.new()
	_facing_polygon.polygon = _triangle_polygon(stats.body_size)
	_facing_polygon.color = stats.color.lightened(0.45)
	_visual.add_child(_facing_polygon)

	health_bar = HealthBar.new()
	health_bar.offset_y = -(stats.body_size * 0.5 + 12.0)
	health_bar.bar_width = maxf(18.0, stats.body_size * 2.0)
	add_child(health_bar)
	health_bar.set_ratio(1.0)

	_acquire_cd = randf() * 0.2
	z_index = 10


static func _square_polygon(size: float) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h),
	])


static func _triangle_polygon(size: float) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([
		Vector2(h + 4.0, 0.0),
		Vector2(h - 3.0, -h * 0.55),
		Vector2(h - 3.0, h * 0.55),
	])


# ------------------------------------------------------------------ orders
func move_to(destination: Vector2) -> void:
	move_goal = destination
	has_move_order = true
	worker_state = WorkerState.IDLE
	harvest_target = null
	carried = 0
	_path_valid = false
	_has_path = false
	action_text = "Moving"


func attack_target(t: Combatant) -> void:
	target = t
	has_move_order = true
	move_goal = t.global_position if t != null else global_position
	_path_valid = false
	_has_path = false
	action_text = "Attacking"
	_chase = true


func stop() -> void:
	has_move_order = false
	worker_state = WorkerState.IDLE
	harvest_target = null
	_chase = false
	_path_valid = false
	_has_path = false
	action_text = "Idle"


func harvest(ore: OreField) -> void:
	if ore == null:
		return
	harvest_target = ore
	worker_state = WorkerState.GO_MINE
	has_move_order = false
	_chase = false
	_path_valid = false
	_has_path = false
	action_text = "Mining"


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func is_worker() -> bool:
	return stats != null and stats.carry_capacity > 0


# ------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if not alive:
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_acquire_cd -= delta
	_repath_cd = maxf(0.0, _repath_cd - delta)

	if is_worker():
		_process_worker(delta)
	else:
		_process_combat_orders(delta)

	var desired := Vector2.ZERO
	if worker_state == WorkerState.GO_MINE or worker_state == WorkerState.GO_DEPOSIT:
		desired = _steer_to(_worker_destination())
	elif has_move_order:
		desired = _steer_to(move_goal)
	elif target != null and is_instance_valid(target) and target.is_alive() and _chase:
		desired = _steer_to(target.global_position)
		if global_position.distance_to(target.global_position) <= stats.attack_range:
			desired = Vector2.ZERO

	desired += _compute_separation(delta)
	if desired.length() > 1.0:
		desired = desired.normalized()

	velocity = velocity.move_toward(desired * stats.speed, stats.speed * 8.0 * delta)
	move_and_slide()

	if _facing_polygon != null and velocity.length_squared() > 25.0:
		_facing_polygon.rotation = velocity.angle()


func _process_combat_orders(delta: float) -> void:
	if target != null and (not is_instance_valid(target) or not target.is_alive()):
		target = null

	if _acquire_cd <= 0.0:
		_acquire_cd = 0.2
		_acquire_target()

	if target != null and is_instance_valid(target) and target.is_alive():
		var distance := global_position.distance_to(target.global_position)
		if distance <= stats.attack_range:
			_try_fire()
			if not has_move_order:
				action_text = "Attacking"
		elif not has_move_order:
			# Idle units defend their position.
			_chase = true
	else:
		_chase = false
		if not has_move_order and action_text == "Attacking":
			action_text = "Idle"


func _acquire_target() -> void:
	if target != null and is_instance_valid(target) and target.is_alive():
		return
	target = null
	var group := "enemy_units" if faction == FACTION_PLAYER else "player_units"
	var best: Unit = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(group):
		var other := node as Unit
		if other == null or not other.is_alive():
			continue
		var distance := global_position.distance_to(other.global_position)
		if distance > stats.acquire_range:
			continue
		# Prefer close targets, with a nudge towards finishing off wounded ones.
		var score := distance - (1.0 - other.health_ratio()) * 60.0
		if score < best_score:
			best_score = score
			best = other
	target = best


func _try_fire() -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	if _attack_cd > 0.0:
		return
	_attack_cd = stats.attack_cooldown
	var damage := _damage_against(target)

	if stats.is_ranged:
		var parent := get_parent()
		if parent == null:
			return
		var shell := Projectile.new()
		parent.add_child(shell)
		shell.launch(target, damage, stats.projectile_speed, global_position, self)
	else:
		target.take_damage(damage, self)


func _damage_against(other: Combatant) -> float:
	var multiplier := GameConfig.damage_multiplier(kind, other.armor_class)
	return stats.attack_damage * multiplier


# ------------------------------------------------------------ worker FSM
func _worker_destination() -> Vector2:
	match worker_state:
		WorkerState.GO_MINE:
			return harvest_target.global_position if harvest_target != null else global_position
		WorkerState.GO_DEPOSIT:
			var depot := _nearest_deposit()
			return depot.global_position if depot != null else global_position
	return global_position


func _process_worker(delta: float) -> void:
	if target != null and (not is_instance_valid(target) or not target.is_alive()):
		target = null

	match worker_state:
		WorkerState.GO_MINE:
			if harvest_target == null or not is_instance_valid(harvest_target):
				worker_state = WorkerState.IDLE
				action_text = "Idle"
				return
			action_text = "Mining"
			if global_position.distance_to(harvest_target.global_position) <= 22.0:
				worker_state = WorkerState.MINING
				_mining_cd = stats.mining_time
		WorkerState.MINING:
			action_text = "Mining"
			_mining_cd -= delta
			if _mining_cd <= 0.0:
				_mining_cd = stats.mining_time
				if harvest_target != null and is_instance_valid(harvest_target):
					carried += harvest_target.extract(stats.harvest_rate)
				if carried >= stats.carry_capacity:
					worker_state = WorkerState.GO_DEPOSIT
					_path_valid = false
					_has_path = false
				elif harvest_target == null or not is_instance_valid(harvest_target) or harvest_target.is_depleted():
					worker_state = WorkerState.GO_DEPOSIT
					_path_valid = false
					_has_path = false
		WorkerState.GO_DEPOSIT:
			action_text = "Returning"
			var depot := _nearest_deposit()
			if depot == null:
				worker_state = WorkerState.IDLE
				action_text = "Idle"
				return
			if global_position.distance_to(depot.global_position) <= maxf(24.0, depot.deposit_radius() * 0.6):
				worker_state = WorkerState.DEPOSIT
		WorkerState.DEPOSIT:
			action_text = "Depositing"
			if carried > 0:
				if faction == FACTION_PLAYER:
					Game.add_minerals(carried)
				else:
					Events.enemy_minerals_gained.emit(carried)
				carried = 0
			if harvest_target != null and is_instance_valid(harvest_target) and not harvest_target.is_depleted():
				worker_state = WorkerState.GO_MINE
				_path_valid = false
				_has_path = false
			else:
				worker_state = WorkerState.IDLE
				action_text = "Idle"
			_path_valid = false
			_has_path = false
		_:
			# Idle workers still defend themselves.
			_process_combat_orders(delta)


func _nearest_deposit() -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("deposit_points"):
		var deposit := node as Node2D
		if deposit == null or not is_instance_valid(deposit):
			continue
		var is_player_deposit := deposit.is_in_group("player_deposits")
		if is_player_deposit != (faction == FACTION_PLAYER):
			continue
		var distance := global_position.distance_to(deposit.global_position)
		if distance < best_distance:
			best_distance = distance
			best = deposit
	return best


# ------------------------------------------------------------- movement
func _steer_to(destination: Vector2) -> Vector2:
	var distance := global_position.distance_to(destination)
	if distance < 1.0:
		return Vector2.ZERO

	var goal_changed := not _path_valid or _path_goal.distance_to(destination) > 40.0
	if goal_changed:
		if _repath_cd <= 0.0:
			_repath_cd = 0.25
			_path = Pathfinder.find_path(global_position, destination)
			_path_goal = destination
			_path_valid = true
			_path_index = 0
			_has_path = _path.size() > 0
			if not _has_path:
				# Unreachable through the grid: fall back to a straight line so the
				# unit still makes progress instead of standing still.
				return (destination - global_position).normalized()
		elif not _has_path:
			return (destination - global_position).normalized()
	else:
		if not _has_path:
			# Already standing on the current goal.
			return Vector2.ZERO

	while _path_index < _path.size() and global_position.distance_to(_path[_path_index]) < 20.0:
		_path_index += 1
	if _path_index >= _path.size():
		_has_path = false
		return Vector2.ZERO
	return (_path[_path_index] - global_position).normalized()


func _compute_separation(delta: float) -> Vector2:
	_separation_cd -= delta
	if _separation_cd <= 0.0:
		_separation_cd = 0.1
		var group := "player_units" if faction == FACTION_PLAYER else "enemy_units"
		var push := Vector2.ZERO
		for node in get_tree().get_nodes_in_group(group):
			var other := node as Unit
			if other == null or other == self or not other.is_alive():
				continue
			var offset := global_position - other.global_position
			var distance := offset.length()
			var minimum := stats.radius + other.stats.radius
			if distance > 0.01 and distance < minimum:
				push += offset / distance * (minimum - distance) / minimum
		_separation = push
	return _separation * 1.6


func _on_died(_source: Node) -> void:
	Game.unregister_unit(self, faction == FACTION_PLAYER)
	if _body_polygon != null:
		_body_polygon.color = Color(0.4, 0.4, 0.4, 0.6)


func _draw() -> void:
	if not selected:
		return
	draw_arc(Vector2.ZERO, stats.radius + 5.0, 0.0, TAU, 24, Color(1.0, 0.92, 0.25, 0.95), 2.0, true)
