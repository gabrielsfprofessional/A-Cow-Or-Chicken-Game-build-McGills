class_name ReadyPeers
extends RefCounted
## Server: the peers that said client_ready, so relays never reach a peer whose
## world is not loaded yet (T06; card T39 adds recipients() for send_to_ready).
## Owner: Gabe (game/net). Pure, so tests can drive it without autoloads.

var _ready: Dictionary[int, bool] = {}


func add(peer_id: int) -> void:
	_ready[peer_id] = true


func remove(peer_id: int) -> void:
	_ready.erase(peer_id)


func has(peer_id: int) -> bool:
	return _ready.has(peer_id)


## The connected peers that are ready, sorted. A peer that left but wasn't
## removed yet is skipped, since it isn't in `connected`.
func recipients(connected: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	for peer_id: int in connected:
		if _ready.has(peer_id):
			out.append(peer_id)
	out.sort()
	return out
