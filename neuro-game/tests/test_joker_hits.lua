_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("joker-hits")
local JH = require("core.joker_hits")
local Vanilla = require("tests.fixtures.vanilla_jokers")

local function jk(sid) return Vanilla.card("j_blackboard", sid) end

local function modded(sid, description, blueprint_compat)
  return {
    sort_id = sid,
    sell_cost = 3,
    ability = { set = "Joker", name = "Modded " .. sid, extra = { flavour = true } },
    config = { center = { key = "j_modded_" .. sid, set = "Joker", name = "Modded " .. sid,
      blueprint_compat = blueprint_compat,
      loc_txt = { name = "Modded " .. sid, text = { description } } } },
  }
end

local function board(cards)
  _G.G = { NEURO = {}, GAME = { hands = {} }, jokers = { cards = cards } }
  JH.reset_run_state()
end

local PAID = { jokers = { x_mult = 3 } }
local IDLE = {}

local function play_hand(cards, fired)
  local before = { before = true, full_hand = {} }
  for _, c in ipairs(cards) do JH.note_eval(c, before, IDLE) end
  local main = { joker_main = true }
  for _, c in ipairs(cards) do
    JH.note_eval(c, main, fired[c.sort_id] and PAID or IDLE)
  end
  local after = { after = true }
  for _, c in ipairs(cards) do JH.note_eval(c, after, IDLE) end
end

local function rec(sid) return G.NEURO.joker_hits and G.NEURO.joker_hits[sid] end

local a, b = jk(1), jk(2)
board({ a, b })
play_hand({ a, b }, { [1] = true })
play_hand({ a, b }, {})
play_hand({ a, b }, { [1] = true, [2] = true })
check("H1a a joker that paid twice over three hands reads 2 of 3",
  rec(1) and rec(1).hands == 3 and rec(1).fired == 2,
  rec(1) and (rec(1).fired .. "/" .. rec(1).hands) or "nil")
check("H1b a joker that paid once over the same three hands reads 1 of 3",
  rec(2) and rec(2).hands == 3 and rec(2).fired == 1,
  rec(2) and (rec(2).fired .. "/" .. rec(2).hands) or "nil")

local function ratio(card)
  local hits, hands = JH.condition_counts(card)
  return hits and (hits .. "/" .. hands) or nil
end

check("H2a three hands is enough to render the count", ratio(a) == "2/3", ratio(a))
board({ a })
play_hand({ a }, {})
play_hand({ a }, {})
check("H2b two hands renders nothing", ratio(a) == nil, ratio(a))

board({ a })
for _ = 1, 9 do play_hand({ a }, {}) end
check("a joker that never fired anywhere reports an honest zero", ratio(a) == "0/9", ratio(a))

do
  local c = jk(3)
  board({ c })
  play_hand({ c }, { [3] = true })
  for _ = 1, 8 do play_hand({ c }, {}) end
  check("H3b a joker that has paid before, then stopped, still reports the ratio",
    ratio(c) == "1/9", ratio(c))
end

board({ a })
do
  local before = { before = true }
  JH.note_eval(a, before, IDLE)
  JH.note_eval(a, { joker_main = true }, PAID)
  JH.note_eval(a, { individual = true }, PAID)
  JH.note_eval(a, { after = true }, IDLE)
end
check("two paying evals in one hand count once", rec(1).hands == 1 and rec(1).fired == 1,
  rec(1).fired .. "/" .. rec(1).hands)

board({ a })
play_hand({ a }, {})
JH.note_eval(a, { buying_card = true }, { jokers = { dollars = 5 } })
check("a shop evaluation after the hand closed does not count as the condition holding",
  rec(1).hands == 1 and rec(1).fired == 0, rec(1).fired .. "/" .. rec(1).hands)

board({ a })
play_hand({ a }, {})
JH.note_eval(a, { before = true }, IDLE)
JH.note_eval(a, { joker_main = true }, { jokers = { message = "+5 Chips" } })
check("a message-only eval IS a firing, because the game filed it under ret.jokers",
  rec(1).fired == 1, tostring(rec(1).fired))

board({ a, b })
play_hand({ a, b }, { [1] = true, [2] = true })
play_hand({ b, a }, { [1] = true, [2] = true })
check("H7a reordering jokers keeps both counters intact",
  rec(1).hands == 2 and rec(1).fired == 2 and rec(2).hands == 2 and rec(2).fired == 2,
  tostring(rec(1).hands) .. "/" .. tostring(rec(2).hands))
