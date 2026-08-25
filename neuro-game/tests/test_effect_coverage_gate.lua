_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { STATE = 5, STATES = { SHOP = 5 },
  GAME = { round = 1, dollars = 8, round_resets = { ante = 2 }, probabilities = { normal = 1 },
           hands = { ["High Card"] = { played = 2, visible = true }, ["Pair"] = { played = 1, visible = true } },
           starting_deck_size = 53, current_round = { discards_left = 3, hands_left = 3 },
           consumeable_usage_total = { tarot = 3 } },
  NEURO = { once_serials = {}, jokers_sold_run = 0 },
  deck = { cards = {} }, playing_cards = {}, jokers = { cards = {}, config = { card_limit = 5 } } }
for i = 1, 52 do G.deck.cards[i] = { sort_id = 500 + i }; G.playing_cards[i] = G.deck.cards[i] end
G.jokers.cards[1] = { ability = { set = "Joker" }, sell_cost = 5, area = G.jokers }
G.jokers.cards[2] = { ability = { set = "Joker" }, sell_cost = 4, area = G.jokers }

local check, done = require("tests.helpers").harness("effect-coverage-gate")
local Vanilla = require("tests.fixtures.vanilla_jokers")
local Truth = require("tests.fixtures.vanilla_joker_truth")
local NE = require("facts.numeric_effects")
local CardSemantics = require("facts.card_semantics")

