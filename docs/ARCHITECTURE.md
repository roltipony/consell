# Consell — Architecture Deep Dive

## Signal Flow Example: Placing a Building

```
Player clicks BuildMenu → "Cottage"
        │
        ▼
BuildMenu.gd emits EventBus.build_mode_entered("cottage")
        │
        ▼
BuildingPlacer._on_build_mode_entered("cottage")
  → ConfigLoader.get_building("cottage") → raw dict
  → BuildingData.from_dict(raw) → typed resource
  → Instantiates ghost preview scene
        │
Player left-clicks on valid cell
        │
        ▼
BuildingPlacer._try_place()
  → EconomySystem.can_afford(150) → true
  → EconomySystem.spend_gold(150)
      → EventBus.gold_changed(new_gold)
          → HUD._on_gold_changed() updates label
  → load("res://scenes/buildings/Cottage.tscn").instantiate()
  → node.initialize(building_data, cell)
  → GridSystem.place_building(data, cell, node)
      → EventBus.building_placed(data, cell)
  → EventBus.build_mode_exited()
```

## Tick Pipeline (every TICK_INTERVAL_SECONDS × speed_multiplier)

```
GameManager._process_game_tick()
  ├── GameTime.advance_tick()
  │     └── may emit new_day / new_month / new_year
  ├── EconomySystem.process_tick()
  │     ├── _recalculate_flows() (iterates all buildings)
  │     ├── add_gold(income - expenses)
  │     └── emits gold_changed, income_changed, expense_changed
  ├── PopulationSystem.process_tick()
  │     ├── _update_capacity()
  │     ├── _update_happiness()
  │     ├── _update_growth()
  │     └── emits population_changed, happiness_changed
  └── EventSystem.process_tick()
        └── every N ticks: weighted random event roll
```

## Extending the Save System

Any system can opt into serialisation by implementing:

```gdscript
func serialize() -> Dictionary:
    return { "my_data": my_data }

func deserialize(data: Dictionary) -> void:
    my_data = data.get("my_data", default_value)
```

Then register in `SaveManager._collect_state()` and `_apply_state()`.

## Planned Systems (not yet implemented)

| System | Description |
|--------|-------------|
| `RoadSystem` | Pathfinding for road connectivity checks |
| `ServiceSystem` | Coverage radius for wells, guard posts, etc. |
| `ResearchSystem` | Tech tree unlocking new buildings |
| `DisasterSystem` | Fire, flood — extending EventSystem |
| `TradeSystem` | Importing/exporting resources |
| `UnitSystem` | Citizen agents walking around |
