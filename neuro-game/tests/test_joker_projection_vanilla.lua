_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("joker-projection-vanilla")
local Vanilla = require("tests.fixtures.vanilla_jokers")
local CardSemantics = require("facts.card_semantics")
local JokerHits = require("core.joker_hits")

local function playing_card(id, suit, sort_id)
  return {
    sort_id = sort_id,
    base = { id = id, suit = suit, nominal = math.min(id, 10) },
    get_id = function(self) return self.base.id end,
    is_suit = function(self, s) return self.base.suit == s end,
    is_face = function(self) return self.base.id >= 11 and self.base.id <= 13 end,
  }
end

local function full_deck()
  local deck, n = {}, 0
  for _, suit in ipairs({ "Hearts", "Diamonds", "Spades", "Clubs" }) do
    for id = 2, 14 do
      n = n + 1
      deck[n] = playing_card(id, suit, 500 + n)
    end
  end
  return deck
end

local function board(cards, held)
  local deck = full_deck()
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1, SHOP = 5 },
    GAME = { round = 1, dollars = 8, round_resets = { ante = 2 },
      probabilities = { normal = 1 }, hands = {} },
    NEURO = { once_serials = {}, jokers_sold_run = 0 },
    deck = { cards = deck },
    playing_cards = deck,
    hand = { cards = held or {}, config = { card_limit = 8 } },
    jokers = { cards = cards or {}, config = { card_limit = 5 } },
  }
end
board({})

