extends Control
## Join screen: type a server address, press Join. Owner: John (game/ui).
## Join hands the address to Settings, then Net.play() opens the world and joins.
## If that fails, Net brings the player back here with the reason in Net.last_reason.

const MENU_SCENE: String = "res://game/ui/main_menu.tscn"

@onready var _address: LineEdit = $Center/Rows/AddressEdit
@onready var _message: Label = $Center/Rows/Message
@onready var _join: Button = $Center/Rows/JoinButton
@onready var _back: Button = $Center/Rows/BackButton

var _joining: bool = false


func _ready() -> void:
	_address.text = _starting_address()
	_address.text_changed.connect(_on_address_changed)
	_address.text_submitted.connect(_on_address_submitted)
	_join.pressed.connect(_start_join)
	_back.pressed.connect(_on_back_pressed)
	Net.join_failed.connect(_on_join_failed)
	_show_last_reason()
	_update_join_button()
	_address.grab_focus()
	_address.caret_column = _address.text.length()


## The address tried this session, else the last one that worked, else the server's.
func _starting_address() -> String:
	if Settings.last_tried != "":
		return Settings.last_tried
	if Settings.last_address != "":
		return Settings.last_address
	return Net.server_address()


## Shows the reason Net left behind, once.
func _show_last_reason() -> void:
	_message.text = Net.last_reason
	Net.last_reason = ""


func _on_address_changed(_text: String) -> void:
	_update_join_button()


func _on_address_submitted(_text: String) -> void:
	_start_join()


func _update_join_button() -> void:
	_join.disabled = _joining or _address.text.strip_edges() == ""


func _start_join() -> void:
	var address: String = _address.text.strip_edges()
	if _joining or address == "":
		return
	_joining = true
	_message.text = "Joining %s ..." % address
	_address.editable = false
	_back.disabled = true
	_update_join_button()
	Settings.begin_join(address)
	Net.play(address)


## Only reached when this screen is still up, for example when the world would not load.
func _on_join_failed(_reason: String) -> void:
	_joining = false
	_address.editable = true
	_back.disabled = false
	_show_last_reason()
	_update_join_button()
	_address.grab_focus()


func _on_back_pressed() -> void:
	if not _joining:
		get_tree().change_scene_to_file(MENU_SCENE)
