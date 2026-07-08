extends HarvestView

func _init() -> void:
	action_verb = "Chopping"
	progress_color = Color("#4c9a47")
	progress_mode = ActionCard.ProgressMode.SEGMENTS

## Bigger trees take more chop bars: 2 for saplings up to 4 for the ancients.
func _segments_for(node: HarvestNode) -> int:
	if node.required_level >= 70: return 4
	if node.required_level >= 25: return 3
	return 2
