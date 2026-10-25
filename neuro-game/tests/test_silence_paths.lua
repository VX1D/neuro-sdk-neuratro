require("tests.stubs").setup({ love = "timers" })
local TmpWork = require("tests.tmp_workdir")
local MOD_PATH = TmpWork.open("silence_paths_mod")
require("tests.engine_cards").install_smods({ current_mod = { path = MOD_PATH }, Mods = {},
  findModByID = function() return nil end })

local check, done = require("tests.helpers").harness("silence-paths")

local Router = require("force.force_router")
local Guard = require("core.validate")
local Tuning = require("core.config")
local FAILSAFE = Tuning.get("NEURO_ROUTER_DEFER_FAILSAFE")

local PACK_STATES = require("tests.engine_cards").states()

local tarot = require("tests.fake_cards").bare_tarot

local function pack_board()
  _G.G = {
    P_CENTERS = require("tests.engine_centers").centers(),
    STATE = PACK_STATES.SMODS_BOOSTER_OPENED, STATES = PACK_STATES, STATE_COMPLETE = true,
    TIMERS = { REAL = 1000 }, SETTINGS = { GAMESPEED = 1 },
    GAME = { dollars = 20, round = 11, chips = 0, STOP_USE = 0, last_tarot_planet = "c_pluto",
      current_round = { hands_left = 4, discards_left = 3, reroll_cost = 5 },
      round_resets = { ante = 4, blind_choices = {}, blind_states = {} },
      blind = { name = "Big Blind" }, used_vouchers = {}, modifiers = {},
      hands = { Pair = { level = 1, chips = 10, mult = 2, visible = true } }, pack_choices = 2 },
    P_BLINDS = {},
    NEURO = { run_generation = 1, once_serials = {}, decision_serial = 1,
      state_enter_serial = 1, plan = {}, reserved_dollars = 0 },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    hand = { cards = {}, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} },
    pack_cards = { cards = { tarot() }, config = {} },
    booster_pack = {},
    FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
      skip_booster = function() end, use_card = function() end },
    CONTROLLER = { locks = {} },
  }
  Guard.reset_run_state()
  Router._guard_defer_at = nil
  Router._guard_defer_state = nil
  Router._guard_defer_generation = nil
  Router._pack_exit_at = nil
  Router._pack_exit_generation = nil
end

local function shape(state)
  local force = Router.get_force_for_state(state)
  if not force then return nil end
  return table.concat(force.actions, ",")
end

