# A Cow or Chicken: rules for Claude Code

Read this before every task. Plan: docs/PROJECT_PLAN.md. Tasks: docs/BACKLOG.md. Workflow: docs/WORKFLOW.md.

## The game
2D top-down hero shooter, fantasy and sci-fi, for 5-16 family players aged 12-65.
Windows only. Keyboard and mouse. Arena mode for Thanksgiving (Nov 26, 2026), Battle Royale at v1 (Feb 27, 2027).

## Who you're working with
- Gabe: tech lead, Heroes & Combat. Technical.
- Adam: Maps & Modes. John: Look, Sound & Players. Not programmers.
With Adam and John: plain words, exact clicks and keys, one step at a time, wait after each step.
Never ask them to edit code by hand.

## Engine
- Godot 4.7.2 only. Editor: C:\Godot\Godot_v4.7.2-stable_win64.exe
- For commands use the console build: C:\Godot\Godot_v4.7.2-stable_win64_console.exe (or $GODOT if set).
- GDScript only, static types (var hp: int = 100), tabs for indentation.
- Never Godot 3 syntax: no KinematicBody2D, no yield (use await), no "export var" (use @export),
  no TileMap node (use TileMapLayer).
- Never edit .godot/. Do commit the .uid and .import files Godot creates.

## Smoke test (run it before saying anything is done)
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke.ps1
It imports the project, runs it headless and fails on any script error.
The same test runs on every pull request on GitHub (the "smoke" check).

## Architecture (ask Gabe before changing)
- A headless dedicated server is peer 1. Clients connect with ENet on UDP 7777 (autoload Net).
- Each client moves its own hero. The server decides hits, damage, abilities, deaths, pickups,
  zone, score and saves.
- Bullets: the server sends spawn events (origin, direction, speed); clients draw the flight.
- Tunable numbers live in Resources (.tres) in a data/ folder. Never hard-code a number someone
  might want to tune.
- Systems talk through signals on the Events autoload. Keys are defined only in game/core/game.gd.
- Never put the server address, a join key or player saves in the repo. They live in git-ignored
  files (server.cfg, saves/).

## Folders and owners
- Gabe: game/core, game/net, game/heroes, game/weapons (logic), server, tests, tools
- Adam: game/maps, game/modes, game/items, game/weapons/data
- John: game/ui, game/players, assets, audio
- docs/team/<name>.md belongs to that person.
Only edit the folders on the card. Ask before touching project.godot, autoloads or anyone else's folder.

## Every change
1. Start from an up-to-date main on a new branch named <name>/t<NN>-short-title.
2. Plan first: list every file you will create or change, then wait for "go".
3. Build it, then run the smoke test.
4. Give numbered steps to test it in Godot (F5 = whole game, F6 = current scene).
5. Only after "ship it": commit as "T<NN>: Title", push the branch, open a pull request with
   "Closes #<issue>" and a "How to test" section.
Never push to main. Never force-push. Only Gabe merges.

## Scenes
Keep scenes small: one script per scene root, stable node names. After creating or changing a scene,
ask the user to open it in Godot (double-click it in the FileSystem panel) and confirm the Output
panel shows no red errors.

## Style
Files and folders snake_case, classes PascalCase, signals past tense (hero_eliminated).
Art and sound must be CC0 or made by us; add every source to CREDITS.md.

## Never
- Commit files over 50 MB, or exports/, saves/, server.cfg, _bakeoff/, .godot/.
- Add plugins or addons without Gabe's OK.
- Fix a gameplay bug by changing network code; ask Gabe.
- Upgrade Godot. Everyone stays on 4.7.2 until after v1.
