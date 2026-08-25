_G.NEURO_TEST = true
_G.G = {}
local Scoring = require("util.scoring")

local check, done = require("tests.helpers").harness("scoring")

local function jokers(list) G.jokers = { cards = list } end

G.jokers = nil
check("no jokers -> false", Scoring.owned_has_xmult() == false)
jokers({})
check("empty jokers -> false", Scoring.owned_has_xmult() == false)
jokers({ { ability = { mult = 8 } } })
check("flat mult only -> false", Scoring.owned_has_xmult() == false)
jokers({ { ability = { x_mult = 3 } } })
check("ability.x_mult>1 -> true", Scoring.owned_has_xmult() == true)
jokers({ { ability = { extra = { Xmult = 1.5 } } } })
check("conditional ability.extra.Xmult is not guaranteed -> false", Scoring.owned_has_xmult() == false)
jokers({ { ability = { extra = { x_mult = 2 } } } })
check("conditional ability.extra.x_mult is not guaranteed -> false", Scoring.owned_has_xmult() == false)
jokers({ { ability = {}, edition = { polychrome = true } } })
check("polychrome edition -> true", Scoring.owned_has_xmult() == true)
jokers({ { ability = { x_mult = 3 }, debuff = true } })
check("debuffed x_mult joker -> false", Scoring.owned_has_xmult() == false)
jokers({ { ability = { mult = 4 } }, { ability = { extra = { Xmult = 2 } } } })
check("flat + conditional xmult -> false", Scoring.owned_has_xmult() == false)

jokers({ { ability = { x_mult = 2 } } })
local s = Scoring.joker_summary()
check("top-level x_mult -> guaranteed xmult", s and s.xmult == 2, s and s.xmult)
check("top-level x_mult -> cond_xmult untouched", s and s.cond_xmult == 1, s and s.cond_xmult)

jokers({ { ability = { extra = { Xmult = 3 } } } })
s = Scoring.joker_summary()
check("extra.Xmult -> conditional, not guaranteed", s and s.cond_xmult == 3 and s.xmult == 1,
  s and (tostring(s.xmult) .. "/" .. tostring(s.cond_xmult)))

jokers({ { ability = { extra = { x_mult = 1.5 } } } })
s = Scoring.joker_summary()
check("extra.x_mult -> conditional", s and s.cond_xmult == 1.5, s and s.cond_xmult)

jokers({ { ability = {}, edition = { x_mult = 1.5 } } })
s = Scoring.joker_summary()
check("edition x_mult -> guaranteed", s and s.xmult == 1.5 and s.cond_xmult == 1,
  s and (tostring(s.xmult) .. "/" .. tostring(s.cond_xmult)))

jokers({ { ability = { x_mult = 3 } }, { ability = { extra = { Xmult = 1.5 } } } })
s = Scoring.joker_summary()
check("mixed: guaranteed x3 + conditional x1.5 kept apart",
  s and s.xmult == 3 and s.cond_xmult == 1.5, s and (tostring(s.xmult) .. "/" .. tostring(s.cond_xmult)))

jokers({ { ability = { type = "Spades", extra = { Xmult = 2 } } } })
s = Scoring.joker_summary()
check("typed extra.Xmult -> ledger by_type bucket, not flat",
  s and s.ledger.by_type.Spades and s.ledger.by_type.Spades.xmult == 2 and s.cond_xmult == 1 and s.xmult == 1,
  s and s.ledger.by_type.Spades and s.ledger.by_type.Spades.xmult)

do
  jokers({ { ability = { set = "Joker", x_chips = 2, type = "Pair" },
             config = { center = { key = "j_x", set = "Joker",
               loc_txt = { description = { "x2 Chips if played hand contains a Pair" } } } } } })
  local s2 = Scoring.joker_summary()
  check("typed xChips survives in its hand-type bucket",
    s2 ~= nil and s2.ledger.by_type.Pair and s2.ledger.by_type.Pair.xchips == 2
      and s2.cond_xchips == 1,
    s2 and s2.ledger.by_type.Pair and tostring(s2.ledger.by_type.Pair.xchips))
  check("typed xChips does not silently become guaranteed",
    s2 ~= nil and s2.xchips == 1, s2 and tostring(s2.xchips))
