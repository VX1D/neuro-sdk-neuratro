local ES = require("tests.engine_cards").states()
_G.NEURO_TEST = true
if not love then
  love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("joker-order-fact")
local H = require("tests.helpers")

local ContextCompact = require("context.context_compact")
local FactHints = require("facts.fact_hints")

local function joker(key, name, ability, desc)
  ability = ability or {}
  ability.name = name
  ability.set = "Joker"
  return { sort_id = key, ability = ability, sell_cost = 3, cost = 4,
    config = { center = { key = key, set = "Joker", name = name,
      loc_txt = { name = name, description = { desc or "" } } } } }
end

local function FORTUNE() return joker("j_fortune_teller", "Fortune Teller", { extra = 1 }, "gains +1 Mult per Tarot used") end
local function CARTO() return joker("j_cartomancer", "Cartomancer", {}, "Creates a Tarot card when Blind is selected") end
local function RAMEN() return joker("j_ramen", "Ramen", { x_mult = 1.84 }, "loses X0.01 Mult per card discarded") end
local function POPCORN() return joker("j_popcorn", "Popcorn", { mult = 16 }, "loses 4 mult per round") end
local function SLY() return joker("j_sly", "Sly Joker", { t_chips = 50 }, "+50 Chips if played hand contains a Pair") end
local function BUS() return joker("j_ride_the_bus", "Ride the Bus", { mult = 5 }, "gains +1 Mult per consecutive hand with no face card") end

local function board(cards, round)
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = ES.SHOP, STATES = ES, STATE_COMPLETE = true,
    TIMERS = { REAL = 100 }, FUNCS = {},
    NEURO = { enabled = true, run_generation = 1, jokers_sold_run = 0,
      once_serials = {}, session_once_serials = {} },
    GAME = { round = round or 1, consumeable_usage_total = { tarot = 9 }, hands = {},
      dollars = 10, chips = 0, modifiers = {}, used_vouchers = {},
      current_round = {}, round_resets = { ante = 1 }, probabilities = { normal = 1 } },
    jokers = { cards = cards, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    deck = { cards = {} },
  }
  FactHints.reset_pending()
end

local function frame()
  FactHints.reset_pending()
  pcall(ContextCompact.build, "SHOP", nil,
    { split = "stable", return_list = true })
  local force = ContextCompact.build("SHOP", { "buy_from_shop" },
    { split = "volatile" }) or ""
  local hint = H.drain_hints()
  local at = force:find("Joker order:", 1, true)
  local line = at and (force:sub(at):match("^[^\n]*"):gsub("%s+$", "")) or nil
  return line, force, hint
end

local function order_line()
  local line = frame()
  return line
end

local GOLD_ONE =
  "Joker order: Popcorn (slot 4) +16 Mult sits right of Ramen (slot 3), so its x1.84 Mult does not multiply it."
  .. " Left of Ramen, Popcorn would add +13.44 Mult more on every hand."
local GOLD_TWO =
  "Joker order: Popcorn (slot 2) +16 Mult; Ride the Bus (slot 3) up to +5 Mult sit right of Ramen (slot 1),"
  .. " so its x1.84 Mult does not multiply them. Left of Ramen, they would add Popcorn +13.44 Mult"
  .. " and Ride the Bus up to +4.2 Mult more on every hand."

board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() })
local line_one, force_one, hint_one = frame()
check("a +Mult joker behind the xMult is named with its slot, its value and the multiplier it misses",
  line_one == GOLD_ONE, line_one or "(no line)")
check("O1b the fact rides the window it annotates and never the retained wire",
  force_one:find("Joker order:", 1, true) ~= nil
    and hint_one:find("Joker order:", 1, true) == nil, "wire=[" .. hint_one .. "]")
check("O1c the force context still carries the joker roster it annotates",
  force_one:find("Your jokers", 1, true) ~= nil, force_one)

board({ FORTUNE(), CARTO(), POPCORN(), RAMEN(), SLY() })
check("the same jokers in scoring order produce no line",
  order_line() == nil, order_line() or "-")

