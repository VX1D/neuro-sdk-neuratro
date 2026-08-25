_G.NEURO_TEST = true

local CLOCK = 1000.0
_G.love = { timer = { getTime = function() return CLOCK end } }
_G.G = { GAME = {}, CONTROLLER = { locks = {} } }

local Guard = require("core.transition_guard")

local check, done = require("tests.helpers").harness("transition-guard")

local function blocked(name) return Guard.reject_reason(name) ~= nil end

G.GAME.STOP_USE = 0
check("play_hand never blocked", not blocked("play_hand"))

G.GAME.STOP_USE = 0
check("use_card allowed when STOP_USE=0", not blocked("use_card"))
G.GAME.STOP_USE = 4
check("use_card blocked while STOP_USE>0", blocked("use_card"))
G.GAME.STOP_USE = 0
check("use_card allowed again once STOP_USE clears", not blocked("use_card"))

for _, pair in ipairs({ { "toggle_shop", "toggle_shop" }, { "reroll_shop", "shop_reroll" }, { "skip_blind", "skip_blind" } }) do
  local action, lock = pair[1], pair[2]
  G.CONTROLLER.locks = {}
  check(action .. " allowed when lock clear", not blocked(action))
  G.CONTROLLER.locks[lock] = true
  check(action .. " blocked while " .. lock .. " held", blocked(action))
  G.CONTROLLER.locks[lock] = nil
  check(action .. " allowed once lock released", not blocked(action))
end

G.CONTROLLER.locks = {}
Guard.reset()
CLOCK = 2000.0
check("cash_out allowed before firing", not blocked("cash_out"))
Guard.mark("cash_out")
check("cash_out blocked immediately after firing", blocked("cash_out"))
CLOCK = 2000.0 + 0.5
check("cash_out still blocked mid-window (0.5s < 1.0s)", blocked("cash_out"))
CLOCK = 2000.0 + 1.5
check("cash_out allowed after window elapses (1.5s > 1.0s)", not blocked("cash_out"))

CLOCK = 2500.0
check("skip_booster allowed before firing", not blocked("skip_booster"))
Guard.mark("skip_booster")
check("skip_booster blocked immediately after firing", blocked("skip_booster"))
CLOCK = 2500.0 + 0.5
check("skip_booster still blocked mid-window (0.5s < 0.8s)", blocked("skip_booster"))
CLOCK = 2500.0 + 1.0
check("skip_booster allowed after window elapses", not blocked("skip_booster"))

CLOCK = 2600.0
G.GAME.STOP_USE = 0
check("skip_booster allowed when STOP_USE=0", not blocked("skip_booster"))
G.GAME.STOP_USE = 4
check("skip_booster blocked while STOP_USE>0 (co-gated with use_card)", blocked("skip_booster"))
check("use_card also blocked while STOP_USE>0 (both settle together)", blocked("use_card"))
G.GAME.STOP_USE = 0
check("skip_booster allowed again once STOP_USE clears", not blocked("skip_booster"))

CLOCK = 2800.0
G.CONTROLLER.locks = { toggle_shop = true }
check("leaked lock rejects while fresh", blocked("toggle_shop"))
CLOCK = 2800.0 + 4.0
check("leaked lock still rejects at 4s", blocked("toggle_shop"))
CLOCK = 2800.0 + 5.5
check("leaked lock ignored after 5s (degrades, no permanent wedge)", not blocked("toggle_shop"))
G.CONTROLLER.locks.toggle_shop = nil
CLOCK = 2800.0 + 6.0
check("unlocked observation clears the leak tracker", not blocked("toggle_shop"))
G.CONTROLLER.locks = { toggle_shop = true }
check("fresh re-lock rejects again after a clear", blocked("toggle_shop"))
G.CONTROLLER.locks = {}

CLOCK = 3000.0
Guard.mark("select_blind")
check("select_blind blocked within 0.8s window", blocked("select_blind"))
CLOCK = 3000.0 + 0.9
check("select_blind allowed after 0.8s window", not blocked("select_blind"))

CLOCK = 4000.0
Guard.mark("reroll_boss")
check("reroll_boss blocked within 0.5s window", blocked("reroll_boss"))
CLOCK = 4000.0 + 0.6
check("reroll_boss allowed after 0.5s (sequential Retcon rerolls unaffected)", not blocked("reroll_boss"))

Guard.mark("use_card")
G.GAME.STOP_USE = 0
check("use_card not latched by mark (STOP_USE governs it)", not blocked("use_card"))

CLOCK = 5000.0
Guard.mark("cash_out")
check("cash_out blocked after mark", blocked("cash_out"))
Guard.reset()
check("reset clears the latch", not blocked("cash_out"))

do
  Guard.reset()
  CLOCK = 2000.0
  G.CONTROLLER.locks.toggle_shop = true
  check("lock: held now -> blocked", blocked("toggle_shop"))
  CLOCK = 2002.0
  check("lock: still held inside the window -> blocked", blocked("toggle_shop"))
  CLOCK = 2006.0
  check("lock: held past the escape while polled -> allowed", not blocked("toggle_shop"))

  CLOCK = 2100.0
  check("lock: a genuine new lock after a polling gap is blocked again", blocked("toggle_shop"))

  CLOCK = 2101.0
  G.CONTROLLER.locks.toggle_shop = nil
  blocked("toggle_shop")
  G.CONTROLLER.locks.toggle_shop = true
  CLOCK = 2102.0
  check("lock: after a released observation the next lock blocks from scratch", blocked("toggle_shop"))

  Guard.reset()
  local escaped_at
  for i = 0, 20 do
    CLOCK = 3000.0 + i * 0.5
    if not blocked("toggle_shop") then escaped_at = i * 0.5 break end
  end
  check("lock: continuous polling still escapes at LOCK_LEAK_S", escaped_at == 5.0, tostring(escaped_at))
  G.CONTROLLER.locks.toggle_shop = nil
  Guard.reset()
end

do
  check("Guard.BUSY exports the busy phrasing as a string", type(Guard.BUSY) == "string")
  check("Guard.BUSY keeps the still-resolving wording",
    Guard.BUSY:find("still resolving on screen", 1, true) ~= nil, tostring(Guard.BUSY))
  check("Guard.BUSY keeps the wait-and-retry wording",
    Guard.BUSY:find("Wait a moment, then choose again.", 1, true) ~= nil, tostring(Guard.BUSY))

  Guard.reset()
  G.GAME.STOP_USE = 4
  check("Guard.BUSY is exactly what reject_reason returns while blocked",
    Guard.reject_reason("use_card") == Guard.BUSY)
  G.GAME.STOP_USE = 0
end

done()
