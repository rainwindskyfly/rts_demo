class_name HUD
extends Control
## 游戏主界面 HUD。
##
## 所有子节点都在 _ready() 里用代码创建（工程不提交任何 .tscn 文件）。
## 除了建造面板的按钮和 "Play Again" 按钮，其余所有 Control 都是
## MOUSE_FILTER_IGNORE，否则会吃掉世界的框选输入（最常见的坑）。
## 文本一律用 ASCII：Godot 内置默认字体没有中文字形。

signal build_entry_activated(index: int)
signal play_again_requested()

# ------------------------------------------------------------------ 配色
const COL_PANEL := Color(0.06, 0.07, 0.09, 0.82)
const COL_PANEL_SOLID := Color(0.09, 0.10, 0.13, 0.92)
const COL_BORDER := Color(0.30, 0.36, 0.44, 0.95)
const COL_TEXT := Color(0.88, 0.91, 0.95)
const COL_DIM := Color(0.55, 0.58, 0.64)
const COL_ACCENT := Color(0.95, 0.78, 0.25)
const COL_OK := Color(0.35, 0.85, 0.45)
const COL_WARN := Color(0.95, 0.82, 0.30)
const COL_BAD := Color(0.95, 0.38, 0.34)

const TOAST_LIFETIME := 2.5
const HINT_LIFETIME := 3.0
const BUILD_BUTTON_HEIGHT := 26.0

# ------------------------------------------------------------------ 节点
var _res_panel: PanelContainer = null
var _minerals_label: Label = null
var _units_label: Label = null
var _income_label: Label = null

var _timer_panel: PanelContainer = null
var _timer_label: Label = null

var _sel_panel: PanelContainer = null
var _sel_title: Label = null
var _sel_detail: Label = null
var _sel_action: Label = null
var _hp_bar_holder: Control = null
var _hp_bar_bg: ColorRect = null
var _hp_bar_fill: ColorRect = null
var _hp_ratio: float = 0.0

var _build_panel: PanelContainer = null
var _build_buttons: Array[Button] = []
var _build_entries: Array[Dictionary] = []
var _build_mode: int = -1

var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null

var _hint_label: Label = null
var _hint_tween: Tween = null

var _end_overlay: Control = null
var _end_title: Label = null
var _end_stats: Label = null

var _selected_units: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_resource_panel()
	_build_timer()
	_build_selection_panel()
	_build_build_panel()
	_build_toast()
	_build_hint()
	_build_end_panel()
	_connect_events()

	refresh()
	call_deferred("refresh")
	_show_hint()


