local Utils = require("util.utils")
local GameFacts = require("facts.game_facts")
local CtxHelpers = require("context.ctx_helpers")
local CtxEconomy = require("facts.economy_facts")
local CardUtil = require("facts.card_util")
local SemanticRegistry = require("core.semantic_registry")
local normalize_text = CtxHelpers.normalize_text
local has_action = CtxHelpers.has_action
local safe_name_or = Utils.safe_name_or
local calc_interest = CtxEconomy.calc_interest
local economy_projection = CtxEconomy.economy_projection
local card_set = CardUtil.card_set
local booster_kind = CardUtil.booster_kind
local money = CtxHelpers.money
local yn = CtxHelpers.yn
local decode_payout = CtxHelpers.decode_payout
local humanize_effect = CtxHelpers.humanize_effect

local REQUIREMENT_ACTIONS = {
  { "buy", "buy_from_shop" },
  { "reroll", "reroll_shop" },
  { "sell", "sell_card" },
  { "use", "use_card" },
  { "leave", "toggle_shop" },
}
local PLAN_FIELD_ORDER = { "hand", "build", "money" }
local ACTION_PHRASE = {
  buy = "buying", reroll = "rerolling", sell = "selling",
  use = "using a consumable", leave = "leaving the shop",
}
local function join_phrases(list)
  if #list == 1 then return list[1] end
  if #list == 2 then return list[1] .. " and " .. list[2] end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
