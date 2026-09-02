_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function(a)
  if type(a) == "table" and a.type == "raw_descriptions" then return { "All Heart cards are debuffed" } end
  return ""
end

local check, done = require("tests.helpers").harness("shop-boss-primer")
local H = require("tests.helpers")

local function fresh_G(with_boss)
  require("core.context_delivery").reset_transport()
  require("facts.fact_hints").reset_pending()
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    P_BLINDS = { bl_head = { name = "The Head", key = "bl_head", set = "Blind", debuff = {} } },
    GAME = {
      dollars = 8, interest_cap = 25, round = 4,
      round_resets = { ante = 2, blind_choices = with_boss and { Boss = "bl_head" } or {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 },
      modifiers = {},
    },
    NEURO = { once_serials = {}, session_once_serials = {}, run_generation = 1,
      state_enter_serial = 1, decision_serial = 1 },
    jokers = { cards = {} }, consumeables = { cards = {} },
    shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
  }
end

local Actions = require("core.actions")
Actions.is_action_valid = function(n) return n == "leave_shop" end
local FS = require("force.force_shop")

local function force()
  local q = (FS.build() or {}).query or ""
  return q, H.drain_hints()
end

local HEAD_SELECT = "Boss (The Head): All Hearts cards are debuffed this round (marked +DB): they score 0"
  .. " chips and their abilities are off, but they still count toward forming a hand. Every Wild Card counts"
  .. " as every suit, so Wild Cards are debuffed too; Stone Cards have no suit and are not."

fresh_G(true)
check("the primer body is EXACTLY the extracted select renderer output (facts only, no steering)",
  require("facts.boss.render").render("select", "bl_head") == HEAD_SELECT,
  require("facts.boss.render").render("select", "bl_head"))
local qa, ra = force()
check("primer present with boss on-deck", qa:find("Upcoming " .. HEAD_SELECT, 1, true) ~= nil, qa)
check("primer names the SPECIFIC effect", qa:find("All Hearts cards are debuffed", 1, true) ~= nil)
check("primer carries no advisory framing beyond the renderer output",
  qa:find(HEAD_SELECT .. " --", 1, true) == nil, qa)
check("the primer rides the ephemeral force, never the retained context channel",
  ra:find("Upcoming Boss", 1, true) == nil and ra:find("debuff", 1, true) == nil, ra)

local qb = force()
check("primer restated on the next decision of the SAME shop entry",
  qb:find("Upcoming " .. HEAD_SELECT, 1, true) ~= nil, qb)
G.NEURO.decision_serial = G.NEURO.decision_serial + 1
local qb1 = force()
check("B1b and on the decision after that", qb1:find("Upcoming " .. HEAD_SELECT, 1, true) ~= nil, qb1)

G.NEURO.state_enter_serial = (G.NEURO.state_enter_serial or 0) + 1
local qb2 = force()
check("primer re-shows on a new shop entry within the SAME ante",
  qb2:find("Upcoming " .. HEAD_SELECT, 1, true) ~= nil, qb2)

G.NEURO.state_enter_serial = (G.NEURO.state_enter_serial or 0) + 1
G.GAME.round_resets.ante = 3
local qc = force()
check("primer shows again on a new shop entry", qc:find("Upcoming " .. HEAD_SELECT, 1, true) ~= nil, qc)

fresh_G(false)
local qd, rd = force()
check("no boss/debuff text when no boss on-deck",
  qd:find("Upcoming Boss", 1, true) == nil and qd:lower():find("debuff", 1, true) == nil, qd)
check("and none on the retained channel either", rd:lower():find("debuff", 1, true) == nil, rd)

local MARK = {
  jokerless_priority = "You own NO jokers",
  scaling_gap        = "None of your jokers multiply",
  build_mgmt         = "As you plan, weigh your joker build",
  idle_slot          = "empty joker slot",
  unleveled_hands    = "poker hands are all still at base level",
}
local function verdicts(label, q, r, want, unwanted)
  local text = q .. " || " .. r
  for _, tag in ipairs(want or {}) do
    check("E " .. label .. ": the roster draws " .. tag,
      text:find(MARK[tag], 1, true) ~= nil, text)
  end
  for _, tag in ipairs(unwanted or {}) do
    check("E " .. label .. ": the roster does not draw " .. tag,
      text:find(MARK[tag], 1, true) == nil, text)
  end
end

local FLAT = { config = { center = { key = "j_joker", set = "Joker", name = "Joker" } },
  ability = { name = "Joker", set = "Joker", mult = 4 }, sell_cost = 2 }
local XMULT = { config = { center = { key = "j_hologram", set = "Joker", name = "Hologram" } },
  ability = { name = "Hologram", set = "Joker", x_mult = 2.5 }, sell_cost = 2 }
local ICE = { config = { center = { key = "j_ice_cream", set = "Joker", name = "Ice Cream" } },
  ability = { name = "Ice Cream", set = "Joker", mult = 0 }, sell_cost = 2 }

fresh_G(false)
do local q, r = force(); verdicts("empty roster", q, r, { "jokerless_priority" }, { "scaling_gap" }) end

fresh_G(false)
G.jokers.cards = { FLAT }
do
  local q, r = force()
  verdicts("flat +Mult only, an empty slot and an affordable joker in stock", q, r,
    { "scaling_gap" }, { "jokerless_priority" })
end

fresh_G(false)
G.jokers.cards = { XMULT }
do
  local q, r = force()
  verdicts("xMult owned", q, r, nil, { "scaling_gap", "jokerless_priority" })
end

do
  local narrow_valid = Actions.is_action_valid
  Actions.is_action_valid = function(n)
    return n == "leave_shop" or n == "sell_card" or n == "set_joker_order"
  end
  fresh_G(false)
  G.jokers.cards = { FLAT, ICE }
  local qm, rm = force()
  verdicts("sell_card and set_joker_order both offered", qm, rm,
    { "build_mgmt", "scaling_gap" }, { "jokerless_priority" })
  check("E offer: the legal forms for reordering are still stated",
    qm:find("set_joker_order", 1, true) ~= nil, qm)
  check("E offer: and so is selling", qm:find("sell_card", 1, true) ~= nil, qm)
  check("the shop force does not duplicate the timeless trigger-order explainer",
    qm:find("your jokers fire left to right", 1, true) == nil
      and qm:find("before any joker's flat +Mult", 1, true) == nil, qm)
  Actions.is_action_valid = narrow_valid
end

done()