check("the fixture built the full 150-joker roster", #Vanilla.keys() == 150, #Vanilla.keys())

local DUMP_DIR = os.getenv("BALATRO_DUMP")
local DUMP_PATH = DUMP_DIR and (DUMP_DIR .. "/card.lua") or nil

local function read_lines(path)
  if not path then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  return lines
end

local function scan_name_branch_lines(lines)
  local fn_start, fn_end
  for i, l in ipairs(lines) do
    if l:match("^function Card:calculate_joker%(") then fn_start = i end
    if fn_start and i > fn_start and l:match("^function ") then fn_end = i - 1; break end
  end
  fn_end = fn_end or #lines
  local by_name = {}
  for i = fn_start, fn_end do
    local nm = lines[i]:match("self%.ability%.name%s*==%s*'([^']+)'")
      or lines[i]:match('self%.ability%.name%s*==%s*"([^"]+)"')
    if nm then
      by_name[nm] = by_name[nm] or {}
      by_name[nm][#by_name[nm] + 1] = i
    end
  end
  return by_name, fn_start, fn_end
end

local GENERIC_REF = { [4027] = true, [3596] = true, [4322] = true }

local lines = read_lines(DUMP_PATH)
if not lines then
  require("tests.skip_ledger").bail("effect-coverage-gate", 13, "game dump not found; set BALATRO_DUMP to run")
end
check("the dump's card.lua is readable at " .. tostring(DUMP_PATH), lines ~= nil)

local NAME_BRANCH_LINES = {}
if lines then
  local fn_start, fn_end
  NAME_BRANCH_LINES, fn_start, fn_end = scan_name_branch_lines(lines)
  check("Card:calculate_joker was located in the dump", fn_start ~= nil and fn_end ~= nil,
    tostring(fn_start) .. ".." .. tostring(fn_end))

  local checked, mismatched = 0, {}
  for key, entries in pairs(Truth) do
    local name = Vanilla.card(key, 1).ability.name
    for _, t in ipairs(entries) do
      if t.ref and not GENERIC_REF[t.ref] then
        checked = checked + 1
        local branch_lines = NAME_BRANCH_LINES[name]
        local found = false
        if branch_lines then
          for _, bl in ipairs(branch_lines) do if bl == t.ref then found = true end end
        end
        if not found then mismatched[#mismatched + 1] = key .. "@" .. t.ref end
      end
    end
  end
  table.sort(mismatched)
  check("every non-generic truth-table ref cites a real self.ability.name branch in the dump (" .. checked .. " checked)",
    #mismatched == 0, table.concat(mismatched, ", "))
end

local TRUTH_SCOPE = { hand = "hand", scoring_card = "card", held_card = "held", other_joker = "joker" }
local function model_scope(effects)
  local scope
  for _, e in ipairs(effects) do
    if e.at_most_once then return "hand" end
    local s = TRUTH_SCOPE[e.scope]
    if s and s ~= "hand" then scope = s end
  end
  return scope or "hand"
end

local function set_of(list)
  local s = {}
  for _, k in ipairs(list) do s[k] = true end
  return s
end

local EXPECTED_LOST = set_of{ "j_raised_fist" }
local EXPECTED_UNDERSTATED = set_of{}

local counts = { correct = 0, understated = 0, lost = 0 }
local actual = { correct = {}, understated = {}, lost = {} }
local none_count, retrigger_keys = 0, {}
local payer_count = 0

for _, key in ipairs(Vanilla.keys()) do
  local truth = Truth[key] or {}
  if #truth == 0 then
    none_count = none_count + 1
  elseif truth[1].scope == "retrigger" then
    retrigger_keys[#retrigger_keys + 1] = key
  else
    payer_count = payer_count + 1
    local card = Vanilla.card_played(key, 1)
    local projection = CardSemantics.project(card)
    local verdict
    if #projection.effects == 0 then
      verdict = "lost"
    else
      local truescope = truth[1].at_most_once and "hand" or truth[1].scope
      verdict = (model_scope(projection.effects) == truescope) and "correct" or "understated"
    end
    counts[verdict] = counts[verdict] + 1
    actual[verdict][#actual[verdict] + 1] = key
  end
end

check("population: 150 vanilla jokers split 56 pay-nothing / 6 retrigger / 88 payers (plan-effect-model.md section 1)",
  none_count == 56 and #retrigger_keys == 6 and payer_count == 88,
  string.format("none=%d retrigger=%d payer=%d", none_count, #retrigger_keys, payer_count))

local retrigger_covered = 0
for _, key in ipairs(retrigger_keys) do if NE.RETRIGGER[key] then retrigger_covered = retrigger_covered + 1 end end
check("6/6 retrigger jokers are covered by NumericEffects.RETRIGGER",
  retrigger_covered == #retrigger_keys, retrigger_covered .. "/" .. #retrigger_keys)

print(string.format("EFFECT COVERAGE GATE -- correct: %d, understated: %d, lost: %d (of %d payers)",
  counts.correct, counts.understated, counts.lost, payer_count))

check("correct count pinned at 87", counts.correct == 87, counts.correct)
check("understated count pinned at 0", counts.understated == 0, counts.understated)
check("lost count pinned at 1", counts.lost == 1, counts.lost)

local function sorted_keys_of(set)
  local out = {}
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function list_eq(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

table.sort(actual.lost)
table.sort(actual.understated)
local expected_lost_sorted = sorted_keys_of(EXPECTED_LOST)
local expected_understated_sorted = sorted_keys_of(EXPECTED_UNDERSTATED)

check("the lost joker roster matches the pinned set (drift in either direction fails this)",
  list_eq(actual.lost, expected_lost_sorted), table.concat(actual.lost, ","))
check("the understated joker roster matches the pinned set (drift in either direction fails this)",
  list_eq(actual.understated, expected_understated_sorted), table.concat(actual.understated, ","))

local RATE_KIND = { mult = true, chips = true, xmult = true }

local function projected_rate(card, kind)
  for _, e in ipairs(CardSemantics.project(card).effects) do
    if e.kind == kind and e.source ~= "edition" then return tonumber(e.rate or e.value) end
  end
  return nil
end

local function moved_live_value(key)
  local base, played = Vanilla.card(key, 1).ability, Vanilla.card_played(key, 1).ability
  local moved, count = nil, 0
  for f, v in pairs(played) do
    if type(v) == "number" and tonumber(base[f]) ~= v then moved = v; count = count + 1
    elseif type(v) == "table" then
      for g, w in pairs(v) do
        if type(w) == "number" and tonumber((base[f] or {})[g]) ~= w then moved = w; count = count + 1 end
      end
    end
  end
  if count == 1 then return moved end
  return nil
end

local literal_checked, acc_checked, formula_skipped, wrong_rate = 0, 0, 0, {}

for _, key in ipairs(Vanilla.keys()) do
  for _, t in ipairs(Truth[key] or {}) do
    if RATE_KIND[t.kind] then
      local want, bucket
      if type(t.val) == "number" then
        want, bucket = t.val, "literal"
      elseif t.val == "acc" then
        want = moved_live_value(key)
        bucket = want and "acc" or nil
      end
      if want then
        if bucket == "literal" then literal_checked = literal_checked + 1
        else acc_checked = acc_checked + 1 end
        local got = projected_rate(Vanilla.card_played(key, 1), t.kind)
        if not got or math.abs(got - want) > 1e-6 then
          wrong_rate[#wrong_rate + 1] = string.format("%s.%s mod=%s dump=%s",
            key, t.kind, tostring(got), tostring(want))
        end
      else
        formula_skipped = formula_skipped + 1
      end
    end
  end
end

table.sort(wrong_rate)
print(string.format("EFFECT VALUE GATE -- rates compared: %d literal + %d accumulator, %d formula rows not comparable",
  literal_checked, acc_checked, formula_skipped))

check("the value gate actually compared a population, not an empty one",
  literal_checked >= 51 and acc_checked >= 19,
  literal_checked .. " literal / " .. acc_checked .. " accumulator")
check("every compared rate equals the dump's (" .. (literal_checked + acc_checked) .. " rows)",
  #wrong_rate == 0, table.concat(wrong_rate, ", "))
check("the rows the value gate cannot compare are a known, bounded remainder",
  formula_skipped <= 24, tostring(formula_skipped))

done()
