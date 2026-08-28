_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("joker-prose-truth")

local Vanilla = require("tests.fixtures.vanilla_jokers")

local function world(cards, extra)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1 },
    GAME = { round = 1, dollars = 10, hands_played = 4, round_resets = { ante = 1 },
      probabilities = { normal = 1 }, hands = {},
      current_round = { discards_left = 2, hands_left = 3, mail_card = { rank = "7" } } },
    NEURO = { once_serials = {}, jokers_sold_run = 0, joker_intents = {}, joker_bought_cost = {} },
    hand = { cards = {}, config = { card_limit = 8 }, highlighted = {} },
    deck = { cards = {} },
    jokers = { cards = cards, config = { card_limit = 5 } },
    FUNCS = {},
  }
  for k, v in pairs(extra or {}) do G[k] = v end
end

local CtxJokers = require("context.ctx_jokers")

local function details_line(name)
  local section = CtxJokers.joker_descriptions_section() or ""
  for line in (section .. "\n"):gmatch("([^\n]*)\n") do
    if line:find(name, 1, true) then return line end
  end
  return nil
end

local function numbers(text)
  local set = {}
  for tok in tostring(text):gmatch("%d+%.?%d*") do set[tok] = true end
  return set
end

local CASES = {
  { key = "j_popcorn", name = "Popcorn", live = function(a) a.mult = 8 end,
    vars = function(a) return { a.mult, a.extra } end,
    live_text = "+8 Mult, -4 Mult per round played" },                       -- card.lua:1092
  { key = "j_ramen", name = "Ramen", live = function(a) a.x_mult = 1.42 end,
    vars = function(a) return { a.x_mult, a.extra } end,
    live_text = "X1.42 Mult, loses X0.01 Mult per card discarded" },         -- card.lua:1093
  { key = "j_rocket", name = "Rocket", live = function(a) a.extra.dollars = 7 end,
    vars = function(a) return { a.extra.dollars, a.extra.increase } end,
    live_text = "Earn $7 at end of round, payout increases by $2 when Boss Blind is defeated" }, -- card.lua:1063
  { key = "j_selzer", name = "Seltzer", live = function(a) a.extra = 3 end,
    vars = function(a) return { a.extra } end,
    live_text = "Retrigger all cards played for the next 3 hands" },         -- card.lua:1096
  { key = "j_turtle_bean", name = "Turtle Bean", live = function(a) a.extra.h_size = 2 end,
    vars = function(a) return { a.extra.h_size, a.extra.h_mod } end,
    live_text = "+2 hand size, reduces by 1 every round" },                  -- card.lua:1080
  { key = "j_ice_cream", name = "Ice Cream", live = function(a) a.extra.chips = 75 end,
    vars = function(a) return { a.extra.chips, a.extra.chip_mod } end,
    live_text = "+75 Chips, -5 Chips for every hand played" },               -- card.lua:1090
  { key = "j_yorick", name = "Yorick",
    live = function(a) a.x_mult = 3; a.yorick_discards = 12 end,
    vars = function(a) return { a.extra.xmult, a.extra.discards, a.yorick_discards, a.x_mult } end,
    live_text = "This Joker gains X1 Mult every 23 [12] cards discarded (Currently X3 Mult)" }, -- card.lua:1121
  { key = "j_loyalty_card", name = "Loyalty Card", live = function(a) a.loyalty_remaining = 2 end,
    vars = function(a)
      return { a.extra.Xmult, a.extra.every + 1, tostring(a.loyalty_remaining) .. " remaining" }
    end,
    live_text = "X4 Mult every 6 hands played, 2 remaining" },               -- card.lua:983
  { key = "j_mail", name = "Mail-In Rebate", live = function(a) a.extra = 5 end,
    vars = function(a) return { a.extra, G.GAME.current_round.mail_card.rank } end,
    live_text = "Earn $5 for each discarded 7, rank changes every round" },  -- card.lua:1000
  { key = "j_todo_list", name = "To Do List", live = function(a) a.to_do_poker_hand = "Two Pair" end,
    vars = function(a) return { a.extra.dollars, a.to_do_poker_hand } end,
    live_text = "Earn $4 if poker hand is a Two Pair, poker hand changes at end of round" }, -- card.lua:1009
}

