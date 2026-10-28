# RTS 微缩 Demo 技术方案（Godot 4.7.2 / GDScript）

> 目标：今晚 5–6 小时交付一个**可直接运行、可导出 exe** 的 RTS 微缩 demo。原则：能跑 > 优雅；数值全部走 Resource，本文档只定义接口。

---

## ⚠️ 0.1 实现说明：本文档与最终代码的差异

本文档最初是在动手前写的**方案**。实现过程中有若干处被**有意改掉**，以代码为准。
下面逐条列出差异与改动理由，其余章节仍然成立。

| 项 | 原方案 | 最终实现 | 为什么 |
|---|---|---|---|
| 寻路 | `NavigationRegion2D` + `NavigationAgent2D` | **自写 30px 栅格 A\***（`scripts/systems/pathfinder.gd`） | 导航服务器有地图同步窗口，新生成的 agent 会静默拿不到路径而原地不动。一晚的交付容不下这种不确定性 |
| 数值文件 | `.tres` 资源 | **代码构建**（`GameConfig.create_default()`） | 手写 `.tres` 需要 `script_class` 注册，依赖 `.godot` 缓存，容易踩坑；单文件改数值也更快 |
| 单位种类 | 2 种（步兵兼采集） | **3 种**（步兵 / 坦克 / 工兵） | 与策划案一致，工兵独立后采集闭环更清晰 |
| 场景文件 | `Main.tscn` + 多个 `.tscn` | **只有 `Main.tscn`**，其余全部代码生成 | 手写 `.tscn` 会引用过期脚本；代码生成后整条装配链在一处可读 |
| 依赖环 | 直接互相引用 | 新增 **`Combatant` 基类** | `Unit ↔ Projectile`、`Unit ↔ Building` 是循环，Godot 4 无法解析；`Combatant` 把依赖树化 |
| 输入映射 | 写进 `project.godot` | **运行时注册**（`InputSetup.apply()`） | 手写 `[input]` 段格式脆弱易损坏 |
| 额外产出 | — | **`tests/` 冒烟测试 + 截图工具** | 无头验收，24 项断言 |

> 文档正文里凡涉及上述条目的具体描述，均以本节为准。

## 0. 约束与关键决策

| 项 | 决策 |
|---|---|
| 引擎/项目根 | Godot 4.7.2-stable，GDScript，`project.godot` config_version=5；根目录 `E:\rts_demo` |
| 导出物 | `E:\rts_demo\build\RTSDemo.exe` + `RTSDemo.pck`（非单文件，便于排错） |
| 单位 | 仅 2 种：`Soldier`（步兵，兼作采集者）、`Tank`（坦克） |
| 采集闭环 | 采集者=步兵：背矿→回基地/兵营→转资源→建兵营/造坦克→摧毁敌方基地=胜利 |
| 敌方 AI | `AICommander` 造兵（PRODUCE）+ 单位大脑 ATTACK/DEFEND/HOLD 三态；敌方资源独立变量 |
| 自动攻击 | 步兵=近战即时判定；坦克=炮击（Projectile 命中结算，可降级为即时伤害） |
| 寻路 | `NavigationAgent2D`；障碍物**必须烘焙进 NavigationPolygon**（见 §12 R3） |

**纪律**：前 60 分钟只做「1 单位 + 1 障碍 + 绕行跑通」；每次改完就 F5；数值不写死在代码（统一进 `.tres`，来不及先 `@export`）；第 6 步（框选）前不碰 UI；第 15 步（导出）留足 25 分钟。

## 1. 目录结构（实际）
```
E:\rts_demo\
├─ project.godot            # 引擎设置 + autoload（Events / Game）
├─ export_presets.cfg       # Windows Desktop 导出预设
├─ icon.svg  README.md  LICENSE  .gitignore
├─ scenes\
│  └─ Main.tscn             # 唯一场景文件，只挂 scripts/main.gd
├─ scripts\
│  ├─ main.gd               # 场景总装：建树、接线、胜负判定、快捷键
│  ├─ core\    events.gd(autoload Events) game.gd(autoload Game) config.gd
│  │           unit_stats.gd building_stats.gd input_setup.gd
│  ├─ entities\ combatant.gd  unit.gd  building.gd  ore_field.gd
│  │             projectile.gd  health_bar.gd
│  ├─ systems\ pathfinder.gd  selection.gd  commands.gd  camera_rig.gd
│  │             ai_commander.gd
│  ├─ ui\      hud.gd  minimap.gd  drag_rect.gd
│  └─ world\   map_builder.gd
├─ tests\     SmokeTest.tscn  smoke_test.gd  Screenshot.tscn  screenshot.gd
├─ docs\      DESIGN.md  TECH_PLAN.md
└─ build\                    # 导出产物（gitignore）
```
职责：**scripts=逻辑、scenes=结构、config=数值**。`.tscn` 里出现数字即违规。

