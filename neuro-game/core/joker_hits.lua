local M = {}

local MIN_HANDS = 3

local GETTER_FALLBACK = { "mod_probability", "fix_probability", "check_enhancement" }

local _serial = 0
local _open = false
local _before_ctx = nil
local _after_ctx = nil
local _triggered = nil

local function store()
  local g = rawget(_G, "G")
  local N = g and g.NEURO
  if type(N) ~= "table" then return nil end
  local hits = N.joker_hits
  if type(hits) ~= "table" then
    hits = {}
    N.joker_hits = hits
  end
  return hits
end

local function fired(eval)
  return type(eval) == "table" and (eval.jokers ~= nil or eval.retriggers ~= nil)
end

local function is_query(context)
  if type(context) ~= "table" then return false end
  if context.retrigger_joker_check then return true end
  local smods = rawget(_G, "SMODS")
  if type(smods) == "table" and type(smods.is_getter_context) == "function" then
    local ok, res = pcall(smods.is_getter_context, context)
    if ok then return res and true or false end
  end
  for i = 1, #GETTER_FALLBACK do
    if context[GETTER_FALLBACK[i]] then return true end
  end
  return false
end

local function pays_from_a_calculate_context(card)
  local center = card and card.config and card.config.center
  return not (center and center.blueprint_compat == false)
end

local function has_condition(card)
  if not pays_from_a_calculate_context(card) then return false end
  local ok, conditional = pcall(function()
    return require("facts.card_semantics").is_conditional(card)
  end)
  return (ok and conditional) and true or false
end

local function open_hand()
  _serial = _serial + 1
  _open = true
  local hits = store()
  if not hits then return end
  local g = rawget(_G, "G")
  local cards = g and g.jokers and g.jokers.cards
  if type(cards) == "table" then
    for i = 1, #cards do
      local card = cards[i]
      local sid = (type(card) == "table") and card.sort_id or nil
      if sid ~= nil then
        local rec = hits[sid]
        if type(rec) ~= "table" then
          rec = { hands = 0, fired = 0 }
          hits[sid] = rec
        end
        rec.hands = (tonumber(rec.hands) or 0) + 1
        rec.seen = _serial
      end
    end
  end
  for sid, rec in pairs(hits) do
    if type(rec) ~= "table" or rec.seen ~= _serial then hits[sid] = nil end
  end
end

function M.note_eval(card, context, eval)
  local triggered = _triggered
  _triggered = nil
  if _after_ctx ~= nil and context ~= _after_ctx then
    _open = false
    _after_ctx = nil
  end
  if type(context) == "table" and context.before and context ~= _before_ctx then
    _before_ctx = context
    open_hand()
  end
  if type(card) == "table" and card.sort_id ~= nil then
    local ability = card.ability
    if type(ability) == "table" and ability.set == "Joker"
      and not is_query(context) and (fired(eval) or triggered == card) then
      local hits = store()
      local rec = hits and hits[card.sort_id]
      if type(rec) == "table" then
        if _open then
          if rec.hit ~= _serial then
            rec.hit = _serial
            rec.fired = (tonumber(rec.fired) or 0) + 1
          end
        else
          rec.outside = true
        end
      end
    end
  end
  if type(context) == "table" and context.after then _after_ctx = context end
end

function M.install()
  if rawget(_G, "__neuro_joker_hits_guard") then return false end
  local orig = rawget(_G, "eval_card")
  if type(orig) ~= "function" then return false end
  _G.__neuro_joker_hits_guard = true
  _G.eval_card = function(card, context)
    local eff, post = orig(card, context)
    pcall(M.note_eval, card, context, eff)
    return eff, post
  end
  local Card = rawget(_G, "Card")
  if type(Card) == "table" and type(Card.calculate_joker) == "function" then
    local orig_calculate = Card.calculate_joker
    Card.calculate_joker = function(self, context)
      local ret, triggered = orig_calculate(self, context)
      if triggered then _triggered = self end
      return ret, triggered
    end
  end
  return true
end

function M.condition_counts(card)
  local sid = (type(card) == "table") and card.sort_id or nil
  if sid == nil then return nil end
  local g = rawget(_G, "G")
  local hits = g and g.NEURO and g.NEURO.joker_hits
  local rec = (type(hits) == "table") and hits[sid] or nil
  if type(rec) ~= "table" then return nil end
  if not has_condition(card) then return nil end
  local hands = tonumber(rec.hands) or 0
  if hands < MIN_HANDS then return nil end
  local hits_n = tonumber(rec.fired) or 0
  if hits_n <= 0 and rec.outside then return nil end
  return hits_n, hands
end

function M.reset_run_state()
  _serial = 0
  _open = false
  _before_ctx = nil
  _after_ctx = nil
  _triggered = nil
end

if rawget(_G, "NEURO_TEST") then
  M._test = { MIN_HANDS = MIN_HANDS, fired = fired, is_query = is_query, has_condition = has_condition }
end

return M
