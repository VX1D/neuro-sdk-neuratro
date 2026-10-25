require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("prose-channel-fixes")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Gate = require("core.gate")

LB.CONSUMABLE_TEXT.c_magician = { "Enhances 2 selected cards to Lucky Cards" }

local function has(text, needle) return (text or ""):find(needle, 1, true) ~= nil end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  local magician = LB.consumable("c_magician", 720)
  magician.area = G.shop_jokers
  G.shop_jokers.cards = { magician }
  local p = FP.build("SHOP")
  local q, s = p and p.query or "", p and p.state or ""
  check("the shop row in the state says how many cards The Magician targets",
    s:match("1%. The Magician %(Tarot%)[^\n]*targets 1 to 2 cards") ~= nil, s)
  check("and no longer states the count as a fact", not has(q, "targets 1-2 hand cards"), q)
end

do
  local real_final, real_decline = Gate.final_play_required, Gate.decline_context
  Gate.final_play_required = function() return true end
  Gate.decline_context = function() return { indices = { 1, 2 } } end
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  G.FUNCS.get_poker_hand_info = require("tests.engine_hand_info").engine()
  G.hand.cards[2].facing = "back"
  local q = (require("force.force_router").get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("a declined hidden selection says its type is hidden because of the face-down card",
    has(q, "indices [1,2] = type hidden: the selection includes face-down card 2."), q)
  check("and never prints an unexplained unknown", not has(q, "unknown hand type"), q)

  G.hand.cards[2].facing = "front"
  q = (require("force.force_router").get_force_for_state("SELECTING_HAND") or {}).query or ""
  check("with no face-down card selected it claims no hidden card", has(q, "indices [1,2] = type not named."), q)
  Gate.final_play_required, Gate.decline_context = real_final, real_decline
end

done()
