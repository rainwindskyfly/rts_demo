class_name DragRect
extends Control
## 框选矩形：只负责画，不负责输入。
##
## 由外部（全屏铺满）驱动：
##   * SelectionManager 拖拽时调用 set_rect(rect)
##   * 拖拽结束时调用 clear_rect()
## 本控件自身 MOUSE_FILTER_IGNORE，不会吃掉任何鼠标事件。

signal rect_changed(rect: Rect2)
signal rect_cleared()

const FILL_COLOR := Color(1.0, 0.90, 0.25, 0.18)
const BORDER_COLOR := Color(1.0, 0.90, 0.25, 0.95)
const BORDER_WIDTH := 2.0

var _rect: Rect2 = Rect2()
var _has_rect: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 设置并绘制新的框选矩形（屏幕坐标）。
func set_rect(r: Rect2) -> void:
	_rect = r
	_has_rect = true
	queue_redraw()
	rect_changed.emit(_rect)


## 清除框选矩形。
func clear_rect() -> void:
	_rect = Rect2()
	_has_rect = false
	queue_redraw()
	rect_cleared.emit()


## 当前是否有可见的框选矩形。
func has_rect() -> bool:
	return _has_rect


## 当前框选矩形。
## 注意：不能命名为 `get_rect`，那会覆盖 Control 的原生方法并被引擎拒绝。
func current_rect() -> Rect2:
	return _rect


func _draw() -> void:
	if not _has_rect:
		return
	draw_rect(_rect, FILL_COLOR, true)
	draw_rect(_rect, BORDER_COLOR, false, BORDER_WIDTH)
