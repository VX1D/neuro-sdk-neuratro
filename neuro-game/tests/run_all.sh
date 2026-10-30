#!/usr/bin/env bash
# Release gate: run the whole offline suite under luajit. Exit non-zero on any failure or skip.
# Usage: cd neuro-game && bash tests/run_all.sh (set REQUIRE_COMPLETE=0 to allow skips locally)
# Exit codes: 0 clean, 1 failures, 2 bad invocation, 3 clean but incomplete under REQUIRE_COMPLETE.
set -u
REQUIRE_COMPLETE="${REQUIRE_COMPLETE:-1}"
cd "$(dirname "$0")/.." || exit 2
LUAJIT_REQUEST="${LUAJIT:-luajit}"
PATH="/usr/bin:/bin"
export PATH
case "$LUAJIT_REQUEST" in
  ''|*[!A-Za-z0-9_./+-]*) echo "invalid LUAJIT executable name" >&2; exit 2 ;;
esac
LUAJIT="$(command -v "$LUAJIT_REQUEST" 2>/dev/null || true)"
[ -x "$LUAJIT" ] || { echo "LUAJIT executable not found or not executable" >&2; exit 2; }
unset LUA_CPATH LUA_CPATH_5_1 LUA_PATH LUA_PATH_5_1
export LUA_PATH="./?.lua;./?/init.lua"
unset RUSTC RUSTDOC RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER RUSTFLAGS RUSTDOCFLAGS
unset CARGO_BUILD_RUSTC CARGO_BUILD_RUSTC_WRAPPER CARGO_ENCODED_RUSTFLAGS CARGO_BUILD_TARGET
unset CARGO_HOME CARGO_CONFIG CARGO_TARGET_DIR CARGO_NET_OFFLINE CARGO_NET_RETRY
unset CARGO_NET_GIT_FETCH_WITH_CLI CARGO_HTTP_PROXY CARGO_HTTP_TIMEOUT CARGO_HTTP_CHECK_REVOKE
unset CARGO_REGISTRIES_CRATES_IO_PROTOCOL CARGO_REGISTRIES_CRATES_IO_INDEX
unset RUSTUP_TOOLCHAIN RUSTUP_HOME LD_PRELOAD LD_LIBRARY_PATH
export LC_ALL=C LANG=C
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

# Every command owns its pass/fail result. The runner captures output for diagnostics, but it never
# treats a printed summary, receipt, or side-channel marker as completion evidence.
record_skip() {  # record_skip <label> <reason> [lost-check-count]
  skipped=$((skipped + 1))
  lost_checks=$((lost_checks + ${3:-0}))
  skips="${skips}
    $1: $2"
}

skip() {  # skip <label> <reason>
  printf '  SKIP %-16s %s\n' "$1" "$2"
  record_skip "$1" "$2"
}