local function requirement_prose(legal)
  local ok, PlanGate = pcall(require, "core.plan_gate")
  if not ok or not PlanGate then return nil end
  local clauses = {}
  for _, pair in ipairs(REQUIREMENT_ACTIONS) do
    local label, action_name = pair[1], pair[2]
    if not (legal and legal[label] == false) then
      local requirements = PlanGate.action_requirements("SHOP", action_name)
      local parts = {}
      for _, field in ipairs(PLAN_FIELD_ORDER) do
        if requirements.plan[field] then parts[#parts + 1] = "plan." .. field .. "_plan" end
      end
      if #parts > 0 then
        clauses[#clauses + 1] = (ACTION_PHRASE[label] or label) .. ": include " .. join_phrases(parts)
      end
    end
  end
  if #clauses == 0 then return nil end
  return "Action requirements (same action payload): " .. table.concat(clauses, "; ") .. "."
end

local function legality_section(state_name, action_set)
  if not G then return nil end

  if state_name == "SHOP" then
    local spendable = CtxEconomy.spendable()
    local rf = CtxEconomy.reroll_facts()
    local can_reroll = rf.can_reroll
    local function available(name)
      if type(action_set) == "table" and next(action_set) then
        return has_action(action_set, name)
      end
      local ok_a, A = pcall(require, "core.actions")
      return not not (ok_a and A and A.is_action_valid and A.is_action_valid(name))
    end
    local can_sell = available("sell_card")
    local can_use = available("use_card") or available("use_directional_card")

    local cheapest, can_buy_any = CtxEconomy.cheapest_buyable(spendable)

    local reroll_safe = false
    if type(cheapest) == "number" then
      if rf.free > 0 or (type(rf.effective) == "number" and rf.effective <= 0) then
        reroll_safe = true
      elseif type(rf.effective) == "number" and rf.effective > 0 then
        reroll_safe = (spendable - rf.effective) >= cheapest
      end
    end

    local s = string.format("Legality: can buy something: %s; can reroll: %s (still affordable after: %s); can sell: %s; can use a consumable: %s.",
      yn(can_buy_any), yn(can_reroll), yn(reroll_safe), yn(can_sell), yn(can_use))
    local req = requirement_prose({ buy = can_buy_any, reroll = can_reroll, sell = can_sell, use = can_use })
    if req then s = s .. " " .. req end
    return s
  end

  if state_name == "RUN_SETUP" or state_name == "MENU" then
    local function avail(name)
      if action_set and next(action_set) then return has_action(action_set, name) end
      local ok_a, A = pcall(require, "core.actions")
      return not not (ok_a and A and A.is_action_valid and A.is_action_valid(name))
    end
    local has_deck_switch = avail("change_selected_back")
    local can_start = avail("start_setup_run") or avail("start_challenge_run") or avail("setup_run")
    return string.format("Legality: can start run: %s; can switch deck: %s.", yn(can_start), yn(has_deck_switch))
  end

  return nil
end

local BOOSTER_ROLE = {
  Buffoon = "pack of Jokers", Arcana = "pack of Tarot consumables",
  Celestial = "pack of Planet consumables", Spectral = "pack of Spectral consumables",
  Standard = "pack of playing cards",
}
local function shop_item_role(area, typ)
  if area == "shop_booster" then return BOOSTER_ROLE[typ] end
  if area == "shop_jokers" and CardUtil.is_consumable_set(typ) then
    return "a consumable, not a Joker -- buy with area shop_jokers, it fills a consumable slot"
  end
  return nil
end

local function shop_item_line(entry, i, card, spendable_amount)
  local name = normalize_text(safe_name_or(card))
  local cost = tonumber(card.cost or 0) or 0
  local afford_status = CtxEconomy.item_afford_status(card, entry.label, spendable_amount)
  local ctype = card_set(card)
  if ctype == "Booster" then
    local bk = booster_kind(card)
    if bk ~= "" then ctype = bk end
  end
  if ctype == "Default" then ctype = "Playing" end
  if not ctype or ctype == "" then ctype = "?" end
  local center = card and card.config and card.config.center
  local rarity = (center and center.set == "Joker") and CardUtil.rarity_name(center.rarity) or nil
  local raw_eff = SemanticRegistry.render("shop_card_row", card)
  local suffix = CardUtil.planet_run_state_suffix(card):gsub("^; ", "")
  local desc = SemanticRegistry.render("card_description_full", card)
  if desc == "" or desc == raw_eff then
    desc = nil
  else
    local nd = desc:lower():gsub("[^%w]", "")
    local ne = raw_eff:lower():gsub("[^%w]", "")
    if nd ~= "" and ne:find(nd, 1, true) then desc = nil end
  end

  local area = entry.label:gsub("_", " ")
  local s = area .. " slot " .. i .. ": " .. name .. " (" .. ctype
  if rarity then s = s .. ", " .. rarity end
  s = s .. ")"
  local role = shop_item_role(entry.label, ctype)
  if role then s = s .. " [" .. role .. "]" end
  s = s .. string.format(" $%d, affordable now: %s", cost, yn(afford_status.afford))
  if entry.label == "shop_jokers" then
    s = s .. string.format(", free slot: %s", yn(afford_status.has_space))
    if rarity then
      local owned = (G and G.jokers and G.jokers.cards) and #G.jokers.cards or 0
      if afford_status.has_space then
        s = s .. string.format(", lands rightmost (joker slot %d)", owned + 1)
      else
        s = s .. ", lands rightmost"
      end
    end
  end
  local bank = tonumber(G and G.GAME and G.GAME.dollars) or 0
  local interest_cost = calc_interest(bank) - calc_interest(bank - cost)
  if interest_cost > 0 then s = s .. string.format(", interest cost: $%d", interest_cost) end
  local eff_h = (raw_eff ~= "-" and raw_eff ~= "") and humanize_effect(raw_eff) or ""
  if suffix ~= "" then eff_h = (eff_h ~= "" and (eff_h .. "; " .. suffix)) or suffix end
  if eff_h ~= "" then s = s .. " -- " .. eff_h end
  if desc and desc ~= "" and desc ~= raw_eff then
    if not (eff_h ~= "" and eff_h:find(desc, 1, true)) then s = s .. ". " .. desc end
  end
  return s
end

local function shop_section()
  if not G or not G.GAME then return nil end
  local money_amt = G.GAME.dollars or 0
  local spendable = CtxEconomy.spendable()
  local discount = G.GAME.discount_percent or 0
  local inflation = G.GAME.inflation or 0
  local interest = calc_interest(money_amt)
  local no_interest = CtxEconomy.no_interest()
  local ante = GameFacts.ante("?")
  local econ = economy_projection({ exclude_action_bonus = true })
  local interest_cap = CtxEconomy.interest_cap()
  local rf = CtxEconomy.reroll_facts()
  local free_rerolls = rf.free
  local spend_floor = CtxEconomy.spend_floor()
  local at_interest_cap = money_amt >= interest_cap
  local to_next_interest = (money_amt < 5) and (5 - money_amt) or (5 - (money_amt % 5))
  local spendable_i = math.floor(spendable)
  local safe_spend = math.floor(CtxEconomy.safe_spend_keep_interest())

  local function num_or_q(v) return type(v) == "number" and tostring(v) or "?" end

  local p = {}
  if spendable_i ~= money_amt then
    p[#p + 1] = string.format("Shop (ante %s). %s in bank, %s spendable now.", tostring(ante), money(money_amt), money(spendable_i))
  else
    p[#p + 1] = string.format("Shop (ante %s). %s in bank.", tostring(ante), money(money_amt))
  end

  local interest_line = CtxEconomy.interest_line(interest)
  if (not no_interest) and not at_interest_cap then
    interest_line = interest_line .. ", $" .. tostring(to_next_interest) .. " to next step"
  end
  if (not no_interest) and at_interest_cap then
    interest_line = interest_line .. ", at cap"
  end
  p[#p + 1] = interest_line .. "."

  if (not no_interest) and safe_spend ~= spendable_i then
    p[#p + 1] = "You can spend $" .. tostring(safe_spend) .. " while keeping this interest."
  end

  local reroll = "Reroll costs $" .. num_or_q(rf.effective) .. ", next $" .. num_or_q(rf.next)
    .. ", up to " .. tostring(rf.max_affordable) .. " affordable"
  if free_rerolls > 0 then reroll = reroll .. ", " .. tostring(free_rerolls) .. " free" end
  p[#p + 1] = reroll .. "."

  if spend_floor < 0 then
    local floor_note = "Spend floor " .. money(spend_floor) .. "."
    local below_floor = CtxEconomy.below_spend_floor_reason(money_amt)
    if below_floor then floor_note = "Spend floor " .. money(spend_floor) .. " -- " .. below_floor .. "." end
    p[#p + 1] = floor_note
  end
  if discount > 0 then p[#p + 1] = "Discount " .. tostring(discount) .. "%." end
  if inflation > 0 then p[#p + 1] = "Inflation " .. tostring(inflation) .. "." end
  local payout = decode_payout(econ or {})
  if payout then p[#p + 1] = "Cash-out if the round ended now: " .. payout .. "." end

  local lines = { table.concat(p, " ") }

  local areas = {
    { area = G.shop_jokers, label = "shop_jokers" },
    { area = G.shop_vouchers, label = "shop_vouchers" },
    { area = G.shop_booster, label = "shop_booster" },
  }
  local has_items = false
  for _, entry in ipairs(areas) do
    if entry.area and entry.area.cards and #entry.area.cards > 0 then
      if not has_items then
        lines[#lines + 1] = "Shop items:"
        has_items = true
      end
      for i, card in ipairs(entry.area.cards) do
        lines[#lines + 1] = shop_item_line(entry, i, card, spendable)
      end
    end
  end
  if not has_items then
    lines[#lines + 1] = "The shop stock is empty."
  end

  return table.concat(lines, "\n")
end

return { legality_section = legality_section, shop_section = shop_section }
