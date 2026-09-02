_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("play-size-contract")

local Legality = require("facts.boss.legality")
local Actions = require("core.actions")
local ActionResult = require("core.action_result")
local HandHandlers = require("handlers.hand_handlers")

local VALN = require("tests.helpers").VALN
local RANKS = { "A", "K", "Q", "J", "9", "8", "7", "6" }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }

local _sort_id = 0
local function card(v, suit)
  _sort_id = _sort_id + 1
  return {
    base = { value = VALN[v] or v, suit = suit },
    sort_id = _sort_id,
    config = { center = { key = "c_base", set = "Default" } },
    is_suit = function(_, s) return s == suit end,
  }
end

local function setup(opts)
  _sort_id = 0
  local cards = {}
  for i = 1, opts.hand do cards[i] = card(RANKS[i], SUITS[((i - 1) % 4) + 1]) end
  local blind = { key = opts.boss, name = opts.boss and "The Psychic" or "Small Blind",
    debuff = opts.debuff or {}, hands = {}, only_hand = false }
  _G.G = {
    hand = { cards = cards, config = { highlighted_limit = opts.highlighted_limit or 5 }, highlighted = {} },
    GAME = {
      blind = blind,
      round = 1,
      hands = {},
      probabilities = { normal = 1 },
      starting_params = opts.starting_params or {},
      current_round = {
        hands_left = opts.hands_left or 3,
        discards_left = opts.discards_left or 2,
        most_played_poker_hand = "High Card",
      },
    },
    FUNCS = { get_poker_hand_info = function(cs) return "High Card", {}, {}, { cs[1] } end },
    NEURO = {},
    jokers = { cards = {} },
    consumeables = { cards = {} },
    playing_cards = cards,
    deck = { cards = {} },
    play = nil,
  }
  return cards
end

local function schema_bounds()
  local ix = require("core.action_registry").get("play_hand").schema.properties.indices
  return ix.minItems, ix.maxItems
end

local function handler_accepts(n)
  local indices = {}
  for i = 1, n do indices[i] = i end
  G.NEURO = {}
  local res, err = HandHandlers.handle_play_hand({ indices = indices })
  local accepted = res ~= nil or ActionResult.normalize(err).reason_code ~= "INVALID_SELECTION"
  require("core.hand_transaction").reset()
  return accepted
end

