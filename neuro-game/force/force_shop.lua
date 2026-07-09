local Actions = require("core.actions")
local FactHints = require("facts.fact_hints")
local ForceHelpers = require("force.force_helpers")
local CardUtil = require("facts.card_util")
local CtxEconomy = require("context.ctx_economy")
local once_per_state_entry_hint = FactHints.once_per_state_entry_hint
local voucher_chain_hint = FactHints.voucher_chain_hint
local voucher_basics_hint = FactHints.voucher_basics_hint
local shop_edition_hint = FactHints.shop_edition_hint
local failed_action_warning = ForceHelpers.failed_action_warning

local function build()
  -- set_joker_order is ride-along: added after the empty-check so it never counts as the only progress action
  local force_actions, can = ForceHelpers.collect_actions(
    { "buy_from_shop", "sell_card", "reroll_shop", "use_card", "toggle_shop" })

  if #force_actions == 0 then
    return nil
  end
  if Actions.is_action_valid("set_joker_order") then force_actions[#force_actions + 1] = "set_joker_order" end

  local js = CardUtil.joker_slot_status()
  local joker_slot_warn = ""
  if js.full then
    local has_neg_in_shop = CardUtil.area_has_negative(G.shop_jokers)
    joker_slot_warn = ForceHelpers.joker_full_warn(js, has_neg_in_shop)
    if not has_neg_in_shop and G.shop_jokers and G.shop_jokers.cards then
      for _, c in ipairs(G.shop_jokers.cards) do
        if CardUtil.is_joker_like_card(c, "shop_jokers") then
          joker_slot_warn = joker_slot_warn
            .. "To take a shop joker with slots full: sell a joker (sell_card|{\"area\":\"jokers\",\"index\":N}) first, then buy_from_shop. "
          break
        end
      end
    end
  end
  local buffoon_full_warn = ""
  if js.full and G.shop_booster and G.shop_booster.cards then
    for _, c in ipairs(G.shop_booster.cards) do
      if CardUtil.booster_kind(c) == "Buffoon" then
        buffoon_full_warn = "A Buffoon pack gives jokers; with slots full you can open it but can't keep one without selling a joker first. "
        break
      end
    end
  end
  local cs = CardUtil.consumable_slot_status()
  local cons_slot_warn = ""
  if cs.full then
    cons_slot_warn = string.format("Consumable slots FULL (%d/%d). Tarot/planet/spectral cards require an open consumable slot. Selling or using an owned consumable frees a consumable slot immediately. A no-target shop consumable can be bought-and-used immediately (buy with \"use\":true) with NO free slot needed; only buying one to keep requires an open slot. ", cs.count, cs.limit)
  end
  local blocked_consumable_warn = ""
  if CardUtil.has_blocked_consumable() then
    blocked_consumable_warn = "An owned consumable that creates a joker or consumables (C: ok=N) is blocked by a full output slot; sell a joker or consumable first to free room. "
  end
  local joker_order_hint = ""
  if G.jokers and G.jokers.cards and #G.jokers.cards >= 2 then
    local has_copy = false
    for _, card in ipairs(G.jokers.cards) do
      if CardUtil.is_copy_joker(card) then has_copy = true end
    end
    local copy_fact = has_copy
      and "Blueprint copies the joker to its right; Brainstorm copies the leftmost joker. "
      or ""
    joker_order_hint = once_per_state_entry_hint(
      "joker_order",
      copy_fact
        .. "Use set_joker_order|{\"from_index\":i,\"to_index\":j} to rearrange the J: order. "
    )
  end
  local voucher_chains = voucher_chain_hint()
  local voucher_basics = voucher_basics_hint()
  local edition_hint = shop_edition_hint()

  -- shop_jokers area also lists Tarot/Planet/Spectral cards, not just jokers
  local has_shop_consumable = false
  if G.shop_jokers and G.shop_jokers.cards then
    for _, c in ipairs(G.shop_jokers.cards) do
      local set = CardUtil.card_set(c)
      if set == "Tarot" or set == "Planet" or set == "Spectral" then has_shop_consumable = true break end
    end
  end

  local move_bits = {}
  if can.buy_from_shop then
    local buy_bit = 'buy_from_shop|{"area":"shop_jokers|shop_vouchers|shop_booster","index":N}'
    if has_shop_consumable then
      buy_bit = buy_bit .. ' (for a no-target consumable add "use":true; a targeting consumable must be bought, then use_card with hand_indices)'
    end
    move_bits[#move_bits + 1] = buy_bit
  end
  if can.reroll_shop then move_bits[#move_bits + 1] = 'reroll_shop|{} (replaces all I: rows with a new random set; cost rises each reroll)' end
  if can.sell_card then move_bits[#move_bits + 1] = 'sell_card|{"area":"jokers|consumeables","index":N}' end
  if can.use_card then move_bits[#move_bits + 1] = 'use_card|{"area":"consumeables","index":N}' end
  if can.toggle_shop then move_bits[#move_bits + 1] = 'toggle_shop|{} to leave the shop' end
  local move_tail = (#move_bits > 0) and ("Your move: " .. table.concat(move_bits, "; ") .. ". ") or ""

  local cash = tonumber(G and G.GAME and G.GAME.dollars or 0) or 0
  local econ_line = string.format(
    "ECO|cash:$%d|spendable:$%d|interest_next_round:$%d|safe_spend_to_keep_interest:$%d|debt_floor:$%d. "
    .. "Avoid buying boosters or rerolling if spendable would drop below $2 after the purchase, unless the buy clearly advances the run. ",
    cash, CtxEconomy.spendable(), CtxEconomy.calc_interest(cash),
    CtxEconomy.safe_spend_keep_interest(), CtxEconomy.spend_floor())

  local query = "State: SHOP. "
    .. econ_line
    .. failed_action_warning()
    .. joker_slot_warn
    .. buffoon_full_warn
    .. cons_slot_warn
    .. blocked_consumable_warn
    .. joker_order_hint
    .. edition_hint
    .. voucher_basics
    .. voucher_chains
    .. move_tail
  return {
    query = query:gsub("  +", " "),
    actions = force_actions
  }
end

return { build = build }
