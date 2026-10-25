local CardUtil = require("facts.card_util")
local Scoring = require("util.scoring")
local Utils = require("util.utils")
local ForceHelpers = require("force.force_helpers")
local FactHints = require("facts.fact_hints")
local ActionRegistry = require("core.action_registry")
local TargetContracts = require("facts.target_contracts")
local ForceReferences = require("force.force_references")
local SkipTriggers = require("facts.skip_triggers")

local function force_pack()
  local actions, action_set, accepted = ForceHelpers.collect_actions(
    { "choose_pack_card", "choose_directional_pack_card", "use_consumable",
      "use_directional_consumable", "skip_pack", "sell_card" })

  local bp = CardUtil.pack_area()
  local public_pack = ForceHelpers.public_cards(bp)

  local slot_warn = ""
  local is_consumable_pack, is_joker_pack = false, false
  for _, entry in ipairs(public_pack) do
    local set = CardUtil.card_set(entry.card)
    if CardUtil.is_consumable_set(set) then is_consumable_pack = true break end
    if CardUtil.is_joker_like_card(entry.card) then is_joker_pack = true break end
  end
  local first_public = public_pack[1] and public_pack[1].card or nil
  local is_standard = (not is_consumable_pack) and (not is_joker_pack)
    and first_public and first_public.base and first_public.base.suit ~= nil
  local js = is_joker_pack and CardUtil.joker_slot_status() or nil
  local sell_then_take = ""
  if is_joker_pack and js.full then
    local has_neg_in_pack = CardUtil.area_has_negative(bp)
    slot_warn = ForceHelpers.joker_full_warn(js, has_neg_in_pack)
    if accepted.sell_card and not accepted.choose_pack_card then
      sell_then_take = "To keep a joker from this pack with slots full, sell one of your jokers first to free a slot: "
        .. ForceReferences.withheld("choose_pack_card", "a joker slot opens") .. ". "
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
        "A sell review is open for %s: the next legal sale completes it, even if you choose a different joker. ",
        card_name)
    end
  end

  local can_pick = accepted.choose_pack_card or accepted.choose_directional_pack_card
  local sel_hints = ""
  if is_consumable_pack then
    local needs_sel = {}
    for _, entry in ipairs(public_pack) do
      local c, i = entry.card, entry.index
      local mn, mh = CardUtil.consumable_target_range(c)
      local action_name = TargetContracts.get(c) and "choose_directional_pack_card"
        or "choose_pack_card"
      if mh and mh > 0 and accepted[action_name] and CardUtil.can_take_pack_card(c) then
        local nm = require("util.utils").safe_name_or(c)
        local lo, hi = ForceHelpers.payload_target_range({ area = "booster_pack", index = i })
        needs_sel[#needs_sel + 1] = string.format(
          "For card %d (%s), %s with %s.",
          i, nm, require("core.action_registry").phrase(action_name):gsub("^%u", string.lower), ForceHelpers.target_fields(action_name, lo or mn, hi or mh))
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
  if can_pick then
    take_hint = "When a card is takeable (you have a free slot or a hand target), taking it is almost always better than skipping. "
  end

  local kind_hint = ""
  if can_pick then
    if is_standard then
      kind_hint = "Playing cards go straight to your deck -- a Standard pick never needs a free slot. "
    elseif is_consumable_pack then
      kind_hint = "A picked Tarot/Planet/Spectral is used the moment you pick it, so a full consumable board usually does NOT block a pick. Exception: a card that CREATES consumables needs an open consumable slot, and one that creates a joker needs an open joker slot. "
    end
  end

  local blocked_reason = ""
  if not can_pick
    and is_consumable_pack and #public_pack > 0 then
    blocked_reason = "You can't take a card from this pack right now: a card that CREATES a joker/consumable needs an open slot (and a targeting card needs a valid hand target). Free a slot by using or selling an owned consumable/joker if you want it"
      .. (accepted.skip_pack and ", otherwise skip the pack. " or ". ")
  end

  local pack_scaling_hint = ""
  if is_joker_pack and can_pick
    and Scoring.owned_xmult_state() == "none" then
    pack_scaling_hint = "None of your jokers multiply your score -- prefer a joker whose text shows an X multiplier (e.g. 'X1.5 Mult'), or one that feeds a joker you own, over a flat +chips/+mult pick. "
  end

  local has_planet = ForceHelpers.any_public(bp, function(c) return CardUtil.card_set(c) == "Planet" end)
  local has_other = ForceHelpers.any_public(bp, function(c) return CardUtil.card_set(c) ~= "Planet" end)
  local planet_hint = ""
  if has_planet and can_pick then
    planet_hint = "A Planet permanently levels ONE hand type -- prefer one for the hand you play most (each Planet row above shows how often you played its hand this run), not one you rarely make. "
  end

  local candidates, push_move = ForceHelpers.candidate_list, ForceHelpers.push_move
  local move_bits, tool_bits = {}, {}
  if accepted.choose_pack_card then push_move(move_bits, candidates("choose_pack_card")) end
  if accepted.choose_directional_pack_card then
    move_bits[#move_bits + 1] = ActionRegistry.prompt("choose_directional_pack_card")
  end
  if accepted.skip_pack then
    move_bits[#move_bits + 1] = ActionRegistry.render("skip_pack", {})
      .. " (take nothing from this pack and move on; the pack is already paid for, so skipping costs"
      .. " no money and no slot)"
  end
  if accepted.sell_card then tool_bits.sell_card = candidates("sell_card") end
  ForceHelpers.consumable_tools(tool_bits, accepted)
  local move_tail = ForceHelpers.your_move(move_bits)

  local plan_window = FactHints.plan_note("pack")
  if can_pick then
    plan_window = plan_window
      .. "Pick the card that fits your build and plan -- your jokers and hand levels are shown above. "
      .. (has_other and "A Tarot/Spectral/Joker should support your build, not just any card. " or "")
      .. (accepted.skip_pack and "If none of them do, skipping the pack is a real option rather than a forfeit. " or "")
  end

  local bank_line = (G and G.GAME and G.GAME.dollars ~= nil)
    and (Utils.money(G.GAME.dollars) .. " in bank.") or ""

  local query = pending_sell .. ForceHelpers.repeat_pressure_note(actions) .. ForceHelpers.paragraph(plan_window)
    .. ForceHelpers.paragraph(sell_then_take .. blocked_reason .. sel_hints
      .. take_hint .. kind_hint .. pack_scaling_hint .. planet_hint)
    .. move_tail
  local StateDoc = require("context.state_doc")
  return ForceHelpers.finish(query, {
    state_extra = StateDoc.lines(StateDoc.section("Pack", bank_line),
      StateDoc.section("Constraints", slot_fact .. slot_warn),
      StateDoc.section("Skip rules", SkipTriggers.note("pack", G.jokers, bp)),
      FactHints.plan_state("pack")),
    actions = actions,
    tool_bits = tool_bits,
  })
end

return { build = force_pack }
