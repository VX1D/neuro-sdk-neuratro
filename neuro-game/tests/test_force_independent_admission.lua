require("tests.stubs").setup({ love = "lazy" })
_G.G = require("tests.helpers").base_G()

local check, done = require("tests.helpers").harness("force-independent-admission")
local H = require("tests.helpers")
local V = require("tests.fixtures.vanilla_jokers")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Registry = require("core.action_registry")
local TxCache = require("core.bridge").tx

local function neuro(state)
  G.NEURO = H.started_bridge({ state = state, state_enter_serial = 1, decision_serial = 1, run_generation = 1,
    enabled = true, persona = "neuro", dispatcher = Dispatcher, actions = Actions, shop_visit_epoch = 1,
    register_actions = H.noop, send_context = H.yes, is_transition_cooldown = H.no })
end

local n = 0
local function send(name, payload)
  n = n + 1
  local id = "fi-" .. n
  local b = H.fake_bridge({ reason = "reason_code" })
  require("core.validate").reset_run_state()
  assert(TxCache.open(id, name, G.TIMERS.REAL))
  Dispatcher.handle_message({ command = "action", data = { id = id, name = name, data = payload } }, b)
  return b.results[#b.results] or {}
end

do
  H.selecting_hand_env({ reset_tx_cache = true, time = 100 })
  neuro("SELECTING_HAND")
  G.GAME.current_round.discards_left = 0
  H.stage_registered("SELECTING_HAND", { "discard_hand" })
  local ok, message, _, code = H.pre_action("discard_hand", { indices = { 1 } })
  H.open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  local forced_ok, forced_message, _, forced_code = H.pre_action("discard_hand", { indices = { 1 } })
  G.NEURO.force_window = nil
  check("unforced discard_hand with no discards left is refused as unavailable",
    ok == false and code == "ACTION_UNAVAILABLE", tostring(code) .. " " .. tostring(message))
  check("the forced one gets the same refusal",
    forced_ok == ok and forced_code == code and forced_message == message,
    tostring(forced_code) .. " " .. tostring(forced_message))
end

do
  H.selecting_hand_env({ reset_tx_cache = true, time = 120 })
  neuro("SELECTING_HAND")
  H.stage_registered("SELECTING_HAND", { "play_hand", "discard_hand" })
  local Validate = require("core.validate")
  Validate.note_accepted({ name = "discard_hand", forced = false })
  local ok, message, _, code = H.pre_action("discard_hand", { indices = { 1 } })
  Validate.note_accepted({ name = "discard_hand", forced = false })
  H.open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  local forced_ok, _, _, forced_code = H.pre_action("discard_hand", { indices = { 1 } })
  G.NEURO.force_window = nil
  check("an unforced discard right after another is admitted like the forced one",
    ok == forced_ok and code == forced_code, tostring(code) .. " " .. tostring(message) .. " vs " .. tostring(forced_code))
end

do
  H.selecting_hand_env({ reset_tx_cache = true, time = 150 })
  neuro("SELECTING_HAND")
  G.GAME.blind = G.GAME.blind or {}
  G.GAME.blind.block_play = true
  H.stage_registered("SELECTING_HAND", { "play_hand" })
  local _, message, _, code = H.pre_action("play_hand", { indices = { 1 } })
  H.open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  local _, _, _, forced_code = H.pre_action("play_hand", { indices = { 1 } })
  G.NEURO.force_window = nil
  G.GAME.blind.block_play = nil
  check("unforced play_hand under a boss banner waits", code == "TRANSITION_PENDING", tostring(code) .. " " .. tostring(message))
  check("the forced one gets the same verdict", forced_code == code, tostring(forced_code))
end

do
  H.selecting_hand_env({ reset_tx_cache = true, time = 200 })
  neuro("SELECTING_HAND")
  Registry.reset()
  H.stage_registered(nil, { "play_hand", "discard_hand", "buy_from_shop" })
  local free = send("frobnicate", "{}")
  check("outside a force the unknown name gets exactly the reference SDK text, with no action list",
    free.ok == false and free.reason_code == "ACTION_UNKNOWN"
      and free.message == "Action failed. Unknown action 'frobnicate'.",
    tostring(free.message))
  H.open_force("SELECTING_HAND", { "discard_hand" })
  local forced = send("frobnicate", "{}")
  G.NEURO.force_window = nil
  check("during a force it is the same text: the force's offer is not listed either",
    forced.ok == false and forced.reason_code == "ACTION_UNKNOWN"
      and forced.message == "Action failed. Unknown action 'frobnicate'.",
    tostring(forced.message))
end

do
  H.shop_env()
  neuro("SHOP")
  H.stage_registered("SHOP", { "record_plan" })
  local r = send("record_plan", [[{"plan":{"hand_plan":"Play the flush"}}]])
  check("a nested record_plan is saved", r.ok == true and G.NEURO.plan and G.NEURO.plan.hand == "Play the flush",
    tostring(r.message) .. " / " .. tostring(G.NEURO.plan and G.NEURO.plan.hand))
end

do
  H.shop_env()
  neuro("SHOP")
  local function board(eternal)
    local hid = V.card_played("j_luchador", 501)
    hid.sell_cost, hid.facing = 5, "back"
    if eternal then hid.ability.eternal = true end
    local lu = V.card_played("j_luchador", 503)
    lu.sell_cost, lu.facing = 5, "front"
    G.jokers = { cards = { hid, lu }, config = { card_limit = 5 } }
    hid.area, lu.area = G.jokers, G.jokers
  end
  H.stage_registered("SHOP", { "sell_card" })
  local plan = [[{"area":"jokers","index":1,"plan":{"build_plan":"keep scaling the flush build","money_plan":"hold interest at 25 dollars"}}]]

  board(true)
  local eternal = send("sell_card", plan)
  check("the Eternal refusal names the face-down joker by its public label",
    eternal.ok == false and tostring(eternal.message):find("Cannot sell face-down item #1 in jokers", 1, true) ~= nil
      and tostring(eternal.message):find("Luchador", 1, true) == nil, tostring(eternal.message))

  require("core.gate").reset()
  board(false)
  local review = send("sell_card", plan)
  local target = require("handlers.shop_handlers").pending_sell_card_name()
  check("the sell review opens", review.reason_code == "CONFIRMATION_REQUIRED", tostring(review.reason_code))
  check("its target, quoted in the next force, is the public label",
    target == "face-down item #1 in jokers", tostring(target))
  require("core.gate").reset()
end

done()
