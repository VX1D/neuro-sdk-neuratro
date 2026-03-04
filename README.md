<div align="center">

# neuro-sdk-neuratro

**Neuro-sama plays Balatro**

Lua mod hooks into the game, Rust bridge relays messages over WebSocket,
Neuro gets game state and responds with actions.

[![Version](https://img.shields.io/badge/version-0.5.2-ff4d94?style=flat-square)](CHANGELOG.md)
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

The Lua mod reads game state, figures out valid actions, and sends a force request. The bridge relays it to whatever is on the other end (Neuro's API in production, local LLM for testing).

---

## Requirements

| Dependency | Notes |
|---|---|
| [Balatro](https://store.steampowered.com/app/2379780/Balatro/) | Steam version |
| [Lovely injector v0.9.0](https://github.com/ethangreen-dev/lovely-injector/releases/tag/v0.9.0) | Drop `version.dll` into the Balatro game folder |
| [Steamodded](https://github.com/Steamodded/smods) | Mod framework |
| [Rust toolchain](https://rustup.rs/) | To build the bridge |
| [Neuratro](https://www.nexusmods.com/balatro/mods/486) | Optional but strongly recommended |

> **Neuratro** is a community Balatro content mod with Neuro-sama themed jokers, decks, and art. The integration was built and tested with Neuratro and it makes the whole thing way better.

---

## Quick start

### 1. Set up Lovely + Steamodded

Follow the instructions on the [Lovely](https://github.com/ethangreen-dev/lovely-injector/releases/tag/v0.9.0) and [Steamodded](https://github.com/Steamodded/smods) repos. Both need to be working before anything else.

### 2. Install Neuratro (recommended)

Get it from [NexusMods](https://www.nexusmods.com/balatro/mods/486).

### 3. Copy the mod

```
%AppData%\Balatro\Mods\neuro-game\
```

Should sit directly inside `Mods\`, not nested further.

### 4. Build the bridge

```powershell
cd neuro-bridge-rs
cargo build --release
```

Binary ends up at `neuro-bridge-rs\target\release\neuro-bridge.exe`.

### 5. Run

```powershell
.\run-bridge.ps1        # starts bridge, connects to ws://127.0.0.1:8000
```

Then launch Balatro. The mod connects automatically.

---

## Configuration

All timing is configurable through the `.env` file in `neuro-game/`. The mod reads it on startup. OS environment variables override `.env` values, so you can still change things per-session.

If `NEURO_SPEED_MULT` is below 0.6, fast defaults kick in automatically.

### Connection

| Variable | Default | Description |
|---|---|---|
| `NEURO_ENABLE` | unset | Set to `1` to enable the SDK |
| `NEURO_SDK_WS_URL` | `ws://127.0.0.1:8000` | WebSocket endpoint |
| `NEURO_IPC_DIR` | auto | IPC directory shared between bridge and mod |
| `NEURO_DEBUG` | unset | Set to `1` for verbose mod logging |

<details>
<summary><strong>Force system</strong> -- when the mod sends queries after state changes and actions</summary>

| Variable | Default | Fast | What it does |
|---|---|---|---|
| `NEURO_SPEED_MULT` | `1.0` | - | Animation speed multiplier, lower is faster |
| `NEURO_STATE_COOLDOWN` | `0.10` | `0.04` | Pause after a state change before the first force query |
| `NEURO_ACTION_COOLDOWN` | `0.20` | `0.06` | Pause after any action before the force system can re-fire |
| `NEURO_FORCE_DEBOUNCE` | `0.25` | `0.10` | Collapses rapid re-force triggers into one send |
| `NEURO_FORCE_TIMEOUT_SECONDS` | `45` | `45` | How long to wait for a response before timing out |
| `NEURO_FORCE_ONLY` | `false` | `false` | Only allow actions during force windows |

</details>

<details>
<summary><strong>State entry cooldowns</strong> -- pause when entering a new game state</summary>

These give viewers time to see what happened and let animations finish.

| Variable | Default | What it does |
|---|---|---|
| `NEURO_ENTRY_CD_ROUND_EVAL` | `3.5` | Time for viewers to read round earnings |
| `NEURO_ENTRY_CD_SHOP` | `1.5` | Lets shop items finish loading in |
| `NEURO_ENTRY_CD_BUFFOON_PACK` | `2.8` | Pack open animation settle time |
| `NEURO_ENTRY_CD_TAROT_PACK` | `2.8` | Same for tarot packs |
| `NEURO_ENTRY_CD_PLANET_PACK` | `2.8` | Same for planet packs |
| `NEURO_ENTRY_CD_SPECTRAL_PACK` | `2.8` | Same for spectral packs |
| `NEURO_ENTRY_CD_STANDARD_PACK` | `2.8` | Same for standard packs |
| `NEURO_ENTRY_CD_SMODS_BOOSTER_OPENED` | `2.8` | Same for modded booster packs |

</details>

<details>
<summary><strong>Action throttles</strong> -- prevent the AI from hammering actions too fast</summary>

| Variable | Default | Fast | What it does |
|---|---|---|---|
| `NEURO_ENFORCE_COOLDOWN` | `0.45` | `0.18` | Min gap between two firings of the same action |
| `NEURO_THROTTLE_SHOP` | `0.90` | `0.30` | Same-action throttle override for shop |
| `NEURO_THROTTLE_BUFFOON_PACK` | `0.90` | `0.35` | Same-action throttle for buffoon packs |
| `NEURO_THROTTLE_TAROT_PACK` | `0.90` | `0.35` | Same-action throttle for tarot packs |
| `NEURO_THROTTLE_PLANET_PACK` | `0.90` | `0.35` | Same-action throttle for planet packs |
| `NEURO_THROTTLE_SPECTRAL_PACK` | `0.90` | `0.35` | Same-action throttle for spectral packs |
| `NEURO_THROTTLE_STANDARD_PACK` | `0.90` | `0.35` | Same-action throttle for standard packs |

</details>

<details>
<summary><strong>Global throttles</strong> -- minimum gap between any two actions regardless of type</summary>

| Variable | Default | Fast | What it does |
|---|---|---|---|
| `NEURO_GLOBAL_COOLDOWN` | `1.5` | `0.65` | Baseline min gap between any two actions |
| `NEURO_GLOBAL_THROTTLE_SELECTING_HAND` | `1.2` | `0.55` | Gap during hand selection |
| `NEURO_GLOBAL_THROTTLE_SHOP` | `3.8` | `2.20` | Gap in shop, long enough for the buy highlight to show |
| `NEURO_GLOBAL_THROTTLE_BLIND_SELECT` | `2.0` | `0.80` | Gap during blind selection |
| `NEURO_GLOBAL_THROTTLE_BUFFOON_PACK` | `2.8` | `1.40` | Gap during buffoon pack picks |
| `NEURO_GLOBAL_THROTTLE_TAROT_PACK` | `2.8` | `1.40` | Gap during tarot pack picks |
| `NEURO_GLOBAL_THROTTLE_PLANET_PACK` | `2.8` | `1.40` | Gap during planet pack picks |
| `NEURO_GLOBAL_THROTTLE_SPECTRAL_PACK` | `2.8` | `1.40` | Gap during spectral pack picks |
| `NEURO_GLOBAL_THROTTLE_STANDARD_PACK` | `2.8` | `1.40` | Gap during standard pack picks |

</details>

<details>
<summary><strong>Visual delays</strong> -- highlight previews before actions fire</summary>

These let viewers see what the AI is about to do before it happens.

| Variable | Default | What it does |
|---|---|---|
| `NEURO_PACK_PICK_DELAY` | `1.5` | How long the card highlight shows before a pack pick fires |
| `NEURO_PACK_PICK_BLOCK` | `2.0` | How long the force system stays blocked after a pack pick |
| `NEURO_SHOP_BUY_DELAY` | `1.5` | How long the card highlight shows before a shop buy fires |
| `NEURO_SHOP_BUY_BLOCK` | `1.8` | How long the force system stays blocked after a shop buy |
| `NEURO_TRANSITION_COOLDOWN` | `0.12` | Bridge-level pause after state transitions |

</details>

---

## Project structure

```
neuro-game/                  Lua mod, copy to %AppData%\Balatro\Mods\
  neuro-game.lua             Entry point, hooks, UI overlay, palettes
  dispatcher.lua             Action validation, execution, force queries
  actions.lua                Action definitions and per-state filtering
  context_compact.lua        Token-efficient game state snapshots
  bridge.lua                 File-based IPC layer
  state.lua                  Game state collection
  staging.lua                Action buffering and hover animations
  enforce.lua                Throttling and cooldowns
  dotenv.lua                 .env file reader, used by all timing code
  .env                       All cooldown and timing values, edit to tune
  filtered.lua               Profanity filter
  context.lua                Token-efficient context (verbose counterpart to context_compact.lua)
  neuro-anim.lua             Emote animation controller
  neuro_json.lua             Bundled JSON encoder/decoder
  utils.lua                  Shared utility functions
  test_deadlock.lua          In-game deadlock test suite (F8 / --test flag)
  assets/                    Emote spritesheets and persona art

neuro-bridge-rs/             Rust WebSocket <-> IPC relay
```

---

## [Changelog](CHANGELOG.md)

---

<div align="center">

**[MIT License](LICENSE)**

</div>
