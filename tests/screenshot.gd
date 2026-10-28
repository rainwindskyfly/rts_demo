extends Node
## Renders the game and writes a PNG of the viewport.
##
## Run it with:
##   godot --path . res://tests/Screenshot.tscn --fixed-fps 60 --resolution 1280x720
##
## It boots the real Main scene, lets the simulation run for a few seconds so
## the workers are already moving and mining, selects the player's units so the
## selection rings are visible, then captures the viewport.
##
## This must NOT run with `--headless`: the headless display driver has no
## rendering backend, so the captured image would be empty.

const OUTPUT_PATH := "res://build/screenshot.png"
const SETTLE_FRAMES: int = 300  # 5 simulated seconds


func _ready() -> void:
	print("[shot] booting Main scene...")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	add_child(main)

	# Let the world settle: workers walk to the ore and start mining.
	for i in SETTLE_FRAMES:
		await get_tree().process_frame

	# Select the player's units so the screenshot shows selection feedback.
	var selection := get_tree().get_first_node_in_group("selection_manager")
	if selection != null:
		for node in Game.player_units:
			var unit := node as Unit
			if unit != null and unit.is_alive():
				selection.select(unit, true)

	for i in 10:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		print("[shot] FAILED to save: ", error)
	else:
		print("[shot] saved ", OUTPUT_PATH, " (", image.get_width(), "x", image.get_height(), ")")
	get_tree().quit(0 if error == OK else 1)
