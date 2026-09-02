local CardUtil = require("facts.card_util")
local HandFacts = require("facts.hand_facts")
local Scoring = require("util.scoring")
local money = require("context.ctx_helpers").money
local ForceHelpers = require("force.force_helpers")
local FactHints = require("facts.fact_hints")
local ActionRegistry = require("core.action_registry")
local failed_action_warning = ForceHelpers.failed_action_warning

local function force_pack(state_name)
  local pack_type = (state_name == "SMODS_BOOSTER_OPENED") and "BOOSTER" or state_name:gsub("_PACK", "")
  local actions, action_set, accepted = ForceHelpers.collect_actions(
    { "choose_pack_card", "choose_directional_pack_card", "use_consumable",
      "use_directional_consumable", "skip_pack", "sell_card" })

  local bp = CardUtil.pack_area()

  local slot_warn = ""
  local is_consumable_pack = (pack_type == "TAROT" or pack_type == "PLANET" or pack_type == "SPECTRAL")
  local is_joker_pack = (pack_type == "BUFFOON")
  if not is_joker_pack and not is_consumable_pack and bp and bp.cards then
    for _, c in ipairs(bp.cards) do
      local set = CardUtil.card_set(c)
      if CardUtil.is_consumable_set(set) then is_consumable_pack = true break end
      if CardUtil.is_joker_like_card(c) then is_joker_pack = true break end
    end
  end
  local is_standard = (not is_consumable_pack) and (not is_joker_pack)
    and bp and bp.cards and bp.cards[1] and bp.cards[1].base and bp.cards[1].base.suit ~= nil
  local js = is_joker_pack and CardUtil.joker_slot_status() or nil
  local sell_then_take = ""
  if is_joker_pack and js.full then
    local has_neg_in_pack = CardUtil.area_has_negative(bp)
    slot_warn = ForceHelpers.joker_full_warn(js, has_neg_in_pack)
    if action_set.sell_card and not action_set.choose_pack_card then
      sell_then_take = FactHints.emit("pack_sell_then_take",
        "To keep a joker from this pack with slots full: sell_card one of your jokers first to free a slot, then choose_pack_card to take the pack joker (it becomes takeable once a slot opens). ")
    end
  end

  if action_set.sell_card then
    local jfull = (js or CardUtil.joker_slot_status()).full
    local cfull = CardUtil.consumable_slot_status().full
    if not (jfull or cfull) then
      action_set.sell_card = nil
      accepted.sell_card = nil
      for i = #actions, 1, -1 do if actions[i] == "sell_card" then table.remove(actions, i) end end
    end
  end

  local pending_sell = ""
  if action_set.sell_card then
    local ok_ps, card_name = pcall(require("handlers.shop_handlers").pending_sell_card_name)
    if ok_ps and type(card_name) == "string" and card_name ~= "" then
      pending_sell = string.format(
        "A sell_card confirmation is open for %s: sending sell_card for that joker again completes the sale. ",
        card_name)
    end
  end

  local sel_hints = ""
  if is_consumable_pack and bp and bp.cards then
    local needs_sel = {}
    for i, c in ipairs(bp.cards) do
      local mn, mh = CardUtil.consumable_target_range(c)
      if mh and mh > 0 then
        local nm = c.ability and c.ability.name or "Tarot"
        local pick = (mn == mh) and ((mn == 1) and "pick 1 hand position"
            or ("pick exactly " .. mn .. " different hand positions"))
          or ("pick " .. mn .. " to " .. mh .. " different hand positions")
        needs_sel[#needs_sel + 1] = string.format(
          "Card %d (%s) needs %d-%d hand cards. "
          .. 'choose_pack_card|{"area":"booster_pack","index":%d,"hand_indices":[<%s>]}.',
          i, nm, mn, mh, i, pick)
      end
    end
    if #needs_sel > 0 then
      sel_hints = table.concat(needs_sel, " ") .. " "
    end
  end

  local slot_fact = ""
  if is_joker_pack and not js.full then
    if (js.count or 0) > 0 then
      slot_fact = "You have room to keep a joker. "
    else
      slot_fact = string.format("You own no jokers and have %d open joker slot(s). ", js.limit)
    end
  end

  local take_hint = ""
  if action_set.choose_pack_card or action_set.choose_directional_pack_card then
    take_hint = FactHints.emit("pack_take",
      "When a card is takeable (you have a free slot or a hand target), taking it is almost always better than skipping. ")
  end

  local kind_hint = ""
  if action_set.choose_pack_card or action_set.choose_directional_pack_card then
    if is_standard then
      kind_hint = FactHints.emit("pack_std",
        "Playing cards go straight to your deck -- a Standard pick never needs a free slot. ")
    elseif is_consumable_pack then
      kind_hint = FactHints.emit("pack_cons",
        "A picked Tarot/Planet/Spectral is used the moment you pick it, so a full consumable board usually does NOT block a pick. Exception: a card that CREATES consumables needs an open consumable slot, and one that creates a joker needs an open joker slot. ")
    end
  end

  local blocked_reason = ""
  if not (action_set.choose_pack_card or action_set.choose_directional_pack_card)
    and is_consumable_pack and bp and bp.cards and #bp.cards > 0 then
    blocked_reason = FactHints.emit("pack_blocked_cons",
      "You can't take a card from this pack right now: a card that CREATES a joker/consumable needs an open slot (and a targeting card needs a valid hand target). Free a slot by using or selling an owned consumable/joker if you want it, otherwise skip_pack. ")
  end

  local pack_scaling_hint = ""
  if is_joker_pack and (action_set.choose_pack_card or action_set.choose_directional_pack_card)
    and Scoring.owned_xmult_state() == "none" then
    pack_scaling_hint = FactHints.emit("pack_scaling",
      "None of your jokers multiply your score -- prefer a joker whose text shows an X multiplier (e.g. 'X1.5 Mult'), or one that feeds a joker you own, over a flat +chips/+mult pick. ")
  end

  local planet_hint = ""
  do
    local has_planet = (pack_type == "PLANET")
    if not has_planet and bp and bp.cards then
      for _, c in ipairs(bp.cards) do if CardUtil.card_set(c) == "Planet" then has_planet = true; break end end
    end
    if has_planet and (action_set.choose_pack_card or action_set.choose_directional_pack_card) then
      planet_hint = FactHints.emit("pack_planet",
        "A Planet permanently levels ONE hand type -- level a type you actually play (see the Hand levels and played counts), not one you rarely make. "
        .. HandFacts.leveled_spread_note())
    end
  end

  local function candidates(name)
    local out = {}
    for _, payload in ipairs(ActionRegistry.candidates(name)) do
      out[#out + 1] = ActionRegistry.render(name, payload)
    end
    return table.concat(out, " or ")
  end
  local move_bits = {}
  if accepted.choose_pack_card then
    local rendered = candidates("choose_pack_card")
    if rendered ~= "" then move_bits[#move_bits + 1] = rendered end
  end
  if accepted.choose_directional_pack_card then
    move_bits[#move_bits + 1] = ActionRegistry.prompt("choose_directional_pack_card")
  end
  if accepted.skip_pack then
    move_bits[#move_bits + 1] = ActionRegistry.render("skip_pack", {})
      .. " (take nothing from this pack and move on; the pack is already paid for, so skipping costs"
      .. " no money and no slot)"
  end
  if accepted.sell_card then
    local rendered = candidates("sell_card")
    if rendered ~= "" then move_bits[#move_bits + 1] = rendered end
  end
  if accepted.use_consumable then
    local rendered = candidates("use_consumable")
    if rendered ~= "" then move_bits[#move_bits + 1] = rendered end
  end
  if accepted.use_directional_consumable then
    move_bits[#move_bits + 1] = ActionRegistry.prompt("use_directional_consumable")
  end
  local area_bits = { 'booster_pack = the cards in the pack ('
    .. ForceHelpers.index_range((bp and bp.cards) and #bp.cards or 0) .. ')' }
  local owned = (G and G.consumeables and G.consumeables.cards) and #G.consumeables.cards or 0
  if owned > 0 then
    area_bits[#area_bits + 1] = 'consumeables = the Consumables you already own ('
      .. ForceHelpers.index_range(owned) .. ')'
  end
  local move_tail = (#move_bits > 0)
    and ("Areas: " .. table.concat(area_bits, "; ")
      .. ".\nYour move: " .. table.concat(move_bits, "; ") .. ". ")
    or ""

  local plan_window = FactHints.plan_note("pack")
  if action_set.skip_pack then
    plan_window = plan_window .. FactHints.emit("pack_pick_fit",
      "Pick the card that fits your build and plan -- your jokers and hand levels are shown above. A Planet levels the hand you play most; a Tarot/Spectral/Joker should support your build, not just any card. If none of them do, skip_pack is a real option rather than a forfeit. ")
  end

  local bank_line = (G and G.GAME and G.GAME.dollars ~= nil)
    and (money(G.GAME.dollars) .. " in bank. ") or ""

  local query = "State: " .. pack_type .. " pack. " .. bank_line
    .. failed_action_warning() .. pending_sell .. ForceHelpers.pending_gate_note(actions)
    .. ForceHelpers.repeat_pressure_note() .. plan_window
    .. slot_fact .. slot_warn .. sell_then_take .. blocked_reason .. sel_hints .. take_hint .. kind_hint
    .. pack_scaling_hint .. planet_hint
    .. move_tail
  return {
    query = query:gsub("  +", " "),
    actions = actions
  }
end

return { build = force_pack }
