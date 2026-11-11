# battle_settlement.gd
# Settles a finished battle in one call. settle() applies everything a win does
# to the save and the achievements file, the work of the original's
# post-battle frame (frame_219/DoAction.as) and its victory screen
# (DefineSprite_3142/frame_9), and returns the summary the result screens
# show. A loss or a draw changes nothing and ends the game.
#
# No autoload references - the achievements file comes in as a path, which the
# battle scene takes from ZoneManager.achievements_path.
class_name BattleSettlement
extends RefCounted

var outcome: BattleRunner.Outcome = BattleRunner.Outcome.ONGOING
var game_over: bool = false
var money_gained: int = 0
var xp_gained: float = 0.0
var levels_gained: int = 0
var fighting_party: Array[int] = []
var drops: Array[int] = []
var cutscene: String = ""
# One of ZoneProgression.CUTSCENE_GOTO_SCENE's values, or empty when the win
# queues no cutscene.
var goto_scene: String = ""
# The fight a win goes straight on to, with no victory screen. Empty for a win
# that opens the victory screen.
var next_fight: Dictionary = {}
# Only the ids this win unlocked, not ones the player already held, because the
# original's awardAch shows its banner only for those
# (frame_46/DoAction_2.as:3-9).
var achievements_unlocked: Array[int] = []


# Settles the battle the runner has finished. pick is the dictionary ZoneManager
# hands the battle scene: is_story_progress says whether a win moves the zone
# on, and train_cap clamps the "X" and "Z" levels the victory money averages.
# Settling a battle that isn't over reports an error and changes nothing.
# slot_saves are the saves in the four slot files, which All Star scans together
# with the live save.
static func settle(runner: BattleRunner, save: PlayerSave, pick: Dictionary, achievements_path: String, slot_saves: Array = []) -> BattleSettlement:
	var settlement := BattleSettlement.new()
	settlement.outcome = runner.win_condition as BattleRunner.Outcome
	if settlement.outcome == BattleRunner.Outcome.ONGOING:
		push_error("BattleSettlement.settle: battle %d isn't over" % runner.battle.id)
		return settlement
	# The original sends a draw on to loseCombat like a defeat
	# (DefineSprite_3355/frame_85/DoAction.as:5-16, frame_241/DoAction.as:1),
	# which resets the game and opens gameOverMenu (frame_230/DoAction.as:1-5,
	# frame_43/DoAction.as:21-25).
	settlement.game_over = settlement.outcome == BattleRunner.Outcome.LOSS or settlement.outcome == BattleRunner.Outcome.DRAW
	if settlement.outcome != BattleRunner.Outcome.WIN:
		return settlement
	# A Tutorial win only puts the class's starting moves back on the first two bar
	# slots (frame_219/DoAction.as:65-69). It pays nothing and settles nothing
	# else, because the original applies a win's money, XP, drops and achievements
	# on the victory screen (DefineSprite_3142/frame_9), which a Tutorial win never
	# opens (frame_181/PlaceObject3_3142_175 onClipEvent(load), lines 3-7).
	if runner.battle.id == ZoneProgression.TUTORIAL_BATTLE_ID:
		var starting_moves: Array = TalentTree.STARTING_MOVES.get(save.player_class, [])
		for i in starting_moves.size():
			save.move_matrix[i] = starting_moves[i]
		settlement.next_fight = ZoneProgression.FIGHT_AFTER_TUTORIAL
		return settlement

	var was_story_progress: bool = pick.get("is_story_progress", false)
	var progression: Dictionary = ZoneProgression.after_battle_won(save, runner.battle.id, was_story_progress)
	settlement.cutscene = progression["cutscene"]
	settlement.goto_scene = progression["goto_scene"]
	settlement.fighting_party = _fighting_party(runner.units)
	var train_cap: int = int(pick.get("train_cap", BattleSetup.DEFAULT_TRAIN_CAP))
	var money_levels: Array = BattleRewards.money_levels(runner.battle, save, train_cap)
	var enemy_levels: Array = BattleRewards.unit_levels_from_slots(runner.units, [2, 4, 6])
	var rewards: Dictionary = BattleRewards.apply_victory(save, money_levels, enemy_levels, settlement.fighting_party)
	settlement.money_gained = rewards["money_gained"]
	settlement.xp_gained = rewards["xp_gained"]
	settlement.levels_gained = rewards["levels_gained"]
	settlement.drops.assign(BattleRewards.roll_drops(runner.battle))
	var counters: Dictionary = Achievements.collect_battle_counters(runner, runner.units)
	for achievement_id in Achievements.check_battle_victory(save, runner.battle.id, was_story_progress, counters):
		if Achievements.unlock(achievement_id, achievements_path):
			settlement.achievements_unlocked.append(achievement_id)
	# Every win asks checkIfAllStar, which scans the slot saves and the live game
	# (DefineSprite_3142/frame_9/DoAction_2.as:64-67).
	var all_star_id: int = Achievements.NAMES.find("All Star")
	if Achievements.check_all_star(slot_saves + [save]) and Achievements.unlock(all_star_id, achievements_path):
		settlement.achievements_unlocked.append(all_star_id)
	return settlement


# The original pays XP to the companions in Krin.friendlySlotsFFTT, which
# krinAddNewUnit fills with each companion it spawns
# (frame_42/DoAction_14.as:187-192) as frame 201 spawns slots 1 to 6 in order
# (frame_201/DoAction.as:125, 206). Nothing takes a companion back out when it
# dies, so a fallen one still earns XP, and a guest never does.
static func _fighting_party(units: Dictionary) -> Array[int]:
	var party_ids: Array[int] = []
	var slots: Array = units.keys()
	slots.sort()
	for slot in slots:
		var unit: CombatUnit = units[slot]
		if unit.origin == CombatUnit.Origin.COMPANION:
			party_ids.append(unit.party_id)
	return party_ids
