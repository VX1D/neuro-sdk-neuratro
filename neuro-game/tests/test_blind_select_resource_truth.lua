_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("blind-select-resource-truth")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local function payload(boss_key)
  LB.load("BLIND_SELECT", "Boss blind only (no skip, no reroll voucher)")
  if boss_key then
    G.P_BLINDS = G.P_BLINDS or {}
    G.P_BLINDS[boss_key] = G.P_BLINDS[boss_key]
      or { name = "The Needle", dollars = 5, mult = 1, boss = true, debuff = {} }
    G.GAME.round_resets.blind_choices.Boss = boss_key
    require("context.context_compact").invalidate_cache()
  end
  local p = FP.build("BLIND_SELECT")
  return p.state .. "\n" .. p.query
end

local needle = payload("bl_needle")

check("the boss row states the number the blind will leave",
  needle:find("set your hands for the round to 1", 1, true) ~= nil, needle:sub(1, 400))
check("no line claims the pre-blind allowance is what you get 'this round'",
  needle:find("hands and 3 discards this round", 1, true) == nil, needle)
check("the figure is kept, scoped to when it is true",
  needle:find("4 hands and 3 discards before effects triggered by selecting the blind", 1, true) ~= nil, needle)
check("and with a boss on deck the payload says the boss row overrides it",
  needle:find("A boss blind can change that when it starts", 1, true) ~= nil, needle)

do
  LB.load("BLIND_SELECT", "Small blind selectable")
  local p = FP.build("BLIND_SELECT")
  local small = p.state .. "\n" .. p.query
  check("with a non-boss blind on deck the caveat is not printed",
    small:find("A boss blind can change that", 1, true) == nil, small)
  check("but the scoped figure still is",
    small:find("before effects triggered by selecting the blind", 1, true) ~= nil, small)
end

done()
