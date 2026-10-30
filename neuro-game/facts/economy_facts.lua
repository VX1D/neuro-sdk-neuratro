local M = {}
local Utils = require("util.utils")
local CardUtil = require("facts.card_util")
local GameFacts = require("facts.game_facts")

local BOSS_REROLL_COST = 10
local TOOTH_PER_CARD = 1

local function spend_floor()
  return tonumber(G and G.GAME and G.GAME.bankrupt_at or 0) or 0
end

local function spendable()
  local dollars = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0
  local reserved = tonumber(G and G.NEURO and G.NEURO.reserved_dollars or 0) or 0
  return dollars - reserved - spend_floor()
end

local function owns_voucher(key)
  return not not (G and G.GAME and G.GAME.used_vouchers and G.GAME.used_vouchers[key])
end

function M.can_reroll_boss()
  local boss_not_rerolled = not (G and G.GAME and G.GAME.round_resets and G.GAME.round_resets.boss_rerolled)
  local enabled = owns_voucher("v_retcon") or (owns_voucher("v_directors_cut") and boss_not_rerolled)
  local spent = not enabled and owns_voucher("v_directors_cut")
  return (enabled and spendable() >= BOSS_REROLL_COST), enabled, spent
end

function M.blind_remaining(blind)
  blind = blind or (G and G.GAME and G.GAME.blind)
  local t = blind and tonumber(blind.chips)
  if not t then return nil end
  local score = tonumber(G and G.GAME and G.GAME.chips or 0) or 0
  return math.max(0, t - score)
end

function M.below_spend_floor_reason(money)
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

function M.max_interest() return interest_amount() * (interest_cap() / 5) end

function M.interest_line(interest)
  if no_interest() then return "Interest disabled" end
  if interest == nil then
    interest = calc_interest(tonumber(G and G.GAME and G.GAME.dollars) or 0)
  end
  return "Interest " .. Utils.money_change(interest) .. " (cap " .. Utils.money(interest_cap()) .. ")"
end

function M.below_first_interest_step()
  if no_interest() then return false end
  if interest_amount() <= 0 or interest_cap() < 5 then return false end
  local money = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0
  return money >= 0 and money < 5
end

local function cheapest_buyable(spendable_amount, after_reroll)
  if spendable_amount == nil then spendable_amount = spendable() end
  local cheapest, can_buy_any = nil, false
  for _, entry in ipairs({
    { area = G and G.shop_jokers, label = "shop_jokers" },
    { area = G and G.shop_vouchers, label = "shop_vouchers" },
    { area = G and G.shop_booster, label = "shop_booster" },
  }) do
    if entry.area and entry.area.cards and not (after_reroll and entry.label == "shop_jokers") then
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

