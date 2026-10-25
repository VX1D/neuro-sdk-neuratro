local GameFacts = require("facts.game_facts")
local Actions = require("core.actions")
local HandFacts = require("facts.hand_facts")
local CardUtil = require("facts.card_util")
local TargetContracts = require("facts.target_contracts")
local FactHints = require("facts.fact_hints")
local EconomyFacts = require("facts.economy_facts")
local ForceHelpers = require("force.force_helpers")
local DebuffFacts = require("facts.debuff_facts")
local BossLegality = require("facts.boss.legality")
local ContextReadable = require("context.context_readable")
local ActionRegistry = require("core.action_registry")
local Gate = require("core.gate")
local CtxHelpers = require("context.ctx_helpers")
local ForceReferences = require("force.force_references")

-- If a selected hand includes a face-down card, give only its position as the reason.
local function hidden_type_reason(indices)
  local cards = G and G.hand and G.hand.cards or {}
  local down = {}
  for _, ix in ipairs(indices or {}) do
    local card = cards[tonumber(ix)]
    if card and CardUtil.is_hidden(card) then down[#down + 1] = tostring(ix) end
  end
  if #down == 0 then return "type not named" end
  return "type hidden: the selection includes face-down card" .. (#down > 1 and "s " or " ") .. table.concat(down, ",")
end

local function declined_comparison_fact(record)
  if type(record) ~= "table" or not (record.dominant_alt and #record.dominant_alt > 0) then return "" end
  return "At that review, Ready hands that would score more were: " .. table.concat(record.dominant_alt, ", ") .. "."
end

local function declined_choice_note(record, can_play, can_discard, ready_listed)
  if type(record) ~= "table" then return "" end
  local indices = table.concat(record.indices or {}, ",")
  local hand_type = record.hand_type and tostring(record.hand_type) or hidden_type_reason(record.indices)
  local out = string.format(
    "You declined the previous play proposal: indices [%s] = %s. ",
    indices, hand_type)
  out = out .. "Re-evaluate from the complete current context below. "
  if can_discard then
    out = out .. "If you wanted a redraw, discard now with the exact throwaway indices; answering no drew nothing. "
  else
    out = out .. "Answering no drew nothing, and no discard is offered now, so a redraw is not possible this hand. "
  end
  if can_play then
    if ready_listed then
      out = out .. "If you wanted another Ready hand, play it now with its exact listed indices. "
    end
    out = out .. "Any play now is final and commits immediately without another review. "
  end
  return out
end

local function boss_state_note(offered)
  local blind = G.GAME and G.GAME.blind
  if not (blind and blind.boss
      and not Gate.boss_plan_is_current(G.NEURO and G.NEURO.plan)) then
    return ""
  end
  local carriers = {}
  if offered.play_hand then carriers[#carriers + 1] = "play" end
  if offered.discard_hand then carriers[#carriers + 1] = "discard" end
  if #carriers == 0 then return "" end
  return "You did not set a boss plan when you chose this blind. State the rule this boss imposes on you in plan.boss_plan with your next "
    .. table.concat(carriers, " or ") .. ". "
end

local function hand_options(structure, comparison, ...)
  local StateDoc = require("context.state_doc")
  return StateDoc.section("Hand options", StateDoc.lines(StateDoc.lines(...), structure, comparison, "Hand card indices: "
    .. ForceHelpers.index_range((G.hand and G.hand.cards) and #G.hand.cards or 0) .. "."))
end

local function build()
  Actions.get_static_actions()
  local hands_left = GameFacts.hands_left()
  -- Refresh context first because it can invalidate the open transaction and unblock mutations.
  Gate.context_revision()
  local offer = { "play_hand", "discard_hand", "use_consumable", "use_directional_consumable" }
  if BossLegality.boss_names_reorder() then offer[#offer + 1] = "set_joker_order" end
  offer[#offer + 1] = "sell_card"
  local hand_actions, can, can_now = ForceHelpers.collect_actions(offer)
  local can_play, can_discard, can_sell = can.play_hand or false, can.discard_hand or false, can.sell_card or false
  local final_play = Gate.final_play_required()

  local confirming = false
  local pending_confirm, pending_facts = "", ""
  do
    local HH = require("handlers.hand_handlers")
    local ok_pc, pend = pcall(HH.pending)
    local ok_ready, ready = pcall(HH.confirm_ready)
    if ok_pc and ok_ready and ready and pend then
      confirming = true
      if pend.rendered_verdict then
        local mismatch
        local p = G and G.NEURO and G.NEURO.plan
        local focus = p and p.hand_focus
        local ok_focus, is_current = pcall(function()
          return Gate.hand_focus_is_current(p)
        end)
        if ok_focus and is_current and type(focus) == "table"
            and pend.hand_type and focus.primary ~= pend.hand_type then
          mismatch = string.format(
            "Your declared primary hand is %s; the pending confirmed selection is %s.",
            tostring(focus.primary), tostring(pend.hand_type))
        end
        pending_facts = require("context.state_doc").lines(pend.rendered_facts, mismatch)
        pending_confirm = pend.rendered_verdict
          .. " A play review is open. While it is open, the only move is to answer it yes or no; no other hand decision is available. "
      else
        pending_confirm = string.format(
          "A play confirmation is open for indices [%s]. Yes commits these cards. No changes nothing and spends this hand's one review; after it a discard redraws and the next play commits immediately. While this review is open, the only move is to answer it yes or no. ",
          table.concat(pend.indices, ","))
      end
    end
  end

  local hand_structure = HandFacts.structure()
  local ready_n = hand_structure and hand_structure.ready and #hand_structure.ready or 0
  local all_hidden = hand_structure ~= nil and hand_structure.hidden ~= nil
  local structure = ContextReadable.structure_prose(hand_structure)

  local consumable_hint = ""
  if (not confirming) and G.consumeables and G.consumeables.cards
      and Actions.is_action_valid("use_directional_consumable") then
    for _, c in ipairs(G.consumeables.cards) do
      local _, mh = CardUtil.consumable_target_range(c)
      local contract = mh and mh > 0 and TargetContracts.get(c)
      if contract and contract.mode == "ordered_pair" then
        consumable_hint = "To use a directional targeting consumable, give left_index (the hand card it applies to) and right_index (the card it takes from): "
          .. ActionRegistry.example("use_directional_consumable", { area = "consumables" },
            { "area", "index", "name", "left_index", "right_index" }) .. ". "
        break
      end
    end
  end

  local pad_note = ""
  local min_play
  do
    local bl = G.GAME and G.GAME.blind
    local d = bl and not bl.disabled and bl.debuff
    min_play = (type(d) == "table" and tonumber(d.h_size_ge)) or 0
    if min_play > 0 and not BossLegality.play_floor_relaxed() then
      pad_note = "Under this boss a play under " .. min_play .. " cards still spends a hand but scores 0 --"
        .. " select at least " .. min_play .. " cards. Padding cards join the evaluated hand and can change its"
        .. " type (a Pair can become Two Pair or Three of a Kind). "
    end
  end
  local boss_pace_note = boss_state_note({ play_hand = can_play, discard_hand = can_discard })
  local discard_advice = can_discard and HandFacts.discard_advice_applies()
  local has_close = hand_structure ~= nil and not all_hidden and #hand_structure.close > 0
  local board_rules = confirming and "" or (pad_note .. boss_pace_note)

  local discard_lead, ready_fact = "", ""
  if can_discard then
    if discard_advice and not HandFacts.has_strong_ready() then
      ready_fact = all_hidden and "" or "No hand of Straight/Flush rank or better is Ready."
      discard_lead = require("handlers.hand_handlers").DISCARD_POOL_RULE
        .. (has_close
          and " -- the one-card-away odds above show which stronger hands a discard can reach. "
          or ". ")
    end
  elseif (ready_n == 0 or (ready_n == 1 and hand_structure.ready[1].name == "High Card"))
      and not HandFacts.any_face_down() then
    ready_fact = "No hand above High Card is Ready from these cards -- a Straight or Flush one card short of complete scores as High Card, and no card is drawn before a play resolves."
  end

  local banner_lead = ""
  do
    local blind = G and G.GAME and G.GAME.blind
    if blind and blind.block_play and not blind.disabled and not can_play then
      banner_lead = ForceReferences.withheld("play_hand", "this blind's debuff banner finishes playing")
        .. " -- that is an animation, not a rule about your hand. "
        .. (can_discard and "Discard now if you want to, or wait and the play offer returns unchanged. "
          or "Wait and the play offer returns unchanged. ")
    end
  end

  local debuff_lead = ""
  do
    local nd = hand_structure and hand_structure.debuffed
    if nd and nd > 0 then
      local key = require("facts.boss.render").active_boss_key()
      local rec = key and require("facts.boss.model").get(key)
      if not (rec and rec.marks) then
        local noun = HandFacts.any_face_down() and "visible held card" or "held card"
        debuff_lead = CtxHelpers.plural(nd, noun)
          .. ((nd == 1) and " is debuffed: it scores 0 chips and its abilities are off."
              or " are debuffed: they score 0 chips and their abilities are off.")
      end
    end
  end

  local splash_exception_note = CardUtil.owns_live_joker("j_splash")
    and "Exception (Splash): every card you play scores, so add your highest spare cards to a Ready hand for extra chips at no extra hand cost. "
    or ""

  local move_cue = ""
  do
    local rem = EconomyFacts.blind_remaining()
    if rem and rem > 0 then
      if hands_left <= 0 then
        move_cue = "No hands remain; only discards are left. "
      elseif hands_left == 1 then
        move_cue = "This is your last hand: it must score all the chips still to go, or the blind is not cleared. "
      else
        move_cue = "Spread the target evenly across the hands you have left. "
      end
    end
  end

  local facedown_cue = ""
  if all_hidden then
    facedown_cue = (can_play and can_discard)
      and "With every hand card face-down, playing or discarding blind is your call. " or ""
  elseif HandFacts.any_face_down() then
    facedown_cue = (can_play and can_discard and not discard_advice)
      and "Decide from the visible cards, and prefer playing your best hand from what you can see over burning discards. "
      or "Decide from the visible cards. "
  end

  local pending_guarded = ForceHelpers.pending_confirmation_note({ sell_card = can_sell })

  local decline = final_play and Gate.decline_context() or nil
  local decline_note = declined_choice_note(decline, can_play, can_discard, ready_n > 0 and not all_hidden)

  local query_head = decline_note .. pending_confirm .. pending_guarded
  local query = move_cue .. facedown_cue .. banner_lead .. discard_lead
    .. ForceHelpers.paragraph(board_rules) .. consumable_hint
    .. FactHints.plan_note("hand") .. splash_exception_note

  local most_played_fact = ""
  if (not confirming) and Actions.is_action_valid("use_consumable") then
    local has_planet = false
    if G.consumeables and G.consumeables.cards then
      for _, c in ipairs(G.consumeables.cards) do
        if CardUtil.card_set(c) == "Planet" then has_planet = true break end
      end
    end
    local mp = has_planet and DebuffFacts.most_played_by_count() or nil
    if mp then
      local hv = HandFacts.hand_values(mp)
      most_played_fact = string.format("Played most this run: %s, %d times, level %d.",
        CtxHelpers.normalize_text(mp), hv and hv.played or 0, hv and hv.level or 1)
      query = query
        .. "Levels compound -- with a Planet in hand, prefer levelling the hand you play most (named under Hand levels) over one you rarely make; Black Hole levels every type. "
    end
  end

  local commit_opts, tool_bits = {}, {}

  if confirming then
    local tx = Gate.proposal()
    local resolution_query = pending_confirm
      .. "Your move: answer the play review. Answer yes to commit the offered cards or no to cancel without playing. "
    return ForceHelpers.finish(resolution_query, {
      state_extra = require("context.state_doc").lines(
        require("context.state_doc").section("Proposed play", pending_facts), hand_options(structure, nil, debuff_lead)),
      actions = { "resolve_play" },
      decision_snapshot = tx and Gate.snapshot_proposal() or nil,
      confirmation_proposal_ref = tx and tx.ref or nil,
    }, true)
  end

  local boss_plan_example = ""
  do
    local requirements = Gate.action_requirements("SELECTING_HAND", "play_hand")
    if requirements.plan.boss and not Gate.boss_plan_is_current(G.NEURO and G.NEURO.plan) then
      boss_plan_example = " and set plan.boss_plan"
    end
  end
  if can_play then
    local HH = require("handlers.hand_handlers")
    local no_review_now = (not final_play) and HH.confirm_hand_on() and HH.forced_play_now()
    local play_note = final_play
      and " (FINAL PLAY CHOICE: commits these indices immediately; uses a hand)"
      or (no_review_now
        and " (last hand, no discards and at most one Ready hand: there is nothing to weigh, so this"
          .. " commits immediately unless "
          .. (require("facts.boss.render").active_boss_key()
            and "this boss's rule would score it 0 or debuff every scoring card, or " or "")
          .. "a low type is played while a Ready hand scores more or one of its cards will not score; uses a hand)"
        or " (uses a hand)")
    commit_opts[#commit_opts + 1] = ActionRegistry.prompt("play_hand")
      .. play_note
      .. boss_plan_example
  end
  if can_discard then
    commit_opts[#commit_opts + 1] = ActionRegistry.prompt("discard_hand")
      .. " (uses a discard)"
      .. boss_plan_example
  end
  ForceHelpers.consumable_tools(tool_bits, can_now)
  if can.set_joker_order then
    tool_bits.set_joker_order = (ForceHelpers.joker_order_move() or ActionRegistry.prompt("set_joker_order"))
      .. " (the boss shuffled your jokers; it moves them by position)"
  end
  local joker_sellable = false
  if can_sell then
    local sellable = {}
    for _, payload in ipairs(ActionRegistry.candidates("sell_card")) do
      sellable[#sellable + 1] = ActionRegistry.render("sell_card", payload)
      if payload.area == "jokers" then joker_sellable = true end
    end
    if #sellable > 0 and can_now.sell_card then
      tool_bits.sell_card = table.concat(sellable, " or ")
    end
  end
  -- An owned consumable is blocked by full joker slots, not by consumable slots.
  local blocked_note = ""
  if can.use_consumable or can.use_directional_consumable or can_sell then
    local slot_tail = joker_sellable
      and "Free a joker slot by selling a joker now. "
      or "This mod blocks selling jokers mid-round (base Balatro allows it), so free a joker slot by selling one in the shop. "
    local slot_blocked
    blocked_note, slot_blocked = require("facts.use_gate").blocked_note()
    query = query .. (slot_blocked and slot_tail or "")
  end
  query = query .. ForceHelpers.pending_gate_note(hand_actions)

  query = query_head .. ForceHelpers.repeat_pressure_note(hand_actions) .. query .. ForceHelpers.your_move(commit_opts)

  return ForceHelpers.finish(query, {
    state_extra = require("context.state_doc").lines(
      hand_options(structure, declined_comparison_fact(decline), ready_fact, debuff_lead),
      require("context.state_doc").section("Constraints", blocked_note), FactHints.plan_state("hand"),
      require("context.state_doc").section(require("context.ctx_hand").levels_heading(), most_played_fact)),
    actions = hand_actions,
    tool_bits = tool_bits,
    decision_snapshot = {
      proposal_ref = nil,
      phase = "proposal",
      context_revision = Gate.context_revision(),
      run_generation = tonumber(G.NEURO and G.NEURO.run_generation) or 0,
      state_enter_serial = tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0,
      actions = { unpack(hand_actions) },
    },
  }, true)
end

local M = { build = build }

if rawget(_G, "NEURO_TEST") then M.boss_state_note = boss_state_note end

return M
