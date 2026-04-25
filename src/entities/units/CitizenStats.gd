## CitizenStats.gd
## Value object that holds all personal statistics for a single citizen.
##
## Every base value and range is loaded from
## game_settings.json["citizen_stats"]. Nothing is hardcoded here.
##
## Lifecycle:
##   var stats := CitizenStats.new()
##   stats.initialize(cfg)          ← pass ConfigLoader.game_settings["citizen_stats"]
##
## Stats summary:
##   health    — 0..max_health.  Reaches 0 → citizen dies.
##   hunger    — 0..max_hunger.  Reaches 0 → drains health (hunger_damage_per_day / day).
##   thirst    — 0..max_thirst.  Reaches 0 → drains health (thirst_damage_per_day / day).
##   speed     — world-units / second.  Base ± speed_variation applied at spawn.
##   gender    — "male" | "female".  Chosen randomly at spawn.
##   strength  — 0..100 base stat, randomised ± strength_variation.
##   stamina   — 0..100 base stat, randomised ± stamina_variation.
##   happiness — 0.0..1.0.
##   age       — integer years.  Starts random in [age_min_spawn, age_max_spawn].
##               Increments by 1 each in-game year.  ≥ max_age → citizen dies.
##   sight     — detection radius in world units.  Base ± sight_variation.
class_name CitizenStats
extends RefCounted

# ─── Signals ──────────────────────────────────────────────────────────────────
## Emitted whenever a stat is modified so listeners (UI, AI) can react.
signal stat_changed(stat_name: String, new_value: Variant)
## Emitted when health reaches zero OR age reaches max_age.
signal citizen_died(cause: String)

# ─── Derived limits (loaded from config) ──────────────────────────────────────
var max_health:  float = 0.0
var max_hunger:  float = 0.0
var max_thirst:  float = 0.0
var max_age:     int   = 0

var hunger_damage_per_day: float = 0.0
var thirst_damage_per_day: float = 0.0

# ─── Personal statistics ───────────────────────────────────────────────────────
var health:    float  = 0.0
var hunger:    float  = 0.0
var thirst:    float  = 0.0
var speed:     float  = 0.0
var gender:    String = ""
var strength:  float  = 0.0
var stamina:   float  = 0.0
var happiness: float  = 0.0
var age:       int    = 0
var sight:     float  = 0.0

# ─── Internal guard ───────────────────────────────────────────────────────────
var _dead: bool = false

# ─── Initialization ───────────────────────────────────────────────────────────
## Reads every base value and variation from the provided config dictionary.
## All random variation is applied here once — stats are personal from birth.
func initialize(cfg: Dictionary) -> void:
	max_health  = float(cfg.get("max_health",  50.0))
	max_hunger  = float(cfg.get("max_hunger",  50.0))
	max_thirst  = float(cfg.get("max_thirst",  50.0))
	max_age     = int(cfg.get("max_age",       80))

	hunger_damage_per_day = float(cfg.get("hunger_damage_per_day", 10.0))
	thirst_damage_per_day = float(cfg.get("thirst_damage_per_day", 20.0))

	health    = max_health
	hunger    = max_hunger
	thirst    = max_thirst
	happiness = float(cfg.get("base_happiness", 0.75))

	# Speed: base ± variation (clamped above 0)
	var base_speed:       float = float(cfg.get("base_speed",       1.5))
	var speed_variation:  float = float(cfg.get("speed_variation",  0.1))
	speed = maxf(0.1, base_speed + randf_range(-speed_variation, speed_variation))

	# Strength: base ± variation
	var base_strength:      float = float(cfg.get("base_strength",      50.0))
	var strength_variation: float = float(cfg.get("strength_variation", 10.0))
	strength = clampf(base_strength + randf_range(-strength_variation, strength_variation),
		0.0, 100.0)

	# Stamina: base ± variation
	var base_stamina:      float = float(cfg.get("base_stamina",      50.0))
	var stamina_variation: float = float(cfg.get("stamina_variation", 10.0))
	stamina = clampf(base_stamina + randf_range(-stamina_variation, stamina_variation),
		0.0, 100.0)

	# Sight: base ± variation
	var base_sight:      float = float(cfg.get("base_sight",      5.0))
	var sight_variation: float = float(cfg.get("sight_variation", 1.0))
	sight = maxf(0.5, base_sight + randf_range(-sight_variation, sight_variation))

	# Age: random start inside spawn range
	var age_min: int = int(cfg.get("age_min_spawn", 18))
	var age_max: int = int(cfg.get("age_max_spawn", 40))
	age = randi_range(age_min, age_max)

	# Gender: equal 50/50 from config list so adding genders only needs a config edit
	var genders: Array = cfg.get("genders", ["male", "female"])
	gender = str(genders[randi() % genders.size()])

	# React to global resource shortages declared by PopulationSystem.
	EventBus.resource_shortage.connect(_on_resource_shortage)

