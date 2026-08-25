_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("retriggers")
local Scoring = require("util.scoring")
local NumericEffects = require("facts.numeric_effects")

local function jk(key, name, extra)
  return { sort_id = key, ability = { set = "Joker", name = name, extra = extra }, sell_cost = 3,
    config = { center = { key = key, set = "Joker", name = name,
      loc_txt = { name = name, description = { "" } } } } }
end

local function pc(id, face)
  local c = { base = { id = id, value = tostring(id) } }
  function c:is_face() return face and true or nil end
  function c:get_id() return id end
  return c
end

local SELECTION = nil

local function board(jokers, selection, scoring, hands_left)
  SELECTION = selection
  _G.G = {
    STATE = 1, STATES = { SHOP = 5 },
    NEURO = { once_serials = {}, jokers_sold_run = 0 },
    GAME = { round = 1, dollars = 10, hands = {}, modifiers = {},
      current_round = { hands_left = hands_left or 3, discards_left = 3 } },
    jokers = { cards = jokers, config = { card_limit = 5 } },
    hand = { cards = selection or {}, highlighted = selection or {},
      config = { card_limit = 8, highlighted_limit = 5 } },
    FUNCS = { get_poker_hand_info = function() return "Pair", nil, {}, scoring or {} end },
  }
end

local function summary() return Scoring.joker_summary(SELECTION) end

local function entry(key)
  local s = summary()
  for _, e in ipairs((s and s.retriggers) or {}) do
    if e.key == key then return e, s end
  end
  return nil, s
end

local FACE, LOW, MID = pc(12, true), pc(3, false), pc(9, false)

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) }, {}, {})
do
  local e, s = entry("j_sock_and_buskin")
  check("R1a a retrigger joker with no hand selected is still reported",
    e ~= nil and e.reps == 1 and e.subject == "face" and e.kind == "reps"
      and e.scope == "retrigger" and e.area == "played",
    e and (e.subject .. "/" .. e.reps) or "nil")
  check("R1b with no selection there is no card count and no pass total",
    e ~= nil and e.cards == nil and e.passes == nil and s.retrigger_passes == nil,
    e and tostring(e.cards) .. "/" .. tostring(e.passes) or "nil")
end

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) },
  { FACE, pc(13, true), LOW }, { FACE, pc(13, true), LOW })
do
  local e, s = entry("j_sock_and_buskin")
  check("two face cards in the scoring hand buy two extra scoring passes",
    e and e.cards == 2 and e.passes == 2 and s.retrigger_passes == 2,
    e and (e.cards .. "/" .. e.passes) or "nil")
end

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) },
  { FACE, LOW, MID }, { LOW, MID })
check("a face card outside the scoring hand is not counted",
  (select(1, entry("j_sock_and_buskin")) or {}).cards == 0,
  tostring((select(1, entry("j_sock_and_buskin")) or {}).cards))

do
  local sel = { pc(2), LOW, pc(5), pc(6), MID, FACE }
  board({ jk("j_hack", "Hack", 1) }, sel, sel)
end
check("Hack counts ranks 2-5 and stops there (a 6 is not a low card)",
  (select(1, entry("j_hack")) or {}).cards == 3,
  tostring((select(1, entry("j_hack")) or {}).cards))

board({ jk("j_hanging_chad", "Hanging Chad", 2) }, { FACE, LOW, MID }, { FACE, LOW, MID })
do
  local e, s = entry("j_hanging_chad")
  check("Hanging Chad is one card at two repetitions, not three cards",
    e and e.cards == 1 and e.reps == 2 and e.passes == 2 and s.retrigger_passes == 2,
    e and (e.cards .. "x" .. e.reps) or "nil")
end

board({ jk("j_dusk", "Dusk", 1) }, { FACE, LOW }, { FACE, LOW }, 3)
do
  local e, s = entry("j_dusk")
  check("R6a Dusk with hands left is reported but not live, and adds no passes",
    e and e.gated == true and e.gate_text == "only on the last hand of the round"
      and e.live == false and e.cards == 2 and s.retrigger_passes == nil,
    e and tostring(e.live) or "nil")
end
board({ jk("j_dusk", "Dusk", 1) }, { FACE, LOW }, { FACE, LOW }, 1)
do
  local e, s = entry("j_dusk")
  check("R6b on the last hand Dusk is live and its passes count",
    e and e.live == true and s.retrigger_passes == 2, e and tostring(e.live) or "nil")
end

board({ jk("j_selzer", "Seltzer", 10) }, { FACE, LOW }, { FACE, LOW })
do
  local e = entry("j_selzer")
  check("Seltzer repeats once per card regardless of its extra field",
    e and e.reps == 1 and e.passes == 2, e and (e.reps .. "/" .. e.passes) or "nil")
