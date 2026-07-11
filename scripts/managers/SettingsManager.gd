# SettingsManager.gd
# Player preferences that live OUTSIDE the run save (they survive hard
# resets): currently the window mode/size choice. Stored in their own
# settings file and applied at boot.
extends Node

const SETTINGS_PATH: String = "user://graveyard_shift_settings.json"

## The window choices offered in Settings, in display order.
## Fixed sizes stay above the game's minimum window size (1160x660).
const WINDOW_CHOICES: Array[Dictionary] = [
	{"id": "fullscreen", "label": "Fullscreen"},
	{"id": "maximized", "label": "Maximized window"},
	{"id": "1280x720", "label": "1280 × 720", "size": Vector2i(1280, 720)},
	{"id": "1366x768", "label": "1366 × 768", "size": Vector2i(1366, 768)},
	{"id": "1600x900", "label": "1600 × 900", "size": Vector2i(1600, 900)},
	{"id": "1920x1080", "label": "1920 × 1080", "size": Vector2i(1920, 1080)},
	{"id": "2560x1440", "label": "2560 × 1440", "size": Vector2i(2560, 1440)},
]

var window_choice: String = "maximized"

func _ready() -> void:
	load_settings()
	call_deferred("apply_window_choice")

# --- Window choice ---

func get_choice_labels() -> Array:
	var labels: Array = []
	for choice in WINDOW_CHOICES:
		labels.append(choice["label"])
	return labels

func get_choice_index(choice_id: String) -> int:
	for i in range(WINDOW_CHOICES.size()):
		if WINDOW_CHOICES[i]["id"] == choice_id:
			return i
	return 1  # maximized

## Sets, applies, and persists the player's window choice.
func set_window_choice_by_index(index: int) -> void:
	if index < 0 or index >= WINDOW_CHOICES.size(): return
	window_choice = WINDOW_CHOICES[index]["id"]
	apply_window_choice()
	save_settings()

## Pushes the stored choice onto the actual OS window. No-op in headless
## runs (tests) where there is no window to move.
func apply_window_choice() -> void:
	if DisplayServer.get_name() == "headless": return
	var window = get_window()
	if window == null: return

	var choice = WINDOW_CHOICES[get_choice_index(window_choice)]
	match choice["id"]:
		"fullscreen":
			window.mode = Window.MODE_FULLSCREEN
		"maximized":
			window.mode = Window.MODE_MAXIMIZED
		_:
			window.mode = Window.MODE_WINDOWED
			var size: Vector2i = choice["size"]
			window.size = size
			# Center on the current screen's usable area
			var screen = DisplayServer.screen_get_usable_rect(window.current_screen)
			window.position = screen.position + (screen.size - size) / 2

# --- Persistence (separate from the run save; survives hard resets) ---

func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if not file:
		push_warning("SettingsManager: could not write settings file.")
		return
	file.store_string(JSON.stringify({"window_choice": window_choice}))
	file.close()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH): return
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file: return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var stored = str(parsed.get("window_choice", "maximized"))
		window_choice = WINDOW_CHOICES[get_choice_index(stored)]["id"]
