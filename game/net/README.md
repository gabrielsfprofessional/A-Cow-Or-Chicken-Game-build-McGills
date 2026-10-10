# game/net

Owner: Gabe

Connection, syncing heroes, LAN discovery, headless test bots. Cards: T06, T07, T09.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

## What is here

| File | What it is |
| --- | --- |
| `test_world.tscn` / `test_world.gd` | Temporary proving ground from T06/T07: one hero per player, a border wall and two inner walls. T16 replaces it with the real arena. |
| `net_hero.tscn` / `net_hero.gd` | `NetHero`, the T07 hero: moves, sends, checks and smooths. T13/T14 move it into `game/heroes`. |
| `move_check.gd` | `MoveCheck`: the server's check on each movement update. Pure, tested by `tests/move_check_test.gd`. |
| `remote_timeline.gd` | `RemoteTimeline`: plays other players' heroes back 100 ms behind. Pure, tested by `tests/remote_timeline_test.gd`. |
| `delay_queue.gd` | `DelayQueue`: fakes a slow network for `--sim-lag` / `--sim-jitter`. Tested by `tests/delay_queue_test.gd`. |
| `data/movement.tres` | `MovementData`: move speed (px/s). Tune it in the Inspector. T13 moves it into HeroData. |

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
- `Update the game from the Drive folder (server v0.0.1+net2, you v0.0.1)` (a T06 build sends a bare version)
- `The server refused the connection. It may be full, or running a different version.`
- `Lost connection to the server. It may have been closed.`

Until T10 lands, `Net` shows the reason with `OS.alert` and goes back to the main
menu by itself. **T10 should stop that**: once the Join screen listens to these
signals and shows the reason, drop the `_return_to_menu` call from `game/core/net.gd`.

## Running it

Nobody needs to type any of this. Double-click the two launchers in `tools/`:

| Double-click | What happens |
| --- | --- |
| `tools/run_server.bat` | Starts the server on this PC. A black window opens and says `server up`. Leave it open while everyone plays; close it to stop the server. |
| `tools/join_game.bat` | Asks `Server address (Enter = this PC)`, then opens the game and joins. Enter alone means `127.0.0.1`. You can also drop an address on it, or pass one: `join_game.bat 192.168.1.20`. |

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

The handshake sends `"<version>+net<NET_PROTOCOL>"`, for example `0.0.1+net2`:
the game version (`application/config/version` in `project.godot`) plus the wire
format number `NET_PROTOCOL` in `game/core/net.gd`. It rides along inside the
ENet connect handshake, using `SceneMultiplayer`'s `auth_callback`, `send_auth`
and `complete_auth`. Both sides send theirs, so either side can name both in the
message. A mismatch is refused before the peer counts as connected: the client
shows `Update the game from the Drive folder (server vX, you vY)` and the server
logs `refused peer <id>: version mismatch`.

**NET_PROTOCOL** is 1 for T06 (which sent a bare version) and 2 from T07. Bump it
in the same pull request as any change to an RPC, its arguments, its channel or
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
2. When the handshake finishes, the client sends `client_ready` to the server.
3. Only then does the server spawn that client's hero through the
   `HeroSpawner` (`MultiplayerSpawner`): a `NetHero` under `Heroes`,
   named with the peer id, labelled `Player <id>`, with multiplayer authority
   set to that peer.
4. When a peer disconnects, the server frees its hero and the spawner takes the
   hero off every client.
5. The server only relays movement to peers that have sent `client_ready`.

## Movement (card T07)

- **Your own hero** moves the instant you press a key: a `CharacterBody2D` in
  floating mode, moved every physics tick with `Input.get_vector` on the
  `move_*` actions, at `data/movement.tres` speed. It never waits on the server.
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

| RPC | Direction | Mode | Transfer | Channel | Payload |
| --- | --- | --- | --- | --- | --- |
| `submit_move` | owner -> server (`rpc_id(1)`) | `authority` + server checks `get_remote_sender_id()` is the owner | `unreliable_ordered` | `Net.MOVE_CHANNEL` (1) | `sequence: int, position: Vector2` |
| `relay_move` | server -> each ready peer except the owner (`rpc_id`) | `any_peer`, ignored unless the sender is 1 | `unreliable_ordered` | `Net.MOVE_CHANNEL` (1) | `sequence: int, position: Vector2` |
| `snap_back` | server -> owner only (`rpc_id`) | `any_peer`, ignored unless the sender is 1 | `reliable` | 0 | `sequence: int, position: Vector2` (the server's last good position) |

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
format and `NET_PROTOCOL` stays 2.

### The server's check (MoveCheck)

In order, the first failure wins:

1. Not from the hero's owner: dropped.
2. Sequence not newer than the last one: dropped.
3. NaN or INF in the position, or a coordinate beyond +/-100000 px: rejected.
4. **Time budget:** each hero has up to 1 s of movement time. It starts full,
   refills at 1.1x real time, and each accepted update spends its sequence gap
   x 50 ms. An update that would overspend is rejected (this also stops a huge
   sequence jump). A player who lags as they join is fine: the budget is full.
5. Moved further than speed x 1.25 x (sequence gap x 50 ms): rejected.

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
| `--sim-jitter=<ms>` | Adds a random 0 to `<ms>` on top. Messages never overtake each other. |
| `--speed-cheat=<x>` | Multiplies this client's own speed. 2 gets it snapped back. |
| `--version-override=<v>` | Pretends to be version `<v>` (see above). |

The fake lag delays movement messages only, not the handshake or spawns. The
launchers in `tools/` never pass these flags.
