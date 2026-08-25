_G.NEURO_TEST = true

local STATES = { SHOP = 5 }
_G.G = {
  TIMERS = { REAL = 0, TOTAL = 0 }, SETTINGS = { GAMESPEED = 1, paused = false }, SPEEDFACTOR = 1,
  STATES = STATES, STATE = STATES.SHOP,
}

local check, done = require("tests.helpers").harness("clock-carry-integral")
local Utils = require("util.utils")

Utils.observe_clock() -- t=0, unpaused: establishes last_real=0, last_total=0, carry=0

G.TIMERS.REAL = 60
G.TIMERS.TOTAL = 60 -- SPEEDFACTOR=1, unpaused: TOTAL genuinely advanced through the gap
G.SETTINGS.paused = true

local read1 = Utils.game_now()
local read2 = Utils.game_now()
check("a pure-read game_now() does not itself attribute the unsampled gap to the pause",
  read1 == 60, read1)
check("repeated pure reads are idempotent (no accumulation as a side effect of reading)",
  read1 == read2, read2)

G.TIMERS.REAL, G.TIMERS.TOTAL = 0, 0
Utils.observe_clock()

local function tick(seconds, dt)
  dt = dt or 1 / 60
  local target = G.TIMERS.REAL + seconds
  while G.TIMERS.REAL < target - 1e-12 do
    local step = math.min(dt, target - G.TIMERS.REAL)
    G.TIMERS.REAL = G.TIMERS.REAL + step
    if not G.SETTINGS.paused then G.TIMERS.TOTAL = G.TIMERS.TOTAL + step * G.SPEEDFACTOR end
    Utils.observe_clock()
  end
end

tick(5) -- unpaused
G.SETTINGS.paused = true
tick(3) -- paused: TOTAL frozen, carry should absorb exactly these 3s
G.SETTINGS.paused = false
tick(2) -- unpaused again

local read3 = Utils.game_now()
check("a diligently-sampled carry (the real per-frame contract) still totals wall seconds exactly",
  math.abs(read3 - 10) < 1e-6, read3)

done()
