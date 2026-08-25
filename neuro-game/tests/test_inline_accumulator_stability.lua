_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("inline-accumulator-stability")
local Compact = require("context.context_compact")

local function card(name, value)
  return { ability = { name = name, set = "Joker", mult = value }, sell_cost = 2,
    config = { center = { key = "j_" .. name:lower():gsub(" ", "_"), set = "Joker",
      loc_txt = { name = name, text = { "+" .. value .. " Mult now" } } } } }
end

local function build(value)
  _G.G = {
    GAME = { dollars = 10, used_vouchers = {}, current_round = { hands_left = 2, discards_left = 2 },
      round_resets = { ante = 3 }, modifiers = {}, blind = { name = "Blind", chips = 100 } },
    NEURO = {}, jokers = { cards = { card("Popcorn", value) }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } }, hand = { cards = {} }, playing_cards = {},
  }
  Compact.invalidate_cache()
  return Compact.build("SELECTING_HAND", nil, { split = "rule", no_cache = true }) or "",
    Compact.build("SELECTING_HAND", nil, { split = "state", no_cache = true }) or ""
end

local r20, s20 = build(20)
local r8, s8 = build(8)
check("accumulator mutation cannot alter retained rules", r20 == r8, r20 .. " || " .. r8)
check("no per-Joker accumulator description enters retained rules",
  not r20:find("Popcorn", 1, true) and not r20:find("20", 1, true), r20)
check("the live value is available in the old ephemeral state", s20:find("20", 1, true) ~= nil, s20)
check("the new force replaces it with the new live value", s8:find("8", 1, true) ~= nil
  and s8 ~= s20, s8)

done()
