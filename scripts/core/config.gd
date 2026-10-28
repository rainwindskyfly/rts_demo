class_name GameConfig
extends Resource
## Central tuning table for the whole demo.
##
## Everything the design document calls a "number" lives here, so balancing is
## a one-file edit. The class also owns the static map layout so the world
## builder and the AI read from exactly the same source of truth.

# ---------------------------------------------------------------- map layout
@export var map_size: Vector2 = Vector2(2400, 1350)
@export var player_start: Vector2 = Vector2(180, 1180)
@export var enemy_start: Vector2 = Vector2(2220, 170)
@export var window_size: Vector2i = Vector2i(1280, 720)

## Ore field layout: position + starting amount.
@export var ore_fields: Array[Dictionary] = [
	{"pos": Vector2(320, 1010), "amount": 900, "home": true},
	{"pos": Vector2(2080, 340), "amount": 900, "home": true},
	{"pos": Vector2(1200, 675), "amount": 1200, "home": false},
	{"pos": Vector2(620, 300), "amount": 800, "home": false},
	{"pos": Vector2(1780, 1050), "amount": 800, "home": false},
]

## Circular obstacles: position + radius. Symmetric about the map centre.
@export var obstacles: Array[Dictionary] = [
	{"pos": Vector2(900, 980), "radius": 130.0},
	{"pos": Vector2(1500, 370), "radius": 130.0},
	{"pos": Vector2(700, 520), "radius": 95.0},
	{"pos": Vector2(1700, 830), "radius": 95.0},
]

# ------------------------------------------------------------------ economy
@export var start_minerals: int = 350
@export var mineral_cap: int = 999
@export var max_workers: int = 5
@export var max_army: int = 40
@export var starting_workers: int = 2
@export var starting_infantry: int = 1

# -------------------------------------------------------------------- match
@export var match_length: float = 1200.0  ## 20 minutes

# --------------------------------------------------------------- unit stats
@export var infantry_stats: UnitStats
@export var tank_stats: UnitStats
@export var worker_stats: UnitStats

# ---------------------------------------------------------- building stats
@export var hq_stats: BuildingStats
@export var barracks_stats: BuildingStats
@export var refinery_stats: BuildingStats

## Build panel contents: kind is "building" or "unit"; stats is the matching
## Resource; cost is the mineral price; hotkey is the in-panel shortcut.
@export var build_menu: Array[Dictionary] = []

## Armour classes used by the damage table (docs/DESIGN.md §4.2).
enum Armor { LIGHT = 0, HEAVY = 1, STRUCTURE = 2 }


