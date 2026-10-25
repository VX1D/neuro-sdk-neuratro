local ES = require("tests.engine_cards").states()
local check, done = require("tests.helpers").harness("action-registration-contract")

local Bridge = require("core.bridge")
local Registry = require("core.action_registry")
local Dispatcher = require("core.dispatcher")

local function new_bridge()
  local sent = {}
  local b = setmetatable({ send = function(_, msg) sent[#sent + 1] = msg.command end },
    { __index = Bridge })
  return b, sent
end

local function def(name, description)
  return { name = name, description = description or "d", schema = { type = "object" } }
end

local has = require("tests.helpers").has

Registry.reset()
do
  local b, sent = new_bridge()
  b:register_actions({ def("play_hand") })
  check("register_actions sends a frame and records registration",
    has(sent, "actions/register") and Registry.is_registered("play_hand") == true)
end

do
  Registry.reset()
  local b, sent = new_bridge()
  local ok = b:register_actions({ def("empty_description", "") })
  check("contract-valid empty descriptions register",
    ok == true and has(sent, "actions/register") and Registry.is_registered("empty_description") == true)
end
do
  Registry.reset()
  local b, sent = new_bridge()
  local ok = b:register_actions({ def("whitespace_description", " \t\n ") })
  check("contract-valid whitespace descriptions register like Rust wire sanitization",
    ok == true and has(sent, "actions/register")
      and Registry.is_registered("whitespace_description") == true)
end
do
  Registry.reset()
  local b, sent = new_bridge()
  local ok_call, refused = pcall(Registry.register, 17)
  local accepted = b:register_actions({ def("valid_sibling") })
  check("a scalar malformed definition is skipped without crashing or costing valid siblings",
    ok_call and refused == false and accepted == true and has(sent, "actions/register")
      and Registry.is_registered("valid_sibling") == true)
end
do
  Registry.reset()
  local b, sent = new_bridge()
  local long_name = string.rep("a", 1025)
  local ok = b:register_actions({ def(long_name) })
  check("frame-valid long action names remain registrable",
    ok == true and has(sent, "actions/register")
      and Registry.is_registered(long_name) == true)
end
do
  Registry.reset()
  local b, sent = new_bridge()
  local long_description = string.rep("d", 64 * 1024 + 1)
  local ok = b:register_actions({ def("description_bomb", long_description) })
  check("frame-valid long action descriptions remain registrable",
    ok == true and has(sent, "actions/register")
      and Registry.is_registered("description_bomb") == true)
  local catalogue_bomb = {}
  for i = 1, 70 do catalogue_bomb[i] = def("catalogue_bomb_" .. i, string.rep("c", 60 * 1024)) end
  local catalogue_ok = b:register_actions(catalogue_bomb)
  check("frame-valid action catalogues remain registrable",
    catalogue_ok == true and has(sent, "actions/register")
      and Registry.is_registered("catalogue_bomb_70") == true)
end
do
  Registry.reset()
  local b, sent = new_bridge()
  local deep = { type = "object" }
  local cursor = deep
  for _ = 1, 65 do
    cursor.properties = { child = { type = "object" } }
    cursor = cursor.properties.child
  end
  local ok = b:register_actions({
    { name = "deep_schema", description = "d", schema = deep },
  })
  check("schema depth within the parser bound remains registrable",
    ok == true and has(sent, "actions/register")
      and Registry.is_registered("deep_schema") == true)
end
do
  Registry.reset()
  local b, sent = new_bridge()
  local actions = {}
  for i = 1, 4097 do actions[i] = def("bounded_" .. i) end
  local ok = b:register_actions(actions)
  check("frame-valid action batches remain registrable",
    ok == true and #sent > 0 and Registry.is_registered("bounded_4097") == true)
end


do
  local b, sent = new_bridge()
  b:register_actions({ def("play_hand") })
  sent[1] = nil
  local before = #sent
  b:register_actions({ def("play_hand") })
  check("dedup: an identical contract sends no frame but remains registered",
    #sent == before and Registry.is_registered("play_hand") == true)
end

do
  Registry.reset()
  local b = new_bridge()
  b:register_actions({ def("play_hand") })
  Dispatcher.reset_tx()
  check("reset_tx clears the registry", Registry.is_registered("play_hand") == false)
  b:register_actions({ def("play_hand") })
  check("after registry reset, register_actions restores registration even when the frame is deduplicated",
    Registry.is_registered("play_hand") == true)
end
do
  Registry.reset()
  local b = new_bridge()
  b:register_actions({ def("first_incremental") })
  b:register_actions({ def("second_incremental") })
  Dispatcher.reset_tx()
  b:register_actions({ def("first_incremental") })
  check("an unchanged incremental registration restores dispatch visibility after a reset",
    Registry.is_registered("first_incremental") == true)
end

do
  Registry.reset()
  local b = new_bridge()
  b:register_actions({ def("play_hand") })
  b:withdraw_actions({ "play_hand" })
  check("a completed withdrawal removes the registration",
    Registry.is_registered("play_hand") == false)
  b:register_actions({ def("play_hand") })
  check("re-registration after a withdrawal succeeds",
    Registry.is_registered("play_hand") == true)
end

do
  Registry.reset()
  local b = new_bridge()
  local def_a = { name = "play_hand", description = "Play", schema = { type = "object", properties = { cards = { type = "array", minItems = 1 } } } }
  b:register_actions({ def_a })
  check("the initial registration is active",
    Registry.is_registered("play_hand") == true and Registry.is_recently_unregistered("play_hand") == false)

  local def_b = { name = "play_hand", description = "Play", schema = { type = "object", properties = { cards = { type = "array", minItems = 2 } } } }
  b:register_actions({ def_b })
  check("a schema change leaves the action registered",
    Registry.is_registered("play_hand") == true, tostring(Registry.is_registered("play_hand")))
  check("a schema change does not leave the action recently unregistered",
    Registry.is_recently_unregistered("play_hand") == false, tostring(Registry.is_recently_unregistered("play_hand")))
end

do
  Registry.reset()
  _G.G = {
    NEURO = { dispatcher = Dispatcher, actions = require("core.actions"), run_generation = 1 },
    FUNCS = {}, GAME = { current_round = { hands_left = 4, discards_left = 3 } },
    STATES = ES, STATE = ES.SELECTING_HAND, TIMERS = { REAL = 0 },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 5 } },
    jokers = { cards = {}, config = { card_limit = 5 } },
  }
  G.NEURO.state = "SELECTING_HAND"
  local results, contexts = {}, {}
  local b = {
    send_action_result = function(_, id, ok, msg, reason)
      results[#results + 1] = { id = id, ok = ok, msg = msg, reason = reason }
    end,
    send_context = function(_, msg) contexts[#contexts + 1] = tostring(msg) return true end,
  }
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "unreg-1", name = "help" } }, b)
  check("an empty registry rejects an otherwise ungated action",
    results[1] ~= nil and results[1].ok == false,
    results[1] and tostring(results[1].ok))
  check("an empty registry reports ACTION_UNKNOWN",
    results[1] and results[1].reason == "ACTION_UNKNOWN",
    results[1] and tostring(results[1].reason))
  check("an empty registry does not execute the handler", #contexts == 0, contexts[1])
end

do
  Registry.reset()
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local results = {}
  local b = {
    send_action_result = require("tests.helpers").result_log(results, { "_", "ok", "_", "reason" }),
    send_context = require("tests.helpers").yes,
  }
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "why-it-matters", name = "play_hand", data = '{"indices":[1]}' } }, b)
  check("an empty registry rejects a forced action while its window is open",
    results[1] and results[1].ok == false and results[1].reason == "ACTION_UNREGISTERED",
    results[1] and tostring(results[1].reason))
  check("the force window survives the rejection for a valid retry",
    require("core.window").current() ~= nil)
end

Registry.reset()
done()
