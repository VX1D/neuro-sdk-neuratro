_G.NEURO_TEST = true
love = setmetatable({ timer = { getTime = function() return 100 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = { NEURO = {}, TIMERS = { REAL = 100 } }

local FM = require("core.force_state")

local check, fails, checks = require("tests.helpers").collector()
local function reset() G.NEURO = {} end

reset()
check("idle: not inflight", FM._test.is_inflight() == false)

check("arm returns true when idle", FM.arm("SHOP", { "a", "b" }, { a = true, b = true }, 100) == true)
check("arm sets inflight", G.NEURO.force_inflight == true)
check("arm sets state", G.NEURO.force_state == "SHOP")
check("arm does not stamp sent_at", G.NEURO.force_sent_at == nil)
check("mark_sent stamps sent_at", FM.mark_sent(101) == true and G.NEURO.force_sent_at == 101)
check("arm sets window names", G.NEURO.force_window.names[1] == "a")
check("arm sets window set", G.NEURO.force_window.set.b == true)
check("arm sets pending", G.NEURO.force_last_result == "pending")
check("is_inflight true after arm", FM._test.is_inflight() == true)
check("is_forced_action in-set", FM.is_forced_action("a") == true)
check("is_forced_action out-of-set", FM.is_forced_action("z") == false)

check("SDK: arm REFUSES a second force while inflight", FM.arm("MENU", { "x" }, { x = true }, 200) == false)
check("SDK: state unchanged after refused arm", G.NEURO.force_state == "SHOP")

FM.mark_answered()
check("mark_answered sets answered while inflight", G.NEURO.force_last_result == "answered")

reset()
FM.arm("SHOP", { "a" }, { a = true }, 100)
FM.supersede()
check("supersede clears inflight", G.NEURO.force_inflight == false)
check("supersede sets result", G.NEURO.force_last_result == "superseded")
check("supersede nils state", G.NEURO.force_state == nil)
check("supersede dirties force", G.NEURO.force_dirty == true)

reset()
FM.mark_answered()
check("mark_answered no-op when not inflight", G.NEURO.force_last_result == nil)

reset()
FM.rearm()
check("rearm dirties force", G.NEURO.force_dirty == true)
check("rearm sets the debounce anchor", G.NEURO.force_dirty_at ~= nil)

reset()
FM.arm("SHOP", { "a" }, { a = true }, 100)
FM.mark_sent(101)
FM.clear_force_state()
check("clear: inflight false", G.NEURO.force_inflight == false)
check("clear: state nil", G.NEURO.force_state == nil)
check("clear ends the window", G.NEURO.force_window.phase == "ended")
check("clear closes the force window", require("core.force_state").window_is_open() == false)
check("clear: sent_at nil after having been stamped", G.NEURO.force_sent_at == nil)

print("====================================================")
if #fails == 0 then
  print("==== force_machine: all transitions + SDK one-at-a-time hold, 0 FAIL ====")
else
  print(string.format("==== force_machine: %d FAIL ====", #fails))
  for _, f in ipairs(fails) do print("  FAIL " .. f) end
end
print("FORCE_MACHINE_FAILS=" .. #fails .. " (0 = clean) FORCE_MACHINE_CHECKS=" .. checks())
os.exit(#fails == 0 and 0 or 1)
