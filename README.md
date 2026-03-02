# neuro-sdk-neuratro

Neuro-sama plays Balatro. Lua mod hooks into the game, Rust bridge relays messages over WebSocket, Neuro gets game state and responds with actions.

Built by **x264.webrip**

---

## How it works

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

The Lua mod reads game state, figures out valid actions, and sends a force request. The bridge relays it to whatever's on the other end (Neuro's API in production, local LLM for testing).

---

## Requirements

- [Balatro](https://store.steampowered.com/app/2379780/Balatro/) on Steam
- [Lovely injector v0.9.0](https://github.com/ethangreen-dev/lovely-injector/releases/tag/v0.9.0) - drop `version.dll` into the Balatro game folder
- [Steamodded](https://github.com/Steamodded/smods) - mod framework
- [Rust toolchain](https://rustup.rs/) - to build the bridge

### Neuratro

[Neuratro](https://www.nexusmods.com/balatro/mods/486) is a community Balatro content mod with Neuro-sama themed jokers, decks, and art. Optional but strongly recommended. The integration was built and tested with Neuratro and it makes the whole thing way better.

---

## Install

### 1. Set up Lovely + Steamodded

Follow the instructions on the [Lovely](https://github.com/ethangreen-dev/lovely-injector/releases/tag/v0.9.0) and [Steamodded](https://github.com/Steamodded/smods) repos. Both need to be working before anything else.

### 2. (Recommended) Install Neuratro

Get it from [NexusMods](https://www.nexusmods.com/balatro/mods/486)

### 3. Copy the mod

Copy the `neuro-game` folder into your Balatro mods directory:

```
%AppData%\Balatro\Mods\neuro-game\
```

Should sit directly inside `Mods\`, not nested further.

### 4. Build the bridge

You need the [Rust toolchain](https://rustup.rs/) installed, then:

```powershell
cd neuro-bridge-rs
cargo build --release
```

Binary ends up at `neuro-bridge-rs\target\release\neuro-bridge.exe`.

---

## Running

**1. Start the bridge:**

```powershell
.\run-bridge.ps1
```

Sets up the IPC directory and connects to `ws://127.0.0.1:8000` by default. Override with `NEURO_SDK_WS_URL` if needed.

**2. Launch Balatro** - the mod connects automatically once the game is running.

---

## Environment variables

### Connection

| Variable | Default | Description |
|---|---|---|
| `NEURO_ENABLE` | unset | Set to `1` to enable the SDK |
| `NEURO_SDK_WS_URL` | `ws://127.0.0.1:8000` | WebSocket endpoint |
| `NEURO_IPC_DIR` | auto | IPC directory shared between bridge and mod |

### Timing and cooldowns

Controls how fast the mod sends actions and force queries. Defaults work at normal game speed. If `NEURO_SPEED_MULT` is below 0.6, fast defaults kick in automatically.

| Variable | Default | Fast | Description |
|---|---|---|---|
| `NEURO_SPEED_MULT` | `1.0` | - | Animation speed multiplier (lower = faster) |
| `NEURO_STATE_COOLDOWN` | `0.08` | `0.04` | Wait after state change before acting |
| `NEURO_ACTION_COOLDOWN` | `0.15` | `0.06` | Wait between actions |
| `NEURO_FORCE_DEBOUNCE` | `0.22` | `0.10` | Wait before re-sending a force query |
| `NEURO_FORCE_TIMEOUT_SECONDS` | `45` | `45` | Timeout for action response |
| `NEURO_FORCE_ONLY` | `false` | `false` | Only allow actions during force windows |

### Debug

| Variable | Default | Description |
|---|---|---|
| `NEURO_DEBUG` | unset | Set to `1` for verbose mod logging |

---

## Project structure

```
neuro-game/              Lua mod, copy to %AppData%\Balatro\Mods\
  neuro-game.lua         Entry point, hooks, UI overlay, palettes
  dispatcher.lua         Action validation, execution, force queries
  actions.lua            Action definitions and per-state filtering
  context_compact.lua    Token-efficient game state snapshots
  bridge.lua             File-based IPC layer
  state.lua              Game state collection
  staging.lua            Action buffering and hover animations
  enforce.lua            Throttling and cooldowns
  filtered.lua           Profanity filter
  assets/                Emote spritesheets and persona art

neuro-bridge-rs/         Rust WebSocket <-> IPC relay
```

---

## License

[MIT](LICENSE)
