class_name UnitStats
extends Resource
## Immutable tuning numbers for one unit archetype.
##
## Values are mirrored from `docs/DESIGN.md` §4.2 so the design document and
## the running game never drift apart.

@export_group("Identity")
@export var display_name: String = "Unit"
@export var kind: int = 0  ## 0 = infantry, 1 = tank, 2 = worker
@export var color: Color = Color(0.6, 0.7, 0.8)
@export var radius: float = 9.0
@export var body_size: float = 11.0

@export_group("Combat")
@export var max_health: float = 100.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 40.0
@export var attack_cooldown: float = 1.0
@export var acquire_range: float = 160.0
@export var is_ranged: bool = false
@export var projectile_speed: float = 320.0

@export_group("Movement")
@export var speed: float = 100.0
@export var turn_speed: float = 10.0

@export_group("Economy")
@export var build_cost: int = 50
@export var build_time: float = 6.0
@export var carry_capacity: int = 0  ## > 0 makes this unit a harvester
@export var harvest_rate: int = 5     ## ore taken per mining cycle
@export var mining_time: float = 2.0  ## seconds per mining cycle

@export_group("Rules")
@export var can_be_built: bool = true
@export var is_combat_unit: bool = true
