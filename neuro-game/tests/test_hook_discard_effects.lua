require("tests.stubs").setup({ love = "lazy", localize = true })

-- The Hook’s forced discard fires discard context for each card, removing Green Joker mult before scoring.
local check, done = require("tests.helpers").harness("hook-discard-effects")
local Vanilla = require("tests.fixtures.vanilla_jokers")
local EC = require("tests.engine_cards")
local CtxJokers = require("context.ctx_jokers")
local HF = require("facts.hand_facts")

local HOOK = { name = "The Hook", key = "bl_hook", config = { blind = { key = "bl_hook" } }, disabled = false,
  in_blind = true }

local function board(jokers, hand_specs, opts)
  opts = opts or {}
  local states = EC.states()
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = states.SELECTING_HAND, STATES = states,
    GAME = { round = 3, dollars = 4, round_resets = { ante = 1 }, probabilities = { normal = 1 },
      current_round = { hands_left = 2, discards_left = 0, discards_used = 4, hands_played = 2,
        castle_card = { suit = "Spades" } },
      hands = { ["Two Pair"] = { visible = true, level = 1, chips = 20, mult = 2, played = 1, played_this_round = 1 },
        Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 1, played_this_round = 0 } },
      blind = HOOK },
    NEURO = { once_serials = {}, jokers_sold_run = 0 },
    hand = { cards = {}, config = { card_limit = 8, highlighted_limit = 5 }, highlighted = {} },
    deck = { cards = {} }, discard = { cards = {} }, playing_cards = {},
    jokers = { cards = jokers, config = { card_limit = 5 } },
    FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").engine() },
  }
  for _, s in ipairs(hand_specs) do
    local c = EC.playing(s[1], s[2], { facing = s.down and "back" or "front" })
    c.area = G.hand
    G.hand.cards[#G.hand.cards + 1] = c
    G.playing_cards[#G.playing_cards + 1] = c
  end
end

local HAND = { { "Ace", "Clubs" }, { "10", "Spades" }, { "7", "Spades" }, { "7", "Hearts" }, { "5", "Diamonds" },
  { "3", "Spades" }, { "2", "Clubs" }, { "2", "Diamonds" } }

local function green(mult)
  local j = Vanilla.card("j_green_joker", 2)
  j.ability.mult = mult
  return j
end

board({ Vanilla.card("j_flash", 1), green(1) }, HAND)
local text = CtxJokers.jokers_section("SELECTING_HAND") or ""
check("L109: with no play chosen yet every play leaves cards for The Hook, so Green Joker pays +1, not +2",
  text:find("Green Joker +1 Mult -- The Hook's discard before scoring takes it down 1 Mult first (not below 0),"
    .. " then it gains +1 Mult before every hand pays", 1, true) ~= nil, text)

local hand = G.hand.cards
local chain = HF.joker_chain_prose(HF.joker_chain({ hand[3], hand[4], hand[7], hand[8] }, "Two Pair"))
check("L107: the Two Pair's joker chain pays +1 Mult", chain == "then jokers left to right: joker 2 +1 mult", chain)

board({ Vanilla.card("j_flash", 1), green(0) }, HAND)
local zero = HF.joker_chain_prose(HF.joker_chain({ G.hand.cards[3], G.hand.cards[4] }, "Pair"))
check("at +0 the discard cannot take it lower, so it still pays +1", zero == "then jokers left to right: joker 2 +1 mult", zero)

local Scoring = require("util.scoring")
local function castle_row(led)
  for _, r in ipairs(led.rows) do
    if r.gate and r.gate.text == "it gains Chips for each card of its suit The Hook discards before scoring" then return r end
  end
  return nil
end
do
  local castle = Vanilla.card("j_castle", 1)
  castle.ability.extra = { chips = 30, chip_mod = 3 }
  board({ castle }, HAND)
  local h = G.hand.cards
  local row = castle_row(Scoring.joker_summary({ h[3], h[4], h[7], h[8] }).ledger)
  local led = Scoring.joker_summary({ h[3], h[4], h[7], h[8] }).ledger
  check("Castle under The Hook: its +30 always pays, the growth is at most +6 Chips, never a guess of which cards go",
    led.always.chips.n == 30 and row and row.at_score == nil and row.total and row.total.k == "at_most"
      and row.total.n == 6,
    row and row.total and (tostring(led.always.chips.n) .. " " .. tostring(row.total.k) .. " " .. tostring(row.total.n)))
end

do
  local function castle_ledger(hidden_suit)
    local castle = Vanilla.card("j_castle", 1)
    castle.ability.extra = { chips = 30, chip_mod = 3 }
    local specs = {}
    for i, s in ipairs(HAND) do specs[i] = { s[1], s[2] } end
    specs[1] = { "Ace", hidden_suit, down = true }
    board({ castle }, specs)
    local h = G.hand.cards
    return Scoring.joker_summary({ h[3], h[4], h[7], h[8] }).ledger
  end
  local la, lb = castle_ledger("Spades"), castle_ledger("Hearts")
  local ra, rb = castle_row(la), castle_row(lb)
  check("a face-down held card leaves Castle's growth with no figure, whatever the card is",
    ra == nil and rb == nil and la.always.chips.n == 30 and lb.always.chips.n == 30
      and la.refused[1] and la.refused[1].name == "Castle", tostring(la.refused[1] and la.refused[1].name))
  check("and what is said does not depend on the hidden suit",
    #la.refused == #lb.refused and la.refused[1] and lb.refused[1] and la.refused[1].reason == lb.refused[1].reason,
    tostring(la.refused[1] and la.refused[1].reason))
end

local rule = require("facts.boss.model").RECORDS.bl_hook.rule
check("the boss rule says its discards fire on-discard effects, and names Burnt Joker's exception",
  rule:find("yet they fire on-discard effects such as Green Joker", 1, true) ~= nil
    and rule:find("(Burnt Joker ignores them)", 1, true) ~= nil, rule)

done()
