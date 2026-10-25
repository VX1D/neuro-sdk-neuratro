require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("registry-reconcile")

local STATES = require("tests.engine_cards").states()

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
  FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Pair") },
  CONTROLLER = { locks = {} },
  E_MANAGER = { queues = {} },
}

local SUITS = { "Spades", "Hearts", "Clubs", "Diamonds" }
for i = 1, 7 do
  G.hand.cards[i] = require("tests.engine_cards").playing(tostring(i + 1), SUITS[((i - 1) % 4) + 1], { sort_id = i })
end

local Config = require("core.config")
Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off")
Config.set("NEURO_INBOX_TRUNCATE_ON_STARTUP", "off")

local Bridge = require("core.bridge")
local ActionRegistry = require("core.action_registry")
local TxCache = require("core.bridge").tx


local TmpWork = require("tests.tmp_workdir")
local IPC_DIR = TmpWork.open("registry_reconcile")

local function frames(bridge)
  return require("tests.helpers").outbox_frames(IPC_DIR .. "/" .. bridge.outbox_file)
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

local has = require("tests.helpers").has

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
  require("core.window").register_catalogue()
  local registered = {}
  for _, f in ipairs(frames(b)) do
    if f.command == "actions/register" then
      for _, n in ipairs(names_of(f)) do registered[#registered + 1] = n end
    end
  end
  check("play_hand is among them", has(registered, "play_hand"))

  local mark = #frames(b)
  ActionRegistry.available = function() return false end
  local valid = Actions.get_valid_actions_for_state("SELECTING_HAND")
  check("nothing is legal once every predicate refuses", #valid == 0, #valid)

  require("core.window").register_catalogue()
  ActionRegistry.available = real_available

  local emitted = since(b, mark)
  local dropped = {}
  for _, f in ipairs(emitted) do
    if f.command == "actions/unregister" then
      for _, n in ipairs(names_of(f)) do dropped[#dropped + 1] = n end
    end
  end
  check("legality changes do not retract the stable canonical catalogue", #dropped == 0, kinds(emitted))
  check("play_hand remains a registered canonical definition", b._registered_sigs.play_hand ~= nil)
  check("the stable catalogue is not re-registered for a legality-only change",
    not kinds(emitted):find("actions/register"), kinds(emitted))
end

do
  local b = fresh_bridge()
  require("core.window").register_catalogue()
  local mark = #frames(b)
  require("core.window").register_catalogue()
  check("an unmodelled screen emits nothing", #since(b, mark) == 0, kinds(since(b, mark)))
  check("and leaves the previous set registered", b._registered_sigs.play_hand ~= nil)
end

do
  local b = fresh_bridge()
  require("core.window").register_catalogue()
  local mark = #frames(b)
  local offered = {}
  for n in pairs(b._registered_sigs) do offered[#offered + 1] = n end
  table.sort(offered)
  check("a force window's names are registered", #offered > 1, #offered)

  b:withdraw_actions(offered)
  local withdrawn = since(b, mark)
  check("an explicit withdrawal emits the requested registered names",
    #withdrawn == 1 and withdrawn[1].command == "actions/unregister"
      and #names_of(withdrawn[1]) == #offered, kinds(withdrawn))
  check("an explicit withdrawal removes the names", b._registered_sigs.play_hand == nil)

  require("core.window").register_catalogue()
  check("a catalogue sync keeps withdrawn actions off until a force offers them",
    #since(b, mark) == 1, kinds(since(b, mark)))
  require("core.window").register_catalogue(offered)
  local reapplied = since(b, mark)
  check("the force that offers them brings them back",
    #reapplied == 2 and reapplied[2].command == "actions/register"
      and #names_of(reapplied[2]) == #offered, kinds(reapplied))
end

do
  local b = fresh_bridge()
  require("core.window").register_catalogue()
  local mark = #frames(b)

  b:withdraw_actions({ "play_hand" })
  assert(TxCache.open("act-1", "play_hand", G.TIMERS.REAL))
  b:send_action_result("act-1", true, nil)
  local emitted = since(b, mark)
  check("the committed action is withdrawn before its result",
    kinds(emitted) == "actions/unregister,action/result", kinds(emitted))
  check("and it is the committed name", has(names_of(emitted[1]), "play_hand"))
  check("the registry no longer holds it", b._registered_sigs.play_hand == nil)

  local mark2 = #frames(b)
  require("core.window").register_catalogue()
  check("the closed commit alone does not bring it back", #since(b, mark2) == 0,
    kinds(since(b, mark2)))
  require("core.window").register_catalogue({ "play_hand", "discard_hand" })
  local back = since(b, mark2)
  check("the next force offering it brings it back", #back == 1 and back[1].command == "actions/register",
    kinds(back))
  check("and only it", #names_of(back[1]) == 1 and names_of(back[1])[1] == "play_hand",
    table.concat(names_of(back[1]), ","))
end

do
  local b = fresh_bridge()
  require("core.window").register_catalogue()
  local mark = #frames(b)
  b:withdraw_actions({ "play_hand", "no_such_action" })
  local emitted = since(b, mark)
  check("an explicit withdrawal is not filtered by desired names",
    #emitted == 1 and emitted[1].command == "actions/unregister"
      and has(names_of(emitted[1]), "play_hand"), kinds(emitted))
  check("the explicitly withdrawn action is absent", b._registered_sigs.play_hand == nil)

  b.state = "MENU"
  G.STATE = STATES.MENU
  b:withdraw_actions({ "play_hand" })
  check("repeating a withdrawal for an absent action emits nothing",
    #since(b, mark) == 1, kinds(since(b, mark)))
  b.state = "SELECTING_HAND"
  G.STATE = STATES.SELECTING_HAND
end

do
  local b = fresh_bridge()
  b:register_actions({ { name = "play_hand", description = "d", schema = { type = "object" } } })
  local mark = #frames(b)
  b:withdraw_actions({ "play_hand" })
  local emitted = since(b, mark)
  check("no provider means no second-guessing",
    #emitted == 1 and emitted[1].command == "actions/unregister", kinds(emitted))
end

do
  local b = fresh_bridge()
  require("core.window").register_catalogue()
  local mark = #frames(b)
  b:withdraw_actions({ "play_hand", "discard_hand" })
  local cancelled = since(b, mark)
  check("a force cancellation sends the unregister alone, with no register behind it",
    kinds(cancelled) == "actions/unregister", kinds(cancelled))
  require("core.window").register_catalogue()
  check("a catalogue sync keeps the cancelled names off", #since(b, mark) == 1, kinds(since(b, mark)))
  require("core.window").register_catalogue({ "play_hand" })
  local back = since(b, mark)
  check("the next force brings back only what it offers",
    #back == 2 and back[2].command == "actions/register"
      and #names_of(back[2]) == 1 and names_of(back[2])[1] == "play_hand", kinds(back))
end

os.execute("rm -rf " .. IPC_DIR)
TmpWork.close()
done()
