# Battle

A battle shows the player's team on the left and the enemies on the right,
with HP and focus bars at the top. The player clicks an enemy to open the
radial menu, picks a move orb, and watches the half-turn play. The bottom
bar has the stance rows of the companions, the pass button in the clock,
the retreat x and the Log toggle.

## Sub-features

- `battle-speech` shows the speech box and skips it with Space.
- `battle-attack` opens the radial menu on an enemy and runs a move.
- `battle-pass` passes the turn with the button in the clock. Not yet driven.
- `battle-stance` sets a companion stance in the bottom bar. Not yet driven.
- `battle-log` opens the combat log with `Log`. Not yet driven.

## How to get to it (user POV)

- Click the red story orb in the hub (`ZoneHost/Zone1/StoryFight/Control`).
  With the `rich` preset this starts battle 109 against Felicity.
- Click the yellow training orb. Not yet driven.
- Setup shortcut, not a player path:
  `$V launch v --scene res://scenes/battle_scene.tscn -- --battle=109`.

## Driving it with urchin_verify

Preconditions:

- `$V launch v --scene res://scenes/battle_scene.tscn -- --battle=109`, or
  the hub path above.
- `$V log v --grep "waiting for player"` prints a line. The enemy acts
  first, so this takes a few seconds.

- **Skip speech.** Run `$V send v '[{"type":"key","key":"Space"},{"type":"wait","duration_ms":1500},{"type":"screenshot"}]' --label battle-skip`.
  The speech box goes away.
- **Find the enemy.** Run `$V tree v Battlefield --depth 3`. Each fighter
  has an `Overlay/HitButton` (56x100). The enemy is the one on the right.
  In battle 109 it is
  `HallWindow/HallSpace/BattleScreenClip/Battlefield/FighterPresenter/Overlay/HitButton`
  at rect `[609.9, 245.4, 56, 100]`, center `(637.9, 295.4)`.
- **Attack.** The radial menu opens around the enemy's Overlay. Orb0 is 51 px
  above that point. Open and pick in one sequence:
  `$V send v '[{"type":"click","x":637.9,"y":295.4},{"type":"wait","duration_ms":150},{"type":"screenshot"},{"type":"click","x":637.9,"y":246.4},{"type":"wait","duration_ms":3000},{"type":"screenshot"}]' --label battle-attack`.
  The first screenshot shows the red target ring and the move orbs. The
  second shows a damage number over the enemy and a lower HP on its bar.
- **Side effect.** Run `$V log v --grep "result shown"`. The last line has
  `target=2 (Felicity)` and an HP under 4044.
- **Proof.** Both screenshots of the attack and the log line.

## Gotchas

- On Linux the radial menu closes 0.82 s after the real cursor is away from
  it. Two separate `click` calls take too long, so the second click lands
  on a closed menu and nothing happens. Use one `send`.
- `RadialMenu/Orb<n>` reports `visible: false` while the menu is closed,
  but its rect stays where the menu last opened. After one open,
  `$V node v RadialMenu/Orb3` gives that orb's center.
- A left click outside a Decision shows the "cannot move yet" banner.
  Wait for `waiting for player` in the log first.
- The orb tooltips follow the real cursor on Linux. They need `send --warp`,
  which moves the user's cursor. Ask first.
- Only the first presenter has a fixed name. Find the others by rect.
- The two entry points give different teams. From the hub with `rich`,
  battle 109 has Sonny, Roald and Veradux against Felicity. With
  `--battle=109` it has Sonny and Veradux, and the first stance row reads
  `< Team Member Inactive >`. Felicity's HitButton has the same rect in
  both (checked 2026-11-21).
- Companions act in the same half-turn, so the log can show more than one
  `result shown` line for Felicity after one pick. Check that her HP is
  lower than before the pick, not which line came from the player.
