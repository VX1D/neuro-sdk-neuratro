require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("offered-payload-choice")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Registry = require("core.action_registry")
require("core.actions")

local boards, candidate_count, array_count = 0, 0, 0
local invalid, missing = {}, {}
local function candidate_in_force(force, name, candidate)
  local query = tostring(force.query or "") .. "\n" .. tostring(force.state or "")
  local rendered = Registry.render(name, candidate)
  if rendered and query:find(rendered, 1, true) then return true end
  local scalar = {}
  if candidate.area ~= nil then scalar.area = candidate.area end
  if candidate.index ~= nil then scalar.index = candidate.index end
  local base = Registry.render(name, scalar)
  return base ~= nil and query:find(base, 1, true) ~= nil
end

for _, board in ipairs(LB.BOARDS) do
  LB.load(board.state, board.desc)
  local force = FP.build(board.state)
  if force then
    boards = boards + 1
    for _, name in ipairs(force.actions or {}) do
      local contract = Registry.get(name)
      if not contract then
        invalid[#invalid + 1] = name
      else
        local candidates = Registry.candidates(name)
        for _, candidate in ipairs(candidates) do
          candidate_count = candidate_count + 1
          if type(candidate) ~= "table" then
            invalid[#invalid + 1] = name .. ": non-object candidate"
          else
            if not candidate_in_force(force, name, candidate) then
              missing[#missing + 1] = board.state .. "/" .. name
            end
            for _, value in pairs(candidate) do
              if type(value) == "table" and #value > 0 then
                array_count = array_count + 1
              end
            end
          end
        end
        local guidance = Registry.render(name, {})
        if guidance:find("|{", 1, true) then invalid[#invalid + 1] = name .. ": legacy guidance" end
      end
    end
  end
end

check("the sweep visits force action surfaces", boards >= 11, tostring(boards))
check("every offered action has a registry contract", #invalid == 0, table.concat(invalid, ", "))
check("every emitted candidate is bound in its own force prose",
  #missing == 0, table.concat(missing, ", "))
check("candidate payloads are structured objects", candidate_count > 0, tostring(candidate_count))
check("candidate payloads leave optional array targeting to the action schema",
  array_count == 0, tostring(array_count))

done()
