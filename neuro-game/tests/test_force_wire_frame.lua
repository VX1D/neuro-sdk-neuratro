_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("force-wire-frame")
local FW = require("tests.force_wire")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Census = require("tests.force_census_rows")
local Notation = require("tests.notation_audit")
local WIRE_SIZE = require("tests.force_size_baseline").WIRE
local function band(size)
  local slack = math.min(math.ceil(size * 0.06), 150)
  return size - slack, size + slack
end

FW.attach()

local ROWS = Census.ROWS
local norm, has, has_loose, bank_claims =
  Census.norm, Census.has, Census.has_loose, Census.bank_claims

local no_frame, mismatched, over, under, unbudgeted = {}, {}, {}, {}, {}
local missing_section, missing_value, wrong_bank, notation, offers, leaked = {}, {}, {}, {}, {}, {}
local rewrite = {}
local boards, exercised, groups_seen, per_name = 0, 0, 0, {}

for _, board in ipairs(Census.ALL_BOARDS) do
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
      local floor, ceiling = band(size)
      if total > ceiling then over[#over + 1] = key .. " sum=" .. total .. " > " .. ceiling end
      if total < floor then under[#under + 1] = key .. " sum=" .. total .. " < " .. floor end
    end

    local nflat = norm(flat)
    for _, row in ipairs(ROWS) do
      if row.states[board.state] and row.data() then
        exercised = exercised + 1
        if row.header and not has(flat, row.header) then
          missing_section[#missing_section + 1] = key .. "/" .. row.id
            .. " (no '" .. row.header .. "' on the wire)"
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
          if not has_loose(nflat, want) then
            missing_value[#missing_value + 1] = key .. "/" .. row.id
              .. " does not state " .. string.format("%q", want)
          end
        end
        for _, banned in ipairs((row.forbidden and row.forbidden()) or {}) do
          if has(flat, banned) then
            leaked[#leaked + 1] = key .. "/" .. row.id .. " states " .. string.format("%q", banned)
          end
        end
      end
    end

    local bad, seen, names = Notation.audit(key, flat)
    for _, b in ipairs(bad) do notation[#notation + 1] = b end
    groups_seen = groups_seen + seen
    for n, c in pairs(names) do per_name[n] = (per_name[n] or 0) + c end

    local wire_names = {}
    for _, n in ipairs(wire.action_names) do wire_names[n] = true end
    for _, canonical in ipairs(payload.actions) do
      local alias = nil
      for a in pairs(wire_names) do
        if a:find("^" .. canonical:gsub("([^%w])", "%%%1") .. "_force_%d+$") then alias = a end
      end
      if not alias then
        offers[#offers + 1] = key .. ": offered " .. canonical .. " is not in the frame's action_names"
      end
    end
    if #wire.action_names ~= #payload.actions then
      offers[#offers + 1] = string.format("%s: offered %d actions, the frame carries %d",
        key, #payload.actions, #wire.action_names)
    end

    local raw = wire.state .. "\n" .. wire.query
    for _, canonical in ipairs(payload.actions) do
      if raw:find("%f[%w_]" .. canonical:gsub("([^%w])", "%%%1") .. "%f[^%w_]") then
        rewrite[#rewrite + 1] = key .. ": canonical '" .. canonical .. "' survives on the wire"
      end
    end
    if flat:find("_force_%d+") then
      rewrite[#rewrite + 1] = key .. ": an alias survives after the rewrite was undone"
    end
  end
end

check("every board delivered an actions/force frame through a real Bridge",
  #no_frame == 0 and boards == 19 and FW.delivered() == boards,
  table.concat(no_frame, " | ") .. " (frames " .. FW.delivered() .. ", boards " .. boards .. ")")
check("the frame carries the message byte for byte, once the alias rewrite is undone",
  #mismatched == 0, table.concat(mismatched, " | "))
check("every board has a recorded wire size", #unbudgeted == 0, table.concat(unbudgeted, " | "))
check("no frame exceeds its board's ceiling", #over == 0, table.concat(over, " | "))
check("no frame fell through its board's floor", #under == 0, table.concat(under, " | "))
check("the census ran against the frame, not an empty message",
  exercised >= 117, "state/row pairs asserted on the wire: " .. exercised)
check("every required section is on the wire in every state that must carry it",
  #missing_section == 0, table.concat(missing_section, " | "))
check("every section on the wire states the live values",
  #missing_value == 0, table.concat(missing_value, " | "))
check("every bank figure on the wire is the live one",
  #wrong_bank == 0, table.concat(wrong_bank, " | "))
check("F9b no frame states an identity a row forbids",
  #leaked == 0, table.concat(leaked, " | "))
check("the notation audit found payloads on the wire to audit",
  groups_seen >= 60 and (per_name.play_hand or 0) > 0,
  "objects " .. groups_seen .. ", play_hand payloads " .. tostring(per_name.play_hand))
check("every JSON object on the wire is a registry render of the action it names",
  #notation == 0, "\n  " .. table.concat(notation, "\n  "))
check("every offered action reached the frame's action_names",
  #offers == 0, table.concat(offers, " | "))
check("the bridge never refused a force during the sweep",
  #FW.refusals() == 0, table.concat(FW.refusals(), " | "))

check("the per-window alias rewrite is total in both directions",
  #rewrite == 0, table.concat(rewrite, " | "))
check("the notation predicate still rejects the sentence F1 shipped",
  #Notation.audit("selftest", "To play, send play_hand with {indices:array[1-5]:unique}.") > 0)

FW.close()
done()
