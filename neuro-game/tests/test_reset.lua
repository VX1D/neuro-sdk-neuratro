package.path = "./?.lua;;" .. package.path
love = setmetatable({ timer = { getTime = function() return 100 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = { NEURO = {}, TIMERS = { REAL = 100 } }

local Lifecycle = require("core.neuro_lifecycle")

local fails = {}
local function check(name, cond)
  if not cond then fails[#fails + 1] = name end
end

G.NEURO = {
  force_inflight = true, force_state = "SHOP", force_action_names = { "a" },
  force_action_set = { a = true }, force_sent_at = 50, force_dirty = true,
  force_dirty_at = 50, force_last_result = "pending", last_force_fingerprint = "fp",
  action_phase = "exec", action_phase_at = 50, reserved_dollars = 7,
  purchase_showcase_queue = { 1, 2 }, stable_ctx_sig = "x", stable_refresh_due = 9,
  stable_sig_cheap = "y", shop_reroll_count = 3, last_play = { "AH" },
  recent_actions = { "play_hand" }, reforce_count = 4, state = "SHOP",
  persona = "evil", rules_sent = true, seed_pasted = "ABC123",
}

Lifecycle.reset_run_state()
local N = G.NEURO

check("clears force_inflight", N.force_inflight == false)
check("clears force_state", N.force_state == nil)
check("clears force_action_names", N.force_action_names == nil)
check("clears force_action_set", N.force_action_set == nil)
check("clears force_sent_at", N.force_sent_at == nil)
check("clears force_dirty_at", N.force_dirty_at == nil)
check("keeps last_force_fingerprint", N.last_force_fingerprint == "fp")
check("keeps state", N.state == "SHOP")
check("clears force_last_result (gap field)", N.force_last_result == nil)
check("clears action_phase (gap field)", N.action_phase == nil)
check("clears action_phase_at (gap field)", N.action_phase_at == nil)
check("clears reserved_dollars (gap field)", N.reserved_dollars == nil)
check("clears purchase_showcase_queue", N.purchase_showcase_queue == nil)
check("clears stable_ctx_sig (gap field)", N.stable_ctx_sig == nil)
check("clears stable_refresh_due (gap field)", N.stable_refresh_due == nil)
check("clears stable_sig_cheap (gap field)", N.stable_sig_cheap == nil)
check("clears shop_reroll_count", N.shop_reroll_count == nil)
check("clears last_play", N.last_play == nil)
check("clears recent_actions", N.recent_actions == nil)
check("zeroes reforce_count", N.reforce_count == 0)
check("zeroes state_enter_serial", N.state_enter_serial == 0)
check("clears force_dirty", N.force_dirty == false)

check("KEEPS session persona", N.persona == "evil")
check("KEEPS rules_sent", N.rules_sent == true)
check("KEEPS seed_pasted (pre-run setup)", N.seed_pasted == "ABC123")

print("====================================================")
if #fails == 0 then
  print("==== reset: run-scoped cleared, session/setup kept, 0 FAIL ====")
else
  print(string.format("==== reset: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("RESET_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
