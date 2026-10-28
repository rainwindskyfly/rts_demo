extends Node2D
## Scene bootstrap and integration layer.
##
## The whole game is assembled in code — there is exactly one scene file
## (`scenes/Main.tscn`) which contains nothing but this script. That keeps the
## project free of hand-authored .tscn resources that could reference stale
## scripts, and it makes the entire wiring readable in one place.

const PLAYER_FACTION: int = Combatant.FACTION_PLAYER
const ENEMY_FACTION: int = Combatant.FACTION_ENEMY

# --- scene references ---
var world: Node2D = null
var map_root: MapBuilder = null
var entities: Node2D = null
var units_root: Node2D = null
var buildings_root: Node2D = null
var ore_root: Node2D = null
var camera_rig: CameraRig = null
var hud: HUD = null
var minimap: MiniMap = null
var drag_rect: DragRect = null
var selection: SelectionManager = null
var commands: CommandDispatcher = null
var ai: AICommander = null

# --- gameplay state ---
var player_hq: Building = null
var enemy_hq: Building = null
var _preview: ColorRect = null
var _preview_entry: int = -1


func _ready() -> void:
	InputSetup.apply()
	_build_tree()
	_build_world()
	_spawn_forces()
	_wire()


# ------------------------------------------------------------------- setup
func _build_tree() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)

	# The map is added to the tree BEFORE the entity containers. Sibling draw
	# order follows tree order, so the ground polygon would otherwise be
	# painted on top of the ore fields.
	map_root = MapBuilder.new()
	map_root.name = "Map"
	world.add_child(map_root)

	entities = Node2D.new()
	entities.name = "Entities"
	world.add_child(entities)

	units_root = Node2D.new()
	units_root.name = "Units"
	entities.add_child(units_root)

	buildings_root = Node2D.new()
	buildings_root.name = "Buildings"
	entities.add_child(buildings_root)

	ore_root = Node2D.new()
	ore_root.name = "OreFields"
	entities.add_child(ore_root)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	world.add_child(camera_rig)

	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)

	drag_rect = DragRect.new()
	drag_rect.name = "DragRect"
	drag_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(drag_rect)

	hud = HUD.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(hud)

	minimap = MiniMap.new()
	minimap.name = "MiniMap"
	ui_layer.add_child(minimap)

	var managers := Node.new()
	managers.name = "Managers"
	add_child(managers)

	selection = SelectionManager.new()
	selection.name = "SelectionManager"
	managers.add_child(selection)

	commands = CommandDispatcher.new()
	commands.name = "CommandDispatcher"
	managers.add_child(commands)

	ai = AICommander.new()
	ai.name = "AICommander"
	managers.add_child(ai)


func _build_world() -> void:
	map_root.build(Game.config, ore_root)


func _spawn_forces() -> void:
	player_hq = _spawn_building(Game.config.hq_stats, Game.config.player_start, PLAYER_FACTION)
	enemy_hq = _spawn_building(Game.config.hq_stats, Game.config.enemy_start, ENEMY_FACTION)

	# Identical opening forces for both sides.
	for i in Game.config.starting_workers:
		_spawn_unit(Game.config.worker_stats, PLAYER_FACTION, _ring(Game.config.player_start, 70.0, i))
		_spawn_unit(Game.config.worker_stats, ENEMY_FACTION, _ring(Game.config.enemy_start, 70.0, i))
	for i in Game.config.starting_infantry:
		_spawn_unit(Game.config.infantry_stats, PLAYER_FACTION, _ring(Game.config.player_start, 96.0, i + 3))
		_spawn_unit(Game.config.infantry_stats, ENEMY_FACTION, _ring(Game.config.enemy_start, 96.0, i + 3))

	ai.setup(enemy_hq, units_root, buildings_root)
	camera_rig.focus_home()
	_auto_assign_starting_workers()


## Sends the opening workers straight to the home ore field. The economy loop
## is the first thing a player should see working, so the demo does not make
## them discover the harvest order before anything happens on screen.
func _auto_assign_starting_workers() -> void:
	for node in Game.player_units:
		var unit := node as Unit
		if unit == null or not unit.is_worker():
			continue
		if unit.worker_state != Unit.WorkerState.IDLE:
			continue
		var ore := _nearest_ore(unit.global_position)
		if ore != null:
			unit.harvest(ore)


func _nearest_ore(from: Vector2) -> OreField:
	var best: OreField = null
	var best_distance := INF
	for node in Game.ore_fields:
		var ore := node as OreField
		if ore == null or not is_instance_valid(ore) or ore.is_depleted():
			continue
		var distance := from.distance_to(ore.global_position)
		if distance < best_distance:
			best_distance = distance
			best = ore
	return best


static func _ring(centre: Vector2, radius: float, index: int) -> Vector2:
	var angle := TAU * float(index) / 6.0
	return centre + Vector2(cos(angle), sin(angle)) * radius


func _spawn_building(building_stats: BuildingStats, spot: Vector2, faction: int) -> Building:
	var building := Building.new()
	building.setup(building_stats, faction, spot)
	buildings_root.add_child(building)
	return building


func _spawn_unit(unit_stats: UnitStats, faction: int, spot: Vector2) -> Unit:
	var unit := Unit.new()
	unit.setup(unit_stats, faction, spot)
	units_root.add_child(unit)
	return unit


