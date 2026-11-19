class_name BattleClock
extends Control

# The original's clock, battleClocker (DefineSprite 3389): the dark ring 3388
# under thingerClock, whose two frames light the ring blue for the player's
# side or orange for the other side. Two hands light the ring as BattleTimeNow climbs to BattleTimeLimit
# (DefineSprite_3386/frame_1, the enterFrame scripts of PlaceObject2_3385_2 and
# PlaceObject2_3385_6). extract_battle_screen renders the lit ring on each
# frame at each BattleTimeNow from 0 to BattleTimeLimit, so this only picks the
# render to show.

enum Side { FRIEND, ENEMY }

const FRAMES: String = "res://assets/ui/battle/clock/%s_%03d.png"
const LABELS: Dictionary = {Side.FRIEND: "friend", Side.ENEMY: "enemy"}

@onready var _ring: TextureRect = $Ring


# Shows the ring on the frame of `side` at `battle_time_now`, in SWF frames.
# On Easy and Normal the conductor holds BattleTimeNow at BattleTimeLimit less
# 0.000001 (frame_217/PlaceObject2_3389_480 enterFrame, lines 639-642), which
# rounds to the render of the whole ring.
func show_time(side: int, battle_time_now: float) -> void:
	var frame: int = clampi(roundi(battle_time_now), 0, int(BattleRunner.BATTLE_TIME_LIMIT))
	var path: String = FRAMES % [LABELS[side], frame]
	if _ring.texture == null or _ring.texture.resource_path != path:
		_ring.texture = load(path)