echo "== neuro-game offline suite =="
run() {  # run <label> <cmd...>
  local label="$1"; shift
  local out rc summary
  out="$("$@" 2>&1)"
  rc=$?
  summary="$(printf '%s\n' "$out" | grep -iE 'PASS,|passed|FAILS=|ROUNDTRIP_FAILS|====.*(PASS|FAIL|probes|iters)' | tail -1)"

  # A Lua-side skip is a lost check, not a pass. tests/skip_ledger.lua emits one
  # "==SKIP== <count> <label> -- <reason>" line per group of checks that did not run.
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

  if [ "$rc" -eq 3 ] && [ "$lost" -ne 0 ]; then
    printf '  SKIP %-16s %s\n' "$label" "REQUIRE_COMPLETE=1: $lost check(s) could not run"
    incomplete=1
  elif [ "$rc" -ne 0 ]; then
    printf '  FAIL %-16s %s\n' "$label" "$summary"
    printf '%s\n' "$out" | grep -iE 'FAIL|ERROR|THREW|panic' | head -20 | sed 's/^/       /'
    fail=1
  elif [ "$lost" -ne 0 ]; then
    printf '  SKIP %-16s %s  [-%d check(s)]\n' "$label" "$summary" "$lost"
  else
    printf '  ok   %-16s %s\n' "$label" "$summary"
  fi
}
run gameplay_journal "$LUAJIT" tests/test_gameplay_journal.lua
run decision_evidence "$LUAJIT" tests/test_verified_decision_evidence.lua
run last_play_cash_out "$LUAJIT" tests/test_last_play_after_cash_out.lua
run zeroed_hand_report "$LUAJIT" tests/test_zeroed_hand_report.lua
run joker_observe "$LUAJIT" tests/test_joker_observations.lua
run joker_hits_debuffed "$LUAJIT" tests/test_joker_hits_debuffed_notice.lua
run observers_cg_on "$LUAJIT" tests/test_joker_observers_without_crash_guards.lua on
run observers_cg_off "$LUAJIT" tests/test_joker_observers_without_crash_guards.lua off
run hud_surfaces  "$LUAJIT" tests/test_hud_surfaces.lua
run hand_order    "$LUAJIT" tests/test_hand_type_order.lua
run pack_geom     "$LUAJIT" tests/test_pack_geometry.lua
run use_outcome    "$LUAJIT" tests/test_consumable_outcome.lua
run deadlock      "$LUAJIT" tests/run_deadlock.lua
run gameover_synth "$LUAJIT" tests/run_gameover_synth.lua
run roundtrip     "$LUAJIT" tests/run_roundtrip.lua
run staging       "$LUAJIT" tests/run_staging.lua
run inbox_rot     "$LUAJIT" tests/test_inbox_rotation.lua
run inbox_malformed "$LUAJIT" tests/test_inbox_malformed_line.lua
run staged_visibility "$LUAJIT" tests/test_staged_visibility.lua
run clock_stalls  "$LUAJIT" tests/test_clock_stalls.lua
run paused_overlay "$LUAJIT" tests/test_paused_overlay.lua
run exact_select  "$LUAJIT" tests/test_exact_hand_selection.lua
run use_verdict   "$LUAJIT" tests/test_consumable_use_verdict.lua
run use_gate      "$LUAJIT" tests/test_engine_use_gate.lua
run game_heartbeat "$LUAJIT" tests/test_game_heartbeat.lua
run buy_clock     "$LUAJIT" tests/test_buy_clock.lua
run fuzz          "$LUAJIT" tests/run_fuzz.lua
run anti_regress  "$LUAJIT" tests/test_anti_regress.lua
run wire_envelope "$LUAJIT" tests/test_wire_envelope.lua
run stable_action_protocol "$LUAJIT" tests/test_stable_action_protocol.lua
if [ -f "../neuro-bridge-rs/src/main.rs" ]; then
  run bridge_reset  "$LUAJIT" tests/test_bridge_register_reset.lua
  if command -v cargo >/dev/null 2>&1; then
    run bridge_wire cargo test --quiet --manifest-path ../neuro-bridge-rs/Cargo.toml
    # The relay is held to rustfmt and to a clippy with no warnings; a missing component is a
    # lost check, not a pass.
    if cargo fmt --version >/dev/null 2>&1; then
      run bridge_fmt cargo fmt --check --manifest-path ../neuro-bridge-rs/Cargo.toml
    else
      skip bridge_fmt "rustfmt not installed, the relay formatting was not checked"
    fi
    if cargo clippy --version >/dev/null 2>&1; then
      run bridge_clippy cargo clippy --quiet --all-targets --manifest-path ../neuro-bridge-rs/Cargo.toml -- -D warnings
    else
      skip bridge_clippy "clippy not installed, the relay lints were not checked"
    fi
  else
    skip bridge_wire "cargo not installed, the Rust bridge tests did not run"
  fi
else
  skip bridge_reset "neuro-bridge-rs not checked out beside neuro-game, the wire-contract cross-check and the Rust bridge tests did not run"
  skip bridge_wire  "neuro-bridge-rs not checked out beside neuro-game, the Rust bridge tests did not run"
