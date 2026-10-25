require("tests.stubs").setup({ love = "lazy", localize = true })

local H = require("tests.helpers")
local EC = require("tests.engine_cards")
local HandInfo = require("tests.engine_hand_info")
local check, done = H.harness("hidden boss verdict")

local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King", "Ace" }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
local VISIBLE = { "KingSpades", "KingHearts", "9Hearts", "5Diamonds", "3Spades", "7Clubs", "AceHearts" }
local HIDDEN_SLOT = 3

local function board(hidden_key, blind, setup)
  local g = H.base_G()
  g.discard, g.play = { cards = {} }, { cards = {} }
  g.deck = { cards = {}, config = { card_limit = 52 } }
  local by, sid = {}, 0
  for _, s in ipairs(SUITS) do
    for _, r in ipairs(RANKS) do
      sid = sid + 1
      local c = EC.playing(r, s, { sort_id = sid })
      c.cost, c.sell_cost = 1, 1
      by[r .. s] = c
      g.playing_cards[#g.playing_cards + 1] = c
    end
  end
  local hand, used = {}, {}
  for i = 1, #VISIBLE + 1 do
    local key = i == HIDDEN_SLOT and hidden_key or VISIBLE[i < HIDDEN_SLOT and i or i - 1]
    local c = by[key]
    c.area = g.hand
    if i == HIDDEN_SLOT then c.facing = "back" end
    hand[i], used[key] = c, true
  end
  g.hand.cards = hand
  for _, s in ipairs(SUITS) do
    for _, r in ipairs(RANKS) do
      local c = by[r .. s]
      if not used[r .. s] then c.area, c.facing = g.deck, "back"; g.deck.cards[#g.deck.cards + 1] = c end
    end
  end
  g.FUNCS.get_poker_hand_info = HandInfo.engine()
  for _, n in ipairs(HandInfo.HANDLIST) do
    g.GAME.hands[n] = { level = 1, chips = 10, mult = 2, played = 0, played_this_round = 0, visible = true, order = 1 }
  end
  g.GAME.blind = { name = blind.name, chips = 1600, dollars = 5, in_blind = true, boss = true,
    debuff = {}, disabled = false, config = { blind = { key = blind.key } },
    get_type = function() return "Boss" end }
  g.GAME.round_resets.blind_choices.Boss = blind.key
  setup(g)
  H.in_engine_state("SELECTING_HAND")
  require("core.validate").reset_run_state()
  require("facts.fact_hints").reset_pending()
  return g
end

local function emit(hidden_key, blind, setup)
  local g = board(hidden_key, blind, setup)
  local sel, idx = { g.hand.cards[1], g.hand.cards[2], g.hand.cards[3] }, { 1, 2, 3 }
  local verdict = require("facts.boss.legality").play_verdict(sel, idx)
  local ok, ask, _, facts = pcall(require("handlers.hand_handlers").play_review_reason, sel, idx)
  local review = ok and require("context.state_doc").lines(facts, ask) or ("ERR " .. tostring(ask))
  local okp, exec, err = pcall(require("core.dispatcher").preflight, "play_hand", { indices = idx })
  local pf = (not okp) and ("ERR " .. tostring(exec)) or (exec and "ACCEPTED")
    or ("REFUSED: " .. tostring(type(err) == "table" and err.message or err))
  local st, q = H.force_frame("SELECTING_HAND")
  return table.concat({ tostring(verdict), tostring(review), pf, tostring(st), tostring(q) }, "\n=====\n"), verdict
end

local CASES = {
  { label = "Eye after Pair", blind = { key = "bl_eye", name = "The Eye" },
    setup = function(g) g.GAME.blind.hands = { Pair = true, ["Three of a Kind"] = false } end,
    expect = "hides this selection's hand type" },
  { label = "Eye after Three of a Kind", blind = { key = "bl_eye", name = "The Eye" },
    setup = function(g) g.GAME.blind.hands = { Pair = false, ["Three of a Kind"] = true } end,
    expect = "hides this selection's hand type" },
  { label = "Eye before any play", blind = { key = "bl_eye", name = "The Eye" },
    setup = function(g) g.GAME.blind.hands = { Pair = false } end, expect = false },
  { label = "Mouth locked to Pair", blind = { key = "bl_mouth", name = "The Mouth" },
    setup = function(g) g.GAME.blind.only_hand = "Pair" end, expect = "hides this selection's hand type" },
  { label = "Mouth locked to Three of a Kind", blind = { key = "bl_mouth", name = "The Mouth" },
    setup = function(g) g.GAME.blind.only_hand = "Three of a Kind" end, expect = "hides this selection's hand type" },
  { label = "Mouth before any play", blind = { key = "bl_mouth", name = "The Mouth" },
    setup = function(g) g.GAME.blind.only_hand = false end, expect = false },
  { label = "Psychic, three cards", blind = { key = "bl_psychic", name = "The Psychic" },
    setup = function(g) g.GAME.blind.debuff = { h_size_ge = 5 } end, expect = "scores 0" },
}

local pile = {}
for _, s in ipairs(SUITS) do
  for _, r in ipairs(RANKS) do
    local k = r .. s
    local visible = false
    for _, v in ipairs(VISIBLE) do if v == k then visible = true end end
    if not visible then pile[#pile + 1] = k end
  end
end

for _, case in ipairs(CASES) do
  local base, base_verdict = emit(pile[1], case.blind, case.setup)
  local diff
  for i = 2, #pile do
    local text = emit(pile[i], case.blind, case.setup)
    if text ~= base then diff = pile[1] .. " vs " .. pile[i]; break end
  end
  check(case.label .. ": every emitted text is independent of the face-down card", diff == nil, tostring(diff))
  if case.expect then
    check(case.label .. ": the review states the public boss fact",
      type(base_verdict) == "string", tostring(base_verdict))
  else
    check(case.label .. ": no boss verdict when no hand type is blocked yet", base_verdict == nil, tostring(base_verdict))
  end
end

do
  local _, visible = emit("KingClubs", CASES[4].blind, function(g)
    CASES[4].setup(g)
    g.hand.cards[HIDDEN_SLOT].facing = "front"
  end)
  check("a visible selection still names the blocked hand type",
    type(visible) == "string" and visible:find("Three of a Kind", 1, true) ~= nil,
    tostring(visible))
end

done()
