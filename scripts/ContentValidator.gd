# ContentValidator.gd
# QA-2: a content-integrity pass over every `.tres`. Broken resource references
# in Godot fail *silently* at runtime (a missing item shows up as a null), so
# content bugs can ship unnoticed. This loads all content and asserts the things
# code assumes: loot pools point at real items, zones at real nodes, costs at
# real items, boss nodes at real encounters, and every affix/effect id is one the
# code actually handles (via Ids). Each problem is reported with its file path.
#
# Runs three ways:
#   - headless tool:  res://tools/ValidateContent.tscn  (CI / pre-commit)
#   - the smoke test: tests/SmokeTest.gd calls validate()
#   - debug boot:     GameManager warns on any failure when OS.is_debug_build()
#
# Talks to: Ids (known id lists), GameManager (AFFIXES + SkillType), and the
# `.tres` content directly (loaded fresh, independent of the runtime registries
# so it also catches files that failed to register at all).
class_name ContentValidator
extends RefCounted

const ITEM_DIRS: Array[String] = ["res://data/items/materials/", "res://data/items/tools/"]
const NODE_DIRS: Array[String] = ["res://data/nodes/graves/", "res://data/nodes/trees/", "res://data/nodes/mines/"]
const ZONE_DIRS: Array[String] = ["res://data/zones/"]
const MINION_DIRS: Array[String] = ["res://data/minions/"]
const ENCOUNTER_DIRS: Array[String] = ["res://data/encounters/"]
const STRUCTURE_DIRS: Array[String] = ["res://data/structures/"]

const NODE_LOOT_POOLS: Array[String] = ["common_pool", "rare_pool", "hit_pool", "break_pool"]

## Validates all content. Returns one human-readable error per problem (each
## naming the offending file), or an empty array when everything checks out.
static func validate() -> Array[String]:
	var errors: Array[String] = []

	# --- Build the id sets we validate references against ---
	var item_ids := {}
	for e in _load_dirs(ITEM_DIRS):
		if e.res is Item and e.res.id != "":
			item_ids[e.res.id] = true

	var encounter_ids := {}
	for e in _load_dirs(ENCOUNTER_DIRS):
		if e.res is Encounter and e.res.id != "":
			encounter_ids[e.res.id] = true

	# --- Nodes: loot pools, affix ids, boss encounters ---
	for e in _load_dirs(NODE_DIRS):
		if not (e.res is HarvestNode):
			continue
		var node: HarvestNode = e.res
		for pool_name in NODE_LOOT_POOLS:
			var pool: Array = node.get(pool_name)
			for i in pool.size():
				var drop = pool[i]
				if drop == null:
					errors.append("%s: %s[%d] is a null LootDrop (broken sub-resource)" % [e.path, pool_name, i])
				elif drop.item == null:
					errors.append("%s: %s[%d] has no item (broken item reference)" % [e.path, pool_name, i])
		if node.affix != "" and not Ids.AFFIX_ALL.has(node.affix):
			errors.append("%s: unknown affix id '%s' (not in Ids.AFFIX_ALL)" % [e.path, node.affix])
		if node.encounter_id != "" and not encounter_ids.has(node.encounter_id):
			errors.append("%s: encounter_id '%s' matches no encounter" % [e.path, node.encounter_id])
		if node.is_boss and node.encounter_id == "":
			errors.append("%s: is_boss is set but encounter_id is empty" % e.path)

	# --- Zones: every listed node must resolve ---
	for e in _load_dirs(ZONE_DIRS):
		if not (e.res is HarvestZone):
			continue
		var zone: HarvestZone = e.res
		for i in zone.nodes.size():
			if zone.nodes[i] == null:
				errors.append("%s: nodes[%d] is null (broken node reference)" % [e.path, i])

	# --- Structures: known effect, cost items exist ---
	for e in _load_dirs(STRUCTURE_DIRS):
		if not (e.res is Structure):
			continue
		var structure: Structure = e.res
		if not Ids.EFFECT_ALL.has(structure.effect):
			errors.append("%s: unknown effect id '%s' (not in Ids.EFFECT_ALL)" % [e.path, structure.effect])
		for i in structure.tiers.size():
			var tier = structure.tiers[i]
			if tier == null:
				errors.append("%s: tiers[%d] is null" % [e.path, i])
				continue
			for cost_id in tier.cost:
				if not item_ids.has(cost_id):
					errors.append("%s: tier %d cost references unknown item '%s'" % [e.path, i + 1, cost_id])

	# --- Minions: raise cost items exist, ability effects are known ---
	for e in _load_dirs(MINION_DIRS):
		if not (e.res is Minion):
			continue
		var minion: Minion = e.res
		for cost_id in minion.raise_cost:
			if not item_ids.has(cost_id):
				errors.append("%s: raise_cost references unknown item '%s'" % [e.path, cost_id])
		for ability in minion.abilities:
			if ability == null:
				errors.append("%s: has a null ability" % e.path)
				continue
			if ability.kind == MinionAbility.Kind.PASSIVE:
				if not (Ids.EFFECT_ALL.has(ability.effect) or Ids.COMBAT_EFFECT_ALL.has(ability.effect)):
					errors.append("%s: passive '%s' has unknown effect '%s' (not a known gather or combat effect)" % [e.path, ability.id, ability.effect])
			elif ability.kind == MinionAbility.Kind.ACTIVE:
				if not Ids.ACTIVE_ALL.has(ability.effect):
					errors.append("%s: active '%s' has unknown effect '%s' (not in Ids.ACTIVE_ALL)" % [e.path, ability.id, ability.effect])

	# --- Encounters: every listed enemy must resolve ---
	for e in _load_dirs(ENCOUNTER_DIRS):
		if not (e.res is Encounter):
			continue
		var encounter: Encounter = e.res
		for i in encounter.enemies.size():
			if encounter.enemies[i] == null:
				errors.append("%s: enemies[%d] is null (broken enemy reference)" % [e.path, i])

	# --- Internal consistency: the Ids lists must match the code they mirror ---
	errors.append_array(_validate_ids_match())

	return errors

