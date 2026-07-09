local CardUtil = require("facts.card_util")
local ForceHelpers = require("force.force_helpers")
local FactHints = require("facts.fact_hints")
local failed_action_warning = ForceHelpers.failed_action_warning
local once_per_state_entry_hint = FactHints.once_per_state_entry_hint

local function force_pack(state_name)
  local pack_type = (state_name == "SMODS_BOOSTER_OPENED") and "BOOSTER" or state_name:gsub("_PACK", "")
  local picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0
  local actions, action_set = ForceHelpers.collect_actions(
    { "use_card", "skip_booster", "sell_card" })

  local bp = CardUtil.pack_area()

  local slot_warn = ""
  local is_consumable_pack = (pack_type == "TAROT" or pack_type == "PLANET" or pack_type == "SPECTRAL")
  local is_joker_pack = (pack_type == "BUFFOON")
  if not is_joker_pack and not is_consumable_pack and bp and bp.cards then
    for _, c in ipairs(bp.cards) do
      local set = CardUtil.card_set(c)
      if set == "Tarot" or set == "Planet" or set == "Spectral" then is_consumable_pack = true break end
      if CardUtil.is_joker_like_card(c) then is_joker_pack = true break end
    end
  end
  local is_standard = (not is_consumable_pack) and (not is_joker_pack)
    and bp and bp.cards and bp.cards[1] and bp.cards[1].base and bp.cards[1].base.suit ~= nil
  local js = is_joker_pack and CardUtil.joker_slot_status() or nil
  if is_joker_pack then
    if js.full then
      local has_neg_in_pack = CardUtil.area_has_negative(bp)
      slot_warn = ForceHelpers.joker_full_warn(js, has_neg_in_pack)
    end
  end

  local sel_hints = ""
  if is_consumable_pack and bp and bp.cards then
    local needs_sel = {}
    for i, c in ipairs(bp.cards) do
      local mn, mh = CardUtil.consumable_target_range(c)
      if mh and mh > 0 then
        local nm = c.ability and c.ability.name or "Tarot"
        needs_sel[#needs_sel + 1] = string.format(
          "Card %d (%s) needs %d-%d hand cards. "
          .. 'use_card|{"area":"booster_pack","index":%d,"hand_indices":[N,...]}.',
          i, nm, mn, mh, i)
      end
    end
    if #needs_sel > 0 then
      sel_hints = table.concat(needs_sel, " ") .. " "
    end
  end

  local slot_fact = ""
  if is_joker_pack then
    if not js.full then
      slot_fact = string.format("Joker slots: %d/%d used (room to keep a joker). ", js.count, js.limit)
    end
  end

  local take_hint = ""
  if action_set.use_card then
    take_hint = once_per_state_entry_hint("pack_take",
      "This booster is already paid for -- skipping wastes it. When a card is takeable (you have a free slot or a hand target), taking one is almost always better than skipping. ")
  end

  local kind_hint = ""
  if action_set.use_card then
    if is_standard then
      kind_hint = once_per_state_entry_hint("pack_std",
        "Playing cards go straight to your deck and always fit -- there is no slot to spend, so a Standard pick never needs room. ")
    elseif is_consumable_pack then
      kind_hint = once_per_state_entry_hint("pack_cons",
        "A picked Tarot/Planet/Spectral is used the moment you pick it and normally takes no consumable slot, so a full consumable board usually does NOT block a pick. Exceptions -- cards that CREATE consumables (The Emperor makes 2 Tarots, The High Priestess makes 2 Planets, The Fool) can't be picked while your consumable board is full; cards that create a joker (Judgement, The Soul, Wraith, Ankh) need an open joker slot. ")
    end
  end

  local move_bits = {}
  if action_set.use_card then
    move_bits[#move_bits + 1] = 'use_card|{"area":"booster_pack","index":N}'
      .. (is_consumable_pack and ' (add "hand_indices":[N,...] for a targeting card)' or '')
  end
  if action_set.skip_booster then move_bits[#move_bits + 1] = 'skip_booster|{}' end
  if action_set.sell_card then move_bits[#move_bits + 1] = 'sell_card|{"area":"jokers|consumeables","index":N}' end
  local move_tail = (#move_bits > 0) and ("Your move: " .. table.concat(move_bits, "; ") .. ". ") or ""

  local query = "State: " .. pack_type .. " pack. Picks left: " .. tostring(math.max(0, math.floor(picks_left))) .. ". "
    .. slot_fact .. slot_warn .. sel_hints .. take_hint .. kind_hint
    .. failed_action_warning()
    .. move_tail
  return {
    query = query:gsub("  +", " "),
    actions = actions
  }
end

return { build = force_pack }
