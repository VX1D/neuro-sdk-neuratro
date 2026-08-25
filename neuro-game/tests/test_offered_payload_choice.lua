_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("offered-payload-choice")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Registry = require("core.action_registry")
require("core.actions")

local function offers(text)
  local out = {}
  for name, payload in tostring(text or ""):gmatch("([%w_]+)|(%b{})") do
    if Registry.get(name) then out[#out + 1] = { name = name, payload = payload } end
  end
  return out
end

local function array_fields(name)
  local contract = Registry.get(name)
  local props = (contract and contract.schema and contract.schema.properties) or {}
  local out = {}
  for field, spec in pairs(props) do
    if type(spec) == "table" and spec.type == "array" then out[field] = true end
  end
  return out
end

local function literal_selections(name, payload)
  local bad = {}
  for field in pairs(array_fields(name)) do
    local value = payload:match('"' .. field .. '":(%b[])')
    if value and value:gsub("<[^>]*>", ""):find("%d") then bad[#bad + 1] = field .. ":" .. value end
  end
  return bad
end

local scanned, with_arrays = 0, 0
for _, board in ipairs(LB.BOARDS) do
  LB.load(board.state, board.desc)
  local first = FP.build(board.state)
  local text = (first and ((first.state or "") .. "\n" .. (first.query or ""))) or ""
  for _, offer in ipairs(offers(text)) do
    scanned = scanned + 1
    if next(array_fields(offer.name)) and offer.payload:find("%[") then with_arrays = with_arrays + 1 end
    local bad = literal_selections(offer.name, offer.payload)
    check("" .. board.state .. ": " .. offer.name .. " asks for its selection instead of answering it",
      #bad == 0, table.concat(bad, ", ") .. " in " .. offer.payload)
  end
end

check("the sweep actually found offers to scan", scanned > 20, tostring(scanned))
check("at least one scanned offer carries an array field", with_arrays > 0, tostring(with_arrays))

do
  local REGRESSION = 'use_card|{"area":"consumeables","index":1,"hand_indices":[1]}'
  local hits = offers(REGRESSION)
  check("the regression payload is extracted", #hits == 1, tostring(#hits))
  if hits[1] then
    check("the regression payload is rejected",
      #literal_selections(hits[1].name, hits[1].payload) == 1, hits[1].payload)
  end
  local FIXED = 'use_card|{"area":"consumeables","index":1,"hand_indices":[<pick 1 to 5 different hand positions>]}'
  local ok_hits = offers(FIXED)
  check("the fixed payload is extracted", #ok_hits == 1, tostring(#ok_hits))
  if ok_hits[1] then
    check("the fixed payload passes",
      #literal_selections(ok_hits[1].name, ok_hits[1].payload) == 0, ok_hits[1].payload)
  end
  local BOUND = 'sell_card|{"area":"jokers","index":2}'
  check("a state-fixed scalar may still be bound",
    #literal_selections("sell_card", BOUND:match("%b{}")) == 0, BOUND)
end

done()
