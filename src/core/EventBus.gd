## EventBus.gd
## Central signal bus for decoupled communication between systems.
## All game-wide events are emitted and connected through here.
extends Node

# ─── Economy Signals ───────────────────────────────────────────────
signal gold_changed(new_amount: int)
signal income_changed(new_income: int)
signal expense_changed(new_expense: int)
signal resource_changed(resource_id: String, new_amount: float)
signal resource_shortage(resource_id: String)

# ─── Population Signals ────────────────────────────────────────────
signal population_changed(new_population: int)
signal happiness_changed(new_happiness: float)
signal unemployment_changed(new_rate: float)
signal citizen_spawned(citizen: Object, cell: Vector2i)
signal citizen_despawned(citizen: Object, cell: Vector2i)
signal citizen_assigned_job(citizen: Object, work_cell: Vector2i, job_type: String)
signal citizen_died(citizen: Object, cause: String)
signal citizen_stats_changed(citizen: Object, stat_name: String, new_value: Variant)
signal citizen_hovered(citizen: Object)
signal citizen_unhovered()
signal citizen_selected(citizen: Object)
signal citizen_deselected()

## Emitted when a new immigrant arrives in the village.
## citizen_type: "male" | "female"
signal citizen_arrived(citizen: Object, gender: String)

## Emitted when two citizens form a couple and move into a house together.
signal couple_formed(citizen_a: Object, citizen_b: Object, house_cell: Vector2i)

## Emitted when a couple produces a child.
signal child_born(child: Object, parent_a: Object, parent_b: Object, house_cell: Vector2i)

## Emitted when a child citizen reaches child_growth_age and becomes an adult.
signal citizen_grew_up(citizen: Object)

## Emitted when the player clicks a house to request the occupants panel.
signal house_info_requested(house_cell: Vector2i, occupants: Array)

# ─── Time Signals ──────────────────────────────────────────────────
signal hour_changed(hour: int)
signal wheat_field_registered(cell: Vector2i)
signal wheat_field_unregistered(cell: Vector2i)

# ─── Building Signals ──────────────────────────────────────────────
signal building_placed(building_data: BuildingData, cell: Vector2i)
signal building_removed(building_data: BuildingData, cell: Vector2i)
signal building_upgraded(building_data: BuildingData, cell: Vector2i)
signal building_selected(building_data: BuildingData, cell: Vector2i)
signal building_deselected()

# ─── Grid / Map Signals ────────────────────────────────────────────
signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i, button: int)
signal zone_changed(cell: Vector2i, zone_type: String)

# ─── Game State Signals ────────────────────────────────────────────
signal game_started()
signal game_paused(is_paused: bool)
signal game_saved(slot: int)
signal game_loaded(slot: int)
signal game_speed_changed(speed: float)
signal new_day(day: int, month: int, year: int)
signal new_month(month: int, year: int)
signal new_year(year: int)

# ─── UI Signals ────────────────────────────────────────────────────
signal hud_notification(message: String, type: String)
signal panel_open_requested(panel_id: String, data: Dictionary)
signal panel_close_requested(panel_id: String)
signal build_mode_entered(building_id: String)
signal build_mode_exited()
signal build_mode_rotate()

# ─── Event / Disaster Signals ──────────────────────────────────────
signal game_event_triggered(event_data: Dictionary)
signal game_event_resolved(event_data: Dictionary)

# ─── Helpers ───────────────────────────────────────────────────────
## Emit a HUD notification with a given type: "info", "warning", "error", "success"
func notify(message: String, type: String = "info") -> void:
	emit_signal("hud_notification", message, type)
