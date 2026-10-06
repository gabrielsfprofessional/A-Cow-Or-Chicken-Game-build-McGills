# Adam: Prompt 1 (your first session)

**Start after Gabe posts "repo is ready".** Time: 60-90 minutes.

## Before you paste
1. Finish [docs/SETUP.md](../docs/SETUP.md), steps 1-8.
2. In GitHub Desktop click **Fetch origin** (top bar), then **Pull origin** if it appears, so you have the newest files.
3. In the Claude app's **Code** tab, start a new session on the game folder (**Local > Select folder**).

## Copy this into Claude Code
Hover over the box, click the copy icon in its top-right corner, paste into Claude Code, send.

```text
I'm Adam. I own Maps & Modes for our family game "A Cow or Chicken" (Godot 4.7.2 on Windows). I'm not a programmer: use plain words, give exact clicks and keys, do one step at a time, and wait for me after each step.

First read CLAUDE.md, docs/WORKFLOW.md and my cards in docs/BACKLOG.md (owner Adam). Then:

1. Setup check. Confirm git works, run `gh auth status`, and check that C:\Godot\Godot_v4.7.2-stable_win64_console.exe --version says 4.7.2. Run the smoke test. Fix or explain anything that's missing.

2. Card T02, my first pull request. Update main and create branch adam/t02-team-card. Fill in docs/team/adam.md: ask me for my GitHub username, real hours per week and best weekly sync time; collect my PC specs yourself and show them to me before saving. Commit as "T02: Adam team card", push, and open a pull request whose body says "Part of #<T02 issue number>" (find the number with gh). Show me the link.

3. Card T05, Arena graybox v0. Update main and create branch adam/t05-arena-graybox. Plan the scene game/maps/arena/arena_graybox.tscn: about 2 x 2 screens (3840 x 2160 pixels), outer walls, 10-14 cover blocks made of plain gray rectangles I can drag and resize in the editor, and 8 spawn points (Marker2D nodes named SpawnA1-SpawnA4 and SpawnB1-SpawnB4, 4 per team on opposite sides). Add a fly camera so I can press F6 and look around: WASD or arrow keys to move, mouse wheel to zoom. Show me the plan and wait for "go". Then build it, run the smoke test, and teach me how to move and resize a wall in the Godot editor. When I say "ship it", open the pull request with "Closes #<T05 issue number>".

Rules: only change files in game/maps/ and docs/team/adam.md. Never push to main. End with a 3-line summary and my next card.
```

## What happens
1. Claude checks your setup and runs the smoke test.
2. It walks you through your first pull request (T02). Gabe merges it.
3. It builds a gray test arena you edit by dragging boxes, and teaches you how (T05).

## If something goes wrong
- Hit your usage limit: come back later and type `Continue where we stopped.`
- Godot shows red errors: copy the red text into Claude Code.
- Anything else: screenshot it and send it to the family chat.

## After this
Your next cards: T12 (team spawns), T15 (Arena rules), T19 (weapon data), T20 (practice range), T23 (Arena map v1). Start each in a fresh session with `/build-card T<NN>`.