G.jokers.cards = { b }
play_hand({ b }, { [2] = true })
check("H7b a joker no longer on the board is dropped", rec(1) == nil, rec(1) and "present")
check("H7c the surviving joker keeps counting", rec(2).hands == 3 and rec(2).fired == 3,
  rec(2).fired .. "/" .. rec(2).hands)

board({ a })
do
  local pc = { sort_id = 99, ability = { set = "Default" } }
  play_hand({ a }, {})
  JH.note_eval(a, { before = true }, IDLE)
  JH.note_eval(pc, { joker_main = true }, PAID)
  check("H8a a playing card gets no record of its own", rec(99) == nil, rec(99) and "present")
  local impostor = { sort_id = 1, ability = { set = "Default" } }
  JH.note_eval(impostor, { joker_main = true }, PAID)
  check("H8b a non-joker sharing a joker's id cannot credit that joker",
    rec(1).fired == 0, tostring(rec(1).fired))
end

-- The install path, driven through a miniature of the real eval_card: it asks calculate_joker for
-- (jokers, triggered) and files ONLY `jokers` into ret, exactly as functions/common_events.lua:770
-- does. That is what makes the (nil, true) case invisible in the return value -- see H16.
do
  _G.G = { NEURO = {}, GAME = { hands = {} }, jokers = { cards = { a } } }
  JH.reset_run_state()
  local calls = 0
  _G.Card = { calculate_joker = function(_, context)
    if context.silent_scale then return nil, true end
    if context.joker_main then return { x_mult = 3 }, nil end
    return nil, nil
  end }
  _G.eval_card = function(card, context)
    calls = calls + 1
    local jokers, triggered = _G.Card.calculate_joker(card, context)
    local ret = {}
    if jokers or triggered then ret.jokers = jokers end
    return ret, {}
  end
  check("H9a install wraps a present eval_card", JH.install() == true)
  check("H9b a second install does not double-wrap", JH.install() == false)
  local eff, post = _G.eval_card(a, { before = true })
  check("H9c both return values survive the wrapper",
    type(eff) == "table" and type(post) == "table")
  _G.eval_card(a, { joker_main = true })
  check("H9d the wrapper records through the real call path",
    rec(1) and rec(1).hands == 1 and rec(1).fired == 1,
    rec(1) and (rec(1).fired .. "/" .. rec(1).hands) or "nil")
  check("H9e the wrapper called through to the original", calls == 2, calls)

  local scaler = jk(9)
  _G.G = { NEURO = {}, GAME = { hands = {} }, jokers = { cards = { scaler } } }
  JH.reset_run_state()
  _G.eval_card(scaler, { before = true })
  check("H16a the silent scaler starts from a clean sheet",
    rec(9) and rec(9).hands == 1 and rec(9).fired == 0,
    rec(9) and (rec(9).fired .. "/" .. rec(9).hands) or "nil")
  _G.eval_card(scaler, { silent_scale = true })
  check("H16b a joker that scales via (nil, true) with no effect table still counts as fired",
    rec(9) and rec(9).fired == 1, rec(9) and tostring(rec(9).fired) or "nil")
  _G.Card = nil
  _G.eval_card = nil
  _G.__neuro_joker_hits_guard = nil
end

do
  local ok = pcall(JH.note_eval, nil, nil, nil)
  check("a nil card and nil context are survivable", ok)
end

-- A joker answering a query is not a joker firing. eval_card itself refuses to build retriggers under
-- a getter context or a retrigger probe (functions/common_events.lua:775), so neither may count here.
do
  local f = jk(6)
  board({ f })
  JH.note_eval(f, { before = true }, IDLE)
  JH.note_eval(f, { check_enhancement = true }, PAID)
  JH.note_eval(f, { mod_probability = true }, PAID)
  JH.note_eval(f, { fix_probability = true }, PAID)
  check("headless fallback: a getter context is a question, not a firing",
    rec(6).fired == 0, tostring(rec(6).fired))
  JH.note_eval(f, { retrigger_joker_check = true }, PAID)
  check("a retrigger probe is not a firing", rec(6).fired == 0, tostring(rec(6).fired))
  JH.note_eval(f, { joker_main = true }, PAID)
  check("H13b the same joker on a real context still counts", rec(6).fired == 1, tostring(rec(6).fired))
end

