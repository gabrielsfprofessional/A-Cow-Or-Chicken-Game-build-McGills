# game/ui

Owner: John

Menus, HUD, lobby, hero select, results, leaderboard. Cards: T10, T16, T17, T24, T28, A11.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

## Hero select (card T16)

Play on the main menu opens `hero_select.tscn`, then the Join screen, which calls
`Net.play()`. Back or Esc returns to the menu.

- One card per hero in `game/heroes/data/roster.tres`, in roster order, so the card's
  position is the roster slot the world spawns. Each card shows the hero's name, role,
  Q ability name and default weapon name, all read from the data (`HeroRoster.at()`).
  Nothing is listed by hand and Gabe's files are only read.
- Arrows and Tab move, Enter or a click picks, Esc goes back. The picked card uses the
  theme's `HeroCard` style (mint border), never a team color.
- A pick sets `Net.chosen_hero_index` (the roster slot) and saves `last_hero`, the hero's
  file name (for example `mage`), in `user://settings.json` through `Settings`. The key
  is optional, so the file's version stays 1. A missing or unknown value starts on the
  first hero. A failed join comes back to the Join screen with the pick kept.
- It logs one line per pick: `[UI] hero picked: <file> (slot <n>)`.
- `--server`, `--join` and `--bot` launches never open it; they use `--hero`.
- Test: `game/ui/tools/test_hero_select.gd` (smoke does not run game/ui/tools yet; run it
  with `APPDATA` pointed at a temp folder).
