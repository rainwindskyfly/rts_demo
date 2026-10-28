class_name SelectionManager
extends Node
## Box selection, click selection and control groups for the player.
##
## All picking happens in *screen* space: a unit is projected with
## `get_viewport().get_canvas_transform() * unit.global_position` and then
## compared against the mouse rectangle. That keeps the behaviour identical at
## every zoom level, because the drag rectangle is drawn by the UI layer in
## screen coordinates as well.
##
## The drag rectangle is never drawn here. The UI layer listens to
## `drag_rect_changed` / `drag_rect_cleared` and renders it.

## Emitted while the player drags a selection rectangle (screen space).
signal drag_rect_changed(rect: Rect2)
## Emitted when the drag rectangle must be removed from the UI layer.
signal drag_rect_cleared()
## Emitted after a control group was recalled, so the order layer can issue the
## "move to the cursor" order that completes the recall.
signal group_recalled(units: Array[Unit])

## Screen-space radius used to pick a unit with a single click.
const PICK_RADIUS: float = 24.0
## Minimum drag distance (screen px) before a click turns into a box select.
const DRAG_THRESHOLD: float = 6.0
## Fraction of a unit's footprint that must be covered by the box.
const OVERLAP_RATIO: float = 0.30
## Maximum number of units stored per control group.
const MAX_GROUP_SIZE: int = 20
## Lowest / highest control group index.
const GROUP_MIN: int = 1
const GROUP_MAX: int = 9

## The currently selected player units.
var selected: Array[Unit] = []
## Control group index -> Array[Unit].
var control_groups: Dictionary = {}

## True while the build panel owns the number keys. Set by main.gd through
## `set_build_panel_open()` (or `CommandDispatcher.build_panel_visibility_changed`).
var build_panel_open: bool = false
## True while a build entry is active. Mirrors `Events.build_mode_changed`.
var build_mode_active: bool = false

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_announced: bool = false


func _ready() -> void:
	add_to_group("selection_manager")
	Events.unit_died.connect(_on_unit_died)
	Events.build_mode_changed.connect(_on_build_mode_changed)


## Tells the selection manager that the build panel is open (or closed), so
## that the number keys can be routed to the build menu instead of the groups.
func set_build_panel_open(open: bool) -> void:
	build_panel_open = open


## Selects a single unit. With `additive` the unit is added to the current
## selection, otherwise the selection is replaced.
func select(unit: Unit, additive: bool) -> void:
	if unit == null or not is_instance_valid(unit) or not unit.is_alive():
		return
	if not additive:
		_clear_silent()
	_add_unit(unit)
	_emit_changed()


## Removes every unit from the selection and notifies listeners.
func clear() -> void:
	_clear_silent()
	_emit_changed()


## Selects every living player combat unit (workers are excluded).
func select_all_combat() -> void:
	_clear_silent()
	for unit in _player_units():
		if unit.stats != null and not unit.stats.is_combat_unit:
			continue
		_add_unit(unit)
	_emit_changed()


