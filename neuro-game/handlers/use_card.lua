local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local CardUtil = require("facts.card_util")
local function anim() return Utils.lazy_require("render.neuro-anim") end
local Showcase = require("hud.showcase")
local ActionResult = require("core.action_result")
local LevelDelta = require("util.level_delta")
local HandHandlers = require("handlers.hand_handlers")
local validate_hand_indices = CardArea.validate_hand_indices
local clear_area_highlight = GameActions.clear_area_highlight
local mock_UIBox = GameActions.mock_UIBox
local can_take_pack_card = CardUtil.can_take_pack_card

local function canonical_action(area, directional)
  local from_pack = area == "booster_pack"
  if directional then
    return from_pack and "choose_directional_pack_card" or "use_directional_consumable"
  end
  return from_pack and "choose_pack_card" or "use_consumable"
end

local function trusted_action_name(data)
  local name = type(data) == "table" and data._action_name
  if name == "use_consumable" or name == "choose_pack_card"
      or name == "use_directional_consumable"
      or name == "choose_directional_pack_card" then
    return name
  end
  return canonical_action(data and data.area, false)
end

local function is_directional_action(name)
  return name == "use_directional_consumable" or name == "choose_directional_pack_card"
end

local function unusable_reason(card, card_name, hand_indices, targets)
  local minimum, maximum
  if not CardUtil.is_hidden(card) then minimum, maximum = CardUtil.consumable_target_range(card) end
  if hand_indices and maximum then
    return string.format(
      "'%s' can't be used with hand card(s) %s selected: the game refuses that target selection, so nothing was used. It takes %d-%d card(s) its effect can apply to.",
      card_name, table.concat(hand_indices, ", "), minimum or 1, maximum)
  end
  return string.format("'%s' can't be used right now: %s.", card_name,
    GameActions.consumable_refusal(card, targets) or "the game refuses it")
end

local OUTCOME_SETTLE_MAX = 3

local PublicCard = require("facts.public_card_identity")

local function hand_card_text(card)
  return require("core.destruction_log").card_label(card)
end

local function card_traits(c)
  local enh = CardUtil.enhancement_key(c)
  return {
    base = Utils.playing_card_label(c),
    enhancement = enh and CardUtil.enhancement_name(enh) or nil,
    seal = type(c.seal) == "string" and require("facts.display_names").seal(c.seal) or nil,
    edition = CardUtil.edition_name(c.edition),
  }
end

local function article(name) return (name:match("^[AEIOUaeiou]") and "an " or "a ") .. name end

