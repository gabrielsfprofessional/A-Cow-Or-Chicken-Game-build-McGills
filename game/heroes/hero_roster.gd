class_name HeroRoster
extends Resource
## The heroes players can pick, in hero-select order. Owner: Gabe (game/heroes).
## Card T13. data/roster.tres is the one roster; John's T16 hero select reads it.
## Until T16 everyone plays the first hero.

## Every playable hero, in the order hero select shows them.
@export var heroes: Array[HeroData] = []


## The hero everyone plays until T16; null when the roster is empty.
func first() -> HeroData:
	return heroes[0] if not heroes.is_empty() else null


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
