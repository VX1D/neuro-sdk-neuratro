# Changelog

### 1.1.0 -- 2026-08-25

<details>
<summary><strong>Prose context replaces compact notation as the default</strong></summary>

- `context_readable.lua` sends natural-language state descriptions to the LLM unconditionally now, not the token-dense notation
- Deleted the old `context/context.lua` (668 lines gone)
- `context_compact.lua` is no longer a public interface — it's just the internal data collector `context_readable` pulls from

</details>

<details>
<summary><strong>Hand, joker, shop, and blind context rewritten per-domain</strong></summary>

- `ctx_hand.lua`: poker hand level, base chips/mult, and played-count projections
- `ctx_jokers.lua`: eternal/perishable/rental flags, sell values, Blueprint/Brainstorm copy targets, retrigger multipliers
- `ctx_shop.lua`: exact requirement text per action, reroll affordability after a hypothetical purchase, planet run-state summary
- `ctx_blind.lua`: payout projection (remaining hands, interest cap, tag bonuses) and full boss status
- Economy context logic moved into `facts/economy_facts.lua`, `ctx_economy.lua` shim removed

</details>

<details>
<summary><strong>Multi-step plan engine and transactions</strong></summary>

- `core/plan_gate.lua` / `core/plan_transaction.lua`: multi-step action plans across game states, with mutation aging gates and rollback if a step fails partway
- Transaction ledger validates pre-conditions and applies state changes step by step, rolls back prepared acceptances on failure
- `handlers/plan_handlers.lua`: register/execute/cancel for multi-action sequences

</details>

<details>
<summary><strong>Task mode framework</strong></summary>

- `core/task_mode.lua`: goal-driven task workflows with their own sub-plans, progress tracking, phase transitions

</details>

<details>
<summary><strong>Boss blind model covering all 28 bosses</strong></summary>

- `facts/boss/`: debuff legality, suit rules, counterplay hints, Director's Cut / Retcon reroll tracking, one module per boss

</details>

<details>
<summary><strong>Hand out calculations and draw odds</strong></summary>

- `facts/hand_facts.lua` (+1245 lines): straight/flush out calculations (`straight_outs`, inside vs open draw, `draw N/M = %`, `discard at most N`)
- Smeared Joker / Wild Card multi-suit resolution
- Boss debuff awareness (+DB markers, zeroed chips, min-card-play requirements)

</details>

<details>
<summary><strong>Live joker scoring simulator</strong></summary>

- `facts/dynamic_jokers.lua` + `util/scoring.lua`: simulates joker chip/mult/xmult output live based on rank/suit/enhancement/hand played
- Retrigger tracking for Hack, Sock and Buskin, Dusk, Seltzer, Blueprint copies

</details>

<details>
<summary><strong>Decision delta and card semantics</strong></summary>

- `facts/decision_delta.lua`: snapshot diff across LLM decisions — jokers gained/lost, sell value changes, consumable slots freed, money delta, cards drawn/discarded
- `facts/card_semantics.lua`: strips UI drag/hover text out of raw engine localization to isolate the actual rule text

</details>

<details>
<summary><strong>Economy facts engine</strong></summary>

- `facts/economy_facts.lua`: spendable cash vs debt floor (Credit Card limits, $20 floor), reroll inflation tracking, end-of-round payout projection

</details>

<details>
<summary><strong>Voucher tray and consumable/action handlers split out</strong></summary>

- `hud/vouchers.lua`: live voucher tray
- `handlers/use_card.lua`: consumable routing
- Action handlers for hand plays, shop buys, voucher unlocks, seed config, menu nav split out into `handlers/`

</details>

<details>
<summary><strong>Gameplay journal</strong></summary>

- `core/gameplay_journal.lua`: runtime event log — plays, discards, shop visits, purchases, rerolls, blind completions — for context reflection

</details>

<details>
<summary><strong>Joker performance analytics</strong></summary>

- `core/joker_hits.lua` / `core/joker_recorder.lua`: per-joker trigger counts, chip/mult output, scaling history for the whole run