### 运行与验收

```powershell
# 无头验收（24 项断言，几十秒内跑完）
godot --headless --path . res://tests/SmokeTest.tscn --fixed-fps 60

# 生成 README 用截图
godot --path . res://tests/Screenshot.tscn --fixed-fps 60 --resolution 1280x720

# 导出
godot --headless --path . --export-release "Windows Desktop" "build/RTSDemo.exe"
```

## 2. 主场景 `Main.tscn` 节点树
```
Main (Node2D)                          scripts/main.gd
├─ World (Node2D)
│  ├─ Map (Node2D)                     MapBuilder：地形 / 网格线 / 障碍 / 矿脉
│  ├─ Entities (Node2D)
│  │  └─ Units / Buildings / OreFields
│  └─ CameraRig (Node2D)               camera_rig.gd → Camera2D
├─ UI (CanvasLayer, layer=10)
│  ├─ DragRect (Control)               drag_rect.gd（只画框，IGNORE）
│  ├─ HUD (Control)                    hud.gd
│  └─ MiniMap (Control)                minimap.gd
└─ Managers (Node)
   ├─ SelectionManager (Node)  ├─ CommandDispatcher (Node)  └─ AICommander (Node)
```
约定：屏幕 UI 用 `CanvasLayer > Control`；世界内血条/光圈用 `Node2D + _draw`（R7）。
**Map 必须在 Entities 之前加入树**：同层级绘制顺序跟随树序，否则地面会盖住矿脉。

## 3. 脚本清单（基类 / 公开签名 / 职责）
> autoload 脚本**不写 `class_name`**（与单例同名会报 "hides an autoload singleton"，R2）。数值类见 §6。
| 文件 | 基类 | 公开签名 | 职责 |
|---|---|---|---|
| core/events.gd *(autoload Events)* | Node | `signal unit_died(unit: Unit, killer: Unit)`<br>`signal resources_changed(cur: int, delta: int)`<br>`signal selection_changed(units: Array[Unit])`<br>`signal game_over(victory: bool)`<br>`signal order_issued(order: Dictionary)`<br>`signal building_ready(building: Building)` | 全局信号总线，只声明不发逻辑 |
| core/resources_manager.gd *(autoload Resources)* | Node | `var current: int`<br>`func add(amount: int) -> void`<br>`func can_afford(cost: int) -> bool`<br>`func spend(cost: int) -> bool` | 资源总量与增减，自行广播信号 |
| core/combat.gd | RefCounted | `static func damage(target: Node2D, amount: float, source: Node = null) -> void` | 统一伤害入口 |
| entity/unit.gd | CharacterBody2D `Unit` | `@export var stats: UnitStats`<br>`func setup(s: UnitStats) -> void`<br>`func take_damage(amount: float, source: Node = null) -> void`<br>`func die(killer: Unit = null) -> void`<br>`func is_alive() -> bool`<br>`func current_target() -> Unit` | 基类：血量/朝向/移动/自动攻击/血条/死亡 |
| entity/player_unit.gd | Unit `PlayerUnit` | `func move_to(target: Vector2) -> void`<br>`func harvest(node: ResourceNode) -> void`<br>`func deposit_at(b: Building) -> void` | 执行玩家指令（移动/采集/回仓） |
| entity/enemy_ai.gd | Unit `EnemyUnit` | `enum State {ATTACK, DEFEND, HOLD}`<br>`func set_role(role: int) -> void`<br>`func current_state() -> int` | 敌方单位大脑 |
| entity/building.gd | Node2D `Building` | `@export var stats: BuildingStats`<br>`func take_damage(...) -> void`<br>`func produce() -> Unit`<br>`func is_player_building() -> bool` | 血量/生产/阵营 |
| entity/resource_node.gd | Node2D `ResourceNode` | `func remaining() -> int`<br>`func extract(amount: int) -> int` | 矿点储量与开采 |
| entity/projectile.gd | Node2D `Projectile` | `func launch(target: Unit, damage: float, speed: float) -> void` | 炮弹飞行与命中结算 |
| entity/health_bar.gd | Node2D `HealthBar` | `func set_ratio(r: float) -> void` | 世界空间血条 |
| systems/selection_manager.gd | Node `SelectionManager` | `var selected: Array[Unit]`<br>`signal drag_rect_changed(rect: Rect2)`<br>`func select(u: Unit, additive: bool) -> void`<br>`func clear() -> void`<br>`func units_in_rect(r: Rect2) -> Array[Unit]` | 框选与选中集合 |
| systems/command_dispatcher.gd | Node `CommandDispatcher` | `func issue_move(units: Array[Unit], world_pos: Vector2) -> void`<br>`func issue_harvest(units: Array[Unit], node: ResourceNode) -> void` | 指令翻译成单位行为 |
| systems/path_agent.gd | RefCounted `PathAgent` | `func _init(a: NavigationAgent2D) -> void`<br>`func set_target(p: Vector2) -> void`<br>`func next_step() -> Vector2`<br>`func is_done() -> bool` | 封装 NavigationAgent2D 与到达判定 |
| systems/ai_commander.gd | Node `AICommander` | `@export var enemy_resources: int`<br>`@export var wave_interval: float`<br>`func set_difficulty(d: float) -> void` | 敌方造兵与波次调度 |
| ui/hud.gd | Control | `func refresh() -> void` | 资源面板/选中信息/胜负横幅 |
| ui/minimap.gd | Control | `func refresh() -> void` | 小地图绘制 |
| ui/drag_rect.gd | Control | `func set_rect(r: Rect2) -> void`<br>`func hide_rect() -> void` | 框选矩形绘制 |
| camera/camera_rig.gd | Node2D | `func zoom(delta: float) -> void`<br>`func pan(v: Vector2) -> void`<br>`func focus(p: Vector2) -> void` | 相机平移缩放 |

