local Actions = require("core.actions")
local HandFacts = require("facts.hand_facts")
local CardUtil = require("facts.card_util")
local FactHints = require("facts.fact_hints")
local ForceHelpers = require("force.force_helpers")
local DebuffFacts = require("facts.debuff_facts")
local blueprint_chain_hint = FactHints.blueprint_chain_hint
local once_per_state_entry_hint = FactHints.once_per_state_entry_hint
local failed_action_warning = ForceHelpers.failed_action_warning

local function build()
  local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
  local disc = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
  if hands_left <= 0 and disc <= 0 then
    return nil
  end

  local structure = HandFacts.summary()
  local bp_chain = blueprint_chain_hint()

  local consumable_hint = ""
  if G.consumeables and G.consumeables.cards then
    local needs = {}
    for i, c in ipairs(G.consumeables.cards) do
      local nm = c and c.ability and c.ability.name or ""
      local min_h, mh = CardUtil.consumable_target_range(c)
      if mh and mh > 0 then
        needs[#needs + 1] = string.format("slot %d '%s' needs %d-%d hand cards", i, nm, min_h, mh)
      end
    end
    if #needs > 0 then
      consumable_hint = once_per_state_entry_hint("consumable_slots",
        "Targeting consumables: " .. table.concat(needs, "; ")
        .. '. use_card|{"area":"consumeables","index":N,"hand_indices":[N,...]}. ')
    end
  end

  local enhanced_in_hand = ""
  if G.hand and G.hand.cards then
    for _, card in ipairs(G.hand.cards) do
      if CardUtil.enhancement_key(card) == "m_glorp" then
        enhanced_in_hand = "Glorpy cards give 10x chips and break at end of round. "
        break
      end
    end
  end

  local framing = "When a hand is Ready, its [..] positions are the exact cards that form it -- play"
    .. " those to get that hand (any type counts). Discards can build toward a Close hand. "
    .. "Use B|NPH as a rough per-hand target: if the strongest Ready hand looks far below NPH,"
    .. " discard toward a stronger Close hand instead of playing a weak Ready hand. "
    .. "If unsure whether a Ready hand can reach NPH, call simulate_hand on those indices before playing. "
  if structure:find("Close:", 1, true) then
    framing = framing .. "Close[..] lists cards to KEEP; to discard, pick the OTHER H: positions. "
  end
  if (G.hand and G.hand.cards and DebuffFacts.count(G.hand.cards) > 0)
    or DebuffFacts.forced_selection_index() then
    framing = framing .. "DB cards score 0; a LOCK card must be in every play or discard. "
  end

  local query = "State: SELECTING_HAND. "
    .. bp_chain
    .. consumable_hint
    .. enhanced_in_hand
  query = query .. failed_action_warning()
  query = query .. structure
  query = query .. framing

  local hand_actions = {}
  local commit_opts = {}
  if hands_left > 0 then
    hand_actions[#hand_actions + 1] = "play_hand"
    commit_opts[#commit_opts + 1] = 'play_hand|{"indices":[N,...]} plays the selected cards as a poker hand (final, uses a hand)'
  end
  if disc > 0 then
    hand_actions[#hand_actions + 1] = "discard_hand"
    commit_opts[#commit_opts + 1] = 'discard_hand|{"indices":[N,...]} discards the selected cards and draws replacements (final, uses a discard)'
  end
  if Actions.is_action_valid("use_card") then
    hand_actions[#hand_actions + 1] = "use_card"
    commit_opts[#commit_opts + 1] = 'use_card|{"area":"consumeables","index":N} uses a consumable now (add "hand_indices":[N,...] for a targeting card)'
  end
  if CardUtil.has_blocked_consumable() then
    query = query .. "Some owned Tarot/Spectral cards create a joker or consumables and need an open output slot; a C: row with ok=N stays blocked until a slot frees. Selling is not available during a round, so free room in the shop (or by using another consumable now). "
  end
  if Actions.is_action_valid("sell_card") then
    hand_actions[#hand_actions + 1] = "sell_card"
    commit_opts[#commit_opts + 1] = 'sell_card|{"area":"jokers|consumeables","index":N} sells a joker or consumable for money'
    query = query .. "sell_card is offered only for edge cases like freeing a slot before a creator consumable; selling a joker mid-round is not base-Balatro behavior. "
  end
  query = query .. "Your move: " .. table.concat(commit_opts, "; ") .. ". "

  local extra = ForceHelpers.collect_actions({ "sort_hand_suit", "sort_hand_value", "set_joker_order" })
  for _, name in ipairs(extra) do hand_actions[#hand_actions + 1] = name end

  return {
    query = query:gsub("  +", " "),
    actions = hand_actions
  }
end

return { build = build }
