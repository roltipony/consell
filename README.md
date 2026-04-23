# Consell — City Builder

> A city builder built with **Godot 4.3** using a fully data-driven, object-oriented architecture.
> Every numeric constant lives in a JSON config file. Every citizen behaviour is expressed in a Behaviour Tree.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [Core Systems](#core-systems)
4. [Citizen System](#citizen-system)
5. [Wheat & Food Production](#wheat--food-production)
6. [Adding Content](#adding-content)
7. [Configuration Files](#configuration-files)
8. [Signals (EventBus)](#signals-eventbus)
9. [Save System](#save-system)
10. [Getting Started](#getting-started)

---

## Project Structure

```
Consell/
├── config/                         # ALL numeric constants live here (no hardcoding)
│   ├── game_settings.json          # Grid, camera, economy, citizen schedules & colors
│   ├── buildings.json              # Every building definition
│   ├── resources.json              # Food, water, wood, stone, wheat…
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
│   │   └── behavior_tree/          # BTNode, BTAction, BTCondition, BTSelector, BTSequence, BTInverter
│   ├── core/                       # Autoloads: GameManager, EventBus, ConfigLoader, SaveManager
│   │                               # GameTime (value object)
│   ├── entities/
│   │   ├── buildings/              # BuildingData (Resource), Building (Node3D base)
│   │   ├── units/                  # Citizen, FarmerCitizen, CitizenSchedule
│   │   └── resources/              # ResourceData, TerrainData
│   ├── systems/
│   │   ├── economy/                # EconomySystem
│   │   ├── population/             # PopulationSystem, CitizenManager, WheatFieldRegistry
│   │   ├── grid/                   # GridSystem, BuildingPlacer, CameraController, MapGenerator
│   │   └── events/                 # EventSystem
│   ├── ui/
│   │   ├── hud/                    # HUD.gd, Notification.gd
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
          ┌────────────────────┼───────────────────┐
          │                    │                   │
   ┌──────▼──────┐    ┌────────▼───────┐   ┌──────▼──────────────┐
   │GameManager  │    │  EconomySystem │   │ PopulationSystem     │
   │  (Autoload) │    │                │   │ CitizenManager       │
   └──────┬──────┘    └────────────────┘   │ WheatFieldRegistry   │
          │                                └─────────────────────┘
   ┌──────▼──────┐    ┌────────────────┐
   │ConfigLoader │    │  GridSystem    │
   │  (Autoload) │    │(owns buildings)│
   └──────┬──────┘    └────────────────┘
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
- **Single responsibility** — each system does one thing
- **All citizen behaviour in Behaviour Trees** — no `if/else` behaviour logic outside BT nodes

---

## Core Systems

### GameManager (`src/core/GameManager.gd`)
Owns the game tick loop and `GameTime`. Holds references to all systems (registered via `register_system()`). Controls pause and speed (PAUSED / SLOW / NORMAL / FAST).

`TICK_INTERVAL_SECONDS` controls how many real seconds pass per in-game hour. Default is `1.0` (1 second = 1 hour). Set to `3.0` or higher during development to observe citizen behaviour at a comfortable speed.

### EventBus (`src/core/EventBus.gd`)
All game-wide signals are declared here. Systems emit and connect without importing each other. Use `EventBus.notify(msg, type)` for HUD toasts.

### ConfigLoader (`src/core/ConfigLoader.gd`)
Loads all JSON files on startup. Exposes typed accessors: `get_building(id)`, `get_resource(id)`. Call `ConfigLoader.reload()` during development for hot-reload.

### EconomySystem (`src/systems/economy/EconomySystem.gd`)
Tracks gold, income, expenses, and per-resource stockpiles. Every tick it recalculates building flows and runs `_convert_resources()`, which automatically converts any resource that declares a `food_value` (e.g. wheat) into food and resets its stockpile to zero.

### GridSystem (`src/systems/grid/GridSystem.gd`)
Tracks `buildings`, `zones`, and `road_cells`. `can_place()` / `place_building()` / `remove_building()`. `world_to_cell()` / `cell_to_world()` for coordinate conversion.

### PopulationSystem (`src/systems/population/PopulationSystem.gd`)
Tracks population, happiness, and unemployment. Growth is probabilistic and capped by housing capacity.

### WheatFieldRegistry (`src/systems/population/WheatFieldRegistry.gd`)
Tracks all placed wheat fields and their accumulated work-hour counters. Each field has an independent `_field_hours` counter. Every in-game hour, if the assigned farmer's `is_working()` returns true, the counter increments. When it reaches `hours_per_unit` (from `resources.json → wheat`), it produces 1 wheat unit (which `EconomySystem` converts to food that same tick). The counter carries over across days — no work is ever lost at midnight.

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

A lightweight value object that resolves the active day-phase for any given hour. It is loaded from config — the citizen class never hardcodes phase boundaries.

```gdscript
var schedule := CitizenSchedule.new()
schedule.load_from_config("farmer")
var phase: String = schedule.phase_at(8)  # → "work"
```

Each phase entry has three fields:

| Field | Type | Description |
|---|---|---|
| `id` | String | Phase name used as blackboard key and BT condition value |
| `start` | int | First hour the phase is active (inclusive, 0–23) |
| `end` | int | First hour the phase is no longer active (exclusive, 1–24) |

Phases that cross midnight are supported (e.g. `start: 22, end: 6`).

### Defining and modifying schedules

All schedules live in `config/game_settings.json` under `citizen_schedules`. Each citizen type has its own array of phases:

```json
"citizen_schedules": {
  "farmer": [
    { "id": "sleep",   "start": 0,  "end": 8  },
    { "id": "work",    "start": 8,  "end": 14 },
    { "id": "eat",     "start": 14, "end": 15 },
    { "id": "leisure", "start": 15, "end": 24 }
  ]
}
```

**To change a schedule:** edit the `start` / `end` values in the JSON. No code changes needed.

**To add a new citizen type with a different schedule:** add a new entry under `citizen_schedules` with the type's name as the key. Then add the corresponding phase colors under `citizen_phase_colors`.

**Future per-citizen modifiers** (e.g. a night-shift farmer or a lazy merchant) will apply hour offsets on top of the base schedule at spawn time. The schedule system is designed for this: `CitizenSchedule` can be extended to accept a `modifiers: Dictionary` that shifts individual phase boundaries without touching any other citizen's schedule.

### Phase colors

Each phase can have a distinct visual color per citizen type, configured in `citizen_phase_colors`:

```json
"citizen_phase_colors": {
  "farmer": {
    "work":    "#a0c840",
    "eat":     "#d09040",
    "leisure": "#70a0d0",
    "sleep":   "#4060a0"
  }
}
```

Colors are applied once per phase transition via `_on_phase_changed()`, never every frame.

### FarmerCitizen (`src/entities/units/FarmerCitizen.gd`)

Extends `Citizen`. Its BT has four phase branches (sleep, work, eat, leisure) plus a safety fallback wander. The work branch uses `CTX_GOING_TO_FIELD` to ensure `move_to` is called exactly once per trip — without this flag a reactive BT would restart the walk every frame once the farmer arrived, keeping `is_working` stuck at false permanently.

```
Selector
├── Sequence [sleep]    phase="sleep" → go home and stay
├── Sequence [work]     phase="work"  → walk to field once → is_working=true
├── Sequence [eat]      phase="eat"   → walk home once
├── Sequence [leisure]  phase="leisure" → wander
└── Action              wander (safety fallback)
```

---

## Wheat & Food Production

```
FarmerCitizen arrives at field
        │
        ▼ (each in-game hour while is_working=true)
WheatFieldRegistry._on_hour_changed
  └── _field_hours[cell] += 1
        │
        ▼ (when _field_hours >= hours_per_unit)
_produce_wheat()
  └── EconomySystem.add_resource("wheat", food_value)
        │
        ▼ (same tick, after hour_changed signals)
EconomySystem._convert_resources()
  └── wheat → food  (wheat stockpile reset to 0)
        │
        ▼
EventBus.resource_changed("food", new_amount)
  └── HUD updates food counter
```

Key config values in `config/resources.json → wheat`:

| Key | Default | Description |
|---|---|---|
| `hours_per_unit` | 2 | Working hours a field needs to produce 1 wheat |
| `food_value` | 1.0 | How much food 1 wheat converts to |

Hours accumulate across days — a field worked for 1 hour today and 1 hour tomorrow produces on the second day.

---

## Adding Content

### New building
1. Add an entry to `config/buildings.json`
2. Create a texture at the path in `icon_path`
3. Create a scene at `scene_path` (root Node3D + script extending `Building`)
4. The BuildMenu populates itself from ConfigLoader automatically

### New citizen type
1. Add a `class_name MyCitizen extends Citizen` script in `src/entities/units/`
2. Override `_build_behavior_tree()` to define its behaviour
3. Add the type mapping to `game_settings.json → citizen_type_classes`
4. Add its schedule to `citizen_schedules`
5. Add its phase colors to `citizen_phase_colors`
6. Assign `citizen_type` in the spawning building's JSON entry

### New resource
1. Add an entry to `config/resources.json`
2. Add an icon at `icon_path`
3. Reference the resource id in building `resource_production` / `resource_consumption`
4. If it converts to another resource, add a `food_value` (or similar) field — `EconomySystem._convert_resources` handles it automatically

### New event
1. Add an entry to `config/events.json` with weight, effects, and min_population
2. No code changes needed

---

## Configuration Files

| File | Purpose |
|---|---|
| `game_settings.json` | Grid, camera, economy start values, citizen schedules, phase colors |
| `buildings.json` | All building types with costs, effects, sizes, citizen types |
| `resources.json` | Resource types, storage limits, production parameters |
| `events.json` | Random events with weights, requirements, effects |
| `terrain_types.json` | Tile types with buildability and yields |
| `zone_rules.json` | Zone categories, allowed building types, bonuses |

---

## Signals (EventBus)

| Signal | Emitted by | When |
|---|---|---|
| `gold_changed(amount)` | EconomySystem | After any gold change |
| `resource_changed(id, amount)` | EconomySystem | After any resource stockpile change |
| `population_changed(pop)` | PopulationSystem | Each growth tick |
| `happiness_changed(value)` | PopulationSystem | Each tick |
| `citizen_spawned(citizen, cell)` | CitizenManager | On citizen creation |
| `citizen_despawned(citizen, cell)` | CitizenManager | On citizen removal |
| `citizen_assigned_job(citizen, cell, job)` | Citizen | On job assignment |
| `building_placed(data, cell)` | GridSystem | After successful placement |
| `building_removed(data, cell)` | GridSystem | After demolition |
| `building_selected(data, cell)` | Building node | On click |
| `hud_notification(msg, type)` | Anywhere | Via `EventBus.notify()` |
| `game_event_triggered(dict)` | EventSystem | On random event |
| `hour_changed(hour)` | GameTime | Every in-game hour |
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

# 3. Place a Tent or Cottage to spawn a farmer
#    Place a Wheat Field near the house
#    The farmer will be assigned automatically and start walking to the field at hour 8
```

**Adjusting game speed for development:**
In `src/core/GameManager.gd`, change `TICK_INTERVAL_SECONDS` to slow down time:
- `1.0` → 1 real second per in-game hour (default)
- `3.0` → 3 real seconds per in-game hour (comfortable for observation)

---

*Consell — built for extensibility. Every number in a JSON. Every behaviour in a tree.*