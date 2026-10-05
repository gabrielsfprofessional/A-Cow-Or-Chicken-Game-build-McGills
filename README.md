# A Cow or Chicken

A 2D top-down hero shooter, fantasy and sci-fi, for 5-16 family players aged 12-65.
Built with **Godot 4.7.2** and **Claude Code**.

| Milestone | Date |
| --- | --- |
| Arena mode at the Thanksgiving family playtest | Thu Nov 26, 2026 |
| v1: Battle Royale, unlocks, family leaderboard | Sat Feb 27, 2027 |

## Start here

**Gabe goes first. Adam and John start after Gabe posts "repo is ready".**

1. **Gabe:** follow [prompts/1-gabe.md](prompts/1-gabe.md). It pushes this starter kit, builds the task board and invites Adam and John.
2. **Adam and John:**
   1. Accept the GitHub invite email.
   2. Do [docs/SETUP.md](docs/SETUP.md), steps 1-8 (about 45 minutes, once).
   3. Open your Prompt 1, click the copy button on the gray box, paste it into Claude Code, send it.
      - Adam: [prompts/1-adam.md](prompts/1-adam.md)
      - John: [prompts/1-john.md](prompts/1-john.md)

> Do **not** use the green **Code > Download ZIP** button. A ZIP can't send your work back.
> Clone with GitHub Desktop ([docs/SETUP.md](docs/SETUP.md), step 6).

After Prompt 1, every task starts the same way: type `/build-card <issue number>` in Claude Code.
See [docs/WORKFLOW.md](docs/WORKFLOW.md).

## Who owns what

| Person | Role | Folders you may edit |
| --- | --- | --- |
| Gabe | Tech lead, Heroes & Combat | game/core, game/net, game/heroes, game/weapons (logic), server, tests, tools |
| Adam | Maps & Modes | game/maps, game/modes, game/items, game/weapons/data |
| John | Look, Sound & Players | game/ui, game/players, assets, audio |

## Documents

| File | What's in it |
| --- | --- |
| [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) | Decisions, game design, architecture, roadmap, risks |
| [docs/BACKLOG.md](docs/BACKLOG.md) | Every task with owner, week, dependencies and "done when" |
| [docs/SETUP.md](docs/SETUP.md) | Windows install steps, start to finish |
| [docs/WORKFLOW.md](docs/WORKFLOW.md) | How one task goes from card to game |
| [CLAUDE.md](CLAUDE.md) | The rules Claude Code follows in this repo |
| [CREDITS.md](CREDITS.md) | Every asset and its license |

## Five rules

1. Only edit your own folders.
2. One card = one branch = one pull request.
3. Only Gabe merges into main.
4. The smoke test must pass before you ship.
5. Never commit the server address, save files, or anything over 50 MB.
