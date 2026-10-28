class_name CommandDispatcher
extends Node
## Translates player intent into unit behaviour.
##
## Right click issues orders (attack / harvest / unload / move), the build
## panel drives building placement and unit production. The dispatcher never
## creates entities itself: it emits `building_placement_requested` and lets
## main.gd spawn the actual Building.

## Emitted after a placement was validated *and* the minerals were spent.
## `entry_index` is the build menu index, `pos` the world position.
signal building_placement_requested(entry_index: int, pos: Vector2)
## Emitted when the build panel is opened or closed, so that other systems can
## give up the number keys.
signal build_panel_visibility_changed(open: bool)

## Spacing of the formation grid used when several units move together.
const FORMATION_SPACING: float = 28.0
## A refinery must be placed within this distance of an ore field.
const ORE_SNAP_RADIUS: float = 60.0
## Extra world-space slack around a unit when picking it with the right button.
const UNIT_PICK_SLACK: float = 6.0
## World-space radius used to pick an ore field.
const ORE_PICK_RADIUS: float = 34.0

## Injected by main.gd. When null the dispatcher looks the manager up in the
## "selection_manager" group.
var selection: SelectionManager = null
## True while the build panel is open.
var build_panel_open: bool = false
## Active build menu index, -1 when nothing is selected.
var current_entry: int = -1
## True when the active entry is a building that is waiting to be placed.
var placement_mode: bool = false

var _menu: Array = []


func _ready() -> void:
	_menu = _build_menu()
	if selection == null and is_inside_tree():
		selection = get_tree().get_first_node_in_group("selection_manager") as SelectionManager


## The build menu entries, one dictionary per entry. The entries are the ones of
## `Game.config.build_menu`, so the indices match the ones used by the HUD:
## {"kind": "building"|"unit", "stats": BuildingStats|UnitStats,
##  "label": String, "cost": int, "hotkey": String}
func build_menu() -> Array:
	return _menu.duplicate()


## Stats of the active entry (null when nothing is active).
func current_entry_stats() -> Resource:
	var entry := _entry(current_entry)
	if entry.is_empty():
		return null
	return entry.get("stats", null)


## Cost of the active entry (0 when nothing is active).
func current_entry_cost() -> int:
	var entry := _entry(current_entry)
	if entry.is_empty():
		return 0
	return int(entry.get("cost", 0))


## Enters the build mode for a menu entry. Building entries switch to
## placement mode, unit entries wait for a left click to queue production.
func begin_placement(entry_index: int) -> void:
	var entry := _entry(entry_index)
	if entry.is_empty():
		Events.toast.emit("Unknown build entry", 2)
		return
	if not build_panel_open:
		build_panel_open = true
		build_panel_visibility_changed.emit(true)
	current_entry = entry_index
	placement_mode = _entry_kind(entry) == "building"
	Events.build_mode_changed.emit(entry_index)


## Cancels the active build entry and leaves placement mode.
func cancel_placement() -> void:
	current_entry = -1
	placement_mode = false
	Events.build_mode_changed.emit(-1)


## Opens the build panel.
func open_build_panel() -> void:
	if build_panel_open:
		return
	build_panel_open = true
	build_panel_visibility_changed.emit(true)


## Closes the build panel and cancels the active entry.
func close_build_panel() -> void:
	cancel_placement()
	if not build_panel_open:
		return
	build_panel_open = false
	build_panel_visibility_changed.emit(false)


## Toggles the build panel.
func toggle_build_panel() -> void:
	if build_panel_open:
		close_build_panel()
	else:
		open_build_panel()


## True while the build panel is open.
func is_build_panel_open() -> bool:
	return build_panel_open


