class_name HealthBar
extends Node2D
## World-space health bar drawn above a unit or building.
##
## Implemented as a `Node2D` with `_draw` rather than a `Control`, so it lives
## in world space and never fights with the screen-space UI layout.

@export var bar_width: float = 26.0
@export var bar_height: float = 4.0
@export var offset_y: float = -20.0
@export var always_visible: bool = false

var ratio: float = 1.0
var _damaged: bool = false


func _ready() -> void:
	z_index = 40
	position.y = offset_y
	queue_redraw()


func set_ratio(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if absf(clamped - ratio) < 0.0001:
		return
	ratio = clamped
	_damaged = ratio < 0.999
	queue_redraw()


func mark_damaged() -> void:
	_damaged = true
	queue_redraw()


func _draw() -> void:
	if ratio >= 0.999 and not always_visible and not _damaged:
		return
	var background := Rect2(-bar_width * 0.5, -bar_height * 0.5, bar_width, bar_height)
	draw_rect(background, Color(0.05, 0.05, 0.05, 0.75))
	var fill_color := Color(0.32, 0.82, 0.35)
	if ratio < 0.25:
		fill_color = Color(0.88, 0.24, 0.18)
	elif ratio < 0.5:
		fill_color = Color(0.92, 0.76, 0.20)
	draw_rect(Rect2(background.position, Vector2(bar_width * ratio, bar_height)), fill_color)
