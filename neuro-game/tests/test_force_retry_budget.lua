require("tests.stubs").setup({ love = "timers", G = "timed" })

local check, done = require("tests.helpers").harness("force-no-retry-budget")

local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()
local Actions = require("core.actions")
local TxCache = require("core.bridge").tx
local ActionReceipt = require("core.action_result")

local play_card = require("tests.helpers").play_card

local function bridge()
  return require("tests.helpers").fake_bridge({ reason = "reason", ack = "written", register = "noop", cooldown = true })
end

local function env(t)
  G.TIMERS.REAL = t
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  G.STATE_COMPLETE = true; G.OVERLAY_MENU = nil; G.CONTROLLER = nil
  G.GAME = { dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } }, modifiers = {} }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Pair") }
  require("core.validate").reset_run_state()
  Enforce.reset_run_state()
  TxCache.reset()
  local b = bridge()
  G.NEURO = { enabled = true, decision_serial = 1, run_generation = 1, persona = "neuro",
    dispatcher = Dispatcher, actions = Actions,
    send_context = function() return true end }
  require("tests.helpers").stage_registered("SELECTING_HAND",
    { "buy_from_shop", "leave_shop", "discard_hand" })
  return b
end

local function counts(b)
  local retried, terminal = 0, 0
  for _, r in ipairs(b.results) do
    if r.ok == false then retried = retried + 1 else terminal = terminal + 1 end
  end
  return retried, terminal
end

local function send(b, msg) Dispatcher.route_message(msg, b) end

local function stuck(id, b)
  require("core.execute").abort("test")
  require("core.execute").admit({ id = id, name = "play_hand", data = {}, bridge = b,
    run_generation = G.NEURO.run_generation, state = "SELECTING_HAND",
    exec = function()
      return ActionReceipt.create({ id = id, name = "play_hand", run_generation = G.NEURO.run_generation,
        deadline = ActionReceipt.now() + 100000, probe = function() return "pending" end,
        timeout_outcome = "ambiguous" })
    end }, false)
  b.results = {}
end

local function all_refused(label, b, sends)
  local retried, terminal = counts(b)
  check(label, retried == sends and terminal == 0,
    string.format("sends=%d success:false=%d success:true=%d", sends, retried, terminal))
end

