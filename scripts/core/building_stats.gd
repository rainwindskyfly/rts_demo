class_name BuildingStats
extends Resource
## Immutable tuning numbers for one building archetype.
##
## Mirrors `docs/DESIGN.md` §4.7.

@export_group("Identity")
@export var display_name: String = "Building"
@export var kind: int = 0  ## 0 = HQ, 1 = barracks, 2 = refinery
@export var color: Color = Color(0.7, 0.7, 0.6)
@export var size: Vector2 = Vector2(40, 40)

@export_group("Combat")
@export var max_health: float = 400.0
@export var armor: int = 2  ## 0 = light, 1 = heavy, 2 = structure

@export_group("Economy")
@export var build_cost: int = 0
@export var build_time: float = 0.0
@export var deposit_radius: float = 70.0

@export_group("Production")
@export var produces: Array[UnitStats] = []
@export var queue_size: int = 3
## A refinery must be placed on top of an ore field.
@export var must_be_on_ore: bool = false
@export var can_be_built: bool = true
