extends Node
## Headless acceptance test for the RTS demo.
##
## Run it with:
##   godot --headless --path . res://tests/SmokeTest.tscn --fixed-fps 60
##
## `--fixed-fps` disables real-time synchronisation, so the simulation runs as
## fast as the CPU allows: 3300 frames equals 55 in-game seconds and finishes
## in a couple of wall-clock seconds.
##
## The test boots the real Main scene and asserts the parts of the acceptance
## checklist in docs/DESIGN.md §11 that can be observed programmatically.
##
## It runs as its own scene (not via `--script`) on purpose: a custom MainLoop
## skips autoload registration, so the `Game` and `Events` singletons would
## not exist.

const MAIN_SCENE := "res://scenes/Main.tscn"

const FRAME_INITIAL: int = 120    # 2 s
const FRAME_AI_BUILDS: int = 900  # 15 s
const FRAME_ECONOMY: int = 2400   # 40 s
const FRAME_BUILD: int = 2700     # 45 s
const FRAME_ATTACK: int = 2900    # 48 s
const FRAME_COMBAT: int = 3200    # 53 s
const FRAME_DONE: int = 3300      # 55 s

var main: Node = null
var frames: int = 0
var failures: Array[String] = []
var checks: int = 0

var _enemy_hq: Building = null
var _hq_health_before: float = 0.0


func _ready() -> void:
	print("[smoke] booting Main scene...")
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		failures.append("Main.tscn failed to load")
		_finish()
		return
	main = packed.instantiate()
	add_child(main)


func _process(_delta: float) -> void:
	frames += 1

	if frames == FRAME_INITIAL:
		_check_initial_state()
		_check_pathfinding()
	elif frames == FRAME_AI_BUILDS:
		_check_ai_economy()
	elif frames == FRAME_ECONOMY:
		_check_player_economy()
		_check_ai_production()
	elif frames == FRAME_BUILD:
		_check_build_placement()
	elif frames == FRAME_ATTACK:
		_begin_attack()
	elif frames == FRAME_COMBAT:
		_check_combat()
	elif frames >= FRAME_DONE:
		_finish()


# ------------------------------------------------------------------ checks
func _check_initial_state() -> void:
	_check(Game.player_buildings.size() == 1, "player should start with exactly one building (HQ)")
	_check(Game.enemy_buildings.size() == 1, "enemy should start with exactly one building (HQ)")
	_check(Game.player_units.size() >= 3, "player should start with at least 3 units (got %d)" % Game.player_units.size())
	_check(Game.enemy_units.size() >= 3, "enemy should start with at least 3 units (got %d)" % Game.enemy_units.size())
	_check(Game.ore_fields.size() == 5, "map should have 5 ore fields (got %d)" % Game.ore_fields.size())
	_check(Game.minerals == Game.config.start_minerals, "player should start with %d minerals" % Game.config.start_minerals)
	_check(not Pathfinder.is_blocked_world(Vector2(200, 200)), "map corner must be walkable")
	_check(Pathfinder.is_blocked_world(Vector2(900, 980)), "obstacle centre must be blocked")

	# Both HQs must be reachable from each other.
	var path := Pathfinder.find_path(Game.config.player_start, Game.config.enemy_start)
	_check(path.size() > 1, "a path across the map must exist (got %d points)" % path.size())

	# Workers must be actively harvesting, not idle.
	var harvesting := 0
	for node in Game.player_units:
		var unit := node as Unit
		if unit != null and unit.is_worker() and unit.worker_state != Unit.WorkerState.IDLE:
			harvesting += 1
	_check(harvesting >= 1, "starting workers should be harvesting (got %d)" % harvesting)


func _check_pathfinding() -> void:
	# A path that has to go around the big obstacle in the lower-left quadrant.
	var detour := Pathfinder.find_path(Vector2(700, 1100), Vector2(1100, 1100))
	_check(detour.size() > 1, "path around obstacle 1 must exist")
	var blocked_hits := 0
	for point in detour:
		if Pathfinder.is_blocked_world(point):
			blocked_hits += 1
	_check(blocked_hits == 0, "path must not cross blocked cells (hit %d)" % blocked_hits)

	# Unreachable goals must return an empty path rather than hanging.
	var unreachable := Pathfinder.find_path(Vector2(100, 100), Vector2(-5000, -5000))
	_check(unreachable.size() == 0, "out-of-bounds goal must yield an empty path")


