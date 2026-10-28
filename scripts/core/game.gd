extends Node
## Global game state autoload.
##
## Deliberately contains no references to custom `class_name` types: this
## script is loaded before any scene, and typing it against `Unit` or
## `Building` would create a cyclic dependency that Godot 4 refuses to
## resolve. Registries therefore hold plain `Node2D` references.

enum MatchResult { ONGOING = 0, VICTORY = 1, DEFEAT = 2, DRAW = 3 }

var config: GameConfig = null
var minerals: int = 0
var elapsed: float = 0.0
var match_length: float = 1200.0
var result: int = MatchResult.ONGOING
var paused: bool = false

# --- registries (untyped on purpose, see class docs above) ---
var player_units: Array[Node2D] = []
var enemy_units: Array[Node2D] = []
var player_buildings: Array[Node2D] = []
var enemy_buildings: Array[Node2D] = []
var ore_fields: Array[Node2D] = []

# --- statistics for the end-of-match panel ---
var stat_minerals_gathered: int = 0
var stat_units_built: int = 0
var stat_kills: int = 0

var _timer_accum: float = 0.0


func _ready() -> void:
	config = GameConfig.create_default()
	minerals = config.start_minerals
	match_length = config.match_length
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if result != MatchResult.ONGOING or paused:
		return
	elapsed += delta
	_timer_accum += delta
	if _timer_accum >= 0.25:
		_timer_accum = 0.0
		Events.match_timer_updated.emit(maxf(0.0, match_length - elapsed))
	_prune_invalid()


## Drops entries whose node was freed without unregistering itself. Registries
## are the single source of truth for "who is alive", so a stale entry would
## make the HUD, the minimap and the AI disagree with the scene.
func _prune_invalid() -> void:
	_prune_array(player_units)
	_prune_array(enemy_units)
	_prune_array(player_buildings)
	_prune_array(enemy_buildings)
	_prune_array(ore_fields)


func _prune_array(target: Array[Node2D]) -> void:
	var index := target.size() - 1
	while index >= 0:
		if not is_instance_valid(target[index]):
			target.remove_at(index)
		index -= 1


func add_minerals(amount: int) -> void:
	if amount == 0:
		return
	minerals = clampi(minerals + amount, 0, config.mineral_cap)
	if amount > 0:
		stat_minerals_gathered += amount
	Events.minerals_changed.emit(minerals, amount)


func can_afford(cost: int) -> bool:
	return minerals >= cost


func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	minerals -= cost
	Events.minerals_changed.emit(minerals, -cost)
	return true


func refund(amount: int) -> void:
	if amount <= 0:
		return
	minerals = clampi(minerals + amount, 0, config.mineral_cap)
	Events.minerals_changed.emit(minerals, amount)


func time_remaining() -> float:
	return maxf(0.0, match_length - elapsed)


func time_text() -> String:
	var t := int(time_remaining())
	return "%02d:%02d" % [t / 60, t % 60]


func end_match(new_result: int) -> void:
	if result != MatchResult.ONGOING:
		return
	result = new_result
	Events.match_ended.emit(result)


func reset() -> void:
	minerals = config.start_minerals
	elapsed = 0.0
	_timer_accum = 0.0
	result = MatchResult.ONGOING
	paused = false
	stat_minerals_gathered = 0
	stat_units_built = 0
	stat_kills = 0
	player_units.clear()
	enemy_units.clear()
	player_buildings.clear()
	enemy_buildings.clear()
	ore_fields.clear()
	Events.minerals_changed.emit(minerals, 0)


## Registers a unit in the appropriate registry.
func register_unit(unit: Node2D, is_player: bool) -> void:
	if is_player:
		player_units.append(unit)
	else:
		enemy_units.append(unit)


func unregister_unit(unit: Node2D, is_player: bool) -> void:
	if is_player:
		player_units.erase(unit)
	else:
		enemy_units.erase(unit)


func register_building(building: Node2D, is_player: bool) -> void:
	if is_player:
		player_buildings.append(building)
	else:
		enemy_buildings.append(building)


func unregister_building(building: Node2D, is_player: bool) -> void:
	if is_player:
		player_buildings.erase(building)
	else:
		enemy_buildings.erase(building)
