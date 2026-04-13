#!/usr/bin/env python3
"""
create_placeholder_scenes.py
Run this once from the project root to generate minimal .tscn placeholder files
for every scene referenced in the GDScript sources.
Usage: python3 create_placeholder_scenes.py
"""

import os

SCENES = {
    # path : (root_type, script_path)
    "scenes/main/MainMenu.tscn":        ("Control",   "res://src/ui/menus/MainMenu.gd"),
    "scenes/main/GameWorld.tscn":       ("Node2D",    "res://src/ui/menus/GameWorld.gd"),
    "scenes/ui/HUD.tscn":              ("CanvasLayer","res://src/ui/hud/HUD.gd"),
    "scenes/ui/BuildMenu.tscn":        ("PanelContainer","res://src/ui/panels/BuildMenu.gd"),
    "scenes/ui/InfoPanel.tscn":        ("PanelContainer","res://src/ui/panels/InfoPanel.gd"),
    "scenes/ui/Notification.tscn":     ("PanelContainer","res://src/ui/hud/Notification.gd"),
    "scenes/ui/BuildButton.tscn":      ("Button",     "res://src/ui/panels/BuildButton.gd"),
    "scenes/buildings/Tent.tscn":      ("Node2D",     "res://src/entities/buildings/Building.gd"),
    "scenes/buildings/Cottage.tscn":   ("Node2D",     "res://src/entities/buildings/Building.gd"),
    "scenes/buildings/Market.tscn":    ("Node2D",     "res://src/entities/buildings/Building.gd"),
    "scenes/buildings/Farm.tscn":      ("Node2D",     "res://src/entities/buildings/Building.gd"),
    "scenes/buildings/Well.tscn":      ("Node2D",     "res://src/entities/buildings/Building.gd"),
    "scenes/buildings/Road.tscn":      ("Node2D",     "res://src/entities/buildings/Building.gd"),
    "scenes/buildings/Tavern.tscn":    ("Node2D",     "res://src/entities/buildings/Building.gd"),
    "scenes/buildings/GuardPost.tscn": ("Node2D",     "res://src/entities/buildings/Building.gd"),
}

TSCN_TEMPLATE = """\
[gd_scene load_steps=2 format=3 uid="uid://placeholder_{uid}"]

[ext_resource type="Script" path="{script}" id="1_{uid}"]

[node name="{name}" type="{root_type}"]
script = ExtResource("1_{uid}")
"""

def main():
    for rel_path, (root_type, script) in SCENES.items():
        os.makedirs(os.path.dirname(rel_path), exist_ok=True)
        if os.path.exists(rel_path):
            print(f"  skip  {rel_path}")
            continue
        name = os.path.splitext(os.path.basename(rel_path))[0]
        uid  = name.lower().replace(" ", "_")
        content = TSCN_TEMPLATE.format(
            uid=uid, script=script, name=name, root_type=root_type
        )
        with open(rel_path, "w") as f:
            f.write(content)
        print(f"  created {rel_path}")

if __name__ == "__main__":
    main()
