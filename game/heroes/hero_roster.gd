class_name HeroRoster
extends Resource
## The heroes players can pick, in hero-select order. Owner: Gabe (game/heroes).
## Cards T13, T18. data/roster.tres is the one roster; John's T16 hero select reads it.
## Until T16 the debug flag --hero=<file name> picks one (T18); the default is the first.

## Every playable hero, in the order hero select shows them.
@export var heroes: Array[HeroData] = []


## The default hero; null when the roster is empty.
func first() -> HeroData:
	return heroes[0] if not heroes.is_empty() else null


## The slot of the hero whose file is `<file_name>.tres` ("mage" gives 1), or -1 (T18).
func index_of(file_name: String) -> int:
	for i: int in heroes.size():
		if heroes[i] != null and heroes[i].resource_path.get_file().get_basename() == file_name:
			return i
	return -1


## The hero in slot `index`; null when there is no such slot or it is empty (T18).
func at(index: int) -> HeroData:
	return heroes[index] if index >= 0 and index < heroes.size() else null


## The roster's problems and each hero's, in plain words. Empty when the file is fine.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if heroes.is_empty():
		problems.append("heroes is empty; add at least one HeroData file")
	for i: int in heroes.size():
		var hero := heroes[i]
		if hero == null:
			problems.append("heroes[%d] is empty; pick a HeroData file such as bruiser.tres" % i)
			continue
		for problem: String in hero.validate():
			problems.append("heroes[%d] (%s): %s" % [i, DataCheck.file_name(hero), problem])
	return problems