# ─── Per-day tick ─────────────────────────────────────────────────────────────
## Must be called once per in-game day (connected to EventBus.new_day).
## Processes hunger decay, thirst decay, and health drain when either is empty.
## Returns immediately (and silently) if the citizen is already dead.
func tick_day() -> void:
	if _dead:
		return

	# Passive hunger / thirst decay — values come entirely from config
	_deplete_hunger(float(ConfigLoader.game_settings
		.get("citizen_stats", {}).get("hunger_decay_per_day", 5.0)))
	_deplete_thirst(float(ConfigLoader.game_settings
		.get("citizen_stats", {}).get("thirst_decay_per_day", 5.0)))

	# Health drain when a need reaches zero
	if hunger <= 0.0:
		_drain_health(hunger_damage_per_day, "starvation")
	if thirst <= 0.0:
		_drain_health(thirst_damage_per_day, "dehydration")

# ─── Per-year tick ────────────────────────────────────────────────────────────
## Must be called once per in-game year (connected to EventBus.new_year).
func tick_year() -> void:
	if _dead:
		return
	age += 1
	emit_signal("stat_changed", "age", age)
	if age >= max_age:
		_die("old_age")

# ─── Public mutators ─────────────────────────────────────────────────────────
## All external code must go through these so signals always fire.

func restore_hunger(amount: float) -> void:
	if _dead:
		return
	hunger = minf(hunger + amount, max_hunger)
	emit_signal("stat_changed", "hunger", hunger)

func restore_thirst(amount: float) -> void:
	if _dead:
		return
	thirst = minf(thirst + amount, max_thirst)
	emit_signal("stat_changed", "thirst", thirst)

func heal(amount: float) -> void:
	if _dead:
		return
	health = minf(health + amount, max_health)
	emit_signal("stat_changed", "health", health)

func set_happiness(value: float) -> void:
	happiness = clampf(value, 0.0, 1.0)
	emit_signal("stat_changed", "happiness", happiness)

# ─── Serialization ────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	return {
		"health":    health,
		"hunger":    hunger,
		"thirst":    thirst,
		"speed":     speed,
		"gender":    gender,
		"strength":  strength,
		"stamina":   stamina,
		"happiness": happiness,
		"age":       age,
		"sight":     sight,
	}

func deserialize(data: Dictionary) -> void:
	health    = float(data.get("health",    max_health))
	hunger    = float(data.get("hunger",    max_hunger))
	thirst    = float(data.get("thirst",    max_thirst))
	speed     = float(data.get("speed",     speed))
	gender    = str(data.get("gender",    gender))
	strength  = float(data.get("strength",  strength))
	stamina   = float(data.get("stamina",   stamina))
	happiness = float(data.get("happiness", happiness))
	age       = int(data.get("age",       age))
	sight     = float(data.get("sight",     sight))

# ─── Private helpers ──────────────────────────────────────────────────────────
func _deplete_hunger(amount: float) -> void:
	hunger = maxf(0.0, hunger - amount)
	emit_signal("stat_changed", "hunger", hunger)

func _deplete_thirst(amount: float) -> void:
	thirst = maxf(0.0, thirst - amount)
	emit_signal("stat_changed", "thirst", thirst)

func _drain_health(amount: float, cause: String) -> void:
	health = maxf(0.0, health - amount)
	emit_signal("stat_changed", "health", health)
	if health <= 0.0:
		_die(cause)

func _die(cause: String) -> void:
	if _dead:
		return
	_dead = true
	emit_signal("citizen_died", cause)

# ─── Resource shortage response ───────────────────────────────────────────────
## Called by EventBus.resource_shortage when PopulationSystem detects the global
## stockpile cannot cover full demand for this day.
## Maps resource ids to the stat that suffers — driven entirely by config keys
## so new consumable resources never require code changes here.
func _on_resource_shortage(resource_id: String) -> void:
	if _dead:
		return
	var shortage_map: Dictionary = ConfigLoader.game_settings \
		.get("citizen_stats", {}).get("shortage_stat_map", {})
	var stat_name: String = str(shortage_map.get(resource_id, ""))
	match stat_name:
		"hunger":
			_deplete_hunger(float(ConfigLoader.game_settings
				.get("citizen_stats", {}).get("shortage_hunger_penalty", 5.0)))
		"thirst":
			_deplete_thirst(float(ConfigLoader.game_settings
				.get("citizen_stats", {}).get("shortage_thirst_penalty", 5.0)))