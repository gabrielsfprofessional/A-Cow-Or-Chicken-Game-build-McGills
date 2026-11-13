# game/weapons/data

Owner: Adam

One WeaponData .tres file per weapon: damage, fire rate, bullet speed, spread. Cards: T19, T27, A08.

## The weapons

Heroes have 100 health. Each hero plays its default weapon at Thanksgiving. A weapon's look follows
the hero's theme; its numbers don't (docs/PROJECT_PLAN.md, section 3).

| File | Job | Default for | Damage | Seconds between shots | Shot speed (px/s) | Reach (px) |
|---|---|---|---|---|---|---|
| sidearm.tres | Backup | Medic, and Bruiser until Spread | 20 | 0.3 | 900 | 900 |
| rifle.tres | All-round: hits harder and reaches farther, fires slower | Scout | 25 | 0.35 | 1400 | 1300 |
| rapid.tres | Close-range spray: fires fast, short reach | Mage | 10 | 0.12 | 1000 | 600 |

The files are the truth; update this table when a number changes. T27 tunes the numbers.
Spread (the Bruiser's close burst) and Rapid's spread_deg 5 come in Alpha with T19 part 2.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
