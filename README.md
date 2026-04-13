# Consell — City Builder

> A city builder game built with **Godot 4.3** using fully data-driven, object-oriented architecture.

---

## Table of Contents
1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [Core Systems](#core-systems)
4. [Adding Content](#adding-content)
5. [Configuration Files](#configuration-files)
6. [Signals (EventBus)](#signals-eventbus)
7. [Save System](#save-system)
8. [Getting Started](#getting-started)

---

## Project Structure

```
Consell/
├── assets/
│   ├── textures/
│   │   ├── buildings/      # One PNG per building (matches icon_path in buildings.json)
│   │   ├── terrain/        # Tileset textures
│   │   ├── ui/             # Buttons, frames, backgrounds
│   │   └── effects/        # Particles, highlights
│   ├── audio/
│   │   ├── music/          # Looping background tracks
│   │   └── sfx/            # UI clicks, building placement sounds
│   ├── fonts/              # .ttf / .otf fonts
│   ├── models/             # 3-D assets if you switch to 3-D later
│   └── icons/              # Resource icons (food, water, gold…)
│
├── config/                 # ← ALL NUMERIC CONSTANTS LIVE HERE (no hardcoding)
│   ├── game_settings.json  # Grid size, camera speeds, economy start values
│   ├── buildings.json      # Every building definition
│   ├── resources.json      # Food, water, wood, stone…
│   ├── events.json         # Random events with weights and effects
│   ├── terrain_types.json  # Grass, forest, water, mountain…
│   └── zone_rules.json     # Zoning categories and bonuses
│
├── scenes/
│   ├── main/               # MainMenu.tscn, GameWorld.tscn
│   ├── buildings/          # One .tscn per building type
│   ├── ui/                 # HUD, BuildMenu, InfoPanel, Notification…
│   └── environment/        # Terrain, sky, ambient effects
│
├── src/
│   ├── core/               # Autoloads: GameManager, EventBus, ConfigLoader, SaveManager
│   │                         GameTime (value object)
│   ├── entities/
│   │   ├── buildings/      # BuildingData (Resource), Building (Node2D base class)
│   │   ├── units/          # Future: citizens, workers, soldiers
│   │   └── resources/      # ResourceData, TerrainData
│   ├── systems/
│   │   ├── economy/        # EconomySystem
│   │   ├── population/     # PopulationSystem
│   │   ├── grid/           # GridSystem, BuildingPlacer, CameraController
│   │   └── events/         # EventSystem
│   ├── ui/
│   │   ├── hud/            # HUD.gd, Notification.gd
│   │   ├── menus/          # MainMenu.gd, GameWorld.gd (root scene script)
│   │   └── panels/         # BuildMenu.gd, InfoPanel.gd, BuildButton.gd
│   └── utils/              # MathUtils, StringUtils (stateless helpers)
│
├── resources/              # Godot .tres resource files (optional, generated at runtime)
├── docs/                   # Extended design docs
└── project.godot
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
   ┌──────▼──────┐    ┌────────▼───────┐   ┌──────▼──────┐
   │GameManager  │    │  EconomySystem │   │PopSys / etc │
   │  (Autoload) │    │  (Node child)  │   │(Node child) │
   └──────┬──────┘    └────────────────┘   └─────────────┘
          │
   ┌──────▼──────┐    ┌────────────────┐
   │ConfigLoader │    │  GridSystem    │
   │  (Autoload) │    │(owns buildings)│
   └──────┬──────┘    └────────┬───────┘
          │                    │
   ┌──────▼──────┐    ┌────────▼───────┐
   │ JSON config │    │  Building nodes│
   │   files     │    │ (scene instanc)│
   └─────────────┘    └────────────────┘
```

**Key principles:**
- **No hardcoded values** — every number lives in `config/*.json`
- **EventBus decoupling** — systems never import each other; they talk via signals
- **Data/Logic separation** — `BuildingData` (Resource) holds static data; `Building` (Node) holds runtime state
- **Single responsibility** — each system does one thing; `GameManager` only coordinates

---

## Core Systems

### GameManager (`src/core/GameManager.gd`)
- Owns the game tick loop and `GameTime`
- Holds references to all systems (registered via `register_system()`)
- Controls pause and speed (PAUSED / SLOW / NORMAL / FAST)

### EventBus (`src/core/EventBus.gd`)
- All game-wide signals are declared here
- Systems emit and connect without importing each other
- Use `EventBus.notify(msg, type)` for HUD toasts

### ConfigLoader (`src/core/ConfigLoader.gd`)
- Loads all JSON files on startup
- Exposes typed accessors: `get_building(id)`, `get_resource(id)`
- Call `ConfigLoader.reload()` during development for hot-reload

### GridSystem (`src/systems/grid/GridSystem.gd`)
- Tracks `buildings`, `zones`, and `road_cells` dictionaries
- `can_place()` / `place_building()` / `remove_building()`
- `world_to_cell()` / `cell_to_world()` for coordinate conversion

### EconomySystem (`src/systems/economy/EconomySystem.gd`)
- Tracks `gold`, `income`, `expenses`, per-resource stockpiles
- `can_afford()` / `spend_gold()` used before placing buildings
- Tax income scales with population × tax_rate

### PopulationSystem (`src/systems/population/PopulationSystem.gd`)
- Tracks `population`, `happiness`, `unemployment`
- Growth is probabilistic and capped by housing capacity
- Happiness is the sum of all placed building modifiers

### EventSystem (`src/systems/events/EventSystem.gd`)
- Rolls a random event every N ticks (configured in game_settings.json)
- Weighted selection with `min_population` gating
- Effects applied immediately (gold delta, happiness delta)

---

## Adding Content

### New Building
1. Add an entry to `config/buildings.json` following the existing schema
2. Create a texture at the path specified in `icon_path`
3. Create a scene at the path specified in `scene_path` (root Node2D + script extending `Building`)
4. That's it — the BuildMenu populates itself from ConfigLoader automatically

### New Resource
1. Add an entry to `config/resources.json`
2. Add an icon at the `icon_path`
3. Reference the resource id in building `resource_production` / `resource_consumption`

### New Event
1. Add an entry to `config/events.json` with a weight, effects, and min_population
2. No code changes needed

### New Terrain Type
1. Add an entry to `config/terrain_types.json`
2. Add the corresponding tile to the TileSet atlas

---

## Configuration Files

| File | Purpose |
|------|---------|
| `game_settings.json` | Grid dimensions, camera, economy start values |
| `buildings.json` | All building types with costs, effects, sizes |
| `resources.json` | Resource types, storage limits, happiness penalties |
| `events.json` | Random events with weights, requirements, effects |
| `terrain_types.json` | Tile types with buildability and yields |
| `zone_rules.json` | Zone categories, allowed building types, bonuses |

---

## Signals (EventBus)

| Signal | When emitted |
|--------|-------------|
| `gold_changed(amount)` | EconomySystem after any gold change |
| `population_changed(pop)` | PopulationSystem each growth tick |
| `happiness_changed(value)` | PopulationSystem each tick |
| `building_placed(data, cell)` | GridSystem after successful placement |
| `building_removed(data, cell)` | GridSystem after demolition |
| `building_selected(data, cell)` | Building node on click |
| `hud_notification(msg, type)` | Anywhere via `EventBus.notify()` |
| `game_event_triggered(dict)` | EventSystem on random event |
| `new_day / new_month / new_year` | GameTime on calendar advance |
| `build_mode_entered(id)` | UI when player picks a building |
| `build_mode_exited()` | BuildingPlacer on cancel/place |

---

## Save System

Saves are stored in `user://saves/slot_N.json` (slots 0–4).

```gdscript
SaveManager.save_game(0)   # Save to slot 0
SaveManager.load_game(0)   # Load from slot 0
SaveManager.slot_exists(0) # Check if slot has data
SaveManager.delete_slot(0) # Erase a slot
```

Each system that should be saved must implement `serialize() → Dictionary` and `deserialize(data: Dictionary)`.

---

## Getting Started

```bash
# 1. Open the project in Godot 4.3+
#    File → Open Project → select the Consell/ folder

# 2. Generate placeholder .tscn files (first time only)
python3 create_placeholder_scenes.py

# 3. Build your scene tree in GameWorld.tscn:
#    - Add Systems node with: GridSystem, EconomySystem, PopulationSystem, EventSystem
#    - Add CameraController (Camera2D + CameraController.gd)
#    - Add BuildingPlacer (Node2D + BuildingPlacer.gd)

# 4. Add art assets to assets/ matching paths in config JSONs

# 5. Press F5 and build your city!
```

---

*Consell — built for extensibility. Every number in a JSON. Every event in a signal.*
