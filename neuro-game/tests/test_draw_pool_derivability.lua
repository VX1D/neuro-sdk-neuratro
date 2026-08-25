_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("tests.helpers")
local CtxHand = require("context.ctx_hand")
local check, done = H.harness("draw pool derivability")

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

local function board(hidden_key, decorate)
  local by, pile = {}, {}
  _G.G = { GAME = { current_round = {} }, FUNCS = {},
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = pile }, playing_cards = {} }
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do by[v .. s] = card(v, s) end
  end
  if decorate then decorate(by) end
  local visible = { by["AHearts"], by["QHearts"], by["JHearts"], by["9Hearts"],
                    by["7Spades"], by["5Diamonds"], by["3Spades"] }
  local hidden = by[hidden_key]
  hidden.facing = "back"
  hidden.ability.wheel_flipped = true   -- cardarea.lua:59
  local in_hand = {}
  for _, c in ipairs(visible) do in_hand[#in_hand + 1] = c; c.area = G.hand end
  in_hand[#in_hand + 1] = hidden
  hidden.area = G.hand
  G.hand.cards = in_hand
  local seen = {}
  for _, c in ipairs(in_hand) do seen[c] = true end
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do
      local c = by[v .. s]
      if not seen[c] then pile[#pile + 1] = c; c.area = G.deck end
    end
  end
  for _, c in ipairs(in_hand) do G.playing_cards[#G.playing_cards + 1] = c end
  for _, c in ipairs(pile) do G.playing_cards[#G.playing_cards + 1] = c end
  return CtxHand.draw_composition_section(), #pile
end

local a, pile_n = board("KClubs")
local b = board("2Clubs")
check("swapping which of two cards is face down changes no byte of the draw composition",
  a == b, "[" .. tostring(a) .. "]\nvs\n[" .. tostring(b) .. "]")
check("the pile really is 44 cards, so the census below is over 45", pile_n == 44, tostring(pile_n))
check("the hidden card is counted into the pool, not subtracted out of it",
  a:find("K x4", 1, true) ~= nil and a:find("2 x4", 1, true) ~= nil, a)
check("the reader is told the pool is one larger than the pile (UI_definitions.lua:3623-3627)",
  a:find("(45 cards tallied: the 44 in the pile plus 1 face-down hand card the game counts as unplayed.)",
    1, true) ~= nil, a)

local function steel(which)
  return function(by)
    by[which].config.center = { key = "m_steel", set = "Enhanced" }
    by[which].ability.name = "Steel Card"
  end
end
local sa = board("KClubs", steel("KClubs"))
local sb = board("2Clubs", steel("KClubs"))
check("a Steel card face down in hand is still tallied as unseen",
  sa == sb, "[" .. tostring(sa) .. "]\nvs\n[" .. tostring(sb) .. "]")
check("and the enhancement clause is present in both, not dropped from both",
  sa:find("Modifiers in that pool: enhancements Steel x1", 1, true) ~= nil, sa)

do
  local visible_a = board("KClubs")
  G.hand.cards[8].facing = "front"
  G.hand.cards[8].ability.wheel_flipped = nil
  local plain = CtxHand.draw_composition_section()
  check("all-visible hand: the pool is the pile alone",
    plain:find("K x3", 1, true) ~= nil and plain:find("2 x4", 1, true) ~= nil, plain)
  check("all-visible hand: no flipped-card note",
    plain:find("face-down hand card", 1, true) == nil, plain)
  check("all-visible hand: the masked board and the plain board really do differ",
    visible_a ~= plain, "identical")
end

done()
