class_name Combatant
extends CharacterBody2D
## Shared base for everything that has health and can be attacked.
##
## `Unit` and `Building` both extend this. The indirection exists purely to
## break a cyclic class dependency: without it, `Unit` → `Projectile` → `Unit`
## (and `Unit` → `Building` → `Unit`) would be cyclic, which Godot 4 cannot
## resolve. Here the dependency graph is a strict tree:
##
##     Combatant ← Unit ← Projectile
##              ← Building
##
## `CharacterBody2D` is used for buildings too — they simply never move, but
## they inherit the collision plumbing that units need to path around them.

const FACTION_PLAYER: int = 0
const FACTION_ENEMY: int = 1

## Armour classes, mirrored from GameConfig.Armor.
const ARMOR_LIGHT: int = 0
const ARMOR_HEAVY: int = 1
const ARMOR_STRUCTURE: int = 2

var faction: int = FACTION_PLAYER
var armor_class: int = ARMOR_LIGHT
var max_health: float = 100.0
var health: float = 100.0
var alive: bool = true

var health_bar: HealthBar = null

## Seconds of invulnerability-free flash used when the unit is hit.
var _flash_time: float = 0.0
var _visual: Node2D = null


func _ready() -> void:
	add_to_group("combatants")
	if faction == FACTION_PLAYER:
		add_to_group("player_combatants")
	else:
		add_to_group("enemy_combatants")
	set_physics_process(true)


func is_alive() -> bool:
	return alive and health > 0.0


func health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(health / max_health, 0.0, 1.0)


func take_damage(amount: float, _source: Node = null) -> void:
	if not is_alive() or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_flash_time = 0.1
	if _visual != null:
		_visual.modulate = Color(1.0, 0.55, 0.55)
	if health_bar != null:
		health_bar.mark_damaged()
		health_bar.set_ratio(health_ratio())
	Events.unit_health_changed.emit(self, health_ratio())
	if health <= 0.0:
		die(_source)


func die(source: Node = null) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	# `source` may be a Unit or a Projectile. The projectile carries its
	# shooter, so the faction lookup stays duck-typed and no cyclic
	# dependency on `Unit` is introduced here.
	var killer_faction: Variant = null
	if source != null:
		killer_faction = source.get("faction")
	if killer_faction != null and int(killer_faction) == FACTION_PLAYER:
		Game.stat_kills += 1
	Events.unit_died.emit(self, source)
	_on_died(source)
	queue_free()


func _on_died(_source: Node) -> void:
	pass


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0 and _visual != null:
			_visual.modulate = Color(1, 1, 1, 1)


func faction_name() -> String:
	return "Player" if faction == FACTION_PLAYER else "Enemy"