## 4. 关键机制实现

### 4.1 框选多单位（屏幕矩形 → 世界单位检测）
拖拽矩形留在**屏幕空间**，把单位 `global_position` 用 `get_viewport().get_canvas_transform()` 映射到屏幕再判定，缩放下依然准确。`Rect2(a,b).abs()` 处理反向拖拽；`_apply_click` 取 12px 内最近单位；HUD 必须 `MOUSE_FILTER_IGNORE`，否则吃掉框选（R7）。
```gdscript
# systems/selection_manager.gd
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                _drag_start = mb.position; _dragging = true
            else:
                _dragging = false
                var r := Rect2(_drag_start, mb.position).abs()
                if _drag_start.distance_to(mb.position) > 6.0: _apply_area(r, mb.shift_pressed)
                else: _apply_click(mb.position, mb.shift_pressed)
    elif event is InputEventMouseMotion and _dragging:
        drag_rect_changed.emit(Rect2(_drag_start, (event as InputEventMouseMotion).position).abs())

func _apply_area(r: Rect2, additive: bool) -> void:
    if not additive: clear()
    for n in get_tree().get_nodes_in_group("player_units"):
        var u := n as Unit
        if u == null or not u.is_alive(): continue
        var sp: Vector2 = get_viewport().get_canvas_transform() * u.global_position
        if r.has_point(sp): selected.append(u)
    Events.selection_changed.emit(selected)
```
### 4.2 右键下达移动指令（阵型散开；输入放 Node2D 上下文，`event.position` 是屏幕坐标、`get_global_mouse_position()` 是世界坐标，勿混用）
```gdscript
# systems/command_dispatcher.gd
func issue_move(units: Array[Unit], world_pos: Vector2) -> void:
    if units.is_empty(): return
    var cols := int(ceil(sqrt(float(units.size())))); var sp := 28.0
    for i in units.size():
        var gx := i % cols; var gy := i / cols
        var off := Vector2((gx - (cols - 1) * 0.5) * sp, (gy - (ceil(float(units.size()) / cols) - 1) * 0.5) * sp)
        units[i].move_to(world_pos + off)
    Events.order_issued.emit({"type": "move", "pos": world_pos, "count": units.size()})
```
输入放在 Node2D 上下文（`main.gd` 或 SelectionManager）。`get_global_mouse_position()` 是 CanvasItem 方法（世界坐标），`event.position` 是屏幕坐标，二者不要混用。
```gdscript
if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
        command_dispatcher.issue_move(selection.selected, get_global_mouse_position())
```
### 4.3 导航寻路与到达检测
四条铁律：①设置目标前 `await get_tree().physics_frame`（地图未同步会走直线/不动）；②`get_next_path_position()` 基于 agent 自身位置，agent 必须是单位子节点；③`target_desired_distance` 明显大于 `radius`，否则到位抖动；④**障碍物要绕行必须烘焙进 `NavigationRegion2D.navigation_polygon`**，`NavigationObstacle2D` 只做局部避让（R3）。烘焙：NavRegion 选中 → 新建 `NavigationPolygon` → 画外轮廓 → 障碍做成 `NavigationObstacle2D` → NavRegion 上点 `Bake Navigation Polygon` → 运行确认 `NavRegion.enabled == true`。备用（需在 4.7 确认 API 仍在）：`NavigationPolygon.add_outline()` + `make_polygons_from_outlines()`，洞需反向绕序。
```gdscript
# systems/path_agent.gd
func _init(a: NavigationAgent2D) -> void:
    agent = a
    agent.path_desired_distance = 10.0     # 距路径点多远算走过该点
    agent.target_desired_distance = 14.0   # 距最终目标多远算到位（> radius，防抖）
    agent.radius = 10.0
func set_target(p: Vector2) -> void: _has_target = true; agent.target_position = p
func next_step() -> Vector2: return agent.get_next_path_position()
func is_done() -> bool: return not _has_target or agent.is_navigation_finished()

# entity/unit.gd
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
func _ready() -> void:
    add_to_group("player_units" if is_player else "enemy_units")
    await get_tree().physics_frame   # 等 NavigationServer 地图同步后再下发目标
    path = PathAgent.new(nav_agent)
func _physics_process(delta: float) -> void:
    if path == null or path.is_done():
        velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta); move_and_slide(); return
    var dir := (path.next_step() - global_position)
    if dir.length() > 0.001: dir = dir.normalized(); rotation = dir.angle()
    velocity = velocity.lerp(dir * stats.speed, 8.0 * delta)
    move_and_slide()
```
### 4.4 自动索敌与攻击
索敌节流 0.2s；候选为敌对阵营组；评分 = 距离 − 残血加权；已有目标在 `leash_range` 内则保持（防抖）；命中判定 = 距离 ≤ `attack_range` 且冷却归零。
```gdscript
# entity/unit.gd
func _acquire_target() -> void:
    if target != null and target.is_alive(): return
    var group := "enemy_units" if is_player else "player_units"
    var best: Unit = null; var best_score := INF
    for n in get_tree().get_nodes_in_group(group):
        var u := n as Unit
        if u == null or not u.is_alive(): continue
        var d := global_position.distance_to(u.global_position)
        if d > stats.acquire_range: continue
        var score := d - (100.0 - u.health) * 0.35
        if score < best_score: best_score = score; best = u
    target = best

func _fire_at(t: Unit) -> void:
    if _attack_cd > 0.0: return
    _attack_cd = stats.attack_cooldown
    if stats.is_ranged:
        var p := Projectile.new(); p.launch(t, stats.attack_damage, stats.projectile_speed)
    else:
        Combat.damage(t, stats.attack_damage, self)

func take_damage(amount: float, source: Node = null) -> void:
    if not is_alive(): return
    health = maxf(0.0, health - amount)
    health_bar.set_ratio(health / max_health)
    if health <= 0.0: die(source as Unit)
func die(killer: Unit = null) -> void:
    if not is_alive(): return
    health = 0.0; Events.unit_died.emit(self, killer); queue_free()

# core/combat.gd
static func damage(target: Node2D, amount: float, source: Node = null) -> void:
    var u := target as Unit
    if u != null: u.take_damage(amount, source)
```
### 4.5 血条（Node2D + `_draw`；满血可隐藏省重绘，勿用 Control，4.x 统一 `queue_redraw()`）
```gdscript
# entity/health_bar.gd
@export var bar_width := 26.0
@export var bar_height := 4.0
@export var offset_y := -18.0
var ratio := 1.0
func _ready() -> void: z_index = 50; position.y = offset_y; queue_redraw()
func set_ratio(r: float) -> void: ratio = clampf(r, 0.0, 1.0); queue_redraw()
func _draw() -> void:
    draw_rect(Rect2(-bar_width*0.5, -bar_height*0.5, bar_width, bar_height), Color(0,0,0,0.65))
    var col := Color(0.85,0.2,0.15) if ratio < 0.35 else Color(0.25,0.8,0.3)
    draw_rect(Rect2(-bar_width*0.5, -bar_height*0.5, bar_width*ratio, bar_height), col)
```
### 4.6 资源采集与回基地转化
`PlayerUnit` 状态机：`IDLE → GO_MINE → MINING → GO_DEPOSIT → DEPOSIT`。`Resources.add()` 内部自己广播 `resources_changed`，调用点不必再发；采矿过程用冷却即可，不必做进度条。
```gdscript
# entity/player_unit.gd
func harvest(node: ResourceNode) -> void: harvest_target = node; _set_state("GO_MINE")
func _process_state(delta: float) -> void:
    match _state:
        "GO_MINE":
            if harvest_target == null: _set_state("IDLE"); return
            path.set_target(harvest_target.global_position)
            if global_position.distance_to(harvest_target.global_position) <= 16.0: _set_state("MINING")
        "MINING":
            _mining_cd -= delta
            if _mining_cd <= 0.0:
                _mining_cd = 1.0
                carried += harvest_target.extract(stats.harvest_rate)
                if carried >= stats.carry_capacity or harvest_target.remaining() <= 0: _set_state("GO_DEPOSIT")
        "GO_DEPOSIT":
            var b := _nearest_deposit()          # 最近的我方基地/兵营
            if b == null: _set_state("IDLE"); return
            path.set_target(b.global_position)
            if global_position.distance_to(b.global_position) <= 24.0: _set_state("DEPOSIT")
        "DEPOSIT":
            Resources.add(carried); carried = 0
            _set_state("IDLE" if harvest_target == null else "GO_MINE")
```
### 4.7 敌方 AI 状态机（造兵 / 进攻 / 防守）
两层：**AICommander（基地层造兵）** + **EnemyUnit（单位层攻防）**；三态切换阈值放 `UnitStats`（如 `defend_radius`）。敌方资源**独立变量**，不要复用 `Resources` 单例（否则玩家能看到敌方余额）。
```gdscript
# entity/enemy_ai.gd
enum State { ATTACK, DEFEND, HOLD }
var state: int = State.ATTACK
var home_pos := Vector2.ZERO
var _think_cd := 0.0
func _ready() -> void: super._ready(); home_pos = global_position
func _physics_process(delta: float) -> void:
    super._physics_process(delta)
    _think_cd -= delta
    if _think_cd > 0.0: return
    _think_cd = 0.35
    match state:
        State.ATTACK:
            if _threat_near_home(): state = State.DEFEND
            elif target != null: path.set_target(target.global_position)
        State.DEFEND:
            if not _threat_near_home(): state = State.ATTACK
            else:
                var t := _nearest_threat()
                if t != null: path.set_target(t.global_position)
        State.HOLD: pass

# systems/ai_commander.gd
@export var enemy_resources: int = 300
@export var wave_interval := 45.0
var _timer := 0.0
var _wave_index := 0
func _process(delta: float) -> void:
    _timer -= delta
    if _timer > 0.0: return
    _timer = wave_interval; _wave_index += 1
    _spawn_wave(); _try_produce()
func _try_produce() -> void:
    var b := _find_enemy_barracks()
    if b == null: return
    if enemy_resources >= b.stats.produce_cost:
        enemy_resources -= b.stats.produce_cost
        var u: Unit = b.produce()
        u.set_role(EnemyUnit.State.ATTACK if _wave_index % 2 == 0 else EnemyUnit.State.DEFEND)
```
### 4.8 小地图（直接 `_draw`，不用 SubViewport；`world_size` 从 `game_config.tres` 读，点击/框视野是可降级项）
```gdscript
# ui/minimap.gd
@export var world_size := Vector2(4000, 3000)
var _redraw_cd := 0.0
func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
    _redraw_cd -= delta
    if _redraw_cd <= 0.0: _redraw_cd = 0.12; queue_redraw()
func _draw() -> void:
    var s := size / world_size
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.1))
    for gname in ["player_units", "enemy_units"]:
        var col := Color(0.3, 0.8, 1.0) if gname == "player_units" else Color(1.0, 0.35, 0.3)
        for n in get_tree().get_nodes_in_group(gname):
            var u := n as Unit
            if u == null or not u.is_alive(): continue
            draw_circle(u.global_position * s, 2.5, col)
    var cam := get_viewport().get_camera_2d()
    if cam != null:
        var half := get_viewport_rect().size * 0.5
        draw_rect(Rect2((cam.get_screen_center_position() - half) * s, half * 2.0 * s), Color(1,1,1,0.8), false, 1.0)
```
## 5. 信号与事件设计
| 信号 | 参数 | 发出者 | 订阅者 |
|---|---|---|---|
| `Events.unit_died` | `(unit: Unit, killer: Unit)` | `Unit.die()` | SelectionManager（移出选中集）、Main（胜负判定）、HUD |
| `Events.resources_changed` | `(current: int, delta: int)` | `Resources` 单例 | HUD.refresh()、飘字 |
| `Events.selection_changed` | `(units: Array[Unit])` | SelectionManager | HUD（选中信息）、Main（刷新光圈） |
| `Events.order_issued` | `(order: Dictionary)` | CommandDispatcher | HUD 调试日志（可选） |
| `Events.game_over` | `(victory: bool)` | Main | HUD（胜负面板） |
| `Events.building_ready` | `(building: Building)` | Building | AICommander（敌方兵营上线） |
| `SelectionManager.drag_rect_changed` | `(rect: Rect2)` | SelectionManager | DragRect.set_rect() |
```gdscript
# main.gd
Events.selection_changed.connect(func(u: Array[Unit]) -> void: hud.refresh())
Events.unit_died.connect(func(u: Unit, _k: Unit) -> void: if u.is_player and u is Building: _check_victory())
```
约定：信号只用于「一对多广播」；一对一直接方法调用。

