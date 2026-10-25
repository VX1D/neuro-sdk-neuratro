require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("force-window-outside-offer")

local STATES = require("tests.engine_cards").states()

local CLOCK = 1000

local forces, registered = {}, {}
local results = {}

local play_card = require("tests.helpers").play_card

local function bridge_stub()
  return require("tests.helpers").stub_bridge({
    send_action_result = require("tests.helpers").result_log(results, { "id", "ok", "message", "code" }),
    send_context = "written", register_actions = "noop", is_transition_cooldown = "false",
  })
end

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Window = { REGISTERED = "registered", FORCED = "forced", ENDED = "ended" }
local withdrawn = {}
local TxCache = require("core.bridge").tx
local Helpers = require("tests.helpers")

local function board(state_name)
  Helpers.orch_board({ state = state_name, clock = CLOCK, states = STATES, edit = function(g)
    g.hand = Helpers.card_area(g.hand)
    g.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil end
    g.FUNCS.discard_cards_from_highlighted = function()
      local selected, kept = {}, {}
      for _, card in ipairs(G.hand.highlighted or {}) do selected[card] = true end
      for _, card in ipairs(G.hand.cards or {}) do
        if not selected[card] then kept[#kept + 1] = card end
      end
      G.hand.cards = kept
      G.hand.highlighted = {}
      G.GAME.current_round.discards_left =
        (G.GAME.current_round.discards_left or 0) - 1
    end
  end })
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end
  G.NEURO = Helpers.orch_neuro({
    transport_epoch = 1, transport_session = "outside-offer-session",
    dispatcher = Dispatcher, actions = Actions, state = state_name, send_context = "written",
    register_actions = function(_, defs)
      for _, d in ipairs(defs or {}) do registered[#registered + 1] = d.name or d end
      return true
    end,
    withdraw_actions = function(self, names)
      withdrawn[#withdrawn + 1] = names
      for _, name in ipairs(names) do self._registered_sigs[name] = nil end
      return true
    end,
  })
  withdrawn = {}
  function G.NEURO:force_actions(ctx, query, actions)
    forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ","), state = ctx or "", query = query or "" }
    return true
  end
  require("core.validate").reset_run_state()
  require("core.bridge").tx.reset()
end

require("core.orchestrator")

local T = require("tests.helpers").orch_ticker(function() return CLOCK end, function(t) CLOCK = t end)
local tick_for, tick_until = T.tick_for, T.poll_until


local answer_n = 0
local function answer_now(bridge, name, payload)
  answer_n = answer_n + 1
  local id = "oo-" .. answer_n
  Helpers.stage_registered(nil, { name })
  TxCache.open(id, name, G.TIMERS.REAL)
  Dispatcher.handle_message(Helpers.inbound_action(name, id, payload), bridge)
  return results[#results]
end

local function answer(bridge, name, payload)
  answer_now(bridge, name, payload)
  tick_for(0.1)
  return results[#results]
end


local function phase() return require("tests.helpers").force_phase() end
local function in_flight() return require("core.window").current() ~= nil end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  check("P: one force stands", #forces == 1 and phase() == Window.FORCED, phase())
  check("P: and exit_overlay_menu is not in it",
    forces[1] and forces[1].actions:find("exit_overlay_menu", 1, true) == nil,
    forces[1] and forces[1].actions)

  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  local r = answer(b, "exit_overlay_menu", "{}")
  check("P: the out-of-offer answer is admitted", r and r.ok == true
      and r.code == "ACTION_ACCEPTED",
    r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("P: the accepted outside answer leaves the sent offer pending and registered",
    phase() == Window.FORCED and in_flight() and #withdrawn == 0, phase())
  check("P: the decision was not made, so its serial does not move",
    G.NEURO.decision_serial == 1, tostring(G.NEURO.decision_serial))
  local before = #forces
  tick_for(30)
  check("P: no second force lands on the pending one", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local Staging = require("core.staging")
  local armable = require("core.window")._test.armable
  local real_busy = Staging.is_busy
  Staging.is_busy = function() return true end
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  check("O: a closable popup is offered even while an action is staged", armable("SELECTING_HAND") == true)
  G.OVERLAY_MENU = nil
  check("O: without the popup the staged action holds the offer back", armable("SELECTING_HAND") == false)
  Staging.is_busy = real_busy
end

-- Neuro retries a refused answer against the same force, so refusal must leave its offer unchanged.
do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local before = #forces
  local r = answer(b, "exit_overlay_menu", "{}")
  check("R: with no popup open the out-of-offer answer is refused",
    r and r.ok == false, r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("R: the offer stays standing and in flight", phase() == Window.FORCED and in_flight(), phase())
  tick_for(30)
  check("R: so no second force is sent on top of the live one", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  for _ = 1, 3 do answer(b, "play_hand", '{"indices":[1,2,99]}') end
  local terminal = answer_now(b, "play_hand", '{"indices":[1,2,99]}')
  check("N: the spent retry budget answers terminally, which resolves the force on the server",
    terminal and terminal.ok == true and phase() == Window.ENDED and #withdrawn == 0, phase())

  local before, serial_before = #forces, G.NEURO.decision_serial
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  local r = answer_now(b, "exit_overlay_menu", "{}")
  check("N: the out-of-offer answer is admitted", r and r.ok == true
      and r.code == "ACTION_ACCEPTED",
    r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("N: with no window open nothing is withdrawn", not in_flight() and #withdrawn == 0, phase())
  check("N: without spending the decision it never answered",
    G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
  check("N: a replacement force follows",
    tick_until(function() return #forces > before end, 30)
      and #forces == before + 1 and phase() == Window.FORCED,
    tostring(#forces) .. "/" .. phase())
end

do
  board("SELECTING_HAND")
  G.jokers.cards = {
    { sort_id = 901, ability = { set = "Joker", name = "A" }, sell_cost = 1,
      config = { center = { key = "j_a", set = "Joker" } } },
    { sort_id = 902, ability = { set = "Joker", name = "B" }, sell_cost = 1,
      config = { center = { key = "j_b", set = "Joker" } } },
  }
  local b = bridge_stub()
  tick_for(10)
  check("M: set_joker_order is valid here",
    Actions.is_action_valid("set_joker_order") == true)
  check("M: set_joker_order is outside the offer",
    forces[1] and forces[1].actions:find("set_joker_order", 1, true) == nil,
    forces[1] and forces[1].actions)
  local before = #forces
  local r = answer(b, "set_joker_order", '{"from_index":1,"to_index":2}')
  check("M: the outside action is admitted without answering the force",
    r and r.ok == true and r.code == "ACTION_ACCEPTED",
    r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  check("M: the sent offer stays pending after the outside answer",
    phase() == Window.FORCED and in_flight() and #withdrawn == 0, phase())
  check("M: the outside action stays outside the decision",
    G.NEURO.decision_serial == 1, tostring(G.NEURO.decision_serial))
  tick_for(30)
  check("M: no replacement force lands on the pending one", #forces == before, #forces)
  local r2 = answer(b, "discard_hand", '{"indices":[1,2]}')
  check("M: her answer from the offer then resolves the force",
    r2 and r2.ok == true and phase() == Window.ENDED and #withdrawn == 0, phase())
  check("M: and only then is the next decision asked",
    tick_until(function() return #forces > before end, 30) and #forces == before + 1,
    tostring(#forces) .. "/" .. phase())
end

do
  forces, results = {}, {}
  board("SHOP")
  G.shop = {}
  G.jokers.cards = { { sort_id = 911, ability = { set = "Joker", name = "A" }, sell_cost = 1,
    config = { center = { key = "j_a", set = "Joker" } } } }
  local b = bridge_stub()
  tick_for(10)
  local w = require("core.window").current()
  check("S: one shop force stands", #forces == 1 and phase() == Window.FORCED and w ~= nil, phase())
  local offered = w and w.names or {}
  check("S: the shop offer carries its decision and the reusable actions beside it (force_router.offer)",
    forces[1] and forces[1].actions:find("leave_shop", 1, true) ~= nil
      and forces[1].actions:find("sell_card", 1, true) ~= nil
      and forces[1].actions:find("record_plan", 1, true) ~= nil, forces[1] and forces[1].actions)
  check("S: exit_overlay_menu is outside it",
    forces[1] and forces[1].actions:find("exit_overlay_menu", 1, true) == nil)
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  local id = "oo-" .. (answer_n + 1)
  local r = answer(b, "exit_overlay_menu", "{}")
  check("S: the outside action is accepted", r and r.ok == true and r.code == "ACTION_ACCEPTED",
    r and (tostring(r.code) .. "/" .. tostring(r.ok)))
  tick_for(30)
  local missing = {}
  for _, name in ipairs(offered) do
    if not G.NEURO._registered_sigs[name] then missing[#missing + 1] = name end
  end
  check("S: nothing is withdrawn and every offered shop action stays registered",
    #withdrawn == 0 and #missing == 0, table.concat(missing, ","))
  check("S: the same force stays pending and no second force is sent",
    #forces == 1 and phase() == Window.FORCED and require("core.window").current() == w, #forces)
  local per_id = 0
  for _, result in ipairs(results) do
    if result.id == id then per_id = per_id + 1 end
  end
  check("S: exactly one result for the outside action's id", per_id == 1, per_id)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local serial_before = G.NEURO.decision_serial
  local r = answer(b, "discard_hand", '{"indices":[1,2]}')
  tick_for(0.1)
  check("I: an in-offer answer is accepted", r and r.ok == true, r and tostring(r.ok))
  check("I: it ends the window", phase() == Window.ENDED, phase())
  check("I: applying the offered action leaves the decision serial stable",
    G.NEURO.decision_serial == serial_before, tostring(G.NEURO.decision_serial))
end

done()
