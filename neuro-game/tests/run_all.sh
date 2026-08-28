#!/usr/bin/env bash
# Release gate: run the whole offline suite under luajit. Exit non-zero on any failure.
# Usage: cd neuro-game && bash tests/run_all.sh   (REQUIRE_COMPLETE=1 to also reject skips)
# Exit codes: 0 clean, 1 failures, 2 bad invocation, 3 clean but incomplete under REQUIRE_COMPLETE.
set -u
cd "$(dirname "$0")/.." || exit 2
LUAJIT="${LUAJIT:-luajit}"
if [ -n "${LUA_PATH:-}" ]; then
  export LUA_PATH="./?.lua;../?.lua;;;${LUA_PATH}"
else
  export LUA_PATH="./?.lua;../?.lua;;"
fi

if [ -z "${BALATRO_DUMP:-}" ]; then
  for _d in \
    "${APPDATA:-}/Balatro/Mods/lovely/dump" \
    "${HOME:-}/.local/share/Steam/steamapps/compatdata/2379780/pfx/drive_c/users/"*"/AppData/Roaming/Balatro/Mods/lovely/dump" \
    "${HOME:-}/.steam/steam/steamapps/compatdata/2379780/pfx/drive_c/users/"*"/AppData/Roaming/Balatro/Mods/lovely/dump" \
    "${HOME:-}/Library/Application Support/Balatro/Mods/lovely/dump"; do
    if [ -f "$_d/card.lua" ]; then
      export BALATRO_DUMP="$_d"
      break
    fi
  done
fi
fail=0
skipped=0
lost_checks=0
incomplete=0
skips=""

# A run that executed NO checks used to pass: replacing a whole test file with a comment printed
# `ok <label>` with an empty summary, and a faked summary plus a bare os.exit() printed
# `ok wire_notation ==== wire-notation: 0/0 PASS, 0 FAIL ====`. Both reached "ALL GREEN", and
# REQUIRE_COMPLETE=1 did not see them either, because the skip ledger is opt-in and a test that
# simply does nothing files no skip. tests/check_census.txt records, per label, how much work that
# run has to show for itself; a run that shows less is a failure, and a run line with no record at
# all is a failure too, so a new entry cannot be added without recording its floor.
#
# The scanners that print no PASS/FAIL lines (dup_scan, emit_scan, gate_clocks, ...) are not given a
# free pass for being "legitimately empty": each records a RECEIPT pattern instead, and the receipt
# carries that run's own volume of work -- states rendered, files scanned, corrections examined --
# which is floored the same way. An empty summary is allowed; an empty run is not.
#
# Regenerate after adding or removing checks:  WRITE_CHECK_CENSUS=1 bash tests/run_all.sh
# then move tests/check_census.txt.new over tests/check_census.txt. A regeneration that would LOWER a
# floor refuses and exits non-zero unless the label is named in CENSUS_DROP_OK -- see census_record.
CENSUS="tests/check_census.txt"
CENSUS_OUT="$CENSUS.new"
declare -A CENSUS_MIN=() CENSUS_RX=() CENSUS_SEEN=() CENSUS_WAS=()
census_write="${WRITE_CHECK_CENSUS:-0}"
census_drops=""
if [ -r "$CENSUS" ]; then
  # Split explicitly: tab is IFS *whitespace* to `read`, so an entry with no receipt pattern has its
  # two adjacent tabs collapsed into one and the check count is read as the receipt -- which made
  # every such entry fail with "never printed its recorded receipt /11/".
  while IFS= read -r c_line; do
    case "$c_line" in ''|'#'*) continue ;; esac
    c_label="${c_line%%$'\t'*}"; c_rest="${c_line#*$'\t'}"
    c_min="${c_rest%%$'\t'*}"; c_rest="${c_rest#*$'\t'}"
    case "$c_rest" in
      *$'\t'*) c_rx="${c_rest%%$'\t'*}"; c_was="${c_rest#*$'\t'}" ;;
      *) c_rx="$c_rest"; c_was="" ;;
    esac
    CENSUS_MIN["$c_label"]="$c_min"
    CENSUS_RX["$c_label"]="$c_rx"
    CENSUS_WAS["$c_label"]="$c_was"
  done < "$CENSUS"
fi
if [ "$census_write" = "1" ]; then
  # Preserve the explanatory contract above the generated rows. Regeneration replaces only data;
  # previously it silently erased this header and left an opaque table behind.
  sed -n '/^#/p' "$CENSUS" > "$CENSUS_OUT"
  printf '\n' >> "$CENSUS_OUT"
fi

# A run whose check count DROPS has lost checks, and regeneration used to write the smaller floor
# with no trace. The fourth
# census field is the count that was observed when the floor was recorded, so a later regeneration
# can see the drop instead of quietly ratifying it. A drop keeps the OLD floor and the OLD count --
# which makes the very next gate run fail, so the loss has to be read before it is accepted -- unless
# the label is named in CENSUS_DROP_OK, and the accepted loss then shows in this file as 81 -> 4.
# Regeneration also never LOWERS a floor for any other reason: a floor raised by hand stays raised.
census_record() {  # census_record <label> <units observed> <floor computed from them>
  local label="$1" units="$2" floor="$3"
  local prev_floor="${CENSUS_MIN[$label]-}" prev_units="${CENSUS_WAS[$label]-}"
  if [ -n "$prev_units" ] && [ "$units" -lt "$prev_units" ]; then
    case " ${CENSUS_DROP_OK:-} " in
      *" $label "*|*" all "*)
        census_drops="${census_drops}
    $label: $prev_units -> $units check(s) (acknowledged)" ;;
      *)
        census_drops="${census_drops}
    $label: $prev_units -> $units check(s) REFUSED -- rerun with CENSUS_DROP_OK=\"$label\" to record the loss"
        floor="$prev_floor"; units="$prev_units" ;;
    esac
  elif [ -n "$prev_floor" ] && [ "$floor" -lt "$prev_floor" ]; then
    floor="$prev_floor"
  fi
  printf '%s\t%d\t%s\t%d\n' "$label" "$floor" "${CENSUS_RX[$label]-}" "$units" >> "$CENSUS_OUT"
}

