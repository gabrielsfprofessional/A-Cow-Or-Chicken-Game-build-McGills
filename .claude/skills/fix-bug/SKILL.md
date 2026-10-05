---
name: fix-bug
description: Fix one bug issue for A Cow or Chicken with the team workflow - reproduce, find the cause, fix inside the owner's folders, smoke test, pull request. Use whenever the user types /fix-bug with an issue number, or asks to fix a reported bug, crash or glitch.
---

# Fix bug $ARGUMENTS

Follow these steps in order. Use plain words: the user may not be a programmer.

1. **Read the bug.** Run `gh issue view $ARGUMENTS` (or ask the user to paste it). Read CLAUDE.md if you haven't this session.
2. **Fresh branch.** `git switch main`, `git pull`, `git switch -c <name>/bug-$ARGUMENTS-<short-title>`.
3. **Reproduce.** Give exact steps to make the bug happen and ask the user to confirm it does. If it won't happen, ask for the build version and a screenshot.
4. **Find the cause** and explain it in one or two plain sentences. If the fix belongs in someone else's folder, stop and say whose.
5. **Fix.** Show the plan, wait for "go", make the fix, run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke.ps1`.
6. **Verify.** Give steps to confirm the bug is gone and nothing nearby broke.
7. **Ship**, only after "ship it": commit as `Fix #$ARGUMENTS: <title>`, push, then `gh pr create --title "Fix #$ARGUMENTS: <title>" --body "Closes #$ARGUMENTS"` plus "How to test".
8. **Wrap up** in three lines.
