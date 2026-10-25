local M = {}

local JokerHits = require("core.joker_hits")
local is_query = JokerHits.is_query
local CHANNEL_KEYS = {
  score_chips = { chips = true, h_chips = true, chip_mod = true },
  score_xchips = { x_chips = true, xchips = true, Xchip_mod = true },
  score_mult = { mult = true, h_mult = true, mult_mod = true },
  score_xmult = { x_mult = true, Xmult = true, xmult = true, x_mult_mod = true, Xmult_mod = true },
  dollars = { dollars = true, dollar = true },
  retrigger = { repetitions = true, retriggers = true },
}

local function pays(result, key)
  local v = result[key]
  return v ~= nil and JokerHits.contributes({ [key] = v })
end

local function note_runtime_scoring_keys(result, rec)
  local smods = rawget(_G, "SMODS")
  local objects = smods and smods.Scoring_Parameter and smods.Scoring_Parameter.obj_table
  if type(objects) ~= "table" then return end
  for object_key, parameter in pairs(objects) do
    if type(parameter) == "table" and type(parameter.calculation_keys) == "table" then
      local parameter_key = tostring(parameter.key or object_key):lower()
      if parameter_key == "chips" or parameter_key == "mult" then
        for _, result_key in pairs(parameter.calculation_keys) do
          if type(result_key) == "string" and pays(result, result_key) then
            local lower = result_key:lower()
            local multiplicative = lower:match("^x") ~= nil or lower:find("_x", 1, true) ~= nil
            rec[(parameter_key == "chips")
              and (multiplicative and "score_xchips" or "score_chips")
              or (multiplicative and "score_xmult" or "score_mult")] = true
          end
        end
      end
    end
  end
end

local function store() return require("core.neuro_lifecycle").neuro_table("joker_observations") end

local function activated(card)
  local observations = store()
  if not observations then return nil end
  local rec = observations[card.sort_id]
  if type(rec) ~= "table" then rec = {}; observations[card.sort_id] = rec end
  rec.activated = true
  return rec
end

local function is_joker(card)
  return type(card) == "table" and card.sort_id ~= nil
    and type(card.ability) == "table" and card.ability.set == "Joker"
end

local function note_result(card, context, result, triggered)
  if not is_joker(card) or is_query(context) then return end
  if result == nil and not triggered then return end
  local rec = activated(card)
  if not rec or type(result) ~= "table" then return end
  for channel, keys in pairs(CHANNEL_KEYS) do
    for key in pairs(keys) do
      if pays(result, key) then rec[channel] = true; break end
    end
  end
  note_runtime_scoring_keys(result, rec)
end

local function note_payout(card, amount)
  if not is_joker(card) or type(amount) ~= "number" or amount == 0 then return end
  local rec = activated(card)
  if not rec then return end
  rec.dollars = true
  local g = rawget(_G, "G")
  rec.last_dollar_payout = { round = tonumber(g and g.GAME and g.GAME.round) or 0, amount = amount }
end

function M.prune_owned()
  local observations = store()
  if not observations then return end
  local owned = {}
  local g = rawget(_G, "G")
  local cards = g and g.jokers and g.jokers.cards
  if type(cards) == "table" then
    for i = 1, #cards do
      local id = cards[i] and cards[i].sort_id
      if id ~= nil then owned[id] = true end
    end
  end
  for id in pairs(observations) do if not owned[id] then observations[id] = nil end end
end

function M.install()
  local Card = rawget(_G, "Card")
  if type(Card) ~= "table" then return false end
  local installed = false
  if type(Card.calculate_joker) == "function" and not Card.__neuro_joker_observations then
    Card.__neuro_joker_observations = true
    local original = Card.calculate_joker
    Card.calculate_joker = function(self, context)
      local result, triggered = original(self, context)
      pcall(note_result, self, context, result, triggered)
      return result, triggered
    end
    installed = true
  end
  if type(Card.calculate_dollar_bonus) == "function" and not Card.__neuro_dollar_observations then
    Card.__neuro_dollar_observations = true
    local original = Card.calculate_dollar_bonus
    Card.calculate_dollar_bonus = function(self, ...)
      local amount = original(self, ...)
      pcall(note_payout, self, amount)
      return amount
    end
    installed = true
  end
  if type(Card.remove) == "function" and not Card.__neuro_observation_prune then
    Card.__neuro_observation_prune = true
    local original = Card.remove
    Card.remove = function(self, ...)
      local result = original(self, ...)
      pcall(M.prune_owned)
      return result
    end
    installed = true
  end
  return installed
end

if rawget(_G, "NEURO_TEST") then
  M._test = { note_result = note_result }
end
return M
