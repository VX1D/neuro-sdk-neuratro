_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("force-section-census")
local LB = require("tests.fixtures.live_board")
local FP = require("tests.force_payload")
local Census = require("tests.force_census_rows")

local ROWS, ALL_BOARDS = Census.ROWS, Census.ALL_BOARDS
local norm, has, has_loose, bank_claims =
  Census.norm, Census.has, Census.has_loose, Census.bank_claims

local missing_section, missing_value, wrong_bank, leaked = {}, {}, {}, {}
local exercised, per_row, data_seen = 0, {}, {}

for _, board in ipairs(ALL_BOARDS) do
  LB.load(board.state, board.desc)
  local payload = FP.build(board.state)
  if payload then
    local msg, nmsg = payload.message, norm(payload.message)
    for _, row in ipairs(ROWS) do
      if row.states[board.state] then
        local tag = board.state .. "/" .. row.id
        if row.data() then
          data_seen[row.id] = data_seen[row.id] or {}
          data_seen[row.id][board.state] = true
          exercised = exercised + 1
          per_row[row.id] = (per_row[row.id] or 0) + 1
          if row.header and not has(msg, row.header) then
            missing_section[#missing_section + 1] = tag .. " (no '" .. row.header .. "')"
          end
          if row.bank then
            local claims = bank_claims(msg)
            if #claims == 0 then
              missing_section[#missing_section + 1] = tag .. " (no bank figure at all)"
            else
              local live = "$" .. tostring(G.GAME.dollars)
              for _, v in ipairs(claims) do
                if v ~= live then wrong_bank[#wrong_bank + 1] = tag .. " says " .. v .. ", live " .. live end
              end
            end
          end
          for _, want in ipairs((row.values and row.values()) or {}) do
            if not has_loose(nmsg, want) then
              missing_value[#missing_value + 1] = tag .. " does not state " .. string.format("%q", want)
            end
          end
          for _, banned in ipairs((row.forbidden and row.forbidden()) or {}) do
            if has(msg, banned) then
              leaked[#leaked + 1] = tag .. " states " .. string.format("%q", banned)
            end
          end
        end
      end
    end
  else
    missing_section[#missing_section + 1] = board.state .. "/" .. board.desc .. ": no force at all"
  end
end

check("the census actually ran against a populated board",
  exercised >= 117, "state/row pairs asserted: " .. exercised)
do
  local never = {}
  for _, row in ipairs(ROWS) do
    if (per_row[row.id] or 0) == 0 then never[#never + 1] = row.id end
  end
  check("every row of the census was exercised at least once",
    #never == 0, table.concat(never, "; "))
end
do
  local dark = {}
  for _, row in ipairs(ROWS) do
    for state in pairs(row.states) do
      if not (data_seen[row.id] and data_seen[row.id][state]) then
        dark[#dark + 1] = state .. "/" .. row.id
      end
    end
  end
  check("every state/row pair found live data on at least one board",
    #dark == 0, table.concat(dark, "; "))
end
check("every required section is present in every state that must carry it",
  #missing_section == 0, table.concat(missing_section, " | "))
check("every present section states the live values, not an empty header",
  #missing_value == 0, table.concat(missing_value, " | "))
check("every bank figure the payload states is the live one",
  #wrong_bank == 0, table.concat(wrong_bank, " | "))
check("S6b no payload states an identity a row forbids",
  #leaked == 0, table.concat(leaked, " | "))
check("every section was looked for in a payload production actually sent",
  FP.captures() >= #ALL_BOARDS, "payloads captured: " .. FP.captures()
    .. ", boards: " .. #ALL_BOARDS)

done()