## Queues a unit for production in the best matching player building.
func request_produce(entry_index: int) -> void:
	var entry := _entry(entry_index)
	if entry.is_empty():
		Events.toast.emit("Unknown build entry", 2)
		return
	if _entry_kind(entry) != "unit":
		Events.toast.emit("Select a unit entry", 2)
		return
	var stats := entry.get("stats", null) as UnitStats
	if stats == null:
		Events.toast.emit("Unknown build entry", 2)
		return
	var cost := int(entry.get("cost", stats.build_cost))
	var producer := _find_producer(stats)
	if producer == null:
		Events.toast.emit("No production building", 2)
		return
	if not Game.can_afford(cost):
		Events.toast.emit("Not enough minerals", 2)
		return
	if not Game.spend(cost):
		Events.toast.emit("Not enough minerals", 2)
		return
	if not producer.enqueue(stats):
		Game.refund(cost)
		Events.toast.emit("Production queue is full", 2)
		return
	Events.order_issued.emit({"type": "produce", "building": producer, "unit": stats.display_name})


## True when the active entry could legally be placed at `pos`.
func can_place_at(pos: Vector2) -> bool:
	var entry := _entry(current_entry)
	if entry.is_empty():
		return false
	var stats := entry.get("stats", null) as BuildingStats
	if stats == null:
		return false
	var cfg := Game.config
	if cfg != null:
		if pos.x < 0.0 or pos.y < 0.0 or pos.x > cfg.map_size.x or pos.y > cfg.map_size.y:
			return false
	if Pathfinder.is_blocked_world(pos):
		return false
	if stats.must_be_on_ore and not _has_ore_near(pos, ORE_SNAP_RADIUS):
		return false
	return true


## Moves a group of units to a position, spread over a grid so that they do
## not pile up on a single point.
func issue_move(units: Array[Unit], world_pos: Vector2) -> void:
	if units.is_empty():
		return
	var count := units.size()
	var columns := maxi(1, int(ceil(sqrt(float(count)))))
	var rows := int(ceil(float(count) / float(columns)))
	for i in count:
		var unit := units[i]
		if unit == null or not is_instance_valid(unit):
			continue
		var column := i % columns
		var row := i / columns
		var offset := Vector2(
			(float(column) - float(columns - 1) * 0.5) * FORMATION_SPACING,
			(float(row) - float(rows - 1) * 0.5) * FORMATION_SPACING
		)
		unit.move_to(world_pos + offset)
	Events.order_issued.emit({"type": "move", "pos": world_pos, "count": count})


## Orders a group of units to attack a target.
func issue_attack(units: Array[Unit], target: Unit) -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return
	var count := 0
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		unit.attack_target(target)
		count += 1
	if count == 0:
		return
	Events.order_issued.emit({"type": "attack", "target": target, "count": count})


## Orders workers to mine an ore field.
func issue_harvest(units: Array[Unit], ore: OreField) -> void:
	if ore == null or not is_instance_valid(ore):
		return
	var count := 0
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.stats == null or unit.stats.carry_capacity <= 0:
			continue
		unit.harvest(ore)
		count += 1
	if count == 0:
		return
	Events.order_issued.emit({"type": "harvest", "ore": ore, "count": count})


## Orders workers to walk to a deposit building and unload there.
func issue_deposit(units: Array[Unit], depot: Building) -> void:
	if depot == null or not is_instance_valid(depot):
		return
	var count := 0
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.stats == null or unit.stats.carry_capacity <= 0:
			continue
		var load := unit.carried
		unit.move_to(depot.global_position)
		# `move_to` resets the load, so restore it and let the worker FSM walk
		# home and unload instead of idling next to the depot.
		unit.carried = load
		if load > 0:
			unit.worker_state = Unit.WorkerState.GO_DEPOSIT
			unit.has_move_order = false
		count += 1
	if count == 0:
		return
	Events.order_issued.emit({"type": "deposit", "building": depot, "count": count})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if not mb.pressed:
			return
		if placement_mode:
			cancel_placement()
			get_viewport().set_input_as_handled()
			return
		_issue_order(_world_position(mb.position))
		get_viewport().set_input_as_handled()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if placement_mode:
		_try_place(_world_position(mb.position))
		get_viewport().set_input_as_handled()
		return
	if build_panel_open and current_entry >= 0 and _entry_is_unit(current_entry):
		request_produce(current_entry)
		get_viewport().set_input_as_handled()


