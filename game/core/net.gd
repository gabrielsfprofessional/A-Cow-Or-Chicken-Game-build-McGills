extends Node
## Online play (autoload "Net"). Owner: Gabe. Built in card T06.
## Design (docs/PROJECT_PLAN.md, "Architecture"):
## - A headless dedicated server is peer 1. Clients join over ENet on UDP 7777.
## - Each client moves its own hero; the server decides hits, damage and score.
## - The server address comes from res://server.cfg, which git ignores.
##   T29 adds server.cfg to the export filter so it ships inside the .exe.

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 16
const CONFIG_PATH: String = "res://server.cfg"


## Address players join when they click Play. Falls back to this PC.
func server_address() -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		return str(config.get_value("server", "address", "127.0.0.1"))
	return "127.0.0.1"