## 6. 数据驱动（数值全在 `.tres`）
```gdscript
# core/unit_stats.gd
class_name UnitStats
extends Resource
@export var display_name: String = "Unit"
@export var max_health: float = 100.0
@export var speed: float = 90.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 48.0
@export var attack_cooldown: float = 1.0
@export var acquire_range: float = 200.0
@export var leash_range: float = 260.0
@export var build_cost: int = 50
@export var is_ranged: bool = false
@export var projectile_speed: float = 320.0
@export var carry_capacity: int = 0        # 0 = 不采集
@export var harvest_rate: int = 1
@export var defend_radius: float = 320.0

# core/building_stats.gd
class_name BuildingStats
extends Resource
@export var max_health: float = 400.0
@export var build_cost: int = 0
@export var produces_unit: UnitStats       # null = 不生产
@export var produce_cost: int = 60
@export var production_time: float = 12.0
@export var is_mine: bool = false

# core/game_config.gd
class_name GameConfig
extends Resource
@export var map_size: Vector2i = Vector2i(4000, 3000)
@export var player_start: Vector2 = Vector2(400, 1500)
@export var enemy_start: Vector2 = Vector2(3600, 1500)
@export var resource_node_count: int = 6
```
`.tres` 清单：`resources/units/{soldier,tank}.tres`、`resources/buildings/{base,barracks,mine}.tres`、`resources/config/game_config.tres`。
引用方式：`@export var stats: UnitStats = preload("res://resources/units/soldier.tres")`。**不要用运行时 `load("res://" + 拼字符串)`**，会被导出依赖扫描剔除（R11）。

