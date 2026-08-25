_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("audit-dedup")

do
  local CtxMisc = require("context.ctx_misc")
  _G.G = { deck = { cards = { 1, 2, 3 } }, discard = { cards = { 1 } },
           GAME = { selected_back = { name = "Blue Deck" }, back = { name = "Red Deck" } } }
  local line = CtxMisc.deck_size_line()
  check("DK| carries the discard-pile count", line and line:find("1 cards in the discard pile", 1, true) ~= nil, line)
  check("DK| no longer restates the deck name",
    line and line:find("N:", 1, true) == nil and line:find("Deck", 1, true) == nil, line)
end

do
  local CtxBlind = require("context.ctx_blind")
  local covered = { name = "The Window", debuff = { suit = "Diamonds" },
    loc_txt = { text = { "All Diamond cards are debuffed" } } }
  _G.G = { GAME = { blind = covered, hands = {} }, hand = { cards = {} } }
  local bd = CtxBlind.blind_debuff_line()
  check("boss FACT line renders for a curated suit boss",
    type(bd) == "string" and bd ~= "", bd)
  check("boss FACT line is the curated rule, not the raw engine sentence",
    bd ~= nil and bd:find("All Diamonds cards are debuffed this round", 1, true) ~= nil
      and bd:find("All Diamond cards are debuffed", 1, true) == nil, bd)
end

do
  local CtxShop = require("context.ctx_shop")
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    GAME = { dollars = 12, interest_cap = 25, round_resets = { ante = 2 },
             current_round = { free_rerolls = 0, reroll_cost = 5 }, modifiers = {} },
    NEURO = {}, shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local capped = tostring(CtxShop.shop_section() or "")
  check("SH| context line carries the SS: safe-spend field",
    capped:find("spend $2 while keeping this interest", 1, true) ~= nil, capped)

  G.GAME.modifiers = { no_interest = true }
  local equal = tostring(CtxShop.shop_section() or "")
  check("the no-interest shop line really rendered",
    equal:find("Interest disabled.", 1, true) ~= nil, equal)
  check("readable omits the safe-spend clause when it equals spendable",
    equal:find("while keeping this interest", 1, true) == nil, equal)
  G.GAME.modifiers = {}

  local Tuning = require("core.config");
  local Actions = require("core.actions")
  Actions.is_action_valid = function(n) return n == "buy_from_shop" or n == "toggle_shop" end
  local PlanGate = require("core.plan_gate")
  G.NEURO.econ_plan_ok = true
  G.NEURO.plan = { money = "hold", money_scope = PlanGate.current_economy_scope() }
  local q = (require("force.force_shop").build() or {}).query or ""
  check("the shop force query really was built",
    q:find("Your move:", 1, true) ~= nil, q)
  check("shop query emits no separate ECO|/Economy: economy line",
    q:find("ECO|", 1, true) == nil and q:find("Economy:", 1, true) == nil, q)
end

do
  local Tuning = require("core.config")

  local Actions = require("core.actions")
  Actions.is_action_valid = function(n) return n == "select_blind" or n == "skip_blind" or n == "reroll_boss" end
  local Guard = require("core.transition_guard")
  local saved = Guard.reject_reason
  Guard.reject_reason = function(name) return name == "reroll_boss" and "BUSY" or nil end
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 }, P_BLINDS = {},
    GAME = { win_ante = 8, dollars = 20, blind_on_deck = "Small",
      round_resets = { ante = 1, blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" } } },
    NEURO = { once_serials = {} }, jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local q = (require("force.force_blind_select").build() or {}).query or ""
  local ml = q:match("Your move:(.*)") or ""
  check("B guard-rejected reroll_boss is NOT in the move line", ml:find("reroll_boss", 1, true) == nil, ml)
  check("B non-rejected select_blind IS in the move line", ml:find("select_blind", 1, true) ~= nil, ml)
  Guard.reject_reason = saved
end

do
  local src = io.open("context/ctx_jokers.lua"):read("*a")
  check("ctx_jokers has no private reimplementation of the quantity-amount helper",
    src:find("local%s+function%s+amount%s*%(", 1, false) == nil, "found a local `function amount(...)`")
  check("ctx_jokers has no private reimplementation of the quantity-clause helper",
    src:find("local%s+function%s+quantity_clause%s*%(", 1, false) == nil,
    "found a local `function quantity_clause(...)`")
  check("ctx_jokers sources its quantity phrasing from ctx_helpers",
    src:find("CtxHelpers.quantity_amount", 1, true) ~= nil
      and src:find("CtxHelpers.quantity_clause", 1, true) ~= nil, "no CtxHelpers.quantity_* reference found")
end

done()
