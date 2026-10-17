# game/net

Owner: Gabe

Connection, syncing heroes, LAN discovery, headless test bots. Cards: T06, T07, T09.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

## What is here

| File | What it is |
| --- | --- |
| `test_world.tscn` / `test_world.gd` | Temporary proving ground from T06-T09: one hero per player, a border wall and two inner walls, the Shots node, `bot_area()` for test bots, and `ServerStats` on the server. T16 replaces it with the real arena. |
| `hero_input.gd` | `HeroInput` (T09): the owner's move, aim and fire. NetHero and Weapon read only this. Reads the keyboard and mouse. |
| `bot_brain.gd` | `BotBrain` (T09): the `HeroInput` of a test bot. See "Test bots (card T09)". |
| `bot_rules.gd` | `BotRules` (T09): a test bot's decisions. Pure, tested by `tests/bot_rules_test.gd`. |
| `server_stats.gd` | `ServerStats` (T09): the server's `[Stats]` line every 10 s. |
| `move_check.gd` | `MoveCheck`: the server's check on each movement update. Pure, tested by `tests/move_check_test.gd`. |
| `remote_timeline.gd` | `RemoteTimeline`: plays other players' heroes back 100 ms behind. Pure, tested by `tests/remote_timeline_test.gd`. |
| `delay_queue.gd` | `DelayQueue`: fakes a slow network for `--sim-lag` / `--sim-jitter`. Tested by `tests/delay_queue_test.gd`. |
| (no data here) | Since T13 every hero number is in its HeroData (`game/heroes/data/*.tres`); the net code keeps only network plumbing and check tolerances as constants. See "Where the numbers live (card T13)". |

Combat (T08) lives next door: `game/weapons/` (Weapon, Shots, ShotSim, ShotCheck, WeaponData) and `game/heroes/` (NetHero, Health, HealthState, CombatData; NetHero moved there from here in T14). See "Combat (card T08)" below.

The connection code itself lives in `game/core/net.gd` (autoload `Net`), because
every folder needs it.

## The Net API (card T06)

Built for the Join screen in T10. Call these on the `Net` autoload from anywhere.

### Methods

| Call | What it does |
| --- | --- |
| `Net.host() -> Error` | Hosts the game on UDP 7777 for up to 16 players and loads the test world. The dedicated server calls this itself; nothing else needs to. Returns `OK`, or an ENet error if the port is taken. |
| `Net.join(address: String) -> Error` | Connects to `address` on UDP 7777. An empty string means `Net.server_address()`. Returns straight away: the answer arrives as `joined` or `join_failed`, always within 5 seconds. |
| `Net.leave() -> void` | Hangs up. Emits `left("")` and does **not** change the scene, so the caller decides where to go next. Does nothing when already offline. |

Also useful: `Net.server_address()` (address from the git-ignored `server.cfg`,
falling back to `127.0.0.1`), `Net.version()` (the version sent in the
handshake), and `Net.state` (`Net.State.OFFLINE`, `CONNECTING`, `CLIENT` or
`SERVER`) for deciding what a screen should show.

### Signals

| Signal | When it fires |
| --- | --- |
| `joined()` | This client is in the game. `multiplayer.get_unique_id()` is its peer id. |
| `join_failed(reason: String)` | The client never got in. `reason` is one plain sentence to show the player. |
| `left(reason: String)` | The client is out of the game. `reason` is `""` when the player left on purpose through `Net.leave()`, and says what went wrong otherwise (for example a lost server). |

A screen should connect to all three. Each one fires at most once per attempt,
and `join()` always ends in exactly one of `joined` or `join_failed`.

Reasons players can see today, all written for a 12-year-old:

- `Could not reach the server at <address> on UDP 7777 within 5 seconds. Is the server running?`
- `Update the game from the Drive folder (server v0.0.1+net3, you v0.0.1+net2)` (an older build)
- `The server refused the connection. It may be full, or running a different version.`
- `Lost connection to the server. It may have been closed.`

Until T10 lands, `Net` shows the reason with `OS.alert` and goes back to the main
menu by itself. **T10 should stop that**: once the Join screen listens to these
signals and shows the reason, drop the `_return_to_menu` call from `game/core/net.gd`.

## Running it

Nobody needs to type any of this. Double-click the launchers in `tools/`:

