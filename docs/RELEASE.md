# Making a release (card T29)

Only Gabe does this. It turns main into the Windows game and the Windows server,
checks both work, and makes the zip the family downloads from the Drive.
It takes about 20 minutes, most of it the 10-minute bot test.

## Once per PC

1. The official Godot 4.7.2 export templates. In the Godot editor:
   **Editor > Manage Export Templates > Download and Install**. The download is about
   1.3 GB, and they take about 2 GB on disk. They go to
   `%APPDATA%\Godot\export_templates\4.7.2.stable\`. Never use other templates.
   To see they're installed: that folder has `windows_release_x86_64.exe`,
   `windows_release_x86_64_console.exe` and a `version.txt` that says `4.7.2.stable`.
2. `server.cfg` in the main folder (git ignores it; never commit it). It holds the
   address the game joins when a player clicks Play:

       [server]
       address="<the server's address>"

   The Thanksgiving build uses the on-site server's LAN address; the home build
   uses the public address, or the LAN address if NAT loopback failed at Gate 1.
   Reserve that PC's IP on the router first, so the address stays right.

## Every release

1. The version bump is its own one-line pull request (`config/version` in
   `project.godot`), merged first. The release script never changes the version.
2. In the main folder: `git switch main`, then `git pull --ff-only`.
3. Stop any server on this PC (UDP 7777 must be free).
4. Run, with an output folder outside the repo:

       powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1 -Out C:\Dev\acoc-releases

5. It ends with `RELEASE: PASS`, the zip's file list, its SHA-256 and the Drive steps.
   Anything else: read the `RELEASE: FAIL` line; the logs are in the release
   folder's `logs\`.
6. Double-click `client\ACowOrChicken.exe` in the release folder. The script's checks
   run headless, so this is the one look at the real window: the main menu opens and
   shows the new version. Click **Quit**.

## What each check proves

| Step | Check | Why |
| --- | --- | --- |
| 0 | Godot 4.7.2, templates, clean main at origin/main, server.cfg has an address, UDP 7777 free | The zip is exactly main, built with the official engine |
| 1 | `tools\smoke.ps1` | Nothing is broken before a 10-minute run |
| 2 | Both presets export with `--export-release` and the data is inside each `.exe` | No debug build reaches the family; one file to copy |
| 3 | The game prints `[Net] server.cfg: found, Play joins its address`, and the address is in none of its output | Play joins the right server; the address never lands in a log |
| 4 | The exported game joins the exported server with `--version-override` and the server sees the real version | Release builds ignore the debug flags |
| 5 | 8 bots (console editor build, this commit) play 10 minutes against the exported server, started with no `--server` flag; every bot exits 0, the server stays up, 8 joins, hits, no error or refusal line; the server is then stopped by PID and UDP 7777 is free | The real server build holds a match |
| 6 | `LICENSES.txt` (Godot's license, its copyright notices, third-party texts) | Godot's license must ship with the game |
| 7 | The zip holds exactly the game `.exe` and `LICENSES.txt`, at their sizes, with a `.sha256.txt` | What the family downloads |

Steps 4 and 5 save to the release folder's `test-saves\`, and the script stops if the
server says otherwise. A release server's default folder is the family's saves.
Step 4's test game joins with this PC's real profile. It only reads the profile, and
the save it leaves in `test-saves\` has the player's id, name and color, never the token.

The server build (`server\`, both files) stays on the server PC. Start it from a
window with `ACowOrChickenServer.console.exe --headless -- --map=arena`, so you can
see its lines.

## The Drive

The family folder has `Latest` and `Previous`. The script prints the steps:
empty `Previous`, move the old zip from `Latest` into `Previous`, upload the new
zip and its `.sha256.txt` into `Latest`, then post the version in #dev.

Rolling back: move the zip in `Previous` back into `Latest`, and start the
matching server build. A game and a server of different versions refuse each
other ("Update the game from the Drive folder").

## Testing the script itself

`-TestBranch` runs every step from a branch that contains main. The zip is named
`TEST-...` and no Drive steps are printed: such a zip never goes to the Drive.