end

do
  jokers({ { ability = { set = "Joker", t_mult = 8, type = "Pair" },
             config = { center = { key = "j_gate", set = "Joker",
               loc_txt = { description = { "Adds 8 Mult" } } } } } })   -- deliberately no trigger word
  local s4 = Scoring.joker_summary()
  check("hand-gated effect is conditional without a trigger word in the text",
    s4 ~= nil and s4.mult == 0 and s4.ledger.by_type.Pair and s4.ledger.by_type.Pair.mult == 8,
    s4 and (tostring(s4.mult) .. "/" .. tostring(s4.ledger.by_type.Pair and s4.ledger.by_type.Pair.mult)))
  jokers({ { ability = { set = "Joker", mult = 5, type = "discard_custom" },
             config = { center = { key = "j_nogate", set = "Joker",
               loc_txt = { description = { "Adds 5 Mult" } } } } } })
  local s5 = Scoring.joker_summary()
  check("a non-hand type is not treated as a gate",
    s5 ~= nil and s5.mult == 5, s5 and tostring(s5.mult))
  jokers({ { ability = { set = "Joker", mult = 8, type = "Pair" },
             config = { center = { key = "j_plain", set = "Joker",
               loc_txt = { description = { "Adds 8 Mult" } } } } } })
  local s6 = Scoring.joker_summary()
  check("a named hand type does not gate a field the engine pays unconditionally",
    s6 ~= nil and s6.mult == 8 and not (s6.ledger.by_type.Pair and s6.ledger.by_type.Pair.mult),
    s6 and tostring(s6.mult))
end

do
  jokers({ { ability = { set = "Joker", mult = 10 },
             config = { center = { key = "j_a", set = "Joker" } }, debuff = true },
           { ability = { set = "Joker", mult = 4 },
             config = { center = { key = "j_b", set = "Joker" } } } })
  local s3 = Scoring.joker_summary()
  check("debuffed joker excluded from the guaranteed total",
    s3 ~= nil and s3.mult == 4, s3 and tostring(s3.mult))
end

do
  local Q = Scoring.Q
  check("Q: a known pair of xMults multiplies and stays known",
    Q.combine("xmult", Q.known(2), Q.known(3)).k == "known"
      and Q.combine("xmult", Q.known(2), Q.known(3)).n == 6)
  check("Q: chips add rather than multiply",
    Q.combine("chips", Q.known(10), Q.known(5)).n == 15)
  local mixed = Q.combine("xmult", Q.known(3), Q.at_most(5, "4 Kings in your deck"))
  check("Q: known composed with a ceiling is a ceiling, not a known value",
    mixed.k == "at_most" and mixed.n == 15, mixed.k .. "/" .. tostring(mixed.n))
  check("Q: the ceiling source travels with the ceiling",
    mixed.why[1] == "4 Kings in your deck", mixed.why[1])
  local absorbed = Q.combine("xmult", Q.known(3), Q.unknown("how many you will hold"))
  check("Q: unknown absorbs, and carries no number at all",
    absorbed.k == "unknown" and absorbed.n == nil, absorbed.k .. "/" .. tostring(absorbed.n))
  check("Q: unknown absorbs from the left too",
    Q.combine("mult", Q.unknown("x"), Q.known(4)).k == "unknown")
  check("Q: a ceiling with no named source degrades to unknown, never to a bare number",
    Q.at_most(99).k == "unknown" and Q.at_most(99, "").k == "unknown",
    Q.at_most(99).k)
end

