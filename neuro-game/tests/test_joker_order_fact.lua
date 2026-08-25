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
    STATE = 5, STATES = { SHOP = 5, SELECTING_HAND = 2 }, STATE_COMPLETE = true,
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
  ContextCompact.invalidate_cache()
  FactHints.reset_pending()
end

local function frame()
  ContextCompact.invalidate_cache()
  FactHints.reset_pending()
  pcall(ContextCompact.build, "SHOP", nil,
    { split = "stable", full_jokers = true, no_cache = true, return_list = true })
  ContextCompact.invalidate_cache()
  local force = ContextCompact.build("SHOP", { "buy_from_shop" },
    { split = "volatile", no_cache = true, force_phase = true }) or ""
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
  "Joker order: Popcorn (4) +16 Mult sits right of Ramen (3), so its x1.84 Mult does not multiply it."
local GOLD_TWO =
  "Joker order: Popcorn (2) +16 Mult; Ride the Bus (3) +5 Mult sit right of Ramen (1),"
  .. " so its x1.84 Mult does not multiply them."

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
    line_alt == "Joker order: Popcorn (5) +16 Mult sits right of Ramen (3),"
      .. " so its x1.84 Mult does not multiply it.", line_alt or "(no line)")
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
    gap ~= nil and gap.pivot.index == 3 and gap.pivot.xmult == 1.84,
    gap and (gap.pivot.index .. "/" .. tostring(gap.pivot.xmult)) or "nil")
  check("the +Mult standing left of the multiplier is not counted as behind it",
    gap ~= nil and #gap.behind == 1 and gap.behind[1].index == 4,
    gap and #gap.behind or "nil")
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
  ContextCompact.invalidate_cache()
  FactHints.reset_pending()
  pcall(ContextCompact.build, "SHOP", nil,
    { split = "stable", full_jokers = true, no_cache = true, return_list = true })
  FactHints.reset_pending()
  local recovered = order_line()
  check("a discarded build leaves the fact unspent -- the next frame still delivers it",
    recovered == GOLD_ONE, recovered or "(lost)")
end

do
  board({ FORTUNE(), CARTO(), RAMEN(), POPCORN(), SLY() }, 7)
  check("O17a run 1 round 7 delivers the fact", order_line() == GOLD_ONE)
  G.NEURO.once_serials = {}          -- what a run reset really does
  G.NEURO.run_generation = 2
  local next_run = order_line()
  check("O17b the same arrangement in the same round number of the NEXT run is delivered again",
    next_run == GOLD_ONE, next_run or "(silenced by the previous run)")
end

do
  local Dispatcher = require("core.dispatcher")
  local Actions = require("core.actions")
  local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4, MENU = 11 }
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

  _G.G = {
    STATE = STATES.SHOP, STATES = STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
    GAME = {
      dollars = 20, blind_on_deck = "Small", round = 11, chips = 0, STOP_USE = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 4,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_club" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" } },
      blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {}, pack_choices = 2,
      consumeable_usage_total = { tarot = 0 },
      hands = { Pair = { visible = true, level = 1, chips = 10, mult = 2, played = 0 } },
    },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_club = { key = "bl_club", name = "The Club" } },
    jokers = { cards = { RAMEN(), POPCORN() }, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    shop_jokers = { cards = {}, config = { card_limit = 2 } },
    shop_vouchers = { cards = {}, config = { card_limit = 1 } },
    shop_booster = { cards = {}, config = { card_limit = 2 } },
    FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end,
      select_blind = function() end },
    CONTROLLER = { locks = {} },
    blind_select = {},
    E_MANAGER = { queues = {} },
  }
  G.NEURO = {
    enabled = true, persona = "neuro", run_generation = 1,
    dispatcher = Dispatcher, actions = Actions,
    _decision_windows = {}, once_serials = {}, session_once_serials = {},
    decision_serial = 1, state_enter_serial = 1, reserved_dollars = 0,
    jokers_sold_run = 0,
    update = function() end,
    send_action_result = function() end,
  }
  function G.NEURO:send_context(msg, _silent) wire[#wire + 1] = tostring(msg) return true end
  function G.NEURO:register_actions() end
  function G.NEURO:unregister_actions() end
  function G.NEURO:force_actions(ctx, query)
    wire[#wire + 1] = tostring(ctx)
    wire[#wire + 1] = tostring(query)
  end

  require("core.transition_guard").reset()
  FactHints.reset_pending()
  ContextCompact.invalidate_cache()
  local Orchestrator = require("core.orchestrator")
  Orchestrator.reset_run_state()

  local forced = false
  local function ticks(n)
    for _ = 1, n do
      G.TIMERS.REAL = G.TIMERS.REAL + 0.1
      pcall(Orchestrator.update, 0.1)
      if require("core.force_state").window_is_open() then forced = true end
    end
  end

  ticks(200)   -- 20 s inside the round the arrangement was created in
  local phase1 = table.concat(wire, "\n")
  check("the SHOP force actually shipped (the run is meaningful)",
    forced and #wire > 0, "forced=" .. tostring(forced) .. " msgs=" .. #wire)
  check("the order fact REACHES the model in the round its arrangement exists",
    count_sub(phase1, "Joker order:") == 1,
    "count=" .. count_sub(phase1, "Joker order:") .. "\n" .. phase1)
  check("and only once over 20 s of ticks, not once per rebuild",
    count_sub(phase1, "Joker order:") == 1, tostring(count_sub(phase1, "Joker order:")))
  check("the delivered wording is the same fact the unit checks pin",
    phase1:find("so its x1.84 Mult does not multiply it.", 1, true) ~= nil, phase1)

  require("core.force_state").clear_force_state()
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
    _G.G = { GAME = { probabilities = { normal = 1 } },
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