func _handle_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if code == KEY_ESCAPE:
		if placement_mode or current_entry >= 0 or build_panel_open:
			close_build_panel()
			get_viewport().set_input_as_handled()
		return
	if code == KEY_B:
		toggle_build_panel()
		get_viewport().set_input_as_handled()
		return
	if code >= KEY_1 and code <= KEY_5 and build_panel_open:
		begin_placement(code - KEY_0)
		get_viewport().set_input_as_handled()


## Right click order resolution.
func _issue_order(world_pos: Vector2) -> void:
	var manager := _sel()
	if manager == null or manager.selected.is_empty():
		return
	var all := manager.selected.duplicate()

	var enemy := _enemy_unit_at(world_pos)
	if enemy != null:
		issue_attack(all, enemy)
		return

	var workers: Array[Unit] = []
	var others: Array[Unit] = []
	for unit in all:
		if unit.stats != null and unit.stats.carry_capacity > 0:
			workers.append(unit)
		else:
			others.append(unit)

	if not workers.is_empty():
		var ore := _ore_at(world_pos)
		if ore != null:
			issue_harvest(workers, ore)
			if not others.is_empty():
				issue_move(others, ore.global_position)
			return
		var depot := _deposit_at(world_pos)
		if depot != null:
			issue_deposit(workers, depot)
			if not others.is_empty():
				issue_move(others, depot.global_position)
			return

	issue_move(all, world_pos)


## Validates a placement, spends the minerals and asks main.gd to build it.
func _try_place(world_pos: Vector2) -> void:
	var entry := _entry(current_entry)
	if entry.is_empty():
		return
	var stats := entry.get("stats", null) as BuildingStats
	if stats == null:
		return
	var cost := int(entry.get("cost", stats.build_cost))
	if not Game.can_afford(cost):
		Events.toast.emit("Not enough minerals", 2)
		return
	if not can_place_at(world_pos):
		Events.toast.emit("Cannot build here", 2)
		return
	if not Game.spend(cost):
		Events.toast.emit("Not enough minerals", 2)
		return
	building_placement_requested.emit(current_entry, world_pos)
	cancel_placement()


func _find_producer(stats: UnitStats) -> Building:
	var fallback: Building = null
	for node in Game.player_buildings:
		var building := node as Building
		if building == null or not is_instance_valid(building):
			continue
		if building.stats == null or not _produces(building, stats):
			continue
		if building.can_accept_order():
			return building
		if fallback == null:
			fallback = building
	return fallback


func _produces(building: Building, stats: UnitStats) -> bool:
	for produced in building.stats.produces:
		if produced == null:
			continue
		if produced.kind == stats.kind or produced.display_name == stats.display_name:
			return true
	return false


