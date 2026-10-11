class_name ServerStats
extends Node
## The dedicated server's health line (card T09). Owner: Gabe (game/net).
##
## Every INTERVAL_SEC it prints:
##   [Stats] peers <n>, fps <n>, worst frame <ms> ms, memory <MB> MB, up <KB/s> KB/s, down <KB/s> KB/s
## - worst frame: the longest gap between two frames in that window.
## - memory: Godot's own count (OS.get_static_memory_usage()) in MiB. Release
##   exports report 0; tools/run_bots.ps1 shows what Windows sees.
## - up/down: ENet bytes sent and received, without IP/UDP headers. KB = 1000
##   bytes, so Mbps = KB/s x 0.008: Gate 2's 5 Mbps upload budget is 625 KB/s.
## The test world adds it on the server; T16's arena must add it too.

const INTERVAL_SEC: float = 10.0

var _window_start_usec: int = 0
var _last_frame_usec: int = 0
var _worst_frame_usec: int = 0


func _ready() -> void:
	_window_start_usec = Time.get_ticks_usec()
	_last_frame_usec = _window_start_usec
	_pop_traffic()  # Count only from here on.


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_worst_frame_usec = maxi(_worst_frame_usec, now - _last_frame_usec)
	_last_frame_usec = now
	var window_sec := (now - _window_start_usec) / 1000000.0
	if window_sec < INTERVAL_SEC:
		return
	var traffic := _pop_traffic()
	print("[Stats] peers %d, fps %d, worst frame %.1f ms, memory %.1f MB, up %.1f KB/s, down %.1f KB/s" % [
		_peer_count(), Engine.get_frames_per_second(), _worst_frame_usec / 1000.0,
		OS.get_static_memory_usage() / 1048576.0, traffic.x / window_sec / 1000.0, traffic.y / window_sec / 1000.0,
	])
	_window_start_usec = now
	_worst_frame_usec = 0


## The ENet peer while it is an active host, else null. On an inactive one,
## reading `host` or popping a statistic prints an ERROR, which would fail smoke.
func _active_enet() -> ENetMultiplayerPeer:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return null
	return enet


func _peer_count() -> int:
	return multiplayer.get_peers().size() if _active_enet() != null else 0


## Bytes (sent, received) since the last pop: ENet resets both on each pop.
func _pop_traffic() -> Vector2:
	var enet := _active_enet()
	if enet == null:
		return Vector2.ZERO
	return Vector2(enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA),
		enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
