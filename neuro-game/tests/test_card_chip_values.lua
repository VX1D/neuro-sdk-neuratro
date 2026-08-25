_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {}, modifiers = {} }, TIMERS = { REAL = 100 },
  jokers = { cards = {}, config = { card_limit = 5 } } }

local check, done = require("tests.helpers").harness("card-chip-values")

local GameRules = require("context.game_rules")
local TokenLegends = require("facts.token_legends")

local NOMINAL = {
  ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9,
  ["10"] = 10, Jack = 10, Queen = 10, King = 10, Ace = 11,
}

local frame = GameRules.invariant_frame()
check("the permanent rules frame states what a card's chips are",
  frame:find("2%-10 are worth their number") ~= nil, frame)
check("face cards are 10, not their rank order",
  frame:find("J/Q/K 10", 1, true) ~= nil, frame)
check("the Ace is 11, not 14 and not 1",
  frame:find("A 11", 1, true) ~= nil, frame)
check("the statement sits where the engine reads the value, on the per-card step",
  frame:find("that card's chips %-%- 2%-10 are worth their number") ~= nil, frame)

check("the rule is on the invariant channel",
  frame:find("RULES.", 1, true) == 1, frame:sub(1, 40))

local claimed = { ["2"] = 2, ["10"] = 10, Jack = 10, Queen = 10, King = 10, Ace = 11 }
local agree = true
for rank, value in pairs(claimed) do
  if NOMINAL[rank] ~= value then agree = false end
end
check("the stated values equal the engine's rank nominals", agree)
check("the natural wrong reading (K=13, A=14) is not what is stated",
  frame:find("K 13", 1, true) == nil and frame:find("A 14", 1, true) == nil, frame)

local legend = TokenLegends.READABLE_STATE.SELECTING_HAND
check("the hand legend states the same numbers",
  legend:find("J/Q/K = 10", 1, true) ~= nil and legend:find("A = 11", 1, true) ~= nil, legend)
check("the hand legend no longer calls a number card's rank its 'face value'",
  legend:find("face value", 1, true) == nil, legend)

done()