check("the fixture carries the whole vanilla joker pool", #Vanilla.keys() == 150, #Vanilla.keys())
do
  local bb = Vanilla.card("j_blackboard", 1)
  check("V0a set_ability puts the value in ability.extra and leaves x_mult at 1",
    bb.ability.x_mult == 1 and bb.ability.extra == 3,
    tostring(bb.ability.x_mult) .. "/" .. tostring(bb.ability.extra))
end

local function effects_of(key)
  return CardSemantics.project(Vanilla.card(key, 1)).effects
end

local function single(key, kind, value, certainty, hand_type)
  local found = nil
  for _, e in ipairs(effects_of(key)) do
    if e.kind == kind and e.value == value and e.certainty == certainty
      and e.hand_type == hand_type then found = e end
  end
  return found ~= nil
end

local function has_kind(key, kind)
  for _, e in ipairs(effects_of(key)) do
    if e.kind == kind then return true end
  end
  return false
end

local BARE_EXTRA_XMULT = {
  { "j_blackboard", 3 }, { "j_baron", 1.5 }, { "j_photograph", 2 }, { "j_baseball", 1.5 },
  { "j_ancient", 1.5 }, { "j_acrobat", 3 }, { "j_idol", 2 }, { "j_drivers_license", 3 },
  { "j_triboulet", 2 },
}
for _, spec in ipairs(BARE_EXTRA_XMULT) do
  check("" .. spec[1] .. " projects its conditional x" .. spec[2] .. " Mult",
    single(spec[1], "xmult", spec[2], "conditional", nil),
    #effects_of(spec[1]) .. " effects")
end

local BARE_EXTRA_NOT_XMULT = {
  "j_even_steven", "j_odd_todd", "j_scary_face", "j_hiker", "j_credit_card",
  "j_ride_the_bus", "j_blue_joker", "j_smiley", "j_arrowhead",
}
for _, key in ipairs(BARE_EXTRA_NOT_XMULT) do
  check("" .. key .. " gets no xMult invented out of its bare extra",
    not has_kind(key, "xmult"), key)
end

check("V3a Crafty Joker keeps its Flush-gated +80 Chips",
  single("j_crafty", "chips", 80, "conditional", "Flush"))
check("V3b a plain Joker keeps its unconditional +4 Mult",
  single("j_joker", "mult", 4, "guaranteed", nil))
check("V3c Jolly Joker keeps its Pair-gated +8 Mult",
  single("j_jolly", "mult", 8, "conditional", "Pair"))
check("V3d Cavendish keeps its guaranteed x3 Mult",
  single("j_cavendish", "xmult", 3, "guaranteed", nil))
check("V3e Card Sharp keeps its conditional x3 Mult from extra.Xmult",
  single("j_card_sharp", "xmult", 3, "conditional", nil))

-- Yorick's accumulator is ability.x_mult (SMODS.scale_card ref_value, card.lua:3173-3181);
-- ability.extra.xmult is the per-tick increment and is 1 on a fresh card, so a projection keyed on
-- the wrong field reads "no effect" mid-run and would read "X1" as a bonus on a fresh one.
do
  local fresh = Vanilla.card("j_yorick", 1)
  local played = Vanilla.card_played("j_yorick", 1)
  check("V3f the Yorick fixture really keeps its increment in extra.xmult and its total in x_mult",
    fresh.ability.extra.xmult == 1 and played.ability.x_mult == 1.5,
    tostring(fresh.ability.extra.xmult) .. "/" .. tostring(played.ability.x_mult))
  local acc
  for _, e in ipairs(CardSemantics.project(played).effects) do
    if e.kind == "xmult" then acc = e end
  end
  check("V3g Yorick projects the accumulator in ability.x_mult, not the increment in extra.xmult",
    acc ~= nil and acc.rate == 1.5 and acc.certainty == "guaranteed",
    acc and (tostring(acc.rate) .. "/" .. acc.certainty) or "no xmult row")
  check("V3h a fresh Yorick projects no xMult at all (its increment is not a bonus)",
    #CardSemantics.project(fresh).effects == 0, #CardSemantics.project(fresh).effects)
end

do
  local projected, conditional, errors = 0, 0, 0
  for _, key in ipairs(Vanilla.keys()) do
    local card = Vanilla.card(key, 1)
    local ok, proj = pcall(CardSemantics.project, card)
    if not (ok and type(proj) == "table" and type(proj.effects) == "table") then
      errors = errors + 1
    else
      if #proj.effects > 0 then projected = projected + 1 end
    end
    if JokerHits._test.has_condition(card) then conditional = conditional + 1 end
  end
  check("V4a every vanilla joker projects without error", errors == 0, errors)
  check("V4b at least 56 of the 150 vanilla jokers project a numbered effect",
    projected >= 56, projected)
  local gated = 0
  for _, key in ipairs(Vanilla.keys()) do
    for _, e in ipairs(CardSemantics.project(Vanilla.card(key, 1)).effects) do
      if e.gate then gated = gated + 1 break end
    end
  end
  check("V4c at least 110 of them are recognised as having a condition",
    conditional >= 110, conditional)
  check("V4d a gate is declared data, so at least 30 jokers carry one on a row",
    gated >= 30, gated)
end

do
  local Jokers = require("context.ctx_jokers")
  local function summary_line(cards)
    board(cards)
    local out = select(2, pcall(Jokers.jokers_section, "SELECTING_HAND")) or ""
    for line in tostring(out):gmatch("[^\n]+") do
      if line:find("^Joker bonuses") then return line end
    end
    return ""
  end

  local line = summary_line({
    Vanilla.card("j_blue_joker", 1), Vanilla.card("j_blackboard", 2),
    Vanilla.card("j_baron", 3), Vanilla.card("j_crafty", 4),
  })
  check("V5a the always-on total is named as always-on",
    line:find("always on +104 Chips", 1, true) ~= nil, line)
  check("V5b the hand-type conditional is on the line",
    line:find("if the hand contains a Flush: +80 Chips", 1, true) ~= nil, line)
  check("V5c the ceiling raises the per-held rate by the count the board allows",
    line:find("at most x15.19 Mult more from jokers gated on something other than the hand type", 1, true) ~= nil,
    line)
  check("V5c-src the ceiling names where its count came from",
    line:find("Baron x5.06 Mult -- 4 such cards in your deck, and you hold at most 8", 1, true) ~= nil,
    line)

  local kingless = {
    Vanilla.card("j_blue_joker", 1), Vanilla.card("j_blackboard", 2),
    Vanilla.card("j_baron", 3), Vanilla.card("j_crafty", 4),
  }
  board(kingless)
  local kept = {}
  for _, c in ipairs(G.playing_cards) do if c.base.id ~= 13 then kept[#kept + 1] = c end end
  G.playing_cards = kept
  G.deck.cards = kept
  local no_kings = ""
  for l in tostring(select(2, pcall(Jokers.jokers_section)) or ""):gmatch("[^\n]+") do
    if l:find("^Joker bonuses") then no_kings = l end
  end
  check("V5e the ceiling is a function of the board, not a constant",
    no_kings:find("at most x3 Mult more from jokers gated", 1, true) ~= nil
      and no_kings:find("Baron", 1, true) == nil, no_kings)
  check("V5d the line no longer promises that its number covers the conditionals",
    line:find("conditional jokers add only when their condition fires", 1, true) == nil, line)

  local cond = summary_line({ Vanilla.card("j_blackboard", 1) })
  check("V5f a conditional xMult reaches the line as a ceiling, not as a bare rate",
    cond:find("at most", 1, true) ~= nil and cond:find("(conditional)", 1, true) == nil, cond)
  check("V5f and it never leaks into the always-on total beside it",
    cond:find("always on", 1, true) == nil
      and cond:find("x3", 1, true) > cond:find("at most", 1, true), cond)
  local flat = summary_line({ Vanilla.card("j_joker", 1) })
  check("V5g a guaranteed bonus is stated flat, with no ceiling language",
    flat:find("always on +4 Mult", 1, true) ~= nil and flat:find("at most", 1, true) == nil, flat)

  local five = summary_line({
    Vanilla.card("j_baron", 1), Vanilla.card("j_triboulet", 2), Vanilla.card("j_bloodstone", 3),
    Vanilla.card("j_arrowhead", 4), Vanilla.card("j_photograph", 5),
  })
  for _, name in ipairs({ "Baron", "Triboulet", "Bloodstone", "Arrowhead", "Photograph" }) do
    check("V5f the ceiling names source '" .. name .. "' rather than eliding it",
      five:find(name, 1, true) ~= nil, five)
  end
  check("V5g no source is elided behind an 'and N more' tail",
    five:find(" more)", 1, true) == nil and five:find("; and ", 1, true) == nil, five)

  local solo = summary_line({ Vanilla.card("j_crafty", 1) })
  check("a single conditional joker still reaches the summary",
    solo:find("if the hand contains a Flush: +80 Chips", 1, true) ~= nil, solo)
end

do
  local Scoring = require("util.scoring")
  local Jokers = require("context.ctx_jokers")

  local function led(cards, held, selection)
    board(cards, held)
    for _, c in ipairs(cards) do c.area = G.jokers end
    G.FUNCS = { get_poker_hand_info = function(sel) return "Pair", nil, {}, sel end }
    local s = Scoring.joker_summary(selection)
    return s and s.ledger
  end
  local function n_of(l, bucket, kind)
    local q = l and l[bucket] and l[bucket][kind]
    if not q then return (kind == "xmult" or kind == "xchips") and 1 or 0 end
    return q.n
  end
  local function always(cards, kind, held, selection)
    return n_of(led(cards, held, selection), "always", kind)
  end
  local function pair(a, b) return { Vanilla.card(a, 1), Vanilla.card(b, 2) } end

  check("V7a Blueprint over Cavendish doubles the x3, it does not disappear",
    always(pair("j_blueprint", "j_cavendish"), "xmult") == 9,
    always(pair("j_blueprint", "j_cavendish"), "xmult"))
  check("V7b Brainstorm copies the LEFTMOST joker, not the one beside it",
    always(pair("j_cavendish", "j_brainstorm"), "xmult") == 9,
    always(pair("j_cavendish", "j_brainstorm"), "xmult"))
  check("V7c an additive copy adds, it does not multiply",
    always(pair("j_blueprint", "j_joker"), "mult") == 8,
    always(pair("j_blueprint", "j_joker"), "mult"))

  check("V7d a blueprint_compat=false target is not copied",
    always(pair("j_blueprint", "j_four_fingers"), "mult") == 0,
    always(pair("j_blueprint", "j_four_fingers"), "mult"))
  check("V7e Blueprint in the last slot has no target and pays nothing",
    always({ Vanilla.card("j_cavendish", 1), Vanilla.card("j_blueprint", 2) }, "xmult") == 3,
    always({ Vanilla.card("j_cavendish", 1), Vanilla.card("j_blueprint", 2) }, "xmult"))
  check("V7f Brainstorm in slot 1 would copy itself, so it copies nothing",
    always({ Vanilla.card("j_brainstorm", 1), Vanilla.card("j_cavendish", 2) }, "xmult") == 3,
    always({ Vanilla.card("j_brainstorm", 1), Vanilla.card("j_cavendish", 2) }, "xmult"))
  do
    local cards = pair("j_blueprint", "j_cavendish")
    cards[2].debuff = true
    check("V7g a debuffed target is not copied", always(cards, "xmult") == 1, always(cards, "xmult"))
  end
  do
    local chain = { Vanilla.card("j_blueprint", 1), Vanilla.card("j_blueprint", 2),
      Vanilla.card("j_cavendish", 3) }
    check("V7h a Blueprint chain resolves through the copier in front of it",
      always(chain, "xmult") == 27, always(chain, "xmult"))
  end

  do
    local hand = {}
    for _, id in ipairs({ 13, 13, 4, 7, 9 }) do
      local c = { base = { id = id, suit = "Spades", nominal = math.min(id, 10) } }
      function c:get_id() return self.base.id end
      function c:is_suit(s2) return s2 == self.base.suit end
      function c:is_face() return self.base.id >= 11 and self.base.id <= 13 end
      hand[#hand + 1] = c
    end
    local l = led(pair("j_blueprint", "j_baron"), hand)
    check("V7i a copied held-card rate is counted per held card, like the original",
      math.abs(n_of(l, "gated", "xmult") - 5.0625) < 0.0001, n_of(l, "gated", "xmult"))
    local l2 = led(pair("j_blueprint", "j_scary_face"), hand, { hand[1], hand[2] })
    check("V7j a copied per-scoring-card rate is counted per scoring card",
      n_of(l2, "gated", "chips") == 120, n_of(l2, "gated", "chips"))
  end

  do
    local cards = pair("j_blueprint", "j_cavendish")
    board(cards)
    for _, c in ipairs(cards) do c.area = G.jokers end
    local line = ""
    for l in tostring(select(2, pcall(Jokers.jokers_section, "SELECTING_HAND")) or ""):gmatch("[^\n]+") do
      if l:find("^Joker bonuses") then line = l end
    end
    check("V7k the rendered line states the copied total",
      line:find("always on x9 Mult", 1, true) ~= nil, line)
  end
end

done()