# How much work a run showed, in this order of preference:
#   1. the per-check lines it printed;
#   2. the number its recorded receipt pattern ends on -- states rendered, files scanned, probes run;
#   3. the total of its "N/N PASS" summary, for the tests that count internally and print no lines;
#   4. failing all three, the number of non-empty lines it printed.
# Only (4) is a weak signal, and it is used by eight runs that report no count of their own -- see
# tests/check_census.txt. All four make a run that executed nothing show zero.
census_units() {  # census_units <label> <output>
  local label="$1" out="$2" n rx m
  n="$(printf '%s\n' "$out" | grep -cE '^[[:space:]]*(PASS|FAIL|XFAIL)[[:space:]]')"
  if [ "$n" -gt 0 ]; then printf '%s' "$n"; return; fi
  rx="${CENSUS_RX[$label]-}"
  if [ -n "$rx" ]; then
    m="$(printf '%s\n' "$out" | grep -oE "$rx" | tail -1)"
    n="$(printf '%s' "$m" | grep -oE '[0-9]+' | tail -1)"
    if [ -n "$n" ]; then printf '%s' "$n"; return; fi
  fi
  m="$(printf '%s\n' "$out" | grep -oE '[0-9]+/[0-9]+ PASS' | tail -1)"
  n="$(printf '%s' "$m" | grep -oE '[0-9]+' | tail -1)"
  if [ -n "$n" ]; then printf '%s' "$n"; return; fi
  printf '%s' "$(printf '%s\n' "$out" | grep -cE '[^[:space:]]')"
}

# A skipped check is not a passed check. It stays non-fatal so the suite is still runnable on a
# machine that genuinely lacks the dependency, but it can never reach the "ALL GREEN" line the
# release gate looks for, and REQUIRE_COMPLETE=1 turns it into a hard failure for that gate.
# Lua-side skips reach the same ledger through tests/skip_ledger.lua -- see run() below.
# Ledger only, no line of its own: run() prints the per-run status and the tail prints the detail.
record_skip() {  # record_skip <label> <reason> [lost-check-count]
  skipped=$((skipped + 1))
  lost_checks=$((lost_checks + ${3:-0}))
  skips="${skips}
    $1: $2"
}

skip() {  # skip <label> <reason>
  printf '  SKIP %-16s %s\n' "$1" "$2"
  # A dependency that is genuinely absent is a counted skip, not a census hole.
  CENSUS_SEEN["$1"]=1
  record_skip "$1" "$2"
}

run() {  # run <label> <cmd...>
  local label="$1"; shift
  local out; out="$("$@" 2>&1)"; local rc=$?
  local summary; summary="$(printf '%s\n' "$out" | grep -iE 'PASS,|passed|FAILS=|FUZZ_FAILS|ROUNDTRIP_FAILS|====.*(PASS|FAIL|probes|iters)' | tail -1)"
  # A Lua-side skip is a lost check, not a pass. tests/skip_ledger.lua emits one
  # "==SKIP== <count> <label> -- <reason>" line per group of checks that did not run; without this
  # the shell saw rc=0 and printed ok for a run that had silently dropped its checks.
  local lost=0 sline n rest slabel sreason
  while IFS= read -r sline; do
    [ -n "$sline" ] || continue
    rest="${sline#==SKIP== }"
    n="${rest%% *}"
    rest="${rest#* }"
    slabel="${rest%% -- *}"
    sreason="${rest#* -- }"
    case "$n" in (*[!0-9]*|'') n=0 ;; esac
    lost=$((lost + n))
    record_skip "$slabel" "$sreason [$n check(s) did not run]" "$n"
  done < <(printf '%s\n' "$out" | grep '^==SKIP== ')
  # The work receipt. Counted before the verdict so a run that printed nothing cannot reach `ok`.
  local units census_bad=""
  units="$(census_units "$label" "$out")"
  CENSUS_SEEN["$label"]=1
  if [ "$census_write" = "1" ]; then
    local floor=$(( units * 9 / 10 ))
    if [ "$floor" -lt 1 ] && [ "$units" -ge 1 ]; then floor=1; fi
    census_record "$label" "$units" "$floor"
  elif [ -z "${CENSUS_MIN[$label]-}" ]; then
    census_bad="no entry in $CENSUS -- record the minimum number of checks this run must show"
  elif [ -n "${CENSUS_RX[$label]-}" ] \
      && ! printf '%s\n' "$out" | grep -qE "${CENSUS_RX[$label]}"; then
    census_bad="never printed its recorded receipt /${CENSUS_RX[$label]}/ -- the run did not reach its end"
  elif [ "$units" -lt "${CENSUS_MIN[$label]}" ]; then
    census_bad="showed $units check(s), census floor ${CENSUS_MIN[$label]} -- a run that executed no checks is not a pass"
  fi
  # rc 3 is "clean but incomplete" on both sides: REQUIRE_COMPLETE=1 stopped a degraded run.
  if [ $rc -eq 3 ] && [ "$lost" -ne 0 ]; then
    printf '  SKIP %-16s %s\n' "$label" "REQUIRE_COMPLETE=1: $lost check(s) could not run"
    incomplete=1
  elif [ $rc -ne 0 ]; then
    printf '  FAIL %-16s %s\n' "$label" "$summary"
    printf '%s\n' "$out" | grep -iE 'FAIL' | head -20 | sed 's/^/       /'
    fail=1
  elif [ -n "$census_bad" ]; then
    printf '  FAIL %-16s %s\n' "$label" "$census_bad"
    fail=1
  elif [ "$lost" -ne 0 ]; then
    printf '  SKIP %-16s %s  [-%d check(s)]\n' "$label" "$summary" "$lost"
  else
    printf '  ok   %-16s %s\n' "$label" "$summary"
  fi
}

