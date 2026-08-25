local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local CardUtil = require("facts.card_util")
local ForceHelpers = require("force.force_helpers")
local function anim() return Utils.lazy_require("render.neuro-anim") end
local Showcase = require("hud.showcase")
local ActionResult = require("core.action_result")
local ActionReceipt = require("core.action_receipt")
local Lifecycle = require("core.neuro_lifecycle")
local LevelDelta = require("util.level_delta")
local validate_area_card = CardArea.validate_area_card
local validate_hand_indices = CardArea.validate_hand_indices
local clear_area_highlight = GameActions.clear_area_highlight
local add_area_highlight = GameActions.add_area_highlight
local mock_UIBox = GameActions.mock_UIBox
local can_take_pack_card = CardUtil.can_take_pack_card

local function handle_use_card(data)
  local area, card, err = validate_area_card(data)
  if err then return ActionResult.reject("TARGET_UNAVAILABLE", err) end
  local face_down = CardUtil.is_face_down(card)
  local card_name = face_down and "face-down card" or Utils.real_name_or(card)
  local name_err = not face_down and CardArea.check_target_name(card, data.name, data.index, data.area) or nil
  if name_err then return ActionResult.reject("STALE_TARGET", name_err) end
  if require("facts.target_contracts").get(card) and not data._directional_contract then
    return ActionResult.reject("INVALID_SELECTION",
      "This card has directional targets; use use_directional_card so source and destination are explicit.")
  end

  local function queue_pick_showcase(tag, shown_cost, levels)
    Showcase.enqueue_purchase({
      card = face_down and nil or card,
      name = card_name,
      cost = tonumber(shown_cost) or 0,
      area = tostring(tag or "pick"),
      levels = levels,
      at = Utils.now(),
    })
    pcall(require("core.rewards").announce_rare_joker, card)
  end

  local is_playing_card = Utils.is_playing_card(card)
  local _, needs_target = CardUtil.consumable_target_range(card)
  local bp_now = CardUtil.pack_area()
  local from_pack = area == bp_now
  if from_pack and not can_take_pack_card(card) then
    local slot = CardUtil.is_consumable_card(card) and "consumable" or "joker"
    Showcase.enqueue_refusal({ code = "NO_SLOT", card = card, name = card_name,
      action_id = data._action_id })
    return ActionResult.reject("NO_SLOT",
      string.format("Cannot pick '%s': %s slots are full. Use skip_booster or sell a %s first.", card_name, slot, slot))
  end

  local has_hand_indices = data.hand_indices and type(data.hand_indices) == "table" and #data.hand_indices > 0
  if (area == (G and G.consumeables) or from_pack) and not needs_target
     and not has_hand_indices
     and type(card.can_use_consumeable) == "function" then
    local ok_use, usable = pcall(card.can_use_consumeable, card, true, true)
    if ok_use and not usable then
      return ActionResult.reject("PRECONDITION_FAILED",
        string.format("'%s' can't be used right now (needs a valid joker/target/slot or the right screen).", card_name))
    end
  end

  local hand_indices = nil
  local prepared_hand_cards = nil
  if data.hand_indices and type(data.hand_indices) == "table" and #data.hand_indices > 0 then
    if not G.hand or not G.hand.cards then
      return ActionResult.reject("TARGET_UNAVAILABLE",
        "Hand is not available. Cannot select hand cards for consumable use.")
    end
    local mn, mh = CardUtil.consumable_target_range(card)
    local verr
    hand_indices, verr = validate_hand_indices(data.hand_indices, #G.hand.cards, mh)
    if not hand_indices then
      return ActionResult.reject("INVALID_SELECTION", verr)
    end
    if mh and #hand_indices < mn then
      return ActionResult.reject("INVALID_SELECTION",
        string.format("Too few cards: '%s' needs at least %d selected, you provided %d.", card_name, mn, #hand_indices))
    end
    prepared_hand_cards = {}
    for i = 1, #hand_indices do prepared_hand_cards[i] = G.hand.cards[hand_indices[i]] end
  elseif needs_target and needs_target > 0 and not is_playing_card then
    if not (G.hand and G.hand.cards and #G.hand.cards > 0) then
      return ActionResult.reject("TARGET_UNAVAILABLE",
        string.format("'%s' targets hand cards, but there is no hand to target right now.", card_name))
    end
    return ActionResult.reject("INVALID_SELECTION",
      string.format("'%s' needs up to %d card(s) selected in hand — provide hand_indices (1-based positions), e.g. {1,2}.", card_name, needs_target))
  end

  return function()
    local source_area = area
    local pre_pack_choices = tonumber(G and G.GAME and G.GAME.pack_choices) or 0
    local explicit_failure
    local exec_cancelled = false
    local use_observed = false
    local original_raw_use = rawget(card, "use_consumeable")
    local original_use = card.use_consumeable
    local observed_use
    if type(original_use) == "function" then
      observed_use = function(self, ...)
        if self == card then use_observed = true end
        if rawget(card, "use_consumeable") == observed_use then
          card.use_consumeable = original_raw_use
        end
        return original_use(self, ...)
      end
      card.use_consumeable = observed_use
    end
    local applied_showcase
    local function show_pick(tag, shown_cost, levels)
      if data._action_id == nil then
        queue_pick_showcase(tag, shown_cost, levels)
      else
        applied_showcase = function() queue_pick_showcase(tag, shown_cost, levels) end
      end
    end
    local pre_levels = LevelDelta.snapshot(G and G.GAME and G.GAME.hands)
    local bp = CardUtil.pack_area() or area
    local is_pack_pick = from_pack
    local pack_pick_delay
    if is_pack_pick then
      GameActions.try_highlight(card, true)
      local NA_hover = anim()
      if NA_hover and NA_hover.hover_pack_card then
        pcall(function() NA_hover.hover_pack_card(card, bp) end)
      end

      local pack_pick_block = Utils.gate_seconds("pack_pick_block", "NEURO_PACK_PICK_BLOCK")
      pack_pick_delay = require("core.staging").lift_safe_delay(
        Utils.gate_seconds("pack_pick_block", "NEURO_PACK_PICK_DELAY"))
      Lifecycle.mark_action_at(Lifecycle.action_now() + pack_pick_block)

      local _, mh_sel = CardUtil.consumable_target_range(card)
      local needs_hand_sel = (not is_playing_card) and mh_sel and mh_sel > 0
      local captured_hand_cards = needs_hand_sel and prepared_hand_cards or nil

      if G.E_MANAGER and Event then
        local fn = G.FUNCS and G.FUNCS.use_card
        G.E_MANAGER:add_event(Event({
          trigger = "after",
          timer   = "TOTAL",
          delay   = pack_pick_delay,
          blocking = false,
          blockable = true,
          func    = function()
            if exec_cancelled then return true end
            if not fn then
              GameActions.try_highlight(card, false)
              explicit_failure = "use_card callback unavailable"
              return true
            end
            if captured_hand_cards and G.hand and G.hand.cards then
              clear_area_highlight(G.hand)
              for _, hcard in ipairs(captured_hand_cards) do
                if hcard then add_area_highlight(G.hand, hcard) end
              end
            end
            local NA = anim()
            if NA and NA.pick_pack_card then pcall(NA.pick_pack_card, card, bp) end
            local ok_pick, pick_result = pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox })
            if not ok_pick then
              if NA and NA.abort_pack_pick then pcall(NA.abort_pack_pick) end
              GameActions.try_highlight(card, false)
              explicit_failure = "use_card callback threw"
              return true
            end
            if pick_result == false then
              if NA and NA.abort_pack_pick then pcall(NA.abort_pack_pick) end
              GameActions.try_highlight(card, false)
              explicit_failure = "use_card callback declined"
              return true
            end
            if NA and NA.cancel_pending then pcall(NA.cancel_pending) end
            show_pick("booster_pick", 0)
            return true
          end,
        }))
      else
        local fn = G.FUNCS and G.FUNCS.use_card
        GameActions.try_highlight(card, false)
        if captured_hand_cards and G.hand and G.hand.cards then
          clear_area_highlight(G.hand)
          for _, hcard in ipairs(captured_hand_cards) do
            if hcard then add_area_highlight(G.hand, hcard) end
          end
        end
        local ok_pick, pick_result = false, nil
        if fn then ok_pick, pick_result = pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox }) end
        if not fn then
          explicit_failure = "use_card callback unavailable"
        elseif not ok_pick then
          explicit_failure = "use_card callback threw"
        elseif pick_result == false then
          explicit_failure = "use_card callback declined"
        else
          show_pick("booster_pick", 0)
        end
      end
    else
      if prepared_hand_cards and G.hand and G.hand.cards then
        clear_area_highlight(G.hand)
        for _, hcard in ipairs(prepared_hand_cards) do
          if hcard then add_area_highlight(G.hand, hcard) end
        end
      end
      local fn = G.FUNCS and G.FUNCS.use_card
      local used_ok = false
      local used_result
      if not fn then
        explicit_failure = "use_card callback unavailable"
      else
        used_ok, used_result = pcall(fn, { config = { ref_table = card }, UIBox = mock_UIBox })
        if not used_ok then
          explicit_failure = "use_card callback threw"
        elseif used_result == false then
          used_ok = false
          explicit_failure = "use_card callback declined"
        end
      end
      if used_ok then show_pick("use", 0, pre_levels) end
      if used_ok and hand_indices and G and G.NEURO then
        ForceHelpers.rearm()
      end
    end

    if data._action_id == nil then return "Used: " .. card_name end
    return ActionReceipt.create({
      id = tostring(data._action_id or ("use:" .. Utils.now())),
      name = data._action_name or "use_card",
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = ActionReceipt.now()
        + math.max(4, (pack_pick_delay or Utils.gate_seconds("pack_pick_block", "NEURO_PACK_PICK_DELAY")) + 1),
      timeout_outcome = "ambiguous",
      correction = "The accepted " .. (data._action_name or "use_card") .. " outcome could not be verified. Inspect the consumable, pack, hand, and resulting state before choosing again.",
      applied_message = "Used: " .. card_name,
      debug = { area = data.area, index = data.index, card = card_name, from_pack = from_pack },
      probe = function()
        if explicit_failure then return "failed", { reason = explicit_failure } end
        local remains = false
        for _, item in ipairs((source_area and source_area.cards) or {}) do
          if item == card then remains = true break end
        end
        local choices = tonumber(G and G.GAME and G.GAME.pack_choices) or 0
        if use_observed or not remains or (from_pack and choices < pre_pack_choices) then
          return "applied", {
            use_observed = use_observed,
            target_left_area = not remains,
            pack_choices_changed = from_pack and choices < pre_pack_choices,
          }
        end
        return "pending"
      end,
      on_applied = function() if applied_showcase then applied_showcase() end end,
      cleanup = function()
        exec_cancelled = true
        if rawget(card, "use_consumeable") == observed_use then card.use_consumeable = original_raw_use end
        GameActions.try_highlight(card, false)
      end,
    })
  end
end

return { handle_use_card = handle_use_card }
