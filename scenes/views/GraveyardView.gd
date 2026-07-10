extends HarvestView

func _init() -> void:
	action_verb = "Digging"
	progress_color = Color("#c8a24d")
	progress_mode = ActionCard.ProgressMode.FILL
	ambience = Color(0.06, 0.052, 0.082)  # moonlit graveyard violet
