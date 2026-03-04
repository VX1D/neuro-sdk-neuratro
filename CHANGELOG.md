# Changelog

### 0.5.2 -- 2026-03-04

<details>
<summary><strong>SMODS booster pack fix + UI polish + card name resolution</strong></summary>

**SMODS booster pack actions fixed** (`actions.lua`, `dispatcher.lua`)

- `use_card` validation now checks `G.pack_cards` (SMODS) in addition to `G.booster_pack` (vanilla). Previously, SMODS/spectral booster packs were completely broken — the AI's pick actions were rejected as invalid because only the vanilla area was checked
- `skip_booster` is now always included in force allowed actions for all pack states. Was previously only added when `picks_left <= 0`, leaving the AI stuck with no escape if picking failed

**Card name resolution fixed** (`utils.lua`)

- `safe_name` now tries localization sources before falling back to `card.label`. SMODS and Neuratro cards were displaying raw internal keys (e.g. `vedalsdrink`) instead of their display names (e.g. `Banana Rum`) because `card.label` for modded cards is the raw key, not the localized name
- New lookup order: UIBox → `G.localization.descriptions` → `center.loc_txt.name` → `G.P_CENTERS` → label (only if multi-word or capitalized) → `center.name` → `center.key`

**UI panel polish** (`neuro-game.lua`)

- Left and right overlay panels: drop shadow, single clean 1.5px border (replacing 3-layer stack), top inner highlight for glass effect, soft outer glow, deeper title bar with GLOW-color accent bars, rounded corners 10→12
- Shop descriptions: always show full card descriptions with per-word coloring (Mult=red, Chips=cyan, $=gold, +N=green, xN=red)
- Cycling joker blank flash fixed: slot reset now skips fade-in phase so the display doesn't go blank for 0.3s when a joker is sold mid-cycle

</details>

### 0.5.1 -- 2026-03-04

<details>
<summary><strong>Context completeness: 9 missing game state fields added</strong></summary>

Deep audit of every `G.GAME.*` variable in Balatro 1.0.1o against what `context_compact.lua` actually captures. Found and filled genuine gaps that hurt AI decision quality.

**HIGH IMPACT (5 items)**

- **Free rerolls** (`G.GAME.current_round.free_rerolls`): AI now sees `FR:N` in shop header when free rerolls are available. Fixed `can_reroll` and `reroll_safe` legality checks — previously the AI would skip free rerolls thinking they cost money
- **Shop discount %** (`G.GAME.discount_percent`): `DSC:N%` shown in shop header when active. Items may be affordable with discount that the AI previously thought it couldn't buy
- **Full active voucher list** (`G.GAME.used_vouchers`): New `V|` section lists all owned vouchers in SELECTING_HAND, SHOP, and BLIND_SELECT states. Previously only 3 specific vouchers were checked (pareidolia, retcon, directors_cut) — AI was blind to all other voucher effects
- **Discard pile count** (`G.discard.cards`): `DP:N` added to deck size line. Helps AI reason about remaining deck composition
- **Play area cards** (`G.play.cards`): New `PLAY|` section shows cards currently in the play area with full mod info (enhancement, seal, edition)

**MEDIUM IMPACT (4 items)**

- **Blinds skipped this run** (`G.GAME.skips`): `SKP:N` in blind select header. Affects Skip Tag dollar value calculations
- **Bosses already used** (`G.GAME.bosses_used`): New `BU|` section in BLIND_SELECT lists previously defeated bosses. Helps predict upcoming boss blinds
- **Price inflation** (`G.GAME.inflation`): `INF:N` in shop header when > 0. AI needs to know current inflation for buy/skip decisions
- **End-of-round earnings preview** (`G.GAME.current_round.dollars_to_be_earned`): `ERN:N` appended to blind line. Economy planning — know exact payout during the round

All new sections registered in STATE_PRIORITY drop_order for token budget enforcement.

</details>

### 0.5.0 -- 2026-03-03

<details>
<summary><strong>Dead code removal (~200 lines)</strong></summary>

