class_name NetAddress
extends RefCounted
## What Net may say about a server address, in logs and to players. Owner: Gabe.
## Logs reach every player's user://logs, so nothing here returns the address itself.
## A pure class, so tests/net_address_test.gd can call it (--script can't name the Net autoload).

const THIS_PC: String = "this PC"
const LAN: String = "a LAN address"
const INTERNET: String = "an internet address"


## Which kind of address this is, in words safe to log. A name that isn't an IP is
## "an internet address": nothing here looks it up.
static func kind(address: String) -> String:
	var text: String = address.strip_edges().to_lower()
	if text in ["127.0.0.1", "::1", "localhost"]:
		return THIS_PC
	if not text.is_valid_ip_address():
		return INTERNET
	if ":" in text:
		return LAN if _is_lan_v6(text) else INTERNET
	return LAN if _is_lan_v4(text) else INTERNET


## Net's log line when a join starts.
static func join_line(address: String, port: int, version: String) -> String:
	return "joining %s on UDP %d as version %s" % [kind(address), port, version]


## The reason a player sees when the address can't even be used.
static func unusable_reason(error: int) -> String:
	return "Could not use that address (error %d). Check it and try again." % error


## The reason a player sees when no answer came in time.
static func timeout_reason(port: int, seconds: int) -> String:
	return "Could not reach the server on UDP %d within %d seconds. Check the address, and that the server is running." % [
		port, seconds,
	]


## The reason a player sees when the connection failed.
static func unreachable_reason(port: int) -> String:
	return "Could not reach the server on UDP %d. Check the address, and that the server is running." % port


## 10/8, 172.16/12, 192.168/16, 169.254/16.
static func _is_lan_v4(text: String) -> bool:
	var parts: PackedStringArray = text.split(".")
	var first: int = parts[0].to_int()
	var second: int = parts[1].to_int()
	if first == 10:
		return true
	if first == 172:
		return second >= 16 and second <= 31
	if first == 192:
		return second == 168
	return first == 169 and second == 254


## fc00::/7, fe80::/10.
static func _is_lan_v6(text: String) -> bool:
	var head: String = text.get_slice(":", 0)
	if head == "":
		return false
	var first: int = head.hex_to_int()
	return first & 0xfe00 == 0xfc00 or first & 0xffc0 == 0xfe80