do
  local b = env(700)
  local payloads = { '{"indices":[97]}', '{"indices":[98]}' }
  for i = 1, 30 do
    send(b, { command = "action", data = { id = "m1-" .. i, name = "play_hand",
      data = payloads[(i % 2) + 1] } })
  end
  all_refused("M1: a refusal reworded on every retry is success:false every time", b, 30)
  check("no refusal claims a spent budget",
    not b.results[#b.results].message:find("retry budget", 1, true)
      and not b.results[#b.results].message:find("Nothing was executed", 1, true),
    b.results[#b.results].message)
end

do
  local b = env(710)
  local vectors = {
    { "play_hand", '{"indices":"nope"}' },
    { "buy_from_shop", '{"area":"shop_jokers","index":1}' },
    { "play_hand", '{"indices":[99]}' },
  }
  for i = 1, 30 do
    local v = vectors[(i % 3) + 1]
    send(b, { command = "action", data = { id = "m2-" .. i, name = v[1], data = v[2] } })
  end
  all_refused("M2: rotating the class of the fault is success:false every time", b, 30)
end

do
  local b = env(720)
  local ids = { 42, true, {}, "" }
  for i = 1, 30 do
    send(b, { command = "action", data = { id = ids[(i % 4) + 1], name = "play_hand", data = "{}" } })
  end
  check("M3: invalid non-string ids are dropped before retry accounting",
    #b.results == 0, tostring(#b.results))
end

do
  local b = env(730)
  local names = { "play_hand", "discard_hand", "leave_shop" }
  for i = 1, 30 do
    send(b, { command = "action", data = { id = 42, name = names[(i % 3) + 1], data = "{}" } })
  end
  check("M4: invalid non-string ids are dropped before action-name accounting",
    #b.results == 0, tostring(#b.results))
end

do
  local b = env(740)
  local ids = { 42, true, {}, "" }
  local names = { "play_hand", "discard_hand", "leave_shop" }
  for i = 1, 30 do
    send(b, { command = "action",
      data = { id = ids[(i % 4) + 1], name = names[(i % 3) + 1], data = "{}" } })
  end
  check("M5: invalid non-string ids are dropped before combined retry accounting",
    #b.results == 0, tostring(#b.results))
end

do
  local b = env(750)
  for i = 1, 30 do
    send(b, { command = "action", data = { id = "u-" .. i, name = "definitely_not_an_action", data = "{}" } })
  end
  require("core.action_registry").note_unregistered({ "leave_shop" }, require("core.action_registry").now())
  for i = 1, 10 do
    send(b, { command = "action", data = { id = "w-" .. i, name = "leave_shop", data = "{}" } })
  end
  for i = 1, 10 do
    send(b, { command = "action", data = { id = "n-" .. i, data = "{}" } })
  end
  local wrong = {}
  for _, r in ipairs(b.results) do
    if r.ok ~= false or (r.reason ~= "ACTION_UNKNOWN" and r.reason ~= "ACTION_UNREGISTERED") then
      wrong[#wrong + 1] = tostring(r.id) .. "=" .. tostring(r.ok) .. "/" .. tostring(r.reason)
    end
  end
  check("F3: every unknown, unregistered or nameless action is refused with success=false",
    #b.results == 50 and #wrong == 0, #b.results .. " results; " .. table.concat(wrong, " "))
  b.results = {}
  G.NEURO.llm_paused = true
  send(b, { command = "action", data = { id = "p-1", name = "no_such_action", data = "{}" } })
  G.NEURO.llm_paused = false
  local paused = b.results[1] or {}
  check("F3: an unknown action is refused with success=false even while paused",
    paused.ok == false and paused.reason == "ACTION_UNKNOWN", tostring(paused.ok) .. "/" .. tostring(paused.reason))
end

do
  local b = env(760)
  stuck("held", b)
  for i = 1, 30 do
    send(b, { command = "action", data = { id = "v-" .. i, name = "play_hand",
      data = '{"indices":[1,2]}' } })
  end
  all_refused("F4: a stuck verification is told to wait with success:false every time", b, 30)
  require("core.execute").abort("test")
end

do
  local b = env(770)
  G.NEURO.force_window = nil
  stuck("held2", b)
  send(b, { command = "action", data = { id = "wire-1", name = "play_hand",
    data = '{"indices":[1,2]}' } })
  check("an action arriving during a pending verification is told to wait, not judged",
    b.results[1] and b.results[1].reason == "TRANSITION_PENDING" and b.results[1].ok == false,
    b.results[1] and tostring(b.results[1].reason))
  require("core.execute").abort("test")
end

do
  local b = env(780)
  local payloads = { '{"indices":[97]}', '{"indices":[98]}' }
  for i = 1, 20 do
    send(b, { command = "action", data = { id = "p-" .. i, name = "play_hand",
      data = payloads[(i % 2) + 1] } })
  end
  all_refused("the tenth identical-class refusal and every one after it is still success:false", b, 20)
  for _, name in ipairs({ "play_hand", "record_plan" }) do
    b.results = {}
    Enforce.note_accepted({ name = name })
    G.NEURO.decision_serial = G.NEURO.decision_serial + 1
    send(b, { command = "action", data = { id = "p-next-" .. name, name = "play_hand",
      data = '{"indices":[97]}' } })
    check("an accepted " .. name .. " or a new decision changes nothing: the refusal is success:false",
      b.results[1] and b.results[1].ok == false, b.results[1] and tostring(b.results[1].ok))
  end
end

do
  local b = env(785)
  for i = 1, 12 do
    send(b, { command = "action", data = { id = "c-" .. i, name = "play_hand",
      data = '{"indices":[1,' .. (90 + i) .. ']}' } })
  end
  local last = b.results[#b.results] or {}
  check("changed payloads are all refused with their own reason, never a budget statement",
    last.ok == false and not tostring(last.message):find("refused %d+ times")
      and not tostring(last.message):find("retry budget", 1, true), tostring(last.message))
end

do
  local Validate = require("core.validate")
  check("the validator keeps no decision budget to spend",
    Validate.decision_spent == nil and (Validate._test == nil or Validate._test.note_rejection == nil))
end

done()