</details>

<details>
<summary><strong>Central action registry</strong></summary>

- `core/action_registry.lua`: single registry for action providers, metadata, param schemas, preflight checks, availability predicates
- `core/semantic_registry.lua`: normalizes cards/jokers/consumables into stable semantic identities

</details>

<details>
<summary><strong>Structured action receipts</strong></summary>

- `core/action_execution.lua` / `core/action_receipt.lua`: execution now returns a structured receipt with reason codes and a verdict, instead of a bare pass/fail
- `core/confirmation_evidence.lua`: stages evidence/snapshots for `CONFIRMATION_REQUIRED` actions before they execute

</details>

<details>
<summary><strong>F8 layout placement preview</strong></summary>

- Interactive placement controls in F8 — custom anchors, real-time geometry preview, independent Main/Shop offset sliders
- Live RGB/hex colour editor in the COLOURS tab, per-persona
- Tuning for game speed, cooldown scaling, per-state grace periods, staging failsafe timeouts

</details>

<details>
<summary><strong>Dev scenario sandbox and card dex</strong></summary>

- `hud/dev_scenario.lua` / `hud/dev_fixtures.lua`: reproduce or simulate any game state, ante, joker build, pack, or shop scenario in-engine
- `hud/card_dex.lua`: searchable browser for card centers, sprites, descriptions

</details>

<details>
<summary><strong>HUD animation and card rendering overhaul</strong></summary>

- Animation controller rewrite: procedural easing, corridor bounds detection, smooth height transitions (`render/hud_overlay.lua`, `render/panels/`)
- `hud/cards.lua`: mini-card renderer with layered enhancements, seals, editions, stickers
- Persona-specific animation/layout hooks for Evil and Neuro (`acquire_evil.lua`, `acquire_neuro.lua`, `pack_evil.lua`, `pack_neuro.lua`)

</details>

<details>
<summary><strong>Hot reload without restarting Balatro</strong></summary>

- `core/hot_reload.lua`: reload Lua mod modules in-game without a Balatro restart, runtime state preserved

</details>

<details>
<summary><strong>Crash containment guards</strong></summary>

- `core/crash_guards.lua` / `core/transition_guard.lua`: isolated execution wrappers so an unhandled mod error can't take down the Balatro main thread
- `core/gate_clocks.lua`: real wall-clock time kept strictly separate from in-game animation clock for cooldown gating
- Watchdog grace-period timers and defer failsafes so game animations can't freeze execution

</details>

<details>
<summary><strong>Duplicate action and unintended-submit protection</strong></summary>

- `core/tx_cache.lua`: prevents duplicate frame execution and replay collisions
- Two-stage hand commit: `confirm_play` added to stop unintended card submissions
- Safety gates block accidental joker sales mid-round unless a specific boss requires it
- `core/staging.lua`: hover staging with timeout failsafes and rollback recovery

</details>

<details>
<summary><strong>Acquire overlay replaces buy toast and center showcase</strong></summary>

- `render/panels/acquire.lua`: replaces the old standalone buy toast and center showcase panels with one acquire animation queue, persona-aware (`acquire_evil.lua`, `acquire_neuro.lua`)

</details>

<details>
<summary><strong>Booster pack presentation pipeline</strong></summary>

- `render/panels/pack.lua`: multi-phase pack animation (anoint, fold, glide, shrink, crown, exit) with Evil/Neuro flavour hooks (`pack_evil.lua`, `pack_neuro.lua`)

</details>

<details>
<summary><strong>Rendering internals: badges, meshes, guarded graphics state</strong></summary>

- `render/modifier_badges.lua`: layout + rasterizer for enhancement/edition/seal/sticker badges
- `render/rect_mesh.lua`: batched GPU rectangle mesh rendering for rounded backdrops/borders
- `render/gfx_guard.lua`: scoped graphics guard so blend mode/scissor/color state can't leak across Love2D render passes

</details>

