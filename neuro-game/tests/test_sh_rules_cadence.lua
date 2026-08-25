_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("sh-rules-cadence")
local H = require("tests.helpers")
local Registry = require("facts.hint_registry")
local FactHints = require("facts.fact_hints")
local Actions = require("core.actions")
local FSH = require("force.force_selecting_hand")

local FULL_ONLY = "any hand type counts"
local BOTH_LENGTHS = "no number here does that for you"

local function blind(minimum)
  if not minimum then return nil end
  return { key = "bl_psychic", name = "The Psychic", boss = true, disabled = false,
    debuff = { h_size_ge = minimum }, hands = {}, only_hand = false }
end

local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
local RANKS = { "A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3", "2" }
local next_sort_id = 0

local function make_card(rank, suit)
  next_sort_id = next_sort_id + 1
  return { base = { value = H.VALN[rank] or rank, suit = suit }, sort_id = next_sort_id,
    config = { center = { key = "c_base", set = "Default" } },
    is_suit = function(_, s) return s == suit end }
end

local function redraw(n)
  for _ = 1, n do
    table.remove(G.hand.cards, 1)
    G.hand.cards[#G.hand.cards + 1] =
      make_card(RANKS[(next_sort_id % #RANKS) + 1], SUITS[(next_sort_id % #SUITS) + 1])
  end
end

local function fixture(b)
  local cards = {}
  for i, rank in ipairs({ "A", "K", "Q", "J", "9", "8", "7", "6" }) do
    cards[i] = make_card(rank, SUITS[((i - 1) % 4) + 1])
  end
  return { hand = { cards = cards, config = { highlighted_limit = 5 }, highlighted = {} },
    GAME = { blind = b, hands = {}, probabilities = { normal = 1 }, starting_params = {},
      round = 1, dollars = 4, current_round = { hands_left = 3, discards_left = 2,
        discards_used = 0, most_played_poker_hand = "High Card" } },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = { once_serials = {}, decision_serial = 1, state_enter_serial = 1 },
    jokers = { cards = {} }, consumeables = { cards = {} }, playing_cards = cards,
    deck = { cards = {} }, play = nil }
end

local real_valid = Actions.is_action_valid
Actions.is_action_valid = function(name)
  if name == "play_hand" or name == "discard_hand" then return real_valid(name) end
  return false
end

local function force_parts()
  FactHints.reset_pending()
  local f = assert(FSH.build())
  return (f.query or ""), H.drain_hints()
end

local function force()
  local query, hints = force_parts()
  return query .. hints
end

do
  local core = Registry.lookup("sh_rules_core")
  local brief = Registry.lookup("sh_rules_brief")
  check("the full block is a state claim gated per round",
    core and core.claim == "state" and core.cadence == "round"
      and Registry.channel_of(core) == "query",
    core and (core.claim .. "/" .. core.cadence) or "missing")
  check("the short form is a state claim with no gate at all",
    brief and brief.claim == "state" and brief.cadence == "always"
      and Registry.channel_of(brief) == "query",
    brief and (brief.claim .. "/" .. brief.cadence) or "missing")
end

do
  _G.G = fixture(nil)
  local q_full, hints_full = force_parts()
  local q_brief, hints_brief = force_parts()
  check("the full block leaves on the force query, not the permanent channel",
    q_full:find("Rules: 1)", 1, true) ~= nil
      and hints_full:find("Rules: 1)", 1, true) == nil
      and hints_full:find(FULL_ONLY, 1, true) == nil,
    "hints carried " .. tostring(#hints_full) .. " chars")
  check("C3a and so does the short form",
    q_brief:find("Rules: 1)", 1, true) ~= nil
      and hints_brief:find("Rules: 1)", 1, true) == nil,
    "hints carried " .. tostring(#hints_brief) .. " chars")
end

_G.G = fixture(nil)
local q1 = force()
check("the first force of a round states the rules in full",
  q1:find("Rules: 1)", 1, true) ~= nil and q1:find(FULL_ONLY, 1, true) ~= nil, q1)

local q2 = force()
check("a re-ask in the same round still carries the rules",
  q2:find("Rules: 1)", 1, true) ~= nil, q2)
check("and carries them shortened, not repeated verbatim",
  q2:find(FULL_ONLY, 1, true) == nil and #q2 < #q1, string.format("%d vs %d", #q2, #q1))
check("C6b but never shortened past the disclaimer that the figures are not this hand's value",
  q1:find(BOTH_LENGTHS, 1, true) ~= nil and q2:find(BOTH_LENGTHS, 1, true) ~= nil, q2)

local MUST_KEEP = {
  { "the positions a Ready hand lists", "which positions to send" },
  { "the chips remaining to clear the blind", "what to check before spending a hand" },
  { "a discard toward a one-card-away hand", "when a discard is the better spend" },
  { "fewer hands pays more at cash-out", "what pace costs" },
}
for _, rule in ipairs(MUST_KEEP) do
  check("the short form keeps " .. rule[2], q2:find(rule[1], 1, true) ~= nil, q2)
end
do
  local pos, at = {}, q2:find("Rules: 1)", 1, true)
  pos[1] = at
  for n = 2, 4 do
    at = at and q2:find(n .. ") ", at, true)
    pos[n] = at
  end
  local ascending = pos[1] ~= nil
  for n = 2, 4 do
    if not (pos[n] and pos[n] > pos[n - 1]) then ascending = false end
  end
  check("the short form is numbered like the full block, in one ascending list",
    ascending, string.format("positions: %s", table.concat({ tostring(pos[1]), tostring(pos[2]),
      tostring(pos[3]), tostring(pos[4]) }, ", ")))
end

do
  _G.G = fixture(blind(5))
  local full = force()
  check("the boss floor is stated on the first force",
    full:find("every play must select at least 5 cards", 1, true) ~= nil, full)
  local reask = force()
  check("the boss floor survives verbatim into the short form -- it is legality, not advice",
    reask:find("every play must select at least 5 cards", 1, true) ~= nil
      and reask:find(FULL_ONLY, 1, true) == nil, reask)
  G.GAME.blind = blind(4)
  local changed = force()
  check("a changed floor is reflected immediately, so the short form is rebuilt not replayed",
    changed:find("every play must select at least 4 cards", 1, true) ~= nil
      and changed:find("at least 5 cards", 1, true) == nil, changed)
  G.GAME.current_round.discards_left = 0
  G.GAME.current_round.discards_used = 2
  local dry = force()
  check("a rule that stopped applying leaves the short form with it",
    dry:find("a discard toward", 1, true) == nil, dry)
end

do
  _G.G = fixture(nil)
  force()
  G.NEURO.state_enter_serial = 9
  G.NEURO.decision_serial = 9
  check("re-entering the state inside one round does not re-open the full block",
    force():find(FULL_ONLY, 1, true) == nil)
  local reopened = {}
  for hands = 2, 0, -1 do
    G.GAME.current_round.hands_left = hands
    G.GAME.current_round.discards_left = math.max(0, hands - 1)
    G.GAME.current_round.discards_used = 2 - math.max(0, hands - 1)
    G.NEURO.state_enter_serial = G.NEURO.state_enter_serial + 1
    G.NEURO.decision_serial = G.NEURO.decision_serial + 1
    redraw(5)
    if force():find(FULL_ONLY, 1, true) then
      reopened[#reopened + 1] = "hands_left=" .. hands .. " (hand redrawn)"
    end
  end
  check("C13a nor does spending the round's hands and discards, which is what a round IS",
    #reopened == 0, table.concat(reopened, ", "))

  local hand_only = {}
  for i = 1, 4 do
    redraw(3)
    if force():find(FULL_ONLY, 1, true) then hand_only[#hand_only + 1] = "draw " .. i end
  end
  check("C13b nor does the hand changing under it -- a draw is not a new round",
    #hand_only == 0, table.concat(hand_only, ", "))
  G.GAME.round = 2
  G.GAME.current_round.hands_left = 3
  G.GAME.current_round.discards_left = 2
  G.GAME.current_round.discards_used = 0
  check("the next round states them in full again",
    force():find(FULL_ONLY, 1, true) ~= nil)
  redraw(4)
  check("C14a and only once in it, however the hand moves afterwards",
    force():find(FULL_ONLY, 1, true) == nil)
end

do
  _G.G = fixture(nil)
  G.GAME.round = nil
  check("with no round clock there is no window, so the full block is stated",
    force():find(FULL_ONLY, 1, true) ~= nil)
end

Actions.is_action_valid = real_valid
done()
