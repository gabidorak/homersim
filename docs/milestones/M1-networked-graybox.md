# M1: Networked graybox

**Goal**: a dedicated headless server, with up to 6 clients connecting by IP, each controlling a capsule in a graybox arena and seeing the others move smoothly. Joins and leaves are handled cleanly. **No gameplay yet.**
**Estimated effort**: 1–2 weeks.
**Prerequisites**: M0 done.
**Design refs**: [ARCHITECTURE §2–5](../ARCHITECTURE.md#2-process-model).

## 1. Tasks
### Networking core
- [ ] `autoload/net.gd`
  - `host(port: int, max_clients: int) -> Error`: create `ENetMultiplayerPeer`, call `create_server`, set it as `multiplayer.multiplayer_peer`.
  - `join(address: String, port: int) -> Error`, `leave()`.
  - Signals: `connected`, `connection_failed(reason)`, `disconnected`, `peer_joined(id)`, `peer_left(id)`.
  - A connection timeout of 5 s, which emits `connection_failed`.
- [ ] **Join handshake** (in `common/session.gd`): after connecting, the client calls `request_join(name, version)` (version = `ProjectSettings.application/config/version`). The server validates the version and player cap, sanitises and de-duplicates the name, stores it in `players: Dictionary[int, PlayerInfo]`, then replies `on_join_accepted(peer_id, roster)` or `on_join_rejected(reason)` followed by a disconnect.
- [ ] `server/ServerMain.tscn` + `server_main.gd`: read `Cli` + `server.cfg` (`ConfigFile`), `Net.host()`, instance `common/Session.tscn` as `/root/Session`, log peer joins and leaves. Add `server.cfg.example`.
- [ ] `client/MainMenu.tscn`: name field, address field (`127.0.0.1:7777` default), Connect button, status label. On a successful join → free the menu and add `Session` to the root. On disconnect → go back to the menu with the reason.
- [ ] `--connect host:port --name X` CLI args auto-connect (for fast testing).

### Session and world
- [ ] `common/Session.tscn`: root `Session` (`class_name Session`, `static var current`), `World` → `levels/test/TestArena.tscn`, `World/Players` + a `MultiplayerSpawner` (spawn path = `Players`), plus empty `ServerOnly` / `ClientOnly` nodes.
- [ ] `levels/test/TestArena.tscn`: CSG floor 40×40 m with Kenney prototype textures, ramps, boxes of various heights (0.5/1/2 m), a 0.7 m tunnel, a staircase, 6 `Marker3D` spawn points, `DirectionalLight3D` + `WorldEnvironment`.

### Player (temporary, single role)
- [ ] `entities/player/Player.tscn`: `CharacterBody3D` + capsule + a `MeshInstance3D` capsule coloured by peer id + `NameTag` (`Label3D`, billboard).
- [ ] Custom `spawn_function` on the spawner (server calls `spawner.spawn({peer=id, pos=…})`). It sets `name = str(peer)` and calls `set_multiplayer_authority(peer)`.
- [ ] `components/movement/movement_component.gd`: a basic FP controller (WASD, mouse look, jump, gravity). Physics and input run **only if `is_multiplayer_authority()`**.
- [ ] `components/camera/first_person_rig.gd`: `Camera3D` made current only for the local player. Mouse capture, toggled with Esc.
- [ ] `BodySync` (`MultiplayerSynchronizer`): replicate `position`, `rotation.y`, head pitch. Replication interval 0.05 s (20 Hz). Visibility = all.
- [ ] **Interpolation for remote players**: sync into `target_position` / `target_yaw` properties and lerp the visual toward them in `_process` (`1 - exp(-15 * delta)`), or keep a 100 ms snapshot buffer. Start with the lerp.
- [ ] Server: spawn the player on `on_join_accepted`, despawn on `peer_left` (`queue_free` the body; the spawner replicates the removal).

### Dev workflow
- [ ] Editor *Debug → Customize Run Instances*: 4 instances. Instance 1 gets the args `-- --server --headless` (or run the server from a terminal), instances 2–4 get `-- --connect 127.0.0.1:7777 --name P<n>`.
- [ ] `Log` lines on both sides for join, leave and spawn.

## 2. Done when
- [ ] Headless server + 3 clients: everyone sees everyone moving smoothly, with no jitter at 20 Hz.
- [ ] Killing a client process removes its capsule on the others within about 5 s (ENet timeout), and the server logs it.
- [ ] Stopping the server sends all clients back to the menu with "Disconnected from server".
- [ ] Joining with a mismatched version is rejected with a readable message.
- [ ] A 7th client is rejected with "Server full".
- [ ] It still works with `tc netem` at 100 ms delay ±20 ms and 1% loss (only remote movement is slightly behind).

## 3. Manual test script
```bash
godot --headless -- --server --port 7777 &
for n in A B C; do godot -- --connect 127.0.0.1:7777 --name $n & done
# with latency (needs sudo):
sudo tc qdisc add dev lo root netem delay 100ms 20ms loss 1%
sudo tc qdisc del dev lo root     # remove afterwards!
```

## 4. Pitfalls
- RPCs and synchronizers need **identical node paths** on all peers. That's why `Session` is one shared scene.
- Spawned nodes must be **direct children of the spawner's `spawn_path`**, and the scene must be in its spawnable list (or use a `spawn_function`).
- Do not call `set_multiplayer_authority` after the synchronizer has started. Do it in the spawn function, before the node enters the tree.
- `MultiplayerSynchronizer` only replicates *properties* that you add in its Replication panel.
- The mouse stays captured when tabbing out. Release it on `NOTIFICATION_APPLICATION_FOCUS_OUT`.