<details>
<summary><strong>Offline rasterizer for visual regression diffing</strong></summary>

- `scripts/raster.lua` / `scripts/raster_png.py`: headless draw-op capture, generates PNG contact sheets for diffing without a display

</details>

<details>
<summary><strong>Engine contract validation and wire audits</strong></summary>

- `scripts/engine_check.lua` / `scripts/gen_engine_contract.lua`: generate and validate engine event contracts against Balatro centers
- `tools/sdk_wire_audit.lua` / `tools/force_wire_audit.lua`: offline linters checking wire frames against Neuro SDK JSON schemas
- `tools/registry_measure_lib.lua`: measures action registration payload size and serialization overhead

</details>

<details>
<summary><strong>Rust IPC bridge: protocol validation and reconnect handling</strong></summary>

- Multi-stage frame sanitization filters non-conforming params, enforces Neuro SDK schema over the websocket
- Bootstrap replay cache: active action registrations and game state get cached and restored on reconnect
- Monotonic session origin timestamps discard stale IPC messages left over from a prior run
- Orphan action watchdog reports dropped/unanswered actions instead of letting the engine deadlock

</details>

<details>
<summary><strong>Testing</strong></summary>

- Tests, yeah, a lot of tests (366 test suites covering full protocol, gameplay, fuzzy staging, and invariant regression).

</details>

### 1.0.0 -- 2026-07-06

<details>
<summary><strong>Full architectural rewrite: monolith to modular packages (+29.6k / -14.3k lines)</strong></summary>

- `neuro-game.lua` (3,961 lines -> thin bootstrap), `dispatcher.lua` (3,758 lines), `context_compact.lua` (3,384 lines) deleted outright and rebuilt as focused packages under `core/`, `context/`, `facts/`, `force/`, `handlers/`, `hud/`, `render/`, `util/`
- Former top-level files (`actions.lua`, `bridge.lua`, `filtered.lua`, `staging.lua`, `state.lua`, `utils.lua`, `neuro_json.lua`, `dotenv.lua`, `palette.lua`, `neuro-anim.lua`) moved into their new package homes and substantially rewritten in place
- Deleted `enforce.lua`, the 1,916-line root `test_deadlock.lua`, and the standalone root `context.lua` / `context_compact.lua` — superseded by package equivalents

</details>

<details>
<summary><strong>Per-frame orchestrator loop</strong></summary>

- `core/orchestrator.lua` (492 lines): central per-frame loop for bridge I/O, state polling, force triggering, stable-context signalling
- Content-signature gating (`stable_content_sig`) means joker/voucher roster context is only re-sent when the roster actually changes
- `util/level_delta.lua` reports hand-level ups as their own message

</details>

<details>
<summary><strong>Dispatcher rewritten around per-domain handlers</strong></summary>

- `core/dispatcher.lua` (793 lines, rewritten from the deleted 3,758-line version): routes actions to per-domain handlers (`handlers/shop_handlers.lua`, `handlers/use_card.lua`, `handlers/menu_handlers.lua`, `handlers/info_handlers.lua`, `handlers/seed_run_handlers.lua`) instead of one giant branch
- Idempotency cache `tx_settled` (256 entries, capped) short-circuits a replayed action id to its previously recorded result instead of re-executing
- `session_matches` filters stale messages by session id

</details>

<details>
<summary><strong>Cooldown/repeat enforcement rebuilt</strong></summary>

- `core/enforce.lua`: cooldown/repeat gating rebuilt around per-state and global throttle tables (`get_cooldown`, `get_global_cooldown`)
- Env-var overrides per pack state, an explicit `UNGATED_ACTIONS`/`BYPASS_STATE_VALIDATION` allowlist
- Force-window awareness (`is_in_active_force`) so an in-flight forced action set skips the state-legality check

</details>

<details>
<summary><strong>Staging and bridge IPC rewritten</strong></summary>