# ------------------------------------------------------------ 资源面板
func _build_resource_panel() -> void:
	_res_panel = _make_panel(COL_PANEL)
	_res_panel.anchor_left = 0.0
	_res_panel.anchor_right = 0.0
	_res_panel.anchor_top = 0.0
	_res_panel.anchor_bottom = 0.0
	_res_panel.offset_left = 12.0
	_res_panel.offset_top = 12.0
	_res_panel.offset_right = 232.0
	_res_panel.offset_bottom = 92.0
	add_child(_res_panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_res_panel.add_child(box)

	_minerals_label = _make_label("Minerals: 0 / 0", 16)
	_units_label = _make_label("Units: 0/0", 14)
	_income_label = _make_label("Income: 0.0/s", 14)
	box.add_child(_minerals_label)
	box.add_child(_units_label)
	box.add_child(_income_label)


# ---------------------------------------------------------------- 计时器
func _build_timer() -> void:
	_timer_panel = _make_panel(Color(0.05, 0.05, 0.07, 0.75))
	_timer_panel.anchor_left = 0.5
	_timer_panel.anchor_right = 0.5
	_timer_panel.anchor_top = 0.0
	_timer_panel.anchor_bottom = 0.0
	_timer_panel.offset_left = -70.0
	_timer_panel.offset_right = 70.0
	_timer_panel.offset_top = 10.0
	_timer_panel.offset_bottom = 46.0
	add_child(_timer_panel)

	_timer_label = _make_label("00:00", 20)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_panel.add_child(_timer_label)


# ------------------------------------------------------------ 选中信息
func _build_selection_panel() -> void:
	_sel_panel = _make_panel(COL_PANEL)
	_sel_panel.anchor_left = 0.0
	_sel_panel.anchor_right = 0.0
	_sel_panel.anchor_top = 1.0
	_sel_panel.anchor_bottom = 1.0
	_sel_panel.offset_left = 12.0
	_sel_panel.offset_right = 262.0
	_sel_panel.offset_top = -142.0
	_sel_panel.offset_bottom = -12.0
	add_child(_sel_panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_sel_panel.add_child(box)

	_sel_title = _make_label("No selection", 16)
	_sel_detail = _make_label("", 13, COL_DIM)
	_sel_action = _make_label("", 13, COL_DIM)

	_hp_bar_holder = Control.new()
	_hp_bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_holder.custom_minimum_size = Vector2(0.0, 10.0)

	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_bg.color = Color(0.16, 0.17, 0.20, 0.95)
	_hp_bar_bg.size = Vector2(0.0, 10.0)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar_fill.color = COL_OK
	_hp_bar_fill.size = Vector2(0.0, 10.0)

	_hp_bar_holder.add_child(_hp_bar_bg)
	_hp_bar_holder.add_child(_hp_bar_fill)
	_hp_bar_holder.resized.connect(_on_hp_bar_resized)

	box.add_child(_sel_title)
	box.add_child(_sel_detail)
	box.add_child(_hp_bar_holder)
	box.add_child(_sel_action)


# ------------------------------------------------------------ 建造面板
func _build_build_panel() -> void:
	_build_entries = _resolve_build_entries()

	_build_panel = _make_panel(COL_PANEL_SOLID)
	_build_panel.anchor_left = 1.0
	_build_panel.anchor_right = 1.0
	_build_panel.anchor_top = 1.0
	_build_panel.anchor_bottom = 1.0
	_build_panel.offset_left = -262.0
	_build_panel.offset_right = -12.0
	# 5 buttons at 26 px + title + separations + panel margins needs ~205 px,
	# otherwise the last entry is clipped by the screen edge.
	_build_panel.offset_top = -222.0
	_build_panel.offset_bottom = -12.0
	add_child(_build_panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_build_panel.add_child(box)

	var title := _make_label("BUILD", 12, COL_DIM)
	box.add_child(title)

	for i in _build_entries.size():
		var entry: Dictionary = _build_entries[i]
		var btn := Button.new()
		btn.text = "%s   %d   %s" % [
			String(entry.get("label", "Build")),
			int(entry.get("cost", 0)),
			_hotkey_text(entry),
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0.0, BUILD_BUTTON_HEIGHT)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_build_entry_pressed.bind(i))
		box.add_child(btn)
		_build_buttons.append(btn)


# ---------------------------------------------------------------- 提示条
func _build_toast() -> void:
	_toast_panel = _make_panel(Color(0.05, 0.05, 0.07, 0.88))
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 1.0
	_toast_panel.anchor_bottom = 1.0
	_toast_panel.offset_left = -250.0
	_toast_panel.offset_right = 250.0
	_toast_panel.offset_top = -114.0
	_toast_panel.offset_bottom = -74.0
	_toast_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_toast_panel)

	_toast_label = _make_label("", 15)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)


# ------------------------------------------------------------ 开局教学提示
func _build_hint() -> void:
	_hint_label = _make_label("Left-drag select | Right-click command | B build", 14, COL_DIM)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.5
	_hint_label.anchor_right = 0.5
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = -300.0
	_hint_label.offset_right = 300.0
	_hint_label.offset_top = -162.0
	_hint_label.offset_bottom = -136.0
	add_child(_hint_label)


