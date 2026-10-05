# John: Prompt 1 (your first session)

**Start after Gabe posts "repo is ready".** Time: 60-90 minutes.

## Before you paste
1. Finish [docs/SETUP.md](../docs/SETUP.md), steps 1-8.
2. In GitHub Desktop click **Fetch origin** (top bar), then **Pull origin** if it appears, so you have the newest files.
3. In the Claude app's **Code** tab, start a new session on the game folder (**Local > Select folder**).

## Copy this into Claude Code
Hover over the box, click the copy icon in its top-right corner, paste into Claude Code, send.

```text
I'm John. I own Look, Sound & Players for our family game "A Cow or Chicken" (Godot 4.7.2 on Windows). I'm not a programmer: use plain words, give exact clicks and keys, do one step at a time, and wait for me after each step.

First read CLAUDE.md, docs/WORKFLOW.md and my cards in docs/BACKLOG.md (owner John). Then:

1. Setup check. Confirm git works, run `gh auth status`, and check that C:\Godot\Godot_v4.7.2-stable_win64_console.exe --version says 4.7.2. Run the smoke test. Fix or explain anything that's missing.

2. Card T02, my first pull request. Update main and create branch john/t02-team-card. Fill in docs/team/john.md: ask me for my GitHub username, real hours per week and best weekly sync time; collect my PC specs yourself and show them to me before saving. Commit as "T02: John team card", push, and open a pull request whose body says "Part of #<T02 issue number>" (find the number with gh). Show me the link.

3. Card T04, art bake-off. Update main and create branch john/t04-art-bakeoff. We are choosing ONE art pack family for the whole game (fantasy and sci-fi, top-down):
   A = Kenney 1-Bit Pack: https://kenney-assets.itch.io/1-bit-pack
   B = Kenney Tiny Dungeon: https://kenney-assets.itch.io/tiny-dungeon
   Walk me through downloading each zip (itch.io: Download Now, then "No thanks, just take me to the downloads", then Download) and unzipping them into _bakeoff/a and _bakeoff/b (git ignores _bakeoff/). Then build _bakeoff/mock_a.tscn and _bakeoff/mock_b.tscn at 1920 x 1080, each showing: a floor, 4 cover blocks, one fantasy hero, one sci-fi hero (or the closest match), two projectiles, and a simple HUD (health bar, team scores, timer). In each mock, pressing P saves a full-size screenshot to docs/art-bakeoff/a.png or docs/art-bakeoff/b.png. Show me the plan and wait for "go". After I press F6 and P in both mocks, help me fill in the table in docs/art-bakeoff/README.md. When I say "ship it", commit only the docs/art-bakeoff/ folder and open the pull request with "Closes #<T04 issue number>".

Rules: only change files in _bakeoff/, docs/art-bakeoff/ and docs/team/john.md. Never push to main. End with a 3-line summary and my next card.
```

## What happens
1. Claude checks your setup and runs the smoke test.
2. It walks you through your first pull request (T02). Gabe merges it.
3. It builds two mock game screens, one per art pack, and saves a screenshot of each (T04). Post both screenshots in the family chat; the team picks one pack by Oct 17.

## If something goes wrong
- Hit your usage limit: come back later and type `Continue where we stopped.`
- Godot shows red errors: copy the red text into Claude Code.
- Anything else: screenshot it and send it to the family chat.

## After this
Your next cards: T10 (Join screen), T11 (profile), T16 (lobby and hero select), T17 (HUD), T26 (Thanksgiving logistics). Start each in a fresh session with `/build-card <issue number>`.