end

board({ jk("j_mime", "Mime", 1) }, { FACE, LOW }, { FACE, LOW })
do
  local e, s = entry("j_mime")
  check("a held-in-hand retrigger is reported without a count",
    e and e.kind == "reps" and e.scope == "retrigger" and e.area == "held"
      and e.cards == nil and s.retrigger_passes == nil,
    e and tostring(e.cards) or "nil")
end

do
  local j = jk("j_sock_and_buskin", "Sock and Buskin", 1); j.debuff = true
  board({ j }, { FACE }, { FACE })
  check("a debuffed retrigger joker is not reported", entry("j_sock_and_buskin") == nil)
end
do
  local dead = pc(11, true); dead.debuff = true
  board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) }, { FACE, dead }, { FACE, dead })
  check("a debuffed scoring card is not counted",
    (select(1, entry("j_sock_and_buskin")) or {}).cards == 1,
    tostring((select(1, entry("j_sock_and_buskin")) or {}).cards))
end

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) }, {}, {})
check("a retrigger-only board no longer collapses to no summary",
  summary() ~= nil)

board({ jk("j_baseball", "Baseball Card", 1.5) }, { FACE }, { FACE })
do
  local s = summary()
  check("an extra field that is not a repetition count produces no retrigger",
    s == nil or s.retriggers == nil, s and s.retriggers and #s.retriggers or "-")
end

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1), jk("j_hanging_chad", "Hanging Chad", 2) },
  { FACE, pc(13, true), LOW }, { FACE, pc(13, true), LOW })
do
  local s = summary()
  check("two retrigger jokers add up to four extra scoring passes",
    s and s.retrigger_passes == 4, s and tostring(s.retrigger_passes) or "nil")
end

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) }, { FACE, LOW }, { FACE, LOW })
G.FUNCS.get_poker_hand_info = nil
do
  local e, s = entry("j_sock_and_buskin")
  check("a missing hand evaluator degrades to the qualitative form",
    e ~= nil and e.cards == nil and s.retrigger_passes == nil, e and tostring(e.cards) or "nil")
end

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) }, { FACE, LOW }, { FACE, LOW })
do
  local s = Scoring.joker_summary()
  local e = s and s.retriggers and s.retriggers[1]
  check("an engine-held highlight is not read as a selection",
    e ~= nil and e.cards == nil and s.retrigger_passes == nil, e and tostring(e.cards) or "nil")
end

board({ jk("j_sock_and_buskin", "Sock and Buskin", 1) }, { FACE, LOW }, {})
do
  local e, sm = entry("j_sock_and_buskin")
  check("an empty scoring hand is unknown, not a count of zero",
    e ~= nil and e.cards == nil and sm.retrigger_passes == nil, e and tostring(e.cards) or "nil")
end

local Jokers = require("context.ctx_jokers")

local function render(entries, cards, state_name)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1, SHOP = 5 },
    GAME = { round = 1, dollars = 8, round_resets = { ante = 2 }, probabilities = { normal = 1 } },
    NEURO = { once_serials = {}, jokers_sold_run = 0 },
    jokers = { cards = cards, config = { card_limit = 5 } },
  }
  local real = Scoring.joker_summary
  Scoring.joker_summary = function()
    return { chips = 0, mult = 25, xmult = 1, xchips = 1, cond_xmult = 1, cond_xchips = 1,
      cond_mult = 0, cond_mult_per_card = 0, cond_chips = 0, conditional = {}, cond_by_type = {},
      retriggers = entries }
  end
  local ok, out = pcall(Jokers.jokers_section, state_name)
  Scoring.joker_summary = real
  return ok and (out or "") or tostring(out)
end

do
  local sb = jk("j_sock_and_buskin", "Sock and Buskin", 1)
  local out = render({ { key = "j_sock_and_buskin", card = sb, scope = "played",
    subject = "face", reps = 1 } }, { sb })
  check("with no count the clause names the subject the joker re-scores",
    out:find("+25 Mult; Sock and Buskin re-scores played face cards 1 more time.", 1, true) ~= nil, out)
end

do
  local sb = jk("j_sock_and_buskin", "Sock and Buskin", 1)
  local out = render({ { key = "j_sock_and_buskin", card = sb, scope = "played",
    subject = "face", reps = 1, live = true, cards = 2, passes = 2 } }, { sb })
  check("a known selection renders the card count and the pass total",
    out:find("Sock and Buskin re-scores 2 of them 1 more time each -- 2 extra scoring passes on this hand.", 1, true) ~= nil, out)
