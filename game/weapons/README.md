# game/weapons

Owner: Gabe (logic), Adam (data/)

Weapon logic lives here; weapon numbers live in data/. Cards: T08, T13, T19, A08.

T08: `weapon_data.gd` (WeaponData), `weapon.tscn` (aim, fire, the fire messages),
`shots.tscn` (server shots and client visuals), `shot_sim.gd` (server shot
stepping) and `shot_check.gd` (the server's fire check). See game/net/README.md,
"Combat (card T08)".

T13: `WeaponData.validate()` checks every number against its own
`@export_range` (see game/heroes/README.md, "Hero data"). A hero gets its
weapon from its HeroData's `default_weapon`; `weapon.tscn`'s sidearm is only
the default for a Weapon outside a hero.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
