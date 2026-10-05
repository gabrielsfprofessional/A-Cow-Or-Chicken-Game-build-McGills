---
name: build-card
description: Build one task card (a GitHub issue) for A Cow or Chicken from start to finish with the team workflow - fresh branch, plan, build, smoke test, test steps, pull request. Use whenever the user types /build-card with an issue number, or asks to start, do or work on a card, issue or task such as "T05".
---

# Build card $ARGUMENTS

Follow these steps in order. Use plain words: the user may not be a programmer.

1. **Read the card.** Run `gh issue view $ARGUMENTS`. If gh fails, ask the user to paste the card. Read CLAUDE.md if you haven't this session.
2. **Check ownership.** The card's assignee and "Where" folders must match the user. If not, stop and say who owns it.
3. **Fresh branch.** If there are uncommitted changes, ask what to do with them first. Then `git switch main`, `git pull`, `git switch -c <name>/t<NN>-<short-title>` (lowercase, hyphens).
4. **Plan.** List every file you will create or change and what the user will see in the game. Wait for "go".
5. **Build.** Stay inside the card's folders. Tunable numbers go in data files (.tres).
6. **Smoke test.** Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke.ps1`. Fix every failure before going on.
7. **Teach the test.** Give numbered steps, with exact keys and clicks, for each "Done when" check. Wait for the result. Fix and repeat until it passes.
8. **Ship**, only after the user says "ship it": commit as `T<NN>: <title>`, run `git push -u origin <branch>`, then `gh pr create --title "T<NN>: <title>" --body "Closes #$ARGUMENTS"` plus a "How to test" section. Show the pull request link.
9. **Wrap up** in three lines: what changed, how it was tested, the user's next card.