echo "== neuro-game offline suite =="
run loadcheck     "$LUAJIT" tests/run_loadcheck.lua
run gameplay_journal "$LUAJIT" tests/test_gameplay_journal.lua
run decision_evidence "$LUAJIT" tests/test_verified_decision_evidence.lua
run joker_observe "$LUAJIT" tests/test_joker_observations.lua
run directional     "$LUAJIT" tests/test_directional_card.lua
run agnostic_bound  "$LUAJIT" tests/test_agnostic_observation_boundary.lua
run config        "$LUAJIT" tests/test_config.lua
run render_ctx    "$LUAJIT" tests/run_render_smoke.lua
run shop_rows     "$LUAJIT" tests/test_shop_rows_layout.lua
run hud_corridor  "$LUAJIT" tests/test_hud_corridor.lua
run motion_prims  "$LUAJIT" tests/test_motion_primitives.lua
run buy_polarity  "$LUAJIT" tests/test_buy_beat_polarity.lua
run hud_surfaces  "$LUAJIT" tests/test_hud_surfaces.lua
run login_anim    "$LUAJIT" tests/run_login_anim.lua
run draw_exec     "$LUAJIT" tests/run_draw_exec.lua
run dev_scenes    "$LUAJIT" tests/test_dev_scenario_scenes.lua
run dev_isolate   "$LUAJIT" tests/test_dev_isolation.lua
# Offline rasteriser: drives dev_scenario through hud_overlay.draw_indicator and asserts
# on the recorded draw calls -- the only check in the suite that sees whether the acquire
# receipt and the pack claim are actually opaque and on screen. ~0.4s.
run raster        "$LUAJIT" tests/test_raster.lua
run raster_pack   "$LUAJIT" tests/test_raster_pack.lua
run raster_packfin "$LUAJIT" tests/test_raster_pack_final.lua
run pack_episode  "$LUAJIT" tests/test_pack_episode.lua
run raster_x      "$LUAJIT" tests/test_raster_stable_x.lua
run raster_motion "$LUAJIT" tests/test_raster_motion.lua
run raster_anchor "$LUAJIT" tests/test_raster_anchors.lua
run card_prop     "$LUAJIT" tests/test_card_proportions.lua
run badge_chip    "$LUAJIT" tests/test_badge_chip.lua
run draw_budget   "$LUAJIT" tests/test_draw_budget.lua
run text_batch    "$LUAJIT" tests/test_text_batching_budget.lua
run text_block    "$LUAJIT" tests/test_text_block_cache.lua
run ornament_mesh "$LUAJIT" tests/test_ornament_meshes.lua
run divider_ogive "$LUAJIT" tests/test_divider_ogive_meshes.lua
run canvas_bake   "$LUAJIT" tests/test_canvas_bake.lua
run persona_hand  "$LUAJIT" tests/test_persona_handover.lua
run hand_order    "$LUAJIT" tests/test_hand_type_order.lua
run hud_econ_cache "$LUAJIT" tests/test_hud_and_economy_cache.lua
run panel_ring    "$LUAJIT" tests/test_panel_shadow_ring.lua
run scallop_tan   "$LUAJIT" tests/test_scallop_tangency.lua
run hot_reload    "$LUAJIT" tests/test_overlay_watchdog.lua
run pack_claim    "$LUAJIT" tests/test_pack_claim.lua
run acquire_booster "$LUAJIT" tests/test_acquire_booster_pick.lua
run acquire_atlas "$LUAJIT" tests/test_acquire_atlas_fallback.lua
run acquire_timer "$LUAJIT" tests/test_acquire_timer_lane.lua
run acquire_scale "$LUAJIT" tests/test_acquire_mini_scale.lua
run acquire_sticker "$LUAJIT" tests/test_acquire_stickers.lua
run acquire_sprite "$LUAJIT" tests/test_acquire_sprite_geometry.lua
run pack_geom     "$LUAJIT" tests/test_pack_geometry.lua
run pack_stdhero  "$LUAJIT" tests/test_pack_standard_hero.lua
run acquire_geom  "$LUAJIT" tests/test_acquire_geometry.lua
run acquire_morph "$LUAJIT" tests/test_acquire_panel_morph.lua
run showcase_corr "$LUAJIT" tests/test_showcase_corridor.lua
run mini_quad      "$LUAJIT" tests/test_mini_quad_cache.lua
run acquire_layout "$LUAJIT" tests/test_acquire_compact_layout.lua
run acquire_access "$LUAJIT" tests/test_acquire_accessibility.lua
run acquire_pcall  "$LUAJIT" tests/test_acquire_pcall_diagnostics.lua
run use_card_rcpt  "$LUAJIT" tests/test_use_card_receipt.lua
run acquire_anim   "$LUAJIT" tests/test_acquire_animation_guard.lua
run voucher_show   "$LUAJIT" tests/test_voucher_showcase.lua
run voucher_tray  "$LUAJIT" tests/test_voucher_tray.lua
run acquire_verbs  "$LUAJIT" tests/test_acquisition_verbs.lua
run toast_countdown "$LUAJIT" tests/test_toast_countdown.lua
run edition_shader "$LUAJIT" tests/test_edition_shaders.lua
run deadlock      "$LUAJIT" tests/run_deadlock.lua
run gameover_synth "$LUAJIT" tests/run_gameover_synth.lua
run roundtrip     "$LUAJIT" tests/run_roundtrip.lua
run staging       "$LUAJIT" tests/run_staging.lua
run staging_repl  "$LUAJIT" tests/test_staging_replace.lua
run io_failure    "$LUAJIT" tests/test_io_failure.lua
run inbox_rot     "$LUAJIT" tests/test_inbox_rotation.lua
run inbox_malformed "$LUAJIT" tests/test_inbox_malformed_line.lua
run target_name   "$LUAJIT" tests/test_target_name_guard.lua
run glow_timing   "$LUAJIT" tests/test_glow_timing.lua
run glow_band     "$LUAJIT" tests/test_glow_neuro_band.lua
run glow_pool     "$LUAJIT" tests/test_glow_evil_pool.lua
run event_flags   "$LUAJIT" tests/test_event_flags.lua
run engine_check  "$LUAJIT" ../scripts/engine_check.lua
run gate_clocks   "$LUAJIT" ../scripts/gate_clock_check.lua
run gate_clock_ct "$LUAJIT" tests/test_gate_clocks.lua
run clock_stalls  "$LUAJIT" tests/test_clock_stalls.lua
run clock_carry_int "$LUAJIT" tests/test_clock_carry_integral.lua
run paused_overlay "$LUAJIT" tests/test_paused_overlay.lua
run blind_juice   "$LUAJIT" tests/test_blind_juice.lua
run anim_settle   "$LUAJIT" tests/test_anim_settle.lua
run gfx_drain     "$LUAJIT" tests/test_gfx_drain_hooks.lua
run engine_intf   "$LUAJIT" tests/test_engine_interference.lua
run palette_ctr   "$LUAJIT" tests/test_palette_contrast.lua
run buy_clock     "$LUAJIT" tests/test_buy_clock.lua
run fuzz          "$LUAJIT" tests/run_fuzz.lua
run anti_regress  "$LUAJIT" tests/test_anti_regress.lua
run rules_scope   "$LUAJIT" tests/test_game_rules_scope.lua
run ui_text_memo "$LUAJIT" tests/test_ui_text_memo.lua
run carousel_memo "$LUAJIT" tests/test_carousel_memo.lua
run carousel_phase "$LUAJIT" tests/test_carousel_phase.lua
run ui_reaper     "$LUAJIT" tests/test_ui_reaper.lua
run json_wire     "$LUAJIT" tests/run_json.lua
run protocol      "$LUAJIT" tests/test_protocol.lua
run wire_envelope "$LUAJIT" tests/test_wire_envelope.lua
run append_idem   "$LUAJIT" tests/test_outbox_append_idempotence.lua
if [ -f "../neuro-bridge-rs/src/main.rs" ]; then
  run bridge_reset  "$LUAJIT" tests/test_bridge_register_reset.lua
  if command -v cargo >/dev/null 2>&1; then
    run bridge_wire cargo test --quiet --manifest-path ../neuro-bridge-rs/Cargo.toml
  else
    skip bridge_wire "cargo not installed, the Rust bridge tests did not run"
  fi
