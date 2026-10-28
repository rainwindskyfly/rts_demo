class_name AICommander
extends Node
## The enemy faction's brain.
##
## Design (docs/DESIGN.md §4.8) defines six behaviours. They are evaluated on a
## fixed 2 s tick rather than every frame, which keeps the AI cheap and makes
## its decisions legible while watching the demo.
##
## The AI keeps its own mineral purse — it never touches `Game.minerals`,
## which belongs to the player.

enum AiState { DEFEND, MASS, ATTACK, PRODUCE, ECONOMY, BUILD }

const THINK_INTERVAL: float = 2.0
const ATTACK_COOLDOWN: float = 45.0
const MAX_WORKERS: int = 5
const START_MINERALS: int = 350

var enemy_minerals: int = START_MINERALS
var enemy_hq: Building = null
var enemy_barracks: Building = null
var state: int = AiState.ECONOMY

var _elapsed: float = 0.0
var _think_cd: float = 3.0
var _last_attack: float = -999.0
var _rally_point: Vector2 = Vector2.ZERO
var _unit_root: Node2D = null
var _building_root: Node2D = null
var _config: GameConfig = null


func setup(hq: Building, unit_root: Node2D, building_root: Node2D) -> void:
	enemy_hq = hq
	_unit_root = unit_root
	_building_root = building_root
	_config = Game.config
	_rally_point = hq.global_position + Vector2(-90, 60)
	Events.enemy_minerals_gained.connect(_on_minerals_gained)


func _on_minerals_gained(amount: int) -> void:
	enemy_minerals += amount


func _process(delta: float) -> void:
	if Game.result != Game.MatchResult.ONGOING:
		return
	_elapsed += delta
	_think_cd -= delta
	if _think_cd > 0.0:
		return
	_think_cd = THINK_INTERVAL
	_think()


func _think() -> void:
	if enemy_hq == null or not is_instance_valid(enemy_hq) or not enemy_hq.alive:
		return

	_ensure_economy()
	_ensure_barracks()
	_ensure_production()
	_assign_workers()
	_update_combat_state()


# ------------------------------------------------------------------ economy
func _ensure_economy() -> void:
	var workers := _workers()
	if workers.size() >= MAX_WORKERS:
		return
	# Grow the work force early, then top up.
	var wanted := 2 if _elapsed < 30.0 else 4
	if workers.size() >= wanted:
		return
	if enemy_minerals < _config.worker_stats.build_cost:
		return
	if enemy_hq.finished and enemy_hq.can_accept_order():
		enemy_minerals -= _config.worker_stats.build_cost
		enemy_hq.enqueue(_config.worker_stats)


func _ensure_barracks() -> void:
	if enemy_barracks != null and is_instance_valid(enemy_barracks) and enemy_barracks.alive:
		return
	if _elapsed < 12.0:
		return
	if enemy_minerals < _config.barracks_stats.build_cost:
		return
	var spot := _find_free_spot(enemy_hq.global_position + Vector2(-150, -40), 150.0)
	if spot == Vector2.INF:
		return
	enemy_minerals -= _config.barracks_stats.build_cost
	enemy_barracks = _spawn_building(_config.barracks_stats, spot)


func _ensure_production() -> void:
	if enemy_barracks == null or not is_instance_valid(enemy_barracks) or not enemy_barracks.alive:
		return
	if not enemy_barracks.finished:
		return
	var army := _combat_units()
	# Keep a healthy standing army, but do not bankrupt the economy.
	var target_army := 8 if _elapsed > 90.0 else 5
	if army.size() >= target_army:
		return
	if enemy_minerals < _config.infantry_stats.build_cost:
		return
	# A 1 tank : 3 infantry mix, matching the design document.
	var want_tank := army.size() > 0 and army.size() % 4 == 3
	var chosen := _config.tank_stats if want_tank else _config.infantry_stats
	if enemy_minerals < chosen.build_cost:
		chosen = _config.infantry_stats
		if enemy_minerals < chosen.build_cost:
			return
	enemy_minerals -= chosen.build_cost
	enemy_barracks.enqueue(chosen)


