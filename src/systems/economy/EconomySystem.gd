## EconomySystem.gd
## Tracks gold, income, expenses, and per-resource stockpiles.
## All values start from config; nothing is hardcoded.
class_name EconomySystem
extends Node

# ─── Config key ───────────────────────────────────────────────────
const CFG_KEY := "economy"

# ─── State ────────────────────────────────────────────────────────
var gold:          int = 0
var income:        int = 0   # Recalculated each tick
var expenses:      int = 0   # Recalculated each tick
var resources:     Dictionary = {}   # resource_id → float amount
var tax_rate:      float = 0.1

# ─── Lifecycle ────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()
	GameManager.register_system("economy", self)

func _load_config() -> void:
	var cfg: Dictionary = ConfigLoader.game_settings.get(CFG_KEY, {})
	gold     = cfg.get("starting_gold",    500)
	tax_rate = cfg.get("default_tax_rate", 0.10)
	# Initialise resource stockpiles from resources.json
	for rid in ConfigLoader.resources:
		var rdata: Dictionary = ConfigLoader.resources[rid]
		resources[rid] = float(rdata.get("starting_amount", 0))

# ─── Tick ─────────────────────────────────────────────────────────
func process_tick() -> void:
	_recalculate_flows()
	_convert_resources()
	var delta := income - expenses
	add_gold(delta)

func _convert_resources() -> void:
	## Convert sub-resources into their parent resource each tick.
	## Reads food_value from resources.json for each resource that declares it.
	for rid in ConfigLoader.resources:
		var rdata: Dictionary = ConfigLoader.resources[rid]
		var food_value: float = float(rdata.get("food_value", 0.0))
		if food_value <= 0.0:
			continue
		var amount: float = resources.get(rid, 0.0)
		if amount <= 0.0:
			continue
		add_resource("food", amount * food_value)
		add_resource(rid, -amount)

func _recalculate_flows() -> void:
	income   = 0
	expenses = 0
	for cell in GameManager.grid_system.buildings:
		var bld: Building = GameManager.grid_system.buildings[cell]
		if bld == null or not bld.is_operational:
			continue
		var bd: BuildingData = bld.data
		# Only count the origin cell (buildings span multiple cells)
		if cell != bld.cell:
			continue
		income   += bd.income_per_tick
		expenses += bd.upkeep_per_tick
		for rid in bd.resource_production:
			add_resource(rid, bd.resource_production[rid])
		for rid in bd.resource_consumption:
			add_resource(rid, -bd.resource_consumption[rid])

	# Tax income from population
	var pop: int = GameManager.population_system.population if GameManager.population_system else 0
	income += int(pop * tax_rate)

	EventBus.emit_signal("income_changed", income)
	EventBus.emit_signal("expense_changed", expenses)

# ─── Public API ───────────────────────────────────────────────────
func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)
	EventBus.emit_signal("gold_changed", gold)

func can_afford(cost: int) -> bool:
	return gold >= cost

func spend_gold(amount: int) -> bool:
	if not can_afford(amount):
		return false
	add_gold(-amount)
	return true

func add_resource(resource_id: String, amount: float) -> void:
	if not resources.has(resource_id):
		resources[resource_id] = 0.0
	resources[resource_id] = maxf(0.0, resources[resource_id] + amount)
	EventBus.emit_signal("resource_changed", resource_id, resources[resource_id])

func get_resource(resource_id: String) -> float:
	return resources.get(resource_id, 0.0)

func set_tax_rate(rate: float) -> void:
	tax_rate = clampf(rate, 0.0, 1.0)

# ─── Serialisation ────────────────────────────────────────────────
func serialize() -> Dictionary:
	return {"gold": gold, "tax_rate": tax_rate, "resources": resources.duplicate()}

func deserialize(data: Dictionary) -> void:
	gold      = data.get("gold",     gold)
	tax_rate  = data.get("tax_rate", tax_rate)
	resources = data.get("resources", resources).duplicate()
	EventBus.emit_signal("gold_changed", gold)