do
  local saved = _G.G
  _G.G = { GAME = {} }
  local q = Scoring.total_of({ scope = "scoring_card", kind = "chips", rate = 30, key = "j_x" }, {})
  check("scoring_card with no readable population is a sourced ceiling, not an unknown",
    q.k == "at_most" and q.n == 150, q.k .. "/" .. tostring(q.n))
  check("and its source names the cap without restating the cap's size",
    type(q.why[1]) == "string" and q.why[1] ~= "" and q.why[1]:find("%d") == nil, tostring(q.why[1]))

  _G.G.playing_cards = { {}, {}, {} }
  local q2 = Scoring.total_of({ scope = "scoring_card", kind = "chips", rate = 30, key = "j_x" }, {})
  check("a deck-derived ceiling states the population and nothing else",
    q2.k == "at_most" and q2.n == 90 and q2.why[1] == "3 such cards in your deck",
    q2.k .. "/" .. tostring(q2.n) .. "/" .. tostring(q2.why[1]))
  _G.G = saved
end

do
  local Econ = require("facts.economy_facts")
  _G.G = { GAME = {
    dollars = 100, bankrupt_at = 0,
    current_round = { free_rerolls = 2, reroll_cost = 0, reroll_cost_increase = 3 },
    round_resets = { reroll_cost = 5 },
  }, NEURO = {} }
  local f = Econ.reroll_facts()
  check("free reroll costs nothing right now", f and f.effective == 0, f and tostring(f.effective))
  check("first paid reroll = base + current increase (not +1)", f and f.paid == 8, f and tostring(f.paid))

  G.GAME.round_resets.temp_reroll_cost = 2
  local f2 = Econ.reroll_facts()
  check("temp_reroll_cost overrides the base", f2 and f2.paid == 5, f2 and tostring(f2.paid))

  G.GAME.round_resets.temp_reroll_cost = nil
  G.GAME.current_round.free_rerolls = 0
  G.GAME.current_round.reroll_cost = 9
  local f3 = Econ.reroll_facts()
  check("no frees -> effective is the live reroll_cost", f3 and f3.effective == 9, f3 and tostring(f3.effective))

  G.GAME.dollars = -5
  G.GAME.current_round.reroll_cost = 0
  local f4 = Econ.reroll_facts()
  check("a $0 reroll remains available with a negative bank",
    f4 and f4.can_reroll == true and f4.max_affordable >= 1,
    f4 and (tostring(f4.can_reroll) .. "/" .. tostring(f4.max_affordable)))

  local saved_blind_amount = _G.get_blind_amount
  _G.get_blind_amount = function(a) return a * 100 end
  G.GAME.round_resets = { ante = 12 }
  G.GAME.win_ante = 8
  local endless = Econ.scaling_curve()
  check("endless scaling curve continues beyond win_ante",
    endless and endless:find("ante 13", 1, true) and endless:find("ante 14", 1, true), endless)
  _G.get_blind_amount = saved_blind_amount
end

do
  local DynamicJokers = require("facts.dynamic_jokers")
  local key = "j_test_scope_leak_148"
  DynamicJokers.ROWS[key] = { { kind = "mult", scope = "scoring_card", per_hand_type = true } }
  local saved_pht = DynamicJokers.per_hand_type
  DynamicJokers.per_hand_type = function(k)
    if k ~= key then return saved_pht(k) end
    return { kind = "mult", per_type = { Flush = 5 } }
  end
  _G.G = {
    jokers = { cards = { {
      sort_id = key, ability = { set = "Joker", name = "Test Scope Leak" }, sell_cost = 1,
      config = { center = { key = key, set = "Joker", name = "Test Scope Leak",
        loc_txt = { name = "Test Scope Leak", description = { "" } } } },
    } } },
    hand = { cards = {}, config = { card_limit = 8 } }, playing_cards = {}, deck = { cards = {} },
    GAME = {},
  }
  local summary = Scoring.joker_summary()
  check("a hand-type gate on a scoring_card-scope row does not enter the Ledger's by_type",
    summary ~= nil and summary.ledger ~= nil and summary.ledger.by_type.Flush == nil,
    summary and summary.ledger and summary.ledger.by_type.Flush)
  check("cond_by_type is the by_type alias, not a second computation",
    summary ~= nil and summary.cond_by_type == summary.ledger.by_type, summary)
  DynamicJokers.ROWS[key] = nil
  DynamicJokers.per_hand_type = saved_pht
end

done()
