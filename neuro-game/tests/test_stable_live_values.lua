_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function(_, vars)
  local c = vars and vars.nodes and vars.nodes[1]
  return c or ""
end

local check, done = require("tests.helpers").harness("stable-live-values")
local Compact = require("context.context_compact")
local Delivery = require("core.context_delivery")

local function joker(name, text)
  return { ability = { name = name, set = "Joker", extra = 8 }, sell_cost = 3,
    config = { center = { key = "j_test", name = name, set = "Joker",
      loc_txt = { name = name, text = { text } } } } }
end

local sent = {}
local function world(name, dollars, voucher, modifier)
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1 }, P_CENTERS = {},
    GAME = { dollars = dollars, chips = 0, bankrupt_at = 0, used_vouchers = voucher and { [voucher] = true } or {},
      current_round = { hands_left = 3, discards_left = 2, reroll_cost = 5 },
      round_resets = { ante = 2 }, probabilities = { normal = 1 }, modifiers = modifier or {},
      blind = { name = "Small Blind", chips = 300, mult = 1 } },
    jokers = { cards = name and { joker(name, "Currently +" .. tostring(dollars) .. " Chips") } or {},
      config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {} }, playing_cards = {},
    NEURO = { run_generation = 1, once_serials = {}, session_once_serials = {},
      send_context = function(_, msg, silent, receipt)
        sent[#sent + 1] = { msg = msg, silent = silent }
        receipt.status = "written"
        return true
      end },
  }
  Compact.invalidate_cache()
end

world("Bull", 8, "v_hone", {})
local rule_a = Compact.build("SELECTING_HAND", nil, { split = "rule", no_cache = true }) or ""
local state_a = Compact.build("SELECTING_HAND", nil, { split = "state", no_cache = true }) or ""
world("Blue Joker", 18, "v_glow_up", { no_interest = true })
local rule_b = Compact.build("SELECTING_HAND", nil, { split = "rule", no_cache = true }) or ""
local state_b = Compact.build("SELECTING_HAND", nil, { split = "state", no_cache = true }) or ""

check("retained-rule bytes are invariant under cash/roster/voucher/modifier mutation", rule_a == rule_b,
  rule_a .. " || " .. rule_b)
check("retained rules contain no live roster", not rule_a:find("Joker details:", 1, true)
  and not rule_a:find("Vouchers you own", 1, true) and not rule_a:find("Currently +8", 1, true), rule_a)
check("ephemeral state changes with the board", state_a ~= state_b)
check("old state names only the old roster", state_a:find("Bull", 1, true) ~= nil
  and state_a:find("Blue Joker", 1, true) == nil, state_a)
check("new state names only the new roster", state_b:find("Blue Joker", 1, true) ~= nil
  and state_b:find("Bull", 1, true) == nil, state_b)
check("current vouchers remain in ephemeral state", state_a:lower():find("hone", 1, true) ~= nil
  and state_b:lower():find("glow_up", 1, true) ~= nil, state_a .. " || " .. state_b)

Delivery.reset_transport()
Delivery.rule("frame", rule_a)
Delivery.rule("frame", rule_a)
check("an immutable rule is physically written once and silently", #sent == 1 and sent[1].silent == true,
  tostring(#sent))

done()
