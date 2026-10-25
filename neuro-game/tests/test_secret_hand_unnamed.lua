require("tests.stubs").setup({ love = "lazy", localize = true })

local H = require("tests.helpers")
local EC = require("tests.engine_cards")
local HandInfo = require("tests.engine_hand_info")
local check, done = H.harness("secret hand unnamed")

local SECRET = { ["Five of a Kind"] = true, ["Flush House"] = true, ["Flush Five"] = true }

local function frame(five_visible)
  local g = H.base_G()
  g.NEURO.dispatcher = require("core.dispatcher"); g.NEURO.actions = require("core.actions"); g.NEURO.persona = "neuro"
  g.deck = { cards = {}, config = { card_limit = 52 } }
  g.discard = { cards = {} }
  g.play = { cards = {} }
  local hand = {}
  local spec = { { "Ace", "Spades" }, { "Ace", "Hearts" }, { "Ace", "Clubs" }, { "Ace", "Diamonds" },
    { "7", "Clubs" }, { "4", "Hearts" }, { "9", "Spades" }, { "2", "Diamonds" } }
  for i, d in ipairs(spec) do
    local c = EC.playing(d[1], d[2], { sort_id = i })
    c.area = g.hand; hand[i] = c; g.playing_cards[i] = c
  end
  g.hand.cards = hand
  for i, d in ipairs({ { "Ace", "Spades" }, { "King", "Clubs" }, { "5", "Hearts" } }) do
    local c = EC.playing(d[1], d[2], { sort_id = 100 + i })
    c.area, c.facing = g.deck, "back"
    g.deck.cards[i] = c; g.playing_cards[#g.playing_cards + 1] = c
  end
  g.jokers.cards = {}
  g.FUNCS.get_poker_hand_info = HandInfo.engine()
  for _, n in ipairs(HandInfo.HANDLIST) do
    g.GAME.hands[n] = { level = 1, chips = 10, mult = 2, played = 0, played_this_round = 0, order = 1,
      visible = not SECRET[n] or (n == "Five of a Kind" and five_visible) }
  end
  g.GAME.current_round.discards_left = 3
  H.in_engine_state("SELECTING_HAND")
  require("core.validate").reset_run_state()
  local s, q = H.force_frame("SELECTING_HAND")
  return s .. "\n" .. q
end

local hidden = frame(false)
check("a secret Five of a Kind is not named one card away", hidden:find("Five of a Kind", 1, true) == nil,
  hidden:match("One card away[^\n]*"))
local shown = frame(true)
check("once the game reveals it, it is", shown:find("One card away: Five of a Kind", 1, true) ~= nil,
  shown:match("One card away[^\n]*"))

done()
