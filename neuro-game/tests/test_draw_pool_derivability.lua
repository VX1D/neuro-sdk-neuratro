require("tests.stubs").setup({ love = "lazy" })

local H = require("tests.helpers")
local CtxHand = require("context.ctx_hand")
local PublicCard = require("facts.public_card_identity")
local HandFacts = require("facts.hand_facts")
local Legality = require("facts.boss.legality")
local HandHandlers = require("handlers.hand_handlers")
local check, done = H.harness("draw pool derivability")

local RANKS = { "2","3","4","5","6","7","8","9","10","J","Q","K","A" }
local SUITS = { "Spades","Hearts","Clubs","Diamonds" }

local card = require("tests.fake_cards").deck_maker()

local function board(hidden_key, decorate, wheel_only)
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
  hidden.facing = wheel_only and "front" or "back"
  hidden.ability.wheel_flipped = true
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
      -- Every card in the deck area is face down.
      if not seen[c] then pile[#pile + 1] = c; c.area = G.deck; c.facing = "back" end
    end
  end
  for _, c in ipairs(in_hand) do G.playing_cards[#G.playing_cards + 1] = c end
  for _, c in ipairs(pile) do G.playing_cards[#G.playing_cards + 1] = c end
  return CtxHand.draw_composition_section()
end

local a = board("KClubs")
local b = board("2Clubs")
check("face-down deck-area cards still yield the composition in a normal round",
  a ~= nil and b ~= nil, "[" .. tostring(a) .. "]\nvs\n[" .. tostring(b) .. "]")
check("a concealed hand card is counted into the pool, not set aside as unknown",
  a:find("excluded from the tally", 1, true) == nil
    and b:find("excluded from the tally", 1, true) == nil,
  tostring(a) .. "\nvs\n" .. tostring(b))
check("every rank in the pool is tallied, held or not",
  a:find("K x4", 1, true) ~= nil and b:find("K x4", 1, true) ~= nil
    and b:find("2 x4", 1, true) ~= nil,
  tostring(a) .. "\nvs\n" .. tostring(b))

local function steel(which)
  return function(by)
    by[which].config.center = { key = "m_steel", set = "Enhanced" }
    by[which].ability.name = "Steel Card"
  end
end
local sa = board("KClubs", steel("KClubs"))
local sb = board("2Clubs", steel("KClubs"))
check("a concealed hand card's enhancement is part of the public composition",
  sa:find("enhancements Steel x1", 1, true) ~= nil
    and sa:find("excluded from the tally", 1, true) == nil,
  tostring(sa))
check("a Steel card in the deck area is public modifier composition",
  sb:find("enhancements Steel x1", 1, true) ~= nil, tostring(sb))

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

local function wheel_hand(rank)
  board(rank .. "Clubs", nil, true)
  local ten = G.hand.cards[5]
  ten.base.value, ten.base.id, ten.base.nominal = "10", 10, 10
  G.FUNCS.get_poker_hand_info = function(cards)
    local has_king = false
    for _, c in ipairs(cards or {}) do
      if c.base and c.base.value == "King" then has_king = true end
    end
    if has_king then return "Straight", {}, { Straight = cards } end
    return "High Card", {}, {}
  end
  local hidden = G.hand.cards[8]
  return {
    token = CtxHand.card_token(hidden, true),
    summary = require("context.context_readable").structure_prose(HandFacts.structure()),
    ready = HandFacts.has_strong_ready(),
    public = PublicCard.is_public(hidden),
    label = PublicCard.label(hidden, "hand", 8),
    identity = PublicCard.multiset_key(hidden, "hand", 8),
    legal_hidden = Legality.selection_hidden({ hidden }),
  }
end

local wheel_k = wheel_hand("K")
local wheel_2 = wheel_hand("2")
check("front-facing wheel-only cards use the hidden hand token",
  wheel_k.token == "face-down (hidden)" and wheel_2.token == wheel_k.token,
  tostring(wheel_k.token) .. "/" .. tostring(wheel_2.token))
check("front-facing wheel-only card identity is withheld",
  wheel_k.public == false and wheel_k.label == "face-down item #8 in hand"
    and wheel_k.identity == "hidden:hand:8",
  tostring(wheel_k.public) .. "/" .. tostring(wheel_k.label) .. "/" .. tostring(wheel_k.identity))
check("wheel-only hidden rank cannot alter the hand prose or readiness",
  wheel_k.summary == wheel_2.summary and wheel_k.summary:find("face-down (hidden)", 1, true) ~= nil
    and wheel_k.summary:find("King", 1, true) == nil
    and wheel_k.ready == false and wheel_2.ready == false,
  tostring(wheel_k.summary) .. "\nvs\n" .. tostring(wheel_2.summary))
check("legality treats a front-facing wheel-only selection as hidden",
  wheel_k.legal_hidden == true and wheel_2.legal_hidden == true,
  tostring(wheel_k.legal_hidden) .. "/" .. tostring(wheel_2.legal_hidden))

local function wheel_confirmation(rank)
  board(rank .. "Clubs", nil, true)
  G.NEURO = { run_generation = 1, decision_serial = 1 }
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  G.GAME.current_round = { hands_left = 3, discards_left = 1 }
  G.FUNCS.get_poker_hand_info = require("tests.helpers").poker_hand_info("Pair")
  local hidden = G.hand.cards[8]
  local ask, _, facts = HandHandlers.play_review_reason({ G.hand.cards[1], hidden }, { 1, 8 })
  return require("context.state_doc").lines(facts, ask)
end

local confirm_k = wheel_confirmation("K")
local confirm_2 = wheel_confirmation("2")
check("confirmation does not derive a front-facing wheel-only card's identity",
  confirm_k == confirm_2, tostring(confirm_k) .. "\nvs\n" .. tostring(confirm_2))
check("confirmation masks hand type and values for wheel-only hidden selection",
  confirm_k:find("Selection [1,8] = hand type hidden: it includes a face-down card", 1, true) ~= nil
    and confirm_k:find("face down", 1, true) ~= nil
    and confirm_k:find("King", 1, true) == nil
    and confirm_k:find("2", 1, true) == nil,
  tostring(confirm_k))

done()
