local M = {}
local CardUtil = require("facts.card_util")
local PublicCard = require("facts.public_card_identity")
local count = require("facts.text").count

local DF = require("facts.boss.model").debuff_facts

local function any() return true end
local function hidden(c) return CardUtil.is_hidden(c) end
local function safe_count(cards, pred)
  return count(cards, function(c) return type(c) == "table" and pred(c) end)
end

local function public_count(cards, pred)
  return safe_count(cards, function(c) return PublicCard.is_public(c) and pred(c) end)
end

function M.build(blind)
  local df = DF()
  local b = blind or (G and G.GAME and G.GAME.blind) or {}
  local v = {}
  v.blind = b
  v.disabled = not not b.disabled
  v.pareidolia = df.owns_joker("Pareidolia")
  v.smeared = df.owns_joker("Smeared Joker")
  local hand_cards = G and G.hand and G.hand.cards or nil
  v.hand_n = safe_count(hand_cards, any)
  v.hand_size = tonumber(G and G.hand and G.hand.config and G.hand.config.card_limit)
  v.joker_n = safe_count(G and G.jokers and G.jokers.cards or nil, any)
  -- Crimson Heart lifts its last target, then chooses only among non-debuffed jokers.
  v.heart_pool = safe_count(G and G.jokers and G.jokers.cards or nil, function(c)
    return hidden(c) or not c.debuff or (type(c.ability) == "table" and c.ability.crimson_heart_chosen) or false
  end)
  local cr = G and G.GAME and G.GAME.current_round
  v.hands_left = tonumber(cr and cr.hands_left)
  v.discards_left = tonumber(cr and cr.discards_left)
  v.facedown_jokers = safe_count(G and G.jokers and G.jokers.cards or nil, hidden)
  v.facedown_in_hand = safe_count(hand_cards, hidden)
  v.debuffed_card_count = safe_count(G and G.playing_cards or nil, function(c) return not not c.debuff end)
  v.played_this_ante_count = safe_count(G and G.playing_cards or nil, function(c)
    return type(c.ability) == "table" and not not c.ability.played_this_ante
  end)
  v.pillar_used_in_hand = public_count(hand_cards, function(c)
    return c.debuff and type(c.ability) == "table" and c.ability.played_this_ante
  end)
  do
    local used = {}
    if type(b.hands) == "table" then
      for hn, flag in pairs(b.hands) do
        if flag then used[#used + 1] = df.loc_hand(hn) or tostring(hn) end
      end
    end
    table.sort(used)
    v.eye_used = (#used > 0) and table.concat(used, ", ") or "none"
  end
  v.mouth_locked = (type(b.only_hand) == "string" and b.only_hand ~= "")
    and (df.loc_hand(b.only_hand) or tostring(b.only_hand)) or nil
  v.most_played = df.most_played_hand()
  v.deck_n = (G and G.deck and type(G.deck.cards) == "table") and #G.deck.cards or 0
  v.draw_n = math.min(v.deck_n, 3)
  v.lock_index = df.forced_selection_index()
  v.sellable_jokers = public_count(G and G.jokers and G.jokers.cards or nil, function(c)
    return not (type(c.ability) == "table" and c.ability.eternal)
  end)
  return v
end

return M
