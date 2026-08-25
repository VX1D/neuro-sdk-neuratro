love = setmetatable({ timer = { getTime = function() return 100 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = { NEURO = {}, TIMERS = { REAL = 100 } }

local Lifecycle = require("core.neuro_lifecycle")

local check, fails, checks = require("tests.helpers").collector()

G.NEURO = {
  force_sent_at = 50, force_dirty = true,
  force_dirty_at = 50, force_last_result = "pending",
  action_phase = "exec", action_phase_at = 50, reserved_dollars = 7,
  purchase_showcase_queue = { 1, 2 }, stable_ctx_sig = "x", stable_refresh_due = 9,
  stable_sig_cheap = "y", shop_reroll_count = 3, last_play = { "AH" },
  recent_actions = { "play_hand" }, state = "SHOP",
  consumed_actions = { play_hand = true },
  decision_ack_level = 2, decision_ack_at = 98,
  force_cancel_pending = { phase = "sending", names = { "play_hand" }, set = { play_hand = true } },
  force_transport_fault = { reason = "cancel_not_durable" },
  force_transport_paused = true, force_transport_pause_prior = false, llm_paused = true,
  persona = "evil", seed_pasted = "ABC123",
}
require("core.force_state").arm("SHOP", { "a" }, { a = true }, 1)

Lifecycle.reset_run_state()
local N = G.NEURO

check("clears force_inflight", N.force_inflight == false)
check("clears force_state", N.force_state == nil)
check("clears force_window", N.force_window == nil)
check("clears force_sent_at", N.force_sent_at == nil)
check("clears force_dirty_at", N.force_dirty_at == nil)
check("clears state", N.state == nil)
check("clears force_last_result (gap field)", N.force_last_result == nil)
check("clears an old run's force cancellation quarantine", N.force_cancel_pending == nil)
check("clears an old run's cancellation fault without keeping the new run paused",
  N.force_transport_fault == nil and N.force_transport_paused == nil and N.llm_paused == false)
check("clears action_phase (gap field)", N.action_phase == nil)
check("clears action_phase_at (gap field)", N.action_phase_at == nil)
check("clears reserved_dollars (gap field)", N.reserved_dollars == nil)
check("clears purchase_showcase_queue", N.purchase_showcase_queue == nil)
check("stable_ctx_sig is not run-scoped state anymore",
  not table.concat(require("core.lifecycle_registry").describe().run.fields, "|"):find("stable_ctx_sig", 1, true))
check("stable_refresh_due is not a run field (typed delivery owns retained replay)",
  not table.concat(require("core.lifecycle_registry").describe().run.fields, "|"):find("stable_refresh_due", 1, true))
check("stable_sig_cheap is not run-scoped state anymore",
  not table.concat(require("core.lifecycle_registry").describe().run.fields, "|"):find("stable_sig_cheap", 1, true))
check("clears last_play", N.last_play == nil)
check("clears recent_actions", N.recent_actions == nil)
check("clears disposable-action lock", N.consumed_actions == nil)
check("clears decision acknowledgement backoff", N.decision_ack_level == nil and N.decision_ack_at == nil)
check("zeroes state_enter_serial", N.state_enter_serial == 0)
check("clears force_dirty", N.force_dirty == false)

check("KEEPS session persona", N.persona == "evil")
check("clears pre-run seed after generation starts", N.seed_pasted == nil)

local registered = require("core.lifecycle_registry").describe().run.fields
check("the run scope still registers a plausible number of fields (sweep is not vacuous)",
  #registered >= 60)
local SENTINEL = {}
for _, key in ipairs(registered) do G.NEURO[key] = SENTINEL end
G.NEURO.persona = "evil"
Lifecycle.reset_run_state()
local survivors = {}
for _, key in ipairs(registered) do
  if G.NEURO[key] == SENTINEL then survivors[#survivors + 1] = key end
end
check("reset_run_state leaves no registered run field at its pre-reset value: "
  .. table.concat(survivors, ","), #survivors == 0)
check("the sweep did not silently wipe session state", G.NEURO.persona == "evil")

local HudState = require("hud.state")
local keep_new_state, keep_invalidate = HudState.new_state, HudState.invalidate_caches
HudState.panel_y_current, HudState.panel_y_last_time = 999, 12345
HudState.pack_w_hi = 400
Lifecycle.reset_run_state()
check("hud state glide stamps are cleared by construction on run reset",
  HudState.panel_y_last_time == 0 and HudState.panel_y_current == 6
  and HudState.pack_w_hi == nil)
check("hud state functions survive the field wipe",
  HudState.new_state == keep_new_state and HudState.invalidate_caches == keep_invalidate)

local hook_after_throw = false
local registry = require("core.lifecycle_registry")
registry.register_hook("run", "zz_test_throw", function() error("reset hook exploded") end, 998)
registry.register_hook("run", "zz_test_after_throw", function() hook_after_throw = true end, 999)
local generation_before_hook_fault = G.NEURO.run_generation
local reset_ok = pcall(Lifecycle.reset_run_state)
check("one reset-hook failure cannot suppress sibling hooks or final initialization",
  reset_ok and hook_after_throw and G.NEURO.run_generation == generation_before_hook_fault + 1
    and G.NEURO.force_inflight == false)

print("====================================================")
if #fails == 0 then
  print("==== reset: run-scoped cleared, session/setup kept, 0 FAIL ====")
else
  print(string.format("==== reset: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("RESET_FAILS=" .. #fails .. " (0 = clean) RESET_CHECKS=" .. checks())
os.exit(#fails == 0 and 0 or 1)
