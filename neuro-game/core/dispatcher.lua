local Wire = require("core.bridge").wire
local Actions = require("core.actions")
local Utils = require("util.utils")
local Metrics = require("util.metrics")
local Tx = require("core.bridge").tx
local PlanTransaction = require("core.plan_transaction")
local ActionRegistry = require("core.action_registry")
local ActionResult = require("core.action_result")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local GameFacts = require("facts.game_facts")
local CardUtil = require("facts.card_util")
local DeckFacts = require("facts.deck_facts")
local mock_UIBox = GameActions.mock_UIBox

local ShopHandlers = require("handlers.shop_handlers")
local UseCard = require("handlers.use_card")
local Directional = require("handlers.directional_card")
local MenuHandlers = require("handlers.menu_handlers")
local SeedRunHandlers = require("handlers.seed_run_handlers")
local HandHandlers = require("handlers.hand_handlers")
local BoardHandlers = require("handlers.board_handlers")
local PlanHandlers = require("handlers.plan_handlers")

local Dispatcher = {}

local function persona_display_name(persona)
  return persona == "evil" and "Evil Neuro" or "Neuro-sama"
end

local function apply_persona(persona)
  local display_name = persona_display_name(persona)
  if G and G.NEURO then
    local previous = G.NEURO.persona
    G.NEURO.persona = persona
    local StateKinds = require("core.state_kinds")
    local at_menu = StateKinds.is_menu_state(require("core.state").get_state_name())
    if at_menu and not G.NEURO.login_anim then
      G.NEURO.login_anim = {
        start = Utils.now(),
        name = display_name,
        palette_ready = false,
        from = previous,
      }
    end
  end
  return ActionResult.done()
end

local ACTION_PREFLIGHTS = {
  choose_persona = function(data)
    local persona = data.persona
    if persona ~= "neuro" and persona ~= "evil" then
      return nil, "Choose 'neuro' for Neuro-sama or 'evil' for Evil Neuro."
    end
    if G and G.NEURO and G.NEURO.persona ~= "hiyori" then
      if G.NEURO.persona == persona then
        return function() return ActionResult.done() end
      end
      local cur = persona_display_name(G.NEURO.persona)
      return nil, "Identity already set to " .. cur .. ". Cannot change mid-session."
    end
    return function() return apply_persona(persona) end
  end,
  play_hand = HandHandlers.handle_play_hand,
  discard_hand = HandHandlers.handle_discard_hand,
  resolve_play = HandHandlers.handle_resolve_play,
  use_consumable = UseCard.handle_use_card,
  choose_pack_card = UseCard.handle_use_card,
  use_directional_consumable = Directional.handle,
  choose_directional_pack_card = Directional.handle,
  buy_from_shop = ShopHandlers.handle_buy_from_shop,
  sell_card = ShopHandlers.handle_sell_card,
  select_blind = BoardHandlers.handle_select_blind,
  skip_blind = BoardHandlers.handle_skip_blind,
  set_joker_order = BoardHandlers.handle_set_joker_order,
  record_plan = PlanHandlers.handle_record_plan,
  record_joker_roles = PlanHandlers.handle_record_joker_roles,
  open_run_setup = function()
    return function()
      G.NEURO.deck_chosen = false
      G.NEURO.seed_pasted = nil
      MenuHandlers.open_new_run_setup()
      MenuHandlers.sync_run_select()
      return ActionResult.done()
    end
  end,
  select_stake = MenuHandlers.handle_change_stake,
  select_challenge = MenuHandlers.handle_change_challenge_description,
  select_deck = MenuHandlers.handle_change_selected_back,
  toggle_seeded_run = SeedRunHandlers.handle_toggle_seeded_run,
  paste_seed = SeedRunHandlers.handle_paste_seed,
  start_challenge_run = SeedRunHandlers.handle_start_challenge_run,
}

function Dispatcher.skip_pack_reject_reason()
  if require("core.validate").stop_use_active() then
    return ActionResult.wait("The pack is still resolving the last action, so nothing was applied.")
  end
  return nil
end

local ENGINE_FUNCS = { leave_shop = "toggle_shop", skip_pack = "skip_booster", start_run = "start_setup_run" }

