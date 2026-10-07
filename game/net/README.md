# game/net

Owner: Gabe

Connection, syncing heroes, LAN discovery, headless test bots. Cards: T06, T07, T09.

Only the owner's cards change this folder. See CLAUDE.md, "Folders and owners".

## What is here

| File | What it is |
| --- | --- |
| `test_world.tscn` / `test_world.gd` | Temporary proving ground from T06: one 48 px square per player, no movement. T16 replaces it with the real arena. |

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
- `Update the game from the Drive folder (server v0.0.1, you v0.0.0)`
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

The version (`application/config/version` in `project.godot`, `0.0.1` today)
rides along inside the ENet connect handshake, using `SceneMultiplayer`'s
`auth_callback`, `send_auth` and `complete_auth`. Both sides send their version,
so either side can name both numbers in the message. A mismatch is refused
before the peer counts as connected: the client shows
`Update the game from the Drive folder (server vX, you vY)` and the server logs
`refused peer <id>: version mismatch`.

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
   `HeroSpawner` (`MultiplayerSpawner`): a 48 px coloured square under `Heroes`,
   named with the peer id, labelled `Player <id>`, with multiplayer authority
   set to that peer. T07 moves it.
4. When a peer disconnects, the server frees its hero and the spawner takes the
   square off every client.