fi
run outbox_fifo   "$LUAJIT" tests/test_outbox_fifo.lua
run outbox_rot    "$LUAJIT" tests/test_outbox_rotation_fence.lua
run no_name       "$LUAJIT" tests/test_missing_action_name.lua
run liveness_esc  "$LUAJIT" tests/test_liveness_escalation.lua
run liveness_backoff "$LUAJIT" tests/test_liveness_backoff.lua
run wire_guard    "$LUAJIT" tests/test_wire_guard_surface.lua
run unmodelled    "$LUAJIT" tests/test_unmodelled_state_guard.lua
run decision_delta "$LUAJIT" tests/test_decision_delta.lua
run delta_pack_tarot "$LUAJIT" tests/test_delta_pack_tarot.lua
run destruction   "$LUAJIT" tests/test_destruction_log.lua
run reg_gate      "$LUAJIT" tests/test_registration_gate.lua
run tport_reset   "$LUAJIT" tests/test_transport_reset_release.lua
run force_sdk_life "$LUAJIT" tests/test_sdk_force_lifecycle.lua
run engine_gate    "$LUAJIT" tests/test_engine_gate_failsafe.lua
run force_atomic   "$LUAJIT" tests/test_force_send_atomicity.lua
run force_window   "$LUAJIT" tests/test_force_window_contract.lua
run force_win_out  "$LUAJIT" tests/test_force_window_outside_offer.lua
run tool_frames    "$LUAJIT" tests/test_tool_contract_frames.lua
run offer_refs     "$LUAJIT" tests/test_force_offer_references.lua
run tool_wire      "$LUAJIT" tests/test_tool_contract_wire.lua
run overlap_fuzz  "$LUAJIT" tests/test_force_overlap_fuzz.lua
run reconnect_actions "$LUAJIT" tests/test_reconnect_actions.lua
run sdk_integration "$LUAJIT" tests/test_sdk_lifecycle_integration.lua
run hold_confirm_transport "$LUAJIT" tests/test_hold_confirmation_transport.lua
run sdk_reconnect "$LUAJIT" tests/test_sdk_reconnect.lua
run reset_staged  "$LUAJIT" tests/test_reset_staged_action.lua
run containment   "$LUAJIT" tests/test_containment.lua
run hand_facts    "$LUAJIT" tests/test_hand_facts.lua
run boss_plan     "$LUAJIT" tests/test_boss_plan.lua
run readable_hygiene "$LUAJIT" tests/test_context_readable_hygiene.lua
run sdk_compliance "$LUAJIT" tests/test_sdk_compliance.lua
run privacy_regress "$LUAJIT" tests/test_privacy_regressions.lua
run schema_prompt "$LUAJIT" tests/test_schema_prompt.lua
run transport_reg "$LUAJIT" tests/test_transport_registration.lua
run schema_surface "$LUAJIT" tests/test_action_schema_surface.lua
run action_ack     "$LUAJIT" tests/test_action_ack_contract.lua
run action_reg_ctr  "$LUAJIT" tests/test_action_registration_contract.lua
run catalogue_mirror "$LUAJIT" tests/test_catalogue_mirror.lua
run rereg_window   "$LUAJIT" tests/test_reregister_all_window.lua
run receipt_disp   "$LUAJIT" tests/test_receipt_dispatcher.lua
run admission_gates "$LUAJIT" tests/test_admission_gates.lua
run no_continue     "$LUAJIT" tests/test_no_saved_run_continue.lua
run noop_feedback  "$LUAJIT" tests/test_noop_tool_feedback.lua
run sell_receipt  "$LUAJIT" tests/test_sell_receipt.lua
run echo_channel  "$LUAJIT" tests/test_action_echo_channel.lua
run result_refs   "$LUAJIT" tests/test_result_offer_references.lua
run reset_catalog "$LUAJIT" tests/test_run_reset_catalogue.lua
run builder_auth  "$LUAJIT" tests/test_force_builder_authority.lua
run settle_defer  "$LUAJIT" tests/test_force_settling_defer.lua
run silence_paths "$LUAJIT" tests/test_silence_paths.lua
run play_guard    "$LUAJIT" tests/test_play_guardrail.lua
run adv_limits    "$LUAJIT" tests/test_advertised_limits.lua
run confirm_compose "$LUAJIT" tests/test_confirm_play_compose.lua
run play_proposal "$LUAJIT" tests/test_play_proposal.lua
run loop_escape   "$LUAJIT" tests/test_loop_escape.lua
run decision_budget "$LUAJIT" tests/test_decision_budget.lua
run skip_trigger_fact "$LUAJIT" tests/test_skip_trigger_fact.lua
run schema_gate   "$LUAJIT" tests/test_schema_gate_order.lua
run force_ack     "$LUAJIT" tests/test_force_ack_phase.lua
run force_liveness "$LUAJIT" tests/test_force_liveness_watchdog.lua
run unprompted_gap "$LUAJIT" tests/test_unprompted_between_forces.lua
run staged_holds   "$LUAJIT" tests/test_staged_admission_holds.lua
run cancel_notice  "$LUAJIT" tests/test_admitted_cancel_notice.lua
run transient_reask "$LUAJIT" tests/test_transient_reask.lua
run review_paths   "$LUAJIT" tests/test_play_review_paths.lua
run review_wire    "$LUAJIT" tests/test_review_wire_sequence.lua
run gate_ledgers  "$LUAJIT" tests/test_dispatch_gate_ledgers.lua
run inbound_oblig "$LUAJIT" tests/test_inbound_obligation.lua
run protocol_fuzz "$LUAJIT" tests/test_protocol_fuzz.lua
run ack_taxonomy  "$LUAJIT" tests/test_ack_reason_taxonomy.lua
run registry_reconcile "$LUAJIT" tests/test_registry_reconcile.lua
run plan_tx       "$LUAJIT" tests/test_plan_transaction.lua
run plan_review_commit "$LUAJIT" tests/test_plan_review_commit.lua
run plan_provenance "$LUAJIT" tests/test_plan_provenance.lua
run plan_gate_surv "$LUAJIT" tests/test_plan_gate_survival.lua
run plan_guard    "$LUAJIT" tests/test_plan_contract_guard.lua
run run_reset_hook "$LUAJIT" tests/test_run_reset_hook.lua
run screen_catalogue "$LUAJIT" tests/test_screen_catalogue.lua
run window_reg    "$LUAJIT" tests/test_window_registration.lua
run overlay_trans "$LUAJIT" tests/test_overlay_transitional.lua
run card_binding  "$LUAJIT" tests/test_card_binding.lua
run stray_hand_idx  "$LUAJIT" tests/test_stray_hand_indices.lua
run refused_reask "$LUAJIT" tests/test_refused_reask_clock.lua
run force_binding "$LUAJIT" tests/test_force_decision_binding.lua
run bridge_hash_lj20 "$LUAJIT" tests/test_bridge_hash_luajit20.lua
run admission_paths "$LUAJIT" tests/test_admission_paths.lua
run cash_out_ready "$LUAJIT" tests/test_cash_out_ready.lua
run blind_dispose  "$LUAJIT" tests/test_blind_disposable_group.lua
run guide_delivery "$LUAJIT" tests/test_action_guide_delivery.lua
run rules_ante    "$LUAJIT" tests/test_rules_each_ante.lua
run stable_epoch  "$LUAJIT" tests/test_stable_epoch.lua
run gloss_epoch   "$LUAJIT" tests/test_glossary_epoch.lua
run shop_visit_id "$LUAJIT" tests/test_shop_visit_identity.lua
run buy_name      "$LUAJIT" tests/test_buy_name_resolve.lua
run run_setup_src "$LUAJIT" tests/test_run_setup_source.lua
run reroll_price  "$LUAJIT" tests/test_reroll_price_channel.lua
run preflight_msgs  "$LUAJIT" tests/test_preflight_refusals.lua
run sell_hidden_nm  "$LUAJIT" tests/test_sell_refusal_hidden_name.lua
run use_unsettled   "$LUAJIT" tests/test_use_outcome_unsettled.lua
run use_chosen_seat "$LUAJIT" tests/test_use_outcome_chosen_seat.lua
run hidden_ceiling  "$LUAJIT" tests/test_hidden_ceiling_sweep.lua
run hidden_rule_jk  "$LUAJIT" tests/test_hidden_joker_rule_effects.lua
run owed_no_force   "$LUAJIT" tests/test_owed_result_blocks_force.lua
run gate_hidden_rev "$LUAJIT" tests/test_gate_hidden_revision.lua
run force_indep_adm "$LUAJIT" tests/test_force_independent_admission.lua
run secret_hand     "$LUAJIT" tests/test_secret_hand_unnamed.lua
run pack_deal_ready "$LUAJIT" tests/test_pack_deal_readiness.lua
run use_pile_return "$LUAJIT" tests/test_use_effect_pile_return.lua
run saved_round     "$LUAJIT" tests/test_saved_round_channels.lua
run neg_money       "$LUAJIT" tests/test_negative_money_render.lua
run reg_churn       "$LUAJIT" tests/test_registration_churn.lua
run scaling_boss    "$LUAJIT" tests/test_scaling_curve_boss.lua
run delta_held_play "$LUAJIT" tests/test_delta_after_held_play.lua
run decline_channels "$LUAJIT" tests/test_decline_note_channels.lua
run boss_select_rows "$LUAJIT" tests/test_blind_select_boss_rows.lua
run fd_pick_refusal "$LUAJIT" tests/test_facedown_pick_refusal.lua
run refusal_text    "$LUAJIT" tests/test_refusal_text_contract.lua
run challenge_rules "$LUAJIT" tests/test_challenge_rules_channel.lua
run prose_channels  "$LUAJIT" tests/test_prose_channel_fixes.lua
run window_deliver  "$LUAJIT" tests/test_force_window_delivery.lua
run ready_listed  "$LUAJIT" tests/test_review_ready_listed.lua
run result_followup "$LUAJIT" tests/test_force_result_followups.lua
run aura_hidden     "$LUAJIT" tests/test_aura_hidden_target.lua
run hidden_boss     "$LUAJIT" tests/test_hidden_boss_verdict.lua
run pick_showcase   "$LUAJIT" tests/test_pick_showcase_hidden.lua
run can_lines       "$LUAJIT" tests/test_can_lines_offered.lua
run review_can      "$LUAJIT" tests/test_review_can_lines.lua
run reroll_withheld "$LUAJIT" tests/test_reroll_withheld_truth.lua
run joker_reforce   "$LUAJIT" tests/test_joker_order_reforce.lua
run malformed_ref   "$LUAJIT" tests/test_malformed_refusal.lua
run prose_moves     "$LUAJIT" tests/test_prose_channel_moves.lua
run review_hidden   "$LUAJIT" tests/test_review_hidden_selection_ceiling.lua
run sh_channels     "$LUAJIT" tests/test_selecting_hand_channels.lua
run synth_game    "$LUAJIT" tests/test_synthetic_game.lua
run ability_field "$LUAJIT" tests/test_ability_fields.lua
run facedown      "$LUAJIT" tests/test_facedown.lua
run rewards       "$LUAJIT" tests/test_rewards.lua
run cross_scope   "$LUAJIT" tests/test_cross_scope_ceiling.lua
run red_seal_scope "$LUAJIT" tests/test_red_seal_scope.lua
run review_best   "$LUAJIT" tests/test_review_best_value.lua
run shape_review  "$LUAJIT" tests/test_shape_joker_review.lua
run review_brief  "$LUAJIT" tests/test_review_result_brief.lua
run first_send_exec "$LUAJIT" tests/test_first_send_executes.lua
run hold_field_note "$LUAJIT" tests/test_hold_field_note.lua
run menu_prose    "$LUAJIT" tests/test_menu_query_prose.lua
run play_rules_ch "$LUAJIT" tests/test_play_rules_channel.lua
run mark_range    "$LUAJIT" tests/test_mark_draw_range.lua
run mark_near_outs "$LUAJIT" tests/test_mark_near_without_outs.lua
run pack_close_out "$LUAJIT" tests/test_pack_close_outcome.lua

