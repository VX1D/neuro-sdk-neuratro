local M = {}

local GETTER_FALLBACK = { "mod_probability", "fix_probability", "check_enhancement" }
local CHANNEL_KEYS = {
  score_chips = { chips = true, h_chips = true, chip_mod = true },
  score_xchips = { x_chips = true, xchips = true, Xchip_mod = true },
  score_mult = { mult = true, h_mult = true, mult_mod = true },
  score_xmult = { x_mult = true, Xmult = true, xmult = true, x_mult_mod = true, Xmult_mod = true },
  dollars = { dollars = true, dollar = true },
  retrigger = { repetitions = true, retriggers = true },
}

local function note_runtime_scoring_keys(result, rec)
  local smods = rawget(_G, "SMODS")
  local class = type(smods) == "table" and smods.Scoring_Parameter or nil
  local objects = type(class) == "table" and (class.obj_table or class.objects) or nil
  if type(objects) ~= "table" then return end
  for object_key, parameter in pairs(objects) do
    if type(parameter) == "table" and type(parameter.calculation_keys) == "table" then
      local parameter_key = tostring(parameter.key or object_key):lower()
      if parameter_key == "chips" or parameter_key == "mult" then
        for _, result_key in pairs(parameter.calculation_keys) do
          if type(result_key) == "string" and result[result_key] ~= nil then
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

local function store()
  local g = rawget(_G, "G")
  local n = g and g.NEURO
  if type(n) ~= "table" then return nil end
  if type(n.joker_observations) ~= "table" then n.joker_observations = {} end
  return n.joker_observations
end

local function is_query(context)
  if type(context) ~= "table" then return false end
  if context.retrigger_joker_check then return true end
  local smods = rawget(_G, "SMODS")
  if type(smods) == "table" and type(smods.is_getter_context) == "function" then
    local ok, answer = pcall(smods.is_getter_context, context)
    if ok then return answer == true end
  end
  for i = 1, #GETTER_FALLBACK do
    if context[GETTER_FALLBACK[i]] then return true end
  end
  return false
end

local function is_joker(card)
  return type(card) == "table" and card.sort_id ~= nil
    and type(card.ability) == "table" and card.ability.set == "Joker"
end

local function note_result(card, context, result, triggered)
  if not is_joker(card) or is_query(context) then return end
  if result == nil and not triggered then return end
  local observations = store()
  if not observations then return end
  local id = card.sort_id
  local rec = observations[id]
  if type(rec) ~= "table" then rec = {}; observations[id] = rec end
  rec.activated = true
  if type(result) ~= "table" then return end
  for channel, keys in pairs(CHANNEL_KEYS) do
    for key in pairs(keys) do
      if result[key] ~= nil then rec[channel] = true; break end
    end
  end
  note_runtime_scoring_keys(result, rec)
end

local function note_payout(card, amount)
  if not is_joker(card) or type(amount) ~= "number" or amount == 0 then return end
  local observations = store()
  if not observations then return end
  local rec = observations[card.sort_id]
  if type(rec) ~= "table" then rec = {}; observations[card.sort_id] = rec end
  rec.activated = true
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
  return installed
end

if rawget(_G, "NEURO_TEST") then
  M._test = { is_query = is_query, note_result = note_result, note_payout = note_payout }
end
return M
