require("tests.stubs").setup({ love = "timers", G = "timed" })

local Helpers = require("tests.helpers")
local check, done = Helpers.harness("unmodelled-state-guard")

local Actions = require("core.actions")
local Enforce = require("tests.helpers").enforce()
local State = require("core.state")
local Dispatcher = require("core.dispatcher")
local Router = require("force.force_router")
local TxCache = require("core.bridge").tx
local ActionReceipt = require("core.action_result")

local ENGINE_STATES = require("tests.engine_cards").states()

local MOD_ONLY_STATES = { "RUN_SETUP", "UNKNOWN" }

local EXPECTED_UNMODELLED = {
  "DEMO_CTA", "DRAW_TO_HAND", "HAND_PLAYED", "NEW_ROUND", "PLAY_TAROT",
  "SANDBOX", "SMODS_REDEEM_VOUCHER", "TUTORIAL", "UNKNOWN",
}

-- Steamodded patches every booster open to SMODS_BOOSTER_OPENED; vanilla pack states are unreachable.
local NEVER_ENTERED = { TAROT_PACK = true, PLANET_PACK = true, SPECTRAL_PACK = true,
  STANDARD_PACK = true, BUFFOON_PACK = true }

local function all_state_names()
  local names = {}
  for name in pairs(ENGINE_STATES) do
    if not NEVER_ENTERED[name] then names[#names + 1] = name end
  end
  for _, name in ipairs(MOD_ONLY_STATES) do names[#names + 1] = name end
  table.sort(names)
  return names
end
local MODELLED_STATES = {}
for _, name in ipairs(Actions.get_known_states()) do MODELLED_STATES[name] = true end
for name in pairs(ENGINE_STATES) do
  if require("core.state_kinds").is_pack_state(name) then MODELLED_STATES[name] = true end
end

do
  local unmodelled = {}
  for _, name in ipairs(all_state_names()) do
    if not MODELLED_STATES[name] then unmodelled[#unmodelled + 1] = name end
  end
  check("every state the mod can name is either modelled or one of the nine",
    table.concat(unmodelled, ",") == table.concat(EXPECTED_UNMODELLED, ","),
    table.concat(unmodelled, ","))
end

do
  G.OVERLAY_MENU = nil
  G.STATES = ENGINE_STATES
  for _, name in ipairs(EXPECTED_UNMODELLED) do
    local ok, force = pcall(Router.get_force_for_state, name)
    check("no force is offered on " .. name, ok and force == nil, tostring(ok and force))
  end
  for name in pairs(NEVER_ENTERED) do
    check(name .. " is not read as a pack state", not require("core.state_kinds").is_pack_state(name))
  end
end

local play_card = require("tests.helpers").play_card

local played = 0

local function parked_at(state_name)
  G.TIMERS.REAL = G.TIMERS.REAL + 100
  G.STATES = ENGINE_STATES
  G.STATE = ENGINE_STATES[state_name] or -1
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small", blind_choices = {} },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3), play_card(4), play_card(5) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
    play_cards_from_highlighted = function() played = played + 1 end,
    discard_cards_from_highlighted = function() played = played + 1 end,
  }
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions,
    shop_visit_epoch = 1, state = state_name, state_enter_serial = 1 }
  require("core.validate").reset_run_state()
  Enforce.reset_run_state()
  require("core.window").reset()
  TxCache.reset()
  Helpers.stage_registered("SELECTING_HAND")
  check("the parked screen reads back as " .. state_name, State.get_state_name() == state_name,
    State.get_state_name())
end

local STALE_NAMES = Actions.get_action_names_for_state("SELECTING_HAND")

do
  check("SELECTING_HAND really leaves names behind to be refused", #STALE_NAMES > 1, #STALE_NAMES)
  for _, state_name in ipairs(EXPECTED_UNMODELLED) do
    parked_at(state_name)
    local leaked = {}
    for _, name in ipairs(STALE_NAMES) do
      if name ~= "exit_overlay_menu" then
        local allowed, _, _, code = Enforce.pre_action(nil, name, {})
        if allowed ~= false or code ~= "ACTION_UNAVAILABLE" then
          leaked[#leaked + 1] = name .. "/" .. tostring(code)
        end
      end
    end
    check("every stale action is refused as unavailable on " .. state_name,
      #leaked == 0, table.concat(leaked, ","))
  end
end

do
  for _, state_name in ipairs(EXPECTED_UNMODELLED) do
    parked_at(state_name)
    local before = played
    local log = {}
    local bridge = Helpers.stub_bridge({
      send_action_result = Helpers.result_log(log, { "id", "ok", "message", "code" }),
      send_context = "noop", register_actions = "noop", is_transition_cooldown = "false",
    })
    local id = state_name .. "-stale-1"
    Dispatcher.handle_message({ command = "action",
      data = { id = id, name = "play_hand", data = { card_indices = { 1, 2 } } } }, bridge)
    check("a stale action delivered on " .. state_name .. " is answered exactly once",
      #log == 1 and log[1].id == id, #log .. " result(s)")
    check("and it did not reach the engine on " .. state_name, played == before, played - before)
    check("and no result is left owed on " .. state_name, #TxCache.outstanding(0) == 0,
      #TxCache.outstanding(0))
  end
end

local function internal_tag(text)
  for _, pattern in ipairs({ "RUN|", "FRAME|", "STATE:", "table: 0x" }) do
    if text:find(pattern, 1, true) then return pattern end
  end
  return text:match("%f[%w_]%u+_[%u_]+%f[^%w_]") or text:match("%f[%w]nil%f[^%w]")
end

do
  local Window = require("core.window")
  local FP = require("tests.force_payload")
  -- RUN_SETUP comes from its own overlay, so a parked screen cannot report it.
  local parkable = {}
  for _, state_name in ipairs(all_state_names()) do
    if state_name ~= "RUN_SETUP" then parkable[#parkable + 1] = state_name end
  end
  for _, overlay in ipairs({ false, true }) do
    for _, state_name in ipairs(parkable) do
      parked_at(state_name)
      if overlay then G.OVERLAY_MENU = Helpers.options_overlay() end
      local label = state_name .. (overlay and " under a popup" or "")
      local ok, force = pcall(Router.get_force_for_state, state_name)
      check("the router answers on " .. label, ok, tostring(force))
      if ok and force then
        local ok_p, payload = pcall(Window.build_payload, state_name, force)
        local text = tostring(ok_p and payload or "") .. "\n" .. tostring(force.query)
        check("the force on " .. label .. " is built", ok_p and type(payload) == "string" and payload ~= "",
          tostring(payload))
        check("the force on " .. label .. " carries no internal tag", internal_tag(text) == nil,
          tostring(internal_tag(text)) .. " in:\n" .. text)
      end
    end
  end
  for _, state_name in ipairs(EXPECTED_UNMODELLED) do
    parked_at(state_name)
    G.OVERLAY_MENU = Helpers.options_overlay()
    local ok, wire = pcall(FP.build, state_name)
    local text = ok and wire and (wire.state .. "\n" .. wire.query) or tostring(wire)
    check("the force sent on " .. state_name .. " under a popup is readable on the wire",
      ok and wire ~= nil and internal_tag(text) == nil, tostring(ok and internal_tag(text)) .. " in:\n" .. text)
  end
end

done()
