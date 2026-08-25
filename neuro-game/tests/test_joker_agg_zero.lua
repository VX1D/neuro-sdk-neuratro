_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("joker-aggregate-zero")

local Scoring = require("util.scoring")
local Jokers = require("context.ctx_jokers")

local function pair_xmult_joker(key, xmult)
  return { ability = { type = "Pair", x_mult = xmult, set = "Joker" },
           config = { center = { key = key, set = "Joker" } }, sell_cost = 3 }
end
local function pair_xchips_joker(key, xchips)
  return { ability = { type = "Pair", x_chips = xchips, set = "Joker" },
           config = { center = { key = key, set = "Joker" } }, sell_cost = 3 }
end

local function section_with(acc_xmult, acc_xchips)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1, SHOP = 5 },
    GAME = { dollars = 8, round_resets = { ante = 2 }, probabilities = { normal = 1 } },
    NEURO = {},
    jokers = { cards = { pair_xmult_joker("j_test_a", 2), pair_xmult_joker("j_test_b", 2),
      pair_xchips_joker("j_test_c", 6) } },
  }
  local real_jsum = Scoring.joker_summary()
  real_jsum.cond_by_type.Pair.acc_xmult = acc_xmult
  real_jsum.cond_by_type.Pair.acc_xchips = acc_xchips or 1
  real_jsum.cond_by_type.Pair.accumulator = true
  local real = Scoring.joker_summary
  Scoring.joker_summary = function() return real_jsum end
  local ok, out = pcall(Jokers.jokers_section)
  Scoring.joker_summary = real
  return ok, ok and (out or "") or tostring(out)
end

local ok2, out2 = section_with(2)
check("a live accumulator still divides out of the bucket total", ok2
  and out2:find("if the hand contains a Pair", 1, true) ~= nil
  and out2:find("x2 Mult", 1, true) ~= nil, out2)

local ok0, out0 = section_with(0)
check("an accumulator of zero renders a finite conditional total", ok0
  and out0:lower():find("inf", 1, true) == nil
  and out0:lower():find("nan", 1, true) == nil
  and out0:find("x4 Mult", 1, true) ~= nil, out0)

local okc, outc = section_with(2, 0)
check("a chip accumulator of zero renders a finite conditional total", okc
  and outc:lower():find("inf", 1, true) == nil
  and outc:lower():find("nan", 1, true) == nil
  and outc:find("x6 Chips", 1, true) ~= nil, outc)

done()
