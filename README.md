<div align="center">

# neuro-sdk-neuratro

**Neuro-sama plays Balatro**

Lua mod hooks into the game, Rust bridge relays messages over WebSocket,
Neuro gets game state and responds with actions.

[![Version](https://img.shields.io/badge/version-1.1.0-ff4d94?style=flat-square)](CHANGELOG.md)
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

---

## Quick start

### 1. Set up Lovely + Steamodded

Follow the instructions on the [Lovely](https://github.com/ethangreen-dev/lovely-injector/releases/tag/v0.9.0) and [Steamodded](https://github.com/Steamodded/smods) repos. Both need to be working before anything else.

### 2. Copy the mod

```
%AppData%\Balatro\Mods\neuro-game\
```

Should sit directly inside `Mods\`, not nested further.

### 3. Build the bridge

```powershell
cd neuro-bridge-rs
cargo build --release
```

Binary ends up at `neuro-bridge-rs\target\release\neuro-bridge.exe`.

### 4. Run

```powershell
.\run-bridge.ps1        # starts bridge, connects to ws://127.0.0.1:8000
```

Then launch Balatro. The mod connects automatically.

---

## Configuration

Mod settings are integrated directly with Steamodded (`SMODS.current_mod.config`). Pacing, cooldowns, colors, and runtime flags can be tuned live in-game with the **F8 Tuning Panel** (press **S** to persist changes).

### Environment variables

For startup and IPC configuration:

| Variable | Default | Description |
|---|---|---|
| `NEURO_SDK_WS_URL` | `ws://127.0.0.1:8000` | WebSocket endpoint for the Rust bridge |
| `NEURO_IPC_DIR` | `%APPDATA%\Balatro\neuro-ipc` | IPC directory shared between bridge and mod (can also be set in `neuro_ipc_dir.txt`) |
| `NEURO_ENABLE` | unset | Set to `1` to enable the SDK integration |
| `NEURO_DEBUG` | unset | Set to `1` for verbose logging and debug features |
| `NEURO_DEBUG_OVERLAY` | unset | Set to `1` (compact) or `2` (expanded) for the stats overlay on boot |

### In-game live tuning

Press **F8** in-game to open the live tuning panel. The LLM pauses while the panel is open. Changes apply immediately and are saved to Steamodded mod config when pressing **S**.

- **TUNING** -- Speed multiplier (`NEURO_SPEED_MULT`), cooldown scaling, auto-tune with game speed, and per-action delays.
- **COLOURS** -- Per-persona palette tweaks with live RGB hex editing.
- **RUNTIME** -- Persona selection (Neuro / Evil / Hiyori) and runtime debug toggles.

| Key | Action |
|---|---|
| `UP` / `DN` | Move between rows |
| `LT` / `RT` | Adjust value (hold `SHIFT` for 5x / 25x in colours) |
| `ENTER` | Run self-test (TUNING) / edit channel (COLOURS) |
| `R` | Reset selected row to default |
| `S` | Save configuration to Steamodded |
| `TAB` | Switch tab |
| `F8` | Close panel |

Rows and tabs can also be clicked directly with the mouse.

### Diagnostics & overlays

- **F9** -- Toggle stats overlay (off -> compact -> expanded). In expanded mode, **F11** cycles diagnostic sections (`PERF`, `ENGINE`, `FORCE`, `ACTIONS`, `CTX/IPC`).
- **F10** -- Run in-game deadlock check (requires `NEURO_DEBUG=1`).

---

## Testing

- **In-game self-tests** (`core/selftest.lua`) -- Runs engine scenarios on demand from the F8 panel (TUNING tab), or on boot by enabling `SELFTEST ON BOOT` in the RUNTIME tab. Results write to `<save>/selftest/<date>-report.md`.
- **Offline test suite** -- Run `cd neuro-game && bash tests/run_all.sh`

---

## Project structure

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
    config.lua / config_schema.lua  Unified config owner and Steamodded config bridge
    filtered.lua               Profanity filter
    selftest.lua / selftest_cases.lua  In-game self-test runner and cases
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
    utils / neuro_json / scoring / level_delta / schema_validate / metrics / once
  tests/                     Offline + in-game test suites
    test_anti_regress / test_deadlock / run_deadlock / test_readiness / test_containment / test_selftest / test_filter
    test_force_roundtrip / run_roundtrip   Every action x state x payload -> exactly-one-result invariant
    test_force_fuzz / run_fuzz             Randomized G-state fuzzer over the forcer + executor
    run_all.sh                             One-command release gate over the whole offline suite
  assets/                    Emote spritesheets and persona art

neuro-bridge-rs/             Rust WebSocket <-> IPC relay
scripts/                     Developer CLI scripts (rasteriser, linters, checkers)
tools/                       Offline protocol and wire audit tooling
```

---

## [Changelog](CHANGELOG.md)

---

<div align="center">

**[MIT License](LICENSE)**

</div>
