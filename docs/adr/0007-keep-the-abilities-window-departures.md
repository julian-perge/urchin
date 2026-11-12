# Keep four departures in the Abilities window

[#1](https://github.com/julian-perge/urchin/issues/1) asks for an ADR for any departure from the original that a player could notice. The Abilities window, the `skills` frame of `KRINMENU`, has four. The project owner settled all four after a side by side of the original's capture and the port, while writing [spec/107-abilities.md](../../spec/107-abilities.md). The rebuild ([#107](https://github.com/julian-perge/urchin/issues/107)) keeps each one.

## The departures

- **The pool keeps named rows.** The original's `talentPool` (3120) shows two columns of icon tiles with no names. The port shows one row for each ability, with its icon and its name, five rows at a time. A name tells the player what an ability is without a hover, so the rows are a quality-of-life addition. The rows' size and look are the port's own, so the rect test skips them by name.
- **The tree nodes show their rank.** Each node of `talenttreefull` (3100) shows its rank and its maximum rank, such as `1/3`. The original shows no rank on the node. The rank text is a quality-of-life addition.
- **The tree lines are drawn in code.** The port draws the lines between the nodes from the `TalentTree` data. It does not extract them as art. The lines come from the same data that decides what a node needs, so they cannot disagree with it.
- **The buttons are native Godot Buttons.** The tree nodes, the ring sockets, the pool's scroll buttons and the four attribute plus buttons are Buttons with StyleBoxFlat styles, not image buttons. Native Buttons are simpler to handle than image buttons. The cost is the SWF's art for them. For the plus buttons, that is the gradient plates and the black plus glyph (shapes 3064 to 3067). The original tints each plate with an additive colour transform, so no plate has one fill colour. The port fills each plus button with its row's name colour from the rect record.

## Consequences

- The rect test checks where each of these buttons lands, but not its art.
- A later change to any of the four is a new decision. It supersedes this ADR or the one item it changes.
