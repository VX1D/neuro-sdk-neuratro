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

local function has(list, command)
  for i = 1, #list do
    if list[i] == command then return true end
  end
  return false
end

Registry.reset()
do
  local b, sent = new_bridge()
  b:register_actions({ def("play_hand") })
  check("register_actions sends a frame and records registration",
    has(sent, "actions/register") and Registry.is_registered("play_hand") == true)
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
  b:register_actions({ def("play_hand"), def("discard_hand") })
  b:register_actions({ def("play_hand") })
  check("removing an action preserves the remaining registration only",
    Registry.is_registered("play_hand") == true
      and Registry.is_registered("discard_hand") == false)
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
  b:register_actions({ def("play_hand") })
  b:unregister_actions({ "play_hand" })
  check("unregister_actions removes the registration",
    Registry.is_registered("play_hand") == false)
  b:register_actions({ def("play_hand") })
  check("re-registration after unregister succeeds",
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
    STATES = { SELECTING_HAND = 4 }, STATE = 4, TIMERS = { REAL = 0 },
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
  local ForceState = require("core.force_state")
  G.NEURO.force_inflight = false
  G.NEURO.force_window = nil
  ForceState.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 100)
  ForceState.mark_sent(100)
  local results = {}
  local b = {
    send_action_result = function(_, id, ok, msg, reason)
      results[#results + 1] = { ok = ok, reason = reason }
    end,
    send_context = function() return true end,
    unregister_actions = function() end,
  }
  Dispatcher.route_message({ command = "action", run_generation = 1,
    data = { id = "why-it-matters", name = "play_hand", data = '{"indices":[1]}' } }, b)
  check("an empty registry rejects a forced action while its window is open",
    results[1] and results[1].ok == false and results[1].reason == "ACTION_UNKNOWN",
    results[1] and tostring(results[1].reason))
  check("the force window survives the rejection for a valid retry",
    G.NEURO.force_inflight == true, tostring(G.NEURO.force_inflight))
end

do
  local ActionResult = require("core.action_result")
  local ok, errors = Registry.validate()
  check("validate passes cleanly", ok == true, table.concat(errors or {}, ", "))

  local code_set = {}
  for _, code in ipairs(Registry.DEFAULT_FAILURE_CODES or {}) do
    code_set[code] = true
  end

  for code, _ in pairs(ActionResult.CODES) do
    check("CODES[" .. code .. "] is in action_registry DEFAULT_FAILURE_CODES",
      code_set[code] == true, code)
  end

  for _, code in ipairs(Registry.DEFAULT_FAILURE_CODES or {}) do
    check("DEFAULT_FAILURE_CODES[" .. code .. "] is in action_result CODES",
      ActionResult.CODES[code] ~= nil, code)
  end
end

do
  local ActionResult = require("core.action_result")
  ActionResult.CODES.N206_PROBE_CODE = { safe_to_retry = false, transient = false }

  local saved_module = package.loaded["core.action_registry"]
  package.loaded["core.action_registry"] = nil
  local ok_req, FreshRegistry = pcall(require, "core.action_registry")
  package.loaded["core.action_registry"] = saved_module -- restore the shared singleton
  ActionResult.CODES.N206_PROBE_CODE = nil

  local found = false
  if ok_req and FreshRegistry and FreshRegistry.DEFAULT_FAILURE_CODES then
    for _, code in ipairs(FreshRegistry.DEFAULT_FAILURE_CODES) do
      if code == "N206_PROBE_CODE" then found = true end
    end
  end
  check("DEFAULT_FAILURE_CODES is derived from action_result.CODES, not a duplicate literal",
    ok_req and found == true)
end

Registry.reset()
done()
