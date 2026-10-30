# server

Owner: Gabe

Server-only code: player saves (T21), stats (T22), nightly backup, server boot.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

## Player saves: `profile_store.gd` (T21)

Part 1 is the store and its tools. Nothing in the game calls it yet. Part 2 (after #71)
sends the device token in a second auth message, checks name and color with T11's rules,
and saves each player.

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
- Crash test (not in smoke; about 1 minute): hard-kills a process that saves 8 players in
  a loop, 20 times at random moments. After each kill, no player that loaded before may be
  gone or go backwards, every save on disk must load, and no file may need moving aside.
  - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\save_crash_test.ps1`
  - Linux, CI, Git Bash: `GODOT=<godot> bash tools/save_crash_test.sh`

## Nightly backup

`tools\backup_saves.ps1` copies the saves folder into `<name>.partial`, checks the copy,
renames it to `saves-YYYYMMDD-HHMMSS`, keeps the newest 7 (`-Keep`), and logs one line per run
to `backup-log.txt` in the destination and to `%LOCALAPPDATA%\acoc-backup-log.txt`. It only
ever removes folders it named.

1. Copy the script out of the repo, so a branch checkout can't take it away at 3 am:

        Copy-Item C:\Dev\acoc-main\tools\backup_saves.ps1 C:\Dev\acoc-notes\backup_saves.ps1

2. Try it once:

        powershell -NoProfile -ExecutionPolicy Bypass -File C:\Dev\acoc-notes\backup_saves.ps1 -Destination "G:\My Drive\A Cow or Chicken\Backups"

3. Schedule it for 3 am (Gabe's OK first; run once in PowerShell). It runs hidden, on battery
   too, and a missed run starts when the PC wakes up:

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Dev\acoc-notes\backup_saves.ps1" -Destination "G:\My Drive\A Cow or Chicken\Backups"'
        $trigger = New-ScheduledTaskTrigger -Daily -At 3am
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "A Cow or Chicken save backup" -Action $action -Trigger $trigger -Settings $settings

   When the script changes in the repo, copy it again (step 1).

## Restore a backup

1. Stop the server.
2. Rename the saves folder to `saves-broken-<date>`. Never delete it.
3. Copy the chosen `saves-YYYYMMDD-HHMMSS` folder (never a `.partial` one) from the Drive to
   the same place and name it `saves`.
4. Start the server, and check that a player who saved before the backup still loads.
