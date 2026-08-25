_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("effect-registry-bijection")
local Vanilla = require("tests.fixtures.vanilla_jokers")
local DynamicJokers = require("facts.dynamic_jokers")
local NE = require("facts.numeric_effects")

local DUMP_DIR = os.getenv("BALATRO_DUMP")
local DUMP = DUMP_DIR and (DUMP_DIR .. "/card.lua") or nil

local lines = {}
if DUMP then
  local f = io.open(DUMP, "r")
  if f then
    for l in f:lines() do lines[#lines + 1] = l end
    f:close()
  end
end
if #lines == 0 then
  require("tests.skip_ledger").bail("effect-registry-bijection", 8, "game dump not found; set BALATRO_DUMP to run")
end
check("the dump's card.lua is readable", #lines > 0, #lines)

local PAY_KEY = { chips = true, mult = true, x_mult = true, h_mult = true, h_chips = true,
  x_chips = true, h_x_mult = true, chip_mod = true, mult_mod = true, Xmult_mod = true, repetitions = true }

local function name_at(i)
  return lines[i]:match("self%.ability%.name%s*==%s*'([^']+)'")
    or lines[i]:match('self%.ability%.name%s*==%s*"([^"]+)"')
end

local current_name
local paying, fn_start, fn_end = {}, nil, nil
for i, l in ipairs(lines) do
  if l:match("^function Card:calculate_joker%(") then fn_start = i end
  if fn_start and i > fn_start and l:match("^function ") then fn_end = i - 1 break end
end
check("Card:calculate_joker was located", fn_start ~= nil, tostring(fn_start))
fn_end = fn_end or #lines

for i = fn_start or 1, fn_end do
  local nm = name_at(i)
  if nm then
    local in_return, pays = false, false
    for j = i + 1, fn_end do
      if name_at(j) then break end
      if lines[j]:find("return%s*{") then in_return = true end
      if in_return then
        for k in lines[j]:gmatch("([%w_]+)%s*=") do if PAY_KEY[k] then pays = true end end
        if lines[j]:find("^%s*}") then in_return = false end
      end
    end
    if pays then
      paying[nm] = paying[nm] or {}
      paying[nm][i] = true
    end
  end
end

local n_paying = 0
for _ in pairs(paying) do n_paying = n_paying + 1 end
check("the dump has paying name branches to reconcile against", n_paying > 40, n_paying)

local name_of, key_of = {}, {}
for _, key in ipairs(Vanilla.keys()) do
  local nm = Vanilla.card(key, 1).ability.name
  name_of[key] = nm
  key_of[nm] = key
end

local unclaimed = {}
for nm in pairs(paying) do
  local key = key_of[nm]
  if not key then
    unclaimed[#unclaimed + 1] = nm .. " (no vanilla key)"
  elseif not (DynamicJokers.ROWS[key] or NE.RETRIGGER[key]) then
    unclaimed[#unclaimed + 1] = nm .. "/" .. key
  end
end
table.sort(unclaimed)
check("every paying name branch in the dump has a registry row",
  #unclaimed == 0, table.concat(unclaimed, ", "))

local ghosts, bad_ref = {}, {}
for key, rows in pairs(DynamicJokers.ROWS) do
  local nm = name_of[key]
  if not nm then
    ghosts[#ghosts + 1] = key .. " (no vanilla center)"
  else
    for _, row in ipairs(rows) do
      if row.generic_ref then
        if paying[nm] then bad_ref[#bad_ref + 1] = key .. " claims generic but has a name branch" end
      elseif not (paying[nm] and paying[nm][row.ref]) then
        bad_ref[#bad_ref + 1] = key .. "@" .. tostring(row.ref)
      end
    end
  end
end
table.sort(ghosts)
table.sort(bad_ref)
check("no registry row names a joker the game does not have", #ghosts == 0, table.concat(ghosts, ", "))
check("every registry ref cites a real paying branch of that joker", #bad_ref == 0, table.concat(bad_ref, ", "))

-- An accumulator's field is not a matter of opinion either: SMODS.scale_card names the exact
-- ref_table/ref_value it writes, so the row that reads the accumulator must read that field. This is
-- what catches a row keyed on Yorick's ability.extra.xmult (the per-tick increment) instead of
-- ability.x_mult (the running total) -- card.lua:3173-3181.
local accumulator_field = {}
do
  local pending
  for i = 1, #lines do
    local nm = name_at(i)
    if nm then current_name = nm end
    local tbl = lines[i]:match("ref_table%s*=%s*self%.ability%.([%w_]+)")
    if tbl then pending = tbl .. "."
    elseif lines[i]:find("ref_table%s*=%s*self%.ability%s*,") then pending = "" end
    local val = lines[i]:match("ref_value%s*=%s*'([%w_]+)'") or lines[i]:match('ref_value%s*=%s*"([%w_]+)"')
    if val and pending and current_name then
      accumulator_field[current_name] = accumulator_field[current_name] or {}
      accumulator_field[current_name][pending .. val] = true
      pending = nil
    end
  end
end

local wrong_field = {}
for key, rows in pairs(DynamicJokers.ROWS) do
  local fields = accumulator_field[name_of[key] or ""]
  if fields then
    local reads_string, matched = false, false
    for _, row in ipairs(rows) do
      if type(row.from) == "string" then
        reads_string = true
        if fields[row.from] then matched = true end
      end
    end
    if reads_string and not matched then
      local want = {}
      for f in pairs(fields) do want[#want + 1] = f end
      table.sort(want)
      wrong_field[#wrong_field + 1] = key .. " reads " .. tostring(rows[1].from)
        .. ", dump scales " .. table.concat(want, "/")
    end
  end
end
table.sort(wrong_field)
check("every accumulator row reads the field SMODS.scale_card actually writes",
  #wrong_field == 0, table.concat(wrong_field, ", "))

local shapeless = {}
local SCOPES = { hand = true, scoring_card = true, held_card = true, other_joker = true }
for key, rows in pairs(DynamicJokers.ROWS) do
  for i, row in ipairs(rows) do
    if not SCOPES[row.scope] then shapeless[#shapeless + 1] = key .. "[" .. i .. "] scope" end
    if not row.per_hand_type and row.from == nil then shapeless[#shapeless + 1] = key .. "[" .. i .. "] from" end
    if not row.kind then shapeless[#shapeless + 1] = key .. "[" .. i .. "] kind" end
    if row.scope ~= "hand" and not (row.match or row.at_most_once) then
      shapeless[#shapeless + 1] = key .. "[" .. i .. "] per-unit row with no match predicate"
    end
  end
end
table.sort(shapeless)
check("every row declares scope, kind and the field it reads", #shapeless == 0, table.concat(shapeless, ", "))

done()
