require("tests.stubs").setup({ love = "lazy" })
_G.G = require("tests.helpers").base_G()
local check, done = require("tests.helpers").harness("card-binding")
local H = require("tests.helpers")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local TxCache = require("core.bridge").tx
local json = require("util.neuro_json")

local function neuro()
  G.NEURO = H.started_bridge({ state = "SELECTING_HAND", state_enter_serial = 1, decision_serial = 1, run_generation = 1,
    enabled = true, persona = "neuro", dispatcher = Dispatcher, actions = Actions,
    register_actions = H.noop, send_context = H.yes, is_transition_cooldown = H.no })
end

local n = 0
local function send(name, payload)
  n = n + 1
  local id = "cb-" .. n
  local b = H.fake_bridge({ reason = "reason_code" })
  require("core.validate").reset_run_state()
  assert(TxCache.open(id, name, G.TIMERS.REAL))
  Dispatcher.handle_message({ command = "action", data = { id = id, name = name, data = json.encode(payload) } }, b)
  return b.results[#b.results] or {}
end

local function fresh()
  H.selecting_hand_env({ reset_tx_cache = true, time = 100 + n })
  neuro()
  H.stage_registered("SELECTING_HAND", { "play_hand", "discard_hand", "use_consumable", "use_directional_consumable" })
end

do
  fresh()
  local r = send("discard_hand", { indices = { 2, 1 }, cards = { "5 of Hearts", "6 of Hearts" } })
  check("the name echo is a multiset: names in hand order match unsorted indices", r.ok == true,
    tostring(r.reason_code) .. " " .. tostring(r.message))
  fresh()
  r = send("discard_hand", { indices = { 1, 2 }, cards = { "5 of Hearts", "5 of Hearts" } })
  check("a name sent more times than the selection holds it is refused by count",
    r.reason_code == "STALE_TARGET" and tostring(r.message):find("You named 5 of Hearts 2 times, but the positions you "
      .. "selected (1. 5 of Hearts, 2. 6 of Hearts) hold it 1 time, so nothing was done.", 1, true) ~= nil, tostring(r.message))
end

do
  fresh()
  local names = { "5 of Hearts", "6 of Hearts" }
  local r = send("discard_hand", { indices = { 1, 2 }, cards = names })
  check("a selection whose names match the hand is accepted", r.ok == true, tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  table.remove(G.hand.cards, 1)
  local r = send("discard_hand", { indices = { 1, 2 }, cards = { "5 of Hearts", "6 of Hearts" } })
  check("positions from an earlier hand are refused as stale, not played",
    r.ok == false and r.reason_code == "STALE_TARGET", tostring(r.reason_code))
  check("the refusal lists the hand as it is now",
    tostring(r.message):find("1. 6 of Hearts", 1, true) ~= nil, tostring(r.message))
end

do
  fresh()
  local r = send("play_hand", { indices = { 1, 2 }, cards = { "5 of Hearts" } })
  check("one name per index is required", r.ok == false and r.reason_code == "STALE_TARGET", tostring(r.reason_code))
end

do
  fresh()
  local r = send("play_hand", { indices = { 1, 2 } })
  check("cards is an optional echo: a selection without names is accepted",
    r.ok == true and r.reason_code == "CONFIRMATION_REQUIRED", tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  local r = send("play_hand", { indices = { 9 } })
  check("an index out of range is reported as such", r.ok == false
    and tostring(r.message):find("Index 9 is out of range", 1, true) ~= nil, tostring(r.reason_code) .. " " .. tostring(r.message))
  r = send("play_hand", { indices = { 1, 9 }, cards = { "5 of Hearts", "6 of Hearts" } })
  check("an index's own error comes before the names that echo it", r.ok == false
    and tostring(r.message):find("Index 9 is out of range", 1, true) ~= nil, tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  G.hand.cards[2].facing = "back"
  local r = send("discard_hand", { indices = { 1, 2 }, cards = { "5 of Hearts", "face-down" } })
  check("a face-down card is named face-down, so selecting it needs no hidden information", r.ok == true,
    tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  G.STATE = G.STATES.BLIND_SELECT
  local r = send("play_hand", { indices = { 1, 2 } })
  check("a move that is not part of this screen is refused as such before its fields are checked",
    r.ok == false and r.reason_code == "ACTION_UNAVAILABLE" and tostring(r.message):find("isn't part of this screen", 1, true) ~= nil,
    tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  H.stage_registered("SELECTING_HAND", { "play_hand", "discard_hand", "record_plan" })
  local r = send("record_plan", { hand_plan = "Play pairs" })
  check("record_plan on the hand screen says where a plan is recorded",
    r.ok == false and tostring(r.message):find("recorded at blind select, after the round or in the shop", 1, true) ~= nil,
    tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  local opened = send("play_hand", { indices = { 1, 2 }, cards = { "5 of Hearts", "6 of Hearts" } })
  local r = send("discard_hand", { indices = { 3 } })
  check("while a play review is open, a move without card names is acknowledged, not refused into a retry",
    opened.reason_code == "CONFIRMATION_REQUIRED" and r.ok == true and r.reason_code == "POLICY_ACKNOWLEDGED",
    tostring(opened.reason_code) .. " / " .. tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  local r = send("discard_hand", { indices = { 1 }, cards = { "6 of Hearts" } })
  check("a misnamed card is refused with the fact, without claiming the hand changed",
    r.reason_code == "STALE_TARGET" and tostring(r.message):find("6 of Hearts is not among the cards at the positions you selected (1. 5 of Hearts), so nothing was done.", 1, true) ~= nil
      and tostring(r.message):find("hand has changed", 1, true) == nil, tostring(r.message))
  r = send("discard_hand", { indices = { 1 } })
  check("a discard without names is accepted", r.ok == true, tostring(r.reason_code) .. " " .. tostring(r.message))
end

do
  fresh()
  local r = send("discard_hand", { indices = { 1 }, cards = json.array({}) })
  check("an empty cards echo counts as absent", r.ok == true, tostring(r.reason_code) .. " " .. tostring(r.message))
  local SchemaValidate = require("util.schema_validate")
  for name, area in pairs({ use_directional_consumable = "consumables", choose_directional_pack_card = "booster_pack" }) do
    local schema = require("core.action_registry").get(name).schema
    check(name .. "'s schema admits an empty left_card/right_card echo", SchemaValidate.validate_value(schema,
      { area = area, index = 1, name = "Death", left_index = 1, left_card = "", right_index = 2, right_card = "" },
      "parameters"))
  end
end

do
  fresh()
  H.in_engine_state("BLIND_SELECT")
  G.GAME.round_resets.blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" }
  H.stage_registered("BLIND_SELECT", { "select_blind", "skip_blind", "play_hand", "discard_hand" })
  n = n + 1
  local id = "cb-" .. n
  local b = H.fake_bridge({ reason = "reason_code" })
  b.is_transition_cooldown = function() return true end
  require("core.validate").reset_run_state()
  assert(TxCache.open(id, "play_hand", G.TIMERS.REAL))
  Dispatcher.handle_message({ command = "action", data = { id = id, name = "play_hand",
    data = json.encode({ indices = { 1, 2 }, cards = { "5 of Hearts", "6 of Hearts" } }) } }, b)
  local r = b.results[#b.results] or {}
  check("a move for the next screen sent while the screen is changing is told to wait, not refused as off-screen",
    r.reason_code == "TRANSITION_PENDING", tostring(r.reason_code) .. " " .. tostring(r.message))
end

done()
