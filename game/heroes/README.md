# game/heroes

Owner: Gabe

Hero scenes, abilities and hero data files (data/*.tres). Cards: T08, T13, T14, T18, A07.

T08: `health.tscn` (Health: put it under anything on physics layer 2 to make it
hittable), `health_state.gd` (its rules) and `data/combat.tres` (max health,
respawn time).

Anything shootable must turn its collider off when its Health is eliminated
(NetHero does), or it stops shots like a wall. Health only emits signals, so
its parent does this. T20's dummies (Adam) need it too.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