local function handle_simple_action(name)
  local refusal = ActionRegistry.unavailable_reason(name)
  if refusal then return nil, refusal end
  if name == "reroll_shop" and not G.shop then
    return nil, ActionResult.wait("The shop is not open yet, so nothing was applied.",
      "Wait for the shop screen, then choose again.")
  end
  if name == "reroll_boss" and not G.blind_select then
    return nil, ActionResult.wait("The blind select screen is not open yet, so nothing was applied.",
      "Wait for the blind select screen, then choose again.")
  end
  if name == "skip_pack" then
    local reason = Dispatcher.skip_pack_reject_reason()
    if reason then return nil, reason end
  end
  if name == "start_run" then G.SETTINGS.current_setup = 'New Run' end
  if name == "exit_overlay_menu" then
    return function()
      if require("core.state_kinds").is_unlock_popup() then
        G.FUNCS.continue_unlock()
        return ActionResult.done()
      end
      G.FUNCS.exit_overlay_menu()
      return ActionResult.done()
    end
  end
  local gameplay_event
  if name == "reroll_shop" then
    local round = G.GAME.current_round or {}
    local free = (tonumber(round.free_rerolls) or 0) > 0
    gameplay_event = {
      kind = "shop_reroll",
      paid = free and 0 or math.max(0, math.floor(tonumber(round.reroll_cost) or 0)),
      used_free_reroll = free,
    }
  end
  local fn = G.FUNCS[ENGINE_FUNCS[name] or name]
  return function()
    local selected_center, selected_stake, seeded, selected_seed
    if name == "start_run" then
      local key = G and G.NEURO and G.NEURO.selected_back_key
      if key and not MenuHandlers.apply_selected_back(key) then
        error("selected deck is no longer available: " .. tostring(key))
      end
      selected_center = DeckFacts.run_deck_center()
      selected_stake = DeckFacts.run_stake()
      seeded, selected_seed = DeckFacts.run_seed()
    end
    local start_run = name == "start_run" and G.FUNCS.start_run
    if selected_center or selected_stake then
      G.FUNCS.start_run = function(e, args)
        args = args or {}
        args.challenge = nil
        if selected_center then args.deck_choice = selected_center end
        if selected_stake then args.stake, args.stake_choice = selected_stake, selected_stake end
        args.seed = seeded and selected_seed or nil
        return start_run(e, args)
      end
      local ok, result = pcall(fn, { config = {}, UIBox = mock_UIBox })
      G.FUNCS.start_run = start_run
      if not ok then error(result, 0) end
      return nil
    end
    if name == "cash_out" then
      local button = GameFacts.cash_out_button()
      if not button then error("the Cash Out button is gone; the payout was not collected", 0) end
      fn(button)
      return nil
    end
    fn({ config = {}, UIBox = mock_UIBox })
  end, nil, gameplay_event
end
for name, handler in pairs(ACTION_PREFLIGHTS) do
  ActionRegistry.bind_preflight(name, handler)
end
for _, name in ipairs(ActionRegistry.names()) do
  local action_name = name
  local contract = ActionRegistry.get(name)
  if contract and not contract.preflight then
    ActionRegistry.bind_preflight(action_name, function()
      return handle_simple_action(action_name)
    end)
  end
end

ActionRegistry.bind_preflight("copy_seed", function()
  local copy, refusal = handle_simple_action("copy_seed")
  if not copy then return nil, refusal end
  local seed = G.GAME.pseudorandom.seed
  local held = G.CLIPBOARD
  if not G.F_LOCAL_CLIPBOARD then
    local ok, text = pcall(function() return love.system.getClipboardText() end)
    held = ok and text or nil
  end
  if held == seed then return ActionResult.unchanged("Seed " .. seed .. " is already on the clipboard") end
  return copy
end)

