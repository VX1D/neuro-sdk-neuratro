local M = {}
local CardUtil = require("facts.card_util")
local GameFacts = require("facts.game_facts")

local BOSS_REROLL_COST = 10

local function is_credit_card(j)
  local center = j and j.config and j.config.center
  local key = center and center.key
  local name = (j and j.ability and j.ability.name) or (center and center.name)
  return key == "j_credit_card" or key == "j_credit" or name == "Credit Card"
end

local function credit_card_count()
  if not (G and G.jokers and G.jokers.cards) then return 0 end
  local n = 0
  for _, j in ipairs(G.jokers.cards) do
    if is_credit_card(j) then n = n + 1 end
  end
  return n
end

local function credit_floor_fallback()
  if not (G and G.jokers and G.jokers.cards) then return 0 end
  local total = 0
  for _, j in ipairs(G.jokers.cards) do
    if is_credit_card(j) and not j.debuff then
      total = total + ((j.ability and tonumber(j.ability.extra)) or 20)
    end
  end
  return total
end

local function spend_floor()
  local floor = tonumber(G and G.GAME and G.GAME.bankrupt_at or 0) or 0
  if floor >= 0 then
    local extra = credit_floor_fallback()
    if extra > 0 then return -extra end
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

local function below_spend_floor_reason(money)
  if (tonumber(money) or 0) >= spend_floor() then return nil end
  return "below floor from a boss blind's money penalty, not a purchase"
end

local function item_afford_status(card, area_label, spendable_amount)
  local cost = tonumber(card and card.cost) or 0
  if spendable_amount == nil then spendable_amount = spendable() end
  local afford = cost <= 0 or cost <= spendable_amount
  local has_space = CardUtil.can_buy_card_space(card, area_label)
  return { cost = cost, afford = afford, has_space = has_space, ok = afford and has_space }
end

local function no_interest()
  return not not (G and G.GAME and G.GAME.modifiers and G.GAME.modifiers.no_interest)
end

local function interest_amount() return (G and G.GAME and G.GAME.interest_amount) or 1 end
local function interest_cap() return (G and G.GAME and G.GAME.interest_cap) or 25 end

local function interest_units(money)
  return math.max(0, math.min(math.floor((tonumber(money) or 0) / 5), interest_cap() / 5))
end

local function calc_interest(money)
  if not (G and G.GAME) or no_interest() then return 0 end
  return interest_amount() * interest_units(money)
end

local function safe_spend_keep_interest()
  local sp = math.max(0, spendable())
  if no_interest() then return sp end
  local dollars = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0
  local steps = interest_units(dollars)
  if steps <= 0 then return sp end
  return math.max(0, math.min(sp, dollars - steps * 5))
end

local function max_interest() return interest_amount() * (interest_cap() / 5) end

local function interest_line(interest)
  if no_interest() then return "Interest disabled" end
  if interest == nil then
    interest = calc_interest(tonumber(G and G.GAME and G.GAME.dollars) or 0)
  end
  return "Interest +$" .. tostring(interest) .. " (cap $" .. tostring(interest_cap()) .. ")"
end

local function below_first_interest_step()
  if no_interest() then return false end
  if interest_amount() <= 0 or interest_cap() < 5 then return false end
  local money = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0
  return money >= 0 and money < 5
end

local function cheapest_buyable(spendable_amount)
  if spendable_amount == nil then spendable_amount = spendable() end
  local cheapest, can_buy_any = nil, false
  for _, entry in ipairs({
    { area = G and G.shop_jokers, label = "shop_jokers" },
    { area = G and G.shop_vouchers, label = "shop_vouchers" },
    { area = G and G.shop_booster, label = "shop_booster" },
  }) do
    if entry.area and entry.area.cards then
      for _, card in ipairs(entry.area.cards) do
        local status = item_afford_status(card, entry.label, spendable_amount)
        if status.has_space and status.cost >= 0 and (not cheapest or status.cost < cheapest) then
          cheapest = status.cost
        end
        if status.ok then can_buy_any = true end
      end
    end
  end
  return cheapest, can_buy_any
end