end

do
  local dusk = jk("j_dusk", "Dusk", 1)
  local out = render({ { key = "j_dusk", card = dusk, scope = "played",
    subject = "every", reps = 1, gated = true, gate_text = "only on the last hand of the round",
    live = false, cards = 2, passes = 2 } }, { dusk })
  check("a gated retrigger that cannot fire yet claims no passes",
    out:find("Dusk re-scores every scoring card 1 more time, but only on the last hand of the round.", 1, true) ~= nil
    and out:find("extra scoring passes", 1, true) == nil, out)
end

do
  local chad = jk("j_hanging_chad", "Hanging Chad", 2)
  local out = render({ { key = "j_hanging_chad", card = chad, scope = "played",
    subject = "first", reps = 2 } }, { chad })
  check("the repetition count agrees in number",
    out:find("Hanging Chad re-scores the first scoring card 2 more times.", 1, true) ~= nil, out)
end

do
  local mime = jk("j_mime", "Mime", 1)
  local out = render({ { key = "j_mime", card = mime, scope = "held",
    subject = "held_score", reps = 1 } }, { mime })
  check("a held-in-hand retrigger names the cards it re-scores",
    out:find("Mime re-scores the cards you hold in hand that score there 1 more time.", 1, true) ~= nil, out)
end

do
  local chad = jk("j_hanging_chad", "Hanging Chad", 2)
  local out = render({ { key = "j_hanging_chad", card = chad, scope = "played",
    subject = "first", reps = 2, live = true, cards = 1, passes = 2 } }, { chad })
  check("one card at two repetitions is two passes, not one",
    out:find("Hanging Chad re-scores 1 of them 2 more times each -- 2 extra scoring passes on this hand.", 1, true) ~= nil, out)
end

do
  local sb = jk("j_sock_and_buskin", "Sock and Buskin", 1)
  local out = render({ { key = "j_sock_and_buskin", card = sb, scope = "played",
    subject = "face", reps = 1, live = true, cards = 1, passes = 1 } }, { sb })
  check("a single extra pass is stated in the singular",
    out:find("re-scores 1 of them 1 more time each -- 1 extra scoring pass on this hand.", 1, true) ~= nil, out)
end

board({ jk("j_dusk", "Dusk", 1) }, {}, {}, 3)
do
  local e = entry("j_dusk")
  check("Dusk is known to be dead mid-round before any hand is picked",
    e ~= nil and e.gated == true and e.live == false and e.cards == nil,
    e and tostring(e.live) or "nil")
end

do
  local valid, why = true, nil
  for key, spec in pairs(NumericEffects.RETRIGGER) do
    if spec.gate ~= nil and (type(spec.gate) ~= "table"
        or type(spec.gate.active) ~= "function"
        or type(spec.gate.text) ~= "string" or spec.gate.text == "") then
      valid, why = false, key
      break
    end
  end
  check("conditional retriggers bind their predicate and durable rule text together", valid, why)
end

local function render_real_shop(hands_left, selection)
  local dusk = jk("j_dusk", "Dusk", 1)
  board({ dusk }, selection or {}, selection or {}, hands_left)
  G.STATE = G.STATES.SHOP
  return Jokers.jokers_section("SHOP") or ""
end

do
  local expected = "Dusk re-scores every scoring card 1 more time, but only on the last hand of the round."
  local out = render_real_shop(3)
  check("SHOP states Dusk's rule while its current predicate is false",
    out:find(expected, 1, true) ~= nil, out)

  local out_reset = render_real_shop(0, { FACE, LOW })
  check("reset counters cannot make SHOP call Dusk unconditional or exact",
    out_reset:find(expected, 1, true) ~= nil
      and out_reset:find("extra scoring pass", 1, true) == nil
      and out_reset:find("Dusk re-scores every scoring card 1 more time.", 1, true) == nil,
    out_reset)
end

do
  local dusk = jk("j_dusk", "Dusk", 1)
  local out = render({ { key = "j_dusk", card = dusk, scope = "played", subject = "every", reps = 1,
    gated = true, gate_text = "only on the last hand of the round", live = true,
    cards = 5, passes = 5 } }, { dusk }, "SHOP")
  check("roster-only rendering rejects stale exact counts even when the old predicate was live",
    out:find("Dusk re-scores every scoring card 1 more time, but only on the last hand of the round.", 1, true) ~= nil
      and out:find("5 extra scoring passes", 1, true) == nil,
    out)
end