static func create_default() -> GameConfig:
	var c := GameConfig.new()

	c.infantry_stats = UnitStats.new()
	c.infantry_stats.display_name = "Infantry"
	c.infantry_stats.kind = 0
	c.infantry_stats.color = Color(0.42, 0.66, 0.92)
	c.infantry_stats.radius = 8.0
	c.infantry_stats.body_size = 11.0
	c.infantry_stats.max_health = 80.0
	c.infantry_stats.attack_damage = 8.0
	c.infantry_stats.attack_range = 26.0
	c.infantry_stats.attack_cooldown = 0.8
	c.infantry_stats.acquire_range = 150.0
	c.infantry_stats.is_ranged = false
	c.infantry_stats.speed = 130.0
	c.infantry_stats.build_cost = 50
	c.infantry_stats.build_time = 6.0

	c.tank_stats = UnitStats.new()
	c.tank_stats.display_name = "Tank"
	c.tank_stats.kind = 1
	c.tank_stats.color = Color(0.44, 0.52, 0.30)
	c.tank_stats.radius = 12.0
	c.tank_stats.body_size = 17.0
	c.tank_stats.max_health = 260.0
	c.tank_stats.attack_damage = 24.0
	c.tank_stats.attack_range = 220.0
	c.tank_stats.attack_cooldown = 1.6
	c.tank_stats.acquire_range = 320.0
	c.tank_stats.is_ranged = true
	c.tank_stats.projectile_speed = 320.0
	c.tank_stats.speed = 70.0
	c.tank_stats.build_cost = 150
	c.tank_stats.build_time = 14.0

	c.worker_stats = UnitStats.new()
	c.worker_stats.display_name = "Worker"
	c.worker_stats.kind = 2
	c.worker_stats.color = Color(0.93, 0.71, 0.28)
	c.worker_stats.radius = 7.0
	c.worker_stats.body_size = 9.0
	c.worker_stats.max_health = 45.0
	c.worker_stats.attack_damage = 4.0
	c.worker_stats.attack_range = 20.0
	c.worker_stats.attack_cooldown = 1.2
	c.worker_stats.acquire_range = 90.0
	c.worker_stats.is_ranged = false
	c.worker_stats.speed = 100.0
	c.worker_stats.build_cost = 40
	c.worker_stats.build_time = 5.0
	c.worker_stats.carry_capacity = 5
	c.worker_stats.harvest_rate = 5
	c.worker_stats.mining_time = 2.0
	c.worker_stats.is_combat_unit = false

	c.hq_stats = BuildingStats.new()
	c.hq_stats.display_name = "HQ"
	c.hq_stats.kind = 0
	c.hq_stats.color = Color(0.30, 0.48, 0.72)
	c.hq_stats.size = Vector2(56, 56)
	c.hq_stats.max_health = 1000.0
	c.hq_stats.armor = Armor.STRUCTURE
	c.hq_stats.deposit_radius = 70.0
	c.hq_stats.queue_size = 3
	c.hq_stats.can_be_built = false
	c.hq_stats.produces = [c.worker_stats]

	c.barracks_stats = BuildingStats.new()
	c.barracks_stats.display_name = "Barracks"
	c.barracks_stats.kind = 1
	c.barracks_stats.color = Color(0.36, 0.42, 0.52)
	c.barracks_stats.size = Vector2(38, 30)
	c.barracks_stats.max_health = 500.0
	c.barracks_stats.armor = Armor.STRUCTURE
	c.barracks_stats.build_cost = 120
	c.barracks_stats.build_time = 20.0
	c.barracks_stats.queue_size = 5
	c.barracks_stats.produces = [c.infantry_stats, c.tank_stats]

	c.refinery_stats = BuildingStats.new()
	c.refinery_stats.display_name = "Refinery"
	c.refinery_stats.kind = 2
	c.refinery_stats.color = Color(0.50, 0.45, 0.38)
	c.refinery_stats.size = Vector2(26, 26)
	c.refinery_stats.max_health = 300.0
	c.refinery_stats.armor = Armor.STRUCTURE
	c.refinery_stats.build_cost = 100
	c.refinery_stats.build_time = 15.0
	c.refinery_stats.deposit_radius = 70.0
	c.refinery_stats.must_be_on_ore = true
	c.refinery_stats.can_be_built = true

	c.build_menu = [
		{"kind": "building", "stats": c.barracks_stats, "label": "Barracks", "cost": 120, "hotkey": "1"},
		{"kind": "building", "stats": c.refinery_stats, "label": "Refinery", "cost": 100, "hotkey": "2"},
		{"kind": "unit", "stats": c.infantry_stats, "label": "Infantry", "cost": 50, "hotkey": "3"},
		{"kind": "unit", "stats": c.tank_stats, "label": "Tank", "cost": 150, "hotkey": "4"},
		{"kind": "unit", "stats": c.worker_stats, "label": "Worker", "cost": 40, "hotkey": "5"},
	]

	return c


## Damage multiplier table (docs/DESIGN.md §4.2).
## Only two entries differ from 1.0: infantry and workers are blunted by
## heavy armour. Returns 1.0 for every other combination.
static func damage_multiplier(attacker_kind: int, target_armor: int) -> float:
	if target_armor == Armor.HEAVY:
		if attacker_kind == 0:  # infantry
			return 0.5
		if attacker_kind == 2:  # worker
			return 0.25
	return 1.0


## Armour class of a unit archetype.
static func unit_armor(kind: int) -> int:
	if kind == 1:
		return Armor.HEAVY
	return Armor.LIGHT
