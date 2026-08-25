local GameFacts = require("facts.game_facts")
local CardArea = require("facts.card_area_util")
local CardUtil = require("facts.card_util")
local GameActions = require("core.game_actions")
local Utils = require("util.utils")
local CtxHelpers = require("context.ctx_helpers")
local ActionResult = require("core.action_result")
local ActionReceipt = require("core.action_receipt")
local TransitionGuard = require("core.transition_guard")
local ConfirmationEvidence = require("core.confirmation_evidence")
local clear_area_highlight = GameActions.clear_area_highlight
local add_area_highlight = GameActions.add_area_highlight
local validate_hand_indices = CardArea.validate_hand_indices
local call_gfunc = GameActions.call_gfunc

local M = {}

M.DISCARD_POOL_RULE = "Discards are a separate pool that costs no hand-slot"

local function check_blind_size_rule(debuff, count)
  local err = CardArea.blind_size_rule_error(debuff, count, (require("facts.boss.legality").play_size_bounds()))
  if err then return nil, err end
  return true
end

local function play_signature(cards)
  local parts = {}
  for _, c in ipairs(cards or {}) do parts[#parts + 1] = tostring((c and c.sort_id) or "?") end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function play_content(cards)
  local parts = {}
  for _, c in ipairs(cards or {}) do
    local base = (c and c.base) or {}
    local center = c and c.config and c.config.center
    parts[#parts + 1] = table.concat({
      tostring((c and c.sort_id) or "?"), tostring(base.value or "?"),
      tostring(base.suit or "?"), tostring((center and center.key) or "?"),
    }, "/")
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function live_card_index(cards, target)
  for index, card in ipairs(cards or {}) do
    if card == target then return index end
  end
  return nil
end

