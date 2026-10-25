require("tests.stubs").setup({ love = "lazy", localize = true })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("count-agreement")

local Render = require("facts.boss.render")

local function jokers(n)
  local cards = {}
  -- Amber Acorn flips the row face down; only face-up names are available for the roster.
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
  local held = {}
  for i = 1, nd do
    held[i] = require("tests.engine_cards").playing("King", "Hearts", { facing = "front", debuff = true })
  end
  require("core.context_delivery").reset_transport()
  require("facts.fact_hints").reset_pending()
  _G.G = {
    STATE = ES.SELECTING_HAND, STATES = ES,
    GAME = { blind = { name = "Small Blind", chips = 300, boss = false }, chips = 0,
      current_round = { hands_left = 3, discards_left = 3 }, round_resets = { ante = 1 },
      hands = {}, modifiers = {}, probabilities = { normal = 1 }, dollars = 4 },
    NEURO = { once_serials = {}, session_once_serials = {}, run_generation = 1,
      state_enter_serial = 1, decision_serial = 1 },
    hand = { cards = held }, deck = { cards = {} }, jokers = { cards = {} },
    consumeables = { cards = {} }, playing_cards = {},
  }
  Actions.is_action_valid = function(n) return n == "play_hand" end
  local q = require("tests.helpers").built_text(require("force.force_selecting_hand").build())
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

local HH = require("handlers.hand_handlers")
local real_pending, real_confirm_ready = HH.pending, HH.confirm_ready
local function hand_card(hidden, debuffed)
  return require("tests.engine_cards").playing("King", "Hearts",
    { facing = hidden and "back" or "front", debuff = debuffed, enhancement = "m_wild" })
end

local function privacy_query(cards, confirming)
  require("core.context_delivery").reset_transport()
  require("facts.fact_hints").reset_pending()
  _G.G = {
    STATE = ES.SELECTING_HAND, STATES = ES,
    GAME = { blind = { name = "Small Blind", chips = 300, boss = false }, chips = 0,
      current_round = { hands_left = 3, discards_left = 3 }, round_resets = { ante = 1 },
      hands = {}, modifiers = {}, probabilities = { normal = 1 }, dollars = 4 },
    NEURO = { once_serials = {}, session_once_serials = {}, run_generation = 1,
      state_enter_serial = 1, decision_serial = 1 },
    hand = { cards = cards }, deck = { cards = {} }, jokers = { cards = {} },
    consumeables = { cards = {} }, playing_cards = {},
  }
  local calls = {}
  DebuffFacts.count = function(list)
    calls[#calls + 1] = list
    local n = 0
    for _, card in ipairs(list or {}) do
      if card.debuff then n = n + 1 end
    end
    return n
  end
  Actions.is_action_valid = function(n) return n == "play_hand" end
  if confirming then
    HH.pending = function() return { indices = { 1 } } end
    HH.confirm_ready = function() return true end
  end
  local q = require("tests.helpers").built_text(require("force.force_selecting_hand").build())
  DebuffFacts.count, Actions.is_action_valid = real_count, real_valid
  HH.pending, HH.confirm_ready = real_pending, real_confirm_ready
  return q, calls
end

local mixed_normal, normal_calls = privacy_query({ hand_card(false, true), hand_card(true, true) })
local clean_normal = privacy_query({ hand_card(false, true), hand_card(true, false) })
check("mixed-hand normal prose scopes debuffs to visible cards",
  mixed_normal == clean_normal
    and mixed_normal:find("1 visible held card is debuffed: it scores 0 chips and its abilities are off.", 1, true) ~= nil,
  mixed_normal)
check("mixed-hand normal count inputs contain no hidden cards",
  #normal_calls > 0 and (function()
    for _, list in ipairs(normal_calls) do
      for _, card in ipairs(list or {}) do
        if require("facts.card_util").is_hidden(card) then return false end
      end
    end
    return true
  end)())

local function in_state_only(text, sentence)
  local section, at = text:find("\n## Hand options\n", 1, true), text:find(sentence, 1, true)
  return section ~= nil and at ~= nil and at > section and text:find(sentence, 1, true) == at
end
local DEBUFF_FACT = "1 visible held card is debuffed: it scores 0 chips and its abilities are off."
check("the debuff count rides the frame's state, not its query",
  in_state_only(mixed_normal, DEBUFF_FACT), mixed_normal)

local mixed_confirm = privacy_query({ hand_card(false, true), hand_card(true, true) }, true)
local clean_confirm = privacy_query({ hand_card(false, true), hand_card(true, false) }, true)
check("and so does the confirmation's", in_state_only(mixed_confirm, DEBUFF_FACT), mixed_confirm)
check("mixed-hand confirmation prose keeps hidden debuff status private",
  mixed_confirm == clean_confirm
    and mixed_confirm:find("1 visible held card is debuffed: it scores 0 chips and its abilities are off.", 1, true) ~= nil,
  mixed_confirm)

local hidden_only = privacy_query({ hand_card(true, true) })
check("a debuffed hidden-only hand has no debuff lead", hidden_only:find("debuffed", 1, true) == nil,
  hidden_only)

DebuffFacts.count, Actions.is_action_valid = real_count, real_valid
HH.pending, HH.confirm_ready = real_pending, real_confirm_ready

done()
