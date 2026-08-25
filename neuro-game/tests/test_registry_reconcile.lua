_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }

local check, done = require("tests.helpers").harness("registry-reconcile")

local STATES = { BLIND_SELECT = 1, SHOP = 2, SELECTING_HAND = 3, GAME_OVER = 4,
  TAROT_PACK = 6, ROUND_EVAL = 7, MENU = 11 }

_G.G = {
  STATE = STATES.SELECTING_HAND, STATES = STATES, STATE_COMPLETE = true,
  TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
  GAME = { dollars = 20, blind_on_deck = "Small", round = 1, chips = 0, STOP_USE = 0,
    current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
    round_resets = { ante = 1, blind_choices = {}, blind_states = {} },
    blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
    hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
  P_BLINDS = {},
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
  hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
  _sort = 0,
  deck = { cards = {} },
  shop_jokers = { cards = {}, config = { card_limit = 2 } },
  shop_vouchers = { cards = {}, config = { card_limit = 1 } },
  shop_booster = { cards = {}, config = { card_limit = 2 } },
  FUNCS = { get_poker_hand_info = function(c) return "Pair", {}, { Pair = { c } }, c end },
  CONTROLLER = { locks = {} },
  E_MANAGER = { queues = {} },
}

local RANKS = { 2, 3, 4, 5, 6, 7, 8 }
local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
for i = 1, 7 do
  G.hand.cards[i] = {
    base = { value = RANKS[i], suit = SUITS[((i - 1) % 4) + 1] },
    sort_id = i,
    config = { center = { key = "c_base", set = "Default" } },
    is_suit = function(_, s) return s == SUITS[((i - 1) % 4) + 1] end,
  }
end

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
Config.set("NEURO_INBOX_TRUNCATE_ON_STARTUP", "off")

local Bridge = require("core.bridge")
local json = require("util.neuro_json")
local ActionRegistry = require("core.action_registry")

local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("registry_reconcile")

local function frames(bridge)
  local f = io.open(IPC_DIR .. "/" .. bridge.outbox_file, "rb")
  if not f then return {} end
  local raw = f:read("*a")
  f:close()
  local out = {}
  for line in raw:gmatch("[^\n]+") do
    local ok, frame = pcall(json.decode, line)
    if ok then out[#out + 1] = frame end
  end
  return out
end

local function since(bridge, mark)
  local all = frames(bridge)
  local out = {}
  for i = mark + 1, #all do out[#out + 1] = all[i] end
  return out
end

local function kinds(list)
  local out = {}
  for _, f in ipairs(list) do out[#out + 1] = f.command end
  return table.concat(out, ",")
end

local function names_of(frame)
  local out = {}
  if frame.command == "actions/register" then
    for _, a in ipairs(frame.data.actions or {}) do out[#out + 1] = a.name end
  else
    for _, n in ipairs(frame.data.action_names or {}) do out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

local function has(list, name)
  for _, n in ipairs(list) do if n == name then return true end end
  return false
end

local function fresh_bridge()
  os.execute("rm -rf " .. IPC_DIR .. " && mkdir -p " .. IPC_DIR)
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = IPC_DIR })
  G.NEURO = b
  b.enabled = true
  b.persona = "neuro"
  b.run_generation = 1
  b.decision_serial = 1
  b.state = "SELECTING_HAND"
  b:send_startup()
  return b
end

local Orchestrator = require("core.orchestrator")
local Actions = require("core.actions")

local real_available = ActionRegistry.available

do
  local b = fresh_bridge()
  b:set_desired_action_names(Orchestrator.desired_action_names)
  Orchestrator.register_valid_actions("SELECTING_HAND")
  local registered = {}
  for _, f in ipairs(frames(b)) do
    if f.command == "actions/register" then
      for _, n in ipairs(names_of(f)) do registered[#registered + 1] = n end
    end
  end
  check("a modelled screen registers its legal actions", #registered > 0, #registered)
  check("play_hand is among them", has(registered, "play_hand"))

  local mark = #frames(b)
  ActionRegistry.available = function() return false end
  local valid = Actions.get_valid_actions_for_state("SELECTING_HAND")
  check("nothing is legal once every predicate refuses", #valid == 0, #valid)

  Orchestrator.register_valid_actions("SELECTING_HAND")
  ActionRegistry.available = real_available

  local emitted = since(b, mark)
  local dropped = {}
  for _, f in ipairs(emitted) do
    if f.command == "actions/unregister" then
      for _, n in ipairs(names_of(f)) do dropped[#dropped + 1] = n end
    end
  end
  check("the empty set reaches the wire as an unregister", #dropped > 0, kinds(emitted))
  check("every previously registered name is withdrawn", #dropped == #registered,
    #dropped .. "/" .. #registered)
  check("play_hand is no longer offered", has(dropped, "play_hand"))
  check("nothing new is registered for an empty screen",
    not kinds(emitted):find("actions/register"), kinds(emitted))
  check("the bridge holds no registered name", next(b._registered_set or {}) == nil)
end

do
  local b = fresh_bridge()
  b:set_desired_action_names(Orchestrator.desired_action_names)
  Orchestrator.register_valid_actions("SELECTING_HAND")
  local mark = #frames(b)
  check("HAND_PLAYED is not modelled", Actions.state_is_modelled("HAND_PLAYED") == false)
  Orchestrator.register_valid_actions("HAND_PLAYED")
  check("an unmodelled screen emits nothing", #since(b, mark) == 0, kinds(since(b, mark)))
  check("and leaves the previous set registered", b._registered_set.play_hand == true)
end

do
  local b = fresh_bridge()
  b:set_desired_action_names(Orchestrator.desired_action_names)
  Orchestrator.register_valid_actions("SELECTING_HAND")
  local mark = #frames(b)
  local offered = {}
  for n in pairs(b._registered_set) do offered[#offered + 1] = n end
  table.sort(offered)
  check("a force window's names are registered", #offered > 1, #offered)

  b:unregister_actions(offered)
  check("withdrawing them emits nothing", #since(b, mark) == 0, kinds(since(b, mark)))
  check("and they are still registered", b._registered_set.play_hand == true)

  Orchestrator.register_valid_actions("SELECTING_HAND")
  check("the reconcile that follows resends nothing", #since(b, mark) == 0, kinds(since(b, mark)))
end

-- 4. Retracting the action being committed is a statement about that commit, so it flies -- and it
--    flies before the result (API/README.md:19-21).
do
  local b = fresh_bridge()
  b:set_desired_action_names(Orchestrator.desired_action_names)
  Orchestrator.register_valid_actions("SELECTING_HAND")
  local mark = #frames(b)

  b:record_action_phase("act-1", "play_hand", "prepared")
  b:unregister_actions({ "play_hand" })
  b:send_action_result("act-1", true, nil)
  local emitted = since(b, mark)
  check("the committed action is withdrawn before its result",
    kinds(emitted) == "actions/unregister,action/result", kinds(emitted))
  check("and it is the committed name", has(names_of(emitted[1]), "play_hand"))
  check("the registry no longer holds it", b._registered_set.play_hand == nil)

  b:record_action_phase("act-1", "play_hand", "completed")
  local mark2 = #frames(b)
  Orchestrator.register_valid_actions("SELECTING_HAND")
  local back = since(b, mark2)
  check("the closed commit brings it back", #back == 1 and back[1].command == "actions/register",
    kinds(back))
  check("and only it", #names_of(back[1]) == 1 and names_of(back[1])[1] == "play_hand",
    table.concat(names_of(back[1]), ","))
end

do
  local b = fresh_bridge()
  b:set_desired_action_names(Orchestrator.desired_action_names)
  Orchestrator.register_valid_actions("SELECTING_HAND")
  local mark = #frames(b)
  b:unregister_actions({ "play_hand", "no_such_action" })
  check("a still-wanted name survives a retraction", #since(b, mark) == 0, kinds(since(b, mark)))

  b.state = "MENU"
  G.STATE = STATES.MENU
  b:unregister_actions({ "play_hand" })
  local emitted = since(b, mark)
  check("a name the new screen does not want is withdrawn",
    #emitted == 1 and emitted[1].command == "actions/unregister", kinds(emitted))
  check("and it is that name", has(names_of(emitted[1]), "play_hand"))
  b.state = "SELECTING_HAND"
  G.STATE = STATES.SELECTING_HAND
end

do
  local b = fresh_bridge()
  b:register_actions({ { name = "play_hand", description = "d", schema = { type = "object" } } })
  local mark = #frames(b)
  b:unregister_actions({ "play_hand" })
  local emitted = since(b, mark)
  check("no provider means no second-guessing",
    #emitted == 1 and emitted[1].command == "actions/unregister", kinds(emitted))
end

os.execute("rm -rf " .. IPC_DIR)
TmpWork.close()
done()
