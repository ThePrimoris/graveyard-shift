extends PanelContainer

## Drag and drop your rock node .tres files here in the Inspector.
## Order them to match your physical UI cards below.
@export var active_nodes: Array[HarvestNode] = []

# Dynamic tracking for progress bars: { "limestone": 0.0, "slate": 0.0 }
var node_progress: Dictionary = {}

@onready var cards: Array = [
	%VerdSeamsRocks,
	%EmberFissureRocks,
	%HollowCragRocks,
    %PeridotPitsRocks,
	%ObsidianChasmRocks
]

func _ready() -> void:
	add_to_group("ui_updates")
	
	# Loop through all physical cards to ensure they are initialized safely
	for i in range(cards.size()):
		var card = cards[i]
		if not card: continue
		
		# Check if we have a matching data resource file configured for this slot
		if i < active_nodes.size() and active_nodes[i] != null:
			var node_data = active_nodes[i]
			node_progress[node_data.id] = 0.0
			
			card.setup_card(node_data.name, node_data.description, "Mining", node_data.base_duration)
			card.set_progress_color("#5a7fa8") # Keeps your clean blue quarry progress bars!
			card.visible = true
			
			# Bind the current card instance cleanly to the custom engine signal
			card.action_triggered.connect(func():
				print("[Signal Debug] Clicked action button on rock node: ", card.name)
				GameManager.register_activity(card)
			)
		else:
			# Fallback if you haven't assigned a rock .tres asset to this slot yet
			card.setup_card("Undiscovered Vein", "No resource file assigned.", "Mine", 3.0)
			card.action_button.disabled = true

	update_ui()

func _process(delta: float) -> void:
	# Keep a lightweight global action print tracker running for debugging
	if GameManager.active_action_source != null and Engine.get_frames_drawn() % 60 == 0:
		print("[Process Debug] GameManager says active source node is: ", GameManager.active_action_source.name)

	for i in range(active_nodes.size()):
		var node_data = active_nodes[i]
		var card = cards[i]
		
		if not node_data or not card: continue
		
		if GameManager.active_action_source == card:
			node_progress[node_data.id] += delta
			
			if node_progress[node_data.id] >= node_data.base_duration:
				node_progress[node_data.id] = 0.0
				_process_harvest_rewards(node_data)
				
			card.update_progress(node_progress[node_data.id])
		else:
			if node_progress[node_data.id] > 0.0:
				node_progress[node_data.id] = 0.0
				card.update_progress(0.0)

func _process_harvest_rewards(node: HarvestNode) -> void:
	# Keep your minion system bonus calculations intact
	var minion_bonus = 0.0
	if "minions" in GameManager and GameManager.minions.size() > 0:
		minion_bonus = GameManager.minions[0].get("count", 0) * GameManager.minions[0].get("production", 0.0)
		
	var multiplier = 1 + floor(minion_bonus)
	
	# Roll all 3 loot table tiers mapped out in your node .tres asset
	_roll_loot(node.primary_drop, node.primary_chance, multiplier)
	_roll_loot(node.secondary_drop, node.secondary_chance, multiplier)
	_roll_loot(node.tertiary_drop, node.tertiary_chance, multiplier)
	
	# Dynamically convert the SkillType Enum back to a lowercase string key ("spelunking")
	var skill_key = GameManager.SkillType.keys()[node.required_skill].to_lower()
	
	# Safely award your mining experience to the GameManager dictionary
	GameManager.add_xp(skill_key, node.base_xp)
	
	# Historical compatibility legacy checks for global stone counters
	if "stone" in GameManager:
		GameManager.stone += 1.0 * multiplier
		
	# Historical compatibility check for your custom fossil/bone shard mechanics
	if "bones" in GameManager and skill_key == "spelunking":
		var fossil_chance = 0.05 + (GameManager.skills["spelunking"]["level"] * 0.01)
		if randf() <= fossil_chance:
			GameManager.bones += 1.0
			print("Unearthed a fossilized bone shard inside the stone!")

func _roll_loot(item_resource: Resource, drop_chance: float, multiplier: int) -> void:
	if item_resource == null or drop_chance <= 0.0: return
	
	if randf() <= drop_chance:
		InventoryManager.add_item(item_resource, multiplier)
		
		var visual_name: String = ""
		
		if "Name" in item_resource:
			visual_name = item_resource.Name
		elif "item_name" in item_resource:
			visual_name = item_resource.item_name
		elif "name" in item_resource:
			visual_name = item_resource.name
		elif "display_name" in item_resource:
			visual_name = item_resource.display_name
		else:
			visual_name = item_resource.resource_path.get_file().get_basename().capitalize()
		
		NotificationManager.show_item(visual_name, multiplier, item_resource)

func update_ui() -> void:
	var tool = GameManager.active_tool
	
	for i in range(cards.size()):
		var card = cards[i]
		if not card: continue
		
		card.set_button_text(GameManager.active_action_source == card)
		
		if i < active_nodes.size() and active_nodes[i] != null:
			var node = active_nodes[i]
			card.progress_bar.max_value = node.base_duration
			
			# Convert the Enum index back to a lowercase string key for level checks
			var skill_key = GameManager.SkillType.keys()[node.required_skill].to_lower()
			var s_level = GameManager.skills[skill_key]["level"] if skill_key in GameManager.skills else 1
			
			var level_met = s_level >= node.required_level
			var tool_type_met = (node.required_tool_tier == ToolData.ToolTier.RUSTED) or (tool != null and tool.tool_type == node.required_tool_type)
			var tool_tier_met = (node.required_tool_tier == ToolData.ToolTier.RUSTED) or (tool != null and tool.tool_tier >= node.required_tool_tier)
			var fully_accessible = level_met and tool_type_met and tool_tier_met
			
			if not fully_accessible:
				# Cleanly format the skill name dynamically ("Spelunking")
				var formatted_skill = skill_key.capitalize()
				var error_msg = "Requires level %d %s" % [node.required_level, formatted_skill]
				
				# If the rock vein demands an advanced Pickaxe tier, format and overlay the message
				if node.required_tool_tier > ToolData.ToolTier.RUSTED:
					error_msg += " and a %s %s" % [ToolData.ToolTier.keys()[node.required_tool_tier].capitalize(), ToolData.ToolType.keys()[node.required_tool_type].capitalize()]
				card.desc_label.text = error_msg
				card.action_button.disabled = true
			else:
				card.desc_label.text = node.description
				card.action_button.disabled = false