local function spend_posture()
  if not (G and G.GAME) then return nil end
  local jokers = (G.jokers and G.jokers.cards and #G.jokers.cards) or 0
  local ok_s, Scoring = pcall(require, "util.scoring")
  local has_xmult = (ok_s and Scoring and Scoring.owned_xmult_state
    and Scoring.owned_xmult_state() ~= "none") or false
  local ante = tonumber(GameFacts.ante(0)) or 0

  if jokers <= 1 then return { posture = "build", reason = "thin_roster" } end
  if not has_xmult and ante >= 2 then return { posture = "build", reason = "no_xmult" } end

  if no_interest() then return { posture = "either" } end
  local cheapest = cheapest_buyable()
  if cheapest == nil then return { posture = "either" } end
  if cheapest > (safe_spend_keep_interest() or 0) then
    return { posture = "bank", reason = "nothing_fits_safe_spend" }
  end
  return { posture = "either" }
end

local function economy_projection(opts)
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local current_round = G.GAME.current_round or {}
  local modifiers = G.GAME.modifiers or {}
  local hands_left = current_round.hands_left or 0
  if opts and opts.selecting_hand then hands_left = math.max(0, hands_left - 1) end
  local discards_left = current_round.discards_left or 0
  if opts and opts.exclude_action_bonus then hands_left = 0; discards_left = 0 end
  local blind = G.GAME.blind
  local blind_reward = (blind and blind.in_blind and blind.dollars) or 0
  if opts and opts.round_eval then blind_reward = GameFacts.blind_reward() end
  local hands_bonus = 0
  if hands_left > 0 and not modifiers.no_extra_hand_money then
    hands_bonus = hands_left * (modifiers.money_per_hand or 1)
  end
  local discard_bonus = 0
  if discards_left > 0 and modifiers.money_per_discard then
    discard_bonus = discards_left * modifiers.money_per_discard
  end
  local interest = calc_interest(money)
  return {
    blind_reward = blind_reward,
    hands_bonus = hands_bonus,
    discard_bonus = discard_bonus,
    interest = interest,
    projected_total = blind_reward + hands_bonus + discard_bonus + interest,
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

local function scaling_curve()
  if type(get_blind_amount) ~= "function" then return nil end
  local cur = GameFacts.ante(0)
  if cur < 1 then return nil end
  local win = (G and G.GAME and G.GAME.win_ante) or 8
  local scaling = (G.GAME and G.GAME.starting_params and G.GAME.starting_params.ante_scaling) or 1
  local fmt = require("util.utils").fmt_num
  local parts = {}
  local last = cur >= win and (cur + 2) or math.min(cur + 2, win)
  for a = cur + 1, last do
    local ok, base = pcall(get_blind_amount, a)
    if ok and type(base) == "number" then
      parts[#parts + 1] = string.format("ante %d ~%s", a, fmt(math.floor(base * scaling + 0.5)))
    end
  end
  if #parts == 0 then return nil end
  return "Requirement climbs -- next small blinds: " .. table.concat(parts, ", ") .. " (boss about 2x that). "
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
  local can = free > 0 or (type(effective) == "number" and effective >= 0
    and (effective == 0 or sp >= effective))
  return {
    current = rc, effective = effective, paid = paid, free = free,
    next = nextc, max_affordable = free + paid_n, can_reroll = can,
  }
end

M.BOSS_REROLL_COST = BOSS_REROLL_COST
M.credit_card_count = credit_card_count
M.reroll_cost = reroll_cost
M.reroll_facts = reroll_facts
M.scaling_curve = scaling_curve
M.spend_floor = spend_floor
M.spendable = spendable
M.item_afford_status = item_afford_status
M.can_reroll_boss = can_reroll_boss
M.blind_remaining = blind_remaining
M.below_spend_floor_reason = below_spend_floor_reason
M.calc_interest = calc_interest
M.no_interest = no_interest
M.safe_spend_keep_interest = safe_spend_keep_interest
M.interest_amount = interest_amount
M.interest_cap = interest_cap
M.interest_line = interest_line
M.max_interest = max_interest
M.below_first_interest_step = below_first_interest_step
M.cheapest_buyable = cheapest_buyable
M.spend_posture = spend_posture
local function payout_token(econ)
  econ = econ or {}
  local n = require("util.utils").fmt_num
  return string.format("B%s+hr%s+dr%s+I%s=T%s",
    n(econ.blind_reward or 0), n(econ.hands_bonus or 0), n(econ.discard_bonus or 0),
    n(econ.interest or 0), n(econ.projected_total or 0))
end

M.economy_projection = economy_projection
M.payout_token = payout_token
M.calc_blind_target = calc_blind_target

return M
