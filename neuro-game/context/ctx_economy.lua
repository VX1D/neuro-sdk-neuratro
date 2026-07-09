local M = {}
local CardUtil = require("facts.card_util")

local BOSS_REROLL_COST = 10

local function credit_card_count()
  if not (G and G.jokers and G.jokers.cards) then return 0 end
  local n = 0
  for _, j in ipairs(G.jokers.cards) do
    local center = j and j.config and j.config.center
    local key = center and center.key
    local name = (j and j.ability and j.ability.name) or (center and center.name)
    if key == "j_credit_card" or key == "j_credit" or name == "Credit Card" then
      n = n + 1
    end
  end
  return n
end

local function spend_floor()
  local floor = tonumber(G and G.GAME and G.GAME.bankrupt_at or 0) or 0
  if floor >= 0 then
    local cc = credit_card_count()
    if cc > 0 then return -20 * cc end
  end
  return floor
end

local function spendable()
  local dollars = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0
  local reserved = tonumber(G and G.NEURO and G.NEURO.reserved_dollars or 0) or 0
  return dollars - reserved - spend_floor()
end

local function owns_voucher(key)
  return not not (G and G.GAME and G.GAME.used_vouchers and G.GAME.used_vouchers[key])
end

local function can_reroll_boss()
  local boss_not_rerolled = not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.boss_rerolled)
  local enabled = owns_voucher("v_retcon") or (owns_voucher("v_directors_cut") and boss_not_rerolled)
  return (enabled and spendable() >= BOSS_REROLL_COST), enabled
end

local function blind_type(blind)
  blind = blind or (G and G.GAME and G.GAME.blind)
  if not (blind and blind.get_type) then return nil end
  local ok, bt = pcall(blind.get_type, blind)
  if ok and bt then return bt end
  return nil
end

local function blind_target(blind)
  blind = blind or (G and G.GAME and G.GAME.blind)
  return blind and tonumber(blind.chips) or nil
end

local function blind_remaining(blind)
  local t = blind_target(blind)
  if not t then return nil end
  local score = tonumber(G and G.GAME and G.GAME.chips or 0) or 0
  return math.max(0, t - score)
end

local function item_afford_status(card, area_label)
  local cost = tonumber(card and card.cost) or 0
  local afford = cost <= 0 or cost <= spendable()
  local has_space = CardUtil.can_buy_card_space(card, area_label)
  return { cost = cost, afford = afford, has_space = has_space, ok = afford and has_space }
end

local function calc_interest(money)
  if not G or not G.GAME then return 0 end
  if G.GAME.modifiers and G.GAME.modifiers.no_interest then
    return 0
  end
  local amount = G.GAME.interest_amount or 1
  local cap = G.GAME.interest_cap or 25
  local units = math.max(0, math.min(math.floor((money or 0) / 5), cap / 5))
  return amount * units
end

local function no_interest()
  return not not (G and G.GAME and G.GAME.modifiers and G.GAME.modifiers.no_interest)
end

local function safe_spend_keep_interest()
  local dollars = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0
  return math.max(0, dollars - calc_interest(dollars) * 5)
end

local function interest_amount() return (G and G.GAME and G.GAME.interest_amount) or 1 end
local function interest_cap() return (G and G.GAME and G.GAME.interest_cap) or 25 end
local function max_interest() return interest_amount() * (interest_cap() / 5) end
local function rate_pct() return interest_amount() * 20 end

local function economy_projection(opts)
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local current_round = G.GAME.current_round or {}
  local modifiers = G.GAME.modifiers or {}
  local hands_left = current_round.hands_left or 0
  if opts and opts.selecting_hand then hands_left = math.max(0, hands_left - 1) end
  local discards_left = current_round.discards_left or 0
  -- pre-round: no hands/discards committed yet, don't project their reward as income
  if opts and opts.exclude_action_bonus then hands_left = 0; discards_left = 0 end
  -- blind.dollars is stale after cash-out; only an in-progress blind (blind.in_blind) still owes its reward
  local blind = G.GAME.blind
  local blind_reward = (blind and blind.in_blind and blind.dollars) or 0
  local hands_bonus = 0
  if hands_left > 0 and not modifiers.no_extra_hand_money then
    hands_bonus = hands_left * (modifiers.money_per_hand or 1)
  end
  local discard_bonus = 0
  if discards_left > 0 and modifiers.money_per_discard then
    discard_bonus = discards_left * modifiers.money_per_discard
  end
  local interest = calc_interest(money)
  -- dollars_to_be_earned is a string of N literal '$' chars (blind.lua:140); the amount is the COUNT, not tonumber(str)
  local dtb = current_round.dollars_to_be_earned
  local dollars_to_be_earned = tonumber(dtb) or 0
  if dollars_to_be_earned == 0 and type(dtb) == "string" then
    local _, n = dtb:gsub("%$", "")
    dollars_to_be_earned = n
  end
  return {
    blind_reward = blind_reward,
    hands_bonus = hands_bonus,
    discard_bonus = discard_bonus,
    interest = interest,
    projected_total = blind_reward + hands_bonus + discard_bonus + interest,
    end_round_earnings = dollars_to_be_earned,
  }