else
  skip bridge_reset "neuro-bridge-rs not checked out beside neuro-game, the wire-contract cross-check and the Rust bridge tests did not run"
fi
run force_machine  "$LUAJIT" tests/test_force_machine.lua
run wire_rewrite  "$LUAJIT" tests/test_force_wire_text_rewrite.lua
run force_overlap "$LUAJIT" tests/test_force_overlap_guard.lua
run torn_tier     "$LUAJIT" tests/test_torn_remainder_tier.lua
run no_name       "$LUAJIT" tests/test_missing_action_name.lua
run stall_sig     "$LUAJIT" tests/test_stall_signature.lua
run liveness_esc  "$LUAJIT" tests/test_liveness_escalation.lua
run wire_guard    "$LUAJIT" tests/test_wire_guard_surface.lua
run tx_settle     "$LUAJIT" tests/test_tx_claim_store_atomic.lua
run unmodelled    "$LUAJIT" tests/test_unmodelled_state_guard.lua
run deliv_bound   "$LUAJIT" tests/test_force_delivery_bound.lua
run decision_delta "$LUAJIT" tests/test_decision_delta.lua
run context_lifetime "$LUAJIT" tests/test_context_lifetime_sdk.lua
run reg_gate      "$LUAJIT" tests/test_registration_gate.lua
run confirm_rb    "$LUAJIT" tests/test_confirm_rollback.lua
run resv_owner    "$LUAJIT" tests/test_reservation_ownership.lua
run tport_reset   "$LUAJIT" tests/test_transport_reset_release.lua
run provider_err  "$LUAJIT" tests/test_provider_error_surfacing.lua
run force_sdk_life "$LUAJIT" tests/test_sdk_force_lifecycle.lua
run force_super_wire "$LUAJIT" tests/test_force_supersede_wire.lua
run force_cadence  "$LUAJIT" tests/test_force_cadence.lua
run engine_gate    "$LUAJIT" tests/test_engine_gate_failsafe.lua
run force_atomic   "$LUAJIT" tests/test_force_send_atomicity.lua
run force_window   "$LUAJIT" tests/test_force_window_contract.lua
run force_win_obj  "$LUAJIT" tests/test_force_window_object.lua
run force_win_shdw "$LUAJIT" tests/test_force_window_shadow.lua
run force_win_out  "$LUAJIT" tests/test_force_window_outside_offer.lua
run force_decision "$LUAJIT" tests/test_force_decisions.lua
run sdk_integration "$LUAJIT" tests/test_sdk_lifecycle_integration.lua
run sdk_reconnect "$LUAJIT" tests/test_sdk_reconnect.lua
run journal_recov "$LUAJIT" tests/test_action_journal_recovery.lua
run tx_cache      "$LUAJIT" tests/test_tx_cache.lua
run reset         "$LUAJIT" tests/test_reset.lua
run reset_staged  "$LUAJIT" tests/test_reset_staged_action.lua
run framing       "$LUAJIT" tests/run_framing.lua
run filter        "$LUAJIT" tests/test_filter.lua
run containment   "$LUAJIT" tests/test_containment.lua
run readiness     "$LUAJIT" tests/test_readiness.lua
run hand_facts    "$LUAJIT" tests/test_hand_facts.lua
run boss_mech     "$LUAJIT" tests/test_boss_mechanics.lua
run boss_records  "$LUAJIT" tests/test_boss_records.lua
run boss_plan     "$LUAJIT" tests/test_boss_plan.lua
run sf_index      "$LUAJIT" tests/test_straight_flush_ix.lua
run hand_perfect  "$LUAJIT" tests/test_hand_perfect.lua
run hand_estimate "$LUAJIT" tests/test_hand_estimate.lua
run hand_order_shuffle "$LUAJIT" tests/test_hand_order_shuffle.lua
run readable_hygiene "$LUAJIT" tests/test_context_readable_hygiene.lua
run sdk_compliance "$LUAJIT" tests/test_sdk_compliance.lua
run schema_surface "$LUAJIT" tests/test_action_schema_surface.lua
run label_refs    "$LUAJIT" tests/test_label_reference_integrity.lua
run action_ack     "$LUAJIT" tests/test_action_ack_contract.lua
run action_reg_ctr  "$LUAJIT" tests/test_action_registration_contract.lua
run force_win_rej  "$LUAJIT" tests/test_force_window_survives_rejection.lua
run rereg_window   "$LUAJIT" tests/test_reregister_all_window.lua
run action_receipt "$LUAJIT" tests/test_action_receipt.lua
run receipt_disp   "$LUAJIT" tests/test_receipt_dispatcher.lua
run exec_contract  "$LUAJIT" tests/test_execution_contract_completeness.lua
run exec_noops     "$LUAJIT" tests/test_execution_noop_detection.lua
run highlight_owner "$LUAJIT" tests/test_highlight_ownership.lua
run force_pack_slot "$LUAJIT" tests/test_force_pack_slot_snapshot.lua
run force_query_prefix "$LUAJIT" tests/test_force_query_state_prefix.lua
run crash_save    "$LUAJIT" tests/test_crash_guard_save.lua
run utils_norm    "$LUAJIT" tests/test_utils_normalization.lua
run visible_hands "$LUAJIT" tests/test_visible_hand_names.lua
run mod_paths     "$LUAJIT" tests/test_mod_paths.lua
run sell_receipt  "$LUAJIT" tests/test_sell_receipt.lua
run pack_area     "$LUAJIT" tests/test_pack_area.lua
run crash_guards  "$LUAJIT" tests/test_crash_guards.lua
run metrics       "$LUAJIT" tests/test_metrics.lua
run trans_guard   "$LUAJIT" tests/test_transition_guard.lua
run block_play_force "$LUAJIT" tests/test_block_play_force.lua
run builder_auth  "$LUAJIT" tests/test_force_builder_authority.lua
run settle_defer  "$LUAJIT" tests/test_force_settling_defer.lua
run router_latch  "$LUAJIT" tests/test_force_router_latch_lifecycle.lua
run silence_paths "$LUAJIT" tests/test_silence_paths.lua
run rules_gate    "$LUAJIT" tests/test_rules_core_gate.lua
run play_guard    "$LUAJIT" tests/test_play_guardrail.lua
run play_size     "$LUAJIT" tests/test_play_size_contract.lua
run adv_limits    "$LUAJIT" tests/test_advertised_limits.lua
run hand_identity "$LUAJIT" tests/test_hand_commit_identity.lua
run confirm_compose "$LUAJIT" tests/test_confirm_play_compose.lua
run confirm_tool  "$LUAJIT" tests/test_confirm_play_tool.lua
run weak_final    "$LUAJIT" tests/test_forced_play_weak_pause.lua
run latch_prec    "$LUAJIT" tests/test_confirm_latch_precedence.lua
run loop_escape   "$LUAJIT" tests/test_loop_escape.lua
run press_scope   "$LUAJIT" tests/test_repeat_pressure_scope.lua
run gate_pressure "$LUAJIT" tests/test_gate_pressure_agreement.lua
run schema_gate   "$LUAJIT" tests/test_schema_gate_order.lua
run force_ack     "$LUAJIT" tests/test_force_ack_phase.lua
run force_liveness "$LUAJIT" tests/test_force_liveness_watchdog.lua
run force_live_wire "$LUAJIT" tests/test_force_liveness_wire.lua
run force_wire_audit "$LUAJIT" tests/test_force_wire_audit.lua
run sdk_wire_audit "$LUAJIT" tests/test_sdk_wire_audit.lua
run gate_ledgers  "$LUAJIT" tests/test_dispatch_gate_ledgers.lua
run abandon_oblig "$LUAJIT" tests/test_abandon_obligation.lua
run result_ledger "$LUAJIT" tests/test_result_ledger.lua
run inbound_oblig "$LUAJIT" tests/test_inbound_obligation.lua
run protocol_fuzz "$LUAJIT" tests/test_protocol_fuzz.lua
run ack_taxonomy  "$LUAJIT" tests/test_ack_reason_taxonomy.lua
run action_registry "$LUAJIT" tests/test_action_registry.lua
run registry_measure "$LUAJIT" tests/test_registry_measure.lua
run registry_reconcile "$LUAJIT" tests/test_registry_reconcile.lua
run schema_unique "$LUAJIT" tests/test_schema_validate_unique.lua
run set_plan_gate "$LUAJIT" tests/test_set_plan_gate.lua
run plan_tx       "$LUAJIT" tests/test_plan_transaction.lua
run plan_provenance "$LUAJIT" tests/test_plan_provenance.lua
run plan_tx_stale "$LUAJIT" tests/test_plan_tx_stale.lua
run plan_gate_surv "$LUAJIT" tests/test_plan_gate_survival.lua
run shop_lock_visibility "$LUAJIT" tests/test_shop_lock_visibility.lua
run play_hints    "$LUAJIT" tests/test_play_hints.lua
run audit_dedup   "$LUAJIT" tests/test_audit_dedup.lua
run edition_split "$LUAJIT" tests/test_edition_split.lua
run badge_fx      "$LUAJIT" tests/test_badge_fx.lua
run badge_native  "$LUAJIT" tests/test_badge_native_art.lua
run dynamic_mult  "$LUAJIT" tests/test_dynamic_mult.lua
run scaling_curve "$LUAJIT" tests/test_scaling_curve.lua
run round_eval_earn "$LUAJIT" tests/test_round_eval_earnings.lua
run filter_edge_cases "$LUAJIT" tests/test_filter_edge_cases.lua
run contained_ty  "$LUAJIT" tests/test_contained_types.lua
run plan_cont     "$LUAJIT" tests/test_plan_continuity.lua
run sell_guard    "$LUAJIT" tests/test_sell_guardrail.lua
run pack_sell     "$LUAJIT" tests/test_pack_sell_gate.lua
run joker_intent   "$LUAJIT" tests/test_joker_intents.lua
run ctx_prune     "$LUAJIT" tests/test_context_pruning.lua
run voucher_deliv "$LUAJIT" tests/test_voucher_delivery.lua
run voucher_confirm "$LUAJIT" tests/test_voucher_confirm.lua
run stable_epoch  "$LUAJIT" tests/test_stable_epoch.lua
run stable_live   "$LUAJIT" tests/test_stable_live_values.lua
run inline_accum  "$LUAJIT" tests/test_inline_accumulator_stability.lua
run gloss_epoch   "$LUAJIT" tests/test_glossary_epoch.lua
run interest_gate  "$LUAJIT" tests/test_interest_gate.lua
run interest_price "$LUAJIT" tests/test_interest_price.lua
run shop_visit    "$LUAJIT" tests/test_shop_visit_continuity.lua
run shop_entry    "$LUAJIT" tests/test_shop_entry_snapshot.lua
run slot_buffer    "$LUAJIT" tests/test_slot_buffer.lua
run plan_direct    "$LUAJIT" tests/test_plan_direct.lua
run buy_name      "$LUAJIT" tests/test_buy_name_resolve.lua
run setup_deck    "$LUAJIT" tests/test_setup_deck_live.lua
run hint_key_shapes "$LUAJIT" tests/test_hint_key_shapes.lua
run round_unit "$LUAJIT" tests/test_round_unit.lua
run fact_owner    "$LUAJIT" tests/test_fact_ownership.lua
run shop_afford   "$LUAJIT" tests/test_shop_afford_split.lua
run synth_game    "$LUAJIT" tests/test_synthetic_game.lua
run scoring       "$LUAJIT" tests/test_scoring.lua
run ability_field "$LUAJIT" tests/test_ability_fields.lua
run cond_labels   "$LUAJIT" tests/test_conditional_effect_labels.lua
run extra_gates   "$LUAJIT" tests/test_extra_gate_model.lua
run self_plan     "$LUAJIT" tests/test_self_plan.lua
run facedown      "$LUAJIT" tests/test_facedown.lua
run ctx_quality   "$LUAJIT" tests/test_context_quality.lua
run ctx_readable  "$LUAJIT" tests/test_context_readable.lua
run ctx_cache_rewind "$LUAJIT" tests/test_context_compact_cache_rewind.lua
run rewards       "$LUAJIT" tests/test_rewards.lua
run consumables   "$LUAJIT" tests/test_consumables.lua
run pack_planet   "$LUAJIT" tests/test_pack_planet_facts.lua
run shop_planet   "$LUAJIT" tests/test_shop_planet_facts.lua
run xmult_state   "$LUAJIT" tests/test_xmult_state.lua
run order_req     "$LUAJIT" tests/test_joker_order_requirement.lua
run placeholder_guess_order "$LUAJIT" tests/test_placeholder_guess_order.lua
run vanilla_fidel "$LUAJIT" tests/test_vanilla_fixture_fidelity.lua
run fx_bijection  "$LUAJIT" tests/test_effect_registry_bijection.lua
run cross_scope   "$LUAJIT" tests/test_cross_scope_ceiling.lua
run held_scope    "$LUAJIT" tests/test_held_scope_selection.lua
run fx_coverage   "$LUAJIT" tests/test_effect_coverage_gate.lua
run boss_ceiling  "$LUAJIT" tests/test_boss_ceiling.lua
run card_scan     "$LUAJIT" tests/test_card_scan.lua
run carddex       "$LUAJIT" tests/test_carddex.lua
run selftest      "$LUAJIT" tests/test_selftest.lua
run selftest_build "$LUAJIT" tests/run_selftest_build.lua