function M.spend_posture()
  if not (G and G.GAME) then return nil end
  local jokers = (G.jokers and G.jokers.cards and #G.jokers.cards) or 0
  local has_xmult = require("util.scoring").owned_xmult_state() ~= "none"
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

function M.economy_projection(opts)
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local current_round = G.GAME.current_round or {}
  local modifiers = G.GAME.modifiers or {}
  local hands_left = current_round.hands_left or 0
  if opts and opts.selecting_hand then hands_left = math.max(0, hands_left - 1) end
  local discards_left = current_round.discards_left or 0
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
  -- Rental is charged before interest is evaluated and remains charged while debuffed.
  local rent = 0
  if not (opts and opts.round_eval) then
    local PublicCard = require("facts.public_card_identity")
    for _, j in ipairs((G.jokers and G.jokers.cards) or {}) do
      if PublicCard.is_public(j) and j.ability and j.ability.rental then rent = rent + (tonumber(G.GAME.rental_rate) or 3) end
    end
  end
  local bank = money - rent
  local interest = calc_interest(bank)
  local out = { blind_reward = blind_reward, hands_bonus = hands_bonus, discard_bonus = discard_bonus, rent = rent }
  -- The Tooth charges per card, and The Ox zeros cash on its most-played hand before interest.
  if opts and opts.selecting_hand then
    local DebuffFacts = require("facts.debuff_facts")
    if DebuffFacts.tooth_active() then
      local lo_n, hi_n = require("facts.boss.legality").play_size_bounds()
      out.tooth = {
        per_card = TOOTH_PER_CARD, min_cards = lo_n, max_cards = hi_n,
        interest_max = calc_interest(bank - TOOTH_PER_CARD * lo_n),
      }
      interest = calc_interest(bank - TOOTH_PER_CARD * hi_n)
    end
    if DebuffFacts.ox_active() then out.ox_hand = DebuffFacts.most_played_hand() end
  end
  out.interest = interest
  out.projected_total = blind_reward + hands_bonus + discard_bonus + interest
  if out.tooth then out.tooth.projected_max = out.projected_total - interest + out.tooth.interest_max end
  return out
end

function M.calc_blind_target(blind_key)
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

local function boss_mults()
  local count, lo, hi = {}, nil, nil
  for _, v in pairs(G and G.P_BLINDS or {}) do
    local m = type(v) == "table" and v.boss and tonumber(v.mult)
    if m then
      count[m] = (count[m] or 0) + 1
      lo, hi = math.min(lo or m, m), math.max(hi or m, m)
    end
  end
  local usual
  for m, n in pairs(count) do
    if not usual or n > count[usual] or (n == count[usual] and m < usual) then usual = m end
  end
  return usual, lo, hi
end

local function boss_note(ante, base, scaling, fmt)
  local rr = G.GAME.round_resets or {}
  local key = rr.blind_choices and rr.blind_choices.Boss
  local def = ante == GameFacts.ante(0) and type(key) == "string" and G.P_BLINDS and G.P_BLINDS[key]
  local mult = def and tonumber(def.mult)
  if mult and require("facts.boss.model").upcoming_is_public(rr) then
    local name = require("facts.display_names").blind(key) or def.name or key
    return string.format(" (its boss %s is %sx: ~%s)", tostring(name), fmt(mult),
      fmt(math.floor(base * mult * scaling + 0.5)))
  end
  local usual, lo, hi = boss_mults()
  if not usual then return "" end
  if lo == hi then return string.format(" (boss %sx that)", fmt(usual)) end
  return string.format(" (boss not drawn yet: usually %sx that, %sx to %sx across all bosses)",
    fmt(usual), fmt(lo), fmt(hi))
end

function M.scaling_curve()
  if type(get_blind_amount) ~= "function" then return nil end
  local cur = GameFacts.ante(0)
  if cur < 1 then return nil end
  local win = (G and G.GAME and G.GAME.win_ante) or 8
  local scaling = (G.GAME and G.GAME.starting_params and G.GAME.starting_params.ante_scaling) or 1
  local fmt = require("util.utils").fmt_num
  local states = G.GAME.round_resets and G.GAME.round_resets.blind_states
  local small = type(states) == "table" and states.Small or nil
  local first = (small == "Select" or small == "Upcoming") and cur or cur + 1
  local parts = {}
  local last = cur >= win and (first + 1) or math.min(first + 1, win)
  for a = first, last do
    local ok, base = pcall(get_blind_amount, a)
    if ok and type(base) == "number" then
      parts[#parts + 1] = string.format("ante %d ~%s", a, fmt(math.floor(base * scaling + 0.5)))
        .. boss_note(a, base, scaling, fmt)
    end
  end
  if #parts == 0 then return nil end
  return "Requirement climbs -- next small blinds: " .. table.concat(parts, ", ") .. ". "
end

local function reroll_cost()
  return tonumber(G and G.GAME and G.GAME.current_round and G.GAME.current_round.reroll_cost)
end

local function paid_rerolls_for(budget, paid)
  local n = 0
  if type(paid) == "number" and paid >= 0 then
    local s, c = math.max(0, tonumber(budget) or 0), paid
    while s >= c and n < 20 do n = n + 1; s = s - c; c = c + 1 end
  end
  return n
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
  local paid_n = paid_rerolls_for(sp, paid)
  local nextc
  if free > 1 then nextc = 0
  elseif free == 1 then nextc = paid
  elseif type(rc) == "number" then nextc = rc + 1 end
  local can = free > 0 or (type(effective) == "number" and effective >= 0
    and (effective == 0 or sp >= effective))
  return {
    current = rc, effective = effective, paid = paid, free = free,
    next = nextc, max_affordable = free + paid_n, can_reroll = can,
  }
end

local BANK_SCALING = { j_bull = true, j_bootstraps = true }

local function owned_public(area, keys)
  local PublicCard = require("facts.public_card_identity")
  local found = {}
  for _, c in ipairs((area and area.cards) or {}) do
    local key = CardUtil.center_key(c)
    if keys[key] and PublicCard.is_public(c) and not c.debuff then found[#found + 1] = c end
  end
  return found
end

-- With no interest, reserve the reroll cost or The Hermit payout, whichever is larger.
function M.reserve_model()
  if not (G and G.GAME) then return nil end
  local bank = tonumber(G.GAME.dollars) or 0
  if not no_interest() then
    local cap = interest_cap()
    return { interest = true, bank = bank, reserve = cap, surplus = bank - cap, basis = "interest_cap" }
  end
  local rr = G.GAME.round_resets or {}
  local reserve = math.max(0, tonumber(rr.reroll_cost) or tonumber(reroll_cost()) or 0)
  local basis = "reroll"
  for _, c in ipairs(owned_public(G.consumeables, { c_hermit = true })) do
    local cap = tonumber(c.ability and c.ability.extra) or 20
    if cap > reserve then reserve, basis = cap, "hermit" end
  end
  local surplus = bank - reserve
  local rf = reroll_facts()
  local rerolls = 0
  if surplus > 0 then rerolls = math.max(0, rf.free) + paid_rerolls_for(surplus, rf.paid) end
  return {
    interest = false, bank = bank, reserve = reserve, surplus = surplus, basis = basis,
    rerolls = rerolls, bank_scaling = #owned_public(G.jokers, BANK_SCALING) > 0,
  }
end

M.BOSS_REROLL_COST = BOSS_REROLL_COST
function M.credit_card_count()
  return require("facts.text").count(G and G.jokers and G.jokers.cards or {}, function(j)
    return CardUtil.center_key(j) == "j_credit_card" and not j.debuff
  end)
end
M.reroll_cost = reroll_cost
M.reroll_facts = reroll_facts
M.spend_floor = spend_floor
M.spendable = spendable
M.item_afford_status = item_afford_status
M.calc_interest = calc_interest
M.no_interest = no_interest
M.safe_spend_keep_interest = safe_spend_keep_interest
M.interest_amount = interest_amount
M.interest_cap = interest_cap
M.cheapest_buyable = cheapest_buyable


return M
