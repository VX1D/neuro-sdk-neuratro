#!/usr/bin/env bash
# Release gate: run the whole offline suite under luajit. Exit non-zero on any failure.
# Usage: cd neuro-game && bash tests/run_all.sh
set -u
cd "$(dirname "$0")/.." || exit 2
LUAJIT="${LUAJIT:-luajit}"
fail=0

run() {  # run <label> <cmd...>
  local label="$1"; shift
  local out; out="$("$@" 2>&1)"; local rc=$?
  local summary; summary="$(printf '%s\n' "$out" | grep -iE 'PASS,|passed|FAILS=|FUZZ_FAILS|ROUNDTRIP_FAILS|====.*(PASS|FAIL|probes|iters)' | tail -1)"
  if [ $rc -eq 0 ]; then
    printf '  ok   %-16s %s\n' "$label" "$summary"
  else
    printf '  FAIL %-16s %s\n' "$label" "$summary"
    printf '%s\n' "$out" | grep -iE 'FAIL' | head -20 | sed 's/^/       /'
    fail=1
  fi
}

echo "== neuro-game offline suite =="
run loadcheck     "$LUAJIT" tests/run_loadcheck.lua
run render_ctx    "$LUAJIT" tests/run_render_smoke.lua
run login_anim    "$LUAJIT" tests/run_login_anim.lua
run draw_exec     "$LUAJIT" tests/run_draw_exec.lua
run deadlock      "$LUAJIT" tests/run_deadlock.lua
run gameover_synth "$LUAJIT" tests/run_gameover_synth.lua
run roundtrip     "$LUAJIT" tests/run_roundtrip.lua
run staging       "$LUAJIT" tests/run_staging.lua
run fuzz          "$LUAJIT" tests/run_fuzz.lua
run anti_regress  "$LUAJIT" tests/test_anti_regress.lua
run json_wire     "$LUAJIT" tests/run_json.lua
run protocol      "$LUAJIT" tests/test_protocol.lua
run force_machine  "$LUAJIT" tests/test_force_machine.lua
run tx_cache      "$LUAJIT" tests/test_tx_cache.lua
run reset         "$LUAJIT" tests/test_reset.lua
run framing       "$LUAJIT" tests/run_framing.lua
run filter        "$LUAJIT" tests/test_filter.lua
run containment   "$LUAJIT" tests/test_containment.lua
run readiness     "$LUAJIT" tests/test_readiness.lua
run ctx_quality   "$LUAJIT" tests/test_context_quality.lua
run consumables   "$LUAJIT" tests/test_consumables.lua
run card_scan     "$LUAJIT" tests/test_card_scan.lua
run selftest      "$LUAJIT" tests/test_selftest.lua
run selftest_build "$LUAJIT" tests/run_selftest_build.lua

if [ $fail -eq 0 ]; then
  echo "== ALL GREEN =="
else
  echo "== FAILURES PRESENT =="
fi
exit $fail
