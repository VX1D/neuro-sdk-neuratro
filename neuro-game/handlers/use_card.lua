-- use_card owns the pack lifecycle (pack_choices/end_consumeable): do not call end_consumeable here
local Utils = require("util.utils")
local Tuning = require("core.tuning")
local CardArea = require("facts.card_area_util")
local CardUtil = require("facts.card_util")
local ForceHelpers = require("force.force_helpers")
local NeuroAnim = require("render.neuro-anim")
local safe_name = Utils.safe_name
local validate_area_card = CardArea.validate_area_card
local validate_hand_indices = CardArea.validate_hand_indices
local clear_area_highlight = CardArea.clear_area_highlight
local add_area_highlight = CardArea.add_area_highlight
local mock_UIBox = CardArea.mock_UIBox
local can_take_pack_card = CardUtil.can_take_pack_card
local card_set = CardUtil.card_set

local function handle_use_card(data)
  local area, card, err = validate_area_card(data)
  if err then return nil, err end
  local card_name = Utils.real_name_or(card)

  local function snapshot_booster_options(selected_card)
    local bp = CardUtil.pack_area()
    if not (bp and bp.cards and #bp.cards > 0) then
      return nil
    end
    local options = {}
    local selected_index = 1
    for i, opt in ipairs(bp.cards) do
      local nm = safe_name(opt) or ("Card " .. tostring(i))
      local ds = Utils.card_description_with_fallback(opt)
      options[#options + 1] = {
        card = opt,
        name = tostring(nm),
        desc = tostring(ds or "-"),
      }
      if opt == selected_card then
        selected_index = i
      end
    end
    return {
      selected_index = selected_index,
      options = options,
      picks_left = tonumber(G and G.GAME and G.GAME.pack_choices or 0) or 0,
    }
  end

  local function queue_pick_showcase(tag, shown_cost, extra)
    if not G then return end
    local q = G.NEURO.purchase_showcase_queue
    if type(q) ~= "table" then q = {} end

    local desc = Utils.card_description_with_fallback(card)
    if not desc or desc == "" then desc = "-" end

    q[#q + 1] = {
      card = card,
      name = card_name,
      desc = tostring(desc),
      cost = tonumber(shown_cost) or 0,
      area = tostring(tag or "pick"),
      at = Utils.now(),
      options = extra and extra.options or nil,
      selected_index = extra and extra.selected_index or nil,
      picks_left = extra and extra.picks_left or nil,
    }
    while #q > 2 do
      table.remove(q, 1)
    end
    G.NEURO.purchase_showcase_queue = q
  end

  local is_playing_card = Utils.is_playing_card(card)
  local _, needs_target = CardUtil.consumable_target_range(card)
  local bp_now = CardUtil.pack_area()
  if area == bp_now and not can_take_pack_card(card) then
    local set = card_set(card)
    local slot = (set == "Tarot" or set == "Planet" or set == "Spectral") and "consumable" or "joker"
    return nil, string.format("Cannot pick '%s': %s slots are full. Use skip_booster or sell a %s first.", card_name, slot, slot)
  end

  -- gate no-target consumable use: pack jokers/playing cards escape (can_use_consumeable throws on nil ability.consumeable, pcall swallows it); skip when hand_indices given (e.g. Aura highlights only exist after exec)
  local has_hand_indices = data.hand_indices and type(data.hand_indices) == "table" and #data.hand_indices > 0
  if (area == (G and G.consumeables) or area == bp_now) and not needs_target
     and not has_hand_indices
     and type(card.can_use_consumeable) == "function" then
    -- (any_state, skip_check): check real eligibility (target/slot) but skip transient locks that would reject a usable consumable
    local ok_use, usable = pcall(card.can_use_consumeable, card, true, true)
    if ok_use and not usable then
      return nil, string.format("'%s' can't be used right now (needs a valid joker/target/slot or the right screen).", card_name)
    end
  end

  local hand_indices = nil
  if data.hand_indices and type(data.hand_indices) == "table" and #data.hand_indices > 0 then
    if not G.hand or not G.hand.cards then
      return nil, "Hand is not available. Cannot select hand cards for consumable use."
    end
    local mn, mh = CardUtil.consumable_target_range(card)
    local verr
    hand_indices, verr = validate_hand_indices(data.hand_indices, #G.hand.cards, mh)
    if not hand_indices then
      return nil, verr
    end
    if mh and #hand_indices < mn then
      return nil, string.format("Too few cards: '%s' needs at least %d selected, you provided %d.", card_name, mn, #hand_indices)
    end
  elseif needs_target and needs_target > 0 and not is_playing_card then
    if not (G.hand and G.hand.cards and #G.hand.cards > 0) then
      return nil, string.format("'%s' targets hand cards, but there is no hand to target right now.", card_name)
    end
    return nil, string.format("'%s' needs up to %d card(s) selected in hand — provide hand_indices (1-based positions), e.g. {1,2}.", card_name, needs_target)
  end

  return function()
    local pack_snapshot = nil
    local bp = CardUtil.pack_area()
    local is_pack_pick = (area == bp)

    if is_pack_pick then
      pack_snapshot = snapshot_booster_options(card)

      pcall(CardArea.set_highlight, card, true)
      if NeuroAnim and NeuroAnim.hover_pack_card then
        pcall(function() NeuroAnim.hover_pack_card(card, bp) end)
      end

      local pack_pick_block = Tuning.get("NEURO_PACK_PICK_BLOCK")
      local pack_pick_delay = Tuning.get("NEURO_PACK_PICK_DELAY")
      local t = Utils.now()
      G.NEURO.last_action_at = t + pack_pick_block

      local _, mh_sel = CardUtil.consumable_target_range(card)
      local needs_hand_sel = (not is_playing_card) and mh_sel and mh_sel > 0
      local captured_hand_indices = (needs_hand_sel and hand_indices) or nil

      if G.E_MANAGER and Event then
        local fn = G.FUNCS and G.FUNCS.use_card
        G.E_MANAGER:add_event(Event({
          trigger = "after",
          delay   = pack_pick_delay,
          func    = function()
            if not fn then
              ForceHelpers.correct_optimistic("use_card", "Booster pack pick failed to execute.", data._action_id,
                "Your booster pick did not go through; the pack is unchanged.")
              return true
            end
            pcall(CardArea.set_highlight, card, false)
            if NeuroAnim and NeuroAnim.pick_pack_card then pcall(NeuroAnim.pick_pack_card, card, bp) end
            if captured_hand_indices and G.hand and G.hand.cards then
              clear_area_highlight(G.hand)
              for _, idx in ipairs(captured_hand_indices) do
                local hcard = G.hand.cards[idx]
                if hcard then add_area_highlight(G.hand, hcard) end
              end
            end
            -- do NOT clear the hand highlight here: use_consumeable's deferred events (card.lua:1429) still index G.hand.highlighted[i]; clearing early nil-indexes every frame and freezes E_MANAGER
            local ok_pick = pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox })
            if not ok_pick then
              ForceHelpers.correct_optimistic("use_card", "Booster pack pick failed to execute.", data._action_id,
                "Your booster pick did not go through; the pack is unchanged.")
              return true
            end
            if pack_snapshot and pack_snapshot.options and #pack_snapshot.options >= 2 then
              queue_pick_showcase("booster_choice", 0, pack_snapshot)
            else
              queue_pick_showcase("booster_pick", 0)
            end
            return true
          end,
        }))

        local watchdog_delay = pack_pick_delay + Tuning.get("NEURO_PACK_PICK_WATCHDOG_GRACE")
        G.E_MANAGER:add_event(Event({
          trigger = "after",
          delay   = watchdog_delay,
          func    = function()
            if card and card.highlighted and G and G.NEURO then
              pcall(CardArea.set_highlight, card, false)
              ForceHelpers.correct_optimistic("use_card", "Booster pack pick did not complete (event lost).", data._action_id)
            end
            return true
          end,
        }))
      else
        local fn = G.FUNCS and G.FUNCS.use_card
        pcall(CardArea.set_highlight, card, false)
        if captured_hand_indices and G.hand and G.hand.cards then
          clear_area_highlight(G.hand)
          for _, idx in ipairs(captured_hand_indices) do
            local hcard = G.hand.cards[idx]
            if hcard then add_area_highlight(G.hand, hcard) end
          end
        end
        local ok_pick = fn and pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox })
        if not ok_pick then
          ForceHelpers.correct_optimistic("use_card", "Booster pack pick failed to execute.", data._action_id,
            "Your booster pick did not go through; the pack is unchanged.")
          return
        elseif pack_snapshot and pack_snapshot.options and #pack_snapshot.options >= 2 then
          queue_pick_showcase("booster_choice", 0, pack_snapshot)
        else
          queue_pick_showcase("booster_pick", 0)
        end
      end
    else
      if hand_indices and G.hand and G.hand.cards then
        clear_area_highlight(G.hand)
        for _, idx in ipairs(hand_indices) do
          local hcard = G.hand.cards[idx]
          if hcard then add_area_highlight(G.hand, hcard) end
        end
      end
      local fn = G.FUNCS and G.FUNCS.use_card
      local used_ok = true
      if fn then used_ok = pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox }) end
      if not used_ok then
        -- correct_optimistic already sends the failure context; returning a string would send a 2nd one
        ForceHelpers.correct_optimistic("use_card", "the consumable could not be used", data._action_id,
          "Your use_card did not go through (the consumable couldn't be used); nothing changed.")
        return
      end
      if used_ok and hand_indices and G and G.NEURO then
        -- drop the fingerprint so the settled (post-mutation) hand re-sends instead of the pre-mutation H: line
        -- do NOT clear the hand highlight here: deferred events still index G.hand.highlighted[i] (card.lua:1429) -> E_MANAGER freeze
        G.NEURO.force_dirty = true
        G.NEURO.last_force_fingerprint = nil
      end
    end

    return "Used: " .. card_name
  end
end

return { handle_use_card = handle_use_card }
