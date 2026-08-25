_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("scoring_hand_cap")
local Scoring = require("util.scoring")

local function jk(key, name, extra)
  return { sort_id = key, ability = { set = "Joker", name = name, extra = extra }, sell_cost = 3,
    config = { center = { key = key, set = "Joker", name = name,
      loc_txt = { name = name, description = { "" } } } } }
end

local function card(id, suit)
  local c = { base = { id = id, value = tostring(id), suit = suit }, ability = {},
    config = { center = { key = "c_base" } } }
  function c:get_id() return id end
  function c:is_suit(s) return s == suit end
  function c:is_face() return id > 10 and id < 14 end
  return c
end

local function spades(n)
  local out = {}
  for i = 1, n do out[#out + 1] = card(2 + (i % 9), "Spades") end
  return out
end

local function chips_total(summary)
  local led = summary and summary.ledger
  return led and led.gated and led.gated.chips or nil
end

local function arrowhead_board(limit)
  _G.G = {
    GAME = { current_round = {} },
    jokers = { cards = { jk("j_arrowhead", "Arrowhead", 50) } },
    hand = { cards = {}, config = { card_limit = 8, highlighted_limit = limit } },
    playing_cards = spades(13),
    FUNCS = {},
  }
  return chips_total(Scoring.joker_summary())
end

local vanilla = arrowhead_board(5)
check("vanilla play limit still prices Arrowhead over five scoring cards",
  vanilla and vanilla.k == "at_most" and vanilla.n == 250,
  vanilla and (vanilla.k .. "/" .. tostring(vanilla.n)))

local raised = arrowhead_board(8)
check("a play limit raised to 8 raises the ceiling with it (8 x 50 chips)",
  raised and raised.k == "at_most" and raised.n == 400,
  raised and (raised.k .. "/" .. tostring(raised.n)))

local ODD = { 3, 5, 7, 9, 3, 5, 7, 9 }
local function odd_todd_board(opts)
  local sel = {}
  for _, id in ipairs(ODD) do sel[#sel + 1] = card(id, "Hearts") end
  local jokers = { jk("j_odd_todd", "Odd Todd", 31) }
  if opts.splash then jokers[#jokers + 1] = jk("j_splash", "Splash") end
  if opts.hidden_joker then
    local mystery = jk("j_mystery", "Mystery")
    mystery.facing = "back"
    jokers[#jokers + 1] = mystery
  end
  _G.G = {
    GAME = { current_round = {} },
    jokers = { cards = jokers },
    hand = { cards = sel, config = { card_limit = 8, highlighted_limit = 8 } },
    playing_cards = sel,
    FUNCS = { get_poker_hand_info = function(cards)
      local pair = { cards[1], cards[5] }
      return "Pair", nil, { Pair = { pair } }, pair, nil
    end },
  }
  return chips_total(Scoring.joker_summary(sel)), sel
end

local no_splash = odd_todd_board({})
check("without Splash only the poker subset scores (2 x 31 chips), exactly",
  no_splash and no_splash.k == "known" and no_splash.n == 62,
  no_splash and (no_splash.k .. "/" .. tostring(no_splash.n)))

local with_splash = odd_todd_board({ splash = true })
check("with Splash every played card scores (8 x 31 chips)",
  with_splash and with_splash.n == 248,
  with_splash and (with_splash.k .. "/" .. tostring(with_splash.n)))

local hidden = odd_todd_board({ hidden_joker = true })
check("a face-down joker cannot be ruled out as Splash, so the ceiling covers the whole play",
  hidden and hidden.n == 248, hidden and (hidden.k .. "/" .. tostring(hidden.n)))
check("and that figure is a ceiling, not a Known count",
  hidden and hidden.k == "at_most", hidden and hidden.k)

local function seltzer_board(opts)
  local sel = {}
  for i = 1, 4 do sel[#sel + 1] = card(3 + i, "Hearts") end
  local stone = card(-100, "Hearts")
  stone.ability.enhancement = "m_stone"
  sel[#sel + 1] = stone
  local jokers = { jk("j_selzer", "Seltzer", 1) }
  if opts.hidden_joker then
    local mystery = jk("j_mystery", "Mystery")
    mystery.facing = "back"
    jokers[#jokers + 1] = mystery
  end
  _G.G = {
    GAME = { current_round = {} },
    jokers = { cards = jokers },
    hand = { cards = sel, config = { card_limit = 8, highlighted_limit = 5 } },
    playing_cards = sel,
    FUNCS = { get_poker_hand_info = function(cards)
      local pair = { cards[1], cards[2] }
      return "Pair", nil, { Pair = { pair } }, pair, nil
    end },
  }
  local s = Scoring.joker_summary(sel)
  local entry = s and s.retriggers and s.retriggers[1]
  return entry, s
end

local stone_entry = seltzer_board({})
check("a Stone card scores outside the poker hand, so it counts as a retriggered card",
  stone_entry and stone_entry.cards == 3, stone_entry and tostring(stone_entry.cards))

local hidden_entry, hidden_summary = seltzer_board({ hidden_joker = true })
check("with an unidentifiable joker the retrigger pass count is withheld, not guessed",
  hidden_entry and hidden_entry.cards == nil and hidden_summary.retrigger_passes == nil,
  hidden_entry and tostring(hidden_entry.cards))

do
  _G.G = { GAME = {} }   -- no hand, no deck: nothing left to read but the play itself
  local q = Scoring.total_of({ scope = "scoring_card", kind = "chips", rate = 30, key = "j_x" },
    { selection = spades(7) })
  check("an unreadable limit still cannot price fewer cards than the play already holds",
    q.k == "at_most" and q.n == 210, q.k .. "/" .. tostring(q.n))
end

done()