# First-run and action-contract checks.
run action_contract "$LUAJIT" tests/test_action_contracts.lua
run payload_render "$LUAJIT" tests/test_action_payload_render.lua
run avail_lazy    "$LUAJIT" tests/test_availability_lazy_bind.lua
run selb_ui_guard  "$LUAJIT" tests/test_select_blind_ui_guard.lua
run force_avail    "$LUAJIT" tests/test_force_availability_parity.lua
run lifecycle_ctr  "$LUAJIT" tests/test_lifecycle_contracts.lua
run plan_scope    "$LUAJIT" tests/test_plan_scope_freshness.lua
run semantic_ctr   "$LUAJIT" tests/test_semantic_contracts.lua
run joker_tag_req  "$LUAJIT" tests/test_joker_tag_requirement.lua
run registry_full  "$LUAJIT" tests/test_registry_completeness.lua
run action_surface  "$LUAJIT" tests/test_action_surface.lua
run prose_offer     "$LUAJIT" tests/test_force_prose_offer.lua
run registry_default "$LUAJIT" tests/test_registry_default_availability.lua
run transition_track "$LUAJIT" tests/test_transition_tracking.lua
run failure_taxonomy "$LUAJIT" tests/test_failure_taxonomy.lua
run first_run_rep  "$LUAJIT" tests/test_first_run_replay.lua
run contract_drift "$LUAJIT" tests/test_contract_drift.lua
# Context rendering checks use generated states and reject crashes or unexpected
# duplication between sections.
run dup_scan      env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_dup_scan.lua 20260722 3000
# Stable-context emission checks reject duplicate sends and over-suppression.
run emit_scan     env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_emit_scan.lua 20260722 3000
# Action-availability checks reject targets that execution preflight cannot accept.
run stale_scan    env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_stale_scan.lua 20260722 3000
# Rejection-correction checks ensure user-facing messages omit transport details.
run correction_scan env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_correction_scan.lua 20260722 2000
# Action-offer checks ensure displayed actions match the SDK and decision-window rules.
run offer_scan    env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_offer_scan.lua 20260723 3000
# Dead-export scan: module functions with no dotted call and no matching string
# literal (the codebase dispatches actions and context getters by name).
run deadexport    env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_deadexport_scan.lua
run deadexp_scope  "$LUAJIT" tests/test_deadexport_scope.lua
# SHOP base hand values, rank-chip glossary dedup, and util.once session-store scope: SHOP base hand values, rank-chip glossary dedup, util.once session-store scope.
run hint_registry "$LUAJIT" tests/test_hint_registry.lua
run context_delivery "$LUAJIT" tests/test_context_delivery.lua
run correction_ch "$LUAJIT" tests/test_correction_channel.lua
run guard_confirm "$LUAJIT" tests/test_guarded_confirmation_restate.lua
run confirm_turn  "$LUAJIT" tests/test_confirm_turn_payload.lua
run retry_budget  "$LUAJIT" tests/test_force_retry_budget.lua
run result_oblig  "$LUAJIT" tests/test_result_delivery_obligation.lua
run derivable_par "$LUAJIT" tests/test_derivable_parameters.lua
run ctx_cache_deck "$LUAJIT" tests/test_ctx_cache_deck_modifiers.lua
run hint_reask    "$LUAJIT" tests/test_hint_reask_cadence.lua
run hidden_deriv  "$LUAJIT" tests/test_hidden_fact_derivability.lua
run round_eval_ante "$LUAJIT" tests/test_round_eval_ante.lua
run ui_memo       "$LUAJIT" tests/test_ui_text_memo_invalidation.lua
run notation      "$LUAJIT" tests/test_action_notation.lua
run wire_notation "$LUAJIT" tests/test_wire_notation.lua
run shop_landing  "$LUAJIT" tests/test_shop_joker_landing.lua
run pack_facts    "$LUAJIT" tests/test_pack_payload_facts.lua
run chip_values   "$LUAJIT" tests/test_card_chip_values.lua
run fixture_lv    "$LUAJIT" tests/test_fixture_loc_vars.lua
run force_fresh   "$LUAJIT" tests/test_force_freshness.lua
run force_census  "$LUAJIT" tests/test_force_section_census.lua
run force_budget  "$LUAJIT" tests/test_force_size_budget.lua
# The same three audits, re-run on the actions/force frame a real Bridge wrote to the outbox.
run wire_frame    "$LUAJIT" tests/test_force_wire_frame.lua
run reask_parity  "$LUAJIT" tests/test_reask_parity.lua
run act_examples  "$LUAJIT" tests/test_action_example_source.lua
run confirm_hidden "$LUAJIT" tests/test_confirm_hidden_derivability.lua
run close_order   "$LUAJIT" tests/test_hand_facts_close_order.lua
run cache_board   "$LUAJIT" tests/test_ctx_cache_board_scope.lua
run deadexp_style "$LUAJIT" tests/test_deadexport_styles.lua
run untagged_name "$LUAJIT" tests/test_untagged_joker_naming.lua
run zeroed_parity "$LUAJIT" tests/test_zeroed_annotation_parity.lua
run shop_tag_ix   "$LUAJIT" tests/test_shop_tag_index_and_reask.lua
run bs_resource   "$LUAJIT" tests/test_blind_select_resource_truth.lua
run possess_vis   "$LUAJIT" tests/test_possession_visibility.lua
run held_bound    "$LUAJIT" tests/test_held_ceiling_deck_bound.lua
run startup_ledg  "$LUAJIT" tests/test_startup_retry_ledger.lua
run startup_win   "$LUAJIT" tests/test_startup_window_wire_order.lua
run ts_origin     "$LUAJIT" tests/test_transport_session_origin.lua
run drawpool      "$LUAJIT" tests/test_draw_pool_derivability.lua
run drawnote      "$LUAJIT" tests/test_draw_note_derivability.lua
run decision_truth "$LUAJIT" tests/test_decision_point_truth.lua
run offer_choice  "$LUAJIT" tests/test_offered_payload_choice.lua
run ready_value   "$LUAJIT" tests/test_ready_candidate_value.lua
run section_ref   "$LUAJIT" tests/test_query_section_reference.lua
run joker_text_once "$LUAJIT" tests/test_joker_text_once.lua
run sh_rules_cad  "$LUAJIT" tests/test_sh_rules_cadence.lua
run joker_hits    "$LUAJIT" tests/test_joker_hits.lua
run joker_proj    "$LUAJIT" tests/test_joker_projection_vanilla.lua
run retriggers    "$LUAJIT" tests/test_retriggers.lua
run joker_agg0    "$LUAJIT" tests/test_joker_agg_zero.lua
run roster_uncond "$LUAJIT" tests/test_roster_unconditional.lua
run joker_order_f "$LUAJIT" tests/test_joker_order_fact.lua
run hint_channel  "$LUAJIT" tests/test_hint_channel.lua
run gate_contract "$LUAJIT" tests/test_gate_contract.lua
run hint_cadence  "$LUAJIT" tests/test_hint_cadence.lua
run once_scope    "$LUAJIT" tests/test_once_scope.lua
run shop_primer   "$LUAJIT" tests/test_shop_boss_primer.lua
run prose_truth   "$LUAJIT" tests/test_joker_prose_truth.lua
run tag_facts     "$LUAJIT" tests/test_tag_facts.lua
run live_source   "$LUAJIT" tests/test_live_game_source.lua
run modded        "$LUAJIT" tests/test_modded_content.lua
run truth_claims  "$LUAJIT" tests/test_ctx_truth_claims.lua
run selftest_cases "$LUAJIT" tests/test_selftest_case_guards.lua
# Cross-channel redundancy: gates only the channels Neuro receives in one prompt. The FORCE_QUERY
# pairings are the self-contained force query working as designed, so they are reported, not gated.
run ctx_dump      env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_context.lua
# Keeps silent skips and shared scratch paths from coming back -- see tests/skip_ledger.lua.
run hand_shape     "$LUAJIT" tests/test_hand_shape_boundary.lua
run hand_level     "$LUAJIT" tests/test_hand_level_truth.lua
run draw_odds      "$LUAJIT" tests/test_draw_odds_truth.lua
run draw_pile_acc  "$LUAJIT" tests/test_draw_pile_accounting.lua
run scoring_cap    "$LUAJIT" tests/test_scoring_hand_cap.lua
run joker_hidden   "$LUAJIT" tests/test_joker_hidden_subtotal.lua
run deck_commit    "$LUAJIT" tests/test_deck_commit_scope.lua
run retained_scope "$LUAJIT" tests/test_retained_scope.lua
run boss_reveal    "$LUAJIT" tests/test_shop_boss_reveal_gate.lua
run count_agree    "$LUAJIT" tests/test_count_agreement.lua
run harness_hyg   "$LUAJIT" tests/test_harness_hygiene.lua