for _, case in ipairs(CASES) do
  local card = Vanilla.card(case.key, 1)
  case.live(card.ability)
  card.config.center.loc_vars = function(_, _, self)
    return { vars = case.vars(self.ability) }
  end
  world({ card })
  local line = details_line(case.name)
  check(case.key .. ": the details block renders a line", line ~= nil, tostring(line))
  if line then
    local body = line:match("^%d+%. .- %-%- (.*)$") or line
    local live = numbers(case.live_text)
    local rendered = numbers(body)

    local stray = nil
    for tok in pairs(rendered) do
      if not live[tok] then stray = tok break end
    end
    check(case.key .. ": no figure on the line is anything but the live one",
      stray == nil, "stray=" .. tostring(stray) .. " line=" .. tostring(body)
        .. " live=" .. case.live_text)

    local absent = nil
    for tok in pairs(live) do
      if not rendered[tok] then absent = tok break end
    end
    check(case.key .. ": every live figure the game renders reaches the line",
      absent == nil, "absent=" .. tostring(absent) .. " line=" .. tostring(body)
        .. " live=" .. case.live_text)

    if case.live_text:find("(Currently", 1, true) then
      check(case.key .. ": the live running total is kept, not stripped",
        body:find("(Currently", 1, true) ~= nil, body)
    end
  end
end

local Scoring = require("util.scoring")
local CardSemantics = require("facts.card_semantics")

local function bonuses_line()
  local section = CtxJokers.jokers_section() or ""
  for line in (section .. "\n"):gmatch("([^\n]*)\n") do
    if line:find("Joker bonuses", 1, true) then return line end
  end
  return nil
end

local function pc(id, suit)
  local c = { base = { id = id, suit = suit, nominal = id }, ability = {}, playing_card = true }
  function c:get_id() return id end
  function c:is_suit(s) return s == suit end
  function c:is_face() return id >= 11 and id <= 13 end
  return c
end

do
  local kings = { pc(13, "Spades"), pc(13, "Hearts"), pc(13, "Clubs"), pc(5, "Clubs") }
  world({ Vanilla.card("j_baron", 1) })
  G.hand.cards = kings
  G.playing_cards = kings
  local line = bonuses_line() or ""
  check("held_card: the preamble claims the ceiling already counts per card held",
    line:find("per card you hold", 1, true) ~= nil, line)
  check("held_card: and it does -- x3.38 is 1.5^3, not the bare x1.5 rate",
    line:find("x3.38", 1, true) ~= nil, line)
  local s = Scoring.joker_summary()
  check("held_card: covered.held_card is set", s.ledger.covered.held_card == true)
end

do
  world({ Vanilla.card("j_baseball", 1), Vanilla.card("j_ramen", 2), Vanilla.card("j_rocket", 3) })
  local line = bonuses_line() or ""
  check("other_joker: the preamble claims the ceiling already counts per other joker",
    line:find("per other joker", 1, true) ~= nil, line)
  local s = Scoring.joker_summary()
  check("other_joker: covered.other_joker is set", s.ledger.covered.other_joker == true)
  check("other_joker: the figure is the counted product, not the bare rate",
    math.abs((s.ledger.gated.xmult.n or 0) - 1.5 ^ 2) < 1e-9, tostring(s.ledger.gated.xmult.n))
end

do
  world({ Vanilla.card("j_jolly", 1) })
  local fake_src = Vanilla.card("j_jolly", 1)
  local real = CardSemantics.aggregate
  CardSemantics.aggregate = function()
    return {
      guaranteed = { chips = 0, mult = 0, xmult = 1, xchips = 1 },
      conditional = { { scope = "scoring_card", kind = "mult", value = 5, hand_type = "Pair" } },
      refusals = {},
      rows = { { key = "j_modded", kind = "mult", scope = "scoring_card", rate = 5, value = 5,
        hand_type = "Pair", joker_src = fake_src,
        gate = { kind = "hand_type", value = "Pair", text = "a played hand containing a Pair" } } },
    }
  end
  local ok, s = pcall(Scoring.joker_summary)
  CardSemantics.aggregate = real
  check("modded row: joker_summary survives a hand-type-gated scoring_card row", ok, tostring(s))

  local NumericEffects = require("facts.numeric_effects")
  check("a hand-type gate with no text of its own still reads as prose on the wire",
    NumericEffects.gate_phrase("hand_type", "Pair", "prose") == "a played hand containing a Pair",
    tostring(NumericEffects.gate_phrase("hand_type", "Pair", "prose")))
  check("and the HUD stamp keeps its own terser register",
    NumericEffects.gate_phrase("hand_type", "Pair") == "only if hand has Pair",
    tostring(NumericEffects.gate_phrase("hand_type", "Pair")))
  if ok and s then
    check("modded row: coverage is NOT claimed for a scope nothing printed",
      s.ledger.covered.scoring_card == false, tostring(s.ledger.covered.scoring_card))
    check("modded row: it is also absent from the by-type buckets",
      next(s.ledger.by_type) == nil, tostring(next(s.ledger.by_type)))
  end
end

done()
