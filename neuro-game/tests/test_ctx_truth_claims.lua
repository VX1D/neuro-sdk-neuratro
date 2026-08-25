_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("ctx-truth-claims")
local Actions = require("core.actions")

_G.get_blind_amount = function() return 300 end

local function P_BLINDS(extra)
  local t = {
    bl_small = { name = "Small Blind", mult = 1, dollars = 3 },
    bl_big = { name = "Big Blind", mult = 1.5, dollars = 4 },
    bl_manacle = { name = "The Manacle", mult = 2, dollars = 5 },
    bl_hook = { name = "The Hook", mult = 2, dollars = 5 },
    bl_wall = { name = "The Wall", mult = 4, dollars = 5 },
  }
  for k, v in pairs(extra or {}) do
    for kk, vv in pairs(v) do t[k][kk] = vv end
  end
  return t
end

local function blind_select(opts)
  opts = opts or {}
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 }, P_BLINDS = P_BLINDS(opts.blind_extra),
    P_TAGS = {},
    GAME = {
      win_ante = 8, dollars = 30, blind_on_deck = "Small", chips = 0,
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      used_vouchers = {}, modifiers = {}, bosses_used = opts.bosses_used,
      round_resets = {
        ante = 3, blind_ante = 3, hands = 4, discards = 3,
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = opts.boss or "bl_manacle" },
        boss_rerolled = opts.boss_rerolled or false,
      },
    },
    NEURO = { once_serials = {} },
    jokers = { cards = {} }, consumeables = { cards = {} },
  }
  Actions.is_action_valid = function(n) return n == "select_blind" end
  return require("context.ctx_blind").blind_select_section() or ""
end

do
  local rerolled = blind_select({
    bosses_used = { boss = { bl_wall = 1, bl_hook = 1, bl_manacle = 1 } },
    boss_rerolled = true,
  })
  check("a rerolled-away boss is never called beaten",
    rerolled:find("The Hook", 1, true) == nil, rerolled)
  check("no bosses-beaten roster is emitted at all",
    rerolled:lower():find("beaten", 1, true) == nil, rerolled)

  local plain = blind_select({ bosses_used = { boss = { bl_wall = 1, bl_manacle = 1 } } })
  check("the roster stays gone even when every entry happens to be genuine",
    plain:lower():find("beaten", 1, true) == nil, plain)
  check("bosses_used drives no roster line of any name",
    plain:find("The Wall", 1, true) == nil, plain)
  check("the blind rows themselves still render",
    plain:find("Small Blind", 1, true) ~= nil, plain)
end

do
  local s = blind_select({ blind_extra = { bl_small = { debuff = { text = "Can you beat it?" } } } })
  local row = s:match("[^\n]*Can you beat it[^\n]*") or ""
  check("a row whose effect ends in a question mark gets no trailing full stop",
    row ~= "" and row:find("?.", 1, true) == nil, row)

  local e = blind_select({ blind_extra = { bl_small = { debuff = { text = "Beat it!" } } } })
  local erow = e:match("[^\n]*Beat it[^\n]*") or ""
  check("a row whose effect ends in an exclamation mark gets no trailing full stop",
    erow ~= "" and erow:find("!.", 1, true) == nil, erow)

  local d = blind_select({ blind_extra = { bl_small = { debuff = { text = "Hand size is 1 lower." } } } })
  check("a row whose effect ends in a full stop still gets no second one",
    d:find("%.%.") == nil, d:match("[^\n]*%.%.[^\n]*") or d)
end

do
  local DeckFacts = require("facts.deck_facts")
  local ghost = DeckFacts.DECK_INFO["Ghost Deck"] or ""
  check("Ghost Deck names the Polychrome", ghost:find("Polychrome", 1, true) ~= nil, ghost)
  check("Ghost Deck also names the joker destruction Hex pays for it with",
    ghost:lower():find("destroy") ~= nil, ghost)
end

do
  local function shop_line(no_interest, dollars)
    _G.G = {
      STATE = 5, STATES = { SHOP = 5 },
      P_BLINDS = P_BLINDS(), P_TAGS = {},
      GAME = {
        win_ante = 8, dollars = dollars, blind_on_deck = "Small", chips = 0,
        current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
        used_vouchers = {}, modifiers = { no_interest = no_interest or nil },
        round_resets = { ante = 3, blind_ante = 3, hands = 4, discards = 3,
          blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
          blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_manacle" } },
      },
      NEURO = { once_serials = {} },
      jokers = { cards = {} }, consumeables = { cards = {} },
      shop_jokers = { cards = {} }, shop_vouchers = { cards = {} }, shop_booster = { cards = {} },
    }
    local s = require("context.ctx_shop").shop_section() or ""
    return s:match("Interest[^\n]-%.") or s
  end

  local off = shop_line(true, 30)
  check("a no-interest run says interest is disabled", off:find("Interest disabled", 1, true) ~= nil, off)
  check("a no-interest run never claims an interest cap was reached",
    off:find("at cap", 1, true) == nil, off)
  check("a no-interest run never quotes a distance to the next interest step",
    off:find("to next step", 1, true) == nil, off)

  local on_cap = shop_line(false, 30)
  check("a normal run at $30 still reports the cap", on_cap:find("at cap", 1, true) ~= nil, on_cap)
  local on_mid = shop_line(false, 12)
  check("a normal run below the cap still reports the next step",
    on_mid:find("to next step", 1, true) ~= nil, on_mid)
end

done()
