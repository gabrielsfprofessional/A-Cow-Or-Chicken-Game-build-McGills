# Backlog

Every task is a card. Gabe turns each row below into a GitHub Issue titled `TNN: Card` (his Prompt 1, step 3). Work any card with `/build-card T<NN>`, using the card number in the first column. Issue numbers drift away from card numbers because pull requests take numbers too.

## Labels
`core` `net` `server` `heroes` `weapons` `maps` `modes` `items` `ui` `players` `art` `audio` `docs` `tests` `bug` `blocker`

## Milestones

| Milestone | Due | Holds |
| --- | --- | --- |
| M1 Foundation | 2026-10-17 | Weeks 1-2 |
| M2 Graybox | 2026-11-14 | Weeks 3-6 |
| M3 Thanksgiving | 2026-11-25 | Weeks 7-8 |
| M4 Alpha | 2027-01-16 | A01-A11 |
| M5 v1 | 2027-02-27 | B01-B07 |

Weeks: 1 = Oct 4-10 · 2 = Oct 11-17 · 3 = Oct 18-24 · 4 = Oct 25-31 · 5 = Nov 1-7 · 6 = Nov 8-14 · 7 = Nov 15-21 · 8 = Nov 22-25

## To Thanksgiving: Arena mode (T01-T38)

| # | Card | Owner | Week | Label | Depends on | Done when |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | Push the starter kit; labels, milestones, issues, board, branch protection, invites | Gabe | 1 | core | none | Adam and John cloned the repo and pressed F5 |
| T02 | Fill in your team card in docs/team/ (first pull request) | Adam, John | 1 | docs | T01 | Each has one merged pull request |
| T03 | Home network check: CGNAT test, upload speed, UDP 7777 forward, firewall rule | Gabe | 1 | net | none | Upload is 10 Mbps or more; port reachable from Adam's house |
| T04 | Art bake-off: one mock scene from each of two Kenney packs | John | 1 | art | T01 | Team picks one pack family |
| T05 | Arena graybox v0: walls, cover, 8 spawn points, fly camera | Adam | 1 | maps | T01 | Walkable map with no dead ends |
| T06 | Online foundation: headless server, join by address, one hero per connection, version check | Gabe | 1-2 | net | T01, T03 | Three run instances show 2 squares in each client; a version-mismatch client is refused; John joins from his house |
| T07 | Movement: own hero moves locally; others smoothed 100 ms behind | Gabe | 3 | net | T06, T11 | Smooth motion with 4 windows open; names show above heroes |
| T08 | First weapon: server-decided hits, health, death, 4 s respawn | Gabe | 3 | heroes | T07 | Two players can eliminate each other |
| T09 | Test bots: headless clients that join, wander and shoot; smoke test starts server + 2 bots | Gabe | 4 | tests | T08 | One PC runs 8 bots for 10 minutes, no disconnects |
| T10 | Main menu Play button and Join screen with LAN server list | John | 2 | ui | T06 | A second PC on the same Wi-Fi sees the server in the list and joins without typing |
| T11 | Profile: name, color, device token | John | 2 | players | none | First launch opens the profile screen; after Save and a restart the menu shows "Playing as <name>" |
| T12 | Team spawns and 2 s spawn protection | Adam | 3 | modes | T05, T08 | No spawn eliminations in a 10-minute bot test |
| T13 | HeroData and WeaponData resources; all numbers in .tres files | Gabe | 3 | heroes | T08 | Changing a number in the Inspector changes the game |
| T14 | Hero 1 (Fantasy Bruiser) with Shield Charge | Gabe | 3 | heroes | T13 | Ability works online with its cooldown |
| T15 | Arena rules: 2 teams, auto-balance, score limit, 20-minute cap | Adam | 3 | modes | T12 | A full match ends and declares a winner |
| T16 | Lobby and hero select | John | 3 | ui | T11, T13 | 4 players pick heroes and start a match |
| T17 | HUD: health, Q cooldown, team scores, timer | John | 3 | ui | T13 | All values update live online |
| T18 | Heroes 2-4 with their Q abilities | Gabe | 4 | heroes | T14 | All 4 heroes playable online |
| T19 | Six base weapons as data files | Adam | 4 | weapons | T13 | All 6 usable in the practice range |
| T20 | Practice range with target dummies | Adam | 4 | maps | T08 | Dummies show damage numbers |
| T21 | Server profile store: JSON saves, schema version, safe writes, nightly backup | Gabe | 4 | server | T11 | Pulling the plug mid-match loses no saved profile |
| T22 | Stats recording: matches, wins, eliminations, damage, hero | Gabe | 4 | server | T15, T21 | Stats correct after 3 test matches |
| T23 | Arena map v1, sized for 8-16 players | Adam | 5 | maps | T04, T15 | 16 bots play without traffic jams |
| T24 | Results screen | John | 5 | ui | T22 | Shows every player's match stats |
| T25 | Hit feedback: flash, damage numbers, hit and elimination sounds | John | 5 | art | T08 | Every hit is visible and audible |
| T26 | Thanksgiving logistics: location, Wi-Fi, laptop list | John | 5 | docs | none | At least 10 working laptops named |
| T27 | Balance pass 1 (data only) | Adam | 5 | weapons | T18, T19 | No hero or weapon wins every bot test |
| T28 | Family leaderboard screen | John | 6 | ui | T22 | Top 10 by wins and by eliminations |
| T29 | Release pipeline: client .exe, server build, version bump, server.cfg in export, Godot license in credits, Drive upload, install guide | Gabe | 6 | core | T06 | A non-builder installs and joins in 5 minutes |
| T30 | Internal 8-player playtest and bug bash | All | 6 | tests | T23-T29 | Gate 2 passed |
| T31 | Art pass: heroes, weapons, tiles, projectiles | John | 7 | art | T04, T18 | No placeholder art left in Arena |
| T32 | Sound pass: weapons, abilities, UI, one music loop | John | 7 | audio | T18 | Every action has a sound |
| T33 | Motion polish: walk bob, recoil, hit squash, elimination puff (code-driven, no frame animation) | John | 7 | art | T31 | Heroes feel alive |
| T34 | Map dressing and readability: team colors, clear cover | Adam | 7 | maps | T31 | Testers spot cover at a glance |
| T35 | Dress rehearsal, Sat Nov 21, at the Thanksgiving house | All | 7 | tests | T29 | 8+ laptops play 3 full matches on that Wi-Fi |
| T36 | Rehearsal fixes; build freeze Tue Nov 24; copies on Drive and 2 USB sticks | Gabe | 8 | core | T35 | Final build installed on every laptop |
| T37 | Printed quick-start card: install, controls, joining | John | 8 | docs | T29 | A first-timer joins without help |
| T38 | Settings screen: volume, UI scale, window mode, test sound | John | 3 | ui | T11 | Every setting survives a restart; the test sound follows the SFX and Master sliders; no text is cut off at 150% in a 1280x720 window |