func _check_ai_economy() -> void:
	var barracks := 0
	for node in Game.enemy_buildings:
		var building := node as Building
		if building != null and building.kind == 1:
			barracks += 1
	_check(barracks >= 1, "AI should have built a barracks within 15 s (got %d)" % barracks)


func _check_player_economy() -> void:
	_check(Game.minerals > Game.config.start_minerals,
		"player minerals should have grown from %d (got %d)" % [Game.config.start_minerals, Game.minerals])


func _check_ai_production() -> void:
	var combat_units := 0
	for node in Game.enemy_units:
		var unit := node as Unit
		if unit != null and unit.is_alive() and unit.stats.is_combat_unit:
			combat_units += 1
	_check(combat_units >= 2, "AI should have produced combat units (got %d)" % combat_units)


## End-to-end test of the build path: pick the Barracks entry, click the map
## at a legal spot, and verify that minerals were spent *and* that a building
## actually appeared. This is the regression guard for the
## `building_placement_requested` signal being left unconnected.
func _check_build_placement() -> void:
	var dispatcher: CommandDispatcher = main.get_node_or_null("Managers/CommandDispatcher")
	if dispatcher == null:
		failures.append("command dispatcher not found")
		return

	Game.add_minerals(500)
	var buildings_before := Game.player_buildings.size()
	var minerals_before := Game.minerals

	# Entry 0 is the Barracks.
	dispatcher.begin_placement(0)
	_check(dispatcher.placement_mode, "begin_placement must enter placement mode for a building entry")

	# Click a legal spot next to the player HQ.
	var spot := Game.config.player_start + Vector2(140.0, 40.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = get_viewport().get_canvas_transform() * spot
	dispatcher._unhandled_input(click)

	_check(Game.player_buildings.size() == buildings_before + 1,
		"placing a Barracks must create a building (had %d, now %d)" % [buildings_before, Game.player_buildings.size()])
	_check(Game.minerals == minerals_before - Game.config.barracks_stats.build_cost,
		"placing a Barracks must cost %d minerals (before %d, after %d)"
			% [Game.config.barracks_stats.build_cost, minerals_before, Game.minerals])


func _begin_attack() -> void:
	for node in Game.enemy_buildings:
		var building := node as Building
		if building != null and building.kind == 0 and building.alive:
			_enemy_hq = building
			break
	if _enemy_hq == null:
		failures.append("enemy HQ missing at attack check")
		return
	_hq_health_before = _enemy_hq.health

	# Spawn a tank next to the enemy HQ rather than marching an army across
	# the map: this check is about the damage pipeline, not about travel time.
	var units_root: Node = main.get_node_or_null("World/Entities/Units")
	if units_root == null:
		failures.append("units container not found")
		return
	var tank := Unit.new()
	tank.setup(Game.config.tank_stats, Combatant.FACTION_PLAYER,
		_enemy_hq.global_position + Vector2(150.0, 0.0))
	units_root.add_child(tank)
	tank.attack_target(_enemy_hq)

	var attackers := 0
	for node in Game.player_units:
		var unit := node as Unit
		if unit != null and unit.is_alive() and unit.stats.is_combat_unit:
			attackers += 1
	print("[smoke] spawned a player tank beside the enemy HQ (hp %.0f)" % _hq_health_before)
	_check(attackers >= 1, "player should have combat units to attack with")


func _check_combat() -> void:
	if _enemy_hq == null:
		return
	_check(_enemy_hq.health < _hq_health_before,
		"enemy HQ must take damage when attacked (before %.1f, after %.1f)" % [_hq_health_before, _enemy_hq.health])

	# The damage table: infantry is blunted by heavy armour.
	var infantry := Game.config.infantry_stats
	var tank := Game.config.tank_stats
	_check(is_equal_approx(GameConfig.damage_multiplier(infantry.kind, GameConfig.Armor.HEAVY), 0.5),
		"infantry vs heavy armour must be halved")
	_check(is_equal_approx(GameConfig.damage_multiplier(tank.kind, GameConfig.Armor.LIGHT), 1.0),
		"tank vs light armour must be full damage")
	_check(is_equal_approx(GameConfig.damage_multiplier(infantry.kind, GameConfig.Armor.STRUCTURE), 1.0),
		"infantry vs structures must be full damage")


# ------------------------------------------------------------------ report
func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("[  ok  ] ", message)
	else:
		print("[ FAIL ] ", message)
		failures.append(message)


func _finish() -> void:
	print("")
	print("[smoke] %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("[smoke] RESULT: PASS")
	else:
		for failure in failures:
			print("[smoke]   - ", failure)
		print("[smoke] RESULT: FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
