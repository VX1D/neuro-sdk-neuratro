_G.NEURO_TEST = true
love = setmetatable({ timer = { getTime = function() return 100 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = { NEURO = {}, TIMERS = { REAL = 100 } }

local FS = require("core.force_state")
local check, done = require("tests.helpers").harness("force-window-shadow")

local function reset()
  G.NEURO = { decision_serial = 1 }
end

reset()
local names = { "play_hand", "discard_hand" }
local armed = FS.arm("SELECTING_HAND", names, { play_hand = true, discard_hand = true }, 100)
check("arm succeeds", armed == true)
check("shadow arm registers a window without forcing and sets legacy force_inflight",
  FS.window() ~= nil and FS.window().phase == "registered" and G.NEURO.force_inflight == true,
  FS.window() and FS.window().phase)
check("shadow: arm does not stamp delivery", G.NEURO.force_sent_at == nil,
  tostring(G.NEURO.force_sent_at))
check("shadow mark_sent enters forced and stamps delivery",
  FS.mark_sent(101) == true and FS.window().phase == "forced"
    and G.NEURO.force_sent_at == 101,
  FS.window().phase)
check("shadow: a second mark_sent is a no-op", FS.mark_sent(102) == false)
check("the window retains the action list passed to arm", FS.window().names == names)
check("shadow window_owns agrees with the force set",
  FS._test.window_owns("play_hand") == true and FS._test.window_owns("sell_card") == false)
check("shadow window_is_open is true for an open force", FS.window_is_open() == true)

reset()
FS.arm("SELECTING_HAND", names, { play_hand = true, discard_hand = true }, 100)
FS.mark_sent(101)

local first_window = FS.window()
local refused = FS.arm("SHOP", { "sell_card" }, { sell_card = true }, 101)
check("one force at a time: arm rejects while a force is open (SPECIFICATION.md:135-137)",
  refused == false)
check("one force at a time: rejection does not replace the window", FS.window() == first_window)

FS.clear_force_state()
check("shadow clear_force_state ends the window (action_window.gd:104-108)",
  FS.window().phase == "ended" and G.NEURO.force_inflight == false, FS.window().phase)
check("shadow window_is_open is false after closing", FS.window_is_open() == false)

local armed2 = FS.arm("SELECTING_HAND", names, { play_hand = true, discard_hand = true }, 102)
check("arming after close creates a different window because Ended is terminal",
  armed2 == true and FS.window() ~= first_window)
FS.clear_force_state()
G.NEURO.decision_serial = 2
FS.arm("SELECTING_HAND", names, { play_hand = true, discard_hand = true }, 103)
check("a new decision_serial gives the window a new key",
  FS.window().key ~= first_window.key, FS.window().key)

reset()
local empty = FS.arm("SHOP", {}, {}, 104)
check("arm rejects an empty action set (action_window.gd:63-65)",
  empty == false and not G.NEURO.force_inflight)

reset()
FS.arm("SHOP", { "sell_card" }, { sell_card = true }, 105)
FS.supersede()
check("supersede ends the window", FS.window().phase == "ended", FS.window().phase)

done()
