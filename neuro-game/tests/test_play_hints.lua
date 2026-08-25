_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("play-hints")
local H = require("tests.helpers")

local Tuning = require("core.config")

local Actions = require("core.actions")
local real_is_action_valid = Actions.is_action_valid

local function stub_valid(fn)
  check("is_action_valid is unstubbed before this block replaces it",
    Actions.is_action_valid == real_is_action_valid,
    "an earlier block left its stub installed")
  Actions.is_action_valid = fn
end
local function unstub_valid()
  Actions.is_action_valid = real_is_action_valid
end

do
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 }, P_BLINDS = {},
    GAME = {
      win_ante = 8, dollars = 20, round = 0,
      blind_on_deck = "Small",
      round_resets = {
        ante = 1,
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
      },
    },
    NEURO = { once_serials = {} },
    jokers = { cards = {} }, consumeables = { cards = {} },
  }
  stub_valid(function(n) return n == "select_blind" or n == "skip_blind" end)
  local FBS = require("force.force_blind_select")
  local q = ((FBS.build() or {}).query or "") .. H.drain_hints()
  check("blind advice actively raises skipping a beatable blind for its tag",
    q:find("weigh skip_blind", 1, true) ~= nil, q)
  check("advice still cautions when the tag is weak / the blind might win",
    q:find("keep playing when the tag is weak", 1, true) ~= nil, q)
  unstub_valid()
end

local function shop_G(dollars)
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 }, P_BLINDS = {},
    GAME = {
      dollars = dollars, interest_cap = 25, round = 4,
      round_resets = { ante = 2, blind_choices = {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 },
      modifiers = {},
    },
    NEURO = { once_serials = {}, econ_plan_ok = true },
    jokers = { cards = { { ability = { mult = 4 }, config = { center = { key = "j_x", set = "Joker" } }, sell_cost = 3 } } },
    consumeables = { cards = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
  local PlanGate = require("core.plan_gate")
  G.NEURO.plan = { money = "hold", money_scope = PlanGate.current_economy_scope() }
end

stub_valid(function(n) return n == "buy_from_shop" or n == "toggle_shop" end)
local FS = require("force.force_shop")

do
  shop_G(8) -- flat joker (no xMult) -> weak build: the interest-banking nudge is now suppressed
  local q = ((FS.build() or {}).query or "") .. H.drain_hints()
  check("weak build (no xMult): banking nudge suppressed, scaling-gap fact shown instead",
    q:find("banking toward $", 1, true) == nil and q:find("None of your jokers multiply", 1, true) ~= nil, q)
end

do
  shop_G(8)
  G.jokers.cards[1].config.center.key = "j_hologram"
  G.jokers.cards[1].ability.x_mult = 2
  local q = ((FS.build() or {}).query or "") .. H.drain_hints()
  check("B1b strong build (permanent xMult owned): the scaling-gap claim is retracted",
    q:find("None of your jokers multiply", 1, true) == nil, q)
end

do
  shop_G(8)
  G.jokers.cards[1].config.center.key = "j_blackboard"
  local q = ((FS.build() or {}).query or "") .. H.drain_hints()
  check("B1c conditional xMult (Blackboard): no false 'None multiply' claim",
    q:find("None of your jokers multiply", 1, true) == nil, q)
end

do
  shop_G(30)
  local q = ((FS.build() or {}).query or "") .. H.drain_hints()
  check("above the cap: low-cash build hint does NOT fire",
    q:find("below the interest engine", 1, true) == nil, q)
end
unstub_valid()

do
  stub_valid(function(n)
    return (n == "play_hand" or n == "discard_hand") and real_is_action_valid(n)
  end)
  local FSH = require("force.force_selecting_hand")
  local VALN, RID = H.VALN, H.RID
  local NO_READY = "No hand above High Card is Ready from these cards"
  local DISCARD_LEAD = "No hand of Straight/Flush rank or better is Ready"
  local function hand_card(v, suit)
    local id = RID[v]
    return {
      base = { value = VALN[v] or v, suit = suit },
      config = { center = { key = "c_base", set = "Default" } },
      get_id = function() return id end,
      is_suit = function(_, s) return s == suit end,
    }
  end
  local function hand_state(opts)
    _G.G = {
      STATES = { BLIND_SELECT = 1, SELECTING_HAND = 2 },
      STATE = 2,
      hand = {
        cards = opts.cards,
        config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {},
      },
      GAME = {
        chips = 0,
        round_resets = { ante = 1 },
        current_round = { hands_left = 3, discards_left = opts.discards },
        blind = { chips = 1000, name = "Small Blind", debuff = {},
          config = { blind = { key = "bl_small" } } },
        hands = {},
      },
      FUNCS = { get_poker_hand_info = opts.info or function() return nil, nil, {} end },
      NEURO = { once_serials = {}, state_enter_serial = 1 },
    }
    return ((FSH.build() or {}).query or "") .. H.drain_hints()
  end
  local function junk()
    return { hand_card("3", "Spades"), hand_card("7", "Clubs"), hand_card("9", "Hearts"),
      hand_card("K", "Diamonds"), hand_card("2", "Spades") }
  end

  local q0 = hand_state({ cards = junk(), discards = 0 })
  check("no discards and no hand assembled: the query says nothing above High Card is Ready",
    q0:find(NO_READY, 1, true) ~= nil, q0)
  local said = q0:match("No hand above High Card.-%. ") or ""
  check("C1b the line never mentions discards, which this state does not have",
    said ~= "" and said:lower():find("discard", 1, true) == nil, said)
  check("C1c the line stays a fact, with no prescriptive wording",
    said ~= "" and not (said:lower():find("prefer", 1, true) or said:lower():find("should", 1, true)
      or said:lower():find("best", 1, true) or said:lower():find("must", 1, true)), said)
  check("C1d the discard-pool lead is not stated when there is no discard",
    q0:find(DISCARD_LEAD, 1, true) == nil and q0:find("Discards are a separate pool", 1, true) == nil, q0)

  local paired = { hand_card("3", "Spades"), hand_card("3", "Clubs"), hand_card("9", "Hearts"),
    hand_card("K", "Diamonds"), hand_card("2", "Spades") }
  local q1 = hand_state({
    cards = paired, discards = 0,
    info = function() return "Pair", nil, { Pair = { paired[1], paired[2] } }, { paired[1], paired[2] } end,
  })
  check("a Ready hand exists: the no-hand-Ready line is not stated",
    q1:find("Ready to play now: Pair", 1, true) ~= nil and q1:find(NO_READY, 1, true) == nil, q1)

  local q2 = hand_state({ cards = junk(), discards = 3 })
  check("with discards left the existing discard lead still fires instead",
    q2:find(DISCARD_LEAD, 1, true) ~= nil and q2:find(NO_READY, 1, true) == nil, q2)
  unstub_valid()
end

done()
