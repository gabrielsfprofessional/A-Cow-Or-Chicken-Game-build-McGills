extends SceneTree
## Tests for NetAddress: what Net may say about a server address. Owner: Gabe.
## Run: godot --headless --path . --script res://tests/net_address_test.gd
## Exits 1 when any case fails. tools/smoke.ps1 and smoke.sh run it.

const NET_SOURCE: String = "res://game/core/net.gd"
const PORT: int = 7777
const VERSION: String = "0.0.1+net9"
## The only lines of net.gd that may use the address: they connect or ask for its kind.
const ALLOWED_USES: Array[String] = [
	"var _join_target",
	"_join_target = ",
	"_join_target == ",
	"create_client(_join_target,",
	"NetAddress.join_line(_join_target,",
]

var _failed: int = 0
var _count: int = 0


func _initialize() -> void:
	_kinds()
	_join_line_hides_the_address()
	_reasons_hide_the_address()
	_net_never_prints_the_address()
	print("net_address_test: %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 else 0)


func _kinds() -> void:
	for address: String in ["127.0.0.1", "::1", "localhost", "LocalHost", " 127.0.0.1 "]:
		_expect_kind(address, NetAddress.THIS_PC)
	for address: String in [
		"10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.20", "169.254.1.1",
		"fc00::1", "fd12:3456::1", "fe80::1", "febf::1",
	]:
		_expect_kind(address, NetAddress.LAN)
	for address: String in [
		"172.15.255.255", "172.32.0.1", "192.167.1.1", "169.253.1.1", "8.8.8.8",
		"fbff::1", "fec0::1", "2001:4860:4860::8888", "::ffff:10.0.0.1", "example.org", "", "10.0.0",
	]:
		_expect_kind(address, NetAddress.INTERNET)


func _join_line_hides_the_address() -> void:
	for address: String in ["127.0.0.1", "10.1.2.3", "8.8.8.8", "fe80::1", "example.org"]:
		var line: String = NetAddress.join_line(address, PORT, VERSION)
		_expect_true("join line hides %s: %s" % [address, line], not address in line)
		_expect_true("join line names its kind for %s" % address, NetAddress.kind(address) in line)
		_expect_true("join line names the version for %s" % address, VERSION in line)


func _reasons_hide_the_address() -> void:
	var reasons: Array[String] = [
		NetAddress.unusable_reason(ERR_CANT_CREATE),
		NetAddress.timeout_reason(PORT, 5),
		NetAddress.unreachable_reason(PORT),
	]
	for reason: String in reasons:
		_expect_true("a reason starts in plain words: %s" % reason, reason.begins_with("Could not "))
		_expect_true("a reason has no IP in it: %s" % reason, not _has_ip(reason))
	_expect_true("the timeout says how long", "within 5 seconds" in reasons[1])
	_expect_true("the plain failure doesn't", not "within" in reasons[2])


## join() and the reasons are Net's, and it can't be named here, so read its source:
## a line that puts the address in a log or a reason is one this list doesn't allow.
func _net_never_prints_the_address() -> void:
	var source: String = FileAccess.get_file_as_string(NET_SOURCE)
	_expect_true("net.gd can be read", source != "")
	var bad: int = 0
	for line: String in source.split("\n"):
		if "_join_target" in line and not _is_allowed(line):
			bad += 1
			printerr("  net.gd uses the address here: %s" % line.strip_edges())
	_expect_true("net.gd only connects with the address (%d other lines)" % bad, bad == 0)


func _is_allowed(line: String) -> bool:
	for allowed: String in ALLOWED_USES:
		if allowed in line:
			return true
	return false


func _has_ip(text: String) -> bool:
	var pattern: RegEx = RegEx.create_from_string("\\d+\\.\\d+\\.\\d+\\.\\d+")
	return pattern.search(text) != null


func _expect_kind(address: String, wanted: String) -> void:
	_expect_true("'%s' is %s" % [address, wanted], NetAddress.kind(address) == wanted)


func _expect_true(case_name: String, ok: bool) -> void:
	_count += 1
	if ok:
		print("  ok    %s" % case_name)
		return
	_failed += 1
	printerr("  FAIL  %s" % case_name)
