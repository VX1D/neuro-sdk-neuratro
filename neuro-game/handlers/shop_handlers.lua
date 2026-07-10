local Utils = require("util.utils")
local Tuning = require("core.tuning")
local CardArea = require("facts.card_area_util")
local CardUtil = require("facts.card_util")
local CtxEconomy = require("context.ctx_economy")
local ForceHelpers = require("force.force_helpers")
local NeuroAnim = require("render.neuro-anim")
local safe_name_or = Utils.safe_name_or
local validate_area_card = CardArea.validate_area_card
local get_area = CardArea.get_area
local mock_UIBox = CardArea.mock_UIBox
local shop_spend_floor = CtxEconomy.spend_floor

local function handle_buy_from_shop(data)
  local _, card, err = validate_area_card(data)
  if err then return nil, err end
  local card_name = safe_name_or(card)
  local cost = tonumber(card.cost or 0) or 0
  local dollars = tonumber(G.GAME and G.GAME.dollars or 0) or 0
  local reserved = tonumber(G and G.NEURO and G.NEURO.reserved_dollars or 0) or 0
  local floor = shop_spend_floor()
  local spendable = dollars - reserved - floor
  if cost > spendable then
    local credit = (floor < 0) and string.format(" (Credit Card lets you go to -$%d)", math.abs(floor)) or ""
    if reserved > 0 then
      return nil, string.format("Can't afford %s ($%d): $%d cash, $%d reserved for pending buys%s.", card_name, cost, dollars, reserved, credit)
    else
      return nil, string.format("Can't afford %s ($%d): you only have $%d%s.", card_name, cost, dollars, credit)
    end
  end
  local cfg = { ref_table = card }
  local is_booster = card and card.ability and card.ability.set == "Booster"
  local is_voucher = card and card.ability and card.ability.set == "Voucher"
  if data.use and card and card.ability and card.ability.consumeable then
    local needs = tonumber(card.ability.consumeable.max_highlighted or 0) or 0
    if needs > 0 then
      return nil, string.format("%s targets hand cards and can't be used straight from the shop; buy it without use, then use_card with hand_indices.", card_name)
    end
  end
  -- vouchers must go via buy_and_use/use_card/redeem(): plain buy path has no Voucher branch, emplaces it as a dead joker
  if data.use or is_booster or is_voucher then
    cfg.id = "buy_and_use"
  end

  if cfg.id ~= "buy_and_use" and not CardUtil.can_buy_card_space(card, data.area) then
    return nil, string.format("No slot space to buy %s now.", card_name)
  end

  local function queue_purchase_showcase()
    if not G then return end
    local q = G.NEURO.purchase_showcase_queue
    if type(q) ~= "table" then q = {} end

    local desc = Utils.card_description(card)
    if (not desc or desc == "") and card and card.config and card.config.center then
      desc = Utils.safe_description(card.config.center.loc_txt, card)
    end
    if not desc or desc == "" then desc = "-" end

    q[#q + 1] = {
      card = card,
      name = card_name,
      desc = tostring(desc),
      cost = cost,
      area = tostring(data.area or "shop"),
      at = Utils.now(),
    }
    while #q > 2 do
      table.remove(q, 1)
    end
    G.NEURO.purchase_showcase_queue = q
  end

  local buy_area_name = data.area
  local buy_index = data.index

  -- reserve synchronously: a second buy validated before this deferred exec must see the commitment; released by event or watchdog, zeroed on SHOP enter/exit
  G.NEURO = G.NEURO or {}
  G.NEURO.reserved_dollars = (tonumber(G.NEURO.reserved_dollars or 0) or 0) + cost
  local released = false
  local function release_reservation()
    if released or not (G and G.NEURO) then return end
    released = true
    G.NEURO.reserved_dollars = math.max(0, (tonumber(G.NEURO.reserved_dollars or 0) or 0) - cost)
  end

  return function()
    -- guard the whole body: a throw before the release events are scheduled would strand the dollar reservation until the next SHOP enter/exit
    local ok_body, ret = pcall(function()
    pcall(CardArea.set_highlight, card, true)
    local shop_buy_block = Tuning.get("NEURO_SHOP_BUY_BLOCK")
    local shop_buy_delay = Tuning.get("NEURO_SHOP_BUY_DELAY")
    local t = Utils.now()
    G.NEURO.last_action_at = t + shop_buy_block
    -- pcall: a throw here (card desc parse) runs before release events are scheduled and would leak the reservation
    pcall(queue_purchase_showcase)
    if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
        trigger   = "after",
        delay     = shop_buy_delay,
        blockable = false,
        func      = function()
          local function flag_buy_failed()
            ForceHelpers.correct_optimistic("buy_from_shop", "the purchase could not be completed", data._action_id,
              "Your buy_from_shop did not go through (couldn't afford or no space); money and inventory are unchanged.")
          end
          -- card is unhighlighted here, so the highlight watchdog below can't catch a swallowed failure -- must correct the optimistic ok
          local ok_exec = pcall(function()
            CardArea.set_highlight(card, false)
            release_reservation()
            -- authoritative last gate on LIVE money: never breach the floor (catches 2nd of two rapid buys after the 1st deducted)
            local live_dollars = tonumber(G.GAME and G.GAME.dollars or 0) or 0
            if live_dollars - cost < floor then flag_buy_failed() return end

            local live_area = get_area(buy_area_name)
            local buy_card = nil
            if live_area and live_area.cards then
              for _, c in ipairs(live_area.cards) do
                if c == card then buy_card = c break end
              end
              if not buy_card and live_area.cards[buy_index] == card then
                buy_card = card
              end
            end
            if not buy_card then flag_buy_failed() return end

            local buy_cfg = { ref_table = buy_card }
            local fn
            if is_booster or is_voucher then
              -- vanilla opens/redeems shop packs and vouchers via use_card; cost is deducted in Card:open()/redeem(), so buy_from_shop+buy_and_use would charge twice
              fn = G.FUNCS and G.FUNCS.use_card
            else
              if data.use then buy_cfg.id = "buy_and_use" end
              fn = G.FUNCS and G.FUNCS.buy_from_shop
            end
            if not fn then flag_buy_failed() return end
            fn({ config = buy_cfg, UIBox = mock_UIBox })
            if NeuroAnim and NeuroAnim.on_buy then NeuroAnim.on_buy(buy_card) end
          end)
          if not ok_exec then flag_buy_failed() end
          return true
        end,
      }))
      G.E_MANAGER:add_event(Event({
        trigger   = "after",
        delay     = shop_buy_delay + Tuning.get("NEURO_SHOP_BUY_WATCHDOG_GRACE"),
        blockable = false,
        func      = function()
          if card and card.highlighted and G and G.NEURO then
            pcall(CardArea.set_highlight, card, false)
            ForceHelpers.correct_optimistic("buy_from_shop", "Purchase did not complete (event lost).", data._action_id,
              "Your buy_from_shop did not go through (event lost); money and inventory are unchanged.")
          end
          release_reservation()
          return true
        end,
      }))
    else
      release_reservation()
      local cur_dollars = tonumber(G.GAME and G.GAME.dollars or 0) or 0
      if cur_dollars - cost < floor then
        pcall(CardArea.set_highlight, card, false)
        return string.format("Could not buy %s: $%d would drop you below your money floor.", card_name, cost)
      end
      local fn
      if is_booster or is_voucher then
        fn = G.FUNCS and G.FUNCS.use_card
        cfg.id = nil
      else
        fn = G.FUNCS and G.FUNCS.buy_from_shop
      end
      if not fn then
        pcall(CardArea.set_highlight, card, false)
        ForceHelpers.record_failure("buy_from_shop", "the purchase could not be completed")
        return string.format("Could not buy %s: purchase is unavailable right now.", card_name)
      end
      fn({ config = cfg, UIBox = mock_UIBox })
      if NeuroAnim and NeuroAnim.on_buy then NeuroAnim.on_buy(card) end
    end
    return string.format("Buying: %s for $%d", Utils.real_name_or(card), cost)
    end)
    if ok_body then return ret end
    release_reservation()
    error(ret, 0)   -- rethrow so the dispatcher corrects the optimistic ok and clears force state
  end
end

local function handle_sell_card(data)
  local _, card, err = validate_area_card(data)
  if err then return nil, err end
  local card_name = safe_name_or(card)
  if card.ability and card.ability.eternal then
    return nil, string.format("Cannot sell %s — it is Eternal. Eternal jokers can never be sold or destroyed.", card_name)
  end
  local sell_value = card.sell_cost or 0
  return function()
    local fn = G.FUNCS and G.FUNCS.sell_card
    if not fn then
      ForceHelpers.record_failure("sell_card", "the card could not be sold")
      return string.format("Could not sell %s: selling is unavailable right now.", card_name)
    end
    if not pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox }) then
      ForceHelpers.record_failure("sell_card", "the card could not be sold")
      return string.format("Could not sell %s: the sell did not go through.", card_name)
    end
    return string.format("Sold: %s for $%d", card_name, sell_value)
  end
end

return { handle_buy_from_shop = handle_buy_from_shop, handle_sell_card = handle_sell_card }
