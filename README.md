<div align="center">

# neuro-sdk-neuratro

**Neuro-sama plays Balatro**

Lua mod hooks into the game, Rust bridge relays messages over WebSocket,
Neuro gets game state and responds with actions.

[![Version](https://img.shields.io/badge/version-0.4.0-ff4d94?style=flat-square)](#changelog)
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

## Changelog

### 0.4.0 -- 2026-03-03

<details>
<summary><strong>Overlay polish + pack UI fix</strong></summary>

- Edition tags (`[Foil]`, `[Holo]`, `[Poly]`, `[Neg]`) shown inline with card names in overlay panels with animated persona-coloured text
- Joker mult display: static base mult shows shorthand only; accumulated/dynamic mult shows description instead (no misleading bare "+N Mult")
- Deck names resolved from localization data instead of raw internal keys
- Font wrap cache added — eliminates repeated `getWrap` calls during overlay rendering
- Left shop panel now hides correctly during all `*_PACK` states, not just buffoon pack
- Neuro palette darkened to near-black teal fills with hot-pink text (matches Evil Neuro's dark-fill approach)
- Emote routing: `neuroexplode` on round eval, `neurocube` default; `boomevil` on Evil round eval, `evilgamba` on Evil in shop
- TV-glitch login animation upgraded

</details>

### 0.3.1 -- 2026-03-03

<details>
<summary><strong>Hotfix: force query never sent (G.NEURO refactor collision)</strong></summary>

- `G.NEURO.force_actions` field was shadowing the `Bridge:force_actions` method introduced by the 0.2.1 `G.NEURO_*` → `G.NEURO.*` refactor — `actions/force` was never actually sent
- Renamed cached field to `G.NEURO.force_action_names` across `neuro-game.lua`, `dispatcher.lua`, `enforce.lua`

</details>

<details>
<summary><strong>Shop money display uses actual balance</strong></summary>

- Shop affordability display and money projection now use `G.GAME.dollars` directly instead of `dollars - bankrupt_at`
- Previously items showed `(afford)` when the AI couldn't actually buy them (buffer was included in display but not in enforcement), causing repeated failed purchases

</details>

<details>
<summary><strong>Removed forced play override</strong></summary>

- Removed "SIM1 wins easily — play these indices, no thinking needed" shortcut that bypassed LLM decision-making
- SIM1 is now presented as neutral information ("Strongest hand found: Straight at [...]") rather than a command

</details>

### 0.3.0 -- 2026-03-03

<details>
<summary><strong>DESPERATE mode</strong></summary>

- New `DESPERATE` mode when `hands_left <= 0` — AI is explicitly told the blind is already lost and to not play cards
- AI can still use remaining discards to cycle cards for future rounds

</details>

<details>
<summary><strong>Full consumable coverage</strong></summary>

- All 22 base tarots now have specific targeting advice (which cards to pick and why)
- All 16 base spectrals now emit hints — 9 card-selection spectrals get targeting advice, 7 direct-use spectrals were previously completely invisible to the AI
- Destructive spectrals (Ankh, Hex, Ouija, Ectoplasm) include explicit warnings
- Neuratro custom consumables covered: The Twins, The Bit, Mitosis, Rhythm
- The Bit advice fixed: was incorrectly showing Twins advice; now correctly shows Donation enhancement ($2 when scored) targeting 1 card
- The Twins/The Bit deck-specific branches split — previously shared advice despite having different target counts
- Direct-use tarots (The Fool, Temperance, The Hermit, etc.) now emit proper hints

</details>

<details>
<summary><strong>Blueprint/Brainstorm chain hint</strong></summary>

- When Blueprint or Brainstorm is in the joker lineup, AI sees exactly which joker each one copies and its xMult value
- AI knows to use `set_joker_order` when position-sensitive

</details>

<details>
<summary><strong>SHOP money projection</strong></summary>

- AI sees a projected end-of-round money total based on blind reward + interest if $0 is spent
- Shows next-round interest rate and the per-$5-saved interest gain to help AI decide how much to spend vs save

</details>

<details>
<summary><strong>Voucher chain awareness</strong></summary>

- All 16 voucher upgrade pairs tracked (Overstock → Overstock Plus, Clearance Sale → Liquidation, etc.)
- AI is alerted when a base voucher is in the shop (buy now to unlock upgrade next ante) or when it already owns the base and the upgrade is available

</details>

### 0.2.1 -- 2026-03-02

<details>
<summary><strong>Internal refactor: G.NEURO_* → G.NEURO.*</strong></summary>

- All global state moved from flat `G.NEURO_FORCE_INFLIGHT`, `G.NEURO_STATE`, etc. to nested `G.NEURO.force_inflight`, `G.NEURO.state`, etc.
- Cleaner namespace, single table holds all SDK state
- Fixed crash when `NEURO_ENABLE` is not set — empty `G.NEURO` table no longer triggers the update loop

</details>

<details>
<summary><strong>Profanity filter rewrite</strong></summary>

- Exact single-word terms now use O(1) hash lookup instead of regex scan
- Split compiled patterns into `exact_set`, `exact_norm`, and `regex_list`
- Added normalized fallback: leetspeak-encoded slurs caught even when regex replacement doesn't fire
- Removed dead code branch (word-boundary path was unreachable)

</details>

<details>
<summary><strong>select_blind validation fix</strong></summary>

- Relaxed overly strict `select_blind` guard that required `blind_choices` and a matching selectable key
- Fixes cases where blind selection was blocked despite being the correct state

</details>

<details>
<summary><strong>Test harness</strong></summary>

- `--test` CLI flag runs `test_deadlock` module and exits with pass/fail code
- F8 hotkey runs the same test suite in-game
- `G.NEURO.test_actions` and `G.NEURO.test_dispatcher` exposed for test access

</details>

<details>
<summary><strong>Joker synergy analysis</strong></summary>

- `Context.get_joker_synergy_analysis()` exposed — detects synergy pairs across active jokers and returns a formatted analysis block

</details>

<details>
<summary><strong>Staging debug API</strong></summary>

- `Staging.get_debug_lines()` — returns current staging state as formatted lines for overlay display
- `Staging.clear_overlay()` — programmatically clears the staging overlay text

</details>

### 0.2.0 -- 2026-03-02

<details>
<summary><strong>Deck strategy</strong></summary>

- Every deck now has detailed strategy guidance shown to the AI during gameplay
- Deck-specific hand priorities (Checkered: Flush >>> Pairs, Euchre: Jack Pairs/Trips > Flush, etc.)
- Invader/Glorp deck: AI knows Gleeb cards give 10x chips but break at end of round, prioritizes playing them
- Twin deck: AI knows to target Kings with The Twins tarot, understands Twin enhancement (+15 chips +2 mult)
- Deck strategy shown in both SELECTING_HAND and SHOP states

</details>

<details>
<summary><strong>Consumable usage</strong></summary>

- Tarots that need highlighted hand cards (The Twins, The Bit, etc.) now work via single action: `use_card` with `hand_indices` parameter
- AI gets urgent prompts when usable consumables are available, with deck-aware targeting advice
- Planet cards and other consumables also surfaced in SELECTING_HAND state

</details>

<details>
<summary><strong>Enhanced card tracking</strong></summary>

- AI sees which hand cards have enhancements (Twin, Bonus, Gold, Steel, Glass, Glorpy, etc.)
- Glorpy cards get urgent "play NOW, they break at end of round" advice

</details>

<details>
<summary><strong>Cooldown system</strong></summary>

- All cooldowns now configurable via `.env` file (`dotenv.lua` loader)
- Per-action throttle, global cooldown, state entry delays, pack pick delays, shop buy delays
- OS env vars override `.env` values override hardcoded defaults

</details>

<details>
<summary><strong>Deadlock fixes</strong></summary>

- SHOP: `toggle_shop` always available as escape, `use_card` always offered regardless of buy phase
- GAME_OVER: setup actions added to allowed actions
- Overlay intercept: `setup_run` offered as alternative when `exit_overlay_menu` fails
- Repeat limits raised for menu/overlay states

</details>

<details>
<summary><strong>Crash fixes</strong></summary>

- Nil `.cards` guard on all card areas before every update tick
- Rate-limited error logging with 5 second suppression

</details>

<details>
<summary><strong>UI overlay</strong></summary>

- Joker cycling panel always shows descriptions, not just effect shorthand
- Effect badge shown on name line alongside description
- Fixed "+0 Mult" display for jokers with conditional effects

</details>

<details>
<summary><strong>Palette</strong></summary>

- Neuro palette rebuilt from reference art: hot pink dominant, neon cyan accent, periwinkle purple, mint green, sunshine yellow

</details>

### 0.1.0 -- 2026-02-26

Initial release candidate.

- Full game state integration: all game states from SPLASH through GAME_OVER
- Token-efficient compact context for AI
- Score estimation with hand combo detection
- Persona system: Neuro-sama / Evil Neuro with distinct palettes and emotes
- Animated emote spritesheets in UI panel footer
- Card glow overlay for AI-highlighted cards
- Profanity filter for stream safety
- Multi-step action staging (seed setup, shop buying)
- Action throttling and cooldowns
- Custom info-query actions (joker strategy, scoring explanation, etc.)

---

<div align="center">

**[MIT License](LICENSE)**

</div>
