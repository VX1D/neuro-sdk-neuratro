require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("force-wire-frame")
local FW = require("tests.force_wire")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local SectionRows = require("tests.force_section_rows")
local WIRE_SIZE = require("tests.force_size_baseline").WIRE
local function ceiling_of(size)
  return size + math.min(math.ceil(size * 0.06), 150)
end

FW.attach()

local ROWS = SectionRows.ROWS
local norm, has, has_loose, bank_claims =
  SectionRows.norm, SectionRows.has, SectionRows.has_loose, SectionRows.bank_claims

local no_frame, mismatched, over, unbudgeted = {}, {}, {}, {}, {}
local missing_section, missing_value, wrong_bank, offers, leaked = {}, {}, {}, {}, {}
local in_query = {}
local boards, exercised = 0, 0
local per_row, data_seen, sized, plan_wrong, grew, reasks = {}, {}, {}, {}, {}, 0

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

for _, board in ipairs(SectionRows.ALL_BOARDS) do
  local key = board.state .. "/" .. board.desc
  LB.load(board.state, board.desc)
  local payload = FP.build(board.state)
  local wire = payload and payload.wire
  if not wire then
    no_frame[#no_frame + 1] = key .. ": no actions/force frame reached the outbox"
  else
    boards = boards + 1
    local flat = wire.unalias(wire.state) .. "\n" .. wire.unalias(wire.query)

    if wire.unalias(wire.state) ~= payload.state then
      mismatched[#mismatched + 1] = string.format(
        "%s state: built %d bytes, wire %d bytes (un-aliased)", key, #payload.state, #wire.state)
    end
    if wire.unalias(wire.query) ~= payload.query then
      mismatched[#mismatched + 1] = string.format(
        "%s query: built %d bytes, wire %d bytes (un-aliased)", key, #payload.query, #wire.query)
    end

    local total, size = #wire.state + #wire.query, WIRE_SIZE[key]
    print(string.format("   [wire] %-20s state=%5d query=%5d sum=%5d  %s",
      board.state, #wire.state, #wire.query, total, board.desc:sub(1, 34)))
    if not size then
      unbudgeted[#unbudgeted + 1] = key .. ": board has no recorded wire size"
    else
      sized[key] = true
      local ceiling = ceiling_of(size)
      if total > ceiling then over[#over + 1] = key .. " sum=" .. total .. " > " .. ceiling end
    end

    local nflat = norm(flat)
    local state_text, query_text = wire.unalias(wire.state), wire.unalias(wire.query)
    local nstate, nquery = norm(state_text), norm(query_text)
    for _, row in ipairs(ROWS) do
      if row.states[board.state] and row.data() then
        exercised = exercised + 1
        per_row[row.id] = (per_row[row.id] or 0) + 1
        data_seen[row.id] = data_seen[row.id] or {}
        data_seen[row.id][board.state] = true
        local where = row.in_state and "state" or "wire"
        if row.header and not has(row.in_state and state_text or flat, row.header) then
          missing_section[#missing_section + 1] = key .. "/" .. row.id
            .. " (no '" .. row.header .. "' in the " .. where .. ")"
        end
        if row.in_state then
          for _, want in ipairs(row.values()) do
            if (row.query_free or #want >= 30) and has_loose(nquery, want) then
              in_query[#in_query + 1] = key .. "/" .. row.id .. " states " .. string.format("%q", want) .. " in the query"
            end
          end
        end
        if row.bank then
          local claims = bank_claims(flat)
          if #claims == 0 then
            missing_section[#missing_section + 1] = key .. "/" .. row.id .. " (no bank figure)"
          else
            local live = "$" .. tostring(G.GAME.dollars)
            for _, v in ipairs(claims) do
              if v ~= live then
                wrong_bank[#wrong_bank + 1] = key .. " says " .. v .. ", live " .. live
              end
            end
          end
        end
        for _, want in ipairs((row.values and row.values()) or {}) do
          if not has_loose(row.in_state and nstate or nflat, want) then
            missing_value[#missing_value + 1] = key .. "/" .. row.id
              .. " does not state " .. string.format("%q", want) .. " in the " .. where
          end
        end
        for _, banned in ipairs((row.forbidden and row.forbidden()) or {}) do
          if has(flat, banned) then
            leaked[#leaked + 1] = key .. "/" .. row.id .. " states " .. string.format("%q", banned)
          end
        end
      end
    end

    local wire_names = {}
    for _, n in ipairs(wire.action_names) do wire_names[wire.unalias(n)] = true end
    for _, canonical in ipairs(payload.actions) do
      if not wire_names[canonical] then
        offers[#offers + 1] = key .. ": offered " .. canonical .. " is not in the frame's action_names"
      end
    end
    if #wire.action_names ~= #payload.actions then
      offers[#offers + 1] = string.format("%s: offered %d actions, the frame carries %d",
        key, #payload.actions, #wire.action_names)
    end

    local want, got = PLAN_ROWS[key] or NO_PLAN, plan_rows(payload.message)
    for _, field in ipairs({ "bytes", "tags", "notes", "credits" }) do
      if got[field] ~= want[field] then
        plan_wrong[#plan_wrong + 1] = string.format("%s plan %s=%d, recorded %d",
          key, field, got[field], want[field])
      end
    end

    local second = FP.build(board.state)
    if second and second.wire then reasks = reasks + 1 end
    if second and (#second.state + #second.query) > #payload.state + #payload.query then
      grew[#grew + 1] = string.format("%s re-ask %d > first force %d",
        key, #second.state + #second.query, #payload.state + #payload.query)
    end

  end
end

check("every board delivered an actions/force frame through a real Bridge",
  #no_frame == 0 and boards == 18 and FW.delivered() == boards + reasks,
  table.concat(no_frame, " | ") .. " (frames " .. FW.delivered() .. ", boards " .. boards .. ")")
check("the frame carries the message byte for byte, once the alias rewrite is undone",
  #mismatched == 0, table.concat(mismatched, " | "))
for key in pairs(WIRE_SIZE) do
  if not sized[key] then unbudgeted[#unbudgeted + 1] = key .. ": recorded but never measured" end
end
check("every board has a recorded wire size, and every recorded size a board", #unbudgeted == 0,
  table.concat(unbudgeted, " | "))
check("no frame exceeds its board's ceiling", #over == 0, table.concat(over, " | "))
check("the section rows ran against the frame, not an empty message",
  exercised >= 116, "state/row pairs asserted on the wire: " .. exercised)
do
  local never, dark = {}, {}
  for _, row in ipairs(ROWS) do
    if (per_row[row.id] or 0) == 0 then never[#never + 1] = row.id end
    for state in pairs(row.states) do
      if not (data_seen[row.id] and data_seen[row.id][state]) then dark[#dark + 1] = state .. "/" .. row.id end
    end
  end
  check("every section row was exercised at least once", #never == 0, table.concat(never, "; "))
  check("every state/row pair found live data on at least one board", #dark == 0, table.concat(dark, "; "))
end
check("every required section is on the wire in every state that must carry it",
  #missing_section == 0, table.concat(missing_section, " | "))
check("every section on the wire states the live values",
  #missing_value == 0, table.concat(missing_value, " | "))
check("every board fact a row places in state stays out of the query (BEST_PRACTICES.md:9)",
  #in_query == 0, table.concat(in_query, " | "))
check("every bank figure on the wire is the live one",
  #wrong_bank == 0, table.concat(wrong_bank, " | "))
check("F9b no frame states an identity a row forbids",
  #leaked == 0, table.concat(leaked, " | "))
check("every board reached the wire",
  boards == #SectionRows.ALL_BOARDS,
  string.format("boards=%d expected=%d", boards, #SectionRows.ALL_BOARDS))
check("every offered action reached the frame's action_names",
  #offers == 0, table.concat(offers, " | "))
check("the roster's plan rows cost exactly what is recorded, measured on their own bytes",
  #plan_wrong == 0, table.concat(plan_wrong, " | "))
check("a re-ask never costs more than the force it repeats", #grew == 0, table.concat(grew, " | "))
check("the bridge never refused a force during the sweep",
  #FW.refusals() == 0, table.concat(FW.refusals(), " | "))

FW.close()
done()