## 7. 导出流程（Windows → `build\RTSDemo.exe`）
变量约定：`$proj = 'E:\rts_demo'`；`$godot = 'E:\rts_demo\tools\godot\Godot_v4.7.2-stable_win64.exe'`（编辑器解压后实际路径）。
**① 安装导出模板**（版本目录名必须精确 `4.7.2.stable`，以 `version.txt` 为准）。`.tpz` 是 zip 且内含一层 `templates/`，直接解压到用户目录会多一层导致识别失败（R12）。已实测 4.7.2 **没有** `--install-export-templates` 这类 CLI 参数（只有 `--install-android-build-template`），所以只能 GUI 安装或手工拷贝到 `%APPDATA%\Godot\export_templates\4.7.2.stable\`。
```powershell
$ver = '4.7.2.stable'
$src = 'E:\rts_demo\tools\godot\tpl_extract\templates'   # .tpz 解压后的内层目录（含 version.txt）
$dst = Join-Path $env:APPDATA "Godot\export_templates\$ver"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item "$src\*" $dst -Recurse -Force
Get-Content (Join-Path $dst 'version.txt')          # 应输出 4.7.2.stable
```
更稳：编辑器 `Editor ▸ Manage Export Templates ▸ Install from File` 选 `tools\downloads\Godot_v4.7.2-stable_export_templates.tpz`（两条路都做一次，10 秒）。若解压目录名不同，用 `(Get-ChildItem 'E:\rts_demo\tools\godot' -Recurse -Filter version.txt | Select-Object -First 1).Directory.FullName` 自动定位。
**② 生成 `export_presets.cfg`（不要手写，R13）**：编辑器 `Project ▸ Export…` → `Add… ▸ Windows Desktop`（预设名保持 `Windows Desktop`，命令行按名匹配）→ Export Path = `build/RTSDemo.exe` → `Binary Format ▸ Embed PCK` **不勾** → 填 Product Name/Company → `Export Project` → `export_presets.cfg` 自动落盘，**提交进 Git**。
**③ 纯命令行导出**：
```powershell
& $godot --headless --path $proj --import            # 首次导入生成 .godot/imported（4.7.2 已确认存在）
# 备选： & $godot --headless --path $proj --editor --quit
New-Item -ItemType Directory -Force -Path "$proj\build" | Out-Null
& $godot --headless --path $proj --export-release "Windows Desktop" "$proj\build\RTSDemo.exe"
Get-ChildItem "$proj\build"
Start-Process "$proj\build\RTSDemo.exe"
```
报错对照：`No export template found` → 回 ① 查版本目录名；`preset not found` → 预设名必须与 `--export-release` 后字符串完全一致。
目录约定：`build/`、`tools/`、`.godot/` **不入 Git**；`export_presets.cfg`、`resources/**/*.tres` **入 Git**。

## 8. 工程规范
`.gitignore`：
```gitignore
# Godot 4 导入缓存与编辑器状态
.godot/
/android/
export_presets.cfg.bak
# 导出产物
/build/
/export/
*.exe
*.pck
*.zip
# 本地工具链（编辑器与模板，体积巨大）
/tools/
# 系统垃圾与本地秘密
.DS_Store
Thumbs.db
desktop.ini
*.tmp
.env
*.keystore
```
`.gitattributes`（`* text=auto eol=lf` 覆盖全部文本文件，`.gd/.tscn/.tres/.import` 自动 LF）：
```gitattributes
* text=auto eol=lf
*.png binary
*.ttf binary
```
提交信息（Conventional Commits）：`<type>(<scope>): <简短中文描述>`，`type ∈ feat|fix|chore|docs|refactor|perf|style|test|build`，`scope` 用模块名（unit/nav/ui/export/ai）。示例：
```
feat(nav): 烘焙障碍物导航多边形并验证绕行
build(export): 配置 Windows Desktop 预设并产出 RTSDemo.exe
```
README 必含：①简介+截图；②环境要求（Godot 4.7.2-stable、模板安装路径、Windows 11）；③从零运行（F5 与直接跑 exe）；④操作说明（左键框选/单击选中/右键移动/滚轮缩放/WASD 平移/采集造兵）；⑤玩法目标（采集→建兵营→造坦克→摧毁敌方基地）；⑥目录结构（引 §1）；⑦命令行导出步骤（引 §7.3，可直接复制）；⑧数值改哪里（`resources/**/*.tres`）；⑨已知限制 TODO（照实写）；⑩License 与字体/美术授权。

## 9. GitHub 推送（PAT 不进 URL、不进 .git/config、不进历史）
```powershell
cd E:\rts_demo
git init; git branch -M main
git add .; git commit -m "chore(git): 初始化 Godot 4 RTS demo 工程"
git remote add origin https://github.com/<OWNER>/<REPO>.git     # 绝不写 PAT
git remote -v                                                    # 确认无 token
# 一次性 header 推送（PAT 不落盘）
$cred = Get-Credential -UserName '<GitHub用户名>' -Message '输入 GitHub PAT'
$pair = "$($cred.UserName):$($cred.GetNetworkCredential().Password)"
$b64  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
git -c "http.https://github.com/.extraheader=Authorization: Basic $b64" push -u origin main
$cred = $null; $pair = $null; $b64 = $null
```
若已把 PAT 写进 URL：`git remote set-url origin https://github.com/<OWNER>/<REPO>.git` 覆盖，并**立刻到 GitHub Settings ▸ Developer settings ▸ PAT 吊销重发**（出现即视为泄露）。更省事：`git config --global credential.helper manager` 后 `git push -u origin main`，弹窗粘贴 PAT。
安全建议：PAT 只勾 `repo`/`public_repo`（**不勾 workflow、delete_repo、admin**）、设 30 天过期、当晚用完即撤；不要把 PAT 写进任何文档/截图；用 `git config --global --unset-all http.https://github.com/.extraheader` 清理持久化 header；公开仓库若 `git log -p` 出现过 token 也要 revoke。

