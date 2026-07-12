package.path = "./?.lua;;" .. package.path
love = setmetatable({ timer = { getTime = function() return 100 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = { NEURO = {}, TIMERS = { REAL = 100 } }

local FM = require("core.force_state")

local fails = {}
local function check(name, cond)
  if not cond then fails[#fails + 1] = name end
end
local function reset() G.NEURO = {} end

reset()
check("idle: not inflight", FM.is_inflight() == false)

check("arm returns true when idle", FM.arm("SHOP", { "a", "b" }, { a = true, b = true }, "fp1", 100) == true)
check("arm sets inflight", G.NEURO.force_inflight == true)
check("arm sets state", G.NEURO.force_state == "SHOP")
check("arm sets sent_at", G.NEURO.force_sent_at == 100)
check("arm sets action_names", G.NEURO.force_action_names[1] == "a")
check("arm sets action_set", G.NEURO.force_action_set.b == true)
check("arm sets fingerprint", G.NEURO.last_force_fingerprint == "fp1")
check("arm sets pending", G.NEURO.force_last_result == "pending")
check("is_inflight true after arm", FM.is_inflight() == true)
check("is_forced_action in-set", FM.is_forced_action("a") == true)
check("is_forced_action out-of-set", FM.is_forced_action("z") == false)

check("SDK: arm REFUSES a second force while inflight", FM.arm("MENU", { "x" }, { x = true }, "fp2", 200) == false)
check("SDK: state unchanged after refused arm", G.NEURO.force_state == "SHOP")
check("SDK: fingerprint unchanged after refused arm", G.NEURO.last_force_fingerprint == "fp1")

FM.mark_answered()
check("mark_answered sets answered while inflight", G.NEURO.force_last_result == "answered")

reset()
FM.arm("SHOP", { "a" }, { a = true }, "fp", 100)
FM.supersede()
check("supersede clears inflight", G.NEURO.force_inflight == false)
check("supersede sets result", G.NEURO.force_last_result == "superseded")
check("supersede nils state", G.NEURO.force_state == nil)
check("supersede dirties force", G.NEURO.force_dirty == true)

reset()
FM.arm("SHOP", { "a" }, { a = true }, "fp", 100)
FM.stall()
check("stall clears inflight", G.NEURO.force_inflight == false)
check("stall sets result", G.NEURO.force_last_result == "stall")
check("stall drops fingerprint", G.NEURO.last_force_fingerprint == nil)
check("stall dirties force", G.NEURO.force_dirty == true)

reset()
G.NEURO.force_last_result = "prev"
FM.stall()
check("stall while NOT inflight leaves result", G.NEURO.force_last_result == "prev")
check("stall while NOT inflight still drops fingerprint + dirties", G.NEURO.force_dirty == true)

reset()
FM.mark_answered()
check("mark_answered no-op when not inflight", G.NEURO.force_last_result == nil)

reset()
G.NEURO.last_force_fingerprint = "old"
FM.rearm()
check("rearm dirties force", G.NEURO.force_dirty == true)
check("rearm drops fingerprint", G.NEURO.last_force_fingerprint == nil)
check("rearm does NOT set the debounce anchor", G.NEURO.force_dirty_at == nil)

reset()
FM.arm("SHOP", { "a" }, { a = true }, "fp", 100)
FM.clear_force_state()
check("clear: inflight false", G.NEURO.force_inflight == false)
check("clear: state nil", G.NEURO.force_state == nil)
check("clear: names nil", G.NEURO.force_action_names == nil)
check("clear: set nil", G.NEURO.force_action_set == nil)
check("clear: sent_at nil", G.NEURO.force_sent_at == nil)

print("====================================================")
if #fails == 0 then
  print("==== force_machine: all transitions + SDK one-at-a-time hold, 0 FAIL ====")
else
  print(string.format("==== force_machine: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("FORCE_MACHINE_FAILS=" .. #fails .. " (0 = clean)")
os.exit(#fails == 0 and 0 or 1)
