class_name MovementData
extends Resource
## Movement numbers a non-coder may tune. Owner: Gabe (game/net). Card T07.
## Lives here until T13 moves speed into HeroData.

## How fast a hero walks, in pixels per second. The server checks moves against it.
@export_range(50.0, 1000.0, 10.0, "suffix:px/s") var move_speed: float = 300.0