## 10. 实现顺序与工时（合计 350 分钟 + 25 分钟缓冲）
| # | 步骤 | 分钟 | 累计 | 可降级 |
|---|---|---|---|---|
| 1 | 建目录、`project.godot`、input_map（右键/滚轮/WASD）、`.gitignore` | 15 | 15 | — |
| 2 | 编辑器首开：1920×1080、`stretch_mode=canvas_items`、`aspect=expand`、导入一次 | 15 | 30 | — |
| 3 | 地图 + 3 障碍 + **NavRegion 烘焙**，手工跑通绕行 | 30 | 60 | ⚠️ 最后才砍 |
| 4 | `Unit` 基类 + Soldier/Tank 场景 + 血条 + 受击/死亡 | 35 | 95 | — |
| 5 | `PathAgent` + 单位移动 + 右键移动指令 + 阵型散开 | 30 | 125 | — |
| 6 | `SelectionManager` 框选 + DragRect 画框 + 选中光圈 | 30 | 155 | — |
| 7 | 自动索敌 + 近战/炮击 + `Combat` + 死亡广播 | 30 | 185 | — |
| 8 | 建筑：基地/兵营/采矿站 + 生产 + 资源消耗 | 25 | 210 | ⚠️ |
| 9 | 采集闭环：矿点→背矿→回基地→加资源 | 25 | 235 | ⚠️ |
| 10 | HUD 资源面板 + 选中信息 + 事件接线 | 15 | 250 | — |
| 11 | 小地图 `_draw`（单位点 + 相机框） | 20 | 270 | ✅ |
| 12 | 敌方 AI：Commander 造兵 + ATTACK/DEFEND 状态机 | 25 | 295 | ⚠️ |
| 13 | 相机平移缩放 | 10 | 305 | ✅ |
| 14 | 胜利判定 + 胜负界面 | 10 | 315 | — |
| 15 | 导出预设 + 命令行导出 + exe 实测 | 20 | 335 | — |
| 16 | README + `git init/commit` + 推送 | 15 | 350 | — |
| — | 缓冲（调试/返工） | 25 | 375 | — |