- `core/staging.lua` (rewritten from root `staging.lua`): hover-preview action buffering with timeout failsafes
- `core/bridge.lua` (rewritten from root `bridge.lua`): filesystem IPC with atomic writes (temp-file + `os.rename`, non-destructive fallback if rename fails), session id generation
- JSON schema helpers forcing empty Lua tables to serialize as `{}` not `[]`

</details>

<details>
<summary><strong>New core support modules</strong></summary>

- `core/bridge_init.lua`, `core/action_policy.lua`, `core/state.lua`, `core/state_kinds.lua`, `core/tuning.lua`, `core/trace.lua`, `core/force_state.lua`, `core/mod_paths.lua`, `core/neuro_lifecycle.lua`
- Bridge bootstrap/env wiring, shared non-progress action policy, state-name classification, central tuning reader, lightweight tracing, force-state lifecycle — each now independently reusable instead of buried in the monolith

</details>

<details>
<summary><strong>Central tunable config schema</strong></summary>

- `core/config.lua` (324 lines): central schema for every tunable (`NEURO_SPEED_MULT`, cooldown/throttle/post-action delay groups, feature flags) — group, slider bounds/step, unit, env-var-seeded default per entry, driving the new in-game tuning panel
- `neuro.conf.example` (82 lines): documents every supported `NEURO_*` env var with defaults

</details>

<details>
<summary><strong>In-engine self-test framework</strong></summary>

- `core/selftest.lua` (423 lines) + `core/selftest_cases.lua` (3,310 lines): first in-engine automated regression harness
- No-op guards over save/unlock/win side effects during a run (`GUARD_NOOP`), snapshots/restores patched globals
- Drives scripted scenario cases (shop, packs, blinds, hands) against the live game loop with pass/fail tracking and a trace log

</details>

<details>
<summary><strong>Offline test suite</strong></summary>

- `tests/`: 14 files, ~7,110 lines, plus `run_*.lua` runners
- `test_anti_regress.lua` (2,437 lines), `test_deadlock.lua` (2,049 lines), `test_force_roundtrip.lua`, `test_force_fuzz.lua`, `test_readiness.lua`, `test_containment.lua`, `test_framing_consistency.lua`, `test_context_quality.lua`, `test_card_scan.lua`, `test_consumables.lua`, `test_staging_roundtrip.lua`, `test_json_wire.lua`, `test_selftest.lua`, `test_filter.lua`

</details>

<details>
<summary><strong>Context pipeline split into per-domain modules</strong></summary>

- `context/context.lua` (rewritten, 1,112 -> 668 lines) and `context/context_compact.lua` (rewritten, 3,384 lines): the single monolithic context builder split into `ctx_blind.lua` (blind/ante/payout), `ctx_economy.lua` (money/debt/interest), `ctx_hand.lua` (hand candidates), `ctx_helpers.lua`, `ctx_jokers.lua`, `ctx_misc.lua`, `ctx_shop.lua` (shop legality/pricing)
- Shared `game_rules.lua` reference module — each section now independently testable and reusable across the readable and compact builders

</details>

<details>
<summary><strong>Fact derivation engine</strong></summary>

- New single-source fact modules: `card_util.lua` (431 lines), `card_area_util.lua` (182 lines), `hand_facts.lua` (636 lines), `debuff_facts.lua` (311 lines), `deck_facts.lua`, `deck_names.lua`, `fact_hints.lua`, `game_facts.lua`, `numeric_effects.lua`, `token_legends.lua`
- Centralizes card/hand/deck/debuff derivations that were previously computed ad hoc and duplicated across the old context and dispatcher monoliths

</details>

<details>
<summary><strong>Forced-action router</strong></summary>

- `force/force_router.lua`: dispatches to per-state force builders (`force_selecting_hand.lua`, `force_shop.lua`, `force_blind_select.lua`, `force_pack.lua`, `menu_flow.lua`) instead of one long conditional
- Unlock-popup and overlay-menu intercepts handled ahead of state-specific handlers (`GAME_OVER` explicitly excluded from the generic overlay intercept to avoid a soft-loop)
- `force_helpers.snapshot_once_serials`/`restore_once_serials` refund one-shot hint serials when a force build is discarded rather than shipped