func _enemy_unit_at(world_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_distance := INF
	for node in Game.enemy_units:
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var radius := 8.0
		if unit.stats != null:
			radius = unit.stats.radius
		var distance := unit.global_position.distance_to(world_pos)
		if distance <= radius + UNIT_PICK_SLACK and distance < best_distance:
			best_distance = distance
			best = unit
	return best


func _ore_at(world_pos: Vector2) -> OreField:
	var best: OreField = null
	var best_distance := INF
	for node in Game.ore_fields:
		var ore := node as OreField
		if ore == null or not is_instance_valid(ore) or ore.is_depleted():
			continue
		var distance := ore.global_position.distance_to(world_pos)
		if distance <= ORE_PICK_RADIUS and distance < best_distance:
			best_distance = distance
			best = ore
	return best


func _deposit_at(world_pos: Vector2) -> Building:
	var best: Building = null
	var best_distance := INF
	for node in Game.player_buildings:
		var building := node as Building
		if building == null or not is_instance_valid(building) or building.stats == null:
			continue
		if building.kind != 0 and building.kind != 2:
			# Only the HQ and the refinery unload cargo.
			continue
		if building.stats.deposit_radius <= 0.0:
			continue
		var tolerance := maxf(24.0, building.stats.size.x * 0.5 + 10.0)
		var distance := building.global_position.distance_to(world_pos)
		if distance <= tolerance and distance < best_distance:
			best_distance = distance
			best = building
	return best


func _has_ore_near(pos: Vector2, radius: float) -> bool:
	for node in Game.ore_fields:
		var ore := node as OreField
		if ore == null or not is_instance_valid(ore) or ore.is_depleted():
			continue
		if ore.global_position.distance_to(pos) <= radius:
			return true
	return false


func _entry(entry_index: int) -> Dictionary:
	if entry_index < 0 or entry_index >= _menu.size():
		return {}
	var raw = _menu[entry_index]
	if raw is Dictionary:
		return raw
	return {}


func _entry_is_unit(entry_index: int) -> bool:
	var entry := _entry(entry_index)
	return _entry_kind(entry) == "unit"


## "building" or "unit". Falls back to the type of the stats resource.
func _entry_kind(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	var kind := String(entry.get("kind", ""))
	if kind != "":
		return kind
	var stats = entry.get("stats", null)
	if stats is BuildingStats:
		return "building"
	if stats is UnitStats:
		return "unit"
	return ""


## Builds the build menu. `Game.config.build_menu` is used when the config
## exposes it, otherwise the five documented entries are derived from the
## building and unit stats of the config. The entries are used verbatim so
## that the indices match the ones of the HUD build panel.
func _build_menu() -> Array:
	var menu: Array = []
	var cfg := Game.config
	if cfg == null:
		return menu
	if _has_property(cfg, "build_menu"):
		var raw = cfg.get("build_menu")
		if raw is Array:
			for item in raw:
				var entry := _normalise_entry(item)
				if not entry.is_empty():
					menu.append(entry)
			if not menu.is_empty():
				return menu
	if cfg.barracks_stats != null:
		menu.append(_building_entry(cfg.barracks_stats, "Barracks", "1"))
	if cfg.refinery_stats != null:
		menu.append(_building_entry(cfg.refinery_stats, "Refinery", "2"))
	if cfg.infantry_stats != null:
		menu.append(_unit_entry(cfg.infantry_stats, "Infantry", "3"))
	if cfg.tank_stats != null:
		menu.append(_unit_entry(cfg.tank_stats, "Tank", "4"))
	if cfg.worker_stats != null:
		menu.append(_unit_entry(cfg.worker_stats, "Worker", "5"))
	return menu


func _building_entry(stats: BuildingStats, label: String, hotkey: String) -> Dictionary:
	return {"kind": "building", "stats": stats, "label": label, "cost": stats.build_cost, "hotkey": hotkey}


func _unit_entry(stats: UnitStats, label: String, hotkey: String) -> Dictionary:
	return {"kind": "unit", "stats": stats, "label": label, "cost": stats.build_cost, "hotkey": hotkey}


func _normalise_entry(item: Variant) -> Dictionary:
	if item is BuildingStats:
		return _building_entry(item, item.display_name, "")
	if item is UnitStats:
		return _unit_entry(item, item.display_name, "")
	if not (item is Dictionary):
		return {}
	var source: Dictionary = item
	var stats = source.get("stats", null)
	var kind := String(source.get("kind", ""))
	if kind == "":
		kind = String(source.get("type", ""))
	if kind == "":
		if stats is BuildingStats:
			kind = "building"
		elif stats is UnitStats:
			kind = "unit"
	var cost := int(source.get("cost", 0))
	if cost <= 0 and stats != null:
		cost = stats.build_cost
	var label := String(source.get("label", ""))
	if label == "":
		label = String(source.get("name", ""))
	if label == "" and stats != null:
		label = stats.display_name
	var hotkey := String(source.get("hotkey", ""))
	return {"kind": kind, "stats": stats, "label": label, "cost": cost, "hotkey": hotkey}


func _has_property(object: Object, property_name: String) -> bool:
	for info in object.get_property_list():
		if String(info.get("name", "")) == property_name:
			return true
	return false


func _sel() -> SelectionManager:
	if selection != null and is_instance_valid(selection):
		return selection
	if is_inside_tree():
		var node := get_tree().get_first_node_in_group("selection_manager")
		if node != null:
			selection = node as SelectionManager
	return selection


func _world_position(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos
