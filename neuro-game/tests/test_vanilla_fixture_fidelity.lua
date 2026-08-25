_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("vanilla-fixture-fidelity")
local Vanilla = require("tests.fixtures.vanilla_jokers")

local DUMP_DIR = os.getenv("BALATRO_DUMP")
local DUMP_PATH = DUMP_DIR and (DUMP_DIR .. "/card.lua") or nil

local function read_file(path)
  if not path then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local BODY_ANCHOR = "self.ability = self.ability or {}"

local function extract_risk_zone(source)
  local fn_start = source:find("function Card:set_ability%(")
  if not fn_start then return nil end
  local fn_next = source:find("\nfunction ", fn_start)
  local fn_body = source:sub(fn_start, fn_next or #source)
  local anchor_pos = fn_body:find(BODY_ANCHOR, 1, true)
  if not anchor_pos then return nil end
  return fn_body:sub(anchor_pos)
end

local function scan_assigned_keys(zone)
  local keys = {}
  for key in zone:gmatch("self%.ability%.([%a_][%w_]*)%s*=%s*[^=]") do keys[key] = true end
  for key in zone:gmatch("new_ability%.([%a_][%w_]*)%s*=%s*[^=]") do keys[key] = true end
  return keys
end

local NOT_APPLICABLE_TO_JOKER_CENTERS = { consumeable = true }

_G.G = { GAME = { hands_played = 3 }, NEURO = {} }

local produced_keys = {}
for _, key in ipairs(Vanilla.keys()) do
  local card = Vanilla.card(key, 1)
  for k in pairs(card.ability) do produced_keys[k] = true end
end
check("the fixture built the full 150-joker roster to sample keys from", #Vanilla.keys() == 150, #Vanilla.keys())

local source = read_file(DUMP_PATH)
if not source then
  require("tests.skip_ledger").bail("vanilla-fixture-fidelity", 11, "game dump not found; set BALATRO_DUMP to run")
end
check("the dump's card.lua is readable at " .. tostring(DUMP_PATH), source ~= nil)

if source then
  local zone = extract_risk_zone(source)
  check("Card:set_ability's post-table-literal body was located", zone ~= nil)
  if zone then
    local dump_keys = scan_assigned_keys(zone)
    local missing = {}
    for k in pairs(dump_keys) do
      if not NOT_APPLICABLE_TO_JOKER_CENTERS[k] and not produced_keys[k] then
        missing[#missing + 1] = k
      end
    end
    table.sort(missing)
    check(
      "every ability field the dump initialises past the ported table literal is produced by some vanilla joker fixture",
      #missing == 0, table.concat(missing, ", "))
  end
end

do
  local caino = Vanilla.card("j_caino", 1)
  check("Caino's ability initialises caino_xmult = 1, matching card.lua:443",
    caino.ability.caino_xmult == 1, tostring(caino.ability.caino_xmult))

  local invisible = Vanilla.card("j_invisible", 1)
  check("Invisible Joker's ability initialises invis_rounds = 0, matching card.lua:427",
    invisible.ability.invis_rounds == 0, tostring(invisible.ability.invis_rounds))

  local yorick = Vanilla.card("j_yorick", 1)
  check("Yorick's ability initialises yorick_discards from extra.discards, matching card.lua:446",
    yorick.ability.yorick_discards == yorick.ability.extra.discards, tostring(yorick.ability.yorick_discards))

  local loyalty = Vanilla.card("j_loyalty_card", 1)
  check("Loyalty Card's ability initialises burnt_hand = 0, matching card.lua:449",
    loyalty.ability.burnt_hand == 0, tostring(loyalty.ability.burnt_hand))
  check("Loyalty Card's ability initialises loyalty_remaining from extra.every, matching card.lua:450",
    loyalty.ability.loyalty_remaining == loyalty.ability.extra.every, tostring(loyalty.ability.loyalty_remaining))

  local todo = Vanilla.card("j_todo_list", 1)
  check("To Do List's ability initialises a non-nil to_do_poker_hand, matching card.lua:429-441's shape",
    todo.ability.to_do_poker_hand ~= nil, tostring(todo.ability.to_do_poker_hand))

  local joker = Vanilla.card("j_joker", 1)
  check("every joker's ability initialises hands_played_at_create, matching card.lua:455",
    joker.ability.hands_played_at_create == 3, tostring(joker.ability.hands_played_at_create))
end

do
  local CardSemantics = require("facts.card_semantics")
  _G.G.jokers = { cards = {}, config = { card_limit = 5 } }
  local mismatched = {}
  for _, key in ipairs(Vanilla.played_keys()) do
    local card = Vanilla.card_played(key, 1)
    local projection = CardSemantics.project(card)
    if #projection.effects == 0 then mismatched[#mismatched + 1] = key end
  end
  table.sort(mismatched)
  check("every card_played() accumulator overlay moves its field past project()'s zero/one identity element",
    #mismatched == 0, table.concat(mismatched, ", "))
end

done()
