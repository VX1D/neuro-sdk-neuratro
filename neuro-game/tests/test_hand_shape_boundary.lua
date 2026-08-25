_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.G = { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {} }

local H = require("tests.helpers")
local check, done = H.harness("hand-shape boundary")
local HF = require("facts.hand_facts")
local CardUtil = require("facts.card_util")
local Limits = require("core.plan_limits")

local function card(v, suit)
  local id = H.RID[v]
  return {
    base = { value = H.VALN[v] or v, suit = suit, id = id },
    ability = { set = "Default", name = "Base", effect = "" },
    config = { center = { key = "c_base", set = "Default" } },
    facing = "front",
    get_id = function() return id end,
    is_suit = function(_, s) return s == suit end,
  }
end

local function setup(cards, opts)
  opts = opts or {}
  G.hand = { cards = cards, highlighted = {},
    config = { highlighted_limit = opts.highlight or 5, card_limit = 8 } }
  G.deck = { cards = opts.deck or {} }
  G.jokers = nil
  G.GAME = {
    current_round = { discards_left = 3, hands_left = 4 },
    hands = {}, blind = {}, starting_params = opts.starting_params or {},
  }
  G.FUNCS = {}
end

local function hand_of(spec)
  local out = {}
  for _, s in ipairs(spec) do out[#out + 1] = card(s[1], s[2]) end
  return out
end

local FILLER = { { "2", "Clubs" }, { "4", "Spades" }, { "7", "Diamonds" }, { "9", "Clubs" } }
local function with_filler(spec, n)
  local out = {}
  for _, s in ipairs(spec) do out[#out + 1] = s end
  for i = 1, (n or 2) do out[#out + 1] = FILLER[i] end
  return hand_of(out)
end

local function types_of(cards)
  setup(cards)
  return HF.contained_types(cards)
end

do
  local four = with_filler({ { "9", "Hearts" }, { "10", "Spades" }, { "J", "Clubs" }, { "Q", "Diamonds" } })
  local t4 = types_of(four)
  check("4 cards in sequence is NOT a Straight at threshold 5",
    t4["Straight"] ~= true and t4["Straight Flush"] ~= true, "reported a made Straight")
  local s4 = HF.summary()
  check("4 in sequence is reported as Close, not Ready",
    s4:find("near Straight", 1, true) ~= nil and s4:find("Ready:", 1, true) == nil, s4)

  local five = with_filler({ { "9", "Hearts" }, { "10", "Spades" }, { "J", "Clubs" },
                             { "Q", "Diamonds" }, { "K", "Hearts" } })
  local t5 = types_of(five)
  check("5 cards in sequence IS a Straight at threshold 5", t5["Straight"] == true, "no Straight")
end

do
  local four = with_filler({ { "2", "Hearts" }, { "5", "Hearts" }, { "8", "Hearts" }, { "K", "Hearts" } })
  local t4 = types_of(four)
  check("4 cards of a suit is NOT a Flush at threshold 5", t4["Flush"] ~= true, "reported a made Flush")
  local s4 = HF.summary()
  check("4 of a suit is reported as Close, not Ready",
    s4:find("near Flush", 1, true) ~= nil and s4:find("Ready:", 1, true) == nil, s4)

  local five = with_filler({ { "2", "Hearts" }, { "5", "Hearts" }, { "8", "Hearts" },
                             { "K", "Hearts" }, { "J", "Hearts" } })
  local t5 = types_of(five)
  check("5 cards of a suit IS a Flush at threshold 5", t5["Flush"] == true, "no Flush")
end

do
  _G.SMODS = { four_fingers = function() return 4 end }

  local three_run = with_filler({ { "9", "Hearts" }, { "10", "Spades" }, { "J", "Clubs" } }, 3)
  check("Four Fingers: 3 in sequence is still not a Straight",
    types_of(three_run)["Straight"] ~= true, "reported a made Straight")
  local four_run = with_filler({ { "9", "Hearts" }, { "10", "Spades" }, { "J", "Clubs" },
                                 { "Q", "Diamonds" } })
  check("Four Fingers: 4 in sequence IS a Straight",
    types_of(four_run)["Straight"] == true, "no Straight")

  local three_suit = with_filler({ { "2", "Hearts" }, { "5", "Hearts" }, { "8", "Hearts" } }, 3)
  check("Four Fingers: 3 of a suit is still not a Flush",
    types_of(three_suit)["Flush"] ~= true, "reported a made Flush")
  local four_suit = with_filler({ { "2", "Hearts" }, { "5", "Hearts" }, { "8", "Hearts" },
                                  { "K", "Hearts" } })
  check("Four Fingers: 4 of a suit IS a Flush",
    types_of(four_suit)["Flush"] == true, "no Flush")

  _G.SMODS = nil
end

do
  _G.SMODS = { shortcut = function() return true end }
  local four_gapped = hand_of({ { "2", "Hearts" }, { "4", "Spades" }, { "6", "Clubs" },
                                { "8", "Diamonds" }, { "K", "Hearts" }, { "Q", "Clubs" } })
  check("Shortcut: 4 gapped ranks is not a Straight",
    types_of(four_gapped)["Straight"] ~= true, "reported a made Straight")
  local five_gapped = hand_of({ { "2", "Hearts" }, { "4", "Spades" }, { "6", "Clubs" },
                                { "8", "Diamonds" }, { "10", "Hearts" }, { "K", "Clubs" } })
  check("Shortcut: 5 gapped ranks IS a Straight",
    types_of(five_gapped)["Straight"] == true, "no Straight")
  _G.SMODS = nil
end

local function cap_note(s)
  local list, n = s:match("/other%[([%d,]+)%]%(discard at most (%d+)%)")
  if not list then return nil end
  local count = 0
  for _ in list:gmatch("%d+") do count = count + 1 end
  return tonumber(n), count
end

do
  local six_spare = hand_of({ { "K", "Hearts" }, { "K", "Spades" }, { "2", "Clubs" },
                              { "4", "Diamonds" }, { "6", "Hearts" }, { "9", "Spades" },
                              { "J", "Clubs" }, { "3", "Diamonds" } })
  setup(six_spare, { deck = { card("K", "Clubs"), card("8", "Hearts") } })
  local n, listed = cap_note(HF.summary())
  local authority = math.max(1, Limits.discard_select_max())
  check("an over-long other-list advertises a cap at all", n ~= nil, HF.summary())
  check("the advertised cap is the schema's own (core/plan_limits.lua), not a literal",
    n == authority, tostring(n) .. " vs " .. tostring(authority))
  check("and the list it offers is exactly that many cards",
    listed == authority, tostring(listed) .. " vs " .. tostring(authority))

  setup(six_spare, { deck = { card("K", "Clubs"), card("8", "Hearts") },
    starting_params = { discard_limit = 3 } })
  local n2, listed2 = cap_note(HF.summary())
  local authority2 = math.max(1, Limits.discard_select_max())
  check("a discard_limit below the selection cap really does move the schema",
    authority2 == 3 and CardUtil.highlight_limit() == 5,
    tostring(authority2) .. " / " .. tostring(CardUtil.highlight_limit()))
  check("the advertised cap follows the discard limit, not the selection limit",
    n2 == authority2, tostring(n2) .. " vs " .. tostring(authority2))
  check("and the offered list shrinks with it",
    listed2 == authority2, tostring(listed2) .. " vs " .. tostring(authority2))
end

done()
