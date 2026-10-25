local M = {}

local MIN_HANDS = 3

local _serial = 0
local _open = false
local _before_ctx = nil
local _after_ctx = nil
local _triggered = nil
local _snap_ctx, _snap = nil, {}

local function store() return require("core.neuro_lifecycle").neuro_table("joker_hits") end

local IDENTITY = {}
for _, k in ipairs({ "chips", "h_chips", "chip_mod", "mult", "h_mult", "mult_mod", "p_dollars", "dollars",
  "h_dollars", "score", "h_score", "blind_size", "blindsize", "h_blind_size", "h_blindsize", "repetitions" }) do
  IDENTITY[k] = 0
end
for _, k in ipairs({ "x_chips", "xchips", "Xchip_mod", "x_mult", "Xmult", "xmult", "x_mult_mod", "Xmult_mod",
  "xscore", "x_score", "h_x_score", "h_xscore", "xblind_size", "x_blind_size", "xblindsize", "x_blindsize",
  "h_x_blind_size", "h_xblind_size", "h_x_blindsize", "h_xblindsize" }) do
  IDENTITY[k] = 1
end

local PRESENTATION = {
  message = true, colour = true, card = true, focus = true, message_card = true, juice_card = true,
  no_juice = true, sound = true, delay = true, instant = true, remove_default_message = true,
  dollar_message = true, no_retrigger = true, scored_card = true,
}

-- A debuffed held-card joker returns only this notice and pays nothing.
local function debuffed_notice(effect)
  local msg = effect.message
  if type(msg) ~= "string" then return false end
  local ok, text = pcall(localize, "k_debuffed")
  return ok and type(text) == "string" and text ~= "" and text ~= "ERROR" and msg == text
end

local function contributes(effect)
  if type(effect) ~= "table" then return effect ~= nil and effect ~= false end
  local valued = false
  for k, v in pairs(effect) do
    if k ~= "extra" then
      local identity = IDENTITY[k]
      if identity ~= nil then
        valued = true
        if v ~= identity then return true end
      elseif not PRESENTATION[k] then
        return true
      end
    end
  end
  if effect.extra ~= nil and contributes(effect.extra) then return true end
  return not valued and not debuffed_notice(effect)
end

local function fired(eval)
  if type(eval) ~= "table" then return false end
  return eval.retriggers ~= nil or (eval.jokers ~= nil and contributes(eval.jokers))
end

local function is_query(context)
  if type(context) ~= "table" then return false end
  if context.retrigger_joker_check then return true end
  local ok, res = pcall(function() return SMODS.is_getter_context(context) end)
  return ok and res and true or false
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

local function payout_blind(gate)
  return gate.kind == "odds" or gate.kind == "random" or gate.unconditional == true
end

local function payout_kind(card)
  local key = card and card.config and card.config.center and card.config.center.key
  local ok_dj, DynamicJokers = pcall(require, "facts.dynamic_jokers")
  local declared = ok_dj and key and DynamicJokers.ROWS[key] or nil
  if type(declared) == "table" and #declared > 0 then
    local kind = "growth"
    for _, row in ipairs(declared) do
      if row.gate and not row.rescore then
        if not payout_blind(row.gate) then return "condition" end
        kind = "blind"
      end
    end
    return kind
  end
  local ok, projection = pcall(function() return require("facts.card_semantics").project(card) end)
  if not ok or type(projection) ~= "table" then return "growth" end
  local kind = "growth"
  for _, e in ipairs(projection.effects or {}) do
    local g = e.source ~= "edition" and e.gate
    if g and g.kind ~= "rescored" and g.kind ~= "unmodelled" and not e.guessed then
      if not payout_blind(g) then return "condition" end
      kind = "blind"
    end
  end
  return kind
end

local function numbers_of(ability)
  local out = {}
  if type(ability) ~= "table" then return out end
  for k, v in pairs(ability) do
    if type(v) == "number" then out[k] = v end
  end
  local extra = ability.extra
  if type(extra) == "number" then
    out["extra"] = extra
  elseif type(extra) == "table" then
    for k, v in pairs(extra) do
      if type(v) == "number" then out["extra." .. tostring(k)] = v end
    end
  end
  return out
end

local function grew(was, now)
  for k, v in pairs(now) do
    if type(was[k]) == "number" and v > was[k] then return true end
  end
  return false
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

function M.note_pre(card, context)
  if type(context) ~= "table" or type(card) ~= "table" or card.sort_id == nil then return end
  local ability = card.ability
  if type(ability) ~= "table" or ability.set ~= "Joker" then return end
  if context.before then
    if context ~= _snap_ctx then _snap_ctx, _snap = context, {} end
    _snap[card.sort_id] = numbers_of(ability)
  elseif context.after then
    local was = _snap[card.sort_id]
    _snap[card.sort_id] = nil
    if not (was and _open and grew(was, numbers_of(ability))) then return end
    local hits = store()
    local rec = hits and hits[card.sort_id]
    if type(rec) == "table" and rec.grew_hit ~= _serial then
      rec.grew_hit = _serial
      rec.grew = (tonumber(rec.grew) or 0) + 1
    end
  end
end

function M.install()
  if rawget(_G, "__neuro_joker_hits_guard") then return false end
  local orig = rawget(_G, "eval_card")
  if type(orig) ~= "function" then return false end
  _G.__neuro_joker_hits_guard = true
  _G.eval_card = function(card, context)
    pcall(M.note_pre, card, context)
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
  local kind = payout_kind(card)
  if kind == "growth" and (tonumber(rec.grew) or 0) > 0 then
    return tonumber(rec.grew), hands, "held"
  end
  local hits_n = tonumber(rec.fired) or 0
  if hits_n <= 0 and rec.outside then return nil end
  if kind == "condition" then return hits_n, hands, "held" end
  return hits_n, hands, "paid", kind
end

function M.unconditional(card)
  return pays_from_a_calculate_context(card) and not has_condition(card)
end

function M.reset_run_state()
  _serial = 0
  _open = false
  _before_ctx = nil
  _after_ctx = nil
  _triggered = nil
  _snap_ctx, _snap = nil, {}
end

M.is_query = is_query
M.contributes = contributes

return M
