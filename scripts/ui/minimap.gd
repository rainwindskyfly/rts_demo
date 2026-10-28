class_name MiniMap
extends Control
## 右上角小地图。
##
## 直接用 _draw() 绘制（不用 SubViewport）：
##   * 背景
##   * 矿脉（灰色方块，储量越少越暗）
##   * 单位点（玩家白点 / 敌方红点）
##   * 建筑方块（玩家蓝 / 敌方红）
##   * 当前相机视野矩形（白框）
## 每 0.12 秒重绘一次即可，不要每帧重绘。

const MAP_WIDTH := 200.0
const MAP_HEIGHT := 112.0
const REDRAW_INTERVAL := 0.12

const COL_BACKGROUND := Color(0.08, 0.10, 0.12, 0.95)
const COL_BORDER := Color(0.32, 0.38, 0.46, 0.95)
const COL_PLAYER_UNIT := Color(0.95, 0.97, 1.0)
const COL_ENEMY_UNIT := Color(0.95, 0.30, 0.26)
const COL_PLAYER_BUILDING := Color(0.38, 0.68, 0.95)
const COL_ENEMY_BUILDING := Color(0.90, 0.26, 0.22)
const COL_CAMERA := Color(1.0, 1.0, 1.0, 0.9)

const FALLBACK_WORLD_SIZE := Vector2(2400.0, 1350.0)

var _redraw_cd: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MAP_WIDTH, MAP_HEIGHT)
	# 默认摆在右上角；外部若要换位置，请在 add_child() 之后覆盖锚点与偏移。
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -(MAP_WIDTH + 12.0)
	offset_right = -12.0
	offset_top = 12.0
	offset_bottom = 12.0 + MAP_HEIGHT


func _process(delta: float) -> void:
	_redraw_cd -= delta
	if _redraw_cd <= 0.0:
		_redraw_cd = REDRAW_INTERVAL
		queue_redraw()


## 手动刷新一次（外部调用）。
func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, COL_BACKGROUND, true)
	draw_rect(rect, COL_BORDER, false, 1.0)

	var world_size := _world_size()
	var scale := Vector2(size.x / world_size.x, size.y / world_size.y)

	_draw_ore_fields(scale)
	_draw_units(Game.enemy_units, COL_ENEMY_UNIT, scale)
	_draw_units(Game.player_units, COL_PLAYER_UNIT, scale)
	_draw_buildings(Game.enemy_buildings, COL_ENEMY_BUILDING, scale)
	_draw_buildings(Game.player_buildings, COL_PLAYER_BUILDING, scale)
	_draw_camera_view(scale)


# --------------------------------------------------------------- 矿脉
func _draw_ore_fields(scale: Vector2) -> void:
	for field in Game.ore_fields:
		if field == null or not is_instance_valid(field):
			continue
		var amount := int(_prop(field, "amount", 0))
		var max_amount := int(_prop(field, "max_amount", 0))
		if max_amount <= 0 and field.has_method("remaining"):
			amount = int(field.call("remaining"))
		var ratio := 1.0
		if max_amount > 0:
			ratio = clampf(float(amount) / float(max_amount), 0.0, 1.0)
		elif amount > 0:
			ratio = 1.0
		else:
			ratio = 0.0
		var color := Color(0.62, 0.62, 0.66).lerp(Color(0.16, 0.16, 0.18), 1.0 - ratio)
		var center := _to_map(field.global_position, scale)
		draw_rect(Rect2(center - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), color, true)


# --------------------------------------------------------------- 单位
func _draw_units(units: Array, color: Color, scale: Vector2) -> void:
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.has_method("is_alive") and not bool(unit.call("is_alive")):
			continue
		var center := _to_map(unit.global_position, scale)
		draw_circle(center, 2.5, color)


# --------------------------------------------------------------- 建筑
func _draw_buildings(buildings: Array, color: Color, scale: Vector2) -> void:
	for building in buildings:
		if building == null or not is_instance_valid(building):
			continue
		var stats: Variant = _prop(building, "stats", null)
		var world_size := Vector2(40.0, 40.0)
		var value: Variant = _prop(stats, "size", null)
		if value is Vector2:
			world_size = value
		var box := Vector2(
			maxf(4.0, world_size.x * scale.x),
			maxf(4.0, world_size.y * scale.y)
		)
		var center := _to_map(building.global_position, scale)
		draw_rect(Rect2(center - box * 0.5, box), color, true)


# ----------------------------------------------------------- 相机视野
func _draw_camera_view(scale: Vector2) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or not is_instance_valid(camera):
		return
	var center: Vector2 = camera.get_screen_center_position()
	var viewport_size := get_viewport_rect().size
	var zoom: Vector2 = camera.zoom
	if zoom.x <= 0.0:
		zoom.x = 1.0
	if zoom.y <= 0.0:
		zoom.y = 1.0
	var visible_size := Vector2(viewport_size.x / zoom.x, viewport_size.y / zoom.y)
	var top_left := _to_map(center - visible_size * 0.5, scale)
	var bottom_right := _to_map(center + visible_size * 0.5, scale)
	draw_rect(Rect2(top_left, bottom_right - top_left), COL_CAMERA, false, 1.0)


# --------------------------------------------------------------- 工具
func _to_map(world_pos: Vector2, scale: Vector2) -> Vector2:
	return Vector2(world_pos.x * scale.x, world_pos.y * scale.y)


func _world_size() -> Vector2:
	var cfg: GameConfig = Game.config
	if cfg == null:
		return FALLBACK_WORLD_SIZE
	var value: Vector2 = cfg.map_size
	if value.x <= 0.0 or value.y <= 0.0:
		return FALLBACK_WORLD_SIZE
	return value


static func _prop(obj: Variant, prop: String, fallback: Variant) -> Variant:
	if obj == null:
		return fallback
	var value: Variant = obj.get(prop)
	if value == null:
		return fallback
	return value
