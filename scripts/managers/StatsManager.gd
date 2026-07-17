# StatsManager.gd
# The run's memory (P7 / DEP-6): lifetime counters, a data-driven achievement
# list that reads them, and the graveyard-wide RESTORATION meter — the game's
# long-term spine. Counters arrive two ways:
#   - zero-coupling signals subscribed here (harvests, breaks, crafts)
#   - one-line bump() calls at the few sites signals don't cover
#     (combat endings, raisings, offerings, gold income)
# Saved with the run under "stats"; achievements toast once, ever.
#
# Talks to: GameManager / AlchemyManager / ForgeManager (signals),
# NotificationManager (toasts), SaveManager (persistence), NavigationPanel
# (restoration readout), CombatView / MinionManager / InventoryView (bumps).
extends Node

## Counter keys (kept as plain strings in one place; the save stores them verbatim).
const STAT_HARVESTS := "harvests"
const STAT_BREAKS := "breaks"
const STAT_CRAFTS := "crafts"
const STAT_FIGHTS_WON := "fights_won"
const STAT_FIGHTS_LOST := "fights_lost"
const STAT_BOSSES_SLAIN := "bosses_slain"
const STAT_MINIONS_RAISED := "minions_raised"
const STAT_OFFERINGS := "offerings"
const STAT_GOLD_EARNED := "gold_earned"
const STAT_PLAYTIME := "playtime_seconds"

## The achievement book: unlocked when `stat` reaches `at`. Order = display order.
const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "first_dig", "name": "First Shift", "stat": STAT_HARVESTS, "at": 10,
		"blurb": "Ten harvests worked. The grounds notice."},
	{"id": "steady_hands", "name": "Steady Hands", "stat": STAT_HARVESTS, "at": 500,
		"blurb": "Five hundred harvests. The tools know your grip."},
	{"id": "wall_breaker", "name": "Wall Breaker", "stat": STAT_BREAKS, "at": 50,
		"blurb": "Fifty nodes broken open."},
	{"id": "first_blood", "name": "First Blood", "stat": STAT_FIGHTS_WON, "at": 1,
		"blurb": "The warband's first victory."},
	{"id": "boss_taker", "name": "Warden No More", "stat": STAT_BOSSES_SLAIN, "at": 1,
		"blurb": "A boss has fallen to the dead."},
	{"id": "full_roster", "name": "Full Plots", "stat": STAT_MINIONS_RAISED, "at": 4,
		"blurb": "Every minion type raised from the earth."},
	{"id": "generous_dead", "name": "The Generous Dead", "stat": STAT_OFFERINGS, "at": 25,
		"blurb": "Twenty-five offerings laid on the altar."},
	{"id": "cottage_industry", "name": "Cottage Industry", "stat": STAT_CRAFTS, "at": 50,
		"blurb": "Fifty things brewed or smithed."},
	{"id": "grave_fortune", "name": "Grave Fortune", "stat": STAT_GOLD_EARNED, "at": 10000,
		"blurb": "Ten thousand gold pulled from the dark."},
]

## Restoration weights (must sum to 100): what share of the graveyard each
## pillar of the fiction restores.
const RESTORE_STRUCTURES := 40.0   # built tiers / total buildable tiers
const RESTORE_SKILLS := 30.0       # summed skill levels / (skills × MAX_LEVEL)
const RESTORE_MINIONS := 15.0      # raised / minion types
const RESTORE_BOSSES := 15.0       # distinct encounter kinds beaten (approx by count, capped)
const RESTORE_BOSS_CAP := 11       # boss nodes authored today

var stats: Dictionary = {}
## Achievement ids already earned (never toast twice).
var earned: Array = []
## Fired once when restoration first reaches 100%.
var restoration_celebrated: bool = false

func _ready() -> void:
	GameManager.harvest_completed.connect(func(_node_id): bump(STAT_HARVESTS))
	GameManager.node_broken.connect(func(_node_id): bump(STAT_BREAKS))
	AlchemyManager.brew_completed.connect(func(_recipe_id): bump(STAT_CRAFTS))
	ForgeManager.brew_completed.connect(func(_recipe_id): bump(STAT_CRAFTS))

func _process(delta: float) -> void:
	# Playtime accrues quietly; no achievement reads it (yet), so no checks.
	stats[STAT_PLAYTIME] = float(stats.get(STAT_PLAYTIME, 0.0)) + delta

func reset_state() -> void:
	stats.clear()
	earned.clear()
	restoration_celebrated = false

func get_stat(key: String) -> float:
	return float(stats.get(key, 0.0))

## Adds to a counter and checks the achievement book against its new value.
func bump(key: String, amount: float = 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount
	for entry in ACHIEVEMENTS:
		if entry["stat"] != key or earned.has(entry["id"]):
			continue
		if get_stat(key) >= float(entry["at"]):
			earned.append(entry["id"])
			NotificationManager.show_item("Achievement — %s: %s" % [entry["name"], entry["blurb"]], 1)
	_check_restoration()

func has_achievement(achievement_id: String) -> bool:
	return earned.has(achievement_id)

# --- Restoration: the graveyard-wide % (the missing spine) -------------

func get_restoration_pct() -> float:
	# Structures: built tiers over every buildable tier.
	var built := 0
	var buildable := 0
	for structure_id in GroundsManager.structure_db:
		buildable += GroundsManager.structure_db[structure_id].max_level()
		built += GroundsManager.get_level(structure_id)
	var s_part = (float(built) / float(buildable) if buildable > 0 else 0.0) * RESTORE_STRUCTURES
	# Skills: summed levels over the ceiling.
	var levels := 0
	for skill_key in GameManager.skills:
		levels += int(GameManager.skills[skill_key]["level"])
	var k_part = float(levels) / float(GameManager.skills.size() * GameManager.MAX_LEVEL) * RESTORE_SKILLS
	# Minions: raised over the roster of types.
	var m_part = (float(MinionManager.roster.size()) / float(maxi(MinionManager.minion_db.size(), 1))) * RESTORE_MINIONS
	# Bosses: victories over the authored boss count (capped).
	var b_part = minf(get_stat(STAT_BOSSES_SLAIN), float(RESTORE_BOSS_CAP)) / float(RESTORE_BOSS_CAP) * RESTORE_BOSSES
	return clampf(s_part + k_part + m_part + b_part, 0.0, 100.0)

func _check_restoration() -> void:
	if restoration_celebrated:
		return
	if get_restoration_pct() >= 100.0:
		restoration_celebrated = true
		NotificationManager.show_item("THE GRAVEYARD BREATHES AGAIN — every stone reclaimed. Mortimer would weep, had he eyes.", 1)

# --- Save / Load ---

func get_save_data() -> Dictionary:
	return {
		"stats": stats.duplicate(),
		"earned": earned.duplicate(),
		"restoration_celebrated": restoration_celebrated,
	}

func restore_from_save(data: Dictionary) -> void:
	stats.clear()
	var saved = data.get("stats", {})
	for key in saved:
		stats[key] = float(saved[key])
	earned.clear()
	for a in data.get("earned", []):
		earned.append(str(a))
	restoration_celebrated = bool(data.get("restoration_celebrated", false))
