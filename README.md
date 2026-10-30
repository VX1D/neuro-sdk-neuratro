<div align="center">

# neuro-sdk-neuratro

**Neuro-sama plays Balatro**

Lua mod hooks into the game, Rust bridge relays messages over WebSocket,
Neuro gets game state and responds with actions.

[![Version](https://img.shields.io/badge/version-1.2.0-ff4d94?style=flat-square)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-80dfff?style=flat-square)](LICENSE)
[![Balatro](https://img.shields.io/badge/Balatro-1.0.1-9b72e6?style=flat-square)](https://store.steampowered.com/app/2379780/Balatro/)
[![Lua](https://img.shields.io/badge/Lua-5.1-ffd700?style=flat-square)](https://www.lua.org/)
[![Rust](https://img.shields.io/badge/Rust-bridge-00e5ff?style=flat-square)](https://rustup.rs/)

Built by **x264.webrip**

</div>

---

## Architecture

```
     Neuro / LLM
          ^
          | WebSocket
          v
   neuro-bridge-rs      Rust relay
          ^
          | File-based IPC
          v
      neuro-game/       Lua mod inside Balatro
```

The Lua mod reads game state, figures out valid actions, and sends a force request. The Rust relay owns configuration, wire framing, outbox tailing, cursor tracking, bootstrap, action/result bookkeeping, queueing, sessions, and leases in `neuro-bridge-rs/src/`. It opens the WebSocket only after the mod's live `startup`, forwards traffic in outbox order, and never answers an action itself: every `action` goes to the mod, and only the mod sends its `action/result`.

---

## Requirements

| Dependency | Notes |
|---|---|
| [Balatro](https://store.steampowered.com/app/2379780/Balatro/) | Steam version |
| [Lovely injector v0.9.0](https://github.com/ethangreen-dev/lovely-injector/releases/tag/v0.9.0) | Drop `version.dll` into the Balatro game folder |
| [Steamodded 26.1002.0 or newer](https://github.com/Steamodded/smods/releases/tag/26.1002.0) | Mod framework |
| [Rust toolchain](https://rustup.rs/) | To build the bridge |

---

## Quick start

### 1. Set up Lovely + Steamodded

Follow the instructions on the [Lovely](https://github.com/ethangreen-dev/lovely-injector/releases/tag/v0.9.0) and [Steamodded](https://github.com/Steamodded/smods) repos. Both need to be working before anything else.

### 2. Copy the mod

```
%AppData%\Balatro\Mods\neuro-game\
```

Should sit directly inside `Mods\`, not nested further.

### 3. Get the bridge

A release ships a prebuilt `neuro-bridge-<version>-windows-x86_64.exe` next to `run-bridge.ps1`; nothing to build.

From a source checkout, build it once:

```powershell
cd neuro-bridge-rs
cargo build --release
```

Binary ends up at `neuro-bridge-rs\target\release\neuro-bridge.exe`.

### 4. Run

```powershell
.\run-bridge.ps1        # starts bridge, connects to ws://127.0.0.1:8000
```
The launcher validates the WebSocket URL and resolves a usable IPC directory before starting the relay. In a release folder it runs the prebuilt `neuro-bridge-*-windows-x86_64.exe`; in a source checkout it runs `cargo build --release` and refuses to run when the build fails or the expected binary is missing.

Then launch Balatro. The mod connects automatically.

---

## Configuration

Mod settings are integrated directly with Steamodded (`SMODS.current_mod.config`). Pacing, cooldowns, colors, and runtime flags can be tuned live in-game with the **F8 Tuning Panel** (press **S** to persist changes).

### Bridge environment variables

These variables are read by the Rust bridge or the mod bootstrap. Steamodded
runtime settings are listed separately below.

| Variable | Default | Description |
|---|---|---|
| `NEURO_SDK_WS_URL` | required unless `neuro_ws_url.txt` is set | WebSocket endpoint for the Rust bridge. A `neuro_ws_url.txt` file, looked up where `neuro_ipc_dir.txt` is (the deployed mod directory, the working directory, the executable's directory), takes precedence; otherwise the variable is read from the process environment, then (Windows) the user's and the machine's persisted environment, like the Unity SDK's `WsUrlFinder`. The bridge exits with a fatal error if neither is set, matching the reference SDKs. |
| `NEURO_IPC_DIR` | `%APPDATA%\Balatro\neuro-ipc` | IPC directory shared between bridge and mod. Set one canonical **absolute** path in the environment for launcher/direct-binary use; `neuro_ipc_dir.txt` is consumed from the deployed mod directory. |
| `NEURO_ENABLE` | unset | Optional disable gate: `0`, `false`, or `no` disables the integration. Any other value leaves enablement subject to IPC availability. |


### IPC and recovery contract

- Start the bridge from the deployed launcher root, or set `NEURO_IPC_DIR` to the same canonical absolute directory used by the copied `neuro-game` mod. Relative values are rejected because they resolve differently in launchers, the direct Rust binary, and an installed mod.
- Launchers inspect markers only beneath the installed mod under `APPDATA` (`Balatro/Mods/neuro-game` or `neuro_game`); they never use a checkout marker as a substitute for the mod actually loaded by Steamodded. If no portable mapping is available, the launcher fails closed.
- Native Linux/Proton setups must set an absolute Linux-visible `NEURO_IPC_DIR`; a Windows-style `APPDATA` value is rejected rather than translated implicitly. The marker file is configuration, not authentication.
- Treat the IPC directory as a same-user trust boundary, not an authentication mechanism: keep it owned by the account running the bridge and mod, and restrict it to that account (Unix mode `0700`; Windows user-only ACL). Do not place it on a shared or world-writable path.
- Launcher diagnostics print only WebSocket scheme/authority. The child process still receives the complete `NEURO_SDK_WS_URL`, including any path or query required by the server; do not put secrets in a URL that will be shared with other logs or processes.
- The Lua outbox is append-only per file generation and capped at 64 MiB. Protected frames rotate a full durable outbox to `.1` before appending when no torn suffix is pending; unsupported/unsafe rotation fails closed rather than truncating records. Inspect the bridge before any manual archival or removal, and never remove a live outbox or lease.
- While its frame loop runs, the mod rewrites `neuro_heartbeat.txt` about once a second (paused and in menus too). Once the relay has seen it change during a session and it then stays unchanged for 30 s, the relay closes the WebSocket without sending anything on the game's behalf, as a crashed game's socket would close, and reconnects only on the next live `startup`. A mod that never writes the file is never judged dead.
- One relay owns an IPC directory at a time through an OS lock on `.neuro-bridge.lease`; the lock is released when the relay exits or crashes, so no manual cleanup is needed.

### Steamodded/in-game runtime settings

These are `SMODS.current_mod.config` settings, not raw environment controls.
Change them from the **F8 Tuning Panel**.

| Setting | Default | Description |
|---|---|---|
| `NEURO_DEBUG` | `off` | Runtime verbose logging toggle |

### In-game live tuning

Press **F8** in-game to open the live tuning panel. The LLM pauses while the panel is open. Changes apply immediately and are saved to Steamodded mod config when pressing **S**.

- **TUNING** -- Speed multiplier (`NEURO_SPEED_MULT`), cooldown scaling, auto-tune with game speed, and per-action delays.
- **COLOURS** -- Per-persona palette tweaks with live RGB hex editing.
- **RUNTIME** -- Persona selection (Neuro / Evil / Hiyori) and runtime debug toggles.

| Key | Action |
|---|---|
| `UP` / `DN` | Move between rows |
| `LT` / `RT` | Adjust value (hold `SHIFT` for 5x / 25x in colours) |
| `ENTER` | Edit channel (COLOURS) |
| `R` | Reset selected row to default |
| `S` | Save configuration to Steamodded |
| `TAB` | Switch tab |
| `F8` | Close panel |

Rows and tabs can also be clicked directly with the mouse.

---

## Testing

- **Offline test suite** -- Run `cd neuro-game && bash tests/run_all.sh`

---

## Project structure

```
neuro-game/                  Lua mod, copy to %AppData%\Balatro\Mods\
  neuro-game.lua             Entry point: Steamodded header, LOVE hooks, F8 key routing
  core/                      Dispatch + control loop
    dispatcher.lua             Routes game states to handlers, runs the action loop
    orchestrator.lua           Force scheduling, cooldowns, per-state entry gating
    neuro_lifecycle.lua        Boot/enable lifecycle + per-frame update entry
    actions.lua                Action definitions and per-state action-list filtering
    action_policy.lua          Which actions are legal in each state
    enforce.lua                Throttle + cooldown enforcement
    force_state.lua            Force in-flight bookkeeping + decision fingerprint
    staging.lua                Action buffering and hover/preview staging
    state.lua / state_kinds.lua  Game-state collection and classification
    bridge.lua / bridge_init.lua File-based IPC to the Rust bridge
    mod_paths.lua              Mod install-path resolution
    trace.lua                  Structured trace logging
    config.lua / config_schema.lua  Unified config owner and Steamodded config bridge
    filtered.lua               Profanity filter
  context/                   Token-efficient state snapshots sent to the LLM
    context_compact.lua        Compact context builder
    context_readable.lua       Human-readable prose context builder
    ctx_*.lua                  Per-domain slices (hand, shop, jokers, blind, misc, helpers)
    game_rules.lua             Static rules reference used by the context builders
  facts/                     Single-source game-fact derivation
    card_util / card_area_util / hand_facts / debuff_facts / deck_facts / deck_names
    economy_facts / game_facts / numeric_effects / fact_hints
    token_legends.lua          Glossary tokens for retained context
  force/                     Per-state force builders (what to ask the LLM to do)
    force_router.lua           Dispatches to the right builder per state
    menu_flow.lua              MENU / SPLASH / GAME_OVER / run-setup force builder
    force_shop / force_pack / force_blind_select / force_selecting_hand / force_helpers
  handlers/                  Execute the LLM's chosen actions
    hand_handlers / shop_handlers / board_handlers / menu_handlers / plan_handlers / seed_run_handlers / use_card / directional_card
  hud/                       In-game panels + shared draw helpers
    tuning_panel.lua           F8 live-tuning + colour panel
    cards.lua                  Card mini-renderer (atlas sprites: enhancement, seal, edition, sticker)
    emotes / showcase / prims / rows / vouchers / assets / text_colors / state
  render/                    Visual layer
    hud_overlay.lua            Main SDK/persona HUD overlay
    hud_shared.lua             Shared HUD frame/motif helpers
    neuro-anim.lua             Emote animation controller + Motion easing
    palette.lua / persona_palette.lua  Colour system and per-persona palettes
    panels/                    Acquire, shop, pack, right-panel, and persona renderers
  util/                      Shared helpers
    utils / neuro_json / scoring / level_delta / schema_validate / metrics / once
  tests/                     Offline + in-game test suites
    test_anti_regress / test_deadlock / run_deadlock / test_containment
    test_force_roundtrip / run_roundtrip   Every action x state x payload -> exactly-one-result invariant
    test_force_fuzz / run_fuzz             Randomized G-state fuzzer over the forcer + executor
    run_all.sh                             One-command release gate over the whole offline suite
  assets/                    Emote spritesheets and persona art

neuro-bridge-rs/             Rust WebSocket <-> IPC relay
  src/
    main.rs                   Relay entrypoint and session wiring
    config.rs                  Relay configuration
    wire.rs                    WebSocket/IPC wire framing
    cursor.rs                  IPC cursor tracking
    bootstrap.rs               Outbox snapshot at session start
    tailer.rs                  File-ordered outbox tailing
    receive.rs                 Inbound frames to the mod inbox
    obligations.rs             Action/result bookkeeping (one result per id)
    controls.rs                Startup game-name binding
    queue.rs                   Outgoing queue and byte budgets
    socket.rs                  WebSocket I/O and timeouts
    session.rs                 WebSocket session lifecycle and reconnect
    lease.rs                   IPC lease ownership
    liveness.rs                Game heartbeat: a dead game loses its socket
scripts/                     Developer CLI scripts (Lua lint)
```

---

## [Changelog](CHANGELOG.md)

---

<div align="center">

**[MIT License](LICENSE)**

</div>
