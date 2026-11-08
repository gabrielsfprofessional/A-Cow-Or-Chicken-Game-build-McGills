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
- Test: `game/ui/tools/test_hero_select.gd` (smoke runs it; by hand, point `APPDATA`
  at a temp folder).

## HUD: team scores, clock and winner banner (card T17, part 2)

The HUD (`hud.tscn`, built by the `Overlay` autoload) also shows the match, from the
`Events` signals only (`game/core/events.gd`, README "Seams for week 3" in game/net):

- Top centre: `Blue n`, the clock as `mm:ss` (1200 is `20:00`), `Orange n`, and under them
  `You are on <team>`. Nothing shows until the first match event arrives, so the test
  world (no teams) looks the same as before.
- `team_assigned` counts for your own peer id only and is followed at any time, so a
  balance switch moves you to the other team on screen. Overlay hands the Hud your peer
  id (`set_own_peer()`); the Hud keeps every peer's team, so a team that arrives before
  your id is known still shows.
- A banner (`Blue wins!`, `Orange wins!` or `Draw` for -1) shows from `match_ended` until
  `match_started`. There is no "first to <n>": no signal carries the limit.
- Everything clears when you are not a client any more (`clear_match()`), so the next
  match starts from zero.
- The Hud keeps the last value of each event, and Overlay calls `listen()` when it is
  built (not on a headless run), before this client is ready. The late-join replay is
  therefore never missed, even while the HUD is still hidden.
- Team colors (`blue_color`, `orange_color`) and the banner size are `@export` values on
  the Hud. They color the score names, `You are on ...` and the banner only, never a hero.
- Names stay on each hero's own label (#86); the HUD adds no name tags.
- Test: `game/ui/tools/test_hud.gd` (smoke runs it; by hand, point `APPDATA` at a temp
  folder). Preview without a server: F6 on `hud_preview.tscn`; B / O add Blue / Orange
  points, X switches your team, W shows the banner.
