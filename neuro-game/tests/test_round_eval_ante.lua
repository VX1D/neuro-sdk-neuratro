rawset(_G, "NEURO_TEST", true)
love = { timer = { getTime = function() return 0 end } }

local check, done = require("tests.helpers").harness("round eval ante")

local function board(ante, blind_ante, boss)
  _G.G = {
    NEURO = { blind_reward_cache = 8, blind_reward_round = 3 },
    STATE = 7, STATES = { ROUND_EVAL = 7, SELECTING_HAND = 1, SHOP = 2 },
    P_BLINDS = {},
    jokers = { cards = {} }, consumeables = { cards = {} },
    hand = { cards = {}, highlighted = {} }, deck = { cards = {} },
    TIMERS = { REAL = 0 },
    GAME = {
      dollars = 21, chips = 3000, win_ante = 8, used_vouchers = {}, modifiers = {},
      round = 3, skips = 0, interest_amount = 1, interest_cap = 25,
      blind = { name = boss and "The Wall" or "Big Blind", chips = 2800, dollars = 8, boss = boss },
      current_round = { hands_left = 2, discards_left = 1, dollars_to_be_earned = "" },
      round_resets = { ante = ante, blind_ante = blind_ante, blind_states = {}, blind_choices = {} },
      hands = {},
    },
    FUNCS = {},
  }
  return tostring(require("context.ctx_blind").round_eval_section())
end

local boss_cleared = board(4, 3, true)
check("boss of ante 3 cleared: ROUND_EVAL says ante 3, not the already-bumped 4",
  boss_cleared:find("Round 3 of ante 3 cleared", 1, true) ~= nil, boss_cleared)

local big_cleared = board(3, 3, false)
check("Big blind of ante 3 cleared: same sentence stays right",
  big_cleared:find("Round 3 of ante 3 cleared", 1, true) ~= nil, big_cleared)

local no_blind_ante = board(5, nil, false)
check("no blind_ante on the board: falls back to round_resets.ante",
  no_blind_ante:find("Round 3 of ante 5 cleared", 1, true) ~= nil, no_blind_ante)

done()
