require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })
local check, done = require("tests.helpers").harness("menu-query-prose")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")

LB.load("MENU", "Normal: has G.GAME")
local payload = FP.build("MENU")
local query = payload and payload.query or ""
check("the menu force is built", payload ~= nil and query ~= "")

local leaked = {}
for name in pairs(require("tests.engine_cards").states()) do
  if query:find("%f[%w_]" .. name .. "%f[^%w_]") then leaked[#leaked + 1] = name end
end
table.sort(leaked)
check("the menu query names no internal state token", #leaked == 0, table.concat(leaked, ", ") .. " || " .. query)

done()
