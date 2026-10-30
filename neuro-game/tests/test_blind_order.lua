require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("blind-order")
local LB = require("tests.fixtures.live_board")
local Helpers = require("tests.helpers")
local TxCache = require("core.bridge").tx

local n = 0
local function send(name, data)
  local results = {}
  G.NEURO.send_action_result = function(_, _, ok, message, code)
    results[#results + 1] = { ok = ok, message = message, code = code }
    return true
  end
  G.NEURO.withdraw_actions = function() return true end
  Helpers.stage_registered(nil, { name })
  n = n + 1
  TxCache.open("blind-" .. n, name, G.TIMERS.REAL)
  require("core.dispatcher").handle_message(Helpers.inbound_action(name, "blind-" .. n, data), G.NEURO)
  return results[1] or {}
end

check("the rules say blinds are played in a fixed order",
  require("context.game_rules").invariant_frame():find("played in that fixed order", 1, true) ~= nil)

LB.load("BLIND_SELECT", "Small blind selectable")
require("tests.force_payload").build("BLIND_SELECT")
local rr = G.GAME.round_resets
rr.blind_states = rr.blind_states or { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
rr.blind_tags = rr.blind_tags or { Small = "tag_economy", Big = "tag_double" }
for _, want in ipairs({ "big", "boss" }) do
  local r = send("select_blind", { blind = want, plan = { hand_plan = "Play pairs", build_plan = "Scale mult" } })
  check("asking for " .. want .. " while small is on deck says small comes first and can be skipped",
    r.ok == false and tostring(r.message):find("so small comes first: select it or skip it.", 1, true) ~= nil,
    tostring(r.code) .. " " .. tostring(r.message))
end
rr.blind_states = { Small = "Skipped", Big = "Select", Boss = "Upcoming" }
local r = send("select_blind", { blind = "boss", plan = { hand_plan = "Play pairs", build_plan = "Scale mult" } })
check("asking for boss while big is on deck says big comes first",
  r.ok == false and tostring(r.message):find("so big comes first: select it or skip it.", 1, true) ~= nil,
  tostring(r.code) .. " " .. tostring(r.message))
done()
