_G.NEURO_TEST = true
local unpack = unpack or table.unpack
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("hand_commit_identity")
local HandHandlers = require("handlers.hand_handlers")

local function card(id)
  return {
    sort_id = id,
    base = { value = tostring(id + 1), suit = "Spades" },
    ability = { set = "Default", name = "Card " .. id },
    config = { center = { key = "c_base", set = "Default" } },
  }
end

local function setup()
  local cards = { card(1), card(2), card(3), card(4), card(5) }
  local executed
  _G.G = {
    hand = { cards = cards, highlighted = {}, config = { highlighted_limit = 5, card_limit = 8 } },
    GAME = {
      current_round = { hands_left = 4, discards_left = 3 },
      hands = { Pair = { level = 1, chips = 10, mult = 2 } },
      blind = {},
    },
    FUNCS = {
      get_poker_hand_info = function(selected)
        return "Pair", {}, { Pair = { selected } }, selected
      end,
      play_cards_from_highlighted = function()
        executed = { kind = "play", cards = { unpack(G.hand.highlighted) } }
      end,
      discard_cards_from_highlighted = function()
        executed = { kind = "discard", cards = { unpack(G.hand.highlighted) } }
      end,
    },
    NEURO = {
      decision_serial = 1,
      weak_fired_serial = 1,
      ai_highlighted = setmetatable({}, { __mode = "k" }),
    },
  }
  return cards, function() return executed end
end

do
  local cards, execution = setup()
  local confirmed = { cards[1], cards[2], cards[3] }
  G.NEURO.play_confirm = {
    signature = HandHandlers.play_signature(confirmed),
    content = HandHandlers.play_content(confirmed),
    indices = { 1, 2, 3 },
    decision_serial = 1,
    run_generation = 0,
  }
  local commit = HandHandlers.handle_play_hand({ indices = { 1, 2, 3 } })
  check("play prepares an executor", type(commit) == "function")
  G.hand.cards = { cards[5], cards[4], cards[3], cards[2], cards[1] }
  commit()
  local ran = execution()
  check("play executes the objects selected during validation",
    ran and ran.kind == "play" and ran.cards[1] == cards[1]
      and ran.cards[2] == cards[2] and ran.cards[3] == cards[3])
  check("play does not substitute cards now occupying the old indices",
    ran and ran.cards[1] ~= cards[5] and ran.cards[2] ~= cards[4])
end

do
  local cards, execution = setup()
  local commit = HandHandlers.handle_discard_hand({ indices = { 1, 2, 3 } })
  check("discard prepares an executor", type(commit) == "function")
  G.hand.cards = { cards[5], cards[4], cards[3], cards[2], cards[1] }
  commit()
  local ran = execution()
  check("discard executes the objects selected during validation",
    ran and ran.kind == "discard" and ran.cards[1] == cards[1]
      and ran.cards[2] == cards[2] and ran.cards[3] == cards[3])
  check("discard does not substitute cards now occupying the old indices",
    ran and ran.cards[1] ~= cards[5] and ran.cards[2] ~= cards[4])
end

do
  local cards, execution = setup()
  local commit = HandHandlers.handle_discard_hand({ indices = { 1, 2 } })
  check("missing-card fixture prepares an executor", type(commit) == "function")
  G.hand.cards = { cards[2], cards[3], cards[4], cards[5] }
  local result = commit()
  check("a missing selected object aborts the whole engine action", execution() == nil)
  check("a missing selected object reports that the hand changed",
    type(result) == "string" and result:find("no longer in the hand", 1, true) ~= nil, result)
end

done()
