# game/modes

Owner: Adam

Mode rules: teams, score limit, timer, zone, loot tables. Cards: T12, T15, A02, A05.

## What is here

| File | What it does |
| --- | --- |
| `arena_rules.gd` | `ArenaRules` (T12), server only: `MapRules` plus a smarter spawn pick and spawn protection. Without a match (offline, or a test), the arena map's `make_rules()` installs it. |
| `arena_team_rules.gd` | `ArenaTeamRules` (T15), server only: `ArenaRules` plus two teams from a `TeamBook`. Online, `--map=arena` uses it. |
| `team_book.gd` | `TeamBook` (T15): who plays for which team, joining, balancing, and peers that left. No network. |
| `arena_match.gd` | `ArenaMatch` (T15): scores, the score limit, the clock, the winner and the pause before the next match. No network. |
| `arena_mode.gd` | `ArenaMode` (T15): the match itself. The arena map adds it as its child `Mode` in online play only (never in the editor, an F6 run or offline), so its path is the same on every peer. |
| `spawn_picker.gd` | `SpawnPicker.pick()`, the pick as pure math: among the points the hero's team may use, the one farthest from the nearest living enemy; ties go to the one farthest from the nearest living teammate, then to MapRules' own stable pick. Straight-line distance. |
| `arena_rules_data.gd`, `data/arena_rules.tres` | The numbers below. The respawn delay stays `combat.tres` `respawn_sec` (4 s). |
| `tools/test_arena_rules.gd`, `tools/test_arena_teams.gd` | Headless tests; the smoke test runs every `test_*.gd` in `tools/`. |

## Numbers (`data/arena_rules.tres`)

| Number | Default | Meaning |
| --- | --- | --- |
| `spawn_protection_sec` | 2 s | After each respawn: no damage, no knockback. |
| `score_per_player` | 8 | The score limit is this x the players on teams (2 players: 16). |
| `match_length_sec` | 1200 s | The 20-minute cap. |
| `next_match_delay_sec` | 10 s | From a match's end to the next match. |

## Spawns and protection (T12)

The first spawn when a player joins gets no protection; firing does not end it.
Every respawn after that does, including a new match's `world.respawn_all()`
(#80), which brings every hero back at once with 2 s of protection.
A mode with teams must override `is_enemy()` as well as `team_of()`: the pick keeps away from enemies only.

## The arena match (T15)

Server decides; every peer hears.
- **Teams:** 0 Blue, 1 Orange. A new peer joins the smaller team (tie: the team
  behind on score, then Blue), the first time the server asks `team_of()` for it:
  that is when it picks the peer's first spawn point, so it lands on its team's side.
- **Balance:** when a player leaves and one team is 2 bigger, that team's newest
  player switches sides and respawns at once on its new side (no elimination).
- **A peer that left** keeps its last team for its shots still in flight (ShotSim
  asks about the shooter every step, and its last shot can still eliminate someone).
  It never counts in team sizes and never gets a team again. The next match forgets
  its team (`respawn_all()` clears the shots).
- **Score:** an elimination of an enemy gives the eliminator's team 1 point. The
  limit is `score_per_player` x the players on teams, recounted on join and leave,
  so a leave can end the match at once.
- **End:** a team reaches the limit, or the clock reaches 0 (higher score wins;
  equal is a draw, -1). The clock starts when the first player is in.
- **Next match:** `next_match_delay_sec` later: scores 0, a full clock, teams stay,
  `world.respawn_all()`. Eliminations in the pause don't score. When everyone
  leaves, the match waits for the next player.

### Events (on every peer: the server emits, then sends each to every ready peer)

| Signal | When |
| --- | --- |
| `match_started(&"arena")` | The first player is in, and each new match. |
| `team_assigned(peer_id, team)` | A peer gets a team or switches. |
| `team_score_changed(team, score)` | A team scores, and 0 for both at each match start. |
| `match_clock_changed(seconds_left)` | Each whole second while a match runs. |
| `match_ended(winning_team)` | 0, 1, or -1 for a draw. |

A late joiner, once ready, gets `match_started`, every playing peer's team (its own
too), both scores, the clock, and `match_ended` if it joins during the pause.
The mode's RPCs (`receive_started`, `receive_team`, `receive_score`, `receive_clock`,
`receive_ended`) go server to clients only, reliable, channel 0. NET_PROTOCOL 10.
There is no signal for the score limit, so the HUD can't show "first to <n>" yet.

### Log lines (server)

    [Mode] Player <id> plays for Blue (Blue <n>, Orange <m>)
    [Mode] match started: first to <limit>, or 20:00 on the clock
    [Mode] Orange scores (Blue <a>, Orange <b>; first to <limit>)
    [Mode] match over: Blue wins <a>-<b>; next match in 10.0 s   (or "draw")
    [Mode] everyone left, waiting for players

Clients log `[Mode] match over: Blue wins` (or `a draw`).

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