| Double-click | What happens |
| --- | --- |
| `tools/run_server.bat` | Starts the server on this PC. A black window opens and says `server up`. Leave it open while everyone plays; close it to stop the server. |
| `tools/join_game.bat` | Asks `Server address (Enter = this PC)`, then `Hero: bruiser, mage, scout or medic (Enter = bruiser)` (T18, until T16's hero select), then opens the game and joins. Enter alone means `127.0.0.1` and the Bruiser. You can also pass both: `join_game.bat 127.0.0.1 mage`. |
| `tools/run_bots.bat` | Load test (T09): 8 test bots join the server on this PC for 10 minutes. Bot n plays hero (n-1) mod 4: bruiser, mage, scout, medic, bruiser... (T18). Start `run_server.bat` first. See "Test bots (card T09)". |

`run_server.bat` uses the console build at `C:\Godot`, or the `GODOT` environment
variable when it is set. Both launchers run from the repo root no matter where
they are started from.

The same thing by hand, for a terminal:

    C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --server
    C:\Godot\Godot_v4.7.2-stable_win64.exe --path . -- --join=127.0.0.1

`-- --join` with no address uses `Net.server_address()`. In the editor use
**Debug > Customize Run Instances** and put the same arguments after `--`.

The first time Godot hosts, Windows asks to allow it through the firewall. Click
**Allow access**; Cancel writes a block rule that beats the UDP 7777 rule.

## The version check

The handshake sends `"<version>+net<NET_PROTOCOL>"`, for example `0.0.1+net3`:
the game version (`application/config/version` in `project.godot`) plus the wire
format number `NET_PROTOCOL` in `game/core/net.gd`. It rides along inside the
ENet connect handshake, using `SceneMultiplayer`'s `auth_callback`, `send_auth`
and `complete_auth`. Both sides send theirs, so either side can name both in the
message. A mismatch is refused before the peer counts as connected: the client
shows `Update the game from the Drive folder (server vX, you vY)` and the server
logs `refused peer <id>: version mismatch`.

**NET_PROTOCOL** is 1 for T06 (which sent a bare version), 2 for T07, 3 for T08
4 from T14 (the ability and knockback RPCs), 5 from T18 (`client_ready`'s hero index, the spawn data, the ability answers' charge times and `receive_heal`) and 6 from the week-3 seams (the spawn position in the spawn data). Bump it in the same pull request as any change to an RPC, its arguments, its channel or
the channel count. A build with a different wire format is then refused by name
instead of failing later with channel or RPC errors.

To test it without building two versions, a **debug build** accepts:

    C:\Godot\Godot_v4.7.2-stable_win64.exe --path . -- --join=127.0.0.1 --version-override=0.0.0

A release build ignores `--version-override` completely (`Net.version_override()`
returns `""` unless `OS.is_debug_build()`), so it cannot be used to sneak a
mismatched build into a family game.

## How the test world fills up

1. A client loads `test_world.tscn` **before** it connects, so the server's
   spawns have somewhere to land.
2. When the handshake finishes, the client sends `client_ready(hero_index)` to
   the server (T18): its roster slot, from `--hero=<file name>` until T16's hero
   select sends it. The server turns a slot with no hero into 0 and logs
   `[TestWorld] peer <id> asked for hero <n>; there is none, so it plays <first>`.
3. Only then does the server spawn that client's hero through the
   `HeroSpawner` (`MultiplayerSpawner`) with spawn data `[peer_id, hero_index,
   spawn_position]` (the position since the week-3 seams: the server's
   `MatchRules` picks it, NET_PROTOCOL 6; spawn data without it falls back to the
   T06 ring), so every peer, a late joiner included, builds the same hero: a `NetHero`
   under `Heroes`, named with the peer id, labelled `Player <id>  <hero>  <hp>`,
   with multiplayer authority set to that peer.
4. When a peer disconnects, the server frees its hero and the spawner takes the
   hero off every client.
5. The server only relays movement to peers that have sent `client_ready`.

## Movement (card T07)

- **Your own hero** moves the instant you press a key: a `CharacterBody2D` in
  floating mode, moved every physics tick with `Input.get_vector` on the
  `move_*` actions, at its HeroData's `move_speed`. It never waits on the server.
- Physics layer 1 is `world` (walls, Adam's blocks), layer 2 is `heroes`.
  Heroes sit on layer 2 and collide only with layer 1, so they pass through
  each other. The collider is a 40 px circle, so heroes slide round corners.
- **20 times a second** (every `physics_ticks_per_second / 20` physics ticks,
  never a Timer) the owner sends `(sequence, position)`. Sequence 1 is the
  first send after spawning, so `sequence x 50 ms` is exactly how much movement
  has been simulated.
- **The server** checks each update with `MoveCheck` and keeps the result: that
  copy is what T08 hit-tests. Accepted updates are relayed to everyone else.
- **Everyone else** plays the hero back 100 ms behind with `RemoteTimeline`,
  sampled every physics tick. Physics interpolation (Project Settings > Physics
  > Common) makes that smooth on 120/144 Hz screens.

### Messages

All three live on `NetHero` (`Heroes/<peer id>`, the same path on every peer).
Since T08 each carries the hero's life number first (see "Life numbers" below).

| RPC | Direction | Mode | Transfer | Channel | Payload |
| --- | --- | --- | --- | --- | --- |
| `submit_move` | owner -> server (`rpc_id(1)`) | `authority` + server checks `get_remote_sender_id()` is the owner | `unreliable_ordered` | `Net.MOVE_CHANNEL` (1) | `life: int, sequence: int, position: Vector2` |
| `relay_move` | server -> each ready peer except the owner (`rpc_id`) | `any_peer`, ignored unless the sender is 1 | `unreliable_ordered` | `Net.MOVE_CHANNEL` (1) | `life: int, sequence: int, position: Vector2` |
| `snap_back` | server -> owner only (`rpc_id`) | `any_peer`, ignored unless the sender is 1 | `reliable` | 0 | `life: int, sequence: int, position: Vector2` (the server's last good position) |

Movement has its own ENet channel so lost or late moves never hold up reliable
traffic. `Net.CHANNEL_COUNT` (1) goes to `create_client` only: it sets the
channels on each connection, and the server host already allows ENet's maximum.
`create_server` gets no channel count because Godot 4.7.2 passes that number as
ENet's incoming bandwidth (`max_channels + SYSCH_MAX`, about 3 bytes/s). Clients
then throttle their unreliable moves to 1/32 for a few seconds after joining.
`snap_back` stays on channel 0 so channel 1 only ever carries unreliable-ordered
packets.

### ENet throttle

ENet has its own congestion control: when a round trip comes back slower than
usual it drops a share of each peer's unreliable packets, and creeps back up
over several seconds. A round-trip spike while connecting (a server still
starting up, a busy laptop) used to cost 1-41 moves and made remote heroes
stutter. A player sends about 600 B/s, far too little to congest anything, so
that throttle only ever hurt us. `Net` calls
`throttle_configure(5000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)` on every
connection: the server for each peer in `_on_peer_connected`, the client for
peer 1 in `_on_connected_to_server`. Deceleration 0 means ENet never throttles
down; acceleration 32 (full scale) means a dip from before the call recovers on
the next steady ack. The constants are `Net.THROTTLE_INTERVAL_MSEC`,
`THROTTLE_ACCELERATION` and `THROTTLE_DECELERATION`. ENet also passes the
setting to the other end in its own protocol, so it is not a change to our wire
format and did not bump `NET_PROTOCOL`.

### The server's check (MoveCheck)

In order, the first failure wins:

1. Not from the hero's owner: dropped.
2. Sequence not newer than the last one: dropped.
3. NaN or INF in the position, or a coordinate beyond +/-100000 px: rejected.
4. **Time budget:** each hero has up to 1 s of movement time. It starts full,
   refills at 1.1x real time, and each accepted update spends its sequence gap
   x 50 ms. An update that would overspend is rejected (this also stops a huge
   sequence jump). A player who lags as they join is fine: the budget is full.
5. Moved further than speed (the HeroData's `move_speed`) x 1.25 x (sequence gap x 50 ms),
   plus any forced-motion grant still open: rejected.

**Grants (T14):** before the server tells anyone about a dash or a knockback,
it calls `MoveCheck.grant(extra_px, until_sec, now_sec)` with the motion's
distance, open for its duration plus `NetHero.FORCED_MOTION_GRACE_SEC` (1 s).
A move beyond walking draws its excess from the grant (`drew_grant`), grants
add up, the later expiry wins, and `reset()` (respawn) clears them.

On a reject the server keeps the last good position, advances the last
sequence, sends the owner a `snap_back` (at most every 0.5 s while rejects
keep coming, so one bad move cannot cause a stream of them), and logs
`[Move] peer <id>: rejected ...` at most once a second per hero.

### Remote heroes (RemoteTimeline)

Each update's place on the sender's timeline is `sequence x 50 ms`. A smoothed
offset (about 1 s) maps that onto the local clock, and playback runs 100 ms
behind it. Playback never goes backward and never runs more than 10% fast or
slow. Out of data, it carries on along the last velocity for at most 100 ms,
then holds (an "underrun"). A jump of more than 200 px clears the buffer and snaps.

The status line under the title shows `P<id> buf <ms> ur <n>` for each remote
hero: how far ahead its buffer reaches, and its underrun count. **Smooth means
`ur` stays 0 for 60 s at `--sim-lag=150 --sim-jitter=50`.** `[Remote]` lines
also report underruns, at most once a second per hero; `[Move]` lines only ever
mean a server reject.

Constants (network plumbing, not .tres): `NetHero.SEND_RATE`,
`RemoteTimeline.DELAY_SEC`, `MAX_EXTRAPOLATE_SEC`, `SNAP_DISTANCE`,
`MoveCheck.SPEED_TOLERANCE`, `BUDGET_MAX_SEC`, `BUDGET_REFILL_RATE`,
`Net.MOVE_CHANNEL`.

### Debug flags (debug builds only)

Put these after `--` in **Debug > Customize Run Instances** (one row per
window). A release build ignores them. The status line lists the active ones.

| Flag | What it does |
| --- | --- |
| `--sim-lag=<ms>` | Delays this client's movement messages by `<ms>`, both ways. |
| `--sim-jitter=<ms>` | Adds a random 0 to `<ms>` on top. Messages never overtake each other. With either flag on, joining prints one line, `[Net] sim lag 100 ms, jitter 20 ms`, so the log proves it was on. |
| `--speed-cheat=<x>` | Multiplies this client's own speed. 2 gets it snapped back. |
| `--fire-cheat=<x>` | Multiplies this client's fire rate (T08, parsed in `game/weapons/weapon.gd`). 2 gets extra shots refused. |
| `--version-override=<v>` | Pretends to be version `<v>` (see above). |
| `--bot=<seed>` | Makes this client a test bot (T09): a `BotBrain` drives its hero. Use with `--headless`, `--join=<address>` and `--quit-after-sec`. See "Test bots (card T09)". |
| `--hero=<name>` | Plays the roster hero whose file is `<name>.tres`: `bruiser` (the default), `mage`, `scout` or `medic` (T18, until T16's hero select). An unknown name plays the first hero and prints a `[TestWorld]` line. Bots take it too. |
| `--quit-after-sec=<n>` | Ends the run after n seconds with exit code 0 or 1 (T09, `game/core/game.gd`). Works for the server too. See "Test bots (card T09)". |

The fake lag delays movement messages and outgoing fire (T08) only, not the
handshake, spawns or incoming combat messages. `run_server.bat` and
`join_game.bat` pass none of these but `--hero`; `run_bots` passes `--bot`,
`--hero` and `--quit-after-sec`.

## Combat (card T08)

Heroes shoot and eliminate each other; the server decides every hit.

- **Weapon** (`game/weapons/weapon.gd`, child `Weapon` of each hero): the owner
  aims at the mouse and, while fire (left click) is held, fires every
  `fire_interval_sec` of its WeaponData (the HeroData's `default_weapon`), counted on physics
  ticks. The owner draws its own shot at once. Remote barrels turn to each
  accepted shot's direction; aim itself is not sent.
- **Server shots** (`ShotSim`, run by the `Shots` node in the test world):
  each accepted shot starts at the server's own copy of the shooter's center
  (never a client-sent origin). Every physics tick it first checks what it
  overlaps (`intersect_shape`, zero motion), then sweeps the tick's motion
  (`cast_motion`) against layers 1 and 2 with the shooter excluded. Godot's
  `cast_motion` ignores anything the shape starts inside, so the overlap check
  is what catches a hero who stepped onto a shot. A wall stops it, a body with a
  live `Health` child takes damage, `range_px` expires it. A shot that would
  start inside a wall is never started or sent.
- **Health** (`game/heroes/health.gd`, child `Health`): server-only damage,
  floor at 0, eliminated exactly once, mirrored on clients. It only emits
  signals; `NetHero` hides the hero, turns its collider off (at once, not
  deferred), ignores its moves and fire, and respawns it after `respawn_sec`
  (`game/heroes/data/combat.tres`) at `respawn_point(peer_id)` (the T06 ring).
  Health starts at the HeroData's `max_health`.
- **Shot visuals** (`Shots` on clients): `origin + direction x speed x age`,
  drawn below the heroes, ending at the first wall, at `range_px`, or at the
  server's hit position from `receive_damage` (it flies there and stops, or
  goes at once if already past).

### Life numbers

Each hero has a `life`, 0 at spawn and +1 on every respawn. `submit_move`,
`relay_move`, `snap_back` and `fire` carry the life they were sent in, and a
message from another life is dropped silently (not a reject, not logged). So
moves from before a death never teleport anyone or log `[Move]`. While
eliminated, the owner sends nothing and its move sequence stands still (it never
restarts). On respawn the server calls `MoveCheck.reset(spawn, now)` (full
budget, last sequence kept) and every client snaps the hero with
`RemoteTimeline.reset(spawn)`. Clients don't sample an eliminated remote hero,
so a death doesn't add an underrun, unless a resent elimination message lets
playback run dry just before the hero vanishes.

### Combat messages

Every combat message is `reliable` on channel 0. Server-to-client messages go
only to peers that have said `client_ready`.

| RPC | On | Direction | Mode | Transfer | Channel | Payload |
| --- | --- | --- | --- | --- | --- | --- |
| `fire` | `Weapon` | owner -> server | `authority` + `ShotCheck` checks the sender is the owner | `reliable` | 0 | `life: int, shot_id: int, direction: Vector2` |
| `receive_shot` | `Weapon` | server -> each ready peer except the shooter | `any_peer`, ignored unless the sender is 1 | `reliable` | 0 | `shot_id: int, origin: Vector2, direction: Vector2` |
| `receive_damage` | `NetHero` (victim) | server -> every ready peer | `any_peer`, sender 1 | `reliable` | 0 | `attacker: int, shot_id: int, amount: int, health_after: int, hit_position: Vector2` |
| `receive_heal` | `NetHero` (healed hero) | server -> every ready peer | `any_peer`, sender 1 | `reliable` | 0 | `healer: int, amount: int, health_after: int` (T18) |
| `receive_elimination` | `NetHero` (victim) | server -> every ready peer | `any_peer`, sender 1 | `reliable` | 0 | `attacker: int` |
| `receive_respawn` | `NetHero` | server -> every ready peer | `any_peer`, sender 1 | `reliable` | 0 | `position: Vector2, life: int` |
| `receive_combat_state` | `NetHero` | server -> a peer that just joined | `any_peer`, sender 1 | `reliable` | 0 | `life: int, health: int, eliminated: bool, respawn_in: float` |
| `request_ability` | `Ability` (base of each ability) | owner -> server | `authority` + `AbilityCheck` checks the sender is the owner | `reliable` | 0 | `life: int, direction: Vector2` |
| `receive_ability_used` | `Ability` (base of each ability) | server -> every ready peer (the owner's effect starts) | `any_peer`, sender 1 | `reliable` | 0 | `life: int, direction: Vector2, charge_ready_in: PackedFloat64Array` (T18: each charge's seconds to ready, soonest first) |
| `receive_ability_refused` | `Ability` (base of each ability) | server -> owner | `any_peer`, sender 1 | `reliable` | 0 | `charge_ready_in: PackedFloat64Array` |
| `receive_knockback` | `NetHero` (victim) | server -> every ready peer (the victim's owner moves) | `any_peer`, sender 1 | `reliable` | 0 | `life: int, attacker: int, offset: Vector2, duration_sec: float` |

Damage, healing (T18), elimination and respawn share channel 0, so they always
arrive in order and don't need a life number. Each one makes every peer emit
`Events.hero_damaged`, `hero_healed`, `hero_eliminated` or `hero_respawned` (the server when it
decides, clients when the message arrives); the test world prints one
`[Combat]` line per signal.

### Shield Charge (card T14)

Server-confirmed, not predicted. On Q the owner sends `request_ability` and
dashes only when `receive_ability_used` comes back, one round trip later; its
countdown starts then, so an honest owner never asks early. The server checks
with `AbilityCheck` (`game/heroes/ability_check.gd`, tested by
`tests/ability_check_test.gd`): wrong owner is dropped; another life or
eliminated is answered; a NaN or zero direction or a request still cooling down
is refused, answered, and logged as `[Ability] peer <id>: refused ...` at most
once a second per hero. The cooldown is kept through death.

While the dash lasts, the server sweeps each accepted move of the dasher that
drew on its grant with the hero's own circle against layer 2, excluding the
dasher (`ChargeSweep`, tested by `tests/charge_sweep_test.gd`), and knocks back
each live hero it finds once per dash. `Events.ability_used` and
`hero_knocked_back` fire on every peer; the server logs
`[Combat] ability_used: Player <id> used <ability>, ready again in <s> s` (T18 names the ability) and
`[Combat] knocked_back: Player <victim> by Player <attacker>`.

### The server's check (ShotCheck)

In order, the first failure wins:

1. Not from the hero's owner, or a shot id not newer than the last: dropped.
2. Fired in another life, or the shooter is eliminated: dropped.
3. NaN, INF or zero direction: refused. The server normalizes the rest.
4. **Rate, as a schedule:** refused if `now < next - 0.25 s`. Each accepted
   shot sets `next = max(now, next) + fire_interval_sec x 0.9`. One late shot
   never makes the next on-time one look early, up to 0.25 s of jitter never
   refuses an honest shot, the sustained rate stays within 1/0.9 of the
   weapon's, and a pause buys at most 0.25 s of extra fire.

Refusals log `[Shot] peer <id>: refused <n> shot(s), last: <reason>` at most
once a second per hero. Constants: `ShotCheck.JITTER_SEC`, `RATE_SLACK`,
`ShotSim.CAPACITY`, `Shots.VISUAL_CAPACITY`.

### Late join

The spawner rebuilds existing heroes from their spawn data, so a newcomer would
see everyone at full health and life 0, and drop every relay from a hero that
has respawned. In `client_ready`, right after the spawn, the server sends that
peer `receive_combat_state` for every hero: life, health, eliminated and
seconds to respawn.

### Status line and labels

Until John's T17 HUD, each hero's label reads `Player <id>  <health>`, and the
owner's status line adds `Eliminated, back in N s` while it is down, plus
`fire-cheat=<x>` when that flag is on. A hero with an ability (T14) also shows
`Q ready` or `Q <s> s`.

## Where the numbers live (card T13)

Every gameplay number a non-coder tunes is a `.tres` file, edited in the
Inspector and checked by `tests/data_test.gd` on every pull request:

| Number | File |
| --- | --- |
| Move speed, max health, default weapon | The hero's HeroData: `game/heroes/data/bruiser.tres`, `mage.tres`, `scout.tres`, `medic.tres` |
| Which heroes, in what order | `game/heroes/data/roster.tres` (everyone plays the first until T16) |
| Damage, fire rate, shot speed, size and range | The weapon's WeaponData: `game/weapons/data/sidearm.tres` (Adam's) |
| Respawn time | `game/heroes/data/combat.tres` (until T15's mode rules) |
| Shield Charge cooldown, dash and knockback distance and time | `game/heroes/data/shield_charge.tres` (T14), the Bruiser's `ability` |
| Jet Dash charges, cooldown per charge, dash distance and time | `game/heroes/data/jet_dash.tres` (T18), the Scout's `ability` |
| Blink cooldown and distance | `game/heroes/data/blink.tres` (T18), the Mage's `ability` |
| Heal Drone cooldown, heal per tick, tick time, duration and radius | `game/heroes/data/heal_drone.tres` (T18), the Medic's `ability` |

- **One spawn path:** `test_world.gd`'s spawn function runs on every peer and
  calls `NetHero.setup()` with the roster hero its spawn data names (T18; T13
  used `ROSTER.first()` and sent only the peer id).
- `setup()` runs before the hero enters the tree, so it sets the Weapon's
  `data` and Health's `max_health` before their own `_ready`.
- **One speed:** the owner moves at `move_speed` (x `--speed-cheat`), and the
  server builds its MoveCheck with the same `move_speed`. Both read the same
  HeroData, so tuning it never causes `TOO_FAR` rejects.
- What stays as constants in the net code: network plumbing (port, send rate,
  channels, log and snap intervals) and the server's check tolerances
  (MoveCheck's 1.25x slack and 1 s budget, ShotCheck's timing slack, the
  1 s forced-motion grace and the 4000 px/s charge speed cap), per
  CLAUDE.md.

## Test bots (card T09)

A test bot is the real game, headless, joining like a person: the same
handshake, world load, `client_ready`, MoveCheck and ShotCheck. The server can't
tell bots from people, and the wire format did not change (`NET_PROTOCOL`
stays 3). Debug builds only: a release build ignores `--bot` and
`--quit-after-sec`. One bot by hand:

    C:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --join=127.0.0.1 --bot=1 --quit-after-sec=60

### The input hook

The owner's NetHero makes one `HeroInput` child, named `Input`, in `_ready`.
NetHero and Weapon read move, aim and fire only from it: `move()`, `aim()`,
`fire_held()` and `fire_pressed()`. The base reads the keyboard and mouse. With
`--bot=<seed>`, `NetHero._make_input()` makes a `BotBrain` instead; it is the
one place that knows bots exist. T14's Q ability adds its key to `HeroInput`.

### What a bot does

- **Walks** to random points in the world's `bot_area()` (the test world: the
  floor inside its border walls). It picks a new point on arrival (24 px),
  after 1 s without getting 8 px closer, or every 4-8 s. There is no
  pathfinding: a bot stuck at a wall just picks another point (T23 adds
  pathfinding if 16 bots jam). A world without `bot_area()` gets bots that
  stand and shoot.
- **Every 0.25 s** it targets the nearest live hero within its weapon's
  `range_px` that it can see (`intersect_ray` on layer 1, the world), people
  included. Each look rolls a new aim error of up to ±6°.
- **With a target** it fires in 0.5-1.5 s bursts with 0.3-1 s pauses. With none
  it aims where it walks and holds fire. While eliminated it idles; on respawn
  it starts over.
- **Q** (T14, T18): with a target and a charge ready it presses Q, whatever its
  ability. The Heal Drone heals whoever is near; the target only gives the aim.
- **BotRules** holds these decisions: pure, with the clock and a seeded
  RandomNumberGenerator passed in, so the same seed and inputs make the same
  choices. Its numbers are test-tool constants in `bot_rules.gd`, not gameplay
  `.tres` files.

Each bot prints `[Bot] seed <n> is peer <id>` when its hero spawns, then
`[Bot] seed <n>: <shots> shots, <hits> hits, <eliminations> eliminations, <deaths> deaths`
every 30 s and when it leaves. Shots come from `Weapon.fired` (its own shots
only), the rest from Events.

### The run timer (--quit-after-sec)

`-- --quit-after-sec=<n>` (debug builds) ends any run, server or client, after n
seconds with an exit code a script can check. It lives in `game/core/game.gd`,
so it survives scene changes.

| Exit | When |
| --- | --- |
| 0 | A server that hosted, or a client that joined and never lost the connection |
| 1 | Anything else. A timed client whose join fails, or that loses its server, quits with 1 at once |

At the end it logs `[Game] quit-after-sec=<n>: exit <code>` and hangs up with
`Net.leave()` before quitting, so the shutdown logs stay clean. A bot with no
server exits 1 after about 5 s (Net's join timeout). Smoke and `run_bots` always
pass the timer; a bot started by hand without it stays on the headless menu
after a failed join.

### Load test (run_bots)

1. Double-click `tools/run_server.bat` and wait for `server up`.
2. Double-click `tools/run_bots.bat`: 8 bots join this PC for 10 minutes.

From a terminal: `tools\run_bots.ps1 [-Count 8] [-Address 127.0.0.1] [-Minutes 10]`
(`run_bots.bat` passes the same options on). It:

- says which address the bots join, and stops at once when nothing listens on
  UDP 7777 on this PC;
- starts the bots 1 s apart (`--bot=1` to `--bot=<Count>`, bot n with
  `--hero=` the roster's hero (n-1) mod 4 (T18), `--quit-after-sec=<Minutes x 60>`), with logs in `%TEMP%\acoc-bots\bot<n>.log`;
- every 10 s prints how many bots are alive and, when the server runs on this
  PC (whoever owns UDP 7777), the server's CPU (% of one core and of the whole
  PC) and memory (working set);
- at the end shows each bot's hero, exit code and last `[Bot]` line, the server's
  average and peak CPU and peak memory, then PASS when every bot exited 0.
  Ctrl+C stops the bots too.

`[Move]` and `[Shot]` lines would show in the server window; an honest bot never
causes one.

Bots start, and so leave, 1 s apart on purpose. When two peers leave in the same
server frame, Godot's server relay tells the second about the first after ENet
has already dropped it, and the server logs
`ERROR: Unable to send packet on channel 0, max channels: 0`. It is harmless,
but smoke fails on any `ERROR:`. Turning off `multiplayer.server_relay` in `Net`
would remove it (we never send messages client to client); that is a `net.gd`
decision for Gabe.

### Server stats

The dedicated server prints one line every 10 s. It comes from `ServerStats`,
which the test world adds on the server; T16's arena must add it too.

    [Stats] peers 2, fps 145, worst frame 16.2 ms, memory 31.8 MB, up 1.2 KB/s, down 1.1 KB/s

| Field | Meaning |
| --- | --- |
| `peers` | Connected peers |
| `fps` | Frames per second. A headless server runs at about 145. |
| `worst frame` | The longest gap between two frames in those 10 s |
| `memory` | Godot's own count (`OS.get_static_memory_usage()`) in MiB; 0 in release exports. `run_bots` shows what Windows sees. |
| `up` / `down` | ENet bytes sent and received per second, from the host's `pop_statistic` (reset on each pop), without IP/UDP headers. KB = 1000 bytes, so Mbps = KB/s x 0.008: Gate 2's 5 Mbps upload budget is 625 KB/s. |

It reads traffic only while the peer is an active ENet host: on an inactive
one, reading `host` or popping a statistic prints an `ERROR:`.

## Seams for week 3

What Adam's T12/T15 and John's T16/T17 build on. All server-side, no RPC
change except the spawn position in the spawn data: NET_PROTOCOL 6.

### Match events (`Events`, game/core/events.gd)

| Signal | Meaning |
| --- | --- |
| `team_assigned(peer_id, team)` | This peer plays for team 0 (Blue `#3B82F6`) or 1 (Orange `#F97316`). |
| `team_score_changed(team, score)` | That team's score is now `score`. |
| `match_clock_changed(seconds_left)` | Whole seconds left; at most once a second. |
| `match_ended(winning_team)` | 0 or 1, or -1 for a draw. |

Adam's mode (T15) emits all four on **every** peer, the server and each client,
and **replays the current state to a late joiner** (every peer's team, both
scores, the clock) once that peer is ready (`world.is_peer_ready()`, after its
`client_ready`), so a newcomer's HUD and bots start right.

Until T39 (Maps online) there is no relay and no "peer became ready" hook:
- The mode decides on the server and sends the events to clients with its own
  `@rpc` in game/modes. That pull request also changes the `NET_PROTOCOL` line in
  game/core/net.gd (+1, pre-approved) and nothing else in net code.
- For the late-join replay, check `world.is_peer_ready(peer_id)` each frame
  for peers not yet replayed to.
- T39 adds server hooks for "a peer became ready" and "a peer left", and a
  helper that sends only to ready peers; the mode then switches to those. Gabe's code only
listens: the world keeps every team it hears (`teams_seen()`), and bots copy it
when their hero spawns, then follow `team_assigned`, so they never target a
teammate whether the replay comes before or after the hero.

### MatchRules (game/core/match_rules.gd)

The server asks the world's `rules()` who hits whom and where heroes come back.
A mode extends `MatchRules`, overrides what it needs and installs it on the
server with `world.set_rules(MyRules.new())` before heroes spawn (`null` puts the
defaults back). No autoload: heroes, shots and bots already ask the world for
`respawn_point()`, `shots()` and `bot_area()`.

| Method | Default (the game today) | Used by |
| --- | --- | --- |
| `team_of(peer_id) -> int` | -1 (no team) | `can_heal` |
| `is_enemy(a, b) -> bool` | `a != b` | Shots pass through non-enemies (`allies_among`); Shield Charge knocks back enemies only. Not bots: they follow `team_assigned` (no team = enemy), so a mode with another enemy rule must tell its bots too |
| `respawn_point(peer_id) -> Vector2` | the T06 ring | First spawn (sent in the spawn data) and every respawn |
| `respawn_delay_sec(peer_id) -> float` | `combat.tres` `respawn_sec` (4 s) | The server's respawn |
| `spawn_protection_sec() -> float` | 0 | After each respawn (not the first spawn; T12 decides whether that gets it too): no damage, no knockback; healing allowed. T12 reads its seconds from a .tres in game/modes/data, not a number in code |
| `can_heal(healer, target)` (built on the two above; override those instead) | self; everyone while neither side has a team; else not an enemy | The Heal Drone: everyone today, teammates once T15 installs teams (a healer with no team then heals no one on a team). A no-team mode (free-for-all) that must not heal enemies overrides this one |

- A shot that hits a protected hero is absorbed: `receive_damage` and
  `Events.hero_damaged` still fire, with **amount 0**, so every client ends the
  shot there. John's T25: amount can be 0.
- Each respawn with protection logs `[Combat] protected: Player <id> for <s> s`.
- Firing does not end protection. Whether it should is Adam's T12 call.
- Not here yet: clients don't see protection or the rules' respawn delay (the
  countdown still reads `combat.tres`; a late joiner gets the server's
  countdown, up to 60 s). Both need an RPC, so NET_PROTOCOL +1 (7).
- Tested by `tests/match_rules_test.gd` with a 2-team MatchRules.
- ShotSim's `allies_of` returns an `Array[RID]`; an untyped Array is copied in.

### Hero choice (T16)

`Game.hero_choice` (game/core/game.gd): T16's hero select sets the roster slot
before joining (`Net.join()`, or `Net.play()` once T10 lands). `client_ready` sends it when it is
0 or more, else `--hero=` (debug builds only), else 0. It works in release builds.

## Match scene (T16)

Plan only; no scene yet.
1. The match scene replaces `test_world.tscn`: Net loads it before joining, as now.
2. It keeps test_world's root script contract: `rules()`/`set_rules()`, `respawn_point()`,
   `shots()`, `bot_area()`, `teams_seen()`, `is_peer_ready()` and `client_ready()`.
   Fixed paths: `Shots` and `Heroes` are direct children of the root, heroes direct children of `Heroes`.
3. Gabe's parts move over unchanged: `Heroes` + `HeroSpawner`, `Shots`,
   `ServerStats` and the combat log lines.
4. Adam's map is an instanced child: TileMapLayer walls on physics layer 1, two
   team spawn areas and the bot area as marked nodes.
5. Adam's mode is a child node that installs its MatchRules from those spawn
   points on the server and emits the match events.
6. John's HUD (T17) and hero select (T16) listen to Events; neither holds a
   reference to the world.
7. `test_world.tscn` stays as the proving ground for bots and smoke until the
   match scene passes the same bot match.
