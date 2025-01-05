# Urchin

Fan remake of an ArmorGames game.

## File Layout

```text
res://
├── scripts/
│   ├── autoload/
│   │   ├── game_data.gd        # Global game state
│   │   ├── constants.gd        # Game constants
│   │   ├── zone_manager.gd     # Zone progression & state
│   │   └── store_manager.gd    # Store system & inventory
│   ├── battle/
│   │   ├── battle_manager.gd   # Battle system controller
│   │   ├── ability.gd         # Base ability class
│   │   ├── buff.gd           # Buff/debuff system
│   │   └── fight_types/
│   │       ├── story_fight.gd    # Story fight logic
│   │       └── training_fight.gd  # Training fight logic
│   ├── entities/
│   │   ├── character.gd      # Base character class
│   │   ├── player.gd         # Player character
│   │   └── enemy.gd          # Enemy character
│   ├── zones/
│   │   ├── zone_scene.gd     # Main zone scene logic
│   │   ├── zone_map.gd       # Zone map & connections
│   │   └── interactive/
│   │       ├── orb_base.gd           # Base orb class
│   │       ├── story_fight_orb.gd    # Story fight orb
│   │       ├── item_store_orb.gd     # Store orb
│   │       └── training_fight_orb.gd  # Training fight orb
│   └── ui/
│       ├── battle_ui.gd      # Battle interface
│       ├── menu_ui.gd        # Menu systems
│       ├── zone_ui/
│       │   ├── zone_hud.gd         # Zone HUD elements
│       │   ├── zone_button.gd      # Zone selection button
│       │   └── progress_bar.gd     # Zone progress display
│       └── store_ui/
│           ├── store_window.gd     # Store interface
│           └── item_slot.gd        # Item slot in store
├── scenes/
│   ├── battle.tscn          # Battle scene
│   ├── menu.tscn           # Menu scene
│   ├── character.tscn      # Character scene
│   ├── zones/
│   │   ├── zone_scene.tscn       # Main zone scene
│   │   ├── zone_map.tscn         # Zone map scene
│   │   └── interactive/
│   │       ├── orb_base.tscn     # Base orb
│   │       ├── story_orb.tscn    # Story fight orb
│   │       ├── store_orb.tscn    # Store orb
│   │       └── training_orb.tscn # Training fight orb
│   └── ui/
│       ├── zone_hud.tscn         # Zone HUD
│       ├── zone_button.tscn      # Zone map button
│       └── store_window.tscn     # Store interface
└── resources/
	├── abilities/          # Ability resources
	├── items/             # Item resources
	├── zones/             # Zone-specific resources
	│   ├── zone_data.tres        # Zone definitions
	│   └── zone_connections.tres  # Zone connection map
	└── visuals/           # Visual resources
		├── orbs/                # Orb textures/effects
		└── backgrounds/         # Zone backgrounds
```

## Scene Tree Layout

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
