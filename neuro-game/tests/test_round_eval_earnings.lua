_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("round-eval-earnings")

local EF = require("facts.economy_facts")
local GameFacts = require("facts.game_facts")
local CtxHelpers = require("context.ctx_helpers")

local function fresh(blind, money, hands_left, discards_left, score)
  _G.G = { NEURO = {}, GAME = {
    dollars = money or 0,
    chips = score or 1e9,   -- score vs blind.chips decides "cleared" (default: comfortably cleared)
    blind = blind,
    current_round = { hands_left = hands_left or 0, discards_left = discards_left or 0, dollars_to_be_earned = "" },
    modifiers = {},
  } }
end

local function simulate_defeat(blind)
  local cleared = (tonumber(G.GAME.chips) or 0) >= (tonumber(blind.chips) or 0)
  G.NEURO.blind_reward_cache = cleared and (tonumber(blind.dollars) or 0) or 0
end

fresh({ dollars = 5 }, 0, 3, 0)
check("blind_reward reads 0 before any defeat", GameFacts.blind_reward() == 0, GameFacts.blind_reward())
simulate_defeat(G.GAME.blind)
check("blind_reward reflects the recorded reward", GameFacts.blind_reward() == 5, GameFacts.blind_reward())

G.GAME.blind.dollars = 0
check("cache survives the game zeroing blind.dollars", GameFacts.blind_reward() == 5, GameFacts.blind_reward())

local e = EF.economy_projection({ round_eval = true })
check("round_eval blind reward = recorded $5", e and e.blind_reward == 5, e and e.blind_reward)
check("round_eval hands bonus full remaining (no -1)", e and e.hands_bonus == 3, e and e.hands_bonus)
check("round_eval total = 5 + 3 = 8", e and e.projected_total == 8, e and e.projected_total)

fresh({ dollars = 4 }, 10, 2, 0)
simulate_defeat(G.GAME.blind)
local e2 = EF.economy_projection({ round_eval = true })
check("round_eval reward overwritten to new blind ($4)", e2 and e2.blind_reward == 4, e2 and e2.blind_reward)
check("round_eval total = 4 + 2(hands) + 2(interest) = 8", e2 and e2.projected_total == 8, e2 and e2.projected_total)

fresh({ dollars = 0 }, 0, 2, 0)
simulate_defeat(G.GAME.blind)
check("no_blind_reward blind records 0", EF.economy_projection({ round_eval = true }).blind_reward == 0)

fresh({ dollars = 5, chips = 1000 }, 0, 0, 0, 500)
simulate_defeat(G.GAME.blind)
check("saved (failed) blind records 0, not the nominal reward", GameFacts.blind_reward() == 0, GameFacts.blind_reward())
check("round_eval on a saved blind = 0 blind reward", EF.economy_projection({ round_eval = true }).blind_reward == 0)

fresh({ dollars = 5, chips = 1000 }, 0, 2, 0, 1200)
simulate_defeat(G.GAME.blind)
check("cleared blind (score >= requirement) records $5", EF.economy_projection({ round_eval = true }).blind_reward == 5)

fresh({ in_blind = true, dollars = 4 }, 0, 2, 1)
local sh = EF.economy_projection({ selecting_hand = true })
check("selecting_hand still reads live blind.dollars ($4)", sh and sh.blind_reward == 4, sh and sh.blind_reward)
check("selecting_hand still applies the -1 hand projection", sh and sh.hands_bonus == 1, sh and sh.hands_bonus)

fresh({ dollars = 20, in_blind = true }, 20, 2, 0)
G.jokers = { cards = { {
  ability = { set = "Joker", name = "Golden Joker", extra = 4 },
  config = { center = { key = "j_golden" } },
} } }
G.GAME.tags = { { name = "Investment Tag", config = { dollars = 25 } } }
local e3 = EF.economy_projection({ selecting_hand = true })
check("projection is unaffected by a present Golden Joker/Investment Tag (true payout is $29 higher)",
  e3.projected_total == 25, e3.projected_total)

local payout = CtxHelpers.decode_payout(e3)
check("the cash-out sentence names jokers as excluded", payout:find("jokers", 1, true) ~= nil, payout)
check("the cash-out sentence names tags as excluded", payout:find("tags", 1, true) ~= nil, payout)
check("the cash-out sentence says they add to the number, not subtract", payout:find("add more", 1, true) ~= nil, payout)

do
  _G.G = { NEURO = {}, STATE = 1, STATES = { SELECTING_HAND = 1 }, P_BLINDS = {},
    jokers = { cards = {} }, consumeables = { cards = {} }, hand = { cards = {}, highlighted = {} },
    GAME = {
      dollars = 4, chips = 0, win_ante = 8, used_vouchers = {}, modifiers = {},
      blind = { name = "Big Blind", chips = 600, dollars = 4, in_blind = true },
      current_round = { hands_left = 4, discards_left = 3, dollars_to_be_earned = "" },
      round_resets = { ante = 2, blind_ante = 2 },
    } }
  local line = require("context.ctx_blind").blind_line() or ""
  check("the blind line still prints the live hand count", line:find("4 hands and", 1, true) ~= nil, line)
  check("the cash-out figure prices the 3 hands that survive this play, not 4",
    line:find("hands $3", 1, true) ~= nil, line)
  check("the cash-out label does not claim the round could end now",
    line:find("Cash%-out if the round ended now") == nil, line)
  check("the cash-out label names the play it is conditioned on",
    line:find("Cash-out if this hand clears the blind", 1, true) ~= nil, line)
end

done()
