_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("tests.helpers")
local HandFacts = require("facts.hand_facts")
local check, done = H.harness("draw note derivability")

local RANKS = { "2","3","4","5","6","7","8","9","10","J","Q","K","A" }
local SUITS = { "Spades","Hearts","Clubs","Diamonds" }

local sid = 0
local function card(v, suit)
  sid = sid + 1
  local id = H.RID[v]
  local c = {
    base = { value = H.VALN[v] or v, suit = suit, id = id, nominal = (id <= 10 and id or 10) },
    sort_id = sid, ability = { set = "Default", name = "Base", effect = "" },
    config = { center = { key = "c_base", set = "Default" } }, facing = "front",
  }
  c.is_suit = function(_, s) return s == suit end
  c.get_id = function(self) return self.base.id end
  return c
end

local function real_phi(list)
  local by_rank, ranks, by_suit, suits = {}, {}, {}, {}
  for _, c in ipairs(list or {}) do
    local v, u = c.base.id, c.base.suit
    if not by_rank[v] then by_rank[v] = {}; ranks[#ranks + 1] = v end
    by_rank[v][#by_rank[v] + 1] = c
    if not by_suit[u] then by_suit[u] = {}; suits[#suits + 1] = u end
    by_suit[u][#by_suit[u] + 1] = c
  end
  local function hit(name, set) return name, nil, { [name] = set }, set, nil end
  for _, u in ipairs(suits) do
    local set = by_suit[u]
    if #set >= 5 then return hit("Flush", { set[1], set[2], set[3], set[4], set[5] }) end
  end
  for _, v in ipairs(ranks) do
    if #by_rank[v] >= 3 then
      local s = by_rank[v]; return hit("Three of a Kind", { s[1], s[2], s[3] })
    end
  end
  for _, v in ipairs(ranks) do
    if #by_rank[v] >= 2 then local s = by_rank[v]; return hit("Pair", { s[1], s[2] }) end
  end
  return "High Card", nil, {}, {}, nil
end

local function board(hidden_key, face_up)
  local by, pile = {}, {}
  _G.G = { GAME = { current_round = { discards_left = 2, hands_left = 3 } },
    FUNCS = { get_poker_hand_info = real_phi },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = pile }, playing_cards = {} }
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do by[v .. s] = card(v, s) end
  end
  local visible = { by["AHearts"], by["QHearts"], by["JHearts"], by["9Hearts"],
                    by["7Spades"], by["5Diamonds"], by["3Spades"] }
  local hidden = by[hidden_key]
  if not face_up then
    hidden.facing = "back"
    hidden.ability.wheel_flipped = true   -- cardarea.lua:59
  end
  local in_hand, seen = {}, {}
  for _, c in ipairs(visible) do in_hand[#in_hand + 1] = c; c.area = G.hand; seen[c] = true end
  in_hand[#in_hand + 1] = hidden
  hidden.area = G.hand
  seen[hidden] = true
  G.hand.cards = in_hand
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do
      local c = by[v .. s]
      if not seen[c] then pile[#pile + 1] = c; c.area = G.deck end
    end
  end
  for _, c in ipairs(in_hand) do G.playing_cards[#G.playing_cards + 1] = c end
  for _, c in ipairs(pile) do G.playing_cards[#G.playing_cards + 1] = c end
  local pile_hearts = 0
  for _, c in ipairs(pile) do if c.base.suit == "Hearts" then pile_hearts = pile_hearts + 1 end end
  HandFacts._set_shuffle(function(l) return l end)
  local s = HandFacts.summary()
  HandFacts._set_shuffle(nil)
  return s, pile_hearts
end

local heart_hidden, heart_pile = board("KHearts")   -- pile keeps 8 hearts, the K is face down
local club_hidden,  club_pile  = board("2Clubs")    -- pile keeps 9 hearts, the 2 is face down

check("the two boards' piles really differ, so a pile-derived out count could not be equal",
  heart_pile == 8 and club_pile == 9, heart_pile .. " vs " .. club_pile)
check("out counts do not reveal the suit of the face-down hand card",
  heart_hidden == club_hidden, "[" .. heart_hidden .. "]\nvs\n[" .. club_hidden .. "]")

local face_up = board("4Clubs", true)
check("nothing face down: the near-Flush odds are still published",
  face_up:find("(draw ", 1, true) ~= nil, face_up)
check("the flipped board reached the same near-Flush row, minus the odds",
  heart_hidden:find("near Flush", 1, true) ~= nil
    and heart_hidden:find("(draw ", 1, true) == nil, heart_hidden)

done()
