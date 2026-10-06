# Gabe: Prompt 1 (bootstrap the repo)

**You go first.** Adam and John start after you post "repo is ready". Time: about 90 minutes.

## Before you paste
1. Do [docs/SETUP.md](../docs/SETUP.md) steps 2-5 and 8 (Git, GitHub Desktop, GitHub CLI with `gh auth login`, Godot 4.7.2 in `C:\Godot`, the Claude app).
2. Clone the empty repo with GitHub Desktop (SETUP step 6). An "empty repository" message is expected.
3. Extract the starter kit zip. Open the extracted folder, press **Ctrl+A** (this includes `.claude`, `.github`, `.gitignore`, `.gitattributes`), copy, and paste into `Documents\GitHub\A-Cow-Or-Chicken-Game-build-McGills`. `README.md` must sit directly in that folder.
4. Open Claude Code on that folder (SETUP step 8).
5. Have Adam's and John's GitHub usernames ready.

## Copy this into Claude Code
Hover over the box, click the copy icon in its top-right corner, paste into Claude Code, send.

```text
I'm Gabe: tech lead and Heroes & Combat owner for "A Cow or Chicken". I copied the starter kit into this empty clone of our GitHub repo. Read CLAUDE.md, docs/PROJECT_PLAN.md and docs/BACKLOG.md first. Work through the steps in order. Before any command that changes GitHub, show it to me and wait for my OK.

1. Verify. Run `git status` (the kit shows as new files), `gh auth status`, and `C:\Godot\Godot_v4.7.2-stable_win64_console.exe --version` (it must say 4.7.2). Then run the smoke test. If anything fails, stop and help me fix it.

2. First push. This is the only direct push to main, ever. Commit everything as "T01: starter kit (docs, prompts, Godot 4.7.2 skeleton)", push to origin main, then watch the "smoke" GitHub Action until it passes.

3. GitHub setup with gh:
   a. Create every label and milestone listed at the top of docs/BACKLOG.md, milestones with their due dates.
   b. Ask me for Adam's and John's GitHub usernames. Create one issue per card T01-T37: title "TNN: <Card>", body in the format of .github/ISSUE_TEMPLATE/feature-card.md filled from that row (Goal, Where, Depends on, Done when), the row's label, its milestone (by week) and its owner as assignee. T02 goes to Adam and John; "All" cards go to all three of us.
   c. Run `gh auth refresh -s project`, create a project named "A Cow or Chicken" owned by me, and add every issue. Tell me how to add "This week" and "Review" options to its Status field in the web UI.
   d. Invite Adam and John as collaborators with write access.
   e. Protect main: require a pull request (0 approvals, so I can merge my own), require the "smoke" status check, block force pushes and deletion.
   f. Close the T01 issue.

4. Card T03, home network check, on branch gabe/t03-network-check. I do the router and admin steps; you give exact instructions for: a CGNAT test (router WAN IP vs. public IP), an upload speed test (need 10 Mbps or more), forwarding UDP 7777 to this PC, and the admin PowerShell command for an inbound Windows Firewall rule on UDP 7777. Record yes/no answers and Mbps in docs/team/gabe.md, never my IP address. Ship it as a pull request that closes the T03 issue, then merge it once "smoke" is green.

5. Write the message I'll post in the family chat: the repo is ready, accept the GitHub invite, then follow README.md "Start here". Then stop. Next session I start T06 with /build-card T06.
```

## What happens
1. Claude checks your tools and runs the smoke test.
2. It pushes the kit to main and waits for the green "smoke" check on GitHub.
3. It builds the labels, milestones, 37 issues and the project board, invites Adam and John, and protects main.
4. It walks you through the T03 network check and ships it as your first pull request.
5. It drafts your "repo is ready" message.

## If something goes wrong
- Hit your usage limit: come back later and type `Continue where we stopped.`
- The "smoke" check fails on GitHub: paste the failing log into Claude Code.
- CGNAT confirmed (T03): tell Claude; the fallback is a free cloud VM for the server (PROJECT_PLAN section 9).

## After this
Your next cards: T06, T07, T08, T09, then T13, T14. Start each in a fresh session with `/build-card T<NN>`. Review and merge Adam's and John's pull requests on your three fixed review days.