## Gates

| Gate | Date | Pass when | If it fails |
| --- | --- | --- | --- |
| Gate 1 | Sat Oct 17 (after T06) | T06 merged; John and Adam join Gabe's server from their own houses; art pack picked | Fix hosting before anything else |
| Gate 2 | Sat Nov 14 (T30) | An 8-player Arena match with plain art is fun and has no crash bugs | Change the rules before adding art, or switch to Plan B |
| Gate 3 | Sat Jan 16 | Every v1 feature works end to end | Only fixes and balance after this date |

## Alpha: Battle Royale, ultimates, unlocks (Nov 27 - Jan 16)

Split into cards at the first sync after Thanksgiving, using what the playtest taught.

| # | Feature | Owner | Target | Label | Done when |
| --- | --- | --- | --- | --- | --- |
| A01 | Battle Royale map, about 8 x 8 screens, with buildings for loot | Adam | Dec 5 | maps | 16 bots spread out with no dead zones |
| A02 | Shrinking zone: 5 closes over about 16 minutes, damage outside, start size scales with player count | Adam | Dec 12 | modes | Matches with 6 and with 16 bots both end in 15-20 minutes |
| A03 | Loot: spawn points, 3 rarities, 2 weapon slots, shields, health | Adam (spawns), Gabe (inventory) | Dec 12 | items | Every player finds a full kit in about 2 minutes |
| A04 | Squads of 1-4 with knockdown and revive | Gabe | Dec 19 | heroes | Teammates revive in 5 s; enemies can finish knocked players |
| A05 | Redeploy until the second zone close; spectate teammates | Adam (rules), John (camera, UI) | Dec 19 | modes | Early deaths are back in within 15 s |
| A06 | Christmas family playtest of the Battle Royale graybox (optional) | All | Dec 26 | tests | Family plays 2 Battle Royale matches |
| A07 | Ultimates (F) for all 4 heroes | Gabe | Jan 9 | heroes | Each charges in about 90 s and works online |
| A08 | Six weapon sidegrades as data files | Adam | Jan 9 | weapons | Each tested against its base weapon in the range |
| A09 | XP, levels 1-30, unlock track; Thanksgiving stats converted to XP | Gabe (server), John (UI) | Jan 9 | players | Level-ups show after matches and survive restarts |
| A10 | 24 cosmetics: hats, colors, trails | John | Jan 16 | players | Equipped cosmetics are visible to everyone online |
| A11 | Battle Royale HUD: minimap, zone timer, squad health, kill feed | John | Jan 16 | ui | Readable at a glance at 1080p |

## Beta: make it solid (Jan 17 - Feb 27)

| # | Work | Owner | Target | Label | Done when |
| --- | --- | --- | --- | --- | --- |
| B01 | Three balance passes from saved match stats (data only) | Adam, Gabe | Jan 23, Feb 6, Feb 20 | weapons | No hero or weapon dominates the stats |
| B02 | Weekly bug bash; crashes and disconnects first | All | Weekly | bug | Zero open crash bugs at launch |
| B03 | Performance on the oldest family laptop and on the server at 16 players | Gabe | Jan 30 | core | The budgets in PROJECT_PLAN section 4 are met |
| B04 | Onboarding: practice range tips, controls screen, first-match hints | John | Feb 6 | ui | A new player learns the basics in 2 minutes |
| B05 | Update flow: version-mismatch message, Drive link, install guide v2 | Gabe, John | Feb 13 | core | A family member updates without help |
| B06 | Save backup and restore drill | Gabe | Feb 13 | server | A restored backup brings back every profile |
| B07 | Launch night prep: laptop check, server check, printed controls | John | Feb 26 | docs | Checklist done the day before |

## After v1 (the Later list, no fixed order)
Controller support, a Mac build, computer bots, MOBA-lite mode, co-op dungeon mode, a second map, more heroes.