- `neuro-game.lua`: removed `NeuroJson` import, `NEURO_PANEL_MODE`, `PANEL_ROW_CAP` block, `persona_short`, `dbg_lines`/`debug_on` and all dead branches, `PINK_DEEP()`, `ENABLE_PALETTE_TEST_BUTTONS` block (50 lines of palette test rendering), `show_long_descriptions`/`show_shop_descriptions` guards
- `dispatcher.lua`: removed no-op `record_action_result()`
- `context_compact.lua`: removed `last_result_section()`, `payout_scope_section()`, `jokers_compact_inline()`, `ContextCompact.reset_tracking()`, `setup_decks_section()` and its dead `elseif` branch
- `enforce.lua`: removed `get_transition_cooldown()`
- `actions.lua`: removed `get_cheapest_shop_cost()` (superseded by inline `has_affordable()`)

</details>

<details>
<summary><strong>Refactoring: monster functions decomposed</strong></summary>

- `draw_neuro_indicator()` in neuro-game.lua — extracted `joker_fx()` to module level, `build_panel_rows()` separated from rendering
- `combos_section()` in context_compact.lua — split into `tally_hand()`, `detect_value_combos()`, `detect_flush_combos()`, `detect_straight_combos()`, `estimate_score()`
- `get_force_for_state()` in dispatcher.lua — converted to `FORCE_HANDLERS` dispatch table; extracted `count_unlocked_decks()` and `seed_info_query()` helpers
- `safe_card()` in state.lua — converted to `ENHANCEMENT_LOOKUP` table

</details>

<details>
<summary><strong>Deduplication: shared utilities extracted</strong></summary>

- `safe_name()`, `flatten_description()`, `has_playbook_extra()` moved to utils.lua
- Area+index validation extracted as `validate_area_card()` in dispatcher.lua, replacing 5 inline copies
- Hiyori persona check extracted as `hiyori_persona_gate()` in dispatcher.lua, replacing 4 inline copies
- Area resolution in staging.lua extracted as `resolve_payload_card()`, replacing 4 inline copies

</details>

<details>
<summary><strong>Logic bug fixes</strong></summary>

- **Ace chip value**: `math.min(r, 10)` → `(r == 14 and 11 or math.min(r, 10))` — Aces were scoring 10 chips instead of 11
- **Resources block ordering**: moved after `s.blind = get_blind_data()` so `s.blind.target_score` is always accessible
- **sell_card validation**: now checks both jokers AND consumables areas (previously could miss consumables)
- **buy_from_shop validation**: now checks `shop_jokers`, `shop_vouchers`, AND `shop_booster` (previously missed boosters and vouchers)
- **Reroll cost**: removed hardcoded `or 5` fallback — returns `false` if cost is unknown instead of silently lying
- **Score estimation self-parse**: replaced regex-parsing of own formatted output with a structured `combo_scoring` table
- **dispatcher.lua:981 crash**: nil guard added before `#G.hand.cards` comparison in debuffed-play rejection path — could crash if hand was cleared mid-evaluation

</details>

<details>
<summary><strong>Performance: per-frame waste eliminated</strong></summary>

- `pal()` was called 6× per frame — cached once as `_pal = pal()` at top of draw
- `apply_palette()` ran every frame — gated behind dirty-check `if pk ~= _persona_colors_applied`
- `resolve_mod_path()` was not cached — added `_cached_mod_path`/`_mod_path_resolved` cache
- `bridge.lua` JSON encode ran every frame — throttled to 250ms interval, only writes on state change
- `collect_joker_details()` deep-copy depth reduced from 6 to 4, type checks added before copy
- `get_effective_state()` heavy fallback replaced: `State.build()` → lightweight `State.get_state_name()`

</details>

<details>
<summary><strong>Error handling: silent swallowing fixed</strong></summary>

- `Card:draw` hook pcall now logs errors via `neuro_log("GLOW ERROR:", _glow_err)` instead of silently discarding them
- `staging.lua update()` pcall now prints `[neuro-staging] update error:` on failure
- `enforce.lua now_time()` fallback changed from returning `0` to `os.clock()`

</details>

<details>
<summary><strong>Actions system cleanup</strong></summary>

