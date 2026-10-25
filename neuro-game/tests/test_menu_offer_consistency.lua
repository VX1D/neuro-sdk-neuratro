require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("menu-offer-consistency")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

local Actions = require("core.actions")
local MenuFlow = require("force.menu_flow")

local PICKS = { select_deck = "deck", select_stake = "stake" }

local covered = {}
for _, sc in ipairs(LB.OUT_OF_RUN) do covered[sc.state] = true end
for _, screen in ipairs(MenuFlow.SCREENS) do
  check(screen .. ": the menu-flow screen has a board in this test", covered[screen] == true)
end

for _, sc in ipairs(LB.OUT_OF_RUN) do
  LB.load(sc.state, sc.desc)
  local cap = FP.build(sc.state)
  if cap then
    local offered = {}
    for _, name in ipairs(cap.actions) do offered[name] = true end
    for _, name in ipairs(cap.actions) do
      check(sc.state .. ": the offered " .. name .. " is valid on this screen", Actions.is_action_valid(name))
    end
    for tool in pairs(PICKS) do
      if cap.query:find(tool, 1, true) then
        check(sc.state .. ": the query names " .. tool .. " only when it is offered", offered[tool] == true)
      end
    end
  end
end

done()
