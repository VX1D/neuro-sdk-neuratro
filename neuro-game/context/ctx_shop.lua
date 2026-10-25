local Utils = require("util.utils")
local PublicCardIdentity = require("facts.public_card_identity")
local GameFacts = require("facts.game_facts")
local CtxHelpers = require("context.ctx_helpers")
local CtxEconomy = require("facts.economy_facts")
local VoucherFacts = require("facts.voucher_facts")
local CardUtil = require("facts.card_util")
local normalize_text = CtxHelpers.normalize_text

local action_available = CtxHelpers.offers
local safe_name_or = Utils.safe_name_or
local calc_interest = CtxEconomy.calc_interest
local card_set = CardUtil.card_set
local booster_kind = CardUtil.booster_kind
local money = Utils.money
local yn = CtxHelpers.yn
local humanize_effect = CtxHelpers.humanize_effect

local REQUIREMENT_ACTIONS = {
  { "buy", "buy_from_shop" },
  { "reroll", "reroll_shop" },
  { "sell", "sell_card" },
  { "use", "use_consumable" },
  { "leave", "leave_shop" },
}
local PLAN_FIELD_ORDER = { "hand", "build", "money" }
local ACTION_PHRASE = {
  buy = "Buying", reroll = "Rerolling", sell = "Selling",
  use = "Using a consumable", leave = "Leaving the shop",
}
local function requirement_prose(legal)
  local Gate = require("core.gate")
  local clauses = {}
  for _, pair in ipairs(REQUIREMENT_ACTIONS) do
    local label, action_name = pair[1], pair[2]
    if not (legal and legal[label] == false) then
      local requirements = Gate.action_requirements("SHOP", action_name)
      local parts = {}
      for _, field in ipairs(PLAN_FIELD_ORDER) do
        if requirements.plan[field] then parts[#parts + 1] = "plan." .. field .. "_plan" end
      end
      if #parts > 0 then
        clauses[#clauses + 1] = (ACTION_PHRASE[label] or label) .. ": include " .. CtxHelpers.join(parts) .. "."
      end
    end
  end
  if #clauses == 0 then return nil end
  return "Fields to send with that same action -- " .. table.concat(clauses, " ")
end

local function shop_legality(action_set)
  local function available(name) return action_available(action_set, name) end
  local spendable = CtxEconomy.spendable()
  local rf = CtxEconomy.reroll_facts()
  local _, can_buy_any = CtxEconomy.cheapest_buyable(spendable)
  return { buy = available("buy_from_shop") and can_buy_any, reroll = available("reroll_shop") and rf.can_reroll,
    sell = available("sell_card"),
    use = available("use_consumable") or available("use_directional_consumable") }
end

local function requirements_query(action_set)
  if not G then return nil end
  return requirement_prose(shop_legality(action_set))
end

local function legality_section(state_name, action_set)
  if not G then return nil end
  if state_name == "SHOP" then
    local spendable = CtxEconomy.spendable()
    local rf = CtxEconomy.reroll_facts()
    local _, can_buy_any = CtxEconomy.cheapest_buyable(spendable)
    local cheapest = CtxEconomy.cheapest_buyable(spendable, true)

    local reroll_safe = false
    if type(cheapest) == "number" then
      if rf.free > 0 or (type(rf.effective) == "number" and rf.effective <= 0) then
        reroll_safe = true
      elseif type(rf.effective) == "number" and rf.effective > 0 then
        reroll_safe = (spendable - rf.effective) >= cheapest
      end
    end

    local can = CtxHelpers.can_line
    local reroll = can("reroll", action_set, { "reroll_shop" }, rf.can_reroll)
    if reroll == "Can reroll: yes" then reroll = reroll .. " (still affordable after: " .. yn(reroll_safe) .. ")" end
    return table.concat({
      can("buy something", action_set, { "buy_from_shop" }, can_buy_any), reroll,
      can("sell", action_set, { "sell_card" }),
      can("use a consumable", action_set, { "use_consumable", "use_directional_consumable" }),
    }, ".\n") .. "."
  end

  return nil
end

local BOOSTER_ROLE = {
  Buffoon = "pack of Jokers", Arcana = "pack of Tarot consumables",
  Celestial = "pack of Planet consumables", Spectral = "pack of Spectral consumables",
  Standard = "pack of playing cards",
}
local function shop_item_role(area, typ)
  if area == "shop_booster" then
    local used = G and G.GAME and G.GAME.used_vouchers
    if typ == "Arcana" and used and used.v_omen_globe then
      return "pack of Tarot consumables -- Omen Globe lets any card in it be a Spectral instead"
    end
    return BOOSTER_ROLE[typ]
  end
  if area == "shop_jokers" and CardUtil.is_consumable_set(typ) then
    return "a consumable, not a Joker -- it fills a consumable slot"
  end
  return nil
end

local function shop_item_line(entry, i, card, spendable_amount)
  if not PublicCardIdentity.is_public(card) then return CtxHelpers.hidden_row(i, card, entry.label) end

  local name = normalize_text(safe_name_or(card))
  local cost = tonumber(card.cost or 0) or 0
  local afford_status = CtxEconomy.item_afford_status(card, entry.label, spendable_amount)
  local ctype = card_set(card)
  if ctype == "Booster" then
    local bk = booster_kind(card)
    if bk ~= "" then ctype = bk end
  end
  if ctype == "Default" or ctype == "Enhanced" then ctype = "Playing" end
  if not ctype or ctype == "" then ctype = "?" end
  local center = card and card.config and card.config.center
  local rarity = (center and center.set == "Joker") and CardUtil.rarity_name(center.rarity) or nil
  local raw_eff, suffix, desc = CtxHelpers.row_effect(card, "shop_card_row")

  local s = i .. ". " .. name .. " (" .. ctype
  if rarity then s = s .. ", " .. rarity end
  s = s .. ")"
  local stickers = CtxHelpers.sticker_flags(card)
  if stickers then s = s .. " [" .. stickers .. "]" end
  local edition = card.edition and CardUtil.edition_name(card.edition)
  if edition and edition ~= "" then s = s .. " [" .. edition .. " edition]" end
  local role = shop_item_role(entry.label, ctype)
  if role then s = s .. " [" .. role .. "]" end
  s = s .. string.format(" %s, affordable now: %s", money(cost), yn(afford_status.afford))
  if entry.label == "shop_jokers" and CardUtil.is_consumable_card(card) then
    -- `has_space` permits an immediate full-slot buy, so inspect the slot directly.
    local slot = CardUtil.is_negative(card) or CardUtil.has_consumable_space()
    s = s .. string.format(", free consumable slot: %s", yn(slot))
    if not slot and afford_status.has_space then s = s .. " (can only be bought to use at once)" end
    local targets = CtxHelpers.target_count(card)
    if targets then s = s .. ", targets " .. targets end
  elseif entry.label == "shop_jokers" then
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
  if interest_cost > 0 then s = s .. ", interest cost: " .. money(interest_cost) end
  if entry.label == "shop_vouchers" and require("core.gate").reviewed_target("buy_voucher") == Utils.real_name_or(card) then
    s = s .. ", buying it leaves " .. money(math.max(0, bank - cost))
  end
  s = s .. CtxHelpers.effect_tail((raw_eff ~= "-" and raw_eff ~= "") and humanize_effect(raw_eff) or "", suffix, desc)
  local voucher_note = entry.label == "shop_vouchers" and center and VoucherFacts.row_note(center.key)
  if voucher_note then s = CtxHelpers.end_sentence(s) .. " " .. voucher_note .. "." end
  local owned = G and G.GAME and G.GAME.used_vouchers or {}
  local unlock = entry.label == "shop_vouchers" and center and not owned[center.key] and VoucherFacts.unlock_sentence(center.key)
  if unlock then s = CtxHelpers.end_sentence(s) .. " " .. unlock .. "." end
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
  local interest_cap = CtxEconomy.interest_cap()
  local rf = CtxEconomy.reroll_facts()
  local free_rerolls = rf.free
  local spend_floor = CtxEconomy.spend_floor()
  local at_interest_cap = money_amt >= interest_cap
  local to_next_interest = (money_amt < 5) and (5 - money_amt) or (5 - (money_amt % 5))
  local spendable_i = math.floor(spendable)
  local safe_spend = math.floor(CtxEconomy.safe_spend_keep_interest())

  local function money_or_q(v) return type(v) == "number" and money(v) or "$?" end

  local p = { "## Shop (ante " .. tostring(ante) .. ")" }
  if spendable_i ~= money_amt then
    p[#p + 1] = string.format("%s in bank, %s spendable now.", money(money_amt), money(spendable_i))
  else
    p[#p + 1] = string.format("%s in bank.", money(money_amt))
  end
  local entry_dollars = tonumber(G.NEURO and G.NEURO.shop_entry_dollars)
  if entry_dollars and require("core.gate").applies("interest_engine_off") then
    p[#p + 1] = string.format("You entered this shop with %s.", money(math.floor(entry_dollars)))
  end

  local interest_line = CtxEconomy.interest_line(interest)
  if not no_interest then
    interest_line = interest_line .. (at_interest_cap and ", at cap" or (", " .. money(to_next_interest) .. " to next step"))
  end
  p[#p + 1] = interest_line .. "."

  if (not no_interest) and safe_spend ~= spendable_i then
    p[#p + 1] = "You can spend " .. money(safe_spend) .. " while keeping this interest."
  end
  local model = CtxEconomy.reserve_model()
  if model and not model.interest and not model.bank_scaling and model.rerolls >= 2 then
    local why = model.basis == "hermit" and "what The Hermit you hold doubles" or "one reroll at the next shop"
    p[#p + 1] = string.format("No interest this run: %s of your bank sits above a ~%s reserve (%s); it covers about %d rerolls here.",
      money(model.surplus), money(model.reserve), why, model.rerolls)
  end
  if model and model.interest then
    if model.surplus > 0 then
      p[#p + 1] = string.format("%s of your bank is past the %s interest cap and earns no interest.",
        money(model.surplus), money(model.reserve))
    end
    local posture = CtxEconomy.spend_posture()
    if posture and posture.posture == "bank" then
      p[#p + 1] = string.format("Everything here that you have room for costs more than the %s you can spend without losing interest.",
        money(safe_spend))
    end
  end

  local reroll = "Reroll costs " .. money_or_q(rf.effective) .. ", next " .. money_or_q(rf.next)
    .. ", up to " .. tostring(rf.max_affordable) .. " affordable"
  if free_rerolls > 0 then reroll = reroll .. ", " .. tostring(free_rerolls) .. " free" end
  p[#p + 1] = reroll .. "."

  if spend_floor < 0 then
    local below_floor = CtxEconomy.below_spend_floor_reason(money_amt)
    p[#p + 1] = "Spend floor " .. money(spend_floor) .. (below_floor and (" -- " .. below_floor) or "") .. "."
  end
  if discount > 0 then p[#p + 1] = "Discount " .. tostring(discount) .. "%." end
  if inflation > 0 then p[#p + 1] = "Inflation " .. tostring(inflation) .. "." end

  local lines = p

  local areas = {
    { area = G.shop_jokers, label = "shop_jokers", title = "Shop jokers" },
    { area = G.shop_vouchers, label = "shop_vouchers", title = "Shop vouchers" },
    { area = G.shop_booster, label = "shop_booster", title = "Shop boosters" },
  }
  local has_items = false
  for _, entry in ipairs(areas) do
    if entry.area and entry.area.cards and #entry.area.cards > 0 then
      has_items = true
      lines[#lines + 1] = "## " .. entry.title .. ' (area "' .. entry.label .. '")'
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

return { legality_section = legality_section, shop_section = shop_section, requirements_query = requirements_query }