- `generic_schema()` simplified to `{ type = "object" }` — previous complex schema was unused by callers
- `get_all_actions(g_funcs)` unused `g_funcs` parameter removed
- `STATE_ACTIONS` duplication eliminated — extracted shared `PACK_ACTIONS` table referenced by all 5 pack states
- `is_action_valid()` substring matching replaced with explicit `HAND_ACTIONS` lookup set

</details>

<details>
<summary><strong>Rust bridge improvements</strong></summary>

- `Arc<Mutex<bool>>` replaced with `Arc<AtomicBool>` with `Ordering::Relaxed`
- Exponential reconnect backoff added: 1s → 2s → 4s → … → 30s cap (previously no backoff — hammered on disconnect)
- Broken 50-attempt file lock sleep loop removed, replaced with direct file write

</details>

<details>
<summary><strong>Profanity filter</strong></summary>

- False positives on common words fixed — single-word alphabetic terms now use `%f[%a]..%f[%A]` word-boundary anchors; multi-word terms keep substring matching
- Patterns compiled once and cached in `_compiled_patterns` table instead of recompiling on every message

</details>

<details>
<summary><strong>Seeded runs: unlocks and progression re-enabled</strong></summary>

- Wrapped `unlock_card`, `inc_career_stat`, and `win_game` to bypass the `G.GAME.seeded` gate — seeded runs now earn item unlocks, career stats, win streaks, and all win-based progression the same as normal runs
- Normal and challenge runs are unaffected — the wrappers pass through immediately when `G.GAME.seeded` is not set

</details>

<details>
<summary><strong>Debug hygiene and security</strong></summary>

- Debug disk-writes removed (`neuro_emote_debug.log`)
- 14 `print()` calls gated behind `NEURO_DEBUG=1`
- Seed clipboard print removed (was leaking run seeds to log)
- 10 stale files deleted from the repo
- Hardcoded user path removed from `.env`
- 19 `G.FUNCS` nil guards added across dispatcher.lua
- 7 action handlers got bounds checking on card indices
- `xpcall` error guard added on action execution entry point

</details>

### 0.4.1 -- 2026-03-03

<details>
<summary><strong>Pack UI: horizontal grid layout</strong></summary>

- Pack cards now displayed side-by-side in a horizontal grid instead of stacked vertically — each card gets more space and a bigger visual impact
- Panel width scales with card count (`n_cards * 155 + 20`), re-centered on screen
- Slots are taller (190px) with sprite on top, name below, description below that
- Slide-in animation changed from right→left to up-from-bottom

</details>

<details>
<summary><strong>Pack UI: edition prefix + miniature enhancements</strong></summary>

- Edition names prepended to card names in the pack overlay (`Negative 9 of Clubs`, `Polychrome The Fool`, etc.)
- Card miniatures now render enhanced playing card base faces — `Enhanced` cards draw the suit/rank sprite first, then the enhancement overlay at 0.82 alpha
- Seal indicator added to miniature: coloured dot (Red/Blue/Gold/Purple) in bottom-right corner with shadow and specular highlight

</details>

<details>
<summary><strong>Voucher buy popup: "NEW VOUCHER" with green accent</strong></summary>

- Buying a voucher from the shop now shows a distinctive "NEW VOUCHER" popup with green border glow and title bar fill instead of the generic "SHOP BUY" label
- Popup height increased to 260px to give the voucher description room

</details>

<details>
<summary><strong>Bug fixes: pack ghost, panel resize, duplicate pick crash</strong></summary>

- **Pack ghost**: after Neuro picked a card, the card-selection overlay persisted beneath the joker gain panel — fixed by clearing `_pack_picked` state on leaving pack states and gating the render on `is_pack_state`
- **Right panel resize**: hands/discards/target rows were disappearing and reappearing after every play because they only showed during `SELECTING_HAND` — now shown in all mid-round states; panel height lerps smoothly in both directions instead of snapping on grow
- **Duplicate pick crash** (`common_events.lua:2393 attempt to index local 'other' (a nil value)`): the action finalizer was unconditionally setting `last_action_at = now`, clobbering the pack pick handler's `now + 3.0` block; fixed to only update `last_action_at` when the new value is strictly greater

</details>

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