</details>

<details>
<summary><strong>Multi-panel HUD replaces single overlay</strong></summary>

- Single overlay replaced with dedicated panels under `render/panels/`: `right_panel.lua` (615 lines), `shop.lua` (409 lines), `pack.lua` (503 lines), `center_showcase.lua`, `buy_toast.lua`, orchestrated by `render/hud_overlay.lua` (839 lines) and `render/hud_shared.lua`
- `hud/tuning_panel.lua` (1,105 lines): in-game tuning UI reading/writing the `core/config.lua` schema live
- `hud/dev_scenario.lua` (290 lines): in-engine scenario reproduction sandbox

</details>

<details>
<summary><strong>Sprite-atlas card rendering</strong></summary>

- `hud/cards.lua` (689 lines) + `hud/prims.lua` (1,027 lines): sprite-atlas mini-card rendering and low-level draw primitives, replacing prior ad hoc drawing code
- `hud/vouchers.lua` (632 lines): dedicated voucher tray state and rendering

</details>

<details>
<summary><strong>Persona colour grading and animation</strong></summary>

- `render/persona_palette.lua` (415 lines) + `render/palette.lua` (rewritten): per-persona colour grading
- `render/neuro-anim.lua` (rewritten, 731 -> 593 lines): animation controller carried into `render/` with a smaller footprint
- `render/debug_stats.lua` (422 lines) and `render/staging_debug.lua`: runtime debug overlays for perf stats and staging state

</details>

<details>
<summary><strong>Shared utilities</strong></summary>

- `util/utils.lua` (rewritten, 424 -> 666 lines), `util/dotenv.lua` (rewritten), `util/neuro_json.lua` (moved/rewritten): core helpers relocated and expanded
- `util/schema_validate.lua` (143 lines): structural validator distinguishing JSON object-shaped vs. array-shaped Lua tables for outgoing action schemas
- `util/scoring.lua` (45 lines), `util/level_delta.lua` (23 lines), `util/metrics.lua` (53 lines), `util/once.lua` (12 lines): small focused helpers for hand scoring, level-up delta messages, lightweight counters, one-shot execution guards

</details>

<details>
<summary><strong>Developer tooling</strong></summary>

- `selene.toml` / `selene-tests.toml`: Lua static-analysis config declaring the Balatro/Love2D/SMODS global surface (`G`, `love`, `SMODS`, `Card`, `Event`, `EventManager`, etc.) as full-write globals for lint accuracy
- `scripts/lint_lua.sh` (28 lines): wraps `selene` linting for the mod source tree

</details>

### 0.5.3 -- 2026-03-16

<details>
<summary><strong>Booster pack UI: stable card positions after pick</strong></summary>

- Cards no longer reshuffle after the AI picks from a booster pack. Each card stays in its original slot position regardless of how many have been picked
- Original card indices are preserved in `_pack_card_indices` across picks — Balatro shifts array indices when a card leaves, but the UI now maps back to the original slot
- Pack panel width stays constant using `_pack_initial_count` — no more slot resizing as cards are removed
- Slot X position driven by stored index (`dc.index - 1`) instead of iteration order (`ci - 1`)

</details>

<details>
<summary><strong>Buy popup replaced with compact top-center toast</strong></summary>

- Removed the large 420x230 left-corner buy showcase panel that overlapped with other UI elements
- Purchases now show as a compact 480x34px toast bar at the top center, stacking below the joker showcase and pack browser in the `center_top_y` flow
- Toast shows: tiny card sprite, label (`BOUGHT` / `NEW JOKER` / `VOUCHER` / `PICKED` / `OPENED`), card name, and cost — single line, rarity-colored accent
- Duration shortened from 5.5s to 3.2s with faster fade-in/out (0.2s/0.5s)
- Queueable via the existing purchase showcase queue — multiple buys animate sequentially without overlap
- Eliminates the "4 active windows" problem during shop/pack states

</details>

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