## 11. 降级预案（按此顺序砍）
| 顺序 | 砍什么 | 省时 | 理由 |
|---|---|---|---|
| 1 | 小地图只画静态底图（不画单位点/相机框） | 15 min | 纯展示，不影响玩法闭环 |
| 2 | 敌方 AI 去掉 DEFEND 态，只做「定时造兵+波次直推」 | 15 min | 玩家感知最小 |
| 3 | 坦克炮弹改即时伤害+激光线，不做飞行物 | 20 min | 省掉 Projectile 场景与命中判定 |
| 4 | 采集改「矿点自动产出到基地」，去掉背包往返 | 25 min | 保留资源→造兵经济循环 |
| 5 | 血条改「仅选中单位显示」 | 10 min | 视觉弱化，信息保留 |
| 6 | 相机去边缘滚动，只留 WASD+滚轮缩放 | 5 min | 边缘滚动易与框选冲突 |
| 7 | 坦克与步兵只做数值差异，不做形态差异 | 15 min | 数值已在 `UnitStats` |
| 8 | 兵营不排队，点击即造（有冷却） | 10 min | 队列 UI 是纯增量工作 |
| 9 | 障碍绕行 → 直线+遇障停 | 20 min | **最后才砍**，核心卖点 |

**绝对不砍**：框选、右键移动、自动攻击、血条、资源面板、胜负判定——这 6 项决定 demo 成不成立。