do
  local function led(jokers, hand, selection, hands_left, deck)
    _G.G = {
      STATE = 1, STATES = { SELECTING_HAND = 1, SHOP = 5 },
      NEURO = { once_serials = {}, jokers_sold_run = 0 },
      GAME = { round = 1, dollars = 10, hands = {}, modifiers = {},
        current_round = { hands_left = hands_left or 3, discards_left = 3 } },
      jokers = { cards = jokers, config = { card_limit = 5 } },
      hand = { cards = hand or {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
      playing_cards = deck, deck = deck and { cards = deck } or nil,
      FUNCS = { get_poker_hand_info = function(sel) return "Pair", nil, {}, sel end },
    }
    local s = Scoring.joker_summary(selection)
    return s and s.ledger
  end
  local function n(l, kind) local q = l and l.gated[kind]; return q and q.n end
  local KING, KING2, QUEEN = pc(13, true), pc(13, true), pc(12, true)
  local TWO = pc(2, false)

  -- Baron pays per King HELD; Mime repeats the G.hand pass (card.lua:3769), so two Kings are
  -- four payments: 1.5^4 = 5.0625, not 1.5^2.
  do
    local l = led({ jk("j_baron", "Baron", 1.5), jk("j_mime", "Mime", 1) }, { KING, KING2, TWO })
    check("Mime doubles the passes Baron is paid for each King held",
      math.abs((n(l, "xmult") or 0) - 5.0625) < 0.0001, n(l, "xmult"))
  end
  do
    local l = led({ jk("j_baron", "Baron", 1.5) }, { KING, KING2, TWO })
    check("without a retrigger the same board still reads 1.5^2",
      math.abs((n(l, "xmult") or 0) - 2.25) < 0.0001, n(l, "xmult"))
  end

  do
    local sel = { KING, QUEEN }
    local l = led({ jk("j_scary_face", "Scary Face", 30), jk("j_sock_and_buskin", "Sock and Buskin", 1) },
      { KING, QUEEN, TWO }, sel)
    check("Sock and Buskin doubles the chips Scary Face pays for the face cards it re-scores",
      n(l, "chips") == 120, n(l, "chips"))
  end
  do
    local sel = { KING, QUEEN }
    local l = led({ jk("j_scary_face", "Scary Face", 30), jk("j_selzer", "Seltzer", 10) },
      { KING, QUEEN, TWO }, sel)
    check("Seltzer's blanket repeat reaches a per-scoring-card joker too",
      n(l, "chips") == 120, n(l, "chips"))
  end
  do
    local sel = { KING, QUEEN }
    local l = led({ jk("j_scary_face", "Scary Face", 30), jk("j_hanging_chad", "Hanging Chad", 2) },
      { KING, QUEEN, TWO }, sel)
    check("a first-card-only retrigger adds its passes once, not once per card",
      n(l, "chips") == 120, n(l, "chips"))
  end
  do
    local sel = { KING, QUEEN, TWO }
    local l = led({ jk("j_scary_face", "Scary Face", 30), jk("j_hack", "Hack", 1) },
      { KING, QUEEN, TWO }, sel)
    check("a retrigger whose own match misses the paying cards adds no passes",
      n(l, "chips") == 60, n(l, "chips"))
  end
  do
    local sel = { KING, QUEEN }
    local l = led({ jk("j_scary_face", "Scary Face", 30), jk("j_dusk", "Dusk", 1) },
      { KING, QUEEN, TWO }, sel, 3)
    check("a retrigger that cannot fire this hand does not raise the figure",
      n(l, "chips") == 60, n(l, "chips"))
    local live = led({ jk("j_scary_face", "Scary Face", 30), jk("j_dusk", "Dusk", 1) },
      { KING, QUEEN, TWO }, sel, 0)
    check("R35b on the last hand of the round it does",
      n(live, "chips") == 120, n(live, "chips"))
  end

  do
    local deck = {}
    for _, id in ipairs({ 11, 12, 13, 11, 12, 13, 2, 3, 4, 5, 6, 7 }) do
      deck[#deck + 1] = pc(id, id >= 11)
    end
    local l = led({ jk("j_scary_face", "Scary Face", 30), jk("j_sock_and_buskin", "Sock and Buskin", 1) },
      nil, nil, nil, deck)
    local q = l and l.gated.chips
    check("a per-card ceiling counts the passes a retrigger can buy on top of it",
      q and q.k == "at_most" and q.n == 300, q and (q.k .. "/" .. tostring(q.n)))
    check("R36b and it says so, rather than raising a number with no reason",
      q and q.why[1] and q.why[1]:find("Sock and Buskin", 1, true) ~= nil,
      q and tostring(q.why[1]))
  end
end

done()
