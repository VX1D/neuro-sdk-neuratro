local GameFacts = require("facts.game_facts")
local CardArea = require("facts.card_area_util")
local CardUtil = require("facts.card_util")
local GameActions = require("core.game_actions")
local Utils = require("util.utils")
local CtxHelpers = require("context.ctx_helpers")
local ActionResult = require("core.action_result")
local Metrics = require("util.metrics")
local Gate = require("core.gate")
local HandFacts = require("facts.hand_facts")
local Legality = require("facts.boss.legality")
local DebuffFacts = require("facts.debuff_facts")
local Scoring = require("util.scoring")
local PublicCard = require("facts.public_card_identity")
local NumericEffects = require("facts.numeric_effects")
local clear_area_highlight = GameActions.clear_area_highlight
local highlight_exactly = GameActions.highlight_exactly
local validate_hand_indices = CardArea.validate_hand_indices
local call_gfunc = GameActions.call_gfunc

local M = {}

M.DISCARD_POOL_RULE = "Discards are a separate pool that costs no hand-slot"

local function check_blind_size_rule(debuff, count)
  local err = CardArea.blind_size_rule_error(debuff, count, (Legality.play_size_bounds()))
  if err then return nil, err end
  return true
end

local function final_scoring_hand(played, scoring_hand)
  local splash = false
  for _, j in ipairs((G.jokers and G.jokers.cards) or {}) do
    local key = type(j) == "table" and j.config and j.config.center and j.config.center.key
    if key == "j_splash" and not j.debuff then splash = true; break end
  end
  local in_hand = {}
  for _, c in ipairs(scoring_hand) do in_hand[c] = true end
  local out = {}
  for _, c in ipairs(played) do
    if (in_hand[c] or Scoring.always_scores(c) or splash) and not Scoring.never_scores(c) then
      out[#out + 1] = c
    end
  end
  return out
end

local function hand_type_of(cards)
  local ok, text = pcall(G.FUNCS.get_poker_hand_info, cards)
  return ok and text or nil
end

function M.omitted_forced_index(indices)
  local fi = DebuffFacts.forced_selection_index()
  if not fi then return nil end
  for _, ix in ipairs(indices) do if ix == fi then return nil end end
  return fi
end
local omitted_forced_index = M.omitted_forced_index

local function play_signature(cards)
  local parts = {}
  for _, c in ipairs(cards or {}) do parts[#parts + 1] = tostring((c and c.sort_id) or "?") end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function ready_types_in_hand()
  if not (G and G.hand and G.hand.cards) then return nil end
  for _, c in ipairs(G.hand.cards) do
    if CardUtil.is_hidden(c) then return nil end
  end
  local ok, ready = pcall(HandFacts.ready_hands, G.hand.cards)
  if not ok or type(ready) ~= "table" then return nil end
  return ready
end

local function stable_value(value)
  return Utils.stable_repr(value, 2)
end

local function card_content(card)
  if type(card) ~= "table" then return "?" end
  local base = card.base or {}
  local center = card.config and card.config.center or {}
  return table.concat({
    tostring(card.sort_id), tostring(base.value or "?"), tostring(base.suit or "?"),
    tostring(center.key or "?"), tostring(card.enhancement), tostring(card.seal),
    stable_value(card.edition), tostring(card.debuff), stable_value(card.ability),
  }, "/")
end

local function play_content(cards)
  local parts = {}
  for _, c in ipairs(cards or {}) do
    parts[#parts + 1] = card_content(c)
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function resolve_live_indices(signature)
  if not (G and G.hand and G.hand.cards) then return nil end
  local wanted, want_count = {}, 0
  for id in signature:gmatch("[^,]+") do
    if not wanted[id] then want_count = want_count + 1 end
    wanted[id] = true
  end
  local indices = {}
  for index, card in ipairs(G.hand.cards) do
    if wanted[tostring((card and card.sort_id) or "?")] then indices[#indices + 1] = index end
  end
  if #indices < want_count then return nil end
  return indices
end

local function at_most_one_ready_hand()
  local ready = ready_types_in_hand()
  if not ready then return false end
  local count = 0
  for name in pairs(ready) do
    if name ~= "High Card" then
      count = count + 1
      if count > 1 then return false end
    end
  end
  return true
end

local function weak_guard_spent()
  if not (G and G.NEURO) then return false end
  local spent = tonumber(G.NEURO.weak_fired_serial)
  return spent ~= nil and spent == (tonumber(G.NEURO.decision_serial) or 0)
end

local WEAK_HANDS = { ["High Card"] = true, ["Pair"] = true, ["Two Pair"] = true }

local function first_hand_of_round()
  local r = G and G.GAME and G.GAME.current_round
  return r ~= nil and (tonumber(r.hands_played) or 0) == 0
end

local function joker_extra(j, field)
  local e = j.ability and j.ability.extra
  return tonumber(type(e) == "table" and e[field] or e) or 0
end

local SHAPE_TRIGGERS = {
  -- The first hand of exactly one card is copied into the hand.
  { key = "j_dna", off_score = true,
    meets = function(sel) return #sel == 1 and first_hand_of_round() end },
  -- A lone 6 in the round’s first hand is destroyed to create a Spectral card.
  { key = "j_sixth_sense", off_score = true,
    meets = function(sel)
      return #sel == 1 and first_hand_of_round() and PublicCard.is_public(sel[1])
        and NumericEffects.card_id(sel[1]) == 6 and not sel[1].sixth_sense
    end },
  { key = "j_half",
    meets = function(sel, _, j) return #sel <= joker_extra(j, "size") end,
    fact = function(_, _, j)
      return string.format("Half Joker adds +%s Mult to this play because it has %s or fewer cards.",
        Utils.fmt_num(joker_extra(j, "mult")), Utils.fmt_num(joker_extra(j, "size")))
    end },
  { key = "j_square",
    meets = function(sel) return #sel == 4 end,
    fact = function(_, _, j)
      return string.format("Square Joker gains +%s Chips for good because this play has exactly 4 cards.",
        Utils.fmt_num(joker_extra(j, "chip_mod")))
    end },
  -- A hand type already played this round pays; this runs after the round count updates.
  { key = "j_card_sharp",
    meets = function(_, name)
      local h = G.GAME and G.GAME.hands and G.GAME.hands[name]
      return type(h) == "table" and (tonumber(h.played_this_round) or 0) >= 1
    end,
    fact = function(_, name, j)
      return string.format("Card Sharp gives %s Mult because you already played %s this round.",
        Utils.fmt_xmult(joker_extra(j, "Xmult")), name)
    end },
  { key = "j_obelisk",
    meets = function(_, name) return require("facts.dynamic_jokers").most_played_after(name) == false end,
    fact = function(_, name, j)
      return string.format("Obelisk grows by %s Mult because %s is still not your most played hand.",
        Utils.fmt_xmult(joker_extra(j, "extra")), name)
    end },
}

local function live_joker(key)
  for _, j in ipairs((G and G.jokers and G.jokers.cards) or {}) do
    if PublicCard.is_public(j) and not j.debuff and CardUtil.center_key(j) == key then return j end
  end
  return nil
end

local function shape_triggers(selected, handname)
  if type(selected) ~= "table" or #selected == 0 or Legality.selection_hidden(selected) then return {} end
  local out = {}
  for _, t in ipairs(SHAPE_TRIGGERS) do
    local j = live_joker(t.key)
    if j then
      local ok, met = pcall(t.meets, selected, handname, j)
      if ok and met then out[#out + 1] = { trigger = t, joker = j } end
    end
  end
  return out
end

local function off_score_trigger(selected, handname)
  for _, hit in ipairs(shape_triggers(selected, handname)) do
    if hit.trigger.off_score then return true end
  end
  return false
end

local function shape_facts(selected, handname)
  local out = {}
  for _, hit in ipairs(shape_triggers(selected, handname)) do
    if hit.trigger.fact then out[#out + 1] = hit.trigger.fact(selected, handname, hit.joker) end
  end
  return #out > 0 and (" " .. table.concat(out, " ")) or ""
end

local function is_weak(handname, selected)
  if not (handname and WEAK_HANDS[handname]) then return false end
  if #shape_triggers(selected, handname) > 0 then return false end
  local mine = HandFacts.level_value(handname)
  if not mine then return true end
  for name in pairs(HandFacts.HAND_ORDER) do
    local v = not WEAK_HANDS[name] and HandFacts.level_value(name)
    if v and v < mine then return false end
  end
  return true
end

local function better_ready(selected_cards, handname)
  if not (handname and ready_types_in_hand()) then return nil end
  local mine = HandFacts.selection_value(selected_cards, handname)
  if not mine then return nil end
  local ok, st = pcall(HandFacts.structure)
  if not ok or type(st) ~= "table" or type(st.ready) ~= "table" then return nil end
  local chosen = {}
  for _, c in ipairs(selected_cards) do chosen[c] = true end
  local out = {}
  for _, row in ipairs(st.ready) do
    local set, same = {}, #(row.ix or {}) == #selected_cards
    for _, i in ipairs(row.ix or {}) do
      local c = G.hand.cards[i]
      set[#set + 1] = c
      if not chosen[c] then same = false end
    end
    local value = (#set > 0 and not row.zeroed and not same) and HandFacts.selection_value(set, row.name) or nil
    if value and value > mine then
      out[#out + 1] = { label = row.name .. " (cards " .. table.concat(row.ix, ", ") .. ")", value = value }
    end
  end
  table.sort(out, function(a, b) return a.value > b.value end)
  local labels = {}
  for i, o in ipairs(out) do labels[i] = o.label end
  return labels
end

local function better_ready_note(labels)
  if not (labels and #labels > 0) then return "" end
  return string.format(" Ready %s would score more than these cards at your current levels and known joker effects.",
    table.concat(labels, ", "))
end

local function unscored_note(selected_cards, indices)
  local ok, scoring, exact = pcall(Scoring.scoring_subset, selected_cards)
  if not (ok and scoring and exact) then return "" end
  local scores = {}
  for _, c in ipairs(scoring) do scores[c] = true end
  local idle = {}
  for i, c in ipairs(selected_cards) do
    if not scores[c] then idle[#idle + 1] = tostring(indices and indices[i] or i) end
  end
  if #idle == 0 then return "" end
  return string.format(" Card%s %s %s played but will not score.", #idle == 1 and "" or "s",
    table.concat(idle, ", "), #idle == 1 and "is" or "are")
end

local function resolution_contract(discards_left)
  if (tonumber(discards_left) or 0) > 0 then
    return "Answer \"yes\" to commit these exact cards. Answer \"no\" only with a concrete next move; no plays nothing, discards nothing, and draws nothing. After no, the hand decision comes back: redraw by discarding, or play a specific Ready alternative; that next play commits immediately without another review."
  end
  return "Answer \"yes\" to commit these exact cards. Answer \"no\" only for a specific different selection already Ready; no changes or draws any card. After no, the next play you choose commits immediately without another review."
end

local function forced_play_now(hands_left, discards_left)
  return hands_left == 1 and discards_left == 0 and at_most_one_ready_hand()
end

local REVIEW_LEAD = "Review required: answer the play review. "

local function weak_pause_text(indices, handname, level, chips, mult, hands_left, discards_left, score_level,
    selected_cards, played_cards)
  local facts = { Legality.selection_line(indices, handname, level, chips, mult, score_level)
    .. unscored_note(selected_cards, indices) }
  if is_weak(handname, selected_cards) then
    local ready = better_ready(selected_cards, handname)
    facts[#facts + 1] = "Bare " .. handname .. " is one of the three lowest-ranking hand types." .. better_ready_note(ready)
    local redraw = discards_left > 0 and (M.DISCARD_POOL_RULE
      .. ". Check the one-card-away odds for a concrete upgrade before declining to redraw. ") or ""
    return redraw .. REVIEW_LEAD .. resolution_contract(discards_left), ready, table.concat(facts, "\n")
  end
  local masked = handname == Legality.MASK_HAND
  if masked then facts[#facts + 1] = Legality.mask_note(played_cards) or Legality.MASK_NOTE end
  local ready = not masked and better_ready(selected_cards, handname) or nil
  facts[#facts + 1] = shape_facts(selected_cards, handname):sub(2)
  facts[#facts + 1] = better_ready_note(ready):sub(2)
  facts[#facts + 1] = Legality.spend_line(hands_left, discards_left)
  return REVIEW_LEAD .. resolution_contract(discards_left), ready,
    require("context.state_doc").lines(unpack(facts))
end

local function all_cards_score(selected_cards)
  local ok, scoring, exact = pcall(Scoring.scoring_subset, selected_cards)
  return ok and exact == true and type(scoring) == "table" and #scoring == #selected_cards
end

local function best_ready_play(selected_cards, handname)
  if not handname then return false end
  local ready = better_ready(selected_cards, handname)
  return ready ~= nil and #ready == 0 and all_cards_score(selected_cards)
end

M.PLAY_REVIEW_BRIEF = "Nothing was executed: this play waits for your answer to its review in the decision that follows."

local function confirm_hand_on()
  local ok, on = pcall(function() return require("core.config").bool("NEURO_CONFIRM_HAND") end)
  return not ok or on
end
M.confirm_hand_on = confirm_hand_on
M.forced_play_now = function()
  return forced_play_now(GameFacts.hands_left(), GameFacts.discards_left()) == true
end

local function play_confirm_reject(selected_cards, indices)
  if not confirm_hand_on() then return nil end
  Gate.context_revision()
  if Gate.final_play_required() then return nil end

  local classes = {}

  local ok_v, verdict = pcall(Legality.play_verdict, selected_cards, indices)
  if ok_v and type(verdict) == "string" and verdict ~= "" then
    classes.legality = true
    return "Answer the play review. " .. resolution_contract(GameFacts.discards_left()),
      classes, verdict
  end

  local hands_left = GameFacts.hands_left()
  local discards_left = GameFacts.discards_left()
  local hidden = Legality.selection_hidden(selected_cards)
  local shown = not hidden and hand_type_of(selected_cards) or nil
  if shown and off_score_trigger(selected_cards, shown) then return nil end
  if discards_left <= 0 and best_ready_play(selected_cards, shown) then return nil end

  if not weak_guard_spent() and hands_left > 0 then
    local handname, level, chips, mult, score_level
    if hidden then
      handname, level, chips, mult =
        Legality.MASK_HAND, Legality.MASK_FIELD, Legality.MASK_FIELD, Legality.MASK_FIELD
    end
    if not hidden then handname = shown end
    local values = not hidden and handname and HandFacts.hand_values(handname)
    if values then
      level, score_level, chips, mult = values.level, values.score_level, values.chips, values.mult
    end
    local weak_final = discards_left <= 0 and is_weak(handname, not hidden and selected_cards or nil)
      and forced_play_now(hands_left, discards_left)
    if discards_left > 0 or weak_final then
      local weak_text, dominant_alt, facts = weak_pause_text(indices, handname, level, chips, mult,
        hands_left, discards_left, score_level, not hidden and selected_cards or {}, selected_cards)
      classes.weak = true
      classes.dominant_alt = dominant_alt
      return weak_text, classes, facts
    end
  end

  if not forced_play_now(hands_left, discards_left) then
    local ht = shown or "this hand"
    local res = string.format("%d hand(s) and %d discard(s) left", hands_left, discards_left)
    local ok_rem, remaining = pcall(function() return require("facts.economy_facts").blind_remaining() end)
    if ok_rem and type(remaining) == "number" then res = Utils.fmt_num(remaining) .. " to clear, " .. res end
    local fit = ""
    local steps, jsum
    if not hidden then steps, jsum = HandFacts.joker_chain(selected_cards, ht) end
    if not jsum then
      local ok_js, js = pcall(Scoring.joker_summary, selected_cards)
      jsum = ok_js and js or nil
    end
    local led = jsum and jsum.ledger
    local chain = HandFacts.joker_chain_prose(steps)
    local ceilings, open_sources = {}, {}
    for _, kind in ipairs({ "xmult", "xchips", "mult", "chips" }) do
      local q = led and led.gated[kind]
      if q and q.k ~= "known" and not Scoring.Q.is_identity(kind, q) then
        local clause = CtxHelpers.quantity_clause(kind, q)
        if clause then ceilings[#ceilings + 1] = clause end
      end
    end
    for _, src in ipairs(led and led.sources or {}) do
      if src.total.k ~= "known" then open_sources[#open_sources + 1] = src end
    end
    local ceiling
    if #ceilings > 0 then
      local srcs = CtxHelpers.ledger_gated_sources({ sources = open_sources })
      ceiling = table.concat(ceilings, ", ") .. (#srcs > 0 and (" (" .. table.concat(srcs, "; ") .. ")") or "")
    end
    if chain ~= "" then
      fit = string.format(" Your jokers on %s, in scoring order -- %s%s.", ht, chain,
        ceiling and ("; and " .. ceiling) or "")
    elseif ceiling then
      fit = string.format(" Your jokers on %s add %s.", ht, ceiling)
    end
    local weak_note = ""
    if not hidden then
      fit = fit .. unscored_note(selected_cards, indices) .. shape_facts(selected_cards, ht)
        .. better_ready_note(better_ready(selected_cards, ht))
    end
    if discards_left <= 0 and hands_left > 1 and is_weak(ht, not hidden and selected_cards or nil) then
      weak_note = string.format(
        "%s is one of the three lowest-ranking hand types and you have no discards left to improve it: spending a hand here only pays off if your other %d hand(s) can still cover the rest. ",
        ht, hands_left - 1)
    end
    local mask_note = hidden and (" " .. (Legality.mask_note(selected_cards) or Legality.MASK_NOTE)) or ""
    return weak_note .. "Answer the play review. " .. resolution_contract(discards_left),
      classes, string.format("Committing %s -- %s.%s%s", ht, res, fit, mask_note)
  end

  return nil
end

local function commit_hand(data, action, confirmed, confirmation_tx)
  if not confirmed and Gate.proposal() then
    return ActionResult.reject("POLICY_ACKNOWLEDGED",
      "A play review is awaiting your answer; this move was acknowledged without changing anything. Answer the review first.")
  end
  local function execution_failure(message) return ActionResult.outcome("failed", message) end
  if not G.hand or not G.hand.cards then
    return ActionResult.reject("TARGET_UNAVAILABLE",
      "Hand is not available yet. Wait for the hand screen, then select cards.")
  end
  if G.play and G.play.cards and #G.play.cards > 0 then
    return nil, ActionResult.wait("A hand is still resolving, so nothing was applied.")
  end
  local indices, ierr = validate_hand_indices(data.indices, #G.hand.cards)
  if not indices then
    return ActionResult.reject("INVALID_SELECTION", ierr)
  end
  local target_cards = {}
  for i = 1, #indices do target_cards[i] = G.hand.cards[indices[i]] end

  local fi = omitted_forced_index(indices)
  if fi then
    return ActionResult.reject("INVALID_SELECTION",
      string.format("BOSS (Cerulean Bell): card %d is +LOCK (force-selected) -- the engine keeps it highlighted, so it resolves with every play and every discard whether or not you list it. This selection omits index %d, which would not be the hand you asked for. Add index %d to your selection.", fi, fi, fi))
  end

  local sp = G.GAME and G.GAME.starting_params or nil

  if action == "discard" then
    local discards_left = GameFacts.discards_left()
    if discards_left <= 0 then
      return ActionResult.reject("ACTION_UNAVAILABLE", "No discards remaining. Play a hand instead.")
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
      return nil, ActionResult.wait("The boss banner just fired and is still resolving on screen, so nothing was applied.")
    end
    local pl = sp and tonumber(sp.play_limit)
    if pl and #indices > math.max(pl, 1) then
      return ActionResult.reject("INVALID_SELECTION",
        string.format("You can play at most %d card(s) right now (selected %d).", math.max(pl, 1), #indices))
    end

    local debuff = blind and not blind.disabled and blind.debuff or nil
    local ok_sz, err_sz = check_blind_size_rule(debuff, #target_cards)
    if not ok_sz then return ActionResult.reject("INVALID_SELECTION", err_sz) end

    if not confirmed then
      local reason, classes, facts = play_confirm_reject(target_cards, indices)
      if reason then
        local proposal
        if G.NEURO then
          if classes.weak then G.NEURO.weak_fired_serial = tonumber(G.NEURO.decision_serial) or 0 end
          local hand_type = not Legality.selection_hidden(target_cards) and hand_type_of(target_cards) or nil
          proposal = Gate.proposal_fields({
            signature = play_signature(target_cards), content = play_content(target_cards),
            indices = indices, hand_type = hand_type, dominant_alt = classes.dominant_alt,
          })
        end
        return ActionResult.reject("CONFIRMATION_REQUIRED", reason, {
          boss_verdict = classes.legality or nil, proposal = proposal, brief = M.PLAY_REVIEW_BRIEF, facts = facts,
        })
      end
    end
  end

  return function()
    if confirmed then
      if not Gate.commit_is_current(confirmation_tx) then
        return execution_failure(
          "The confirmed hand transaction changed before execution; nothing was played.")
      end
      if play_content(target_cards) ~= confirmation_tx.content then
        Gate.close_proposal(confirmation_tx, "invalidated")
        return execution_failure(
          "The confirmed cards changed before execution; nothing was played.")
      end
    end
    local pre_hands = GameFacts.hands_left()
    local pre_discards = GameFacts.discards_left()
    local pre_discards_used = tonumber(G and G.GAME and G.GAME.current_round
      and G.GAME.current_round.discards_used) or 0
    local live_targets = {}
    local missing_indices = {}
    for i = 1, #target_cards do
      local live_index = Utils.index_in(G.hand.cards, target_cards[i])
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

    local requested_position = {}
    for i, card in ipairs(live_targets) do requested_position[card] = indices[i] end
    local function card_label(card)
      local position = requested_position[card] or Utils.index_in(G.hand.cards, card)
      local name = CardUtil.is_hidden(card) and "face-down (hidden)" or Utils.playing_card_label(card)
      return tostring(position or "?") .. ":" .. name
    end
    local exact, refused, kept = highlight_exactly(G.hand, live_targets)
    if not exact then
      clear_area_highlight(G.hand)
      local refused_cards, kept_cards = {}, {}
      for _, card in ipairs(refused) do refused_cards[#refused_cards + 1] = card_label(card) end
      for _, card in ipairs(kept) do kept_cards[#kept_cards + 1] = card_label(card) end
      local why = {}
      if #refused_cards > 0 then
        why[#why + 1] = "the game refused " .. table.concat(refused_cards, ", ")
          .. " (the hand selection limit is " .. tostring(CardUtil.highlight_limit()) .. ")"
      end
      if #kept_cards > 0 then
        why[#why + 1] = "the game keeps " .. table.concat(kept_cards, ", ") .. " selected"
      end
      return execution_failure("Could not " .. action .. " the requested cards: "
        .. table.concat(why, "; ") .. ". Nothing was " .. (action == "play" and "played" or "discarded")
        .. "; choose again.")
    end

    local selected_cards = {}
    for _, card in ipairs(live_targets) do selected_cards[#selected_cards + 1] = card_label(card) end
    local msg = "Selected cards: " .. table.concat(selected_cards, ", ")

    if #G.hand.highlighted == 0 then
      return execution_failure(msg .. ". No valid cards to " .. action .. ".")
    end
    local play_record
    if action == "play" then
      if G.NEURO then
        local ht, scored, zeroed
        local ok, text, _, _, scoring_hand = pcall(G.FUNCS.get_poker_hand_info, G.hand.highlighted)
        if ok then ht = text end
        if ok then
          -- A hand debuffed by the boss scores no cards.
          if DebuffFacts.boss_would_debuff(G.hand.highlighted, ht) then
            zeroed, scored = Legality.zeroed_note(ht), 0
          else
            local final = final_scoring_hand(G.hand.highlighted, scoring_hand)
            scored = math.max(0, #final - DebuffFacts.count(final))
          end
        end
        play_record = {
          kind = "play", hand_type = ht, played = #G.hand.highlighted, scored = scored, zeroed = zeroed,
          pre_chips = (G.GAME and G.GAME.chips) or 0, hands_left_after = pre_hands - 1,
          action_id = tostring(data._action_id),
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
    else
      local discards_left = GameFacts.discards_left()
      if discards_left <= 0 then
        clear_area_highlight(G.hand)
        return execution_failure(msg .. ". Cannot discard: no discards remaining. Play a hand instead.")
      end
      if G.NEURO then
        play_record = {
          kind = "discard",
          played = #G.hand.highlighted,
          discards_left_after = math.max(0, discards_left - 1),
        }
      end
    end
    if not call_gfunc(action .. "_cards_from_highlighted") then
      clear_area_highlight(G.hand)
      return execution_failure(msg .. ". Could not " .. action .. ": the " .. action
        .. " action is unavailable right now.")
    end

    return ActionResult.create({
      id = tostring(data._action_id),
      name = action == "play" and "play_hand" or "discard_hand",
      run_generation = G and G.NEURO and G.NEURO.run_generation,
      deadline = ActionResult.now() + 4,
      timeout_outcome = "failed",
      debug = { indices = indices, target_count = #target_cards },
      probe = function()
        local left = 0
        for _, target in ipairs(target_cards) do
          if not Utils.index_in(G and G.hand and G.hand.cards, target) then left = left + 1 end
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
            if Utils.index_in(G and G.play and G.play.cards, target) then in_play = in_play + 1 end
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

local function handle_play_hand(data) return commit_hand(data, "play") end
local function handle_discard_hand(data) return commit_hand(data, "discard") end

local function pending_play_confirm()
  if not confirm_hand_on() then return nil end
  local p = Gate.proposal()
  if not (p and p.phase == "ready" and Gate.proposal_valid(p)) then return nil end
  return p
end

function M.pending()
  local pc = pending_play_confirm()
  if not pc then return nil end
  local indices = resolve_live_indices(pc.signature)
  if not indices then return nil end
  return {
    indices = indices,
    rendered_verdict = pc.verdict,
    rendered_facts = pc.facts,
    hand_type = pc.hand_type,
    dominant_alt = pc.dominant_alt,
    proposal_ref = pc.ref,
    context_revision = pc.context_revision,
  }
end

function M.confirm_ready()
  return M.pending() ~= nil
end

local function confirmation_stale(message)
  return ActionResult.reject("POLICY_ACKNOWLEDGED", message)
end

local function abandon_confirmation(tx, message)
  Gate.close_proposal(tx, "invalidated")
  return confirmation_stale(message)
end

local function handle_resolve_play(data)
  local tx = Gate.proposal()
  if not tx then
    return confirmation_stale(
      "No play confirmation is currently open; nothing was applied. Choose the currently offered action.")
  end
  if tx.phase ~= "ready" then
    return confirmation_stale(
      "This play confirmation is no longer awaiting an answer; nothing was applied. Choose the currently offered action.")
  end
  if not pending_play_confirm() then
    return abandon_confirmation(tx,
      "The review is no longer current; nothing was applied. Choose a new play.")
  end

  Metrics.incr("confirmation_answered")
  if tx.created_at then Metrics.record_timing("confirmation_latency", os.clock() - tx.created_at) end

  if data.answer == "no" then
    local function declined(status, message)
      return ActionResult.outcome(status, message, {
        proposal_ref = tx.ref, confirmation_answer = "no",
        terminal_class = "DECLINED_NOOP", state_mutated = false, no_mutation = true,
      })
    end
    return function()
      if not (Gate.proposal() == tx and tx.phase == "ready") then
        return declined("failed",
          "This confirmation changed before cancellation could be applied; nothing was played or discarded.")
      end
      Gate.close_proposal(tx, "cancelled")
      -- A failed decline makes the SDK retry the force.
      return declined("applied")
    end
  end

  local live_indices = resolve_live_indices(tx.signature)
  if not live_indices then
    return abandon_confirmation(tx,
      "The confirmed selection is no longer in your hand; nothing was played. Choose a new play.")
  end
  local target_cards = {}
  for i = 1, #live_indices do target_cards[i] = G.hand.cards[live_indices[i]] end
  if play_content(target_cards) ~= tx.content then
    return abandon_confirmation(tx,
      "The confirmed selection changed underneath the review; nothing was played. Choose a new play.")
  end

  local exec_or_error = commit_hand({ indices = live_indices, _action_id = data._action_id }, "play", true, tx)
  if type(exec_or_error) ~= "function" then
    Gate.close_proposal(tx, "invalidated")
    return exec_or_error
  end
  if not Gate.begin_commit(tx) then
    return abandon_confirmation(tx,
      "The review became stale before commit; nothing was played. Choose a new play.")
  end
  return exec_or_error
end

function M.committing_indices()
  local tx = Gate.proposal()
  if not (tx and tx.phase == "committing" and type(tx.signature) == "string") then return nil end
  return resolve_live_indices(tx.signature)
end

M.handle_play_hand = handle_play_hand
M.handle_discard_hand = handle_discard_hand
M.handle_resolve_play = handle_resolve_play
if _G.NEURO_TEST then
  M.play_review_reason = play_confirm_reject
  M.play_signature = play_signature
  M.play_content = play_content
end

return M
