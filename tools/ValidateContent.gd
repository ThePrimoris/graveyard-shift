# ValidateContent.gd
# Headless entry point for the QA-2 content check. Run it with:
#   godot --headless --path . res://tools/ValidateContent.tscn
# Exits 0 when all content is valid, or the number of problems found (non-zero),
# so it drops straight into CI or a pre-commit hook.
extends Node

func _ready() -> void:
	# Give the autoloads (GameManager et al.) a frame to finish building their
	# registries before we validate.
	await get_tree().process_frame
	var count := ContentValidator.run_and_print()
	get_tree().quit(count)
