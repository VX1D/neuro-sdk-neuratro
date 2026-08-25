love = setmetatable({ timer = { getTime = function() return 100 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = { NEURO = {}, TIMERS = { REAL = 100 } }

local W = require("core.force_window")
local check, done = require("tests.helpers").harness("force-window-object")

local w = W.build("SHOP", 7, 1)
check("build: key_for combines state and decision_serial into a decision identity",
  w.key == W.key_for("SHOP", 7) and w.key == "SHOP#7", w.key)
check("build: a new window starts in the building phase (action_window.gd:9-10)",
  w.phase == W.BUILDING, w.phase)

check("register rejects an empty action list (action_window.gd:63-65)",
  W.register(w, {}) == false and w.phase == W.BUILDING, w.phase)
check("register transitions building to registered and populates the action set",
  W.register(w, { "play_hand", "discard_hand" }) == true
    and w.phase == W.REGISTERED and w.set.play_hand == true, w.phase)
check("register rejects a second call because a registered window is immutable (action_window.gd:88-92)",
  W.register(w, { "sell_card" }) == false and w.set.sell_card == nil)

check("mark_forced transitions registered to forced",
  W.mark_forced(w) == true and w.phase == W.FORCED, w.phase)
check("mark_forced rejects a second call because a window carries one force (action_window.gd:100-103)",
  W.mark_forced(w) == false and w.phase == W.FORCED)

check("owns accepts a name from the set and rejects one outside it",
  W.owns(w, "play_hand") == true and W.owns(w, "sell_card") == false)
check("is_open is true for a forced window",
  W.is_open(w) == true)

check("finish transitions forced to ended per action_window.gd:104-108",
  W.finish(w) == true and w.phase == W.ENDED, w.phase)
check("a second finish is rejected because ended is terminal",
  W.finish(w) == false)
check("is_open is false for ended and building windows",
  W.is_open(w) == false and W.is_open(W.build("SHOP", 7, 1)) == false)

check("mark_forced rejects the building phase (ActionWindow.cs Force guard)",
  W.mark_forced(W.build("SHOP", 7, 1)) == false)
check("key_for gives different keys to different decision serials",
  W.key_for("SHOP", 7) ~= W.key_for("SHOP", 8))

done()
