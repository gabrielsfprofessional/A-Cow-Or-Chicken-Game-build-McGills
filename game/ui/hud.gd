class_name Hud
extends Control
## The in-match display for your own hero (card T17, part 1). Owner: John (game/ui).
##
## It only shows what it is told: Overlay (or hud_preview.gd) calls set_health(),
## set_ability() and set_respawn(). It decides nothing and never takes a click, so
## left click still shoots. Sizes and colors are the @export values below.

## Text size at 1080p; the UI scaler (Settings.ui_scale) grows it.
@export_range(18, 64, 1, "suffix:px") var font_size: int = 28
@export var bar_size: Vector2 = Vector2(360.0, 32.0)
@export var bar_color: Color = Color(0.27, 0.65, 0.35)
@export var bar_low_color: Color = Color(0.94, 0.35, 0.35)
@export var bar_back_color: Color = Color(0.0, 0.0, 0.0, 0.55)
## Below this share of max health the bar turns bar_low_color.
@export_range(0.05, 0.9, 0.05) var low_health_share: float = 0.3
@export var ready_color: Color = Color(0.95, 0.95, 0.95)
@export var cooldown_color: Color = Color(0.7, 0.7, 0.7)
## How dim the Q box is while it cools down or you are eliminated.
@export_range(0.2, 1.0, 0.05) var dimmed_alpha: float = 0.55
## Team colors (T15: team 0 is Blue, team 1 is Orange). They color the score names,
## "You are on ..." and the winner banner only, never a hero.
@export var blue_color: Color = Color("#3B82F6")
@export var orange_color: Color = Color("#F97316")
@export var draw_color: Color = Color(0.95, 0.95, 0.95)
## Text size of the winner banner at 1080p.
@export_range(18, 96, 1, "suffix:px") var banner_font_size: int = 56

@onready var _health_bar: ProgressBar = $Corner/Stack/HealthRow/HealthBar
@onready var _health_text: Label = $Corner/Stack/HealthRow/HealthText
@onready var _q_box: PanelContainer = $Corner/Stack/QBox
@onready var _q_key: Label = $Corner/Stack/QBox/Row/Key
@onready var _q_name: Label = $Corner/Stack/QBox/Row/Name
@onready var _q_state: Label = $Corner/Stack/QBox/Row/State
@onready var _back_in: Label = $BackIn
@onready var _match_bar: VBoxContainer = $MatchBar
@onready var _blue_score: Label = $MatchBar/Row/BlueScore
@onready var _clock: Label = $MatchBar/Row/Clock
@onready var _orange_score: Label = $MatchBar/Row/OrangeScore
@onready var _my_team: Label = $MatchBar/MyTeam
@onready var _banner: Label = $Banner

## "No winner yet" for _winner (match_ended sends 0, 1 or -1 for a draw).
const NO_WINNER: int = -2
const DRAW: int = -1
const TEAM_NAMES: Array[String] = ["Blue", "Orange"]

var _fill: StyleBoxFlat = StyleBoxFlat.new()
## What Events last said about the match. Kept here, not in the world, so a value
## that arrives before the HUD is visible (the late-join replay) still shows.
var _teams: Dictionary = {}
var _scores: Array[int] = [0, 0]
var _clock_sec: int = -1
var _winner: int = NO_WINNER
var _has_match: bool = false
var _own_peer: int = 0


func _ready() -> void:
	for label: Label in [_health_text, _q_key, _q_name, _q_state, _back_in,
			_blue_score, _clock, _orange_score, _my_team]:
		label.add_theme_font_size_override(&"font_size", font_size)
	_banner.add_theme_font_size_override(&"font_size", banner_font_size)
	_blue_score.add_theme_color_override(&"font_color", blue_color)
	_orange_score.add_theme_color_override(&"font_color", orange_color)
	_health_bar.custom_minimum_size = bar_size
	_health_bar.add_theme_stylebox_override(&"fill", _fill)
	var back := StyleBoxFlat.new()
	back.bg_color = bar_back_color
	_health_bar.add_theme_stylebox_override(&"background", back)
	set_health(0, 1)
	set_ability("", 0.0, 0, 0)
	set_respawn(0.0)
	_refresh_match()


## Start listening to the match events. Overlay calls this once, right after it builds
## the Hud (not on a headless run), long before this client is ready, so the replay a
## late joiner gets is never missed. A second call does nothing.
func listen() -> void:
	if Events.match_started.is_connected(_on_match_started):
		return
	Events.match_started.connect(_on_match_started)
	Events.team_assigned.connect(_on_team_assigned)
	Events.team_score_changed.connect(_on_team_score_changed)
	Events.match_clock_changed.connect(_on_match_clock_changed)
	Events.match_ended.connect(_on_match_ended)


