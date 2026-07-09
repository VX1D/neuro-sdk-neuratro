<div align="center">

# neuro-sdk-neuratro

**Neuro-sama plays Balatro**

Lua mod hooks into the game, Rust bridge relays messages over WebSocket,
Neuro gets game state and responds with actions.

[![Version](https://img.shields.io/badge/version-1.0.0-ff4d94?style=flat-square)](CHANGELOG.md)
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

All mod config lives in one file, `neuro.conf` in `neuro-game/` (copy `neuro.conf.example` to start). One loader (`core/config.lua`) owns every key with a single precedence: **OS environment variable > `neuro.conf` > built-in default**. A missing file is fine — every key falls back to its default. Legacy `.env` / `neuro_tuning.env` are still read as a fallback until `neuro.conf` is written (e.g. the first F8 save), then they can be deleted. The F8 tuning panel reads and writes `neuro.conf`.

If `NEURO_SPEED_MULT` is below 0.6, fast defaults kick in automatically.

### Connection

| Variable | Default | Description |
|---|---|---|
| `NEURO_ENABLE` | unset | Set to `1` to enable the SDK |
| `NEURO_SDK_WS_URL` | `ws://127.0.0.1:8000` | WebSocket endpoint |
| `NEURO_IPC_DIR` | `%APPDATA%\Balatro\neuro-ipc` | IPC directory shared between bridge and mod. If you override it, the same value must be visible to **both** the bridge process and the Balatro/mod process, or no messages flow |
| `NEURO_DEBUG` | unset | Set to `1` for verbose mod logging |
| `NEURO_DEBUG_OVERLAY` | unset | Set to `1` (compact) or `2` (expanded) for the in-game SDK/perf overlay. Toggle in-game with **F9** (off -> compact -> expanded), page through the expanded sections with **F11**. See [Debug + tuning](#debug--tuning) |

<details>
<summary><strong>Force system</strong> -- when the mod sends queries after state changes and actions</summary>

| Variable | Default | Fast | What it does |
|---|---|---|---|
| `NEURO_SPEED_MULT` | `1.0` | - | Animation speed multiplier, lower is faster |
| `NEURO_STATE_COOLDOWN` | `0.05` | `0.04` | Pause after a state change before the first force query |
| `NEURO_ACTION_COOLDOWN` | `0.08` | `0.06` | Pause after any action before the force system can re-fire |
| `NEURO_FORCE_DEBOUNCE` | `0.12` | `0.10` | Collapses rapid re-force triggers into one send |
| `NEURO_FORCE_TIMEOUT_SECONDS` | `45` | `45` | How long to wait for a response before timing out |
| `NEURO_FORCE_ONLY` | `false` | `false` | Only allow actions during force windows |

</details>

<details>
<summary><strong>State entry cooldowns</strong> -- pause when entering a new game state</summary>

These give viewers time to see what happened and let animations finish.

| Variable | Default | What it does |
|---|---|---|
| `NEURO_ENTRY_CD_ROUND_EVAL` | `5.0` | Time for viewers to read round earnings |
| `NEURO_ENTRY_CD_SHOP` | `2.5` | Lets shop items finish loading in |
| `NEURO_ENTRY_CD_BUFFOON_PACK` | `4.5` | Pack open animation settle time |
| `NEURO_ENTRY_CD_TAROT_PACK` | `4.5` | Same for tarot packs |
| `NEURO_ENTRY_CD_PLANET_PACK` | `4.5` | Same for planet packs |
| `NEURO_ENTRY_CD_SPECTRAL_PACK` | `4.5` | Same for spectral packs |
| `NEURO_ENTRY_CD_STANDARD_PACK` | `4.5` | Same for standard packs |
| `NEURO_ENTRY_CD_SMODS_BOOSTER_OPENED` | `4.5` | Same for modded booster packs |

</details>

<details>
<summary><strong>Action throttles</strong> -- prevent the AI from hammering actions too fast</summary>

| Variable | Default | Fast | What it does |
|---|---|---|---|
| `NEURO_ENFORCE_COOLDOWN` | `0.60` | `0.18` | Min gap between two firings of the same action |
| `NEURO_THROTTLE_SHOP` | `1.20` | `0.30` | Same-action throttle override for shop |
| `NEURO_THROTTLE_PACK` | `1.20` | `0.35` | Same-action throttle for packs (per-pack `NEURO_THROTTLE_<PACK>` overrides) |

</details>

<details>
<summary><strong>Global throttles</strong> -- minimum gap between any two actions regardless of type</summary>

| Variable | Default | Fast | What it does |
|---|---|---|---|
| `NEURO_GLOBAL_COOLDOWN` | `2.0` | `0.65` | Baseline min gap between any two actions |
| `NEURO_GLOBAL_THROTTLE_SELECTING_HAND` | `1.8` | `0.55` | Gap during hand selection |
| `NEURO_GLOBAL_THROTTLE_SHOP` | `6.0` | `2.20` | Gap in shop, long enough for the buy highlight to show |
| `NEURO_GLOBAL_THROTTLE_BLIND_SELECT` | `3.0` | `0.80` | Gap during blind selection |
| `NEURO_GLOBAL_THROTTLE_PACK` | `4.5` | `1.40` | Gap during pack picks (per-pack `NEURO_GLOBAL_THROTTLE_<PACK>` overrides) |

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

## Debug + tuning

In-game operator controls. Hotkeys are wired in `neuro-game/neuro-game.lua` (`love.keypressed`).

### F8 -- tuning panel

`neuro-game/hud/tuning_panel.lua`. Press **F8** to toggle a live overlay for tuning the mod without a restart. While it is open the LLM is paused (badge "LLM PAUSED (F8)"), so nothing fires under you while you adjust values. Three tabs, cycled with **TAB**:

- **TUNING** -- every pacing value from `core/config.lua` (`Config.entries()`): the speed multiplier, state/action cooldowns, throttles, hover/preview delays, etc. A **RUN SELF-TEST** row at the bottom kicks off the in-game self-test runner (`core/selftest.lua`).
- **COLOURS** -- per-persona colour fine-tune. Each row is a palette key with its live RGB hex value; edit a channel to recolour the HUD in place.
- **RUNTIME** -- persona and the runtime flags (debug log, perf log, AI card glow, staging debug, selftest toggles, etc.). Boot-resolved keys (`NEURO_ENABLE`, `NEURO_IPC_DIR`, `NEURO_TRACE`) are shown read-only. A **RESET ALL RUNTIME** row restores defaults. Flag edits apply on the next reload; persona reskins live.

Controls:

| Key | Action |
|---|---|
| `UP` / `DN` | Move between rows |
| `LT` / `RT` | Adjust the selected value (hold `SHIFT` for x5) |
| `ENTER` | TUNING: run the self-test row. COLOURS: enter/leave edit mode on a row |
| `R` | Reset the selected row (COLOURS) / reset value to default |
| `S` | Save |
| `TAB` | Switch tab |
| `F8` | Close |

In the COLOURS edit mode, `LT`/`RT` adjust the hex channel (hold `SHIFT` for x25) and `UP`/`DN` switch channel. Rows and tabs are also clickable with the mouse.

Changes apply live. **S** saves them to `neuro-game/neuro.conf`, the unified config file -- `core/config.lua` re-reads it on load, so your tuned values survive a restart. (`neuro.conf` is gitignored; ship-safe defaults live in `neuro.conf.example`.)

### F9 -- debug stats overlay

`neuro-game/render/debug_stats.lua`. Press **F9** to cycle the overlay off -> compact -> expanded (same as `NEURO_DEBUG_OVERLAY`). In expanded mode, **F11** pages through the sections: `PERF`, `ENGINE`, `FORCE`, `ACTIONS`, `CTX/IPC` -- frame timing, force scheduling, action throttles, and context/IPC counters for diagnosing latency or stuck-state issues.

> **F10** runs the in-game deadlock test suite (`tests/test_deadlock.lua`), but only when `NEURO_DEBUG` is set.

### Self-test + context

- **Self-test runner** (`core/selftest.lua`, cases in `core/selftest_cases.lua`) -- drives real cases in the live engine, fired from the F8 panel or on boot via `NEURO_SELFTEST_ON_BOOT`. A separate heavy pack suite (`NEURO_SELFTEST_PACK=1`) opens real booster packs end-to-end, including `pack/standard/all_mutations` which sweeps the card mini-renderer over every enhancement x seal x edition x sticker combination. `NEURO_SELFTEST_FILTER=<substr>` narrows to a single case. Results land in `<save>/selftest/<date>-report.md`. The standalone offline suites live in `neuro-game/tests/`.
- **Split context** -- state sent to the LLM is split into a *volatile* channel (decision facts that change per turn) and a *retained* channel (stable descriptions), built in `neuro-game/context/`. Retained descriptions use short glossary tokens defined in `facts/token_legends.lua` to keep the payload small.

---

## Project structure

The old flat `neuro-game/*.lua` monolith is now split into subdirectories.

```
neuro-game/                  Lua mod, copy to %AppData%\Balatro\Mods\
  neuro-game.lua             Entry point: Steamodded header, LOVE hooks, F8/F9 key routing
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
    config.lua                 Unified config owner: every key, one file (neuro.conf), OS env > file > default
    tuning.lua                 Back-compat alias for core.config
    filtered.lua               Profanity filter
    selftest.lua / selftest_cases.lua  In-game self-test runner and cases
  context/                   Token-efficient state snapshots sent to the LLM
    context.lua                Verbose context builder
    context_compact.lua        Compact context builder
    ctx_*.lua                  Per-domain slices (hand, shop, jokers, economy, blind, misc, helpers)
    game_rules.lua             Static rules reference used by the context builders
  facts/                     Single-source game-fact derivation
    card_util / card_area_util / hand_facts / debuff_facts / deck_facts / deck_names
    game_facts / numeric_effects / fact_hints
    token_legends.lua          Glossary tokens for retained context
  force/                     Per-state force builders (what to ask the LLM to do)
    force_router.lua           Dispatches to the right builder per state
    menu_flow.lua              MENU / SPLASH / GAME_OVER / run-setup force builder
    force_shop / force_pack / force_blind_select / force_selecting_hand / force_helpers
  handlers/                  Execute the LLM's chosen actions
    hand_handlers / shop_handlers / info_handlers / menu_handlers / seed_run_handlers / use_card
  hud/                       In-game panels + shared draw helpers
    tuning_panel.lua           F8 live-tuning + colour panel
    cards.lua                  Card mini-renderer (atlas sprites: enhancement, seal, edition, sticker)
    emotes / showcase / prims / rows / vouchers / assets / text_colors / state / dev_scenario
  render/                    Visual layer
    hud_overlay.lua            Main SDK/persona HUD overlay
    hud_shared.lua             Shared HUD frame/motif helpers
    debug_stats.lua            F9 debug/perf stats overlay
    staging_debug.lua          Staging-state debug overlay
    neuro-anim.lua             Emote animation controller + Motion easing
    palette.lua / persona_palette.lua  Colour system and per-persona palettes
    panels/                    Center showcase, shop, pack, right panel, buy toast
  util/                      Shared helpers
    utils / dotenv / neuro_json / scoring / level_delta / schema_validate / metrics / once
  tests/                     Offline + in-game test suites
    test_anti_regress / test_deadlock / run_deadlock / test_readiness / test_containment / test_selftest / test_filter
    test_force_roundtrip / run_roundtrip   Every action x state x payload -> exactly-one-result invariant
    test_force_fuzz / run_fuzz             Randomized G-state fuzzer over the forcer + executor
    run_all.sh                             One-command release gate over the whole offline suite
  neuro.conf                 Unified local config (gitignored; F8 panel reads/writes it)
  neuro.conf.example         Config template with every key + defaults (committed)
  assets/                    Emote spritesheets and persona art

neuro-bridge-rs/             Rust WebSocket <-> IPC relay
```

---

## [Changelog](CHANGELOG.md)

---

<div align="center">

**[MIT License](LICENSE)**

</div>