# ---------------------------------------------------------------- 胜负面板
func _build_end_panel() -> void:
	_end_overlay = Control.new()
	_end_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_overlay.visible = false
	add_child(_end_overlay)

	var dim := ColorRect.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -320.0
	box.offset_right = 320.0
	box.offset_top = -170.0
	box.offset_bottom = 170.0
	_end_overlay.add_child(box)

	_end_title = _make_label("DRAW", 64)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)

	_end_stats = _make_label("", 18, COL_TEXT)
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_stats)

	var again := Button.new()
	again.text = "Play Again"
	again.custom_minimum_size = Vector2(170.0, 40.0)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(_on_play_again_pressed)
	box.add_child(again)


# ------------------------------------------------------------------ 信号
func _connect_events() -> void:
	Events.minerals_changed.connect(_on_minerals_changed)
	Events.selection_changed.connect(_on_selection_changed)
	Events.unit_health_changed.connect(_on_unit_health_changed)
	Events.match_timer_updated.connect(_on_timer_updated)
	Events.toast.connect(_on_toast)
	Events.build_mode_changed.connect(_on_build_mode_changed)
	Events.match_ended.connect(_on_match_ended)


# ------------------------------------------------------------ 外部调用
## 刷新所有面板（资源、计时器、选中信息、建造面板）。
func refresh() -> void:
	_refresh_resources()
	_refresh_timer()
	_refresh_selection()
	_refresh_build_panel()


# ------------------------------------------------------------------ 资源
func _refresh_resources() -> void:
	var cap := 999
	var max_army := 40
	var cfg: GameConfig = Game.config
	if cfg != null:
		cap = cfg.mineral_cap
		max_army = cfg.max_army
	_minerals_label.text = "Minerals: %d / %d" % [Game.minerals, cap]
	_units_label.text = "Units: %d/%d" % [_count_player_units(), max_army]
	_income_label.text = "Income: %.1f/s" % (_count_workers() * 0.75)


func _count_player_units() -> int:
	var count := 0
	for u in Game.player_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.has_method("is_alive") and not bool(u.call("is_alive")):
			continue
		count += 1
	return count


func _count_workers() -> int:
	var count := 0
	for u in Game.player_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.has_method("is_alive") and not bool(u.call("is_alive")):
			continue
		var stats: Variant = _prop(u.get("stats"), "carry_capacity", 0)
		if int(stats) > 0:
			count += 1
	return count


# ------------------------------------------------------------------ 计时
func _refresh_timer() -> void:
	_timer_label.text = Game.time_text()
	if Game.time_remaining() <= 60.0:
		_timer_label.add_theme_color_override("font_color", COL_BAD)
	else:
		_timer_label.add_theme_color_override("font_color", COL_TEXT)


# ---------------------------------------------------------------- 选中信息
func _refresh_selection() -> void:
	var units: Array = []
	for u in _selected_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.has_method("is_alive") and not bool(u.call("is_alive")):
			continue
		units.append(u)

	if units.is_empty():
		_sel_title.text = "No selection"
		_sel_detail.text = ""
		_sel_action.text = ""
		_update_hp_bar(0.0)
		return

	var counts := {}
	for u in units:
		var unit_name := _unit_type_name(u)
		counts[unit_name] = int(counts.get(unit_name, 0)) + 1

	var best_name := ""
	var best_count := 0
	for key in counts.keys():
		var value := int(counts[key])
		if value > best_count:
			best_count = value
			best_name = String(key)

	_sel_title.text = "%s  %d/%d" % [best_name, best_count, units.size()]

	var hp_sum := 0.0
	for u in units:
		if u.has_method("health_ratio"):
			hp_sum += float(u.call("health_ratio"))
		else:
			var health: Variant = _prop(u, "health", 0.0)
			var max_hp: Variant = _prop(u, "max_health", 0.0)
			if float(max_hp) > 0.0:
				hp_sum += float(health) / float(max_hp)
	var hp_ratio := clampf(hp_sum / float(units.size()), 0.0, 1.0)
	_sel_detail.text = "HP: %d%%" % int(round(hp_ratio * 100.0))
	_update_hp_bar(hp_ratio)

	var actions := {}
	for u in units:
		var action := String(_prop(u, "action_text", ""))
		actions[action] = int(actions.get(action, 0)) + 1
	var action_text := ""
	for key in actions.keys():
		action_text = String(key)
		break
	if actions.size() > 1:
		action_text = "Mixed"
	_sel_action.text = action_text


