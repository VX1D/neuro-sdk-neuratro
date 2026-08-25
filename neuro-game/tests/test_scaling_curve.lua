_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("scaling-curve")

_G.get_blind_amount = function(a)
  local t = { 300, 800, 2000, 5000, 11000, 20000, 35000, 50000 }
  return t[a]
end
_G.G = { GAME = { round_resets = { ante = 6 }, win_ante = 8, starting_params = { ante_scaling = 1 } } }

local EF = require("facts.economy_facts")

do
  local c = EF.scaling_curve()
  check("curve shows the next two antes' bases", type(c) == "string"
    and c:find("ante 7 ~35000", 1, true) ~= nil and c:find("ante 8 ~50000", 1, true) ~= nil, c)
  check("curve is a plain fact, not a directive", not (c:find("buy", 1, true) or c:find("reroll", 1, true) or c:find("should", 1, true)), c)
end

do
  G.GAME.round_resets.ante = 8
  check("no curve at the final ante", EF.scaling_curve() == nil)
  G.GAME.round_resets.ante = 7
  check("curve at ante 7 shows only ante 8", (EF.scaling_curve() or ""):find("ante 8", 1, true) ~= nil)
end

do
  G.GAME.round_resets.ante = 1
  G.GAME.starting_params.ante_scaling = 2
  check("ante_scaling multiplies the curve (Plasma x2)", (EF.scaling_curve() or ""):find("ante 2 ~1600", 1, true) ~= nil, EF.scaling_curve())
  G.GAME.starting_params.ante_scaling = 1
end

do
  _G.get_blind_amount = nil
  G.GAME.round_resets.ante = 3
  check("nil when get_blind_amount is unavailable", EF.scaling_curve() == nil)
end

done()
