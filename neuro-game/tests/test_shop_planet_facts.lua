_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local CardUtil = require("facts.card_util")
local check, done = require("tests.helpers").harness("shop-planet-facts")

local function planet(key, hand, cost)
  return {
    ability = { name = (key:gsub("^c_", ""):gsub("_", " ")), set = "Planet",
      consumeable = { hand_type = hand } },
    config = { center = { key = key, set = "Planet", config = { hand_type = hand } } },
    cost = cost or 3,
  }
end
local function joker(key)
  return {
    ability = { name = key, set = "Joker", mult = 4 },
    config = { center = { key = key, set = "Joker" } },
    cost = 5,
  }
end

_G.G = {
  NEURO = { reserved_dollars = 0 }, FUNCS = {},
  GAME = {
    current_round = { reroll_cost = 5, free_rerolls = 0 }, dollars = 10, round_resets = { ante = 2 },
    hands = {
      ["High Card"] = { played = 0, level = 1 },
      ["Two Pair"] = { played = 7, level = 3 },
    },
  },
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
}

check("Pluto suffix names the hand it levels, with the model's own run-state",
  CardUtil.planet_run_state_suffix(planet("c_pluto", "High Card"))
    == "; played High Card 0x this run (lvl 1)",
  CardUtil.planet_run_state_suffix(planet("c_pluto", "High Card")))
check("suffix reflects a played, leveled hand",
  CardUtil.planet_run_state_suffix(planet("c_uranus", "Two Pair"))
    == "; played Two Pair 7x this run (lvl 3)",
  CardUtil.planet_run_state_suffix(planet("c_uranus", "Two Pair")))
check("non-Planet gets no suffix", CardUtil.planet_run_state_suffix(joker("j_x")) == "")
check("Planet for a hand the run never initialised is silent, not a crash",
  CardUtil.planet_run_state_suffix(planet("c_x", "Flush Five")) == "")
check("nil card is safe", CardUtil.planet_run_state_suffix(nil) == "")
check("suffix contains no comma (CSV columns stay intact)",
  not CardUtil.planet_run_state_suffix(planet("c_pluto", "High Card")):find(",", 1, true))

G.shop_jokers = { cards = { planet("c_pluto", "High Card"), joker("j_x") } }
G.shop_vouchers = { cards = {} }
G.shop_booster = { cards = {} }
local CtxShop = require("context.ctx_shop")
local sec = CtxShop.shop_section() or ""
check("shop row carries the run-state", sec:find("played High Card 0x this run (lvl 1)", 1, true) ~= nil, sec)
check("no garbled '-;' before the played-count suffix (empty-effect sentinel leak)",
  sec:find("-; played", 1, true) == nil, sec)
check("Pluto row transitions cleanly from the dash straight into 'played'",
  sec:find("— played High Card", 1, true) ~= nil, sec)
check("exactly one run-state suffix (only the Planet row)",
  select(2, sec:gsub("this run %(lvl", "")) == 1, sec)
check("I: header is unchanged", sec:find("Shop items:", 1, true) ~= nil, sec)

done()
