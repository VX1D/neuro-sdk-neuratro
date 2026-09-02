local GameFacts = require("facts.game_facts")
local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local CardUtil = require("facts.card_util")
local StateKinds = require("core.state_kinds")
local CtxEconomy = require("facts.economy_facts")
local ForceHelpers = require("force.force_helpers")
local function anim() return Utils.lazy_require("render.neuro-anim") end
local Showcase = require("hud.showcase")
local ActionResult = require("core.action_result")
local ActionReceipt = require("core.action_receipt")
local ContextReview = require("core.context_review")
local Lifecycle = require("core.neuro_lifecycle")
local GameplayJournal = require("core.gameplay_journal")
local safe_name_or = Utils.safe_name_or
local validate_area_card = CardArea.validate_area_card
local get_area = CardArea.get_area
local mock_UIBox = GameActions.mock_UIBox
local shop_spend_floor = CtxEconomy.spend_floor

local function card_identity(card, money_field)
  local center = card and card.config and card.config.center or {}
  return table.concat({
    tostring(card and card.sort_id), tostring(center.key),
    tostring(card and Utils.real_name_or(card)),
    tostring(card and card[money_field] or 0),
  }, "/")
end

local function ordered_area_identity(area, money_field)
  local out = {}
  for i, card in ipairs((area and area.cards) or {}) do
    out[#out + 1] = tostring(i) .. ":" .. card_identity(card, money_field)
  end
  return table.concat(out, ",")
end

local function sorted_map_identity(map)
  local out = {}
  for key, value in pairs(type(map) == "table" and map or {}) do
    local detail = type(value) == "table"
      and table.concat({ tostring(value.tag), tostring(value.note) }, "/") or tostring(value)
    out[#out + 1] = tostring(key) .. "=" .. detail
  end
  table.sort(out)
  return table.concat(out, ",")
end

local function common_review_parts(kind)
  local n, game = G and G.NEURO or {}, G and G.GAME or {}
  return {
    kind, tostring(n.run_generation or 0), tostring(n.state or ""),
    tostring(n.state_enter_serial or 0), tostring(n.shop_visit_epoch or 0),
    tostring(game.dollars or 0),
  }
end

local function sell_context_key()
  local n = G and G.NEURO or {}
  local parts = common_review_parts("sell_joker")
  parts[#parts + 1] = ordered_area_identity(G and G.jokers, "sell_cost")
  parts[#parts + 1] = tostring(n.joker_intent_revision or 0)
  parts[#parts + 1] = sorted_map_identity(n.joker_intents)
  parts[#parts + 1] = tostring(n.plan_revision or 0)
  parts[#parts + 1] = tostring(n.plan and n.plan.build or "")
  local sold = n.jokers_sold
  parts[#parts + 1] = tostring(type(sold) == "table" and sold.count or 0)
  return table.concat(parts, "|")
end

local function voucher_context_key()
  local game = G and G.GAME or {}
  local parts = common_review_parts("buy_voucher")
  parts[#parts + 1] = ordered_area_identity(G and G.shop_vouchers, "cost")
  parts[#parts + 1] = tostring(GameFacts.reserved_dollars())
  parts[#parts + 1] = tostring(shop_spend_floor())
  parts[#parts + 1] = sorted_map_identity(game.used_vouchers)
  return table.concat(parts, "|")
end

local function area_contains(area, target)
  for _, card in ipairs((area and area.cards) or {}) do
    if card == target then return true end
  end
  return false
end

local function refuse(data, code, message, card, name, cost)
  Showcase.enqueue_refusal({
    code = code, card = card, name = name, cost = cost, action_id = data._action_id })
  return ActionResult.reject(code, message)
end

local function record_joker_purchase(purchased_card, price)
  if not (G and G.NEURO and purchased_card and purchased_card.sort_id ~= nil) then return end
  G.NEURO.joker_bought_cost = G.NEURO.joker_bought_cost or {}
  G.NEURO.joker_bought_cost[purchased_card.sort_id] = price
  pcall(require("core.rewards").announce_rare_joker, purchased_card)
end

local function voucher_buy_reason(card_name, cost, left)
  return string.format(
    "Buying %s for $%d, leaving $%d. A voucher lasts the whole run and cannot be sold or undone."
      .. " Nothing was purchased. After this review is delivered, the next legal voucher buy in this unchanged shop context is FINAL, even if you choose a different voucher; or pick something else.",
    card_name, cost, math.max(0, left))
end

local function handle_buy_from_shop(data)
  local _, card, err = validate_area_card(data)
  local name_err = (not err) and CardArea.check_target_name(card, data.name, data.index, data.area) or nil
  if (err or name_err) and type(data.name) == "string" and data.name ~= "" then
    local rc, ri = CardArea.find_card_by_name(get_area(data.area), data.name)
    if rc and ri then
      data.index, card, err, name_err = ri, rc, nil, nil
    end
  end
  if err then return ActionResult.reject("TARGET_UNAVAILABLE", err) end
  if name_err then return ActionResult.reject("STALE_TARGET", name_err) end
  local card_name = Utils.real_name_or(card)
  local cost = tonumber(card.cost or 0) or 0
  local dollars = tonumber(G.GAME and G.GAME.dollars or 0) or 0
  local reserved = GameFacts.reserved_dollars()
  local floor = shop_spend_floor()
  local spendable = CtxEconomy.spendable()
  if cost > spendable then
    local credit = (floor < 0) and string.format(" (Credit Card lets you go to -$%d)", math.abs(floor)) or ""
    if reserved > 0 then
      return refuse(data, "INSUFFICIENT_FUNDS",
        string.format("Can't afford %s ($%d): $%d cash, $%d reserved for pending buys%s.", card_name, cost, dollars, reserved, credit),
        card, card_name, cost)
    else
      return refuse(data, "INSUFFICIENT_FUNDS",
        string.format("Can't afford %s ($%d): you only have $%d%s.", card_name, cost, dollars, credit),
        card, card_name, cost)
    end
  end
  local cfg = { ref_table = card }
  local set = CardUtil.card_set(card)
  local is_booster = set == "Booster"
  local is_voucher = set == "Voucher"
  if is_voucher and not (G.NEURO and G.NEURO._candidate_probe) then
    local context_key = voucher_context_key()
    if not ContextReview.is_reviewed("buy_voucher", context_key) then
      return ActionResult.reject("CONFIRMATION_REQUIRED",
        voucher_buy_reason(card_name, cost, dollars - cost), {
          context_review_candidate = ContextReview.candidate("buy_voucher", context_key,
            { target = card_name }),
          consume_force_attempt = true,
        })
    end
  end
  if data.use and card and card.ability and card.ability.consumeable then
    local needs = tonumber(card.ability.consumeable.max_highlighted or 0) or 0
    if needs > 0 then
      return ActionResult.reject("INVALID_SELECTION",
        string.format("%s targets hand cards and can't be used straight from the shop; buy it without use, then use_consumable with hand_indices.", card_name))
    end
  end
  if card and card.ability and card.ability.consumeable and not data.use and not is_booster
      and not CardUtil.is_negative(card) then
    local cs = CardUtil.consumable_slot_status()
    if cs and cs.full then
      local _, mh = CardUtil.consumable_target_range(card)
      if mh and mh > 0 then
        return refuse(data, "NO_SLOT",
          string.format("Consumable slots are full and %s targets hand cards (can't be used from the shop) -- free a slot first, then buy it.", card_name),
          card, card_name, cost)
      end
      return refuse(data, "NO_SLOT",
        string.format("Consumable slots are full -- a plain buy of %s would do nothing. Add \"use\":true to buy-and-use it now, or free a slot.", card_name),
        card, card_name, cost)
    end
  end
  if data.use or is_booster or is_voucher then
    cfg.id = "buy_and_use"
  end

  if cfg.id ~= "buy_and_use" and not CardUtil.can_buy_card_space(card, data.area) then
    local remedy = "free a slot first, then buy it"
    if CardUtil.is_joker_like_card(card) then
      local js = CardUtil.joker_slot_status()
      remedy = string.format("joker slots are %d/%d full -- sell a joker to free one, then buy it",
        js.count, js.limit)
    end
    return refuse(data, "NO_SLOT",
      string.format("No slot space to buy %s now: %s.", card_name, remedy), card, card_name, cost)
  end

  local buy_and_use = (data.use and not is_booster and not is_voucher) and true or false
  local purchase_kind = is_voucher and "voucher" or is_booster and "booster"
    or buy_and_use and "buy_and_use" or set == "Joker" and "joker"
    or CardUtil.is_consumable_card(card) and "consumable" or "other"
  local gameplay_event = {
    kind = "shop_buy",
    public_subject = GameplayJournal.public_card_label(card, data.area, data.index),
    area = data.area,
    purchase_kind = purchase_kind,
    paid = cost,
  }
  local function queue_purchase_showcase()
    local at = Utils.now()
    Showcase.enqueue_purchase({
      card = card,
      name = card_name,
      cost = cost,
      area = buy_and_use and "shop_use" or tostring(data.area or "shop"),
      at = at,
    })
    if is_voucher then Showcase.enqueue_voucher(card, at) end
  end

  local buy_area_name = data.area
  local buy_index = data.index
  local pre_pack_area = CardUtil.pack_area()
  local use_observed = false
  local original_raw_use = rawget(card, "use_consumeable")
  local original_use = card.use_consumeable
  local observed_use

  local reservation_epoch
  local released = false
  local explicit_failure
  local function release_reservation()
    if released or not (G and G.NEURO) then return end
    released = true
    if (tonumber(G.NEURO._reservation_epoch or 0) or 0) ~= reservation_epoch then return end
    G.NEURO.reserved_dollars = math.max(0, GameFacts.reserved_dollars() - cost)
  end

  return function()
    if type(original_use) == "function" then
      observed_use = function(self, ...)
        if self == card then use_observed = true end
        if rawget(card, "use_consumeable") == observed_use then card.use_consumeable = original_raw_use end
        return original_use(self, ...)
      end
      card.use_consumeable = observed_use
    end
    G.NEURO = G.NEURO or {}
    reservation_epoch = tonumber(G.NEURO._reservation_epoch or 0) or 0
    G.NEURO.reserved_dollars = GameFacts.reserved_dollars() + cost
    local shop_buy_delay = require("core.staging").lift_safe_delay(
      Utils.gate_seconds("shop_buy_block", "NEURO_SHOP_BUY_DELAY"))
    local ok_body, ret = pcall(function()
    GameActions.try_highlight(card, true)
    local shop_buy_block = Utils.gate_seconds("shop_buy_block", "NEURO_SHOP_BUY_BLOCK")
    Lifecycle.mark_action_at(Lifecycle.action_now() + shop_buy_block)
    if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
        trigger   = "after",
        timer     = "TOTAL",
        delay     = shop_buy_delay,
        blockable = false,
        blocking  = false,
        func      = function()
          local function flag_buy_failed()
            explicit_failure = "purchase callback refused the prepared target"
          end
          local ok_exec = pcall(function()
            GameActions.set_highlight(card, false)
            release_reservation()
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
              fn = G.FUNCS and G.FUNCS.use_card
            else
              if data.use then buy_cfg.id = "buy_and_use" end
              fn = G.FUNCS and G.FUNCS.buy_from_shop
            end
            if not fn then flag_buy_failed() return end
            if fn({ config = buy_cfg, UIBox = mock_UIBox }) == false then
              flag_buy_failed()
              return
            end
            record_joker_purchase(buy_card, cost)
            if data._action_id == nil then pcall(queue_purchase_showcase) end
            local NA = anim()
            if NA and NA.on_buy then NA.on_buy(buy_card) end
          end)
          if not ok_exec then flag_buy_failed() end
          return true
        end,
      }))
      G.E_MANAGER:add_event(Event({
        trigger   = "after",
        timer     = "TOTAL",
        delay     = shop_buy_delay
          + Utils.gate_seconds("shop_buy_watchdog_grace", "NEURO_SHOP_BUY_WATCHDOG_GRACE"),
        blockable = false,
        blocking  = false,
        func      = function()
          if card and card.highlighted and G and G.NEURO then
            GameActions.try_highlight(card, false)
            explicit_failure = "purchase event did not complete"
          end
          release_reservation()
          return true
        end,
      }))
    else
      release_reservation()
      local cur_dollars = tonumber(G.GAME and G.GAME.dollars or 0) or 0
      if cur_dollars - cost < floor then
        GameActions.try_highlight(card, false)
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
        GameActions.try_highlight(card, false)
        ForceHelpers.record_failure("buy_from_shop", "the purchase could not be completed")
        explicit_failure = "purchase callback unavailable"
        return string.format("Could not buy %s: purchase is unavailable right now.", card_name)
      end
      if fn({ config = cfg, UIBox = mock_UIBox }) == false then
        explicit_failure = "purchase callback refused the prepared target"
      else
        record_joker_purchase(card, cost)
      end
      local NA = anim()
      if NA and NA.on_buy then NA.on_buy(card) end
    end
    return string.format("Buying: %s for $%d", Utils.real_name_or(card), cost)
    end)
    if ok_body and data._action_id == nil then
      if rawget(card, "use_consumeable") == observed_use then card.use_consumeable = original_raw_use end
      return ret
    end
    if ok_body then
      return ActionReceipt.create({
        id = tostring(data._action_id),
        name = "buy_from_shop",
        run_generation = G and G.NEURO and G.NEURO.run_generation,
        deadline = ActionReceipt.now() + math.max(3,
          shop_buy_delay
            + Utils.gate_seconds("shop_buy_watchdog_grace", "NEURO_SHOP_BUY_WATCHDOG_GRACE") + 1),
        timeout_outcome = "failed",
        correction = "The accepted purchase did not complete; the item remains in the shop. Re-check money and slots, then choose again.",
        applied_message = ret,
        debug = { area = buy_area_name, index = buy_index, card = card_name },
        probe = function()
          if explicit_failure then return "failed", { reason = explicit_failure } end
          local left_shop = not area_contains(get_area(buy_area_name), card)
          local destination = set == "Joker" and G and G.jokers or G and G.consumeables
          local voucher_key = card and card.config and card.config.center and card.config.center.key
          local voucher_used = is_voucher and voucher_key and G and G.GAME and G.GAME.used_vouchers
            and G.GAME.used_vouchers[voucher_key]
          local pack_started = is_booster and CardUtil.pack_area() ~= nil
            and CardUtil.pack_area() ~= pre_pack_area
          local transferred = not is_booster and not is_voucher and not data.use
            and area_contains(destination, card)
          if left_shop and (transferred or voucher_used or pack_started or data.use and use_observed) then
            return "applied", {
              target_left_shop = true,
              transferred = transferred,
              voucher_used = not not voucher_used,
              pack_started = pack_started,
              use_observed = use_observed,
            }
          end
          return "pending"
        end,
        on_applied = queue_purchase_showcase,
        cleanup = function()
          if rawget(card, "use_consumeable") == observed_use then card.use_consumeable = original_raw_use end
          release_reservation()
          GameActions.try_highlight(card, false)
        end,
      })
    end
    if rawget(card, "use_consumeable") == observed_use then card.use_consumeable = original_raw_use end
    release_reservation()
    error(ret, 0)
  end, nil, gameplay_event
end

local function record_joker_sold()
  local N = G and G.NEURO
  if not N then return end
  local epoch = tonumber(N.shop_visit_epoch) or 0
  local rec = N.jokers_sold
  if type(rec) ~= "table" or rec.epoch ~= epoch then
    rec = { epoch = epoch, count = 0 }
    N.jokers_sold = rec
  end
  rec.count = (rec.count or 0) + 1
  N.jokers_sold_run = (tonumber(N.jokers_sold_run) or 0) + 1
end

local GUARDED_SELL_STATES = { SHOP = true, BLIND_SELECT = true, SELECTING_HAND = true }

local function sell_is_guarded(state_name)
  return GUARDED_SELL_STATES[state_name] == true or StateKinds.is_pack_state(state_name)
end

local TAG_SELL_LEAD = {
  CORE = "you tagged it CORE.",
  SCALING = "you tagged it SCALING.",
  HOLD = "you tagged it HOLD.",
  CHANGE = "you tagged it CHANGE.",
}

local function joker_sell_reason(card_name, tag, note, sell_value, remaining)
  local N = G and G.NEURO
  local build = N and N.plan and N.plan.build
  local epoch = tonumber(N and N.shop_visit_epoch) or 0
  local rec = N and N.jokers_sold
  local sold = (type(rec) == "table" and rec.epoch == epoch and rec.count) or 0
  local lead = TAG_SELL_LEAD[tag]
  local remaining_s = remaining == 1 and "" or "s"
  local parts = {
    lead and string.format("Selling %s for $%d, leaving %d joker%s: %s", card_name, sell_value, remaining, remaining_s, lead)
      or string.format("Selling %s for $%d leaves %d joker%s and removes this joker's listed effect from the roster.", card_name, sell_value, remaining, remaining_s)
  }
  if type(note) == "string" and note ~= "" then
    parts[#parts + 1] = "You noted about this joker: \"" .. note .. "\"."
  end
  if sold >= 1 then
    parts[#parts + 1] = string.format(
      "You have already sold %d joker%s this shop -- you are dismantling your build.", sold, sold == 1 and "" or "s")
  end
  if type(build) == "string" and build ~= "" then
    parts[#parts + 1] = "Your build plan: \"" .. build .. "\"."
  end
  parts[#parts + 1] = "Nothing was sold. After this review is delivered, the next legal sell_card in this unchanged context is FINAL, even if you choose a different joker; or keep the joker and act elsewhere."
  return table.concat(parts, " ")
end

local function handle_sell_card(data)
  local area, card, err = validate_area_card(data)
  if err then return ActionResult.reject("TARGET_UNAVAILABLE", err) end
  local name_err = CardArea.check_target_name(card, data.name, data.index, data.area)
  if name_err and type(data.name) == "string" and data.name ~= "" then
    local relocated, index = CardArea.find_card_by_name(area, data.name)
    if relocated and index then
      data.index, card, name_err = index, relocated, nil
    end
  end
  if name_err then return ActionResult.reject("STALE_TARGET", name_err) end
  local card_name = safe_name_or(card)
  if card.ability and card.ability.eternal then
    return nil, string.format("Cannot sell %s — it is Eternal. Eternal jokers can never be sold or destroyed.", card_name)
  end
  local is_joker = (card.ability and card.ability.set == "Joker") and true or false
  local state_now = require("core.state").get_state_name()
  if is_joker and not (G.NEURO and G.NEURO._candidate_probe)
    and sell_is_guarded(state_now) then
    local entry = G.NEURO and G.NEURO.joker_intents and G.NEURO.joker_intents[card.sort_id]
    local tag = entry and entry.tag or nil
    local context_key = sell_context_key()
    if not ContextReview.is_reviewed("sell_joker", context_key) then
      local remaining = math.max(0, #((G and G.jokers and G.jokers.cards) or {}) - 1)
      return ActionResult.reject("CONFIRMATION_REQUIRED",
        joker_sell_reason(card_name, tag, entry and entry.note, card.sell_cost or 0, remaining), {
          context_review_candidate = ContextReview.candidate("sell_joker", context_key,
            { target = card_name }),
          consume_force_attempt = true,
        })
    end
  end
  local sell_value = card.sell_cost or 0
  local source_area = get_area(data.area)
  local gameplay_event = {
    kind = "shop_sell",
    public_subject = GameplayJournal.public_card_label(card, data.area, data.index),
    area = data.area,
    received = tonumber(sell_value),
  }
  local function queue_sell_showcase()
    Showcase.enqueue_purchase({
      card = card,
      name = card_name,
      cost = sell_value,
      area = "sell",
      at = Utils.now(),
    })
  end
  return function()
    local fn = G.FUNCS and G.FUNCS.sell_card
    if not fn then
      ForceHelpers.record_failure("sell_card", "the card could not be sold")
      local message = string.format("Could not sell %s: selling is unavailable right now.", card_name)
      if data._action_id ~= nil then return ActionReceipt.outcome("failed", message) end
      return message
    end
    local sell_ok, sell_result = pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox })
    if not sell_ok or sell_result == false then
      ForceHelpers.record_failure("sell_card", "the card could not be sold")
      local message = string.format("Could not sell %s: the sell did not go through.", card_name)
      if data._action_id ~= nil then return ActionReceipt.outcome("failed", message) end
      return message
    end
    Showcase.note_removal(card)
    if data._action_id == nil then
      if is_joker then record_joker_sold() end
      queue_sell_showcase()
      return string.format("Sold: %s for $%d", card_name, sell_value)
    end
    return ActionReceipt.create({
      id = tostring(data._action_id),
      name = "sell_card",
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = ActionReceipt.now() + 3,
      timeout_outcome = "failed",
      correction = "The accepted sale did not complete; the selected card is still present. Inspect the current state and choose again.",
      applied_message = string.format("Sold: %s for $%d", card_name, sell_value),
      debug = { area = data.area, index = data.index, card = card_name },
      probe = function()
        if not area_contains(source_area, card) then return "applied", { target_left_area = true } end
        return "pending"
      end,
      on_applied = function()
        if is_joker then record_joker_sold() end
        queue_sell_showcase()
      end,
    })
  end, nil, gameplay_event
end

local function pending_sell_card_name()
  if not (G and G.NEURO and G.jokers and G.jokers.cards) then return nil end
  return ContextReview.note("sell_joker", sell_context_key())
end

local function pending_voucher_name()
  if not (G and G.NEURO) then return nil end
  return ContextReview.note("buy_voucher", voucher_context_key())
end

local GUARDED_CONFIRMATIONS = {
  { action = "sell_card", live = pending_sell_card_name,
    sentence = "FINAL SELL CHOICE -- the sell review began with %s; the next legal sell_card now commits immediately, including a different joker. " },
  { action = "buy_from_shop", live = pending_voucher_name,
    sentence = "FINAL VOUCHER CHOICE -- the voucher review began with %s; the next legal voucher buy now commits immediately, including a different voucher. " },
}

local function pending_confirmation_note(offered)
  local set = {}
  for key, value in pairs(type(offered) == "table" and offered or {}) do
    if type(key) == "number" then
      if type(value) == "string" then set[value] = true end
    elseif value then
      set[key] = true
    end
  end
  local parts = {}
  for _, entry in ipairs(GUARDED_CONFIRMATIONS) do
    if set[entry.action] then
      local ok, name = pcall(entry.live)
      if ok and type(name) == "string" and name ~= "" then
        parts[#parts + 1] = string.format(entry.sentence, name)
      end
    end
  end
  return table.concat(parts)
end

return { handle_buy_from_shop = handle_buy_from_shop, handle_sell_card = handle_sell_card,
  TAG_SELL_LEAD = TAG_SELL_LEAD, pending_sell_card_name = pending_sell_card_name,
  GUARDED_SELL_STATES = GUARDED_SELL_STATES,
  pending_confirmation_note = pending_confirmation_note,
  GUARDED_CONFIRMATIONS = GUARDED_CONFIRMATIONS }
