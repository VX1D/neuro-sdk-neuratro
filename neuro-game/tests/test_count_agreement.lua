_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("count-agreement")

local Render = require("facts.boss.render")

local function jokers(n)
  local cards = {}
  -- Amber Acorn turns the whole row over (game-dump blind.lua:218-227); a board that names the boss
  -- without doing so makes the payload contradict its own roster, which prints only face-up names.
  for i = 1, n do cards[i] = { facing = "back" } end
  _G.G = {
    GAME = { blind = { key = "bl_final_acorn", name = "Amber Acorn", debuff = {} },
      current_round = {}, probabilities = { normal = 1 }, hands = {} },
    jokers = { cards = cards }, hand = { cards = {} }, deck = { cards = {} }, playing_cards = {},
  }
  return Render.render("status", "bl_final_acorn") or ""
end

local one = jokers(1)
check("Amber Acorn over one joker agrees in the singular",
  one:find("1 joker is face down in a shuffled order.", 1, true) ~= nil, one)
check("and states no plural form of it",
  one:find("1 joker are", 1, true) == nil and one:find("1 jokers", 1, true) == nil, one)
local two = jokers(2)
check("the plural is unchanged",
  two:find("2 jokers are face down in a shuffled order.", 1, true) ~= nil, two)

local DebuffFacts = require("facts.debuff_facts")
local Actions = require("core.actions")
local real_count, real_valid = DebuffFacts.count, Actions.is_action_valid

local function debuff_lead(nd)
  require("core.context_delivery").reset_transport()
  require("facts.fact_hints").reset_pending()
  _G.G = {
    STATE = 3, STATES = { SELECTING_HAND = 3 },
    GAME = { blind = { name = "Small Blind", chips = 300, boss = false }, chips = 0,
      current_round = { hands_left = 3, discards_left = 3 }, round_resets = { ante = 1 },
      hands = {}, modifiers = {}, probabilities = { normal = 1 }, dollars = 4 },
    NEURO = { once_serials = {}, session_once_serials = {}, run_generation = 1,
      state_enter_serial = 1, decision_serial = 1 },
    hand = { cards = {} }, deck = { cards = {} }, jokers = { cards = {} },
    consumeables = { cards = {} }, playing_cards = {},
  }
  DebuffFacts.count = function() return nd end
  Actions.is_action_valid = function(n) return n == "play_hand" end
  local q = ((require("force.force_selecting_hand").build() or {}).query) or ""
  return q:match("%d+ held cards? [^.]*%.") or q:match("%d+ held card%(s%)[^.]*%.") or "<none>"
end

local ok, lead1 = pcall(debuff_lead, 1)
check("the SELECTING_HAND force builds", ok, tostring(lead1))
if ok then
  check("one debuffed held card agrees throughout the sentence",
    lead1 == "1 held card is debuffed: it scores 0 chips and its abilities are off.", lead1)
end
local ok2, lead2 = pcall(debuff_lead, 2)
if ok2 then
  check("two keep the plural",
    lead2 == "2 held cards are debuffed: they score 0 chips and their abilities are off.", lead2)
end
DebuffFacts.count, Actions.is_action_valid = real_count, real_valid

done()
