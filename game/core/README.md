# game/core

Owner: Gabe

Autoloads: Events (signal bus), Game (version, input map), Net (online play). Cards: T06, T07.

`data_check.gd`: `DataCheck`, the shared range check behind every data file's
`validate()` (heroes, weapons, later items). Card T13; moved here from
`game/heroes` in T14.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".
