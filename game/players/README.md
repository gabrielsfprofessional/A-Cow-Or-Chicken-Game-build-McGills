# game/players

Owner: John

Profiles (name, color), cosmetics, unlock track data. Cards: T11, A09, A10.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

## Profile (T11)

- `profile.gd` (`Profile`): `exists()`, `load_or_default()`, `save()`, `newer_version_found()`, `name_problem()`.
  File: `user://profile.json`, with `.tmp`, `.bak` and `.bad-<unix time>` beside it. Never delete or edit these by hand.
- `data/profile_colors.tres` (`ProfileColors`): the 8 swatches and the rules they must pass. `validate()` names any bad swatch.
- `profile_screen.tscn`: name box, swatches, preview, Save and Back.
- The profile color is for menus only, never for a hero or a name in a match.