## 12. 风险清单（Godot 4 特有坑 + 规避）
| # | 坑 | 规避 |
|---|---|---|
| R1 | Godot 3→4 差异：`await get_tree().create_timer(1.0)` 必须写 `.timeout`；`yield` 已删；`move_and_slide()` 属 CharacterBody2D；`export/onready` → `@export/@onready` | 全程只写 4.x 语法；不确定的 API 用编辑器 `Ctrl+Shift+X` 查文档 |
| R2 | autoload 与 `class_name` 同名 → "hides an autoload singleton" | autoload 脚本一律不写 `class_name` |
| R3 | 障碍物不绕行：`NavigationObstacle2D` 只做局部避让，不影响路径 | 障碍形状必须烘焙进 `NavRegion.navigation_polygon`，运行时确认 `NavRegion.enabled == true` |
| R4 | `NavigationAgent2D` 过早下发目标（地图未同步）→ 走直线/不动 | 设置目标前 `await get_tree().physics_frame` |
| R5 | 到达判定抖动 | `target_desired_distance`(14) > `radius`(10)，`path_desired_distance` 调大 |
| R6 | CharacterBody2D 与 agent 速度打架 | 只用 `get_next_path_position()` 给方向，速度由本体 `velocity` 控制再 `move_and_slide()`；别读 `agent.velocity` |
| R7 | Control 当世界血条：锚点/缩放与 Camera2D 不同步 | 世界 UI 用 `Node2D+_draw`；屏幕 UI 用 `CanvasLayer>Control`；全屏 HUD 必须 `MOUSE_FILTER_IGNORE`，否则吃掉框选 |
| R8 | `@onready var x: Type = $Path` 类型不匹配运行期才报错 | 用 `@onready var x := $Path` 让推断生效，或节点类型确与声明一致 |
| R9 | `Array[Unit]` 严格类型，塞 `Node2D` 运行期报 Invalid type | 组遍历后 `as Unit` 过滤，跨类型用 `Array[Node]` |
| R10 | `update()` vs `queue_redraw()` | 4.x 统一 `queue_redraw()`；`_draw()` 只绘制不改状态 |
| R11 | 导出后资源丢失（运行时字符串 `load()` 不被打包） | 用 `preload`/`@export` 静态引用 |
| R12 | 导出模板版本不匹配 | 目录名精确 `4.7.2.stable`，复制后 `Get-Content version.txt` 校验 |
| R13 | 手写 `export_presets.cfg` 字段缺失导出失败 | 只用 GUI 生成一次然后提交 |
| R14 | stretch 默认 `disabled` 导致 UI 与世界错位 | `Display ▸ Window ▸ Stretch Mode = canvas_items`，`Aspect = expand` |
| R15 | 默认字体无中文 → 方框 | 放可商用中文字体到 `assets/fonts/` 并在 HUD Theme 设 `default_font` |
| R16 | 手改 `project.godot` 损坏（`config_version` 必须 5） | 尽量用编辑器改；手改只加 `[input]` 段并保留 `config_version=5` |
| R17 | 每帧 `get_nodes_in_group()` 掉帧 | 索敌节流 0.2s；死亡时用信号维护缓存 |
| R18 | signal 参数类型要求对方已 `class_name`；`connect` 回调签名不匹配（可少不可多） | 参数类型只用已 `class_name` 的类型或 `Node2D`；回调写全量参数，多余用 `_` |
| R19 | 多实例共享 `.tres` 被改互相污染 | `.tres` 只读；运行期数值放成员变量（如 `health`），不回写资源 |