board({ RAMEN(), POPCORN(), BUS() })
local line_two = order_line()
check("several jokers behind the multiplier are all named, with plural agreement",
  line_two == GOLD_TWO, line_two or "(no line)")

board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() })
check("O4a the line lands on the first frame of a lineup", order_line() == GOLD_ONE)
check("O4b the line stands as long as the arrangement does",
  order_line() == GOLD_ONE, order_line() or "-")
G.GAME.round = 2
local line_r2 = order_line()
check("a later round still states the standing arrangement", line_r2 == GOLD_ONE, line_r2 or "(no line)")
check("O5b and every window in that round states it", order_line() == GOLD_ONE, order_line() or "-")

do
  local c = G.jokers.cards
  c[3], c[4] = c[4], c[3]
  check("O6a a reorder that fixes the board silences the line", order_line() == nil, order_line() or "-")
  c[3], c[4] = c[4], c[3]
  check("O6b returning to a broken arrangement states it again, because it is true again",
    order_line() == GOLD_ONE, order_line() or "-")
  c[4], c[5] = c[5], c[4]
  local line_alt = order_line()
  check("O6c a different broken arrangement is a different fact and lands inside the same round",
    line_alt == "Joker order: Popcorn (slot 5) +16 Mult sits right of Ramen (slot 3),"
      .. " so its x1.84 Mult does not multiply it. Left of Ramen, Popcorn would add +13.44 Mult more"
      .. " on every hand.", line_alt or "(no line)")
end

board({ RAMEN(), SLY() })
check("a +Chips joker behind the multiplier is not reported (chips do not enter the product)",
  order_line() == nil, order_line() or "-")

board({ POPCORN(), SLY() })
check("no multiplier on the board -> no line", order_line() == nil, order_line() or "-")

board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() })
G.jokers.cards[4].facing = "back"
check("a face-down joker suppresses the claim (the arrangement is not knowable)",
  order_line() == nil, order_line() or "-")

board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() })
G.jokers.cards[4].debuff = true
check("a debuffed joker contributes no +Mult and is not reported",
  order_line() == nil, order_line() or "-")

do
  local Scoring = require("util.scoring")
  board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() })
  local gap = Scoring.joker_order_gap()
  check("the fact reports the leftmost multiplier as the pivot",
    gap ~= nil and gap.groups[1].pivot.index == 3 and gap.groups[1].pivot.factor == 1.84,
    gap and (gap.groups[1].pivot.index .. "/" .. tostring(gap.groups[1].pivot.factor)) or "nil")
  check("the +Mult standing left of the multiplier is not counted as behind it",
    gap ~= nil and #gap.groups[1].behind == 1 and gap.groups[1].behind[1].index == 4,
    gap and #gap.groups[1].behind or "nil")
end

board({ RAMEN(), joker("j_greedy_joker", "Greedy Joker", { t_mult = 3 }, "Diamond cards give +3 Mult when scored") })
check("a gated +Mult is not claimed as a flat value standing behind the multiplier",
  order_line() == nil, order_line() or "-")

board({ joker("j_gated_x", "Gated X", { x_mult = 2 }, "X2 Mult if played hand contains a Pair"), POPCORN() })
check("a gated xMult is not claimed as the pivot",
  order_line() == nil, order_line() or "-")

do
  local banned = { "prefer", "should", "best", "you must", "better", "instead" }
  local hits = {}
  for _, w in ipairs(banned) do
    if (line_one or ""):lower():find(w, 1, true) or (line_two or ""):lower():find(w, 1, true) then
      hits[#hits + 1] = w
    end
  end
  check("the line states the board, it does not prescribe a move",
    line_one ~= nil and line_two ~= nil and #hits == 0,
    table.concat(hits, ",") .. " | " .. tostring(line_one) .. " | " .. tostring(line_two))
end

do
  board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() })
  FactHints.reset_pending()
  pcall(ContextCompact.build, "SHOP", nil,
    { split = "stable", return_list = true })
  FactHints.reset_pending()
  local recovered = order_line()
  check("a discarded build leaves the fact unspent -- the next frame still delivers it",
    recovered == GOLD_ONE, recovered or "(lost)")
