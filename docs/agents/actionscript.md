# ActionScript and game data

Where the original game's logic and data live, and the mistakes this project
has already made reading them.

## Where the authorities are

- `dev/source_files/action_script/` is the full ffdec script export and the
  authority for game logic. `action_script_curated/` holds commented excerpts.
- `dev/data_json/` is a runtime capture of the Steam build's live `_root`
  arrays, not an export. No script produces it and none can. See
  `SWF_DIFFERENCES.md`.
- The original's English text is in `dev/converted_json/strings.json`.
  `just convert-strings` (`uv run convert_strings`) writes it from the
  `KrinLang.ENGLISH` table in `frame_1/DoAction.as`, with each array index
  equal to the AS index. GDScript reads it through `Strings`, as in
  `Strings.system(17)`, and does not type the text as a literal.
- `DECODED_ALGORITHMS.md` holds behavior already decoded from the AS so it
  never has to be re-derived. Check it before reading the AS yourself.
- `KNOWN_GAPS.md` is deliberate scoped-out gaps. `NEXT_PHASES.md` is what has
  not been built. Both carry DONE entries with what was found.

## Find the place before you read it

Run `just as-lookup <query>` before `rg` on the export. One lookup gives
what `rg 'function X'` and a `sed -n` of a line range take several calls to
find. It prints one answer for each kind of query:

- A function name, such as `executeMove`: the file and line range, the source
  lines (the outline of its blocks when the function has more than 120 lines),
  each caller, each function it calls with the place that defines it, and the
  globals it writes and reads.
- A global name, such as `perKSuccess`: each line that writes it and each
  function or script that reads it.
- An export path, or the unique end of one, such as `frame_42/DoAction_8.as`:
  the same answer for the script, with the functions it defines.
- A path with a line, such as `frame_42/DoAction_8.as:82`: the function that
  holds the line and the chain of blocks around the line.

Each answer ends with `ports`, the GDScript comments that cite that range, so
it shows where the port already implements the code.

The lookup is for navigation only. Read the original lines before you port or
decide anything, because the index is not an authority on behavior. It matches
a caller by name, and it does not resolve which timeline a bare name such as
`AVGNUMC` lands on.

## Reading the ActionScript

- **An array can index by name rather than by order.** `Krin.zoneName`
  (`frame_41/DoAction_2.as`) maps a zone onto a frame label by name, so zone 5
  is CITY and zones 6 and 7 are ROME and JAPAN. Reading it positionally is how
  this repo recorded "zones 6 and 7 have no hub art" as an unclosable gap when
  both have real art (`8ef2139`).
- **Instance names in the SWF can be wrong.** Two of the three class-select
  card instance names disagree with the class they show. The authority is the
  button beside the card, because it sets `Krin.Class` (`fd755b3`).
- **Two fields that look like one usually are two.** The hall and the sky are
  `Krin.ZoneBG` and `Krin.SkyBG`, set independently per battle; 16 of 99
  battles differ. A digit-stripping heuristic derived one from the other and
  got 10 of those 16 wrong (`8c293c8`).
- **A blank data field does not mean the game shows nothing.** Check whether
  the original reads that field at all. Every tree passive's
  `25_tooltip_description` is 0, which was recorded as a data fact and asserted
  in a test; the original never reads it, and takes the text from
  `KrinLang.ENGLISH.BUFFSAY` instead (`46d16da`).
- **Player-facing text comes from `KrinLang.ENGLISH.*`, not the item or buff
  record.** `ITEMNAME[id]` overwrites the item record's own name at load
  (`frame_42/DoAction_16.as`). `internal_name` disagrees with what the game shows
  and nothing in the icon path reads it; a reported collision between four item
  pairs was a read of that field and there was nothing to fix (`dc4c5b2`).
- **Check what an id means before treating it as an index.** `buffId` looks
  numeric and is a string name: buffs register as `_root["KRINBUFF" + name]`.
  Reading it as a frame number matches by chance for 9 of 410 buffs and sends
  every id past 400 to a placeholder (`cfaedb5`).
- **Watch off-by-one in rank tables.** `BUFFSAY` is 0-indexed for rank 1 and
  the original clamps its index up from -1, so rank 0 and rank 1 both show the
  first entry (`46d16da`, `f068f87`).
- **A name in a function body can be a parameter, not a global.** ADR 0005
  said `buffTicker` plays the Shield clip through `IDKT`, a global that
  `executeMove` last set. `IDKT` is a parameter of `executeMove` and is never
  assigned, so the original plays no clip. Before you write that a variable is
  a global, find its declaration and run `rg -uu 'NAME\s*=[^=]'` over
  `dev/source_files/action_script` for an assignment (`c8733b7f`).
- **Flash folds case in linkage lookups.** `KRIN.MAGICBOLT` and
  `Krin.Magicbolt` are the same clip; resolve export names case-insensitively
  (`4ccdb39`).
- **An export name can resolve to a wrapper.** "KrinTrail" is sprite 3, a
  one-frame wrapper whose only frame shows its child's alpha-0 keyframe, which
  is why that clip extracted fully blank. The real 33-frame content is sprite
  2, which has no export name and is only reachable by id (`4ddee5c`).
- **Battle ids in the raw dump are not all correct.** All nine
  `battleCreationID` resets relabel the battle just populated instead of the
  next one, so 2, 55, 109, 212, 308, 409, 513, 603 and 703 came through as
  49, 99, 199, 299, 399, 499, 599, 699 and 999. `battles.py`'s
  `MISLABELED_BATTLE_IDS` corrects all nine at conversion time. `c13cff0`
  corrected only 109, 409 and 513, which left the zone 2, 3, 6 and 7 bosses
  and the tutorial unable to load.