do
  local d = jk(4)
  board({ d })
  play_hand({ d }, {})
  JH.note_eval(d, { end_of_round = true }, { jokers = { dollars = 4 } })
  play_hand({ d }, {})
  play_hand({ d }, {})
  check("H14a an end-of-round firing is not counted as a hand the condition held on",
    rec(4).fired == 0 and rec(4).hands == 3, rec(4).fired .. "/" .. rec(4).hands)
  check("H14b and the row says nothing rather than a false zero",
    ratio(d) == nil, ratio(d))
end

do
  local e = jk(5)
  board({ e })
  JH.note_eval(e, { before = true }, IDLE)
  _G.SMODS = { is_getter_context = function(ctx) return ctx.some_future_query and "future" or false end }
  JH.note_eval(e, { some_future_query = true }, PAID)
  check("H15a a getter type known only to SMODS is honoured", rec(5).fired == 0, tostring(rec(5).fired))
  JH.note_eval(e, { joker_main = true }, PAID)
  check("H15b a non-getter context under the same SMODS still counts",
    rec(5).fired == 1, tostring(rec(5).fired))
  _G.SMODS = nil
end

do
  local p, q = jk(31), jk(32)
  board({ p, q })
  local before = { before = true }
  JH.note_eval(p, before, IDLE)
  JH.note_eval(q, before, IDLE)
  local after = { after = true }
  JH.note_eval(p, after, PAID)
  JH.note_eval(q, after, PAID)
  check("H19a every joker in one `after` pass is inside the same window",
    rec(31).fired == 1 and rec(32).fired == 1,
    tostring(rec(31).fired) .. "/" .. tostring(rec(32).fired))
  check("H19b and none of them is written off as firing outside the hand",
    rec(31).outside == nil and rec(32).outside == nil,
    tostring(rec(31).outside) .. "/" .. tostring(rec(32).outside))
  JH.note_eval(p, { end_of_round = true }, PAID)
  check("H19c the window does close once a different context arrives",
    rec(31).outside == true, tostring(rec(31).outside))
end

do
  local Jokers = require("context.ctx_jokers")
  local card = jk(7)
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    GAME = { round = 1, dollars = 8, round_resets = { ante = 2 }, probabilities = { normal = 1 }, hands = {} },
    NEURO = { once_serials = {}, jokers_sold_run = 0 },
    jokers = { cards = { card }, config = { card_limit = 5 } },
  }
  JH.reset_run_state()
  play_hand({ card }, { [card.sort_id] = true })
  play_hand({ card }, {})
  local out2 = select(2, pcall(Jokers.jokers_section)) or ""
  check("H11a the roster row the ratio is keyed to is rendered",
    out2:find("(sell ", 1, true) ~= nil, out2)
  check("H11a two hands in, the section carries no ratio yet",
    out2:find("Observed this run", 1, true) == nil, out2)
  play_hand({ card }, {})
  local out3 = select(2, pcall(Jokers.jokers_section)) or ""
  check("H11b the third hand puts the ratio in the section, against this joker's row number",
    out3:find("Observed this run, by roster number", 1, true) ~= nil
      and out3:find("1. held 1/3", 1, true) ~= nil, out3)
  check("H11c the skeleton the ratio is worded into appears exactly once",
    select(2, out3:gsub("of your last", "")) == 1, out3)
end

do
  local credit = Vanilla.card("j_credit_card", 20)
  board({ credit })
  for _ = 1, 9 do play_hand({ credit }, {}) end
  check("H17a a joker with no scoring effect at all gets no ratio, not a zero",
    ratio(credit) == nil, ratio(credit))

  local plain = Vanilla.card("j_joker", 21)
  board({ plain })
  for _ = 1, 9 do play_hand({ plain }, {}) end
  check("H17b a joker whose effect is unconditional gets no ratio either",
    ratio(plain) == nil, ratio(plain))

  check("H17c the gate is read off card_semantics, not off a list of keys the tests know",
    JH._test.has_condition(modded(40, "+#1# Mult if the played hand contains a Flush", true)) == true
    and JH._test.has_condition(modded(41, "Sell this card to gain $5", true)) == false)

  check("H17d the real Blackboard passes the gate",
    JH._test.has_condition(Vanilla.card("j_blackboard", 42)) == true)
  check("H17e so does a joker whose value project() cannot reach at all",
    JH._test.has_condition(Vanilla.card("j_mystic_summit", 43)) == true)
  check("H17f a passive rule-changer with no calculate effect never gets the line",
    JH._test.has_condition(Vanilla.card("j_smeared", 44)) == false
    and JH._test.has_condition(Vanilla.card("j_splash", 45)) == false)
end

done()
