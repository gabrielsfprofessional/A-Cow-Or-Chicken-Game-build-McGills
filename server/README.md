# server

Owner: Gabe

Server-only code: player saves (T21), who is joining (T21 part 2), stats (T22), nightly backup.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

## Player saves: `profile_store.gd` (T21)

Part 1 is the store and its tools. Part 2 (below) sends the device token in a second auth
message, checks name and color with T11's rules, and saves each player.

- **One file per player:** `<id>.json`. The id is the SHA-256 of the player's device token,
  as 64 lowercase hex characters. The token itself is never stored, printed or logged.
- **Folder:** `-- --saves=<path>` when given, in any build. Otherwise release builds use
  `user://saves/`, and debug builds use `user://saves_test/` (the editor, the console build,
  smoke, bots, tests). On Windows, `user://` is `%APPDATA%\Godot\app_userdata\A Cow or Chicken\`.
- **The family server** must be a release export (T29) or run with `-- --server --saves=user://saves/`.
  `Godot_v4.7.2-stable_win64_console.exe` is a debug build: without `--saves` it saves to
  `saves_test`, which tests share.
- **Safe writes:** `<id>.json.tmp` first, loaded back to check it, then `<id>.json` becomes
  `<id>.json.bak` and the temp file becomes `<id>.json`. A crash loses at most the newest save.
- **Pulled plug:** Godot can't force a file onto the disk, and Windows may keep a new file in
  memory for a few seconds. So while `<id>.json` is younger than `settle_sec` (30 s), an older
  `.bak` is kept as `<id>.json.old` instead of being deleted. A pulled plug loses at most the
  saves of the last 30 s, never the player.
- **Nothing is deleted that can't be read:** a file that can't be parsed is renamed to
  `<file>.bad-<unix time>`. A file that can't be opened (locked by antivirus or a backup)
  makes `load_player()` answer LOCKED, and saving is refused until it opens. A save from
  another version of the game is left alone, and saving over it is refused.

`load_player(id)` answers OK (with the data), MISSING (a new player), LOCKED (try again
later, never treat as new) or NEWER/OLDER (another version: leave it alone).

A save (version 1):

```json
{
	"color": "#3B82F6",
	"created_unix": 1793000000,
	"id": "<64 hex characters>",
	"last_seen_unix": 1793000000,
	"name": "Gabe",
	"stats": {"damage": 0, "eliminations": 0, "heroes": {}, "matches": 0, "wins": 0},
	"version": 1
}
```

Changing a field means raising `ProfileStore.VERSION` and teaching `_read()` the old one.
Until then an older save reads as OLDER and is left alone.

## Tests

