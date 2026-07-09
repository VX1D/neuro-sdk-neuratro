local Utils = require("util.utils")
local CtxHelpers = require("context.ctx_helpers")
local CtxEconomy = require("context.ctx_economy")
local CardUtil = require("facts.card_util")
local compact_text = CtxHelpers.compact_text
local card_effect_summary = CtxHelpers.card_effect_summary
local card_description_full = CtxHelpers.card_description_full
local has_action = CtxHelpers.has_action
local safe_name_or = Utils.safe_name_or
local calc_interest = CtxEconomy.calc_interest
local economy_projection = CtxEconomy.economy_projection
-- buy-space predicates owned by card_util; don't copy here (drift risk)
local card_set = CardUtil.card_set
local booster_kind = CardUtil.booster_kind

local RARITY_ABBR = { Common = "C", Uncommon = "U", Rare = "R", Legendary = "L" }
local function row_rarity(card)
  local center = card and card.config and card.config.center
  if not center or center.set ~= "Joker" then return "-" end
  return RARITY_ABBR[CardUtil.rarity_name(center.rarity)] or "-"
end

local function legality_section(state_name, action_set)
  if not G then return nil end

  if state_name == "SHOP" then
    local spendable = CtxEconomy.spendable()
    local rf = CtxEconomy.reroll_facts()
    local can_reroll = rf.can_reroll and "Y" or "N"
    local can_sell = (CardUtil.joker_count() > 0 or CardUtil.consumable_count() > 0) and "Y" or "N"
    local can_use = (CardUtil.consumable_count() > 0) and "Y" or "N"

    local can_buy_any = "N"
    local cheapest = nil
    local areas = {
      { area = G.shop_jokers, label = "shop_jokers" },
      { area = G.shop_vouchers, label = "shop_vouchers" },
      { area = G.shop_booster, label = "shop_booster" },
    }
    -- cheapest must track only slot-buyable items, else CRS gets marked unsafe by an unbuyable item
    for _, entry in ipairs(areas) do
      if entry.area and entry.area.cards then
        for _, card in ipairs(entry.area.cards) do
          local status = CtxEconomy.item_afford_status(card, entry.label)
          if status.has_space and status.cost >= 0 then
            if not cheapest or status.cost < cheapest then
              cheapest = status.cost
            end
          end
          if status.ok then
            can_buy_any = "Y"
          end
        end
      end
    end

    local reroll_safe
    if type(cheapest) ~= "number" then
      reroll_safe = "-"
    elseif rf.free > 0 or (type(rf.effective) == "number" and rf.effective <= 0) then
      reroll_safe = "Y"
    elseif type(rf.effective) == "number" and rf.effective > 0 then
      reroll_safe = ((spendable - rf.effective) >= cheapest) and "Y" or "N"
    else
      reroll_safe = "N"
    end

    return string.format("LA|CB:%s|CR:%s|CRS:%s|CS:%s|CU:%s", can_buy_any, can_reroll, reroll_safe, can_sell, can_use)
  end

  if state_name == "RUN_SETUP" or state_name == "MENU" then
    local function avail(name)
      if action_set and next(action_set) then return has_action(action_set, name) end
      local ok_a, A = pcall(require, "core.actions")
      return not not (ok_a and A and A.is_action_valid and A.is_action_valid(name))
    end
    local has_deck_switch = avail("change_selected_back") and "Y" or "N"
    local can_start = (avail("start_setup_run")
      or avail("start_challenge_run")
      or avail("setup_run")) and "Y" or "N"
    return string.format("LA|SR:%s|DS:%s", can_start, has_deck_switch)
  end

  return nil
end

local function shop_section()
  if not G or not G.GAME then return nil end
  local money = G.GAME.dollars or 0
  local spendable = CtxEconomy.spendable()
  local discount = G.GAME.discount_percent or 0
  local inflation = G.GAME.inflation or 0
  local interest = calc_interest(money)
  local no_interest = CtxEconomy.no_interest() and "Y" or "N"
  local ante = G.GAME.round_resets and G.GAME.round_resets.ante or "?"
  local econ = economy_projection({ exclude_action_bonus = true })
  local interest_cap = CtxEconomy.interest_cap()
  local rf = CtxEconomy.reroll_facts()
  local free_rerolls = rf.free
  local spend_floor = CtxEconomy.spend_floor()
  local at_interest_cap = money >= interest_cap
  local to_next_interest = 5 - (money % 5)

  local function num_or_q(v) return type(v) == "number" and tostring(v) or "?" end
  local lines = {}
  -- joker/consumable slot counts live on the J:/C: section headers, not here
  local sh_line = string.format("SH|A:%s|$:%d|SP:%d|IN:+%d|CAP:%d|NI:%s|RR:%s|RRN:%s|RRM:%d|PY:%s",
    tostring(ante), money, math.floor(spendable), interest, interest_cap, no_interest,
    num_or_q(rf.effective), num_or_q(rf.next), rf.max_affordable,
    CtxEconomy.payout_token(econ))
  if spend_floor < 0 then sh_line = sh_line .. "|FLOOR:" .. tostring(spend_floor) end
  if at_interest_cap then
    sh_line = sh_line .. "|MAXED:Y"
  elseif no_interest == "N" then
    sh_line = sh_line .. "|NXT:" .. tostring(to_next_interest)
  end
  if free_rerolls > 0 then sh_line = sh_line .. "|FR:" .. tostring(free_rerolls) end
  if discount > 0 then sh_line = sh_line .. "|DSC:" .. tostring(discount) .. "%" end
  if inflation > 0 then sh_line = sh_line .. "|INF:" .. tostring(inflation) end
  lines[#lines + 1] = sh_line
  local areas = {
    { area = G.shop_jokers, label = "shop_jokers" },
    { area = G.shop_vouchers, label = "shop_vouchers" },
    { area = G.shop_booster, label = "shop_booster" },
  }
  local has_items = false
  for _, entry in ipairs(areas) do
    if entry.area and entry.area.cards and #entry.area.cards > 0 then
      if not has_items then
        lines[#lines + 1] = "I:a,i,n,t,rar,$,ok,f,d"
        has_items = true
      end
      for i, card in ipairs(entry.area.cards) do
        local name = compact_text(safe_name_or(card), 28)
        local cost = tonumber(card.cost or 0) or 0
        local can_afford = CtxEconomy.item_afford_status(card, entry.label).ok and "Y" or "N"
        local ctype = card_set(card)
        -- card_set collapses every pack to "Booster"; booster_kind gives the real kind (Buffoon/Celestial/Arcana/Spectral)
        if ctype == "Booster" then
          local bk = booster_kind(card)
          if bk ~= "" then ctype = bk end
        end
        if ctype == "Default" then ctype = "Playing" end
        if not ctype or ctype == "" then ctype = "?" end
        local rar = row_rarity(card)
        local eff = card_effect_summary(card)
        local desc = card_description_full(card, 140)
        if desc == eff then desc = "-" end
        lines[#lines + 1] = string.format("%s,%d,%s,%s,%s,$%d,%s,%s,%s",
          entry.label, i, name, ctype, rar, cost, can_afford, eff, desc)
      end
    end
  end
  if not has_items then
    lines[#lines + 1] = "I:empty"
  end

  return table.concat(lines, "\n")
end

return { legality_section = legality_section, shop_section = shop_section }