local function agreement_report(label)
  local offered = Actions.is_action_valid("play_hand") == true
  local accepted = {}
  for n = 1, #G.hand.cards do
    if handler_accepts(n) then accepted[#accepted + 1] = tostring(n) end
  end
  if not offered then
    check(label .. ": play_hand is only withdrawn when the handler accepts no selection size",
      #accepted == 0, "handler still accepts: " .. table.concat(accepted, ","))
    return nil
  end
  local lo, hi = schema_bounds()
  local advertised = {}
  for n = lo, hi do advertised[#advertised + 1] = tostring(n) end
  check(label .. ": the schema advertises exactly the selection sizes the handler accepts",
    table.concat(advertised, ",") == table.concat(accepted, ","),
    "schema " .. table.concat(advertised, ",") .. " vs handler " .. table.concat(accepted, ","))
  return lo, hi
end

local PSYCHIC = { h_size_ge = 5 }

do
  setup({ hand = 8, boss = "bl_psychic", debuff = PSYCHIC })
  local lo, hi = agreement_report("psychic, full hand")
  check("psychic with 8 cards advertises exactly 5", lo == 5 and hi == 5, lo .. "-" .. hi)
  check("psychic with 8 cards keeps play_hand available",
    Legality.play_has_legal_size() and Actions.is_action_valid("play_hand") == true)
end

do
  setup({ hand = 4, boss = "bl_psychic", debuff = PSYCHIC })
  agreement_report("psychic, hand smaller than the boss minimum")
  check("a 4-card hand under an h_size_ge=5 boss has no legal play size",
    Legality.play_has_legal_size() == false)
  check("play_hand is withdrawn when no selection size is both schema-legal and executable",
    Actions.is_action_valid("play_hand") == false)
  local valid = Actions.get_valid_actions_for_state("SELECTING_HAND")
  local set = {}
  for _, name in ipairs(valid) do set[name] = true end
  check("play_hand leaves the SELECTING_HAND offer", set["play_hand"] ~= true)
  check("discard_hand stays offered, so the round still has a way forward",
    set["discard_hand"] == true)

  local force = require("force.force_selecting_hand").build()
  local offered = {}
  for _, name in ipairs(force and force.actions or {}) do offered[name] = true end
  check("the force drops play_hand with the registry", offered["play_hand"] ~= true)
  check("the force still leads with discard_hand", offered["discard_hand"] == true)
end

do
  setup({ hand = 8, boss = "bl_psychic", debuff = PSYCHIC, highlighted_limit = 3 })
  agreement_report("psychic, selection cap below the boss minimum")
  check("a selection cap of 3 under an h_size_ge=5 boss has no legal play size",
    Legality.play_has_legal_size() == false)
  check("the schema never lowers a boss minimum to fit a smaller cap",
    Actions.is_action_valid("play_hand") == false)
end

do
  setup({ hand = 8, starting_params = { play_limit = 3, discard_limit = 5 } })
  local lo, hi = agreement_report("play_limit below the selection cap")
  check("play_limit narrows the advertised maximum", lo == 1 and hi == 3, lo .. "-" .. hi)
  local force = require("force.force_selecting_hand").build()
  local query = force and force.query or ""
  check("the force quotes the play range play_limit actually allows",
    query:find('play_hand|{"indices":[<pick 1 to 3 different hand positions>]', 1, true) ~= nil, query)
  check("play_limit does not leak into the discard range",
    query:find('discard_hand|{"indices":[<pick 1 to 5 different hand positions>]', 1, true) ~= nil, query)
end

do
  setup({ hand = 8, boss = "bl_psychic", debuff = PSYCHIC, starting_params = { play_limit = 3 } })
  agreement_report("play_limit below the boss minimum")
  check("a play_limit of 3 under an h_size_ge=5 boss has no legal play size",
    Legality.play_has_legal_size() == false)
end

do
  setup({ hand = 3 })
  local lo, hi = agreement_report("short hand, no boss rule")
  check("the advertised maximum never exceeds the cards on hand", lo == 1 and hi == 3, lo .. "-" .. hi)
  check("a short hand alone still allows a play", Legality.play_has_legal_size())
end

do
  setup({ hand = 8, boss = "bl_psychic", debuff = { h_size_le = 3 } })
  local lo, hi = agreement_report("h_size_le boss")
  check("an h_size_le boss narrows the advertised maximum", lo == 1 and hi == 3, lo .. "-" .. hi)
end

local MIN_PROSE = "every play must select at least"
local Helpers = require("tests.helpers")
local Staging = require("core.staging")
local JSON = require("util.neuro_json")

local function stages_confirmed_play(indices)
  local payload = JSON.encode({ indices = indices })
  return Staging.should_stage({ command = "action",
    data = { name = "play_hand", id = "p", data = payload } })
end
local _entry_serial = 0

local function force_and_hints()
  _entry_serial = _entry_serial + 1
  G.NEURO.state_enter_serial = _entry_serial
  require("facts.fact_hints").reset_pending()
  local force = require("force.force_selecting_hand").build()
  return force, ((force and force.query) or "") .. Helpers.drain_hints()
end

do
  setup({ hand = 3, boss = "bl_psychic", debuff = PSYCHIC, hands_left = 1, discards_left = 0 })
  local lo, hi = agreement_report("psychic dead end: hand below the minimum, no discard left")
  check("the dead end lowers the boss floor to the cards actually in hand",
    lo == 1 and hi == 3, tostring(lo) .. "-" .. tostring(hi))
  check("play_hand returns to the offer", Actions.is_action_valid("play_hand") == true)
  check("the relaxation is reported as such", Legality.play_floor_relaxed() == true)
  local force, hints = force_and_hints()
  check("the force is built instead of going silent", type(force) == "table", type(force))
  local offered = {}
  for _, name in ipairs(force and force.actions or {}) do offered[name] = true end
  check("the rebuilt force leads with play_hand", offered["play_hand"] == true)
  check("the relaxed force stops claiming a minimum it no longer enforces",
    hints:find(MIN_PROSE, 1, true) == nil, hints)
  check("the hover preflight reads the same relaxed floor and confirmation guard as the handler",
    stages_confirmed_play({ 1, 2, 3 }) == true)
end

do
  setup({ hand = 3, boss = "bl_psychic", debuff = PSYCHIC, hands_left = 1, discards_left = 1 })
  agreement_report("psychic, hand below the minimum with a discard still in hand")
  check("one discard left keeps the boss floor", Legality.play_has_legal_size() == false)
  check("nothing is relaxed while another move exists", Legality.play_floor_relaxed() == false)
  local _, hints = force_and_hints()
  check("the unrelaxed force still states the boss minimum",
    hints:find(MIN_PROSE, 1, true) ~= nil, hints)
  check("the hover preflight keeps refusing a play under the boss minimum",
    stages_confirmed_play({ 1, 2, 3 }) == false)
end

do
  setup({ hand = 3, boss = "bl_psychic", debuff = PSYCHIC, hands_left = 0, discards_left = 0 })
  check("a round with no hand left is not a play the floor can rescue",
    Legality.play_floor_relaxed() == false and Actions.is_action_valid("play_hand") == false)
end

do
  setup({ hand = 0, boss = "bl_psychic", debuff = PSYCHIC, hands_left = 1, discards_left = 0 })
  agreement_report("psychic dead end with an empty hand")
  check("an empty hand is never relaxed into a playable range",
    Legality.play_floor_relaxed() == false and Actions.is_action_valid("play_hand") == false)
end

do
  setup({ hand = 8, boss = "bl_psychic", debuff = PSYCHIC, highlighted_limit = 3,
    hands_left = 1, discards_left = 0 })
  local lo, hi = agreement_report("selection cap below the boss minimum, no discard left")
  check("a cap that can never reach the floor is the same dead end",
    lo == 1 and hi == 3, tostring(lo) .. "-" .. tostring(hi))
end

do
  setup({ hand = 8, boss = "bl_psychic", debuff = { h_size_ge = 5, h_size_le = 3 },
    hands_left = 1, discards_left = 0 })
  local lo, hi = agreement_report("contradictory size rule, no discard left")
  check("relaxing the floor never lifts the ceiling", lo == 1 and hi == 3, tostring(lo) .. "-" .. tostring(hi))
end

done()
