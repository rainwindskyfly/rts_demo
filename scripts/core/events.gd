extends Node
## Global signal bus.
##
## Rules that keep this acyclic and safe:
##  * This autoload must NOT declare a `class_name` (it would shadow the singleton).
##  * Signal payloads are typed with built-in classes or `Node` only. Custom
##    `class_name` types are intentionally avoided here so that no script can
##    form a cyclic dependency through the autoload.

## Emitted when a unit dies. `killer` may be null.
signal unit_died(unit: Node, killer: Node)
## Emitted when a building is destroyed. `building` is the destroyed node.
signal building_destroyed(building: Node)
## Emitted whenever the player's mineral count changes.
signal minerals_changed(current: int, delta: int)
## Emitted when the enemy faction gathers minerals (the AI has its own purse).
signal enemy_minerals_gained(amount: int)
## Emitted when the selection set changes. `units` is an Array of Node.
signal selection_changed(units: Array)
## Emitted when the player issues an order (move / attack / harvest / build).
signal order_issued(order: Dictionary)
## Emitted when a building finishes construction.
signal building_ready(building: Node)
## Emitted when the match ends. `result` is a Game.MatchResult value.
signal match_ended(result: int)
## Emitted every time the match timer ticks, with remaining seconds.
signal match_timer_updated(remaining: float)
## Emitted when the HUD should show a transient toast message.
signal toast(message: String, kind: int)
## Emitted when the build-mode entry changes (-1 = closed, otherwise an index).
signal build_mode_changed(entry: int)
## Emitted when a unit's health changes so the HUD/minimap can refresh.
signal unit_health_changed(unit: Node, ratio: float)
