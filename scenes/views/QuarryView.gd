extends HarvestView

func _init() -> void:
	action_verb = "Mining"
	progress_color = Color("#5a7fa8")
	progress_mode = ActionCard.ProgressMode.DEPLETE
	ambience = Color(0.042, 0.049, 0.07)  # cold mineshaft blue-grey
