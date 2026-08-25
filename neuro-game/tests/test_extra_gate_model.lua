_G.NEURO_TEST = true
_G.G = {}

local CardUtil = require("facts.card_util")
local DynamicJokers = require("facts.dynamic_jokers")
local Vanilla = require("tests.fixtures.vanilla_jokers")
local Truth = require("tests.fixtures.vanilla_joker_truth")

local check, done = require("tests.helpers").harness("extra-gate-model")

local centers = {}
for _, k in ipairs(Vanilla.keys()) do centers[k] = Vanilla.card(k).config.center end
_G.G = { P_CENTERS = centers }

local EXPECT = {
  j_half           = { "+20 Mult (a played hand of 3 or fewer cards)", 4046 },
  j_mystic_summit  = { "+15 Mult (having no discards left)", 4068 },
  j_loyalty_card   = { "x4 Mult (every few hands)", 4006 },
  j_card_sharp     = { "x3 Mult (replaying a hand type you already played this round)", 4388 },
  j_scholar        = { "+20 Chips (played Aces); +4 Mult (played Aces)", 3538 },
  j_walkie_talkie  = { "+10 Chips (played 10s and 4s); +4 Mult (played 10s and 4s)", 3546 },
  j_bloodstone     = { "x1.5 Mult (played Hearts, 1 in 2 of the time)", 3626 },
  j_gros_michel    = { "+15 Mult", 4370 },
  j_cavendish      = { "x3 Mult", 4376 },
  j_ice_cream      = { "+100 Chips", 4263 },
  j_stuntman       = { "+250 Chips", 4087 },
}

local SILENT = {
  j_bootstraps = "its rate is floor(dollars/5) * extra.mult, a live-state read (card.lua:4394)",
  j_misprint   = "extra.max is a ceiling, not a rate (card.lua:4074)",
  j_runner     = "extra.chips is an accumulator sitting at its 0 identity (card.lua:4256)",
  j_square     = "extra.chips is an accumulator sitting at its 0 identity (card.lua:4249)",
  j_castle     = "extra.chips is an accumulator sitting at its 0 identity (card.lua:4228)",
  j_wee        = "extra.chips is an accumulator sitting at its 0 identity (card.lua:4221)",
  j_faceless = "no row", j_todo_list = "no row", j_seance = "no row", j_rocket = "no row",
  j_turtle_bean = "no row", j_reserved_parking = "no row", j_troubadour = "no row",
}

for key, exp in pairs(EXPECT) do
  local fx = CardUtil.joker_fx(Vanilla.card(key))
  check(key .. ": stamp matches card.lua:" .. exp[2], fx == exp[1], "[" .. tostring(fx) .. "]")
end

for key, why in pairs(SILENT) do
  local fx = CardUtil.joker_fx(Vanilla.card(key))
  check(key .. ": stamps nothing -- " .. why, fx == "", "[" .. tostring(fx) .. "]")
end

local TRUTH_KIND = { ["+"] = { "mult", "chips" }, x = { "xmult", "xchips" } }
for key, exp in pairs(EXPECT) do
  local ops = {}
  for op in exp[1]:gmatch("[%+x]%d") do ops[op:sub(1, 1)] = true end
  local truth_gated, truth_bare = false, false
  for _, row in ipairs(Truth[key] or {}) do
    for _, kind in ipairs(TRUTH_KIND[row.kind:find("^x") and "x" or "+"] or {}) do
      if kind == row.kind and ops[row.kind:find("^x") and "x" or "+"] then
        if row.gate then truth_gated = true else truth_bare = true end
      end
    end
  end
  local stamped_gate = exp[1]:find("%(") ~= nil
  check(key .. ": stamp qualification agrees with vanilla_joker_truth",
    stamped_gate == truth_gated and stamped_gate ~= truth_bare,
    string.format("stamped_gate=%s truth_gated=%s truth_bare=%s", tostring(stamped_gate),
      tostring(truth_gated), tostring(truth_bare)))
end

for _, key in ipairs(Vanilla.keys()) do
  for _, mode in ipairs({ "card", "card_played" }) do
    local card = Vanilla[mode](key)
    local fx = CardUtil.joker_fx(card)
    check(key .. "/" .. mode .. ": stamp carries no bare xMult marker",
      not fx:find("*", 1, true), "[" .. fx .. "]")
    if fx ~= "" and type(card.ability.extra) == "table" and #DynamicJokers.extra_specs(key) > 0 then
      local gated = false
      for _, spec in ipairs(DynamicJokers.extra_specs(key)) do
        if spec.gate then gated = true end
      end
      check(key .. "/" .. mode .. ": a gated extra row is never stamped bare",
        (not gated) or fx:find("%("), "[" .. fx .. "]")
    end
  end
end

for _, key in ipairs({ "j_wee", "j_square", "j_runner", "j_castle" }) do
  local fx = CardUtil.joker_fx(Vanilla.card_played(key))
  check(key .. ": an accumulator that has moved off its template is not stamped",
    fx == "", "[" .. fx .. "]")
end

_G.G = { P_CENTERS = { j_mod_unknown = { key = "j_mod_unknown", set = "Joker",
  config = { extra = { mult = 7, chips = 9, Xmult = 3 } } } } }
local modded = { ability = { extra = { mult = 7, chips = 9, Xmult = 3 } },
                 config = { center = { key = "j_mod_unknown", set = "Joker" } } }
check("an unregistered key with extra numbers stamps nothing",
  CardUtil.joker_fx(modded) == "", "[" .. tostring(CardUtil.joker_fx(modded)) .. "]")

check("extra_specs is empty for an unregistered key", #DynamicJokers.extra_specs("j_mod_unknown") == 0)
check("extra_specs skips a ceiling row", #DynamicJokers.extra_specs("j_misprint") == 0)
check("extra_specs skips a live-state row", #DynamicJokers.extra_specs("j_bootstraps") == 0)
check("extra_specs carries the row's own gate for j_half",
  (DynamicJokers.extra_specs("j_half")[1] or {}).gate == DynamicJokers.ROWS.j_half[1].gate)

done()
