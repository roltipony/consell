# Consell — City Builder

> A city builder built with **Godot 4.3** using a fully data-driven, object-oriented architecture.
> Every numeric constant lives in a JSON config file. Every citizen behaviour is expressed in a Behaviour Tree.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [Tick Pipeline](#tick-pipeline)
4. [Core Systems](#core-systems)
5. [Citizen System](#citizen-system)
6. [Population & Immigration](#population--immigration)
7. [Housing & Family Lifecycle](#housing--family-lifecycle)
8. [Wheat & Food Production](#wheat--food-production)
9. [Adding Content](#adding-content)
10. [Configuration Files](#configuration-files)
11. [Signals (EventBus)](#signals-eventbus)
12. [Save System](#save-system)
13. [Getting Started](#getting-started)

---

## Project Structure

```
Consell/
├── config/                         # ALL numeric constants live here (no hardcoding)
│   ├── game_settings.json          # Grid, camera, economy, citizen schedules,
│   │                               # population rules, house rules, citizen names
│   ├── buildings.json              # Every building definition (capacity, cost, mesh…)
│   ├── resources.json              # Food, water, wood, stone, wheat (with food_value)
│   ├── events.json                 # Random events with weights and effects
│   ├── terrain_types.json          # Grass, forest, water, mountain…
│   └── zone_rules.json             # Zoning categories and bonuses
│
├── scenes/
│   ├── main/                       # GameWorld.tscn, MainMenu.tscn
│   ├── buildings/                  # One .tscn per building type
│   └── ui/                         # HUD, BuildMenu, InfoPanel, Notification
│
├── src/
│   ├── ai/
│   │   └── behavior_tree/          # BTNode, BTAction, BTCondition,
│   │                               # BTSelector, BTSequence, BTInverter
│   ├── core/                       # Autoloads: GameManager, EventBus,
│   │                               # ConfigLoader, SaveManager, GameTime
│   ├── entities/
│   │   ├── buildings/              # BuildingData (Resource), Building (Node3D base)
│   │   ├── units/                  # Citizen, FarmerCitizen, CitizenSchedule, CitizenStats
│   │   └── resources/              # ResourceData, TerrainData
│   ├── systems/
│   │   ├── economy/                # EconomySystem
│   │   ├── population/             # PopulationSystem, CitizenManager,
│   │   │                           # HouseOccupancy, WheatFieldRegistry
│   │   ├── grid/                   # GridSystem, BuildingPlacer,
│   │   │                           # CameraController, MapGenerator
│   │   └── events/                 # EventSystem
│   ├── ui/
│   │   ├── hud/                    # HUD.gd, Notification.gd, CitizenTooltip.gd,
│   │   │                           # CitizenInfoPanel.gd
│   │   ├── menus/                  # MainMenu.gd, GameWorld.gd
│   │   └── panels/                 # BuildMenu.gd, InfoPanel.gd, BuildButton.gd
│   └── utils/                      # MathUtils, StringUtils (stateless helpers)
│
└── docs/
    └── ARCHITECTURE.md             # Signal flow and tick pipeline diagrams
```

---

## Architecture Overview

```
                        ┌─────────────┐
                        │  EventBus   │  ← Central signal hub (Autoload)
                        └──────┬──────┘
                               │  signals
          ┌────────────────────┼───────────────────────┐
          │                    │                       │
   ┌──────▼──────┐    ┌────────▼────────┐   ┌─────────▼──────────────┐
   │ GameManager │    │ EconomySystem   │   │ PopulationSystem        │
   │  (Autoload) │    │                 │   │ ├─ HouseOccupancy       │
   └──────┬──────┘    └─────────────────┘   │ └─ (owned RefCounted)  │
          │                                 ├─ CitizenManager         │
   ┌──────▼──────┐    ┌─────────────────┐   └─ WheatFieldRegistry    ┘
   │ConfigLoader │    │   GridSystem    │
   │  (Autoload) │    │ (owns buildings)│
   └──────┬──────┘    └─────────────────┘
          │
   ┌──────▼──────┐
   │ JSON config │
   │   files     │
   └─────────────┘
```

**Key principles:**

- **No hardcoded values** — every number lives in `config/*.json`
- **EventBus decoupling** — systems never import each other; they communicate via signals
- **Data / logic separation** — `BuildingData` holds static data; `Building` holds runtime state
- **Single responsibility** — each system does exactly one thing
- **All citizen behaviour in Behaviour Trees** — no `if/else` behaviour logic outside BT nodes

---

## Tick Pipeline

Each game tick corresponds to one in-game hour. `TICK_INTERVAL_SECONDS` in `GameManager` controls how many real seconds one tick takes (default `3.0`).

```
GameManager._process_game_tick()
  │
  ├─ 1. game_time.advance_tick()
  │       └─ emits hour_changed(hour)       → Citizens update phase, WheatFieldRegistry
  │           if hour == 0: emits new_day() → PopulationSystem._on_new_day()
  │                                            (increments cooldown, sets immigration flag,
  │                                             checks shortages — does NOT check immigration yet)
  │
  ├─ 2. economy_system.process_tick()
  │       ├─ _recalculate_flows()           → adds building production to stockpiles
  │       └─ _convert_resources()           → wheat → food conversion
  │
  └─ 3. population_system.process_tick()
          ├─ _update_capacity / happiness / unemployment
          └─ if _immigration_check_pending: → _check_immigration()
                                               reads food AFTER economy has updated it
```

> **Why immigration runs in `process_tick` and not `_on_new_day`:**
> `new_day` is emitted synchronously inside `advance_tick()`, before the economy tick runs.
> Immigration reads the food stockpile, so it must run after `economy_system.process_tick()`.
> The flag `_immigration_check_pending` bridges the two steps without coupling the systems.

---

## Core Systems

### GameManager (`src/core/GameManager.gd`)
Owns the game tick loop and `GameTime`. Holds references to all systems (registered via `register_system()`). Controls pause and speed (PAUSED / SLOW / NORMAL / FAST). Tick order is fixed: `GameTime → EconomySystem → PopulationSystem → EventSystem`.

### EventBus (`src/core/EventBus.gd`)
All game-wide signals are declared here. Systems emit and connect without importing each other. Use `EventBus.notify(msg, type)` for HUD toasts.

### ConfigLoader (`src/core/ConfigLoader.gd`)
Loads all JSON files on startup. Exposes typed accessors: `get_building(id)`, `get_resource(id)`. Call `ConfigLoader.reload()` during development for hot-reload.

### EconomySystem (`src/systems/economy/EconomySystem.gd`)
Tracks gold, income, expenses, and per-resource stockpiles. Every tick it recalculates building flows and runs `_convert_resources()`, which automatically converts any resource that declares a `food_value` (e.g. wheat) into food and resets its stockpile to zero.

### GridSystem (`src/systems/grid/GridSystem.gd`)
Tracks `buildings`, `zones`, and `road_cells`. `can_place()` / `place_building()` / `remove_building()`. `world_to_cell()` / `cell_to_world()` for coordinate conversion.

---

## Citizen System

### Lifecycle

```
CitizenManager.add_child(citizen)   → _ready(): visuals + base context
citizen.initialize(cell, cfg)       → home_cell, move speed, colors
citizen.setup_size(footprint)       → visual scale
citizen.start()                     → loads config, builds BT, syncs phase
```

### Behaviour Tree infrastructure (`src/ai/behavior_tree/`)

| Class | Role |
|---|---|
| `BTNode` | Abstract base; defines the `Status` enum (SUCCESS / FAILURE / RUNNING) |
| `BTAction` | Leaf; executes a `Callable(ctx) → Status` |
| `BTCondition` | Leaf; evaluates a `Callable(ctx) → bool`; returns SUCCESS or FAILURE |
| `BTSelector` | Composite OR; tries children in order, returns first non-FAILURE |
| `BTSequence` | Composite AND; runs children in order, stops on first FAILURE |
| `BTInverter` | Decorator; inverts SUCCESS ↔ FAILURE, passes through RUNNING |

Both `BTSelector` and `BTSequence` are **reactive** — they re-evaluate from child 0 every tick, so higher-priority branches always preempt lower ones automatically.

### CitizenSchedule (`src/entities/units/CitizenSchedule.gd`)

A lightweight value object that resolves the active day-phase for any given hour. Loaded from config — the citizen class never hardcodes phase boundaries. Supports midnight-wrapping phases (e.g. `start: 22, end: 6`).

```gdscript
var schedule := CitizenSchedule.new()
schedule.load_from_config("farmer")
var phase: String = schedule.phase_at(8)  # → "work"
```

### CitizenStats (`src/entities/units/CitizenStats.gd`)

Value object holding all personal stats (health, hunger, thirst, speed, gender, age, strength, stamina, sight). All base values and variation ranges come from `game_settings.json → citizen_stats`.

- `tick_day()` — called each new day: depletes hunger/thirst, drains health if starving/dehydrated
- `tick_year()` — called each new year: ages the citizen, triggers death at `max_age`
- Citizen death is signalled via `CitizenStats.citizen_died` → `Citizen._on_stats_death` → `EventBus.citizen_died`

### FarmerCitizen (`src/entities/units/FarmerCitizen.gd`)

Extends `Citizen`. Overrides `_build_behavior_tree()` with four phase branches plus a fallback wander.

```
Selector
├── Sequence [sleep]    phase="sleep"   → go home and stay
├── Sequence [work]     phase="work"    → walk to assigned field once → is_working=true
├── Sequence [eat]      phase="eat"     → walk home → consume food+water from stockpile
├── Sequence [leisure]  phase="leisure" → wander near home
└── Action              wander (safety fallback)
```

The work branch uses a `CTX_GOING_TO_FIELD` flag so the reactive BT does not restart `move_to` every frame after the farmer arrives.

The eat branch calls the base `_eat_action` (defined in `Citizen`), which deducts food and water from `EconomySystem` once per eat phase (`_ate_this_phase` / `_drank_this_phase` flags, reset at phase start via `_on_hour_changed`).

---

## Population & Immigration

### PopulationSystem (`src/systems/population/PopulationSystem.gd`)

Tracks population count, happiness, housing capacity, job count, and unemployment. Also owns the `HouseOccupancy` instance.

**Immigration flow:**

```
new_day signal (synchronous, inside advance_tick — economy not yet updated)
  └─ _on_new_day()
       ├─ emit resource_shortage if stockpile < daily demand
       ├─ _days_since_immigration += 1
       └─ _immigration_check_pending = true

population_system.process_tick()  (runs AFTER economy_system.process_tick)
  └─ if _immigration_check_pending:
       └─ _check_immigration(eco)
            ├─ cooldown elapsed? (_days_since_immigration >= immigration_cooldown_days)
            ├─ food >= threshold? (eco.get_resource("food") >= food_immigration_threshold)
            └─ house has a free slot? → _spawn_immigrant(gender)
                                           └─ find_house_for_immigrant()
                                                priority: lone adult of opposite gender, no partner
                                                fallback: any house with a free slot
```

**Key config keys** (`game_settings.json → population`):

| Key | Default | Description |
|---|---|---|
| `food_immigration_threshold` | 1.0 | Minimum food stockpile to allow immigration |
| `immigration_cooldown_days` | 1 | Minimum days between immigration events |
| `food_per_citizen_per_day` | 1.0 | Units consumed per citizen at eat phase |
| `water_per_citizen_per_day` | 1.0 | Units consumed per citizen at eat phase |

---

## Housing & Family Lifecycle

### HouseOccupancy (`src/systems/population/HouseOccupancy.gd`)

Owned by `PopulationSystem` (a `RefCounted`, not a Node). Tracks which citizens live in each residential building cell and runs the per-house Behaviour Tree once per day.

**Per-house Behaviour Tree (runs once per house on `new_day`):**

```
Selector
└── Sequence
     ├── Condition : house has a couple
     │               (one male + one female, both adults, both residents, both without a partner)
     ├── Action    : increment couple_days
     └── Selector
          ├── Sequence
          │    ├── Condition : couple_days >= couple_days_to_reproduce AND children < max_children
          │    └── Action    : spawn child, reset couple_days to 0
          └── Action    : noop (couple exists but reproduction not ready)
```

**Key config keys** (`game_settings.json → house_rules`):

| Key | Default | Description |
|---|---|---|
| `couple_days_to_reproduce` | 2 | Days a couple must cohabit before having a child |
| `max_children` | 4 | Maximum children living in one house at a time |
| `child_growth_age` | 4 | In-game years before a child becomes an adult |
| `child_mesh_scale_factor` | 0.55 | Visual scale multiplier applied to child citizens |

### Full family lifecycle

```
1. House placed
   └─ CitizenManager spawns citizen A (random gender)
      registered in HouseOccupancy via _register_initial_resident (deferred)

2. Day 2+ — immigration check passes
   └─ find_house_for_immigrant() prefers house where A is alone with no partner
      citizen B (opposite gender) moves in → _try_form_couple() → couple formed
      couple_days reset to 0

3. couple_days_to_reproduce days later (default 2)
   └─ House BT fires _action_spawn_child()
      child spawned with is_child=true and child mesh scale
      child registered in the same house

4. child_growth_age in-game years later (default 4)
   └─ Citizen._check_child_grown_up()
      is_child = false, mesh scale restored to adult
      EventBus.citizen_grew_up emitted
      _try_emancipate() → searches for any other residential building with a free slot
        if found: HouseOccupancy.remove_resident() + add_resident() → moves out
                  _try_form_couple() fires in new house automatically
        if not found: citizen stays in family home

5. Demolish house
   └─ CitizenManager._despawn_all_for_cell()
      all residents freed, HouseOccupancy entries cleaned up via citizen_died signal
```

**Building capacity** (`buildings.json → population_capacity`):

| Building | Capacity | Notes |
|---|---|---|
| Tent | 6 | 2 adults + up to 4 children |
| Cottage | 6 | 2 adults + up to 4 children |

The child cap is enforced by `can_have_child()` reading `max_children`, not the raw capacity value.

---

## Wheat & Food Production

```
FarmerCitizen arrives at field (phase="work", is_working=true)
        │
        ▼ each in-game hour while is_working=true
WheatFieldRegistry._on_hour_changed
  └─ _field_hours[cell] += 1
        │
        ▼ when _field_hours >= hours_per_unit
_produce_wheat()
  └─ EconomySystem.add_resource("wheat", food_value)
        │
        ▼ same tick — economy_system.process_tick → _convert_resources
wheat → food  (wheat stockpile reset to 0)
        │
        ▼
EventBus.resource_changed("food", new_amount)  → HUD updates food counter
```

**Key config values** (`config/resources.json → wheat`):

| Key | Default | Description |
|---|---|---|
| `hours_per_unit` | 2 | Working hours a field needs to produce 1 wheat |
| `food_value` | 1.0 | How much food 1 wheat converts to |

Hours accumulate across days — no work is ever lost at midnight.

**Field reassignment on demolish:** When a wheat field is removed, the registry erases the cell first, then calls `release_field()` and immediately `_try_assign_farmer()` on the freed farmer, so the farmer finds the next nearest free field in the same frame.

---

## Adding Content

### New building
1. Add an entry to `config/buildings.json`
2. Create a texture at the path in `icon_path`
3. Create a scene at `scene_path` (root Node3D + script extending `Building`)
4. The BuildMenu populates itself from ConfigLoader automatically

### New citizen type
1. Add a `class_name MyCitizen extends Citizen` script in `src/entities/units/`
2. Override `_build_behavior_tree()` — every behaviour must live in BT nodes, no bare if/else
3. Add the type mapping to `game_settings.json → citizen_type_classes`
4. Add its schedule to `citizen_schedules`
5. Add its phase colors to `citizen_phase_colors`
6. Assign `citizen_type` in the spawning building's JSON entry

### New resource
1. Add an entry to `config/resources.json`
2. Add an icon at `icon_path`
3. Reference the resource id in building `resource_production` / `resource_consumption`
4. If it converts to food, add a `food_value` field — `EconomySystem._convert_resources` handles it automatically

### New event
1. Add an entry to `config/events.json` with weight, effects, and min_population
2. No code changes needed

---

## Configuration Files

| File | Purpose |
|---|---|
| `game_settings.json` | Grid, camera, economy start values, citizen schedules, phase colors, population rules, house rules, citizen names |
| `buildings.json` | All building types with costs, capacity, effects, sizes, citizen types |
| `resources.json` | Resource types, storage limits, food values, production parameters |
| `events.json` | Random events with weights, requirements, effects |
| `terrain_types.json` | Tile types with buildability and yields |
| `zone_rules.json` | Zone categories, allowed building types, bonuses |

---

## Signals (EventBus)

| Signal | Emitted by | When |
|---|---|---|
| `gold_changed(amount)` | EconomySystem | After any gold change |
| `resource_changed(id, amount)` | EconomySystem | After any resource stockpile change |
| `resource_shortage(id)` | PopulationSystem | When stockpile < daily demand |
| `population_changed(pop)` | PopulationSystem | On citizen spawn or death |
| `happiness_changed(value)` | PopulationSystem | Each tick |
| `unemployment_changed(rate)` | PopulationSystem | Each tick |
| `citizen_spawned(citizen, cell)` | CitizenManager | On citizen creation |
| `citizen_despawned(citizen, cell)` | CitizenManager | On citizen removal |
| `citizen_assigned_job(citizen, cell, job)` | Citizen | On job assignment |
| `citizen_died(citizen, cause)` | Citizen | On health reaching zero or max age |
| `citizen_arrived(citizen, gender)` | PopulationSystem | On successful immigration |
| `couple_formed(a, b, cell)` | HouseOccupancy | When two adults of opposite gender share a house |
| `child_born(child, a, b, cell)` | HouseOccupancy | On successful reproduction |
| `citizen_grew_up(citizen)` | Citizen | When a child reaches `child_growth_age` |
| `building_placed(data, cell)` | GridSystem | After successful placement |
| `building_removed(data, cell)` | GridSystem | After demolition |
| `building_selected(data, cell)` | Building node | On click |
| `hud_notification(msg, type)` | Anywhere | Via `EventBus.notify()` |
| `game_event_triggered(dict)` | EventSystem | On random event |
| `hour_changed(hour)` | GameTime | Every in-game hour (every tick) |
| `new_day(day, month, year)` | GameTime | Every 24 ticks |
| `new_month / new_year` | GameTime | On calendar advance |
| `wheat_field_registered(cell)` | WheatFieldRegistry | On wheat field placed |
| `wheat_field_unregistered(cell)` | WheatFieldRegistry | On wheat field removed |

---

## Save System

Saves are stored in `user://saves/slot_N.json` (slots 0–4).

```gdscript
SaveManager.save_game(0)   # Save to slot 0
SaveManager.load_game(0)   # Load from slot 0
SaveManager.slot_exists(0) # Check if slot has data
SaveManager.delete_slot(0) # Erase a slot
```

Any system that should persist must implement:

```gdscript
func serialize() -> Dictionary:
    return { "my_key": my_value }

func deserialize(data: Dictionary) -> void:
    my_value = data.get("my_key", default)
```

Then register it in `SaveManager._collect_state()` and `_apply_state()`.

---

## Getting Started

```bash
# 1. Open the project in Godot 4.3+
#    File → Open Project → select the Consell/ folder

# 2. Press F5 to run

# 3. Place a Tent or Cottage — a farmer spawns automatically
#    Place a Wheat Field nearby — the farmer walks to it at hour 8
#    A second immigrant arrives once food > 1.0 and the house has a free slot
#    After 2 days cohabiting, the couple has a child (smaller mesh)
#    After child_growth_age in-game years the child becomes an adult and seeks a new house
```

**Adjusting game speed for development:**
In `src/core/GameManager.gd`, change `TICK_INTERVAL_SECONDS`:
- `1.0` → 1 real second per in-game hour (fast)
- `3.0` → 3 real seconds per in-game hour (comfortable for observation)

---

*Consell — built for extensibility. Every number in a JSON. Every behaviour in a tree.*