do
  pack_board()
  local full = shape("SMODS_BOOSTER_OPENED")
  check("fixture: an unblocked pack offers the two actions that leave it",
    full == "choose_pack_card,skip_pack", tostring(full))

  G.GAME.STOP_USE = 1
  check("the settling pack defers first", shape("SMODS_BOOSTER_OPENED") == nil)
  G.TIMERS.REAL = 1000 + FAILSAFE - 0.5
  check("and holds the defer until the failsafe elapses", shape("SMODS_BOOSTER_OPENED") == nil)

  G.TIMERS.REAL = 1000 + FAILSAFE + 0.5
  local released = shape("SMODS_BOOSTER_OPENED")
  check("past the failsafe the force carries a real way out of the pack",
    released ~= nil and released:find("choose_pack_card", 1, true) ~= nil
      and released:find("skip_pack", 1, true) ~= nil, tostring(released))

  local shapes, order = {}, {}
  local silent = 0
  for step = 0, 600 do
    G.TIMERS.REAL = 1000 + FAILSAFE + 0.5 + step
    local sig = shape("SMODS_BOOSTER_OPENED")
    if sig then shapes[sig] = true; order[#order + 1] = sig else silent = silent + 1 end
  end
  local distinct = 0
  for _ in pairs(shapes) do distinct = distinct + 1 end
  check("ten more minutes with the flag stuck never go silent again", silent == 0, silent)
  check("and never alternate -- one force shape, so the arming loop has nothing to churn",
    distinct == 1 and order[1] == released, distinct .. " shapes")
end

do
  pack_board()
  G.NEURO.pack_exit_pending = true
  check("the optimistic pack exit suppresses the follow-up force",
    shape("SMODS_BOOSTER_OPENED") == nil)
  G.TIMERS.REAL = 1000 + FAILSAFE - 0.5
  check("the suppression holds while the exit is plausible", shape("SMODS_BOOSTER_OPENED") == nil)

  G.TIMERS.REAL = 1000 + FAILSAFE + 0.5
  local back = shape("SMODS_BOOSTER_OPENED")
  check("an engine that never left the pack gets asked again",
    back == "choose_pack_card,skip_pack", tostring(back))
  check("and the stale flag is dropped, so the next pack starts clean",
    G.NEURO.pack_exit_pending == nil, tostring(G.NEURO.pack_exit_pending))

  local silent = 0
  for step = 1, 120 do
    G.TIMERS.REAL = 1000 + FAILSAFE + 0.5 + step
    if not shape("SMODS_BOOSTER_OPENED") then silent = silent + 1 end
  end
  check("no relapse into silence", silent == 0, silent)
end

do
  pack_board()
  local sent = {}
  G.NEURO.send_context = function(_, text, silent, receipt)
    if receipt then receipt.status = "written" end
    sent[#sent + 1] = { text = text, silent = silent }
    return true
  end
  G.NEURO.pack_exit_pending = true
  G.booster_pack = nil
  check("a missing pack alias still suppresses the live pack", shape("SMODS_BOOSTER_OPENED") == nil)
  G.pack_cards = nil
  G.TIMERS.REAL = 1000 + FAILSAFE + 0.5
  check("both destroyed pack aliases do not advertise impossible actions",
    shape("SMODS_BOOSTER_OPENED") == nil, tostring(shape("SMODS_BOOSTER_OPENED")))
  check("the overdue transition is diagnosed and its stale optimistic gate is released",
    G.NEURO.pack_exit_pending == nil and G.NEURO.pack_transition_stalled ~= nil,
    tostring(G.NEURO.pack_exit_pending))
  require("core.context_delivery").step()
  local notice
  for _, frame in ipairs(sent) do
    if frame.text:find("Engine transition stalled", 1, true) then notice = frame end
  end
  check("the stall notice reaches her context without prompting her to respond",
    notice ~= nil and notice.silent == true, notice and tostring(notice.silent) or "not sent")

  G.STATE = PACK_STATES.SHOP
  G.shop = {}
  check("the state handing back releases the suppression",
    Router.get_force_for_state("SHOP") ~= nil)
end

local STATES = require("tests.engine_cards").states()
local CLOCK = 5000
local forces, results = {}, {}

local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Win = require("core.window")
local Window = { REGISTERED = "registered", FORCED = "forced", ENDED = "ended" }
local Helpers = require("tests.helpers")
require("core.orchestrator")

local play_card = require("tests.helpers").play_card

local function bridge_stub()
  local stub = Helpers.stub_bridge({
    send_action_result = Helpers.result_log(results, { "id", "ok", "message", "code" }),
    send_context = "written", register_actions = "noop", is_transition_cooldown = "false",
  })
  if G and G.NEURO then
    G.NEURO.is_transition_cooldown = function() return stub.is_transition_cooldown() end
  end
  return stub
end

local function board(state_name)
  Helpers.orch_board({ state = state_name, clock = CLOCK, states = STATES })
  for i = 1, 5 do G.hand.cards[i] = play_card(i) end

  forces, results = {}, {}
  G.NEURO = Helpers.orch_neuro({
    transport_session = "silence-test", _bridge_init_complete = true, _startup_complete = true,
    dispatcher = Dispatcher, actions = Actions, state = state_name, send_context = "written",
    send_startup = "true", register_actions = "noop",
  })
  function G.NEURO:force_actions(_ctx, _query, actions)
    forces[#forces + 1] = { t = G.TIMERS.REAL, actions = table.concat(actions, ",") }
  end
  Win.reset()
  require("core.validate").reset_run_state()
  require("core.bridge").tx.reset()
  Dispatcher.reset_tx()
end

local T = require("tests.helpers").orch_ticker(function() return CLOCK end, function(t) CLOCK = t end)
local tick_for = T.tick_for

local answer_n = 0
local function frame(name, payload)
  answer_n = answer_n + 1
  Helpers.stage_registered(nil, { name })
  return Helpers.inbound_action(name, "sil-" .. answer_n, payload)
end

local function answer(bridge, name, payload)
  Dispatcher.handle_message(frame(name, payload), bridge)
  return results[#results]
end

local function phase() return require("tests.helpers").force_phase() end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  Dispatcher.handle_message({ command = "neuro-bridge/reregister_all", transport_session = 1 }, b)
  tick_for(10)
  check("fixture: the game asked its first question",
    #forces == 1 and phase() == Window.FORCED, #forces .. "/" .. phase())
  check("fixture: and the mod remembered the transport stamp it has already seen",
    tostring(G.NEURO.transport_session) == "1", tostring(G.NEURO.transport_session))
  local before = #forces

  Dispatcher.handle_message({ command = "neuro-bridge/reregister_all", transport_session = 1 }, b)
  check("a reconnect that repeats its completed stamp preserves the live offer",
    phase() == Window.FORCED, phase())

  tick_for(120)
  check("the repeated stamp does not create a second force",
    #forces == before, #forces .. " forces after " .. before)
  local settled = #forces
  local stale_window = G.NEURO.force_window

  tick_for(Win.liveness_timeout(nil) + 5)
  check("the timed-out offer is withdrawn and asked again once, without a reconnect storm",
    stale_window.phase == Window.ENDED and phase() == Window.FORCED and #forces == settled + 1,
    tostring(#forces) .. " forces after " .. settled .. "/" .. tostring(stale_window.phase))
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  Dispatcher.handle_message({ command = "neuro-bridge/reregister_all", transport_session = 1 }, b)
  tick_for(10)
  local before = #forces
  for _ = 1, 5 do
    Dispatcher.handle_message({ command = "neuro-bridge/reregister_all" }, b)
  end
  check("a stamp-less request from the server never touches a live offer",
    phase() == Window.FORCED, phase())
  tick_for(30)
  check("and asks nothing new", #forces == before, #forces)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  local before = #forces
  b.is_transition_cooldown = function() return true end

  local hits, first = 0, nil
  for _ = 1, 12 do
    local r = answer(b, "play_hand", '{"indices":[1,2]}')
    first = first or r
    if r and r.code == "TRANSITION_PENDING" then hits = hits + 1 end
    tick_for(2)
  end
  check("every one of the twelve answers really hit the transition gate", hits == 12, hits)
  check("the answer to the open force is terminal", first and first.ok == true)
  local asked = #forces - before
  check("twelve answers during a transition buy no replacement force", asked == 0, asked)

  b.is_transition_cooldown = function() return false end
  local parked = #forces
  tick_for(5)
  check("once the game settles the parked offer is re-asked, so this never becomes a dead end",
    #forces == parked + 1, #forces .. " forces after " .. parked)
end

do
  board("SELECTING_HAND")
  local b = bridge_stub()
  tick_for(10)
  b.is_transition_cooldown = function() return true end
  local offer, withdrawn = table.concat(G.NEURO.force_window.names, ","), nil
  b.withdraw_actions = function(_, names) withdrawn = table.concat(names, ",") return true end
  local r = answer(b, "play_hand", '{"indices":[1,2]}')
  check("a single transition answer is a terminal acknowledgement, not a promised follow-up",
    r.ok == true and r.code == "TRANSITION_PENDING", tostring(r.code))
  check("which ends the offer as answered", phase() == Window.ENDED
    and G.NEURO.force_window.ended_by == "answered", phase())
  check("and unregisters its whole offer before the result, as ActionWindowResponse.cs:20 ends the window",
    withdrawn == offer, tostring(withdrawn) .. " vs " .. offer)
end
TmpWork.close()
done()
