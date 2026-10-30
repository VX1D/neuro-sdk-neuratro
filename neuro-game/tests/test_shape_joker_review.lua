require("tests.stubs").setup({ love = "lazy", localize = true, G = "hand" })

local H = require("tests.helpers")
local check, done = H.harness("shape-joker-review")
local HandHandlers = require("handlers.hand_handlers")
local ActionResult = require("core.action_result")
local Gate = require("core.gate")
local Vanilla = require("tests.fixtures.vanilla_jokers")
local card = require("tests.fake_cards").held_maker()

local card_lua = H.read_lines(os.getenv("BALATRO_DUMP"), "card.lua")
if #card_lua == 0 then require("tests.skip_ledger").bail("shape-joker-review", 19, "game dump not found; set BALATRO_DUMP") end
local function engine(head, follow, span)
  for i, text in ipairs(card_lua) do
    local hit = true
    for _, needle in ipairs(head) do hit = hit and text:find(needle, 1, true) ~= nil end
    if hit then
      local window = table.concat(card_lua, "\n", i, math.min(#card_lua, i + (span or 0)))
      for _, needle in ipairs(follow or {}) do
        if not window:find(needle, 1, true) then return false end
      end
      return true
    end
  end
  return false
end
check("engine: DNA copies only on the round's first hand, and only a single played card",
  engine({ "'DNA'", "G.GAME.current_round.hands_played == 0" }, { "#context.full_hand == 1" }, 1))
check("engine: Sixth Sense takes a lone 6 as the first hand",
  engine({ "'Sixth Sense'", "#context.full_hand == 1", "get_id() == 6", "hands_played == 0" }))
check("engine: Half Joker pays on size or fewer cards",
  engine({ "'Half Joker'", "#context.full_hand <= self.ability.extra.size" }))
check("engine: Square Joker grows on exactly 4 cards", engine({ "'Square Joker'", "#context.full_hand == 4" }))
check("engine: Card Sharp pays on a type played before this round", engine({ "'Card Sharp'", "played_this_round > 1" }))
check("engine: Obelisk grows unless the type is the most played",
  engine({ "'Obelisk'", "not context.blueprint" }, { "v.played >= play_more_than" }, 6))

local function setup(jokers, opts)
  opts = opts or {}
  G.hand = { cards = { card("A", "Clubs"), card("10", "Spades"), card("7", "Spades"), card("7", "Clubs"),
    card("6", "Diamonds"), card("4", "Hearts"), card("3", "Hearts"), card("3", "Diamonds") },
    config = { highlighted_limit = 5, card_limit = 8 }, highlighted = {} }
  G.GAME = { current_round = { discards_left = opts.discards or 4, hands_left = 5, hands_played = opts.played or 0 },
    hands = H.game_hands(opts.hands), blind = {} }
  G.FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").engine() }
  G.NEURO = {}
  G.jokers = { cards = jokers }
  H.in_engine_state("SELECTING_HAND")
  Gate.reset()
end

local function joker(key, mutate)
  local j = Vanilla.card(key, 900)
  if mutate then mutate(j) end
  return j
end

local function play(indices)
  local exec, err = HandHandlers.handle_play_hand({ indices = indices })
  return exec, require("tests.helpers").review_text(err)
end

local function commits(label, indices)
  local exec, msg = play(indices)
  check(label, type(exec) == "function" and Gate.proposal() == nil, msg)
end

local function reviewed(label, indices, needle)
  local exec, msg = play(indices)
  check(label, exec == nil and msg:find(needle, 1, true) ~= nil, msg)
end

setup({ joker("j_dna") })
commits("DNA: a lone Ace as the round's first hand commits without a review (L1600)", { 1 })
setup({ joker("j_dna") }, { played = 1 })
reviewed("DNA: after the first hand a lone Ace is reviewed as a bare High Card", { 1 }, "lowest-ranking")
setup({ joker("j_dna") })
reviewed("DNA: two cards on the first hand copy nothing and are reviewed", { 1, 2 }, "Review required")
setup({ joker("j_dna", function(j) j.debuff = true end) })
reviewed("DNA: a debuffed DNA copies nothing, so the play is reviewed", { 1 }, "lowest-ranking")
setup({ joker("j_dna", function(j) j.facing = "back" end) })
reviewed("DNA: a face-down joker is never assumed to be DNA", { 1 }, "lowest-ranking")

setup({ joker("j_sixth_sense") })
commits("Sixth Sense: a lone 6 as the round's first hand commits without a review", { 5 })
setup({ joker("j_sixth_sense") })
reviewed("Sixth Sense: a lone Ace is still a bare High Card", { 1 }, "lowest-ranking")

setup({ joker("j_half") })
local _, half = play({ 3, 4 })
check("Half Joker: a 2-card Pair is not called a lowest-ranking type",
  half:find("lowest-ranking", 1, true) == nil
    and half:find("Half Joker adds +20 Mult to this play because it has 3 or fewer cards.", 1, true) ~= nil, half)

setup({ joker("j_square") })
local _, square = play({ 3, 4, 7, 8 })
check("Square Joker: a 4-card Two Pair is not called a lowest-ranking type",
  square:find("lowest-ranking", 1, true) == nil
    and square:find("Square Joker gains +4 Chips for good because this play has exactly 4 cards.", 1, true) ~= nil, square)

setup({ joker("j_card_sharp") }, { hands = { Pair = { played_this_round = 1 } } })
local _, sharp = play({ 3, 4 })
check("Card Sharp: a Pair already played this round is not called a lowest-ranking type",
  sharp:find("lowest-ranking", 1, true) == nil
    and sharp:find("Card Sharp gives x3 Mult because you already played Pair this round.", 1, true) ~= nil, sharp)
setup({ joker("j_card_sharp") })
reviewed("Card Sharp: a first Pair this round earns nothing from it", { 3, 4 }, "lowest-ranking")

setup({ joker("j_obelisk") }, { hands = { Flush = { played = 5 } } })
local _, obelisk = play({ 3, 4 })
check("Obelisk: a Pair below the most played Flush is not called a lowest-ranking type",
  obelisk:find("lowest-ranking", 1, true) == nil
    and obelisk:find("Obelisk grows by x0.2 Mult because Pair is still not your most played hand.", 1, true) ~= nil,
  obelisk)
setup({ joker("j_obelisk") }, { hands = { Pair = { played = 5 } } })
reviewed("Obelisk: the most played Pair resets it, so it is reviewed as usual", { 3, 4 }, "lowest-ranking")

done()
