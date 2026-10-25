local GameFacts = require("facts.game_facts")
local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local CardUtil = require("facts.card_util")
local StateKinds = require("core.state_kinds")
local CtxEconomy = require("facts.economy_facts")
local FactHints = require("facts.fact_hints")
local function anim() return Utils.lazy_require("render.neuro-anim") end
local Showcase = require("hud.showcase")
local ActionResult = require("core.action_result")
local Gate = require("core.gate")
local PublicCardIdentity = require("facts.public_card_identity")
local Lifecycle = require("core.neuro_lifecycle")
local GameplayJournal = require("core.gameplay_journal")
local safe_name_or = Utils.safe_name_or
local get_area = CardArea.get_area
local mock_UIBox = GameActions.mock_UIBox
local shop_spend_floor = CtxEconomy.spend_floor
local TargetContracts = require("facts.target_contracts")

local function consumable_slot_remedy()
  local ok, Actions = pcall(require, "core.actions")
  local function valid(name) return ok and type(Actions.is_action_valid) == "function" and Actions.is_action_valid(name) end
  local ways = {}
  if valid("use_consumable") or valid("use_directional_consumable") then ways[#ways + 1] = "use" end
  local owned = G and G.consumeables and G.consumeables.cards
  if valid("sell_card") and type(owned) == "table" and #owned > 0 then ways[#ways + 1] = "sell" end
  if #ways == 0 then return "free a consumable slot" end
  return table.concat(ways, " or ") .. " an owned consumable to free a slot"
end


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
  parts[#parts + 1] = sorted_map_identity(n.joker_intents)
  parts[#parts + 1] = tostring(n.joker_intent_revision or 0)
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
  return Utils.index_in(area and area.cards, target) ~= nil
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
  if CardUtil.is_joker_like_card(purchased_card) then
    Lifecycle.sync_joker_intent_revision()
    FactHints.note_joker_gained()
  end
  pcall(require("core.rewards").announce_rare_joker, purchased_card)
end

local function voucher_buy_reason(card_name)
  return string.format(
    "Buying %s is permanent: a voucher lasts the whole run and cannot be sold or undone. Its Shop vouchers row shows what the buy leaves in your bank.",
    card_name)
end
local function shop_use_rejection(card_name, card)
  if TargetContracts.get(card) then
    return string.format(
      "%s has directional targets and can't be used straight from the shop; buy it without use, then use it as a directional consumable with %s.",
      card_name, require("force.force_helpers").target_fields("use_directional_consumable"))
  end
  return string.format(
    "%s targets hand cards and can't be used straight from the shop; buy it without use, then use it as a consumable with hand_indices.",
    card_name)
end


local function handle_buy_from_shop(data)
  local _, card, index, code, err = CardArea.resolve_target(data, CardArea.TARGET_RULES.buy_from_shop)
  if not card then return ActionResult.reject(code, err) end
  data.index = index
  local card_name = Utils.real_name_or(card)
  local cost = tonumber(card.cost or 0) or 0
  local dollars = tonumber(G.GAME and G.GAME.dollars or 0) or 0
  local reserved = GameFacts.reserved_dollars()
  local floor = shop_spend_floor()
  local spendable = CtxEconomy.spendable()
  if cost > spendable then
    local credit = (floor < 0) and " (Credit Card lets you go to " .. Utils.money(floor) .. ")" or ""
    local have = reserved > 0 and Utils.money(dollars) .. " cash, " .. Utils.money(reserved) .. " reserved for pending buys"
      or "you only have " .. Utils.money(dollars)
    return refuse(data, "INSUFFICIENT_FUNDS",
      string.format("Can't afford %s (%s): %s%s.", card_name, Utils.money(cost), have, credit), card, card_name, cost)
  end
  local set = CardUtil.card_set(card)
  local is_booster = set == "Booster"
  local is_voucher = set == "Voucher"
  if is_voucher and not (G.NEURO and G.NEURO._candidate_probe) then
    local review = Gate.check("handler", "buy_from_shop", data, { target = card_name,
      text = function() return voucher_buy_reason(card_name) end })
    if review then return nil, review end
  end
  local _, max_targets = CardUtil.consumable_target_range(card)
  if data.use and card.ability and card.ability.consumeable then
    if max_targets and max_targets > 0 then
      return ActionResult.reject("INVALID_SELECTION", shop_use_rejection(card_name, card))
    end
    -- The engine’s buy-and-use path skips this check; its button is shown only when the check passes.
    local refusal = GameActions.consumable_refusal(card)
    if refusal then
      return ActionResult.reject("PRECONDITION_FAILED", string.format(
        "Can't buy-and-use %s: %s. Nothing was bought. Buy it without use to keep it, or choose something else.",
        card_name, refusal))
    end
  end
  if card.ability and card.ability.consumeable and not data.use and not is_booster
      and not CardUtil.is_negative(card) then
    local cs = CardUtil.consumable_slot_status()
    if cs and cs.full then
      if max_targets and max_targets > 0 then
        return refuse(data, "NO_SLOT",
          string.format("Consumable slots are full and %s targets hand cards (can't be used from the shop) -- %s, then buy it.", card_name, consumable_slot_remedy()),
          card, card_name, cost)
      end
      local refusal = GameActions.consumable_refusal(card)
      if refusal then
        return refuse(data, "NO_SLOT",
          string.format("Consumable slots are full and %s can't be used right now (%s) -- %s, then buy it.", card_name, refusal, consumable_slot_remedy()),
          card, card_name, cost)
      end
      return refuse(data, "NO_SLOT",
        string.format("Consumable slots are full -- a plain buy of %s would do nothing. Add \"use\":true to buy-and-use it now, or %s.", card_name, consumable_slot_remedy()),
        card, card_name, cost)
    end
  end
  local use_is_meaningful = is_booster or is_voucher
    or (card.ability and card.ability.consumeable ~= nil)
  local skips_slots = (data.use and use_is_meaningful) or is_booster or is_voucher

  if not skips_slots and not CardUtil.can_buy_card_space(card, data.area) then
    local remedy = "free a slot first, then buy it"
    if CardUtil.is_consumable_card(card) then
      remedy = consumable_slot_remedy() .. ", then buy it"
    elseif CardUtil.is_joker_like_card(card) then
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
  local function shop_card_is_live()
    return area_contains(get_area(buy_area_name), card)
  end

  local use_watch
  local UseCard = require("handlers.use_card")
  local before_use
  local use_settler = UseCard.outcome_settler()
  local function snapshot_before_use()
    before_use = UseCard.outcome_snapshot()
    if before_use.dollars then before_use.dollars = before_use.dollars - cost end
  end

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
    if not shop_card_is_live() then
      local message = string.format(
        "Could not buy %s: the selected shop item changed before the purchase ran.", card_name)
      return ActionResult.outcome("failed", message)
    end
    local refusal = buy_and_use and GameActions.consumable_refusal(card, nil, true)
    if refusal then
      return ActionResult.outcome("failed", string.format(
        "Could not buy-and-use %s: %s; nothing was bought.", card_name, refusal))
    end
    use_watch = GameActions.observe_use(card)
    reservation_epoch = tonumber(G.NEURO._reservation_epoch or 0) or 0
    G.NEURO.reserved_dollars = GameFacts.reserved_dollars() + cost
    local shop_buy_delay = require("core.staging").lift_safe_delay(
      Utils.gate_seconds("shop_buy_block", "NEURO_SHOP_BUY_DELAY"))
    local ok_body, ret = pcall(function()
    GameActions.try_highlight(card, true)
    local shop_buy_block = Utils.gate_seconds("shop_buy_block", "NEURO_SHOP_BUY_BLOCK")
    require("core.window").hold_after_action(shop_buy_block)
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

          local buy_card = shop_card_is_live() and card or nil
          if not buy_card then flag_buy_failed() return end
          local use_refusal = buy_and_use and GameActions.consumable_refusal(buy_card, nil, true)
          if use_refusal then
            explicit_failure = "the game refuses to use " .. card_name .. " (" .. use_refusal .. "); nothing was bought"
            return
          end
          Lifecycle.observe_joker_roster()

          local buy_cfg = { ref_table = buy_card }
          local fn
          if is_booster or is_voucher then
            fn = G.FUNCS.use_card
          else
            if data.use and use_is_meaningful then buy_cfg.id = "buy_and_use" end
            fn = G.FUNCS.buy_from_shop
          end
          if buy_and_use then snapshot_before_use() end
          if fn({ config = buy_cfg, UIBox = mock_UIBox }) == false then
            flag_buy_failed()
            return
          end
          record_joker_purchase(buy_card, cost)
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
        if card.highlighted and G and G.NEURO then
          GameActions.try_highlight(card, false)
          explicit_failure = "purchase event did not complete"
        end
        release_reservation()
        return true
      end,
    }))
    return string.format("Buying: %s for %s", Utils.real_name_or(card), Utils.money(cost))
    end)
    if ok_body then
      return ActionResult.create({
        id = tostring(data._action_id),
        name = "buy_from_shop",
        run_generation = G and G.NEURO and G.NEURO.run_generation,
        deadline = ActionResult.now() + (buy_and_use and UseCard.OUTCOME_SETTLE_MAX or 0) + math.max(3,
          shop_buy_delay
            + Utils.gate_seconds("shop_buy_watchdog_grace", "NEURO_SHOP_BUY_WATCHDOG_GRACE") + 1),
        timeout_outcome = "failed",
        debug = { area = buy_area_name, index = buy_index, card = card_name },
        probe = function()
          if explicit_failure then return "failed", { cause = explicit_failure } end
          local left_shop = not area_contains(get_area(buy_area_name), card)
          local destination = set == "Joker" and G and G.jokers or G and G.consumeables
          local voucher_key = card.config and card.config.center and card.config.center.key
          local voucher_used = is_voucher and voucher_key and G and G.GAME and G.GAME.used_vouchers
            and G.GAME.used_vouchers[voucher_key]
          local pack_started = is_booster and CardUtil.pack_area() ~= nil
            and CardUtil.pack_area() ~= pre_pack_area
          local transferred = not is_booster and not is_voucher and not data.use
            and area_contains(destination, card)
          if left_shop and (transferred or voucher_used or pack_started or data.use and use_watch.used) then
            if buy_and_use and use_watch.used and not use_settler.done() then return "pending" end
            return "applied", {
              target_left_shop = true,
              transferred = transferred,
              voucher_used = not not voucher_used,
              pack_started = pack_started,
              use_observed = use_watch.used,
            }
          end
          return "pending"
        end,
        on_applied = function(receipt)
          if buy_and_use and use_watch.used and before_use then
            receipt.applied_message = ret .. " and used it"
              .. UseCard.outcome_suffix(before_use, use_settler.unsettled)
          end
          if CardUtil.is_joker_like_card(card) then Lifecycle.sync_joker_intent_revision() end
          queue_purchase_showcase()
        end,
        cleanup = function()
          use_watch.restore()
          release_reservation()
          GameActions.try_highlight(card, false)
        end,
      })
    end
    use_watch.restore()
    release_reservation()
    error(ret, 0)
  end, nil, gameplay_event
