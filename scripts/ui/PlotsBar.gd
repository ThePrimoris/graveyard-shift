# PlotsBar.gd
# The Graveyard Plots dock at the bottom center of the screen: a central
# circle flanked by plots 1-2 on the left and 3-4 on the right.
# Placeholder for now — slotting behaviour returns with the minion rework.
extends Control

# Plot occupants, index 0-3 = plots 1-4. Null means empty.
var plots: Array = [null, null, null, null]

var plot_buttons: Array = []

@onready var circle_button: Button = %CircleButton

func _ready() -> void:
	add_to_group("ui_updates")

	for i in range(1, 5):
		var btn: Button = get_node("%%PlotButton%d" % i)
		plot_buttons.append(btn)
		btn.pressed.connect(_on_plot_pressed.bind(i - 1))

	circle_button.pressed.connect(_on_circle_pressed)
	update_ui()

func _on_plot_pressed(_index: int) -> void:
	# Slotting arrives with the minion rework.
	pass

func _on_circle_pressed() -> void:
	# The central rite arrives with the minion rework.
	pass

func update_ui() -> void:
	for i in range(plot_buttons.size()):
		var btn: Button = plot_buttons[i]
		if plots[i] == null:
			btn.text = str(i + 1)
			btn.tooltip_text = "Graveyard Plot %d — empty" % (i + 1)
		else:
			btn.text = str(plots[i])
			btn.tooltip_text = "Graveyard Plot %d" % (i + 1)