func _unit_type_name(u: Node) -> String:
	var stats: Variant = u.get("stats")
	var name := String(_prop(stats, "display_name", ""))
	if name == "":
		name = "Unit"
	return name


func _update_hp_bar(ratio: float) -> void:
	if _hp_bar_bg == null or _hp_bar_fill == null or _hp_bar_holder == null:
		return
	_hp_ratio = ratio
	var width := _hp_bar_holder.size.x
	if width <= 0.0:
		width = _hp_bar_holder.custom_minimum_size.x
	var height := 10.0
	_hp_bar_bg.size = Vector2(width, height)
	_hp_bar_fill.size = Vector2(width * clampf(ratio, 0.0, 1.0), height)
	if ratio > 0.5:
		_hp_bar_fill.color = COL_OK
	elif ratio > 0.25:
		_hp_bar_fill.color = COL_WARN
	else:
		_hp_bar_fill.color = COL_BAD


## `resized` 不带参数，所以这里缓存上一次的 HP 比例再重绘。
func _on_hp_bar_resized() -> void:
	_update_hp_bar(_hp_ratio)


# ---------------------------------------------------------------- 建造面板
func _refresh_build_panel() -> void:
	for i in _build_buttons.size():
		var btn: Button = _build_buttons[i]
		var entry: Dictionary = _build_entries[i]
		var affordable := Game.minerals >= int(entry.get("cost", 0))
		btn.disabled = not affordable
		_apply_entry_style(btn, _build_mode == i, affordable)


func _apply_entry_style(btn: Button, selected: bool, affordable: bool) -> void:
	var bg := Color(0.14, 0.16, 0.20, 0.92)
	var border := COL_BORDER
	var font := COL_TEXT
	if not affordable:
		bg = Color(0.10, 0.10, 0.12, 0.85)
		border = Color(0.24, 0.16, 0.16, 0.9)
		font = Color(0.48, 0.44, 0.44)
	elif selected:
		bg = Color(0.24, 0.26, 0.14, 0.95)
		border = COL_ACCENT
		font = Color(1.0, 0.95, 0.72)

	var border_width := 2 if selected else 1
	btn.add_theme_stylebox_override("normal", _stylebox(bg, border, border_width))
	btn.add_theme_stylebox_override("hover", _stylebox(bg.lightened(0.12), border, border_width))
	btn.add_theme_stylebox_override("pressed", _stylebox(bg.darkened(0.2), border, border_width))
	btn.add_theme_stylebox_override("disabled", _stylebox(bg, border, border_width))
	btn.add_theme_stylebox_override("focus", _stylebox(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	btn.add_theme_color_override("font_color", font)
	btn.add_theme_color_override("font_hover_color", font)
	btn.add_theme_color_override("font_pressed_color", font)
	btn.add_theme_color_override("font_disabled_color", font)


## 建造条目：优先读 Game.config.build_menu，缺失时用 config 里的 stats 兜底。
func _resolve_build_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cfg: GameConfig = Game.config
	if cfg == null:
		return out
	var raw: Variant = cfg.get("build_menu")
	if raw is Array:
		for item in (raw as Array):
			if item is Dictionary:
				out.append(_normalize_entry(item))
	if out.is_empty():
		out = _fallback_build_entries(cfg)
	return out


func _fallback_build_entries(cfg: GameConfig) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_normalize_entry({
		"kind": "building", "stats": cfg.barracks_stats,
		"label": "Barracks", "hotkey": "1",
	}))
	out.append(_normalize_entry({
		"kind": "building", "stats": cfg.refinery_stats,
		"label": "Refinery", "hotkey": "2",
	}))
	out.append(_normalize_entry({
		"kind": "unit", "stats": cfg.infantry_stats,
		"label": "Infantry", "hotkey": "3",
	}))
	out.append(_normalize_entry({
		"kind": "unit", "stats": cfg.tank_stats,
		"label": "Tank", "hotkey": "4",
	}))
	out.append(_normalize_entry({
		"kind": "unit", "stats": cfg.worker_stats,
		"label": "Worker", "hotkey": "5",
	}))
	return out


func _normalize_entry(entry: Dictionary) -> Dictionary:
	var stats: Variant = entry.get("stats")
	var label := String(_prop(entry, "label", ""))
	if label == "":
		label = String(_prop(stats, "display_name", "Build"))
	var cost := int(_prop(entry, "cost", _prop(stats, "build_cost", 0)))
	return {
		"kind": String(_prop(entry, "kind", "unit")),
		"stats": stats,
		"label": label,
		"cost": cost,
		"hotkey": String(_prop(entry, "hotkey", "")),
	}


func _hotkey_text(entry: Dictionary) -> String:
	var hotkey := String(entry.get("hotkey", ""))
	if hotkey == "":
		return ""
	return "[%s]" % hotkey


# ------------------------------------------------------------------ 提示
func _show_hint() -> void:
	_hint_label.visible = true
	_hint_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(HINT_LIFETIME)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, 0.8)
	_hint_tween.tween_callback(_hide_hint)