## Guards against the Ids.* mirror drifting from the code it stands in for.
static func _validate_ids_match() -> Array[String]:
	var errors: Array[String] = []

	# AFFIXES (GameManager's registry) vs Ids.AFFIX_ALL.
	var affix_keys := GameManager.AFFIXES.keys()
	for key in affix_keys:
		if not Ids.AFFIX_ALL.has(key):
			errors.append("Ids.AFFIX_ALL is missing '%s' (present in GameManager.AFFIXES)" % key)
	for known in Ids.AFFIX_ALL:
		if not affix_keys.has(known):
			errors.append("GameManager.AFFIXES is missing '%s' (present in Ids.AFFIX_ALL)" % known)

	# SkillType enum names vs Ids.SKILL_ALL.
	for skill_name in GameManager.SkillType.keys():
		if not Ids.SKILL_ALL.has(str(skill_name).to_lower()):
			errors.append("Ids.SKILL_ALL is missing skill '%s' (in GameManager.SkillType)" % str(skill_name).to_lower())

	return errors

## Loads every `.tres` in the given dirs, keeping each resource's file path for
## error reporting. Returns an Array of { "res": Resource, "path": String }.
static func _load_dirs(dirs: Array[String]) -> Array:
	var out: Array = []
	for dir_path in dirs:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			push_warning("ContentValidator: could not open directory " + dir_path)
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var full := dir_path + file_name.replace(".remap", "")
				var res = load(full)
				if res != null:
					out.append({"res": res, "path": full})
				else:
					push_warning("ContentValidator: failed to load " + full)
			file_name = dir.get_next()
		dir.list_dir_end()
	return out

## Convenience for headless runs: prints each error and returns the count
## (0 = clean). Suitable as a process exit code.
static func run_and_print() -> int:
	var errors := validate()
	if errors.is_empty():
		print("ContentValidator: PASS — all content valid.")
		return 0
	print("ContentValidator: %d problem(s) found:" % errors.size())
	for err in errors:
		print("  - " + err)
	return errors.size()
