class_name CameraRig
extends Node2D
## RTS camera: keyboard / middle-drag panning, wheel zoom, smooth focus and
## map-boundary clamping.
##
## The Camera2D is created in code (this project ships no .tscn files) and is
## kept as a child of the rig at local origin, so `rig.global_position` and
## `rig.camera().global_position` always agree and external code can use
## either one. The rig is expected to sit directly under the world root so
## that world coordinates and camera coordinates match.
##
## Zoom semantics follow Godot 4: `Camera2D.zoom` above 1.0 magnifies, so a
## smaller value shows a larger part of the map.

const ZOOM_MIN: float = 0.6
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 0.2
const PAN_SPEED: float = 700.0
const PAN_SPEED_FAST: float = 1400.0
const FOCUS_SHARPNESS: float = 6.0
const FOCUS_SNAP_DISTANCE: float = 1.0

## Current zoom factor. Above 1.0 means closer to the ground.
var zoom_level: float = 1.0
## Last battle position reported through `note_battle()`.
var battle_point: Vector2 = Vector2.ZERO
## True once at least one battle position has been reported.
var has_battle_point: bool = false

var _cam: Camera2D = null
var _map_size: Vector2 = Vector2(2400.0, 1350.0)
var _focus_target: Vector2 = Vector2.ZERO
var _focusing: bool = false
var _dragging: bool = false
var _drag_screen: Vector2 = Vector2.ZERO


func _ready() -> void:
	var cfg := Game.config
	if cfg != null:
		_map_size = cfg.map_size

	_cam = Camera2D.new()
	_cam.name = "Camera"
	_cam.enabled = true
	add_child(_cam)
	_cam.make_current()
	_cam.zoom = Vector2(zoom_level, zoom_level)

	global_position = home_position()
	_clamp_to_map()


## The live Camera2D created by this rig.
func camera() -> Camera2D:
	return _cam


## Position of the player's home base (falls back to the origin).
func home_position() -> Vector2:
	var cfg := Game.config
	if cfg != null:
		return cfg.player_start
	return Vector2.ZERO


## Last battle position recorded by `note_battle()`.
func battle_position() -> Vector2:
	return battle_point


## Records the most recent battle location. External code calls this whenever
## combat happens so that `focus_battle()` has a target.
func note_battle(pos: Vector2) -> void:
	battle_point = pos
	has_battle_point = true


## Smoothly moves the camera towards a world position.
func focus(pos: Vector2) -> void:
	_focus_target = pos
	_focusing = true


## Smoothly returns the camera to the player base.
func focus_home() -> void:
	focus(home_position())


## Focuses the most recent battle, or the base when no battle was recorded.
func focus_battle() -> void:
	if has_battle_point:
		focus(battle_point)
	else:
		focus_home()


## Changes the zoom by a delta (positive zooms in). Clamped to the legal range.
func zoom_by(delta: float) -> void:
	set_zoom_level(zoom_level + delta)


## Sets an absolute zoom value, snapped to the 0.2 step grid.
func set_zoom_level(value: float) -> void:
	zoom_level = clampf(snappedf(value, ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
	if _cam != null:
		_cam.zoom = Vector2(zoom_level, zoom_level)
	_clamp_to_map()


## Moves the camera by a world-space delta.
func pan(delta_world: Vector2) -> void:
	_focusing = false
	global_position += delta_world
	_clamp_to_map()


func _process(delta: float) -> void:
	_process_pan(delta)
	_process_focus(delta)
	_clamp_to_map()


func _process_pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if _action_down("cam_up") or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	# Arrow-down always pans the camera. `S` doubles as the stop order, so it
	# only pans while nothing is selected — holding it can never cancel the
	# player's army by accident.
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	elif not _has_selection() and Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if _action_down("cam_left") or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if _action_down("cam_right") or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir == Vector2.ZERO:
		return

	_focusing = false
	var speed := PAN_SPEED
	if _action_down("cam_boost") or Input.is_key_pressed(KEY_SHIFT):
		speed = PAN_SPEED_FAST
	global_position += dir.normalized() * speed * delta


func _process_focus(delta: float) -> void:
	if not _focusing:
		return
	var weight := clampf(delta * FOCUS_SHARPNESS, 0.0, 1.0)
	global_position = global_position.lerp(_focus_target, weight)
	if global_position.distance_to(_focus_target) <= FOCUS_SNAP_DISTANCE:
		global_position = _focus_target
		_focusing = false


## Keeps the visible rectangle inside the map rectangle.
func _clamp_to_map() -> void:
	var half := _visible_half()
	global_position.x = _clamp_axis(global_position.x, half.x, _map_size.x)
	global_position.y = _clamp_axis(global_position.y, half.y, _map_size.y)


func _clamp_axis(value: float, half: float, extent: float) -> float:
	var low := half
	var high := extent - half
	if low >= high:
		# The map is smaller than the visible area: centre it instead.
		return extent * 0.5
	return clampf(value, low, high)


## Half size of the visible world rectangle, accounting for zoom and stretch.
func _visible_half() -> Vector2:
	var view := get_viewport_rect().size
	var scale := get_viewport().get_canvas_transform().get_scale()
	if scale.x <= 0.0 or scale.y <= 0.0:
		scale = Vector2.ONE
	return Vector2(view.x / (2.0 * scale.x), view.y / (2.0 * scale.y))


func _action_down(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


## True when the player currently has units selected. Used to decide whether
## `S` means "stop the selection" or "pan the camera down".
func _has_selection() -> bool:
	var manager := get_tree().get_first_node_in_group("selection_manager")
	if manager == null:
		return false
	var selected: Variant = manager.get("selected")
	return selected is Array and not (selected as Array).is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				zoom_by(ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom_by(-ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_dragging = true
				_drag_screen = mb.position
			else:
				_dragging = false
	elif event is InputEventMouseMotion:
		if not _dragging:
			return
		var mm := event as InputEventMouseMotion
		var delta_screen := mm.position - _drag_screen
		_drag_screen = mm.position
		if delta_screen == Vector2.ZERO:
			return
		_focusing = false
		# Convert the screen delta into a world delta (scale only, no offset).
		var inverse := get_viewport().get_canvas_transform().affine_inverse()
		global_position -= inverse.basis_xform(delta_screen)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_H or key.physical_keycode == KEY_H:
			focus_home()
		elif key.keycode == KEY_SPACE or key.physical_keycode == KEY_SPACE:
			focus_battle()
