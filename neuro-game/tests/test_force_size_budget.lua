_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("force-size-budget")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local SIZE = require("tests.force_size_baseline").PAYLOAD
local SLACK_CAP = 150
local function band(size)
  local slack = math.min(math.ceil(size * 0.06), SLACK_CAP)
  return size - slack, size + slack
end

local function breakdown(state_name, payload)
  local rows = {}
  local ok, sections = pcall(require("context.context_compact").build, state_name, payload.actions,
    { split = "state", no_cache = true, return_list = true })
  if ok and type(sections) == "table" then
    for _, section in ipairs(sections) do
      local text = tostring(section)
      rows[#rows + 1] = { n = #text, where = "state", label = (text:match("^[^\n]*") or ""):sub(1, 52) }
    end
  end
  for line in ((payload.query or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      rows[#rows + 1] = { n = #line, where = "query", label = line:sub(1, 52) }
    end
  end
  table.sort(rows, function(a, b) return a.n > b.n end)
  local out = {}
  for i = 1, math.min(#rows, 12) do
    out[#out + 1] = string.format("      %5d  %-5s  %s", rows[i].n, rows[i].where, rows[i].label)
  end
  return table.concat(out, "\n")
end

local function plan_rows(text)
  local bytes, tags, notes, credits = 0, 0, 0, 0
  for clause in text:gmatch("%-%- your plan: %u+") do bytes = bytes + #clause; tags = tags + 1 end
  for clause in text:gmatch('%-%- your note: "[^"]*"') do bytes = bytes + #clause; notes = notes + 1 end
  for clause in text:gmatch("All plan tags above written by you, Ante %d+, decision %d+%.") do
    bytes = bytes + #clause
    credits = credits + 1
  end
  return { bytes = bytes, tags = tags, notes = notes, credits = credits }
end
local PLAN_ROWS = {
  ["SHOP/Marked roster: a debuffed joker, an eternal joker, and the model's own plan on every row"] =
    { bytes = 473, tags = 5, notes = 4, credits = 1 },
}
local NO_PLAN = { bytes = 0, tags = 0, notes = 0, credits = 0 }
local plan_wrong = {}

local ALL_BOARDS = {}
for _, list in ipairs({ LB.BOARDS, LB.BLOCKED, LB.OUT_OF_RUN }) do
  for _, b in ipairs(list) do ALL_BOARDS[#ALL_BOARDS + 1] = b end
end

local over, under, grew, unbudgeted = {}, {}, {}, {}
local measured, seen = 0, {}

for _, board in ipairs(ALL_BOARDS) do
  local key = board.state .. "/" .. board.desc
  LB.load(board.state, board.desc)
  local first = FP.build(board.state)
  local size = SIZE[key]
  if not first then
    unbudgeted[#unbudgeted + 1] = key .. ": no force at all"
  elseif not size then
    unbudgeted[#unbudgeted + 1] = key .. ": board has no recorded size"
  else
    measured = measured + 1
    seen[key] = true
    local total = #first.state + #first.query
    local floor, ceiling = band(size)
    print(string.format("   [size] %-20s state=%5d query=%5d sum=%5d  (%d..%d)  %s",
      board.state, #first.state, #first.query, total, floor, ceiling, board.desc:sub(1, 34)))
    if total > ceiling then
      over[#over + 1] = string.format("%s sum=%d > %d\n%s", key, total, ceiling,
        breakdown(board.state, first))
    end
    if total < floor then
      under[#under + 1] = string.format("%s sum=%d < %d", key, total, floor)
    end
    do
      local want = PLAN_ROWS[key] or NO_PLAN
      local got = plan_rows(first.message)
      print(string.format("   [plan] %-20s bytes=%4d tags=%d notes=%d credits=%d",
        board.state, got.bytes, got.tags, got.notes, got.credits))
      for _, field in ipairs({ "bytes", "tags", "notes", "credits" }) do
        if got[field] ~= want[field] then
          plan_wrong[#plan_wrong + 1] = string.format("%s plan %s=%d, recorded %d",
            key, field, got[field], want[field])
        end
      end
    end

    local second = FP.build(board.state)
    if second and (#second.state + #second.query) > total then
      grew[#grew + 1] = string.format("%s re-ask %d > first force %d",
        key, #second.state + #second.query, total)
    end
  end
end

do
  local missing = {}
  for key in pairs(SIZE) do
    if not seen[key] then missing[#missing + 1] = key .. ": recorded but never measured" end
  end
  check("every board the fixture produces has a recorded size, and every recorded size a board",
    #unbudgeted == 0 and #missing == 0 and measured == 19,
    table.concat(unbudgeted, " | ") .. " " .. table.concat(missing, " | ")
      .. " (measured " .. measured .. "/19)")
end
check("no board exceeds its own ceiling", #over == 0, "\n" .. table.concat(over, "\n"))
check("no board fell through its own floor -- the budget may not be met by deleting content",
  #under == 0, table.concat(under, " | "))
check("the roster's plan rows cost exactly what is recorded, measured on their own bytes",
  #plan_wrong == 0, table.concat(plan_wrong, " | "))
check("a re-ask never costs more than the force it repeats",
  #grew == 0, table.concat(grew, " | "))
do
  local widest = 0
  for _, size in pairs(SIZE) do
    local floor, ceiling = band(size)
    if (ceiling - size) > widest then widest = ceiling - size end
  end
  check("no board's slack is wide enough to hide a paragraph (widest " .. widest .. ")",
    widest <= SLACK_CAP and SLACK_CAP <= 150, "widest slack " .. widest)
end
check("every byte counted here was taken off G.NEURO.force_actions",
  FP.captures() >= measured * 2, "payloads captured: " .. FP.captures() .. ", boards: " .. measured)

done()
