class_name InputSetup
extends RefCounted
## Registers every InputMap action at runtime.
##
## Writing `project.godot`'s `[input]` section by hand is brittle and easy to
## corrupt, so the actions are declared in code instead. Call `InputSetup.apply()`
## once at startup.

const ACTIONS := {
	"cam_up": [KEY_W, KEY_UP],
	"cam_down": [KEY_S, KEY_DOWN],
	"cam_left": [KEY_A, KEY_LEFT],
	"cam_right": [KEY_D, KEY_RIGHT],
	"cam_boost": [KEY_SHIFT],
	"select_all": [KEY_A],
	"stop_order": [KEY_S],
	"focus_base": [KEY_H],
	"focus_battle": [KEY_SPACE],
	"toggle_build": [KEY_B],
	"cancel": [KEY_ESCAPE],
	"help": [KEY_F1],
	"group_1": [KEY_1],
	"group_2": [KEY_2],
	"group_3": [KEY_3],
	"group_4": [KEY_4],
	"group_5": [KEY_5],
	"group_6": [KEY_6],
	"group_7": [KEY_7],
	"group_8": [KEY_8],
	"group_9": [KEY_9],
}


static func apply() -> void:
	for action_name in ACTIONS.keys():
		var action := StringName(action_name)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in ACTIONS[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

	# Ctrl+A / Ctrl+1..9 use their own modifier-aware events because the plain
	# digit bindings above must stay usable on their own.
	_add_ctrl_variant("select_all", KEY_A)
	for i in range(1, 10):
		_add_ctrl_variant("group_%d" % i, KEY_0 + i)


static func _add_ctrl_variant(action: StringName, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.ctrl_pressed = true
	InputMap.action_add_event(action, ev)
