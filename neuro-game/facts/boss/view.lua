local M = {}

local function DF()
  local ok, mod = pcall(require, "facts.debuff_facts")
  return ok and mod or nil
end

local function safe_count(cards, pred)
  local n = 0
  if type(cards) ~= "table" then return 0 end
  for _, c in ipairs(cards) do
    if type(c) == "table" and pred(c) then n = n + 1 end
  end
  return n
end

function M.build(blind)
  local df = DF()
  local b = blind or (G and G.GAME and G.GAME.blind) or {}
  local v = {}
  v.blind = b
  v.disabled = not not b.disabled
  v.pareidolia = df and df.owns_joker and df.owns_joker("Pareidolia") or false
  v.smeared = df and df.owns_joker and df.owns_joker("Smeared Joker") or false
  v.probability_normal = tonumber(G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal) or 1
  local hand_cards = G and G.hand and G.hand.cards or nil
  v.hand_n = safe_count(hand_cards, function() return true end)
  v.hand_size = tonumber(G and G.hand and G.hand.config and G.hand.config.card_limit)
  v.joker_n = safe_count(G and G.jokers and G.jokers.cards or nil, function() return true end)
  local cr = G and G.GAME and G.GAME.current_round
  v.hands_left = tonumber(cr and cr.hands_left)
  v.discards_left = tonumber(cr and cr.discards_left)
  v.facedown_jokers = safe_count(G and G.jokers and G.jokers.cards or nil, function(c)
    return c.facing == "back" or (require("facts.card_util").is_face_down(c))
  end)
  v.facedown_in_hand = safe_count(hand_cards, function(c)
    return c.facing == "back" or (require("facts.card_util").is_face_down(c))
  end)
  v.debuffed_in_hand = safe_count(hand_cards, function(c) return not not c.debuff end)
  v.debuffed_card_count = safe_count(G and G.playing_cards or nil, function(c) return not not c.debuff end)
  v.played_this_ante_count = safe_count(G and G.playing_cards or nil, function(c)
    return type(c.ability) == "table" and not not c.ability.played_this_ante
  end)
  v.pillar_used_in_hand = safe_count(hand_cards, function(c)
    return c.debuff and type(c.ability) == "table" and c.ability.played_this_ante
  end)
  do
    local used = {}
    if type(b.hands) == "table" then
      for hn, flag in pairs(b.hands) do
        if flag then used[#used + 1] = (df and df.loc_hand and df.loc_hand(hn)) or tostring(hn) end
      end
    end
    table.sort(used)
    v.eye_used_list = used
    v.eye_used = (#used > 0) and table.concat(used, ", ") or "none"
  end
  v.mouth_locked = (type(b.only_hand) == "string" and b.only_hand ~= "")
    and ((df and df.loc_hand and df.loc_hand(b.only_hand)) or tostring(b.only_hand)) or nil
  v.most_played = df and df.most_played_hand and df.most_played_hand() or nil
  v.deck_n = (G and G.deck and type(G.deck.cards) == "table") and #G.deck.cards or 0
  v.draw_n = math.min(v.deck_n, 3)
  v.lock_index = df and df.forced_selection_index and df.forced_selection_index() or nil
  v.sellable_jokers = safe_count(G and G.jokers and G.jokers.cards or nil, function(c)
    return not (type(c.ability) == "table" and c.ability.eternal)
  end)
  local d = type(b.debuff) == "table" and b.debuff or {}
  v.h_size_ge = tonumber(d.h_size_ge)
  v.h_size_le = tonumber(d.h_size_le)
  v.debuff_suit = d.suit
  return v
end

return M