func _assign_workers() -> void:
	for worker in _workers():
		if worker.worker_state != Unit.WorkerState.IDLE:
			continue
		var ore := _nearest_ore(worker.global_position)
		if ore != null:
			worker.harvest(ore)


# ------------------------------------------------------------------- combat
func _update_combat_state() -> void:
	var army := _combat_units()
	if army.is_empty():
		state = AiState.PRODUCE
		return

	var threats := _threats_near_hq()
	if not threats.is_empty():
		state = AiState.DEFEND
		for unit in army:
			unit.attack_target(threats[0])
		return

	if army.size() >= 6:
		if state != AiState.ATTACK:
			state = AiState.MASS
			for unit in army:
				unit.move_to(_rally_point)
		if _elapsed - _last_attack >= ATTACK_COOLDOWN:
			state = AiState.ATTACK
			_last_attack = _elapsed
			var target := _player_hq()
			if target != null:
				for unit in army:
					unit.attack_target(target)
		elif state == AiState.ATTACK:
			# Keep pushing: re-issue the order so stragglers re-engage.
			var target := _player_hq()
			if target != null:
				for unit in army:
					if unit.target == null or not unit.target.alive:
						unit.attack_target(target)
		return

	state = AiState.PRODUCE


# ------------------------------------------------------------------ helpers
func _workers() -> Array[Unit]:
	var result: Array[Unit] = []
	for node in Game.enemy_units:
		var unit := node as Unit
		if unit != null and unit.is_alive() and unit.is_worker():
			result.append(unit)
	return result


func _combat_units() -> Array[Unit]:
	var result: Array[Unit] = []
	for node in Game.enemy_units:
		var unit := node as Unit
		if unit != null and unit.is_alive() and unit.stats.is_combat_unit:
			result.append(unit)
	return result


func _threats_near_hq() -> Array[Unit]:
	var result: Array[Unit] = []
	if enemy_hq == null or not is_instance_valid(enemy_hq):
		return result
	for node in Game.player_units:
		var unit := node as Unit
		if unit == null or not unit.is_alive():
			continue
		if unit.global_position.distance_to(enemy_hq.global_position) <= 500.0:
			result.append(unit)
	return result


func _player_hq() -> Building:
	for node in Game.player_buildings:
		var building := node as Building
		if building != null and building.is_player_building() and building.kind == 0 and building.alive:
			return building
	return null


func _nearest_ore(from: Vector2) -> OreField:
	var best: OreField = null
	var best_distance := INF
	for node in Game.ore_fields:
		var ore := node as OreField
		if ore == null or ore.is_depleted():
			continue
		var distance := from.distance_to(ore.global_position)
		if distance < best_distance:
			best_distance = distance
			best = ore
	return best


func _spawn_building(building_stats: BuildingStats, spot: Vector2) -> Building:
	if _building_root == null:
		return null
	var building := Building.new()
	building.setup(building_stats, Combatant.FACTION_ENEMY, spot)
	_building_root.add_child(building)
	return building


## Spiral outwards from `near` looking for a spot that is not blocked and does
## not collide with an existing building.
func _find_free_spot(near: Vector2, radius: float) -> Vector2:
	for attempt in 32:
		var angle := TAU * float(attempt) / 16.0
		var distance := radius * (0.35 + 0.65 * float(attempt) / 32.0)
		var candidate := near + Vector2(cos(angle), sin(angle)) * distance
		if candidate.x < 40.0 or candidate.y < 40.0:
			continue
		if candidate.x > Game.config.map_size.x - 40.0 or candidate.y > Game.config.map_size.y - 40.0:
			continue
		if Pathfinder.is_blocked_world(candidate):
			continue
		if _overlaps_building(candidate, 42.0):
			continue
		return candidate
	return Vector2.INF


func _overlaps_building(point: Vector2, clearance: float) -> bool:
	for node in Game.enemy_buildings:
		var building := node as Building
		if building == null or not is_instance_valid(building):
			continue
		if building.global_position.distance_to(point) < clearance:
			return true
	return false