- `tests/profile_store_test.gd` (runs in smoke): folders, ids, a round trip, every validation
  rule, a crash while writing the temp file and between the two renames, a cut-short file,
  both files unreadable, saves from a newer game (main and `.bak`), a file holding another
  player's id, unknown fields, numbers JSON would change, a name that wouldn't load back,
  the `.old` copy and a pulled plug after quick saves, locked files (Linux and macOS as a
  user that can't open them; skipped on Windows and as root), listing.
- `tests/player_auth_test.gd` and `tests/player_registry_test.gd` (run in smoke): the second
  auth message's rules, and the registry's saves and guests (part 2).
- Smoke's "player saves" stage: a server with its own folder, two windows with one test
  profile and a bot, over the network (tests/README.md, "Player saves").
- Crash test (not in smoke; about 1 minute): hard-kills a process that saves 8 players in
  a loop, 20 times at random moments. After each kill, no player that loaded before may be
  gone or go backwards, every save on disk must load, and no file may need moving aside.
  - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\save_crash_test.ps1`
  - Linux, CI, Git Bash: `GODOT=<godot> bash tools/save_crash_test.sh`

## Who is joining: `player_auth.gd` and `player_registry.gd` (T21 part 2)

- `PlayerAuth` writes and reads the second auth message: `{"name", "color", "token"}` from the
  player's profile, or `{"guest": <reason>}` for a test bot or a PC with no profile. Pure
  functions; the server reads with `read_message()` and anything that breaks T11's rules
  makes a guest. The name check is T11's without the font (`name_ok()`), since a dedicated
  server export may strip fonts. Details: game/net/README.md, "Who is joining".
- `PlayerRegistry` is the server's list of connected players. On connect it loads or makes
  the save and saves it with the name, color and time; on leaving, and when the server
  closes, it saves the last-seen time. Guests get no save: bots, no profile, a broken
  message, a token already connected (a second window with the same profile), a save that
  is locked or from another version (left alone).
- The server logs `[Server] player saves in <folder>` at start and one `[Server]` line per
  peer, naming a player by the first 8 characters of their id, never the token.
- `player_id(peer)` names the save, `add_stats(peer, delta)` adds a match's counts to it
  (T22, below), and `player_name(peer)` is the name the test world sends to every peer in
  the hero's spawn data (names above heroes, T17).

Two players on one PC: start the second window with `-- --profile=<another profile.json>`
(debug builds). With the same profile, the second window plays as a guest.

## What a match records: `match_stats.gd` (T22)

Each player's save counts `matches`, `wins`, `eliminations`, `damage` and `heroes` (matches
per hero). The server records them; a client never sends a stat.

- `MatchStats` counts between a mode's `match_started` and `match_ended` (signals on Events;
  the arena mode, T15, emits them). Pure: no network, no files.
  - Damage dealt: each `hero_damaged` with an amount above 0 (0 is a hit that spawn
    protection absorbed) that isn't on yourself.
  - Eliminations: each `hero_eliminated` by another peer.
  - Teams come from `team_assigned`, whenever it arrives; the last one counts.
- At `match_ended(winning_team)`, every player on a team gets `matches` +1, `wins` +1 when
  their team won (nobody on a draw, -1), their eliminations and damage, and +1 for the
  hero they play then, by its file name in game/heroes/data (`scout`; display names can change).
- A player who leaves mid-match keeps their eliminations and damage, with no match, win
  or hero. The same when the server shuts down mid-match the normal way (`Net.leave()`); a
  server that is killed saves nothing for that match.
- A match nobody finishes (everyone left) gives nobody a match. Hits before the first match
  and between matches count nothing.
- Guests and bots get nothing: they have no save.
- Net (game/core/net.gd) wires it on the server, next to `PlayerRegistry`, and hands each
  answer to `PlayerRegistry.add_stats()`. That merges it into the registry's copy and saves
  at once with `ProfileStore`'s safe write, so the save on leaving keeps it. Counts that
  would break a save's rules are refused whole. If the disk refuses, the counts stay in
  the copy and the save on leaving writes them.
- One log line per save, naming the player by the first 8 characters of their id:

        [Record] Player 3eb1bd43: matches +1, wins +1, eliminations +3, damage +240, scout +1

  A leaver's line has no hero. A refusal reads `[Record] Player 3eb1bd43: not recorded (<why>)`.
- Tests (run in smoke): `tests/match_stats_test.gd` (every rule above) and
  `tests/player_registry_test.gd` (`add_stats()`).

## Hosting checklist

Before a playtest, on the server laptop (Gabe's), in this order:

1. The network cable is in; Wi-Fi is off; the VPN is off. The server then has one address:
   the one the router's UDP 7777 forward points at. Check it in `ipconfig` against the
   router's forward before players arrive; a build made for the house has that address inside.
2. The laptop is on its charger.
3. Nothing else runs on the server laptop: no game, Discord, browser, smoke test or bots.
   A server on this laptop has frozen in two kinds of run. Every run with 16 bots on the same
   PC froze for up to 0.9 s (Nov 11 and Nov 14). On Nov 14 a practice run with only 4 players
   froze for 2.2 to 9.9 s, as if the whole PC paused. No 8-player run has frozen (218 ten-second
   windows, Nov 14-15). The cause isn't proven yet.
4. OneDrive and other backups are paused for the playtest.
5. 4 GB or more of memory is free.
6. Windows Firewall lets UDP 7777 in on Private networks (one inbound rule, set once per PC).
7. UDP 7777 is free, then start the players' build's own server from its release folder:
   `server\ACowOrChickenServer.console.exe --headless -- --map=arena`. A release build saves
   to the family's folder by default, `user://saves/` (on Windows
   `%APPDATA%\Godot\app_userdata\A Cow or Chicken\saves\`), so its log must read exactly
   `[Server] player saves in user://saves/`. A line naming `saves_test` means a debug build:
   stop it at once, it must not host players.
8. After the last match (its `[Mode] match over` line and its `[Record]` lines), stop the
   server and run the backup (below) once by hand. Before any player with a profile has
   joined, the saves folder is empty and the backup is a FAIL by design.

## Nightly backup

`tools\backup_saves.ps1` copies the saves folder into `<name>.partial`, checks the copy,
renames it to `saves-YYYYMMDD-HHMMSS`, keeps the newest 7 (`-Keep`), and logs one line per run
to `backup-log.txt` in the destination and to `%LOCALAPPDATA%\acoc-backup-log.txt`. It only
ever removes folders it named. A saves folder with no files is a FAIL (exit 1) that makes no
backup and removes none (it only logs the FAIL), so an empty run can never rotate out the real backups. Its test:
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_saves_test.ps1`.

1. Copy the script out of the repo, so a branch checkout can't take it away at 3 am:

        Copy-Item C:\Dev\acoc-main\tools\backup_saves.ps1 C:\Dev\acoc-notes\backup_saves.ps1

2. Try it once:

        powershell -NoProfile -ExecutionPolicy Bypass -File C:\Dev\acoc-notes\backup_saves.ps1 -Destination "$env:OneDrive\ACowOrChicken-Backups"

   The backups go to a OneDrive folder only Gabe can open, never the shared folder that holds
   the install zip.

3. Schedule it for 3 am (Gabe's OK first; run once in PowerShell). It runs hidden, on battery
   too, and a missed run starts when the PC wakes up:

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\Dev\acoc-notes\backup_saves.ps1`" -Destination `"$env:OneDrive\ACowOrChicken-Backups`""
        $trigger = New-ScheduledTaskTrigger -Daily -At 3am
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "A Cow or Chicken save backup" -Action $action -Trigger $trigger -Settings $settings

   When the script changes in the repo, copy it again (step 1).

## Restore a backup

1. Stop the server.
2. Rename the saves folder to `saves-broken-<date>`. Never delete it.
3. Copy the chosen `saves-YYYYMMDD-HHMMSS` folder (never a `.partial` one) from the backup folder to
   the same place and name it `saves`.
4. Start the server, and check that a player who saved before the backup still loads.

Tried on Nov 15 on a throwaway saves folder (scripted check, Gabe's Claude): a test player
saved, `tools\backup_saves.ps1` backed the folder up, the folder was renamed as in step 2 and
the backup copied back as in step 3; the restarted server loaded the player as "returning",
and the restored save was byte for byte the one backed up. A save holds the player's name,
color, stats, dates and the SHA-256 of their device token, never the token itself.
