local CardArea = require("facts.card_area_util")
local Utils = require("util.utils")
local clear_area_highlight = CardArea.clear_area_highlight
local add_area_highlight = CardArea.add_area_highlight
local validate_hand_indices = CardArea.validate_hand_indices
local call_gfunc = CardArea.call_gfunc

local M = {}

local function check_blind_size_rule(debuff, count)
  local err = CardArea.blind_size_rule_error(debuff, count)
  if err then return nil, err end
  return true
end

-- `action` is fixed by the caller, never read from payload -- no preview/commit ambiguity
local function commit_hand(data, action)
  if not G.hand or not G.hand.cards then
    return nil, "Hand is not available yet. Wait for the hand screen, then select cards."
  end
  if G.play and G.play.cards and #G.play.cards > 0 then
    return nil, "A hand is still resolving. Wait a moment before selecting again."
  end
  local indices, ierr = validate_hand_indices(data.indices, #G.hand.cards)
  if not indices then
    return nil, ierr
  end

  -- Cerulean Bell's force-selected card stays highlighted through unhighlight_all and always resolves with the hand; reject plays/discards that omit it
  do
    local ok_df, DF = pcall(require, "facts.debuff_facts")
    local fi = ok_df and DF and DF.forced_selection_index and DF.forced_selection_index()
    if fi then
      local included = false
      for _, ix in ipairs(indices) do if ix == fi then included = true break end end
      if not included then
        return nil, string.format("Cerulean Bell force-selected card %d -- it is always part of your hand. Add index %d to your selection.", fi, fi)
      end
    end
  end

  if action == "discard" then
    local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
    if discards_left <= 0 then
      return nil, "No discards remaining. Use play_hand instead."
    end

  elseif action == "play" then
    local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
    if hands_left <= 0 then
      return nil, "No hands remaining. You cannot play cards right now."
    end

    local selected_cards = {}
    for i = 1, #indices do
      local card = G.hand.cards[indices[i]]
      if card then
        selected_cards[#selected_cards + 1] = card
      end
    end

    local blind = G.GAME and G.GAME.blind or nil
    local debuff = blind and not blind.disabled and blind.debuff or nil
    local ok_sz, err_sz = check_blind_size_rule(debuff, #selected_cards)
    if not ok_sz then return nil, err_sz end
  end

  return function()
    clear_area_highlight(G.hand)
    local selected_cards = {}
    for i = 1, #indices do
      local idx = indices[i]
      local card = G.hand.cards[idx]
      if card then
        add_area_highlight(G.hand, card)
        local card_name = Utils.playing_card_label(card)
        table.insert(selected_cards, idx .. ":" .. card_name)
      end
    end

    if #selected_cards == 0 then
      return "Cleared selection (no valid indices)"
    end

    local msg = "Selected cards: " .. table.concat(selected_cards, ", ")

    if action == "play" then
      if #G.hand.highlighted == 0 then
        return msg .. ". No valid cards to play."
      end
      if G.NEURO then
        local pre_hands = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
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
        G.NEURO.last_play = {
          kind = "play", hand_type = ht, played = #G.hand.highlighted, scored = scored,
          pre_chips = (G.GAME and G.GAME.chips) or 0, hands_left_after = pre_hands - 1,
        }
      end
      if not call_gfunc("play_cards_from_highlighted") then
        return msg .. ". Could not play: the play action is unavailable right now."
      end
      local hands_left = G.GAME and G.GAME.current_round and G.GAME.current_round.hands_left or 0
      return msg .. string.format(". Playing hand! Hands remaining: %d", hands_left - 1)
    else
      if #G.hand.highlighted == 0 then
        return msg .. ". No valid cards to discard."
      end
      local discards_left = G.GAME and G.GAME.current_round and G.GAME.current_round.discards_left or 0
      if discards_left <= 0 then
        return msg .. ". Cannot discard: no discards remaining. Use play_hand instead."
      end
      if G.NEURO then
        G.NEURO.last_play = { kind = "discard", played = #G.hand.highlighted }
      end
      if not call_gfunc("discard_cards_from_highlighted") then
        return msg .. ". Could not discard: the discard action is unavailable right now."
      end
      return msg .. string.format(". Discarding! Discards remaining: %d", discards_left - 1)
    end
  end
end

local function handle_play_hand(data)
  return commit_hand(data, "play")
end

local function handle_discard_hand(data)
  return commit_hand(data, "discard")
end

M.handle_play_hand = handle_play_hand
M.handle_discard_hand = handle_discard_hand

return M
