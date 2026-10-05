# Workflow: from card to game

Every change follows the same 7 steps. Claude Code does the typing. You decide and you test.

## One card, start to finish
1. **Pick** your card on the Projects board. Cards are GitHub Issues titled like `T05: Arena graybox v0`.
2. **Start fresh:** in the Claude app's Code tab, start a new session on the game folder.
3. **Type** `/build-card 12` (12 = the issue number). Claude reads the card, updates main, creates your branch and shows a plan.
4. **Approve** the plan by typing `go`, or say what to change.
5. **Test** in Godot: **F5** runs the whole game, **F6** runs the scene you have open. Do the card's "Done when" checks. Tell Claude what's wrong in plain words; drag a screenshot into the chat.
6. **Ship:** type `ship it`. Claude runs the smoke test, commits, pushes and opens the pull request.
7. **Merge:** Gabe plays it and merges it. Then start your next card.

## Definition of Done
- Smoke test passes: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke.ps1`
- Works with the server and 2 game windows (from T06 on)
- Tunable numbers live in data files (.tres)
- Only the card's folders changed
- The pull request has a screenshot and "How to test" steps
- The "smoke" check on GitHub is green
- Gabe played it and merged it

## What to type in Claude Code

| You want to... | Type |
| --- | --- |
| Start a card | `/build-card 12` |
| Fix a bug card | `/fix-bug 31` |
| See the plan before any change | `Plan first. Don't edit anything yet.` |
| Undo the last change | `Undo your last change.` |
| Understand something | `Explain that in plain words.` |
| Finish a card and free up memory | `/clear` |
| Continue after a usage-limit break | `Continue where we stopped.` |
| Stop Claude right now | Click the stop button |

## Rules that prevent pain
- One card per session. Run `/clear` before the next card.
- Never edit a scene (.tscn) someone else is editing this week.
- Never commit server.cfg, saves/ or exports/ (git ignores them anyway).
- Merge conflict? Type: `Merge main into my branch and fix conflicts only in my folders.`
- Something feels wrong? Stop, take a screenshot, ask in the family chat.

## Names

| Thing | Format | Example |
| --- | --- | --- |
| Branch | `name/t<NN>-short-title` | `adam/t05-arena-graybox` |
| Commit and pull request title | `T<NN>: Title` | `T05: Arena graybox v0` |
| Pull request body | `Closes #<issue>` plus how to test | `Closes #5` |

## Claude usage limits (Pro, $20/month)
- Limits reset on a rolling 5-hour window plus a weekly cap. Chat and Claude Code share them. Check **Settings > Usage** on claude.ai.
- Use Sonnet for normal cards and Opus only for hard bugs.
- Blocked 3 or more days a week? Tell Gabe; we'll make your cards smaller.

## Reviews
Gabe reviews on three fixed days a week, so nobody waits more than 2 days for a merge.
