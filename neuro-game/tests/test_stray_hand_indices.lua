require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("stray-hand-indices")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local TxCache = require("core.bridge").tx

local n = 0
local function use_neptune(hand_indices)
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  local neptune = LB.consumable("c_neptune", 700)
  neptune.area = G.consumeables
  G.consumeables.cards = { neptune }
  FP.build("SELECTING_HAND")
  local results = {}
  G.NEURO.send_action_result = function(_, _, ok, message, code)
    results[#results + 1] = { ok = ok, message = message, code = code }
    return true
  end
  G.NEURO.withdraw_actions = function() return true end
  Helpers.stage_registered(nil, { "use_consumable" })
  n = n + 1
  TxCache.open("stray-" .. n, "use_consumable", G.TIMERS.REAL)
  require("core.dispatcher").handle_message({ command = "action", data = { id = "stray-" .. n, name = "use_consumable",
    data = require("util.neuro_json").encode({ area = "consumables", index = 1, name = "Neptune", hand_indices = hand_indices }) } },
    G.NEURO)
  return results[1] or {}
end

local r = use_neptune({ 1, 2, 3, 4, 5 })
check("a card that targets nothing is used even when she adds hand_indices without their names",
  r.ok == true and r.code == "ACTION_ACCEPTED", tostring(r.code) .. " " .. tostring(r.message))
r = use_neptune({})
check("an empty hand_indices on a card that targets nothing is not refused by the schema",
  r.ok == true and r.code == "ACTION_ACCEPTED", tostring(r.code) .. " " .. tostring(r.message))
done()