local function trait_changes(was, now)
  local out = {}
  if now.base ~= was.base then out[#out + 1] = "became " .. now.base end
  for _, key in ipairs({ "enhancement", "seal" }) do
    local a, b = was[key], now[key]
    if a ~= b then
      out[#out + 1] = (not a and ("gained " .. article(b))) or (not b and ("lost its " .. a))
        or ("had its " .. a .. " replaced by " .. article(b))
    end
  end
  if now.edition ~= was.edition then
    out[#out + 1] = now.edition and ("became " .. now.edition) or ("lost its " .. was.edition .. " edition")
  end
  return out
end

local function outcome_snapshot()
  local snap = { jokers = {}, joker_order = {}, consumables = {}, hand = {}, hand_order = {} }
  for i, c in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    if PublicCard.is_public(c) then
      snap.joker_order[#snap.joker_order + 1] = c
      snap.jokers[c] = { name = PublicCard.label(c, "jokers", i), edition = CardUtil.edition_name(c.edition) }
    end
  end
  for i, c in ipairs((G and G.consumeables and G.consumeables.cards) or {}) do
    if PublicCard.is_public(c) then snap.consumables[c] = PublicCard.label(c, "consumables", i) end
  end
  snap.traits = {}
  for _, c in ipairs((G and G.hand and G.hand.cards) or {}) do
    snap.hand_order[#snap.hand_order + 1] = c
    snap.hand[c] = PublicCard.is_public(c) and hand_card_text(c) or false
    if snap.hand[c] then snap.traits[c] = card_traits(c) end
  end
  snap.dollars = tonumber(G and G.GAME and G.GAME.dollars)
  snap.hand_size = tonumber(G and G.hand and G.hand.config and G.hand.config.card_limit)
  snap.levels = LevelDelta.snapshot(G and G.GAME and G.GAME.hands)
  return snap
end

local function outcome_changes(before)
  local after = outcome_snapshot()
  local parts = {}
  for _, c in ipairs(before.joker_order) do
    local was, now = before.jokers[c], after.jokers[c]
    if now and now.edition ~= was.edition then
      parts[#parts + 1] = was.name .. " became " .. (now.edition or "base edition")
    elseif not now and c.area ~= (G and G.jokers) then
      parts[#parts + 1] = was.name .. " was destroyed"
    end
  end
  for _, c in ipairs(after.joker_order) do
    if not before.jokers[c] then
      parts[#parts + 1] = "gained joker " .. after.jokers[c].name
        .. (after.jokers[c].edition and (" (" .. after.jokers[c].edition .. ")") or "")
    end
  end
  for c, name in pairs(after.consumables) do
    if not before.consumables[c] then parts[#parts + 1] = "gained " .. name end
  end
  local now_seat = {}
  for i, c in ipairs((G and G.hand and G.hand.cards) or {}) do now_seat[c] = i end
  local piles = { [G and G.deck or false] = "deck", [G and G.discard or false] = "discard pile" }
  for seat, c in ipairs(before.hand_order) do
    local was, now = before.hand[c], after.hand[c]
    if now == nil then
      local pile = c.area and piles[c.area]
      if was and not pile then
        parts[#parts + 1] = was .. " left your hand"
      elseif was and CardUtil.is_aggregate_public(c) then
        local changed = trait_changes(before.traits[c], card_traits(c))
        if #changed > 0 then
          parts[#parts + 1] = was .. " " .. table.concat(changed, " and ") .. ", then went back into your " .. pile
        end
      end
    elseif was and now and was ~= now then
      -- A closing pack returns hand cards to the deck one by one, shifting later positions.
      parts[#parts + 1] = "hand card " .. tostring(seat) .. " " .. was .. " became " .. now
    end
  end
  for _, c in ipairs(after.hand_order) do
    if before.hand[c] == nil then
      parts[#parts + 1] = "hand card " .. tostring(now_seat[c]) .. " added: " .. (after.hand[c] or "face-down card")
    end
  end
  if before.dollars and after.dollars and before.dollars ~= after.dollars then
    parts[#parts + 1] = "money " .. Utils.money_change(after.dollars - before.dollars)
      .. " (now " .. Utils.money(after.dollars) .. ")"
  end
  if before.hand_size and after.hand_size and before.hand_size ~= after.hand_size then
    parts[#parts + 1] = string.format("hand size %d -> %d", before.hand_size, after.hand_size)
  end
  local lv = LevelDelta.brief(G and G.GAME and G.GAME.hands, before.levels)
  if lv then parts[#parts + 1] = lv end
  return parts
end

local function outcome_suffix(before, unsettled)
  local parts = outcome_changes(before)
  if #parts > 0 then return " -- " .. table.concat(parts, "; ") end
  return unsettled and " -- nothing visible had changed yet when this was reported" or " -- no visible change"
end

local function use_resolved(closes_pack)
  local began = false
  local function resolved()
    if not began or not G or G.TAROT_INTERRUPT ~= nil then return false end
    local locks = G.CONTROLLER and G.CONTROLLER.locks
    if locks and locks.use then return false end
    return not (closes_pack and G.GAME and G.GAME.PACK_INTERRUPT ~= nil)
  end
  local function mark_begun() began = G ~= nil and G.TAROT_INTERRUPT ~= nil end
  return resolved, mark_begun
end

local function outcome_settler(resolved)
  local used_at
  local settler = {}
  function settler.done()
    local now = ActionResult.now()
    used_at = used_at or now
    settler.unsettled = not (Utils.engine_settled() or (resolved and resolved()))
    return not settler.unsettled or now - used_at >= OUTCOME_SETTLE_MAX
  end
  return settler
end

local function selection_failure(card, card_name, targets)
  if targets then
    if not (G and G.hand and G.hand.cards) then return "the hand is no longer available" end
    if not GameActions.highlight_exactly(G.hand, targets) then
      clear_area_highlight(G.hand)
      return "the game did not select exactly the requested hand cards for " .. card_name
    end
  end
  local refusal = GameActions.consumable_refusal(card, nil, true)
  if refusal then
    if targets then clear_area_highlight(G.hand) end
    return "the game refuses " .. card_name .. (targets and " on the selected hand cards" or "") .. " (" .. refusal .. ")"
  end
  return nil
end

local function pack_refusal(code, card, card_name, data, why)
  Showcase.enqueue_refusal({ code = code, card = card, name = card_name, action_id = data._action_id })
  return ActionResult.reject(code,
    string.format("Cannot pick '%s': %s. Pick another card or skip the pack.", card_name, why))
end

local function face_down_blocked(card, from_pack, max_targets)
  return require("facts.target_contracts").get(card) ~= nil or (max_targets or 0) > 0
    or (from_pack and not can_take_pack_card(card))
    or (not from_pack and not GameActions.consumable_usable(card))
end

local function face_down_refusal(card, card_name, data, from_pack)
  local why = require("facts.use_gate").reason(card).text
  if from_pack then return pack_refusal("PRECONDITION_FAILED", card, card_name, data, why) end
  return ActionResult.reject("PRECONDITION_FAILED",
    string.format("'%s' can't be used: %s. Use another card or choose another action.", card_name, why))
end

local function handle_use_card(data)
  local action_name = trusted_action_name(data)
  local area, card, index, code, err = CardArea.resolve_target(data, CardArea.TARGET_RULES[action_name])
  if not card then return ActionResult.reject(code, err) end
  data.index = index
  local face_down = CardUtil.is_hidden(card)
  local card_name = face_down and "face-down card" or Utils.real_name_or(card)
  local min_targets, max_targets = CardUtil.consumable_target_range(card)
  local from_pack = area == CardUtil.pack_area()
  if face_down and face_down_blocked(card, from_pack, max_targets) then
    return face_down_refusal(card, card_name, data, from_pack)
  end
  if require("facts.target_contracts").get(card) and not is_directional_action(action_name) then
    return ActionResult.reject("INVALID_SELECTION",
      "This card has directional targets; use " .. canonical_action(data.area, true)
        .. " so source and destination are explicit.")
  end

  local function queue_pick_showcase(tag, shown_cost, levels)
    Showcase.enqueue_purchase({
      card = (not face_down) and card or nil,
      name = card_name,
      cost = tonumber(shown_cost) or 0,
      area = tostring(tag or "pick"),
      levels = levels,
      at = Utils.now(),
    })
    pcall(require("core.rewards").announce_rare_joker, card)
    if G and G.jokers and card.area == G.jokers then
      require("facts.fact_hints").note_joker_gained()
    end
  end

  local is_playing_card = Utils.is_playing_card(card)
  if from_pack and not can_take_pack_card(card) then
    if CardUtil.is_consumable_card(card) then
      local why = require("facts.use_gate").reason(card)
      return pack_refusal(why.kind == "slot" and "NO_SLOT" or "PRECONDITION_FAILED", card, card_name, data, why.text)
    else
      Showcase.enqueue_refusal({ code = "NO_SLOT", card = card, name = card_name,
        action_id = data._action_id })
      return ActionResult.reject("NO_SLOT",
        string.format("Cannot pick '%s': joker slots are full. Skip the pack or sell a joker first.", card_name))
    end
  end

  local hand_indices = nil
  local prepared_hand_cards = nil
  if not is_playing_card and max_targets and max_targets > 0 then
    if not (G.hand and G.hand.cards and #G.hand.cards > 0) then
      return ActionResult.reject("TARGET_UNAVAILABLE",
        string.format("'%s' targets hand cards, but there is no hand to target right now.", card_name))
    end
    if type(data.hand_indices) ~= "table" or #data.hand_indices == 0 then
      return ActionResult.reject("INVALID_SELECTION",
        string.format("'%s' needs up to %d card(s) selected in hand — provide hand_indices (1-based positions), e.g. {\"hand_indices\":[1,2]}.", card_name, max_targets))
    end
    local verr
    hand_indices, verr = validate_hand_indices(data.hand_indices, #G.hand.cards, max_targets)
    if not hand_indices then
      return ActionResult.reject("INVALID_SELECTION", verr)
    end
    if #hand_indices < min_targets then
      return ActionResult.reject("INVALID_SELECTION",
        string.format("Too few cards: '%s' needs at least %d selected, you provided %d.", card_name, min_targets, #hand_indices))
    end
    prepared_hand_cards = {}
    for i = 1, #hand_indices do prepared_hand_cards[i] = G.hand.cards[hand_indices[i]] end
  end

  -- Candidate probes use stand-in targets; judge selection only for a real request.
  local probing = G and G.NEURO and G.NEURO._candidate_probe
  local lock_index = prepared_hand_cards and not probing and HandHandlers.omitted_forced_index(hand_indices)
  if lock_index then
    return ActionResult.reject("INVALID_SELECTION", string.format(
      "BOSS (Cerulean Bell): hand card %d is +LOCK (force-selected) -- the engine keeps it selected, so '%s' would target it too. Add index %d to hand_indices.",
      lock_index, card_name, lock_index))
  end
  if (area == (G and G.consumeables) or from_pack) and not (prepared_hand_cards and probing)
      and not GameActions.consumable_usable(card, prepared_hand_cards) then
    return ActionResult.reject("PRECONDITION_FAILED",
      unusable_reason(card, card_name, hand_indices, prepared_hand_cards))
  end

  local function source_card_is_live()
    local live_area = CardArea.get_area(data.area)
    return live_area == area and Utils.index_in(live_area and live_area.cards, card) ~= nil
  end

  return function()
    if not source_card_is_live() then
      local message = string.format(
        "Could not use %s: the selected card changed before use ran.", card_name)
      return ActionResult.outcome("failed", message)
    end
    local source_area = area
    local pre_pack_choices = tonumber(G and G.GAME and G.GAME.pack_choices) or 0
    local explicit_failure
    local exec_cancelled = false
    local use_watch = GameActions.observe_use(card)
    local before_use
    local use_done, mark_use_begun = use_resolved(from_pack and pre_pack_choices <= 1)
    local settler = outcome_settler(use_done)
    local applied_showcase
    local function show_pick(tag, shown_cost, levels)
      applied_showcase = function() queue_pick_showcase(tag, shown_cost, levels) end
    end
    local function invoke_use()
      before_use = outcome_snapshot()
      local ok, result = pcall(G.FUNCS.use_card, { config = { ref_table = card }, UIBox = mock_UIBox })
      mark_use_begun()
      if not ok then return "use_card callback threw" end
      if result == false then return "use_card callback declined" end
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
      require("core.window").hold_after_action(pack_pick_block)

      local needs_hand_sel = (not is_playing_card) and max_targets and max_targets > 0
      local captured_hand_cards = needs_hand_sel and prepared_hand_cards or nil
      -- Restore the prepared hand selection because the card callback reads it.
      local function restore_hand_selection()
        return selection_failure(card, card_name, captured_hand_cards)
      end

      G.E_MANAGER:add_event(Event({
        trigger = "after",
        timer   = "TOTAL",
        delay   = pack_pick_delay,
        blocking = false,
        blockable = true,
        func    = function()
          if exec_cancelled then return true end
          local NA
          local function fail(cause)
            if NA and NA.abort_pack_pick then pcall(NA.abort_pack_pick) end
            GameActions.try_highlight(card, false)
            explicit_failure = cause
            return true
          end
          if not source_card_is_live() then return fail("selected card changed before use") end

          local refused = restore_hand_selection()
          if refused then return fail(refused) end
          NA = anim()
          if NA and NA.pick_pack_card then pcall(NA.pick_pack_card, card, bp) end
          local cause = invoke_use()
          if cause then return fail(cause) end
          if NA and NA.cancel_pending then pcall(NA.cancel_pending) end
          show_pick("booster_pick", 0)
          return true
        end,
      }))
    else
      local refused = selection_failure(card, card_name, prepared_hand_cards)
      if refused then
        return ActionResult.outcome("failed", "Could not use " .. card_name .. ": " .. refused
          .. "; nothing was used. Inspect your hand and choose again.")
      end
      explicit_failure = invoke_use()
      if not explicit_failure then show_pick("use", 0, pre_levels) end
    end

    local receipt
    receipt = ActionResult.create({
      id = tostring(data._action_id),
      name = action_name,
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = ActionResult.now() + OUTCOME_SETTLE_MAX
        + math.max(4, (pack_pick_delay or Utils.gate_seconds("pack_pick_block", "NEURO_PACK_PICK_DELAY")) + 1),
      timeout_outcome = "ambiguous",
      debug = { area = data.area, index = data.index, card = card_name, from_pack = from_pack },
      probe = function()
        if explicit_failure then return "failed", { cause = explicit_failure } end
        local remains = Utils.index_in(source_area and source_area.cards, card) ~= nil
        local choices = tonumber(G and G.GAME and G.GAME.pack_choices) or 0
        if use_watch.used or not remains or (from_pack and choices < pre_pack_choices) then
          if use_watch.used and not face_down and not settler.done() then return "pending" end
          return "applied", {
            use_observed = use_watch.used,
            target_left_area = not remains,
            pack_choices_changed = from_pack and choices < pre_pack_choices,
          }
        end
        return "pending"
      end,
      on_applied = function()
        -- Report only the effect of a use; never describe a face-down card.
        if use_watch.used then
          receipt.applied_message = "Used: " .. card_name
            .. ((not face_down and before_use) and outcome_suffix(before_use, settler.unsettled) or "")
        end
        if applied_showcase then applied_showcase() end
      end,
      cleanup = function()
        exec_cancelled = true
        use_watch.restore()
        GameActions.try_highlight(card, false)
      end,
    })
    return receipt
  end
end

return { handle_use_card = handle_use_card, canonical_action = canonical_action, outcome_snapshot = outcome_snapshot, outcome_suffix = outcome_suffix,
  outcome_settler = outcome_settler, OUTCOME_SETTLE_MAX = OUTCOME_SETTLE_MAX }