## Returns the living player units that fall inside a screen-space rectangle.
## A unit is included when its centre is inside the box, or when the box
## covers at least 30% of its footprint.
func units_in_rect(r: Rect2) -> Array[Unit]:
	var found: Array[Unit] = []
	var xform := get_viewport().get_canvas_transform()
	var scale := xform.get_scale().x
	for unit in _player_units():
		var screen_pos: Vector2 = xform * unit.global_position
		if r.has_point(screen_pos):
			found.append(unit)
			continue
		var half_world := 8.0
		if unit.stats != null:
			half_world = maxf(6.0, unit.stats.radius)
		var half := half_world * scale
		var footprint := Rect2(screen_pos - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
		var overlap := footprint.intersection(r)
		if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
			continue
		var total := footprint.size.x * footprint.size.y
		if total <= 0.0:
			continue
		if overlap.size.x * overlap.size.y / total >= OVERLAP_RATIO:
			found.append(unit)
	return found


## Appends the current selection to control group `n` (max 20 living units).
func add_to_group_n(n: int) -> void:
	if n < GROUP_MIN or n > GROUP_MAX:
		return
	var group: Array[Unit] = []
	var previous: Array = control_groups.get(n, [])
	for entry in previous:
		if entry is Unit and is_instance_valid(entry) and entry.is_alive() and not group.has(entry):
			group.append(entry)
	for unit in selected:
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		if group.has(unit):
			continue
		if group.size() >= MAX_GROUP_SIZE:
			break
		group.append(unit)
	control_groups[n] = group


## Returns control group `n` and selects every unit in it.
func recall_group_n(n: int) -> Array[Unit]:
	var group: Array[Unit] = []
	if control_groups.has(n):
		var raw = control_groups[n]
		if raw is Array:
			for entry in raw:
				if entry is Unit and is_instance_valid(entry) and entry.is_alive() and not group.has(entry):
					group.append(entry)
	control_groups[n] = group
	_clear_silent()
	for unit in group:
		_add_unit(unit)
	_emit_changed()
	group_recalled.emit(group)
	return group


## Living members of control group `n`.
func get_group(n: int) -> Array[Unit]:
	var group: Array[Unit] = []
	if control_groups.has(n):
		var raw = control_groups[n]
		if raw is Array:
			for entry in raw:
				if entry is Unit and is_instance_valid(entry) and entry.is_alive() and not group.has(entry):
					group.append(entry)
	return group


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if build_mode_active:
				# The build panel owns the left button right now.
				return
			_drag_start = mb.position
			_dragging = true
			_drag_announced = false
			return
		if not _dragging:
			return
		_dragging = false
		if _drag_announced:
			drag_rect_cleared.emit()
		var rect := Rect2(_drag_start, mb.position).abs()
		if _drag_start.distance_to(mb.position) > DRAG_THRESHOLD:
			_apply_area(rect, mb.shift_pressed)
		else:
			_apply_click(mb.position, mb.shift_pressed)
	elif event is InputEventMouseMotion:
		if not _dragging:
			return
		var mm := event as InputEventMouseMotion
		if _drag_start.distance_to(mm.position) <= DRAG_THRESHOLD:
			return
		_drag_announced = true
		drag_rect_changed.emit(Rect2(_drag_start, mm.position).abs())
	elif event is InputEventKey:
		_handle_key(event as InputEventKey)


func _handle_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if key.ctrl_pressed:
		if code == KEY_A:
			select_all_combat()
			get_viewport().set_input_as_handled()
			return
		if code >= KEY_1 and code <= KEY_9:
			add_to_group_n(code - KEY_0)
			get_viewport().set_input_as_handled()
			return
		return
	if build_panel_open or build_mode_active:
		# The number keys belong to the build panel while it is open.
		return
	if code >= KEY_1 and code <= KEY_9:
		recall_group_n(code - KEY_0)
		get_viewport().set_input_as_handled()


func _apply_click(screen_pos: Vector2, additive: bool) -> void:
	var xform := get_viewport().get_canvas_transform()
	var scale := xform.get_scale().x
	var best: Unit = null
	var best_distance := INF
	for unit in _player_units():
		var screen_pos_unit: Vector2 = xform * unit.global_position
		var distance := screen_pos_unit.distance_to(screen_pos)
		var radius_world := 8.0
		if unit.stats != null:
			radius_world = unit.stats.radius
		var tolerance := maxf(PICK_RADIUS, radius_world * scale)
		if distance <= tolerance and distance < best_distance:
			best_distance = distance
			best = unit

	if best == null:
		if not additive:
			clear()
		return
	if not additive:
		_clear_silent()
	_add_unit(best)
	_emit_changed()


func _apply_area(rect: Rect2, additive: bool) -> void:
	var hits := units_in_rect(rect)
	if not additive:
		_clear_silent()
	for unit in hits:
		_add_unit(unit)
	_emit_changed()


func _add_unit(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if selected.has(unit):
		return
	unit.set_selected(true)
	selected.append(unit)


func _clear_silent() -> void:
	for unit in selected:
		if is_instance_valid(unit):
			unit.set_selected(false)
	selected.clear()


func _emit_changed() -> void:
	Events.selection_changed.emit(selected)


func _player_units() -> Array[Unit]:
	var found: Array[Unit] = []
	for node in get_tree().get_nodes_in_group("player_units"):
		var unit := node as Unit
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if unit.faction != 0:
			continue
		found.append(unit)
	return found


func _on_unit_died(unit: Node, _killer: Node) -> void:
	var changed := false
	if unit is Unit and selected.has(unit):
		selected.erase(unit)
		changed = true
	for key in control_groups.keys():
		var raw = control_groups[key]
		if not (raw is Array):
			continue
		if raw.has(unit):
			raw.erase(unit)
			changed = true
	if changed:
		_emit_changed()


func _on_build_mode_changed(entry: int) -> void:
	build_mode_active = entry >= 0