func _hide_hint() -> void:
	_hint_label.visible = false


func _show_toast(message: String, kind: int) -> void:
	var color := COL_TEXT
	if kind == 1:
		color = COL_WARN
	elif kind == 2:
		color = COL_BAD
	_toast_label.text = message
	_toast_label.add_theme_color_override("font_color", color)
	_toast_panel.visible = true
	_toast_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_LIFETIME)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(_hide_toast)


func _hide_toast() -> void:
	_toast_panel.visible = false


# ------------------------------------------------------------ 胜负面板
func _show_end_panel(result: int) -> void:
	var title := "DRAW"
	var color := COL_WARN
	if result == 1:
		title = "VICTORY"
		color = COL_OK
	elif result == 2:
		title = "DEFEAT"
		color = COL_BAD
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", color)
	_end_stats.text = "Minerals gathered: %d\nUnits built: %d\nKills: %d" % [
		Game.stat_minerals_gathered,
		Game.stat_units_built,
		Game.stat_kills,
	]
	_end_overlay.visible = true


# ------------------------------------------------------------------ 回调
func _on_minerals_changed(_current: int, _delta: int) -> void:
	_refresh_resources()
	_refresh_build_panel()


func _on_selection_changed(units: Array) -> void:
	_selected_units = units.duplicate()
	_refresh_selection()


func _on_unit_health_changed(_unit: Node, _ratio: float) -> void:
	_refresh_selection()


func _on_timer_updated(_remaining: float) -> void:
	_refresh_timer()


func _on_toast(message: String, kind: int) -> void:
	_show_toast(message, kind)


func _on_build_mode_changed(entry: int) -> void:
	_build_mode = entry
	_refresh_build_panel()


func _on_match_ended(result: int) -> void:
	_show_end_panel(result)


func _on_build_entry_pressed(index: int) -> void:
	build_entry_activated.emit(index)


func _on_play_again_pressed() -> void:
	play_again_requested.emit()


# ------------------------------------------------------------------ 工具
func _make_panel(bg: Color = COL_PANEL, border: Color = COL_BORDER) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _stylebox(bg, border, 1))
	return panel


func _stylebox(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


func _make_label(text: String, font_size: int = 14, color: Color = COL_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func _prop(obj: Variant, prop: String, fallback: Variant) -> Variant:
	if obj == null:
		return fallback
	var value: Variant = obj.get(prop)
	if value == null:
		return fallback
	return value
