local GameFacts = require("facts.game_facts")
local Actions = require("core.actions")
local HandFacts = require("facts.hand_facts")
local CardUtil = require("facts.card_util")
local FactHints = require("facts.fact_hints")
local EconomyFacts = require("facts.economy_facts")
local ForceHelpers = require("force.force_helpers")
local TransitionGuard = require("core.transition_guard")
local DebuffFacts = require("facts.debuff_facts")
local BossLegality = require("facts.boss.legality")
local ContextReadable = require("context.context_readable")
local ActionRegistry = require("core.action_registry")
local HandTx = require("core.hand_transaction")
local CtxHelpers = require("context.ctx_helpers")
local PlanGate = require("core.plan_gate")
local blueprint_chain_hint = FactHints.blueprint_chain_hint
local failed_action_warning = ForceHelpers.failed_action_warning

local RULE_IDS = { "exact", "boss_min", "target", "discard", "pace" }

local function copy_list(list)
  local out = {}
  for i, value in ipairs(list or {}) do out[i] = value end
  return out
end

local function declined_choice_note(record)
  if type(record) ~= "table" then return "" end
  local indices = table.concat(record.indices or {}, ",")
  local hand_type = record.hand_type and tostring(record.hand_type) or "unknown hand type"
  local out = string.format(
    "You declined transaction %s: indices [%s] = %s. ",
    tostring(record.transaction_id or "?"), indices, hand_type)
  if record.dominant_alt and #record.dominant_alt > 0 then
    out = out .. "At that review, stronger hands already Ready were: "
      .. table.concat(record.dominant_alt, ", ") .. ". "
  end
  if record.reason then
    out = out .. "Your own stated reason for no was: \"" .. record.reason
      .. "\". Act on that reason now. "
  else
    out = out .. "You supplied no reason, so re-evaluate from the complete current context below. "
  end
  return out
    .. "If you wanted a redraw, call discard_hand now with the exact throwaway indices; no did not draw anything. "
    .. "If you wanted another Ready hand, call play_hand now with that hand's exact listed indices. "
    .. "Any play_hand now is final and commits immediately without another review. "
end

local function boss_state_note()
  local blind = G.GAME and G.GAME.blind
  if not (blind and blind.boss
      and not PlanGate.boss_plan_is_current(G.NEURO and G.NEURO.plan)) then
    return ""
  end
  return "You did not set a boss plan when you chose this blind. State the rule this boss imposes on you in plan.boss_plan with your next play_hand or discard_hand. "
end

local function count_semicolon_items(structure, label)
  local seg = structure:match(label .. ": (.-)%. ") or structure:match(label .. ": (.-)%.$")
  if not (seg and seg:find("%S")) then return 0 end
  local n = 1
  for _ in seg:gmatch("; ") do n = n + 1 end
  return n
end