# ------------------------------------------------------------------- wiring
func _wire() -> void:
	selection.drag_rect_changed.connect(drag_rect.set_rect)
	selection.drag_rect_cleared.connect(drag_rect.clear_rect)
	selection.group_recalled.connect(_on_group_recalled)

	commands.selection = selection
	commands.build_panel_visibility_changed.connect(_on_build_panel_visibility_changed)
	commands.building_placement_requested.connect(_on_building_placement_requested)

	hud.build_entry_activated.connect(_on_build_entry_activated)
	hud.play_again_requested.connect(_on_play_again)

	Events.building_destroyed.connect(_on_building_destroyed)
	Events.unit_died.connect(_on_unit_died)
	Events.build_mode_changed.connect(_on_build_mode_changed)

	_build_preview()


func _build_preview() -> void:
	_preview = ColorRect.new()
	_preview.name = "BuildPreview"
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.visible = false
	_preview.size = Vector2(40, 40)
	add_child(_preview)


# -------------------------------------------------------------- build order
func _on_build_entry_activated(index: int) -> void:
	if index < 0:
		commands.cancel_placement()
		return
	var entry := _build_entry(index)
	if entry.is_empty():
		return
	if String(entry.get("kind", "")) == "building":
		commands.begin_placement(index)
	else:
		# CommandDispatcher owns affordability, producer lookup and the
		# actual refund-on-failure path, so it is not duplicated here.
		commands.request_produce(index)


func _build_entry(index: int) -> Dictionary:
	var menu: Array[Dictionary] = Game.config.build_menu
	if index < 0 or index >= menu.size():
		return {}
	return menu[index]


func _on_build_panel_visibility_changed(open: bool) -> void:
	selection.set_build_panel_open(open)


func _on_building_placement_requested(entry_index: int, spot: Vector2) -> void:
	if entry_index < 0 or entry_index >= Game.config.build_menu.size():
		return
	var entry: Dictionary = Game.config.build_menu[entry_index]
	var building_stats: BuildingStats = entry["stats"]
	_spawn_building(building_stats, spot, PLAYER_FACTION)
	Events.toast.emit("%s built" % building_stats.display_name, 0)


func _on_build_mode_changed(entry: int) -> void:
	_preview_entry = entry
	if entry < 0:
		_preview.visible = false
		return
	var menu: Array[Dictionary] = Game.config.build_menu
	if entry >= menu.size() or String(menu[entry]["kind"]) != "building":
		_preview.visible = false
		return
	var building_stats: BuildingStats = menu[entry]["stats"]
	_preview.size = building_stats.size
	_preview.visible = true


func _process(_delta: float) -> void:
	_update_preview()

	# Match timeout: decide on battlefield weight.
	if Game.result == Game.MatchResult.ONGOING and Game.time_remaining() <= 0.0:
		_decide_by_weight()


func _update_preview() -> void:
	if _preview == null or not _preview.visible or _preview_entry < 0:
		return
	var menu: Array[Dictionary] = Game.config.build_menu
	if _preview_entry >= menu.size():
		return
	var world_mouse := get_global_mouse_position()
	_preview.position = world_mouse - _preview.size * 0.5
	# CommandDispatcher owns the legality rules; ask it instead of duplicating.
	var legal := commands.can_place_at(world_mouse)
	_preview.color = Color(0.3, 0.9, 0.4, 0.35) if legal else Color(0.9, 0.25, 0.2, 0.35)


# -------------------------------------------------------------- match flow
func _on_building_destroyed(building: Node) -> void:
	if building == player_hq:
		Game.end_match(Game.MatchResult.DEFEAT)
	elif building == enemy_hq:
		Game.end_match(Game.MatchResult.VICTORY)


func _on_unit_died(unit: Node, _killer: Node) -> void:
	if unit is Unit:
		camera_rig.note_battle((unit as Unit).global_position)


func _decide_by_weight() -> void:
	var player_weight := _battlefield_weight(PLAYER_FACTION)
	var enemy_weight := _battlefield_weight(ENEMY_FACTION)
	if player_weight > enemy_weight:
		Game.end_match(Game.MatchResult.VICTORY)
	elif enemy_weight > player_weight:
		Game.end_match(Game.MatchResult.DEFEAT)
	else:
		Game.end_match(Game.MatchResult.DRAW)


func _battlefield_weight(faction: int) -> float:
	var weight := 0.0
	var units: Array[Node2D] = Game.player_units if faction == PLAYER_FACTION else Game.enemy_units
	for node in units:
		var unit := node as Unit
		if unit == null or not unit.is_alive():
			continue
		if unit.kind == 0:
			weight += 1.0
		elif unit.kind == 1:
			weight += 4.0
		else:
			weight += 0.5
	var buildings: Array[Node2D] = Game.player_buildings if faction == PLAYER_FACTION else Game.enemy_buildings
	for node in buildings:
		var building := node as Building
		if building != null and building.alive:
			weight += 2.0
	return weight


func _on_play_again() -> void:
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ hotkeys
## Keyboard shortcuts that are not owned by a single system.
##
## The selection manager already handles Ctrl+A and the control-group keys
## (and consumes them), the command dispatcher owns `Esc` / `B` / the
## build-menu digits, and the camera rig only reacts to `H` and `Space`.
## Stopping the selection is the only one left for the integration layer.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if code == KEY_S:
		for unit in selection.selected:
			unit.stop()


## Recalling a control group selects it; the design document also asks for a
## move order to the cursor, which is issued here.
func _on_group_recalled(units: Array[Unit]) -> void:
	if units.is_empty():
		return
	commands.issue_move(units, get_global_mouse_position())