end

local record_joker_sold = FactHints.note_joker_sold

local GUARDED_SELL_STATES = { SHOP = true, BLIND_SELECT = true, SELECTING_HAND = true }

local function sell_is_guarded(state_name)
  return GUARDED_SELL_STATES[state_name] == true or StateKinds.is_pack_state(state_name)
end

local SELL_TAGS = { CORE = true, SCALING = true, HOLD = true, CHANGE = true }
local SELL_NOTE_MAX = 140

local function quoted_note(note)
  if #note <= SELL_NOTE_MAX then return note end
  local head = note:sub(1, SELL_NOTE_MAX - 3)
  return (head:match("^(.*%S)%s") or head) .. "..."
end

local function joker_sell_reason(card_name, tag, note, sell_value, remaining)
  local sold, unreplaced = FactHints.joker_sales_this_visit()
  local head = string.format("Selling %s for %s leaves %d joker%s", card_name, Utils.money(sell_value),
    remaining, remaining == 1 and "" or "s")
  local tagged = SELL_TAGS[tag] and tag or nil
  local has_note = type(note) == "string" and note ~= ""
  local parts
  if tagged and has_note then
    parts = { string.format('%s. You tagged it %s and noted: "%s".', head, tagged, quoted_note(note)) }
  elseif tagged then
    parts = { string.format("%s. You tagged it %s.", head, tagged) }
  elseif has_note then
    parts = { string.format('%s. You noted: "%s".', head, quoted_note(note)) }
  else
    parts = { head .. " and removes this joker's listed effect from the roster." }
  end
  if unreplaced >= 1 then
    parts[#parts + 1] = string.format(
      "You have already sold %d joker%s this shop -- you are dismantling your build.", sold, sold == 1 and "" or "s")
  end
  return table.concat(parts, " ")
