require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("force-offer-references")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Policy = require("core.action_policy")
local Actions = require("core.actions")
local Registry = require("core.action_registry")
local Refs = require("force.force_references")

Actions.get_static_actions()
local AMBIGUOUS = { help = true }
local CATALOG = {}
for _, name in ipairs(Registry.names()) do
  if not AMBIGUOUS[name] then CATALOG[name] = true end
end

local boards = {}
for _, list in ipairs({ LB.BOARDS, LB.BLOCKED, LB.OUT_OF_RUN }) do
  for _, b in ipairs(list) do boards[#boards + 1] = b end
end

local stray, tools_seen, framed = {}, 0, 0
for _, board in ipairs(boards) do
  local key = board.state .. "/" .. board.desc
  LB.load(board.state, board.desc)
  local payload = FP.build(board.state)
  if payload then
    framed = framed + 1
    local force = require("force.force_router").get_force_for_state(board.state) or {}
    for _, name in ipairs(force.tools or {}) do
      if Policy.is_tool(name) then tools_seen = tools_seen + 1 end
    end
    for field, text in pairs({ query = payload.query, state = payload.state }) do
      for _, name in ipairs(Refs.named_actions(text, CATALOG)) do
        stray[#stray + 1] = key .. " " .. field .. ": " .. name
      end
    end
  end
end

check("the sweep framed the whole corpus", framed == #boards, framed .. "/" .. #boards)
check("the forces describe tools beside their decisions", tools_seen >= 25, tostring(tools_seen))
check("no query or state names an action", #stray == 0,
  table.concat(stray, "; "))

done()