end

local function calc_blind_target(blind_key)
  if not (G and G.GAME and G.P_BLINDS and blind_key and G.P_BLINDS[blind_key]) then
    return nil
  end
  local base = nil
  if type(get_blind_amount) == "function" then
    local ante = (G.GAME.round_resets and G.GAME.round_resets.blind_ante)
      or (G.GAME.round_resets and G.GAME.round_resets.ante)
      or 1
    local ok, result = pcall(get_blind_amount, ante)
    if ok and type(result) == "number" then
      base = result
    end
  end
  if not base then return nil end

  local blind_def = G.P_BLINDS[blind_key]
  local mult = blind_def.mult or (blind_def.config and blind_def.config.mult) or 1
  local scaling = G.GAME.starting_params and G.GAME.starting_params.ante_scaling or 1
  return math.floor(base * mult * scaling + 0.5)
end

local function reroll_cost()
  return tonumber(G and G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost)
end

local function reroll_facts()
  local cr = (G and G.GAME and G.GAME.current_round) or {}
  local free = tonumber(cr.free_rerolls) or 0
  local rc = reroll_cost()
  local paid = rc
  if free > 0 then
    local rr = (G and G.GAME and G.GAME.round_resets) or {}
    paid = tonumber(rr.temp_reroll_cost) or tonumber(rr.reroll_cost) or rc
    if paid then paid = paid + (tonumber(cr.reroll_cost_increase) or 0) end
  end
  local effective = free > 0 and 0 or rc
  local sp = spendable()
  -- cr.reroll_cost_increase is the CUMULATIVE reroll count this round, not the per-step delta; the actual escalation is a fixed +1/reroll
  local inc = 1
  local paid_n = 0
  if type(paid) == "number" and paid >= 0 then
    local s, c = math.max(0, sp), paid
    while s >= c and paid_n < 20 do paid_n = paid_n + 1; s = s - c; c = c + inc end
  end
  local nextc
  if free > 1 then nextc = 0
  elseif free == 1 then nextc = paid
  elseif type(rc) == "number" then nextc = rc + inc end
  local can = free > 0 or (type(effective) == "number" and effective >= 0 and sp >= effective)
  return {
    current = rc, effective = effective, paid = paid, free = free,
    next = nextc, max_affordable = free + paid_n, can_reroll = can,
  }
end

M.BOSS_REROLL_COST = BOSS_REROLL_COST
M.reroll_cost = reroll_cost
M.reroll_facts = reroll_facts
M.spend_floor = spend_floor
M.spendable = spendable
M.item_afford_status = item_afford_status
M.owns_voucher = owns_voucher
M.can_reroll_boss = can_reroll_boss
M.blind_type = blind_type
M.blind_target = blind_target
M.blind_remaining = blind_remaining
M.calc_interest = calc_interest
M.no_interest = no_interest
M.safe_spend_keep_interest = safe_spend_keep_interest
M.interest_amount = interest_amount
M.interest_cap = interest_cap
M.max_interest = max_interest
M.rate_pct = rate_pct
local function payout_token(econ)
  econ = econ or {}
  return string.format("B%d+hr%d+dr%d+I%d=T%d",
    econ.blind_reward or 0, econ.hands_bonus or 0, econ.discard_bonus or 0,
    econ.interest or 0, econ.projected_total or 0)
end

M.economy_projection = economy_projection
M.payout_token = payout_token
M.calc_blind_target = calc_blind_target

return M
