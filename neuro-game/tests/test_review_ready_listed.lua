require("tests.stubs").setup({ love = "lazy", localize = true })

local check, done = require("tests.helpers").harness("review-ready-listed")
local dump = os.getenv("BALATRO_DUMP")
local Engine = require("tests.engine_scorer")
if not (dump and dump ~= "" and Engine.load(dump)) then
  require("tests.skip_ledger").bail("review-ready-listed", 8, "BALATRO_DUMP unset or game/smods source unreadable")
end
local engine_localize = _G.localize
SMODS.reset_card = SMODS.reset_card or function(card, args)
  local t = args.ref_table or card.ability.extra
  t[args.ref_value] = args.reset_value or 0
end

local V = require("tests.fixtures.vanilla_jokers")
local Helpers = require("tests.helpers")
local FP = require("tests.force_payload")
local TxCache = require("core.bridge").tx

local HAND = { { 13, "Diamonds" }, { 12, "Spades" }, { 11, "Clubs" }, { 6, "Spades" }, { 5, "Clubs" }, { 4, "Spades" },
  { 3, "Hearts" }, { 3, "Clubs" } }
local LEVELS = { ["High Card"] = { 5, 1, 1 }, Pair = { 10, 2, 1 }, ["Two Pair"] = { 80, 5, 4 },
  ["Three of a Kind"] = { 70, 7, 3 }, Straight = { 30, 4, 1 }, Flush = { 35, 4, 1 }, ["Full House"] = { 40, 4, 1 },
  ["Four of a Kind"] = { 60, 7, 1 }, ["Straight Flush"] = { 100, 8, 1 }, ["Five of a Kind"] = { 120, 12, 1 },
  ["Flush House"] = { 140, 14, 1 }, ["Flush Five"] = { 160, 16, 1 } }

local function setup()
  local hands = {}
  for name, v in pairs(LEVELS) do
    hands[name] = { chips = v[1], mult = v[2], level = v[3], visible = true, played = 0, played_this_round = 0 }
  end
  _G.G = _G.G or {}
  G.GAME = {
    current_round = { hands_left = 4, discards_left = 4, discards_used = 0, hands_played = 1 },
    hands = hands, probabilities = { normal = 1 }, dollars = 24, dollar_buffer = 0, round_resets = { ante = 5 },
    hands_played = 20, starting_deck_size = 52, consumeable_usage_total = { tarot = 0 }, blind = {}, modifiers = {},
  }
  local cards = {}
  for i, s in ipairs(HAND) do cards[i] = Engine.card(s[1], s[2]) end
  G.hand = { cards = cards, highlighted = {}, config = { card_limit = 7, highlighted_limit = 5 } }
  for _, c in ipairs(cards) do c.area = G.hand end
  local jokers = {}
  for i, key in ipairs({ "j_smiley", "j_popcorn" }) do
    jokers[i] = Engine.joker(V.card(key, 900 + i))
    jokers[i].facing = "front"
  end
  G.jokers = { cards = jokers, config = { card_limit = 6 } }
  G.deck = { cards = {}, config = { card_limit = 52 } }
  G.playing_cards, G.discard, G.play = {}, { cards = {} }, nil
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  Helpers.in_engine_state("SELECTING_HAND")
  G.NEURO = { once_serials = {}, session_once_serials = {} }
  G.FUNCS.get_poker_hand_info = Engine.get_poker_hand_info
  _G.localize = engine_localize
  require("core.gate").reset()
end

local sends = 0
local function send(name, data)
  sends = sends + 1
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  G.NEURO.send_action_result = function() return true end
  G.NEURO.withdraw_actions = function() return true end
  local id = "ready-listed-" .. sends
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, id, data), G.NEURO)
  pcall(require("core.execute").step, G.TIMERS.REAL)
end

local function ready_line(state) return tostring(state):match("%- Ready to play now: ([^\n]*)") or "" end

local function claims(text)
  local out = {}
  text = tostring(text)
  for name, ix in text:gmatch("Ready ([%a ]-) %(cards ([%d, ]+)%) would score more") do
    out[#out + 1] = name .. " (cards " .. ix .. ")"
  end
  local listed = text:match("Ready hands that would score more were: ([^\n]-)%.%s")
  for item in tostring(listed or ""):gmatch("[^;]+") do
    local name, ix = item:match("^%s*,?%s*([%a ]-) %(cards ([%d, ]+)%)")
    if name then out[#out + 1] = name .. " (cards " .. ix .. ")" end
  end
  return out
end

local function unlisted(frame)
  local line, missing = ready_line(frame.state), {}
  local all = claims(frame.state)
  for _, c in ipairs(claims(frame.query)) do all[#all + 1] = c end
  for _, c in ipairs(all) do
    if not line:find(c, 1, true) then missing[#missing + 1] = c end
  end
  return all, missing
end

setup()
local first = FP.build("SELECTING_HAND") or { state = "", query = "" }
local line = ready_line(first.state)
check("the board: the Pair is Ready", line:find("Pair (cards 7, 8)", 1, true) ~= nil, line)
check("the board: High Card is Ready beside the Pair, naming its card", line:find("High Card (cards 1)", 1, true) ~= nil, line)

send("play_hand", { indices = { 7, 8 } })
local review = FP.next() or { state = "", query = "" }
local said, missing = unlisted(review)
check("the review opens", review.state:find("## Proposed play", 1, true) ~= nil, review.state)
check("the review says a Ready hand scores more than the Pair", #said > 0, review.state .. "\n" .. review.query)
check("every Ready hand the review names is on the same frame's Ready line, same cards",
  #missing == 0, table.concat(missing, " | ") .. "\nReady: " .. ready_line(review.state))
local before = {}
for _, c in ipairs(said) do if not line:find(c, 1, true) then before[#before + 1] = c end end
check("and on the Ready line she saw before proposing", #before == 0, table.concat(before, " | "))

send("resolve_play", { answer = "no" })
local after = FP.next() or { state = "", query = "" }
local echoed, gone = unlisted(after)
check("the decline note repeats which Ready hand scored more", #echoed > 0, after.state .. "\n--\n" .. after.query)
check("every Ready hand the decline note names is on that frame's Ready line, same cards",
  #gone == 0, table.concat(gone, " | ") .. "\nReady: " .. ready_line(after.state))

done()