# First-run and action-contract checks.
run lifecycle_ctr  "$LUAJIT" tests/test_lifecycle_contracts.lua
run joker_tag_req  "$LUAJIT" tests/test_joker_tag_requirement.lua
run contract_drift "$LUAJIT" tests/test_contract_drift.lua
# Stable-context emission checks reject duplicate sends and over-suppression.
run emit_scan     env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_emit_scan.lua 20260722 3000
# Action-availability checks reject targets that execution preflight cannot accept.
run stale_scan    env FAIL_ON_FINDINGS=1 "$LUAJIT" tests/dump_stale_scan.lua 20260722 3000
run context_delivery "$LUAJIT" tests/test_context_delivery.lua
run correction_ch "$LUAJIT" tests/test_correction_channel.lua
run retry_budget  "$LUAJIT" tests/test_force_retry_budget.lua
run derivable_par "$LUAJIT" tests/test_derivable_parameters.lua
run hidden_deriv  "$LUAJIT" tests/test_hidden_fact_derivability.lua
run force_fresh   "$LUAJIT" tests/test_force_freshness.lua
run wire_frame    "$LUAJIT" tests/test_force_wire_frame.lua
run wire_markdown "$LUAJIT" tests/test_wire_markdown.lua
run review_marks  "$LUAJIT" tests/test_review_state_markers.lua
run menu_offer    "$LUAJIT" tests/test_menu_offer_consistency.lua
run reask_parity  "$LUAJIT" tests/test_reask_parity.lua
run confirm_hidden "$LUAJIT" tests/test_confirm_hidden_derivability.lua
run cache_board   "$LUAJIT" tests/test_ctx_cache_board_scope.lua
run untagged_name "$LUAJIT" tests/test_untagged_joker_naming.lua
run possess_vis   "$LUAJIT" tests/test_possession_visibility.lua
run query_vis     "$LUAJIT" tests/test_force_query_visibility.lua
run startup_win   "$LUAJIT" tests/test_startup_window_wire_order.lua
run ts_origin     "$LUAJIT" tests/test_transport_session_origin.lua
run drawpool      "$LUAJIT" tests/test_draw_pool_derivability.lua
run drawnote      "$LUAJIT" tests/test_draw_note_derivability.lua
run offer_choice  "$LUAJIT" tests/test_offered_payload_choice.lua
run section_ref   "$LUAJIT" tests/test_query_section_reference.lua
run target_examples "$LUAJIT" tests/test_force_target_examples.lua
run guidance_ctr  "$LUAJIT" tests/test_force_guidance_contract.lua
run stone_identity "$LUAJIT" tests/test_stone_identity_corpus.lua
run wording_generators "$LUAJIT" tests/test_wording_generators.lua
run desc_line_joins "$LUAJIT" tests/test_description_line_joins.lua
run item_fuzz     "$LUAJIT" tests/test_item_context_fuzz.lua
run joker_text_once "$LUAJIT" tests/test_joker_text_once.lua
run joker_order_f "$LUAJIT" tests/test_joker_order_fact.lua
run hint_channel  "$LUAJIT" tests/test_hint_channel.lua
run once_scope    "$LUAJIT" tests/test_once_scope.lua
run offer_stickers "$LUAJIT" tests/test_offer_stickers_emitted.lua
run rescored_jk    "$LUAJIT" tests/test_rescored_jokers.lua
run pool_emitted   "$LUAJIT" tests/test_unplayed_pool_emitted.lua
run unseen_discard "$LUAJIT" tests/test_unseen_discard.lua
run wheel_discard  "$LUAJIT" tests/test_wheel_discard.lua
run delta_hidden   "$LUAJIT" tests/test_decision_delta_hidden_corpus.lua
run scoring_cap    "$LUAJIT" tests/test_scoring_hand_cap.lua
run joker_hidden   "$LUAJIT" tests/test_joker_hidden_subtotal.lua
run deck_commit    "$LUAJIT" tests/test_deck_commit_scope.lua
run boss_reveal    "$LUAJIT" tests/test_shop_boss_reveal_gate.lua
run count_agree    "$LUAJIT" tests/test_count_agreement.lua
run hook_discard   "$LUAJIT" tests/test_hook_discard_effects.lua
run ready_no_score "$LUAJIT" tests/test_ready_no_score.lua


if [ $fail -ne 0 ]; then
  echo "== FAILURES PRESENT =="
  exit 1
fi
if [ $skipped -ne 0 ]; then
  printf '== INCOMPLETE: %d SKIP ENTR(IES), %d COUNTED CHECK(S) NOT RUN ==%s\n' \
    "$skipped" "$lost_checks" "$skips"
  if [ "$REQUIRE_COMPLETE" = "1" ] || [ $incomplete -ne 0 ]; then
    echo "   REQUIRE_COMPLETE=1: treating skipped checks as a failure"
    exit 3
  fi
  echo "   REQUIRE_COMPLETE=0: skips allowed for this local run"
  exit 0
fi
echo "== ALL GREEN =="
exit 0