## Which peer is you, so "You are on ..." follows team_assigned for that peer only.
## Overlay calls this every frame; it only redraws when the id changes.
func set_own_peer(peer_id: int) -> void:
	if peer_id == _own_peer:
		return
	_own_peer = peer_id
	_refresh_match()


## Forget the match (you left it). Does nothing when there is nothing to forget.
func clear_match() -> void:
	if not _has_match and _teams.is_empty() and _winner == NO_WINNER and _own_peer == 0:
		return
	_teams.clear()
	_scores = [0, 0]
	_clock_sec = -1
	_winner = NO_WINNER
	_has_match = false
	_own_peer = 0
	_refresh_match()


func _on_match_started(_mode: StringName) -> void:
	_winner = NO_WINNER
	_has_match = true
	_refresh_match()


func _on_team_assigned(peer_id: int, team: int) -> void:
	if team < 0 or team >= TEAM_NAMES.size():
		return
	_teams[peer_id] = team
	_refresh_match()


func _on_team_score_changed(team: int, score: int) -> void:
	if team < 0 or team >= TEAM_NAMES.size():
		return
	_scores[team] = maxi(score, 0)
	_has_match = true
	_refresh_match()


func _on_match_clock_changed(seconds_left: int) -> void:
	_clock_sec = maxi(seconds_left, 0)
	_has_match = true
	_refresh_match()


func _on_match_ended(winning_team: int) -> void:
	_winner = winning_team if winning_team >= 0 and winning_team < TEAM_NAMES.size() else DRAW
	_has_match = true
	_refresh_match()


func _team_color(team: int) -> Color:
	return blue_color if team == 0 else orange_color


func _refresh_match() -> void:
	_match_bar.visible = _has_match
	_blue_score.text = score_text(0, _scores[0])
	_orange_score.text = score_text(1, _scores[1])
	_clock.text = clock_text(_clock_sec)
	var mine: int = int(_teams.get(_own_peer, -1))
	_my_team.visible = mine >= 0
	_my_team.text = my_team_text(mine)
	_my_team.add_theme_color_override(&"font_color", _team_color(mine))
	_banner.visible = _winner != NO_WINNER
	_banner.text = banner_text(_winner)
	_banner.add_theme_color_override(&"font_color", draw_color if _winner == DRAW else _team_color(_winner))


## Health bar and the "72 / 100" text.
func set_health(current: int, maximum: int) -> void:
	maximum = maxi(maximum, 1)
	current = clampi(current, 0, maximum)
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_text.text = health_text(current, maximum)
	_fill.bg_color = bar_low_color if float(current) / maximum < low_health_share else bar_color


## The Q box. An empty name hides it (a hero without an ability). `charges_total`
## above 1 shows "x2" or "x1" while a charge is ready.
func set_ability(display_name: String, ready_in_sec: float, charges_left: int, charges_total: int) -> void:
	_q_box.visible = display_name != ""
	_q_name.text = display_name
	_q_state.text = ability_text(ready_in_sec, charges_left, charges_total)
	var cooling := ready_in_sec > 0.0 and charges_left <= 0
	_q_state.add_theme_color_override(&"font_color", cooldown_color if cooling else ready_color)
	_q_box.modulate.a = dimmed_alpha if cooling else 1.0


## Seconds until you are back; 0 or less while you are alive.
func set_respawn(seconds_left: float) -> void:
	_back_in.visible = seconds_left > 0.0
	_back_in.text = respawn_text(seconds_left)
	if seconds_left > 0.0:
		_q_box.modulate.a = dimmed_alpha


static func health_text(current: int, maximum: int) -> String:
	return "%d / %d" % [current, maximum]


static func ability_text(ready_in_sec: float, charges_left: int, charges_total: int) -> String:
	if charges_left <= 0 and ready_in_sec > 0.0:
		return "%d" % ceili(ready_in_sec)
	if charges_total > 1:
		return "READY x%d" % charges_left
	return "READY"


static func respawn_text(seconds_left: float) -> String:
	return "Back in %d s" % ceili(seconds_left)


static func score_text(team: int, score: int) -> String:
	return "%s %d" % [TEAM_NAMES[clampi(team, 0, TEAM_NAMES.size() - 1)], score]


## Whole seconds as mm:ss (1200 is "20:00"); "--:--" before the first clock value.
static func clock_text(seconds_left: int) -> String:
	if seconds_left < 0:
		return "--:--"
	@warning_ignore("integer_division")
	return "%02d:%02d" % [seconds_left / 60, seconds_left % 60]


static func my_team_text(team: int) -> String:
	if team < 0 or team >= TEAM_NAMES.size():
		return ""
	return "You are on %s" % TEAM_NAMES[team]


## "Blue wins!", "Orange wins!" or "Draw" (-1); "" while no match has ended.
static func banner_text(winner: int) -> String:
	if winner == DRAW:
		return "Draw"
	if winner >= 0 and winner < TEAM_NAMES.size():
		return "%s wins!" % TEAM_NAMES[winner]
	return ""