local function at_most_one_ready_hand()
  if not (G and G.hand and G.hand.cards and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function") then
    return false
  end
  for _, c in ipairs(G.hand.cards) do
    if CardUtil.is_face_down(c) then return false end
  end
  local ok, ph = pcall(function()
    local _, _, p = G.FUNCS.get_poker_hand_info(G.hand.cards)
    return p
  end)
  if not ok or type(ph) ~= "table" then return false end
  local count = 0
  for name, set in pairs(ph) do
    if name ~= "top" and name ~= "High Card" and set and next(set) then
      count = count + 1
      if count > 1 then return false end
    end
  end
  return true
end

local function latch_matches(sig_field, serial_field, selected_cards, content_field)
  if not (G and G.NEURO) then return false end
  local review_serial = tonumber(G.NEURO[serial_field])
  local decision_serial = tonumber(G.NEURO.decision_serial) or 0
  if G.NEURO[sig_field] ~= play_signature(selected_cards) then return false end
  if review_serial ~= decision_serial then return false end
  local stored = content_field and G.NEURO[content_field]
  if stored ~= nil and stored ~= play_content(selected_cards) then return false end
  return true
end

local function weak_guard_spent()
  if not (G and G.NEURO) then return false end
  local spent = tonumber(G.NEURO.weak_fired_serial)
  return spent ~= nil and spent == (tonumber(G.NEURO.decision_serial) or 0)
end

local WEAK_HANDS = { ["High Card"] = true, ["Pair"] = true, ["Two Pair"] = true }

local function forced_play_now(hands_left, discards_left)
  return hands_left == 1 and discards_left == 0 and at_most_one_ready_hand()
end

local function armed_confirm_class()
  if not (G and G.NEURO) then return nil end
  local serial = tonumber(G.NEURO.decision_serial) or 0
  local legality = tonumber(G.NEURO.last_legality_review_serial) == serial
    and G.NEURO.last_legality_reject or nil
  local quality = tonumber(G.NEURO.last_quality_review_serial) == serial
    and G.NEURO.last_quality_reject or nil
  if legality and quality then return G.NEURO.last_confirm_armed end
  if legality then return "legality" end
  if quality then return "quality" end
  return nil
end

local function latch_commits(class, sig_field, serial_field, selected_cards, content_field)
  if armed_confirm_class() ~= class then return false end
  return latch_matches(sig_field, serial_field, selected_cards, content_field)
end

local function stronger_ready_types(handname)
  if not (G and G.hand and G.hand.cards and G.FUNCS
    and type(G.FUNCS.get_poker_hand_info) == "function") then return nil end
  for _, c in ipairs(G.hand.cards) do
    if CardUtil.is_face_down(c) then return nil end
  end
  local order = require("facts.hand_facts").HAND_ORDER
  local mine = order[handname]
  if not mine then return nil end
  local ok, ph = pcall(function()
    local _, _, p = G.FUNCS.get_poker_hand_info(G.hand.cards)
    return p
  end)
  if not ok or type(ph) ~= "table" then return nil end
  local out = {}
  for name, set in pairs(ph) do
    if name ~= "top" and set and next(set) and (order[name] or 0) > mine then
      out[#out + 1] = name
    end
  end
  if #out == 0 then return nil end
  table.sort(out, function(a, b) return (order[a] or 0) < (order[b] or 0) end)
  return out
end

local function weak_pause_text(indices, handname, level, chips, mult, hands_left, discards_left)
  local Legality = require("facts.boss.legality")
  local head = Legality.selection_line(indices, handname, level, chips, mult) .. "\n"
  if handname and WEAK_HANDS[handname] then
    local ready = stronger_ready_types(handname)
    local ready_note = ready and string.format(
      " These cards can also already form %s right now, with no discard: the Ready list above gives each one's cards.",
      table.concat(ready, ", ")) or ""
    if discards_left > 0 then
      return head .. string.format(
        "This is a bare %s -- one of the three lowest-ranking hand types.%s %s, and you have %d -- the odds above show the stronger hands you are one card away from. Choose one action now: Discard toward one first, or send your final play.",
        handname, ready_note, M.DISCARD_POOL_RULE, discards_left)
    end
    if ready_note ~= "" then
      return head .. string.format(
        "This is a bare %s -- one of the three lowest-ranking hand types.%s Send this same selection again to commit it, or send a different final selection. It commits if it passes the debuff and blind safety guards; there is no second weak/general confirmation.",
        handname, ready_note)
    end
    return head .. string.format(
      "This is a bare %s -- one of the three lowest-ranking hand types. Send this same selection again to commit it, or send a different final selection. It commits if it passes the debuff and blind safety guards; there is no second weak/general confirmation.",
      handname)
  end
  local mask_note = handname == Legality.MASK_HAND and (Legality.MASK_NOTE .. "\n") or ""
  return head .. mask_note .. Legality.spend_line(hands_left, discards_left) .. "\n"
    .. "Resend the same indices to play."
end

local function play_confirm_reject(selected_cards, indices)
  if G and G.NEURO and G.NEURO.selftest_active then return nil end
  if latch_commits("legality", "last_legality_reject", "last_legality_review_serial", selected_cards,
    "last_legality_content") then
    return nil
  end
  local ok_l, Legality = pcall(require, "facts.boss.legality")
  if ok_l and Legality and Legality.play_verdict then
    local ok_v, verdict = pcall(Legality.play_verdict, selected_cards, indices)
    if ok_v and type(verdict) == "string" and verdict ~= "" then
      return verdict, "legality"
    end
  end

  if not weak_guard_spent() then
    local hands_left = GameFacts.hands_left()
    local discards_left = GameFacts.discards_left()
    if hands_left > 0 then
      local LegalityWeak = require("facts.boss.legality")
      local handname, level, chips, mult
      local hidden = LegalityWeak.selection_hidden(selected_cards)
      if hidden then
        handname, level, chips, mult =
          LegalityWeak.MASK_HAND, LegalityWeak.MASK_FIELD, LegalityWeak.MASK_FIELD, LegalityWeak.MASK_FIELD
      end
      if not hidden and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
        local ok_i, text = pcall(G.FUNCS.get_poker_hand_info, selected_cards)
        if ok_i and type(text) == "string" and text ~= "" then handname = text end
      end
      local hd = not hidden and handname and G.GAME and G.GAME.hands and G.GAME.hands[handname]
      if type(hd) == "table" then
        level, chips, mult = hd.level, hd.chips, hd.mult
        local ok_d, DebuffFacts = pcall(require, "facts.debuff_facts")
        if ok_d and DebuffFacts.flint_active() then
          chips, mult = DebuffFacts.flint_halve(chips, mult)
        end
      end
      local weak_final = discards_left <= 0 and handname ~= nil and WEAK_HANDS[handname] ~= nil
        and forced_play_now(hands_left, discards_left)
      if discards_left > 0 or weak_final then
        return weak_pause_text(indices, handname, level, chips, mult, hands_left, discards_left), "weak"
      end
    end
  end

  if not latch_commits("quality", "last_quality_reject", "last_quality_review_serial", selected_cards,
    "last_quality_content")
    and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
    local hands_left = GameFacts.hands_left()
    local discards_left = GameFacts.discards_left()
    if not forced_play_now(hands_left, discards_left) then
      local LegalityQuality = require("facts.boss.legality")
      local hidden = LegalityQuality.selection_hidden(selected_cards)
      local ht = "this hand"
      if not hidden then
        local ok_i, text = pcall(G.FUNCS.get_poker_hand_info, selected_cards)
        ht = (ok_i and type(text) == "string" and text) or ht
      end
      local res = string.format("%d hand(s) and %d discard(s) left", hands_left, discards_left)
      local ok_rem, remaining = pcall(function() return require("facts.economy_facts").blind_remaining() end)
      if ok_rem and type(remaining) == "number" then res = string.format("%d to clear, ", remaining) .. res end
      local fit = ""
      local ok_s, Scoring = pcall(require, "util.scoring")
      if ok_s and Scoring and Scoring.joker_summary then
        local jsum = Scoring.joker_summary(not hidden and selected_cards or nil)
        local parts = {}
        local b = jsum and jsum.ledger and jsum.ledger.by_type[ht]
        if b then
          if (b.mult or 0) ~= 0 then parts[#parts + 1] = string.format("%+d Mult", b.mult) end
          if (b.chips or 0) ~= 0 then parts[#parts + 1] = string.format("%+d Chips", b.chips) end
          if (b.xmult or 1) ~= 1 then parts[#parts + 1] = "x" .. tostring(b.xmult) .. " Mult" end
        end
        local led = jsum and jsum.ledger
        local sources_note = ""
        if led then
          for _, kind in ipairs({ "xmult", "xchips", "mult", "chips" }) do
            local q = led.gated[kind]
            if q and not Scoring.Q.is_identity(kind, q) then
              local clause = CtxHelpers.quantity_clause(kind, q)
              if clause then parts[#parts + 1] = clause end
            end
          end
          local srcs = CtxHelpers.ledger_gated_sources(led)
          if #srcs > 0 then sources_note = " (" .. table.concat(srcs, "; ") .. ")" end
        end
        if #parts > 0 then
          fit = string.format(" Your jokers add %s to %s%s.", table.concat(parts, ", "), ht, sources_note)
        end
      end
      local weak_note = ""
      if discards_left <= 0 and hands_left > 1 and WEAK_HANDS[ht] then
        weak_note = string.format(
          " %s is one of the three lowest-ranking hand types and you have no discards left to improve it: spending a hand here only pays off if your %d remaining hand(s) can still cover the rest.",
          ht, hands_left)
      end
      local mask_note = hidden and (" " .. Legality.MASK_NOTE) or ""
      return string.format(
        "Committing %s -- %s.%s%s%s Send the same indices again to commit this play. Any other selection gets its own confirmation first.",
        ht, res, fit, weak_note, mask_note), "confirm"
    end
  end
  return nil
end

local function commit_hand(data, action)
  local function execution_failure(message)
    if data._action_id ~= nil then return ActionReceipt.outcome("failed", message) end
    return message
  end
  if not G.hand or not G.hand.cards then
    return ActionResult.reject("TARGET_UNAVAILABLE",
      "Hand is not available yet. Wait for the hand screen, then select cards.")
  end
  if G.play and G.play.cards and #G.play.cards > 0 then
    local forced = require("core.force_state").is_forced_action(action == "play" and "play_hand" or "discard_hand")
    return ActionResult.reject(forced and "TRANSITION_ACKNOWLEDGED" or "TRANSITION_PENDING",
      "A hand is still resolving, so nothing was applied. Wait a moment, then choose again.")
  end
  local indices, ierr = validate_hand_indices(data.indices, #G.hand.cards)
  if not indices then
    return ActionResult.reject("INVALID_SELECTION", ierr)
  end
  local target_cards = {}
  for i = 1, #indices do target_cards[i] = G.hand.cards[indices[i]] end

  do
    local ok_df, DF = pcall(require, "facts.debuff_facts")
    local fi = ok_df and DF and DF.forced_selection_index and DF.forced_selection_index()
    if fi then
      local included = false
      for _, ix in ipairs(indices) do if ix == fi then included = true break end end
      if not included then
        return ActionResult.reject("INVALID_SELECTION",
          string.format("BOSS (Cerulean Bell): card %d is +LOCK (force-selected) -- the engine keeps it highlighted, so it resolves with every play and every discard whether or not you list it. This selection omits index %d, which would not be the hand you asked for. Add index %d to your selection.", fi, fi, fi))
      end
    end
  end

  local sp = G.GAME and G.GAME.starting_params or nil

  if action == "discard" then
    local discards_left = GameFacts.discards_left()
    if discards_left <= 0 then
      return ActionResult.reject("ACTION_UNAVAILABLE", "No discards remaining. Use play_hand instead.")
    end
    local dl = sp and tonumber(sp.discard_limit)
    if dl and #indices > math.max(dl, 0) then
      return ActionResult.reject("INVALID_SELECTION",
        string.format("You can discard at most %d card(s) right now (selected %d).", math.max(dl, 0), #indices))
    end

  elseif action == "play" then
    local hands_left = GameFacts.hands_left()
    if hands_left <= 0 then
      return ActionResult.reject("ACTION_UNAVAILABLE", "No hands remaining. You cannot play cards right now.")
    end

    local blind = G.GAME and G.GAME.blind or nil
    if blind and blind.block_play then
      local forced = require("core.force_state").is_forced_action("play_hand")
      return ActionResult.reject(forced and "TRANSITION_ACKNOWLEDGED" or "TRANSITION_PENDING",
        "The boss banner just fired and is still resolving on screen, so nothing was applied. " .. TransitionGuard.BUSY_TAIL)
    end
    local pl = sp and tonumber(sp.play_limit)
    if pl and #indices > math.max(pl, 1) then
      return ActionResult.reject("INVALID_SELECTION",
        string.format("You can play at most %d card(s) right now (selected %d).", math.max(pl, 1), #indices))
    end

    local debuff = blind and not blind.disabled and blind.debuff or nil
    local ok_sz, err_sz = check_blind_size_rule(debuff, #target_cards)
    if not ok_sz then return ActionResult.reject("INVALID_SELECTION", err_sz) end

    local reason, class = play_confirm_reject(target_cards, indices)
    if reason then
      local candidate
      if G.NEURO then
        local sig = play_signature(target_cards)
        local serial = tonumber(G.NEURO.decision_serial) or 0
        if class == "legality" then
          G.NEURO.last_legality_reject = sig
          G.NEURO.last_legality_review_serial = serial
          G.NEURO.last_legality_content = play_content(target_cards)
          G.NEURO.last_confirm_armed = "legality"
        else
          G.NEURO.last_quality_reject = sig
          G.NEURO.last_quality_review_serial = serial
          G.NEURO.last_quality_content = play_content(target_cards)
          G.NEURO.last_confirm_armed = "quality"
          if class == "weak" then G.NEURO.weak_fired_serial = serial end
        end
        local visible = true
        for _, card in ipairs(target_cards) do
          if CardUtil.is_face_down(card) then visible = false break end
        end
        local hand_type
        if visible and G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
          local ok_h, text = pcall(G.FUNCS.get_poker_hand_info, target_cards)
          if ok_h and type(text) == "string" and text ~= "" then hand_type = text end
        end
        local evidence_class = class == "legality" and "legality" or "quality"
        candidate = ConfirmationEvidence.candidate(evidence_class, sig, play_content(target_cards),
          indices, hand_type)
      end
      return ActionResult.reject("CONFIRMATION_REQUIRED", reason, {
        boss_verdict = class == "legality" or nil,
        confirmation_candidate = candidate,
      })
    end

    if G.NEURO then
      G.NEURO.last_legality_reject = nil
      G.NEURO.last_legality_review_serial = nil
      G.NEURO.last_legality_content = nil
      G.NEURO.last_quality_reject = nil
      G.NEURO.last_quality_review_serial = nil
      G.NEURO.last_quality_content = nil
      G.NEURO.last_confirm_armed = nil
      ConfirmationEvidence.clear()
    end
  end

  return function()
    local pre_hands = GameFacts.hands_left()
    local pre_discards = GameFacts.discards_left()
    local pre_discards_used = tonumber(G and G.GAME and G.GAME.current_round
      and G.GAME.current_round.discards_used) or 0
    local live_targets = {}
    local missing_indices = {}
    for i = 1, #target_cards do
      local live_index = live_card_index(G.hand.cards, target_cards[i])
      if live_index then
        live_targets[i] = target_cards[i]
      else
        missing_indices[#missing_indices + 1] = tostring(indices[i])
      end
    end
    if #missing_indices > 0 then
      clear_area_highlight(G.hand)
      return execution_failure("Could not " .. action .. ": selected card(s) at requested index "
        .. table.concat(missing_indices, ", ") .. " are no longer in the hand; nothing was applied.")
    end

    clear_area_highlight(G.hand)
    local selected_cards = {}
    local refused_cards = {}
    for i = 1, #live_targets do
      local card = live_targets[i]
      local requested_index = indices[i]
      local _, live = add_area_highlight(G.hand, card)
      local card_name = CardUtil.is_face_down(card) and "face-down (hidden)" or Utils.playing_card_label(card)
      if live == false then
        table.insert(refused_cards, requested_index .. ":" .. card_name)
      else
        table.insert(selected_cards, requested_index .. ":" .. card_name)
      end
    end

    if #selected_cards == 0 then
      return execution_failure("Cleared selection (no valid indices)")
    end

    local msg = "Selected cards: " .. table.concat(selected_cards, ", ")
    if #refused_cards > 0 then
      msg = msg .. ". The game refused " .. table.concat(refused_cards, ", ")
        .. " -- the hand selection limit is " .. tostring(CardUtil.highlight_limit()) .. "."
    end

    local play_record
    if action == "play" then
      if #G.hand.highlighted == 0 then
        return execution_failure(msg .. ". No valid cards to play.")
      end
      if G.NEURO then
        local ht, scored
        if G.FUNCS and type(G.FUNCS.get_poker_hand_info) == "function" then
          local ok, text, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, G.hand.highlighted)
          if ok then
            ht = (type(text) == "string" and text ~= "" and text)
              or (type(text) == "table" and text.type) or nil
            if type(scoring_hand) == "table" then
              scored = #scoring_hand
              local ok_d, DF = pcall(require, "facts.debuff_facts")
              if ok_d and DF and DF.count then scored = math.max(0, scored - DF.count(scoring_hand)) end
            end
          end
        end
        play_record = {
          kind = "play", hand_type = ht, played = #G.hand.highlighted, scored = scored,
          pre_chips = (G.GAME and G.GAME.chips) or 0, hands_left_after = pre_hands - 1,
          action_id = data._action_id and tostring(data._action_id) or nil,
          run_generation = tonumber(G.NEURO.run_generation) or 0,
          ante = GameFacts.ante(0),
          round = GameFacts.round() or 0,
          blind_key = tostring(G.GAME and G.GAME.blind and G.GAME.blind.config
            and G.GAME.blind.config.blind and G.GAME.blind.config.blind.key
            or G.GAME and G.GAME.blind and G.GAME.blind.name or "unknown blind"),
          hand_level = math.max(1, math.floor(tonumber(ht and G.GAME and G.GAME.hands
            and G.GAME.hands[ht] and G.GAME.hands[ht].level) or 1)),
        }
      end
      if not call_gfunc("play_cards_from_highlighted") then
        clear_area_highlight(G.hand)
        local failure = msg .. ". Could not play: the play action is unavailable right now."
        if data._action_id == nil then
          if G and G.NEURO then G.NEURO.last_play = play_record end
          return failure
        end
        return ActionReceipt.outcome("failed", failure)
      end
      local hands_left = GameFacts.hands_left()
      msg = msg .. string.format(". Playing hand! Hands remaining: %d", hands_left - 1)
    else
      if #G.hand.highlighted == 0 then
        return msg .. ". No valid cards to discard."
      end
      local discards_left = GameFacts.discards_left()
      if discards_left <= 0 then
        clear_area_highlight(G.hand)
        return execution_failure(msg .. ". Cannot discard: no discards remaining. Use play_hand instead.")
      end
      if G.NEURO then
        play_record = {
          kind = "discard",
          played = #G.hand.highlighted,
          discards_left_after = math.max(0, discards_left - 1),
        }
      end
      if not call_gfunc("discard_cards_from_highlighted") then
        clear_area_highlight(G.hand)
        local failure = msg .. ". Could not discard: the discard action is unavailable right now."
        if data._action_id == nil then
          if G and G.NEURO then G.NEURO.last_play = play_record end
          return failure
        end
        return ActionReceipt.outcome("failed", failure)
      end
      msg = msg .. string.format(". Discarding! Discards remaining: %d", discards_left - 1)
    end

    if data._action_id == nil then
      if G and G.NEURO then G.NEURO.last_play = play_record end
      return msg
    end
    return ActionReceipt.create({
      id = tostring(data._action_id or (action .. ":" .. Utils.now())),
      name = action == "play" and "play_hand" or "discard_hand",
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = ActionReceipt.now() + 4,
      timeout_outcome = "failed",
      correction = "The accepted " .. action .. " did not move the prepared cards or consume its counter. Inspect the hand and choose again.",
      applied_message = msg,
      debug = { indices = indices, target_count = #target_cards },
      probe = function()
        local left = 0
        for _, target in ipairs(target_cards) do
          if not live_card_index(G and G.hand and G.hand.cards, target) then left = left + 1 end
        end
        local counter_changed = action == "play"
          and GameFacts.hands_left() < pre_hands
          or action == "discard" and GameFacts.discards_left() < pre_discards
        local used_changed = action == "discard"
          and (tonumber(G and G.GAME and G.GAME.current_round
            and G.GAME.current_round.discards_used) or 0) > pre_discards_used
        local in_play = 0
        if action == "play" then
          for _, target in ipairs(target_cards) do
            if live_card_index(G and G.play and G.play.cards, target) then in_play = in_play + 1 end
          end
        end
        if left == #target_cards and (counter_changed or used_changed or in_play == #target_cards) then
          return "applied", { targets_left_hand = left, counter_changed = counter_changed }
        end
        return "pending"
      end,
      on_applied = function() if G and G.NEURO then G.NEURO.last_play = play_record end end,
      cleanup = function() if G and G.hand then clear_area_highlight(G.hand) end end,
    })
  end
end

local function handle_play_hand(data)
  return commit_hand(data, "play")
end

local function handle_discard_hand(data)
  return commit_hand(data, "discard")
end

function M.pending_confirm_indices()
  if not (G and G.NEURO and G.hand and G.hand.cards) then return nil end
  local class = armed_confirm_class()
  local sig = (class == "legality" and G.NEURO.last_legality_reject)
    or (class == "quality" and G.NEURO.last_quality_reject) or nil
  if type(sig) ~= "string" or sig == "" then return nil end
  local wanted, want_count = {}, 0
  for id in sig:gmatch("[^,]+") do
    if not wanted[id] then want_count = want_count + 1 end
    wanted[id] = true
  end
  local indices = {}
  for index, card in ipairs(G.hand.cards) do
    if wanted[tostring(card and card.sort_id)] then indices[#indices + 1] = index end
  end
  if #indices < want_count then return nil end
  return indices
end

M.handle_play_hand = handle_play_hand
M.handle_discard_hand = handle_discard_hand
M.play_confirm_reject = play_confirm_reject
if _G.NEURO_TEST then
  M.play_signature = play_signature
  M.play_content = play_content
  M.weak_pause_text = weak_pause_text
end

return M
