-- Cash-out resets the round score, but Last hand must retain the settled score of the final hand.
require("tests.stubs").setup({ love = "lazy" })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("last-play-after-cash-out")
local Journal = require("core.gameplay_journal")
local CtxHand = require("context.ctx_hand")

local function base_game(chips)
  _G.G = {
    STATE = ES.SELECTING_HAND,
    STATES = ES,
    GAME = {
      chips = chips,
      round = 2,
      blind = { name = "Small Blind", chips = 300, config = { blind = { key = "bl_small" } } },
      round_resets = { ante = 1 },
      current_round = { hands_left = 3, discards_left = 2 },
      hands = { ["Two Pair"] = { visible = true, level = 1 } },
      dollars = 4,
    },
    NEURO = { run_generation = 3, decision_serial = 5, plan_revision = 0 },
    E_MANAGER = { queues = {} },
    play = { cards = {} },
  }
end

local function last_play(id, pre, zeroed)
  return {
    kind = "play", action_id = id, run_generation = 3,
    ante = 1, round = 2, blind_key = "bl_small", hand_type = "Two Pair", hand_level = 1,
    played = 4, scored = zeroed and 0 or 4, zeroed = zeroed, pre_chips = pre,
  }
end

base_game(884)
G.NEURO.last_play = last_play("opening-hand", 0)
check("the settled hand is observed", Journal.observe_settled("ROUND_EVAL") == true)
local eval_line = CtxHand.last_play_section("ROUND_EVAL")
check("round eval reports the hand's score", eval_line ==
  "Last hand: Two Pair, played 4 cards, 4 scored, +884 chips, now 884/300, target cleared.", eval_line)
G.GAME.chips = 0
local shop_line = CtxHand.last_play_section("SHOP")
check("shop keeps the hand's real score after the reset", shop_line ==
  "Last hand: Two Pair, played 4 cards, 4 scored, +884 chips.", shop_line)

base_game(350)
G.NEURO.last_play = last_play("later-hand", 200)
check("the later hand is observed", Journal.observe_settled("ROUND_EVAL") == true)
G.GAME.chips = 0
shop_line = CtxHand.last_play_section("SHOP")
check("a later hand also keeps its score after the reset", shop_line ==
  "Last hand: Two Pair, played 4 cards, 4 scored, +150 chips.", shop_line)

base_game(0)
G.NEURO.last_play = last_play("zeroed-hand", 0, "zeroed by The Mouth")
check("the zeroed hand is observed", Journal.observe_settled("SELECTING_HAND") == true)
local zeroed_line = CtxHand.last_play_section("SELECTING_HAND")
check("a zeroed hand still reports +0 chips", zeroed_line ==
  "Last hand: Two Pair, played 4 cards, 0 scored, zeroed by The Mouth, +0 chips, now 0/300, 300 short.", zeroed_line)

done()
