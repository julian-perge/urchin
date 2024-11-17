# Urchin

Fan remake of an ArmorGames game.

## File Layout

```text
# Main Zone Scene (zone_scene.tscn)
Root (Node2D)
├── Background (Node2D)
│   ├── ZoneBackground (TextureRect)
│   └── ParallaxBackground (ParallaxBackground)
│       └── ParallaxLayer
│           └── SkyBackground (TextureRect)
├── InteractiveObjects (Node2D)
│   ├── StoryOrb (OrbBase)
│   │   ├── Sprite2D
│   │   ├── CollisionShape2D
│   │   ├── Label
│   │   └── GlowEffect (CPUParticles2D)
│   ├── StoreOrb (OrbBase)
│   │   ├── Sprite2D
│   │   ├── CollisionShape2D
│   │   ├── Label
│   │   └── GlowEffect (CPUParticles2D)
│   └── TrainingOrb (OrbBase)
│       ├── Sprite2D
│       ├── CollisionShape2D
│       ├── Label
│       └── GlowEffect (CPUParticles2D)
├── UI (CanvasLayer)
│   ├── BottomHUD (Control)
│   │   ├── BottomBar (Panel)
│   │   │   ├── LeftButtons (HBoxContainer)
│   │   │   │   ├── InventoryBtn (TextureButton)
│   │   │   │   ├── AbilitiesBtn (TextureButton)
│   │   │   │   ├── SaveBtn (TextureButton)
│   │   │   │   ├── OptionsBtn (TextureButton)
│   │   │   │   └── RespecBtn (TextureButton)
│   │   │   ├── MapButton (TextureButton)
│   │   │   └── ZoneProgress (VBoxContainer)
│   │   │       ├── ProgressLabel (Label)
│   │   │       └── ProgressBar (ProgressBar)
│   ├── ZoneMap (Control)
│   │   ├── Background (TextureRect)
│   │   ├── ConnectionDrawer (Node2D)
│   │   ├── ScrollContainer
│   │   │   └── ZonesContainer (GridContainer)
│   │   │       ├── Zone1Button (ZoneButton)
│   │   │       ├── Zone2Button (ZoneButton)
│   │   │       └── ... (Additional zone buttons)
│   │   └── CloseButton (TextureButton)
│   ├── StoreWindow (Control)
│   │   ├── Background (Panel)
│   │   ├── ItemGrid (GridContainer)
│   │   │   └── ItemSlots (Array of ItemSlot)
│   │   ├── PlayerInventory (GridContainer)
│   │   └── GoldDisplay (Label)
│   └── MessageSystem (Control)
│       └── MessageLabel (Label)
└── Managers
    ├── ZoneManager (Node) # Autoloaded
    ├── StoreManager (Node) # Autoloaded
    └── FightManager (Node) # Autoloaded

# Custom Types:
- OrbBase: Base interactive orb with shared functionality
- ZoneButton: Interactive zone selection button
- ItemSlot: Individual store/inventory slot
```