end

local function handle_sell_card(data)
  local _, card, index, code, err = CardArea.resolve_target(data, CardArea.TARGET_RULES.sell_card)
  if not card then return ActionResult.reject(code, err) end
  data.index = index
  local card_name = PublicCardIdentity.label(card, data.area, index)
  if card.ability and card.ability.eternal then
    return nil, string.format("Cannot sell %s — it is Eternal. Eternal jokers can never be sold or destroyed.", card_name)
  end
  local is_joker = (card.ability and card.ability.set == "Joker") and true or false
  local state_now = require("core.state").get_state_name()
  if is_joker and not (G.NEURO and G.NEURO._candidate_probe)
    and sell_is_guarded(state_now) then
    local entry = G.NEURO and G.NEURO.joker_intents and G.NEURO.joker_intents[card.sort_id]
    local review = Gate.check("handler", "sell_card", data, { target = card_name, text = function()
      local remaining = math.max(0, #((G and G.jokers and G.jokers.cards) or {}) - 1)
      return joker_sell_reason(card_name, entry and entry.tag, entry and entry.note, card.sell_cost or 0, remaining)
    end })
    if review then return nil, review end
  end
  local sell_value = card.sell_cost or 0
  local source_area = get_area(data.area)
  local function sell_card_is_live()
    local live_area = get_area(data.area)
    return live_area == source_area and area_contains(live_area, card)
  end

  local gameplay_event = {
    kind = "shop_sell",
    public_subject = GameplayJournal.public_card_label(card, data.area, data.index),
    area = data.area,
    received = tonumber(sell_value),
  }
  local function queue_sell_showcase()
    Showcase.enqueue_purchase({
      card = card,
      name = safe_name_or(card),
      cost = sell_value,
      area = "sell",
      at = Utils.now(),
    })
  end
  return function()
    if not sell_card_is_live() then
      local message = string.format(
        "Could not sell %s: the selected card changed before the sale ran.", card_name)
      return ActionResult.outcome("failed", message)
    end
    Lifecycle.observe_joker_roster()
    local sell_ok, sell_result = pcall(G.FUNCS.sell_card, { config = { ref_table = card }, UIBox = mock_UIBox })
    if not sell_ok or sell_result == false then
      require("core.neuro_lifecycle").record_failure("sell_card", "the card could not be sold")
      local message = string.format("Could not sell %s: the sell did not go through.", card_name)
      return ActionResult.outcome("failed", message)
    end
    if is_joker then Lifecycle.sync_joker_intent_revision() end
    Showcase.note_removal(card)
    return ActionResult.create({
      id = tostring(data._action_id),
      name = "sell_card",
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = ActionResult.now() + 3,
      timeout_outcome = "failed",
      debug = { area = data.area, index = data.index, card = card_name },
      probe = function()
        if not sell_card_is_live() then return "applied", { target_left_area = true } end
        return "pending"
      end,
      on_applied = function()
        if is_joker then
          Lifecycle.sync_joker_intent_revision()
          record_joker_sold()
        end
        queue_sell_showcase()
      end,
    })
  end, nil, gameplay_event
end

local function pending_sell_card_name()
  if not (G and G.NEURO and G.jokers and G.jokers.cards) then return nil end
  return Gate.reviewed_target("sell_joker")
end

return { handle_buy_from_shop = handle_buy_from_shop, handle_sell_card = handle_sell_card,
  sell_review_key = sell_context_key, voucher_review_key = voucher_context_key,
  pending_sell_card_name = pending_sell_card_name }