end

do
  board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() }, 7)
  check("O17a run 1 round 7 delivers the fact", order_line() == GOLD_ONE)
  G.NEURO.once_serials = {}
  G.NEURO.run_generation = 2
  local next_run = order_line()
  check("O17b the same arrangement in the same round number of the NEXT run is delivered again",
    next_run == GOLD_ONE, next_run or "(silenced by the previous run)")
end

do
  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local STATES = require("tests.engine_cards").states()
  local wire = {}

  local function count_sub(s, sub)
    local n, pos = 0, 1
    while true do
      local a = s:find(sub, pos, true)
      if not a then break end
      n = n + 1; pos = a + #sub
    end
    return n
  end

  H.orch_board({ kind = "club", state = "SHOP", states = STATES, edit = function(g)
    g.GAME.consumeable_usage_total = { tarot = 0 }
    g.GAME.hands.Pair.played = 0
    g.jokers.cards = { RAMEN(), POPCORN() }
    g.shop = {}
  end })
  G.NEURO = H.orch_neuro({ dispatcher = Dispatcher, actions = Actions, session_once_serials = {},
    jokers_sold_run = 0, send_action_result = "noop" })
  function G.NEURO:send_context(msg, _silent) wire[#wire + 1] = tostring(msg) return true end
  function G.NEURO:register_actions() end
  function G.NEURO:force_actions(ctx, query)
    wire[#wire + 1] = tostring(ctx)
    wire[#wire + 1] = tostring(query)
  end

  require("core.validate").reset_run_state()
  FactHints.reset_pending()
  local Orchestrator = require("core.orchestrator")
  Orchestrator.reset_run_state()

  local forced = false
  local function ticks(n)
    for _ = 1, n do
      G.TIMERS.REAL = G.TIMERS.REAL + 0.1
      pcall(Orchestrator.update, 0.1)
      if require("core.window").current() ~= nil then forced = true end
    end
  end

  ticks(200)
  local phase1 = table.concat(wire, "\n")
  check("the SHOP force actually shipped (the run is meaningful)",
    forced and #wire > 0, "forced=" .. tostring(forced) .. " msgs=" .. #wire)
  check("the order fact REACHES the model in the round its arrangement exists",
    count_sub(phase1, "Joker order:") == 1,
    "count=" .. count_sub(phase1, "Joker order:") .. "\n" .. phase1)
  check("the delivered wording is the same fact the unit checks pin",
    phase1:find("so its x1.84 Mult does not multiply it.", 1, true) ~= nil, phase1)

  require("core.window").reset()
  Orchestrator.reset_run_state()
end

do
  local PublicCard = require("facts.public_card_identity")
  local Scoring = require("util.scoring")
  local function jk(key, xm, m, facing)
    return { facing = facing, ability = { name = key, set = "Joker", x_mult = xm, mult = m },
      config = { center = { key = key, set = "Joker" } } }
  end
  local function facing_board(f1, f2)
    _G.G = { P_CENTERS = require("tests.engine_centers").centers(), GAME = { probabilities = { normal = 1 } },
      jokers = { cards = { jk("j_hologram", 2, nil, f1), jk("j_joker", nil, 4, f2) } },
      hand = { cards = {} }, deck = { cards = {} }, playing_cards = {} }
  end
  facing_board(nil, nil)
  check("a fully visible roster still reports the ordering gap",
    Scoring.joker_order_gap() ~= nil)
  check("H1a and the fixture really is visible, so H2/H3 are not vacuous",
    PublicCard.is_public(G.jokers.cards[1]) == true)
  facing_board("back", nil)
  check("one face-down joker ends the answer -- its slot is the fact being asked for",
    Scoring.joker_order_gap() == nil)
  facing_board("back", "back")
  check("a wholly face-down row ends it too, though the multiset is still known",
    Scoring.joker_order_gap() == nil)
end

done()