ActionRegistry.bind_preflight("leave_shop", function(data)
  local tag, refusal
  if data.intents ~= nil then
    tag, refusal = PlanHandlers.handle_record_joker_roles(data)
    if not tag then return nil, refusal end
  end
  local covered, missing = {}, {}
  for _, entry in ipairs(data.intents or {}) do covered[entry.index] = true end
  for _, index in ipairs(CardUtil.untagged_joker_indices()) do
    if not covered[index] then missing[#missing + 1] = tostring(index) end
  end
  if #missing > 0 then
    return nil, "Every joker needs a role tag before you leave, and these jokers carry none: "
      .. table.concat(missing, ", ") .. ". Nothing happened. Leave again with `intents` giving each of them"
      .. " an index and a tag (CORE, SCALING, HOLD or CHANGE), or record their roles first."
  end
  local leave
  leave, refusal = handle_simple_action("leave_shop")
  if not leave then return nil, refusal end
  if not tag then return leave end
  return function()
    local tagged, failed = tag()
    if not tagged then return nil, failed end
    return leave()
  end
end)

function Dispatcher.preflight(name, data)
  data = data or {}
  if type(data.area) == "string" then data.area = CardArea.AREA_ALIASES[data.area] or data.area end
  return ActionRegistry.preflight(name, data)
end
local function add_candidate(out, name, payload, probe)
  if G and G.NEURO then G.NEURO._candidate_probe = true end
  local ok, exec = pcall(Dispatcher.preflight, name, probe or payload)
  if G and G.NEURO then G.NEURO._candidate_probe = nil end
  if ok and type(exec) == "function" then out[#out + 1] = payload end
end

ActionRegistry.bind_candidates("buy_from_shop", function()
  local out = {}
  for _, area_name in ipairs({ "shop_jokers", "shop_vouchers", "shop_booster" }) do
    local area = G and G[area_name]
    for index, card in ipairs((area and area.cards) or {}) do
      if not CardUtil.is_hidden(card) then
        local before = #out
        local name = Utils.real_name_or(card)
        add_candidate(out, "buy_from_shop", { area = area_name, index = index, name = name })
        if #out == before and card and card.ability and card.ability.consumeable then
          add_candidate(out, "buy_from_shop", { area = area_name, index = index, name = name, use = true })
        end
      end
    end
  end
  return out
end)

ActionRegistry.bind_payload_guard("sell_card", function(data)
  local Legality = require("facts.boss.legality")
  if not Legality.sell_blocked_now() then return true end
  local _, card, index = CardArea.resolve_target(data, CardArea.TARGET_RULES.sell_card)
  if not card or not Legality.sell_blocked_now(card) then return true end
  local reason = Legality.in_round_sell_note()
  return false, ActionResult.error("ACTION_UNAVAILABLE",
    "Mid-round, a card can be sold only when its sale does something this round"
      .. (reason and (": " .. reason) or "") .. ". Sell " .. require("facts.public_card_identity").label(card, data.area, index)
      .. " in the shop instead.")
end)

ActionRegistry.bind_candidates("sell_card", function()
  local out = {}
  for _, area_name in ipairs({ "jokers", "consumables" }) do
    local area = CardArea.get_area(area_name)
    for index, card in ipairs((area and area.cards) or {}) do
      if not CardUtil.is_hidden(card) then
        local payload = { area = area_name, index = index, name = Utils.real_name_or(card) }
        add_candidate(out, "sell_card", payload)
      end
    end
  end
  return out
end)

local function card_candidates(action_name, source_name, source_area)
  local out = {}
  for index, card in ipairs((source_area and source_area.cards) or {}) do
    if not CardUtil.is_hidden(card) and not require("facts.target_contracts").get(card) then
      local payload = { area = source_name, index = index, name = Utils.real_name_or(card) }
      local probe = payload
      local minimum, maximum = CardUtil.consumable_target_range(card)
      if maximum and maximum > 0 and not Utils.is_playing_card(card) then
        local stand_in = {}
        local hand_count = G and G.hand and G.hand.cards and #G.hand.cards or 0
        for hand_index = 1, math.min(minimum or 1, hand_count) do
          stand_in[#stand_in + 1] = hand_index
        end
        probe = { area = source_name, index = index, name = payload.name, hand_indices = stand_in }
      end
      add_candidate(out, action_name, payload, probe)
    end
  end
  return out
end

ActionRegistry.bind_candidates("use_consumable", function()
  return card_candidates("use_consumable", "consumables", G and G.consumeables)
end)
ActionRegistry.bind_candidates("choose_pack_card", function()
  return card_candidates("choose_pack_card", "booster_pack", CardUtil.pack_area())
end)

ActionRegistry.bind_candidates("select_blind", function()
  local key = Actions.get_selectable_blind_key()
  local out = {}
  if key then add_candidate(out, "select_blind", { blind = key:lower() }) end
  return out
end)

local NO_CANDIDATE_REASON = {
  buy_from_shop = "Nothing on offer can be bought right now (money, free slots, or an empty shop); sell, reroll or leave instead.",
  sell_card = "Nothing you own can be sold right now; choose another action.",
  select_blind = function()
    return ActionResult.wait("No blind is selectable yet, so nothing was selected.",
      "Wait for the blind select screen, then choose again.")
  end,
}
for name, reason in pairs(NO_CANDIDATE_REASON) do
  local candidate_name, refusal = name, reason
  ActionRegistry.bind_availability(candidate_name, function(data)
    if #ActionRegistry.candidates(candidate_name) > 0 then return true end
    return false, type(refusal) == "function" and refusal(data) or refusal
  end)
end



local function drop(label)
  Metrics.incr("dispatch_drop_" .. tostring(label))
end

local function handle_transport_reconnect(msg)
  local session = msg.transport_session
  if session == nil or (type(session) ~= "number" and type(session) ~= "string") or session == "" then
    return Metrics.incr("dispatch_reconnect_missing_session")
  end
  local ok, handled = pcall(require("core.bridge_init").handle_transport_reconnect, session)
  Metrics.incr((ok and handled ~= false) and "dispatch_reconnect_handled" or "dispatch_reconnect_handler_failed")
end

local function handle_startup(msg)
  local session = type(msg.data) == "table" and msg.data.session
  if type(session) ~= "table" or type(session.characterId) ~= "string" or session.characterId == "" then
    Metrics.incr("dispatch_startup_ack_invalid")
    return drop("handle_startup_invalid")
  end
  if not (G and G.NEURO) then return end
  if (session.characterId == "neuro" or session.characterId == "evil") and G.NEURO.persona == "hiyori" then
    apply_persona(session.characterId)
    require("core.window").withdraw("persona_from_startup")
  end
end

local function usable_id(data)
  local id = data.id
  if type(id) == "string" and id ~= "" and Wire.valid_action_id(id) then return true end
  Metrics.incr("dispatch_action_missing_id")
  if id ~= nil then Metrics.incr("dispatch_action_invalid_id") end
  if id == nil or id == "" or type(id) ~= "string" then drop("missing_action_id") end
  return false
end

local function dispatch(msg, bridge, staged)
  if type(msg) ~= "table" or type(msg.command) ~= "string" then return drop("no_command") end
  if msg.command == "neuro-bridge/reregister_all" then return handle_transport_reconnect(msg) end
  if msg.command == "startup" then return handle_startup(msg) end
  if msg.command ~= "action" then return drop("non_action") end
  if type(msg.data) ~= "table" then
    Metrics.incr("dispatch_action_malformed_data")
    return drop("malformed_action_data")
  end
  if not usable_id(msg.data) then return end
  local Validate = require("core.validate")
  local ok, err = xpcall(function()
    local job = Validate.validate(msg, bridge)
    if job then require("core.execute").admit(job, staged) end
  end, debug.traceback)
  if not ok then
    Metrics.incr("dispatch_action_throw")
    print("[neuro-game] action handling error: " .. Utils.safe_tostring(err))
    pcall(Validate.crashed, bridge, msg.data.id, msg.data.name)
  end
end

function Dispatcher.route_message(msg, bridge)
  return dispatch(msg, bridge, true)
end

function Dispatcher.handle_message(msg, bridge)
  return dispatch(msg, bridge, false)
end

function Dispatcher.reset_run_state(reason)
  require("core.execute").abort(reason or "run state reset")
  PlanTransaction.release()
end

function Dispatcher.reset_transport_state(reason)
  Dispatcher.reset_run_state(reason or "transport reconnected")
  Tx.reset()
  if G and G.NEURO then
    G.NEURO.pack_exit_pending = nil
    G.NEURO.reserved_dollars = nil
  end
end

function Dispatcher.reset_tx()
  Dispatcher.reset_run_state()
  Tx.reset()
  ActionRegistry.reset()
end

function Dispatcher.get_action_handler(name)
  local contract = ActionRegistry.get(name)
  return contract and contract.preflight or nil
end

return Dispatcher