# A census entry nothing executes is an entry that stopped guarding anything.
if [ "$census_write" = "1" ]; then
  printf '== census written to %s (%d entries) ==\n' "$CENSUS_OUT" "$(wc -l < "$CENSUS_OUT")"
  if [ -n "$census_drops" ]; then
    printf '== CHECK COUNTS THAT DROPPED ==%s\n' "$census_drops"
    case "$census_drops" in
      *REFUSED*)
        echo "   a refused drop keeps the old floor, so the next gate run fails until the loss is read"
        exit 1 ;;
    esac
  fi
else
  for c_label in "${!CENSUS_MIN[@]}"; do
    if [ -z "${CENSUS_SEEN[$c_label]-}" ]; then
      printf '  FAIL %-16s %s\n' "$c_label" "recorded in $CENSUS but no run line executed it"
      fail=1
    fi
  done
fi

if [ $fail -ne 0 ]; then
  echo "== FAILURES PRESENT =="
  exit 1
fi
if [ $skipped -ne 0 ]; then
  printf '== INCOMPLETE: %d SKIP ENTR(IES), %d COUNTED CHECK(S) NOT RUN ==%s\n' \
    "$skipped" "$lost_checks" "$skips"
  if [ "${REQUIRE_COMPLETE:-0}" = "1" ] || [ $incomplete -ne 0 ]; then
    echo "   REQUIRE_COMPLETE=1: treating skipped checks as a failure"
    exit 3
  fi
  echo "   install the missing dependency, or set REQUIRE_COMPLETE=1 to make this fatal"
  exit 0
fi
echo "== ALL GREEN =="
exit 0
