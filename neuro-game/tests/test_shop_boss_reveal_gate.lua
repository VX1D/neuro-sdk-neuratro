_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function(a)
  if type(a) == "table" and a.type == "raw_descriptions" then return { "raw" } end
  return ""
end

local check, done = require("tests.helpers").harness("shop-boss-reveal-gate")

local function fresh_G(boss, states)
  require("core.context_delivery").reset_transport()
  require("facts.fact_hints").reset_pending()
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    P_BLINDS = {
      bl_hook = { name = "The Hook", key = "bl_hook", set = "Blind", debuff = {} },
      bl_club = { name = "The Club", key = "bl_club", set = "Blind", debuff = {} },
    },
    GAME = {
      dollars = 8, interest_cap = 25, round = 4,
      round_resets = { ante = 2, blind_choices = { Boss = boss }, blind_states = states },
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
Actions.is_action_valid = function(n) return n == "toggle_shop" end
local FS = require("force.force_shop")

local function query(boss, states)
  fresh_G(boss, states)
  return (FS.build() or {}).query or ""
end

local HOOK = "2 random cards are discarded"
local CLUB = "All Clubs cards are debuffed"

do
  local rollover = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" }
  local a, b = query("bl_hook", rollover), query("bl_club", rollover)
  check("post-boss shop: the payload does not vary with the freshly rolled boss", a == b,
    "A=" .. (a:match("Upcoming Boss[^\n]*") or "<none>")
      .. "\nB=" .. (b:match("Upcoming Boss[^\n]*") or "<none>"))
  check("and it names neither boss's effect",
    a:find(HOOK, 1, true) == nil and a:find(CLUB, 1, true) == nil
      and b:find(HOOK, 1, true) == nil and b:find(CLUB, 1, true) == nil, a)
  check("nor the label the primer rides on", a:find("Upcoming Boss", 1, true) == nil, a)
end

local MID_ANTE = {
  ["after Small, Big not yet on deck"] = { Small = "Defeated", Big = "Upcoming", Boss = "Upcoming" },
  ["after Small, Big on deck"]         = { Small = "Defeated", Big = "Select", Boss = "Upcoming" },
  ["after Big"]                        = { Small = "Defeated", Big = "Defeated", Boss = "Upcoming" },
  ["Small skipped, after Big"]         = { Small = "Skipped", Big = "Defeated", Boss = "Upcoming" },
  ["both skipped, Boss on deck"]       = { Small = "Skipped", Big = "Skipped", Boss = "Select" },
}
for label, states in pairs(MID_ANTE) do
  local q = query("bl_hook", states)
  check("B " .. label .. ": the primer still ships", q:find("Upcoming Boss (The Hook)", 1, true) ~= nil, q)
  check("B " .. label .. ": with the specific effect", q:find(HOOK, 1, true) ~= nil, q)
end

do
  local q = query("bl_hook", nil)
  check("C no blind_states recorded: the primer is not withheld",
    q:find("Upcoming Boss (The Hook)", 1, true) ~= nil, q)
end

done()
