local ES = require("tests.engine_cards").states()
rawset(_G, "NEURO_TEST", true)
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("tests.helpers")
local HandHandlers = require("handlers.hand_handlers")
local check, done = H.harness("review hidden selection ceiling")

local sid = 0
local function card(v, suit)
  sid = sid + 1
  local c = require("tests.engine_cards").playing(H.VALN[v] or v, suit, { sort_id = sid })
  c.cost, c.sell_cost = 1, 1
  return c
end

local function joker(key, name, ability, desc)
  sid = sid + 1
  ability = ability or {}
  ability.name, ability.set = name, "Joker"
  return { sort_id = sid, cost = 5, sell_cost = 2, ability = ability, facing = "front",
    config = { center = { key = key, set = "Joker", name = name, rarity = 1,
      loc_txt = { name = name, description = { desc or "" } } } },
    is_rarity = function(_, r) return r == "Common" end }
end

local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local function base_G()
  local deck, by = {}, {}
  for _, s in ipairs(SUITS) do
    for _, v in ipairs(RANKS) do
      local c = card(v, s)
      deck[#deck + 1] = c
      by[v .. s] = c
    end
  end
  _G.G = {
    NEURO = { run_generation = 1 }, STATE = ES.SELECTING_HAND, STATES = ES,
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = deck }, playing_cards = deck,
    FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").engine() },
    GAME = { dollars = 20, chips = 0, hands = {}, probabilities = { normal = 1 },
      blind = { name = "Big Blind", chips = 600, debuff = {}, disabled = false,
        get_type = function() return "Big" end },
      current_round = { hands_left = 4, discards_left = 0 } },
  }
  return by
end

local function review(sel, indices)
  local ask, _, facts = HandHandlers.play_review_reason(sel, indices)
  return require("context.state_doc").lines(facts, ask)
end

local function baron_play(hidden_key, extra)
  local by = base_G()
  local roster = { joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult") }
  if extra then roster[#roster + 1] = extra() end
  for _, j in ipairs(roster) do j.area = G.jokers end
  G.jokers.cards = roster
  local hidden = by[hidden_key]
  hidden.facing = "back"
  G.hand.cards = { by["KSpades"], by["KClubs"], hidden, by["4Diamonds"], by["7Hearts"], by["9Spades"] }
  return review({ G.hand.cards[1], G.hand.cards[2], G.hand.cards[3] }, { 1, 2, 3 })
end

local base = baron_play("2Hearts")
check("no King is held, so the review prices no Baron ceiling", base:find("x5.06", 1, true) == nil
  and base:find("Baron", 1, true) == nil, base)
check("the joker sentence never opens on a dangling 'and'", base:find("-- and", 1, true) == nil, base)

local differs = {}
for _, key in ipairs({ "KHearts", "KDiamonds", "QHearts", "AHearts", "5Clubs", "10Diamonds", "2Diamonds" }) do
  local text = baron_play(key)
  if text ~= base then differs[#differs + 1] = key .. ": " .. text end
end
check("the review text does not change with the face-down card's identity", #differs == 0,
  table.concat(differs, " || "))

local function held_king(hidden_key)
  local by = base_G()
  local baron = joker("j_baron", "Baron", { extra = 1.5 }, "Each King held in hand gives X1.5 Mult")
  baron.area = G.jokers
  G.jokers.cards = { baron }
  local hidden = by[hidden_key]
  hidden.facing = "back"
  G.hand.cards = { by["KSpades"], by["KClubs"], hidden, by["KHearts"], by["7Hearts"] }
  return review({ G.hand.cards[1], G.hand.cards[2], G.hand.cards[3] }, { 1, 2, 3 })
end
local held = held_king("2Hearts")
check("a held public King draws no deck-wide Baron ceiling",
  held:find("at most", 1, true) == nil and held:find("such cards in your deck", 1, true) == nil, held)
check("and that text is the same whatever card is face down",
  held_king("KDiamonds") == held and held_king("QSpades") == held, held)

local function trib()
  return joker("j_triboulet", "Triboulet", { extra = 2 }, "Played Kings and Queens each give X2 Mult when scored")
end
local t = baron_play("2Hearts", trib)
check("a ceiling with no ordered chain reads 'Your jokers on this hand add at most ...'",
  t:find("Your jokers on this hand add at most x", 1, true) ~= nil and t:find("in scoring order --", 1, true) == nil, t)
check("and it is the same whatever card is face down", baron_play("QDiamonds", trib) == t
  and baron_play("KHearts", trib) == t, t)

done()