local function build()
  Actions.get_static_actions()
  local hands_left = GameFacts.hands_left()
  local disc = GameFacts.discards_left()
  local can_play = Actions.is_action_valid("play_hand")
  local can_discard = Actions.is_action_valid("discard_hand")
  local can_sell = Actions.is_action_valid("sell_card")
  HandTx.context_revision()
  local final_play = HandTx.final_play_required()

  if HandTx.mode() == "publishing" then return nil end

  local confirming = false
  local pending_confirm = ""
  do
    local HH = require("handlers.hand_handlers")
    local ok_pc, pend = pcall(HH.pending)
    local ok_ready, ready = pcall(HH.confirm_ready)
    if ok_pc and ok_ready and ready and pend then
      confirming = true
      local tx = HandTx.current()
      if pend.rendered_verdict then
        local mismatch = ""
        local p = G and G.NEURO and G.NEURO.plan
        local focus = p and p.hand_focus
        local ok_focus, is_current = pcall(function()
          return require("core.plan_gate").hand_focus_is_current(p)
        end)
        if ok_focus and is_current and type(focus) == "table"
            and pend.hand_type and focus.primary ~= pend.hand_type then
          mismatch = string.format(
            "Your declared primary hand is %s; the pending confirmed selection is %s. ",
            tostring(focus.primary), tostring(pend.hand_type))
        end
        pending_confirm = mismatch .. pend.rendered_verdict
          .. string.format(" This is hand transaction %d. While it is open, use only resolve_play with transaction_id %d and answer yes or no; no other hand decision is available. ", tx.id, tx.id)
      else
        pending_confirm = string.format(
          "A play_hand confirmation is open for indices [%s] as transaction %d. Yes commits these cards. No changes nothing and spends this hand's one review; then discard_hand redraws or the next play_hand commits immediately. While this transaction is open, only resolve_play is valid. ",
          table.concat(pend.indices, ","), tx.id, tx.id)
      end
    end
  end

  local raw_structure = HandFacts.summary()
  local ready_n = count_semicolon_items(raw_structure, "Ready")
  local structure = ContextReadable.structure_prose(raw_structure)
  local bp_chain = (not confirming) and blueprint_chain_hint(final_play) or ""

  local consumable_hint = ""
  if (not confirming) and Actions.is_action_valid("use_consumable") and G.consumeables and G.consumeables.cards then
    local any_needs, any_usable_nt = false, false
    for _, c in ipairs(G.consumeables.cards) do
      local _, mh = CardUtil.consumable_target_range(c)
      if mh and mh > 0 then
        any_needs = true
      elseif CardUtil.consumable_usable_now(c) then
        any_usable_nt = true
      end
    end
    local parts = {}
    if any_needs then
      parts[#parts + 1] = "To use a targeting consumable (the consumables list shows how many cards each one needs): "
        .. ActionRegistry.example("use_consumable", { area = "consumeables" }, { "area", "index", "hand_indices" }) .. "."
    end
    if any_usable_nt then
      parts[#parts + 1] = "To use a consumable that needs no target: "
        .. ActionRegistry.example("use_consumable", { area = "consumeables" }) .. "."
    end
    if #parts > 0 then
      consumable_hint = FactHints.emit("consumable_slots", table.concat(parts, " ") .. " ")
    end
  end

  local nph = "the per-hand chip target"
  local remaining = "the chips remaining to clear the blind"
  local closehand = "one-card-away hand"
  local pad_note = ""
  local min_play
  do
    local bl = G.GAME and G.GAME.blind
    local d = bl and not bl.disabled and bl.debuff
    min_play = (type(d) == "table" and tonumber(d.h_size_ge)) or 0
    if min_play > 0 and not BossLegality.play_floor_relaxed() then
      pad_note = "Under this boss every play must select at least " .. min_play
        .. " cards; a Ready hand listing fewer positions is played by selecting those positions plus"
        .. " other cards to reach " .. min_play .. ", and the listed positions still form the scoring hand. "
    end
  end
  local boss_pace_note = boss_state_note()
  local exact_clause = (pad_note ~= "")
    and " the exact cards that form it (any hand type counts) -- play those positions, plus filler only if the boss rule below requires a minimum size. "
    or " the exact cards that form it (any hand type counts) -- play exactly those positions, no extra or missing cards. "
  local clause = {
    exact = "The cards listed on a Ready hand are" .. exact_clause,
    boss_min = pad_note,
    target = "First check " .. remaining .. " -- if a Ready hand's score reaches it, playing it now clears the blind. Judge each hand's value YOURSELF from its level and base values, your jokers and your card bonuses -- no number here does that for you. ",
    discard = (can_discard and not HandFacts.any_face_down())
      and ("If every Ready hand is far below " .. nph .. " (a rough per-hand average, not a floor), a discard toward a " .. closehand .. " can upgrade it. ")
      or "",
    pace = "Once the target is clearly reachable, winning in fewer hands pays more at cash-out. ",
  }
  local brief = {
    exact = (pad_note ~= "")
      and "Play exactly the positions a Ready hand lists, plus filler to reach the boss minimum. "
      or "Play exactly the positions a Ready hand lists, no extra or missing cards. ",
    boss_min = pad_note,
    target = "Check " .. remaining .. " first. Judge each hand's value YOURSELF from its level and "
      .. "base values, your jokers and your card bonuses -- no number here does that for you. ",
    discard = (can_discard and not HandFacts.any_face_down())
      and ("If every Ready hand is far below " .. nph .. ", a discard toward a " .. closehand .. " can upgrade it. ")
      or "",
    pace = "Winning in fewer hands pays more at cash-out. ",
  }
  local function numbered(set)
    local parts, n = { "Rules: " }, 0
    for _, id in ipairs(RULE_IDS) do
      if set[id] ~= "" then
        n = n + 1
        parts[#parts + 1] = n .. ") " .. set[id]
      end
    end
    return table.concat(parts)
  end
  local rules_text = ""
  if not confirming then
    rules_text = (final_play or GameFacts.round() == nil)
      and numbered(clause)
      or FactHints.emit("sh_rules_core", numbered(clause))
  end
  if (not confirming) and rules_text == "" then
    rules_text = FactHints.emit("sh_rules_brief", numbered(brief))
  end
  if not confirming then rules_text = rules_text .. FactHints.emit("sh_rules_boss", boss_pace_note) end

  local discard_lead = ""
  if not HandFacts.any_face_down() then
    if can_discard then
      if not HandFacts.has_strong_ready() then
        discard_lead = "No hand of Straight/Flush rank or better is Ready. "
          .. require("handlers.hand_handlers").DISCARD_POOL_RULE
          .. " -- the one-card-away odds above show which stronger hands a discard can reach. "
      end
    elseif ready_n == 0 then
      discard_lead = "No hand above High Card is Ready from these cards -- a Straight or Flush one card short of complete scores as High Card, and no card is drawn before a play resolves. "
    end
  end

  local banner_lead = ""
  do
    local blind = G and G.GAME and G.GAME.blind
    if blind and blind.block_play and not blind.disabled and not can_play then
      banner_lead = "This blind's debuff banner is still playing, so play_hand is withheld for another moment -- that is an animation, not a rule about your hand. Discard now if you want to, or wait and the play offer returns unchanged. "
    end
  end

  local debuff_lead = ""
  do
    local nd = DebuffFacts.count(G.hand and G.hand.cards or nil)
    if nd and nd > 0 then
      local key = require("facts.boss.render").active_boss_key()
      local rec = key and require("facts.boss.model").get(key)
      if not (rec and rec.marks) then
        debuff_lead = CtxHelpers.plural(nd, "held card")
          .. ((nd == 1) and " is debuffed: it scores 0 chips and its abilities are off. "
              or " are debuffed: they score 0 chips and their abilities are off. ")
      end
    end
  end

  local splash_note = ""
  if G.jokers and G.jokers.cards then
    local PublicCard = require("facts.public_card_identity")
    for i, jc in ipairs(G.jokers.cards) do
      local ck = (jc and not jc.debuff) and PublicCard.multiset_key(jc, "jokers", i) or nil
      if ck == "center:j_splash" then
        splash_note = "Exception (Splash): every card you play scores, so add your highest spare cards to a Ready hand for extra chips at no extra hand cost. "
        break
      end
    end
  end

  local move_cue = ""
  do
    local rem = EconomyFacts.blind_remaining()
    if rem and rem > 0 then
      local rs = (rem < 1e12) and string.format("%.0f", rem) or string.format("%.3g", rem)
      local tail_p = ""
      if hands_left <= 0 then
        tail_p = " No hands remain; only discards are left."
      elseif hands_left == 1 then
        tail_p = " This is your last hand: it must reach that or the blind is not cleared."
      else
        local per = CardUtil.score_per_hand(rem, hands_left)
        if per and per > 0 then
          tail_p = string.format(" Spread evenly that is about %s per hand.",
            (per < 1e12) and string.format("%.0f", per) or string.format("%.3g", per))
        end
      end
      move_cue = string.format("You still need %s chips, with %d hand(s) and %d discard(s) left.%s ", rs, hands_left, disc, tail_p)
    end
  end

  local pending_guarded = ""
  do
    local ok_pg, note = pcall(require("handlers.shop_handlers").pending_confirmation_note,
      { sell_card = can_sell })
    if ok_pg and type(note) == "string" then pending_guarded = note end
  end

  local function teaching(text) return (not confirming) and text or "" end
  local decline_note = final_play and declined_choice_note(HandTx.decline_context()) or ""

  local query = "State: SELECTING_HAND. "
    .. failed_action_warning()
    .. decline_note
    .. pending_confirm
    .. pending_guarded
    .. ForceHelpers.repeat_pressure_note()
    .. teaching(move_cue)
    .. structure
    .. teaching(banner_lead)
    .. teaching(discard_lead)
    .. debuff_lead
    .. rules_text
    .. bp_chain
    .. consumable_hint
  query = query .. teaching(FactHints.plan_note("hand"))
  query = query .. teaching(splash_note)

  if (not confirming) and Actions.is_action_valid("use_consumable") then
    local has_planet = false
    if G.consumeables and G.consumeables.cards then
      for _, c in ipairs(G.consumeables.cards) do
        if CardUtil.card_set(c) == "Planet" then has_planet = true break end
      end
    end
    local mp = has_planet and DebuffFacts.most_played_hand() or nil
    if mp then
      local hd = G.GAME and G.GAME.hands and G.GAME.hands[mp]
      query = query .. FactHints.emit("level_played_type", string.format(
        "You hold a Planet. Levels compound -- prefer levelling the hand you play most (%s, played %dx, lv %d) over one you rarely make; Black Hole levels every type. ",
        tostring(mp), (hd and tonumber(hd.played)) or 0, (hd and tonumber(hd.level)) or 1)
        .. HandFacts.leveled_spread_note())
    end
  end

  local hand_actions = {}
  local commit_opts = {}

  if confirming then
    local tx = HandTx.current()
    local id = tx and tx.id or (pending_confirm:match("transaction (%d+)") or "?")
    local yes_example = tx and ActionRegistry.render("resolve_play", {
      transaction_id = tx.id, answer = "yes",
    }) or ActionRegistry.prompt("resolve_play")
    local no_example = tx and ActionRegistry.example("resolve_play", {
      transaction_id = tx.id, answer = "no",
    }, { "transaction_id", "answer", "reason" }) or ActionRegistry.prompt("resolve_play")
    local resolution_query = "State: SELECTING_HAND. "
      .. failed_action_warning()
      .. pending_confirm
      .. structure
      .. debuff_lead
      .. "Hand card indices: " .. ForceHelpers.index_range((G.hand and G.hand.cards) and #G.hand.cards or 0) .. ". "
      .. string.format("Your move: required transaction_id is %s. Choose exactly one:\nYES: %s\nNO: %s\n",
        tostring(id), yes_example, no_example)
      .. "For yes, omit reason. For no, reason is optional; preferably name the concrete next action and exact indices. "
    local ok_boss, boss_fact = pcall(require("context.ctx_blind").blind_debuff_line)
    if ok_boss and type(boss_fact) == "string" and boss_fact ~= "" then
      resolution_query = resolution_query .. "\n" .. boss_fact .. " "
    end
    return {
      query = resolution_query:gsub("  +", " "),
      actions = { "resolve_play" },
      decision_snapshot = tx and HandTx.snapshot(tx) or nil,
    }
  end

  local boss_plan_example = ""
  do
    local requirements = PlanGate.action_requirements("SELECTING_HAND", "play_hand")
    if requirements.plan.boss and not PlanGate.boss_plan_is_current(G.NEURO and G.NEURO.plan) then
      boss_plan_example = ' with "plan":{"boss_plan":"..."}'
    end
  end
  if can_play then
    hand_actions[#hand_actions + 1] = "play_hand"
    local play_note = final_play
      and " (FINAL PLAY CHOICE: commits these indices immediately; uses a hand)"
      or " (uses a hand)"
    commit_opts[#commit_opts + 1] = ActionRegistry.prompt("play_hand")
      .. play_note
      .. boss_plan_example
  end
  if can_discard then
    hand_actions[#hand_actions + 1] = "discard_hand"
    commit_opts[#commit_opts + 1] = ActionRegistry.prompt("discard_hand")
      .. " (uses a discard)"
      .. boss_plan_example
  end
  if Actions.is_action_valid("use_consumable") then
    hand_actions[#hand_actions + 1] = "use_consumable"
    if not TransitionGuard.reject_reason("use_consumable") then
      local usable = {}
      for _, payload in ipairs(ActionRegistry.candidates("use_consumable")) do
        local area = (payload.area == "consumeables") and G.consumeables or CardUtil.pack_area()
        local _, maximum = CardUtil.consumable_target_range(
          area and area.cards and area.cards[payload.index])
        local fields = (maximum and maximum > 0) and { "area", "index", "hand_indices" } or nil
        usable[#usable + 1] = ActionRegistry.example("use_consumable", payload, fields)
      end
      if #usable > 0 then commit_opts[#commit_opts + 1] = table.concat(usable, " or ") end
    end
  end
  if Actions.is_action_valid("use_directional_consumable") then
    hand_actions[#hand_actions + 1] = "use_directional_consumable"
    if not TransitionGuard.reject_reason("use_directional_consumable") then
      commit_opts[#commit_opts + 1] = ActionRegistry.prompt("use_directional_consumable")
    end
  end
  if BossLegality.boss_names_reorder() and Actions.is_action_valid("set_joker_order") then
    hand_actions[#hand_actions + 1] = "set_joker_order"
    commit_opts[#commit_opts + 1] = ActionRegistry.prompt("set_joker_order")
      .. " (the boss shuffled your jokers; it still moves them by position, and they still fire left-to-right)"
  end
  if can_sell then
    hand_actions[#hand_actions + 1] = "sell_card"
    if not TransitionGuard.reject_reason("sell_card") then
      local sellable = {}
      for _, payload in ipairs(ActionRegistry.candidates("sell_card")) do
        sellable[#sellable + 1] = ActionRegistry.render("sell_card", payload)
      end
      if #sellable > 0 then commit_opts[#commit_opts + 1] = table.concat(sellable, " or ") end
    end
  end
  local consumables_shown = false
  for _, name in ipairs(hand_actions) do
    if name == "use_consumable" or name == "use_directional_consumable" or name == "sell_card" then
      consumables_shown = true
    end
  end
  local other_usable = false
  for _, c in ipairs((G.consumeables and G.consumeables.cards) or {}) do
    if CardUtil.consumable_usable_now(c) then other_usable = true break end
  end
  if (not confirming) and consumables_shown and (can_sell or other_usable)
    and CardUtil.has_blocked_consumable() then
    local slot_tail = can_sell
      and "Only the second case is actionable -- free a slot by using another consumable now, or sell one (sell_card). "
      or "Only the second case is actionable -- this mod blocks selling mid-round (base Balatro allows it), so free a slot by using another consumable now, or sell in the shop. "
    query = query .. "An owned consumable (marked not usable) cannot be used right now: either it needs more cards selected than your hand holds, or it creates a joker/consumable and every output slot is full. " .. slot_tail
  end
  query = query .. teaching(ForceHelpers.pending_gate_note(hand_actions))
  query = query .. "Hand card indices: " .. ForceHelpers.index_range((G.hand and G.hand.cards) and #G.hand.cards or 0) .. ". "
  do
    local boss_fact = require("context.ctx_blind").blind_debuff_line()
    if boss_fact and boss_fact ~= "" then
      query = query .. "\n" .. boss_fact .. " "
    end
  end
  query = query .. "\nYour move: " .. table.concat(commit_opts, "; ") .. ". "

  return {
    query = query:gsub("  +", " "),
    actions = hand_actions,
    decision_snapshot = {
      transaction_id = nil,
      phase = "proposal",
      context_revision = HandTx.context_revision(),
      run_generation = tonumber(G.NEURO and G.NEURO.run_generation) or 0,
      state_enter_serial = tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0,
      actions = copy_list(hand_actions),
    },
  }
end

local M = { build = build }

if rawget(_G, "NEURO_TEST") then M.boss_state_note = boss_state_note end

return M
