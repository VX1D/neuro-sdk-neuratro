require("tests.stubs").setup({ love = "lazy" })
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), GAME = { current_round = {} }, hand = { cards = {} }, FUNCS = {},
  NEURO = { withdraw_actions = function() return true end } }

local check, done = require("tests.helpers").harness("sdk-compliance")

local Bridge = require("core.bridge")
local Actions = require("core.actions")

local function capture_bridge()
  local b = Bridge:new({ game = "Balatro", enabled = true })
  b.sent = {}
  b.send = function(self, message) self.sent[#self.sent + 1] = message end
  b.write_file = function() return true end
  return b
end

local function with_menu_overlay(fn)
  local old_states, old_state = G.STATES, G.STATE
  require("tests.helpers").in_engine_state("MENU")
  local old_overlay = G.OVERLAY_MENU
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  fn(require("core.validate").reset_run_state)
  G.OVERLAY_MENU = old_overlay
  G.STATES, G.STATE = old_states, old_state
  require("core.validate").reset_run_state()
end

do
  local D = require("core.dispatcher")
  require("core.bridge").tx.reset()
  G.NEURO.llm_paused = true
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  require("core.action_registry").note_registered({ "play_hand" })
  local results = {}
  local b = capture_bridge()
  b.send_action_result = require("tests.helpers").result_log(results, { "id", "success", "message", "reason" }, true)
  D.route_message({ command = "action",
    data = { id = "pause-forced-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("a paused answer to the active force is acknowledged with no mutation",
    results[1] and results[1].success == true,
    results[1] and tostring(results[1].success) .. "/" .. tostring(results[1].message))
  check("the local force closes after the paused answer, so a fresh force can be asked",
    require("core.window").current() == nil)
  G.NEURO.llm_paused = nil
  G.NEURO.force_window = nil
end

local function all_action_defs()
  return Actions.get_static_actions()
end

do
  local semantic_terms = {
    use_consumable = { "area", "index", "hand_indices" },
    use_directional_consumable = { "area", "left_index", "right_index" },
    choose_pack_card = { "area", "index", "displayed name" },
    choose_directional_pack_card = { "area", "left_index", "right_index" },
    buy_from_shop = { "area", "index", "use" },
    sell_card = { "area", "index", "name" },
    play_hand = { "indices", "confirmation" },
    resolve_play = { "answer" },
    discard_hand = { "indices", "discard" },
    record_plan = { "hand_plan", "build_plan", "money_plan" },
  }
  local checked = 0
  for _, def in ipairs(all_action_defs()) do
    local terms = semantic_terms[def.name]
    if terms then
      checked = checked + 1
      local description = tostring(def.description or "")
      check("concise action contract: " .. def.name .. " stays readable",
        #description > 0 and #description <= 1400, tostring(#description))
    end
  end
  check("concise action contract: representative actions were exercised", checked >= 10, checked)
end

do
  local TmpWork = require("tests.tmp_workdir")
  local dir = TmpWork.open("sdk_compliance_wire")
  local b = Bridge:new({ game = "Balatro", enabled = true, fs_dir = dir })
  b:send_startup()
  b:send_context("real bridge repeated context", true)
  b:send_context("real bridge repeated context", true)
  b:register_actions({ { name = "wire_probe", description = "probe", schema = { type = "object" } } })
  local frames = require("tests.helpers").outbox_frames(dir .. "/" .. b.outbox_file, { must = true })
  local context_count, register_count = 0, 0
  for _, msg in ipairs(frames) do
    if msg.command == "context" and msg.data and msg.data.message == "real bridge repeated context" then
      context_count = context_count + 1
    elseif msg.command == "actions/register" then
      register_count = register_count + 1
    end
  end
  check("real bridge/temp-outbox: repeated context calls are durable", context_count == 2, context_count)
  check("real bridge/temp-outbox: registration reaches the durable outbox", register_count == 1, register_count)
  TmpWork.close()
end

do
  local frames = {}
  local bridge = Bridge:new({ enabled = true })
  function bridge:send(message)
    frames[#frames + 1] = message
    return true
  end

  bridge:send_context("same automatic context", true)
  bridge:send_context("same automatic context", true)
  check("every context call produces a frame, repeats included", #frames == 2, #frames)

  bridge:send_context("requested information", true)
  bridge:send_context("requested information", true)
  check("a repeated context is delivered on every call",
    #frames == 4
      and frames[3].data.message == "requested information"
      and frames[4].data.message == "requested information", #frames)
end

do
  local b = capture_bridge()
  local defs = {
    { name = "use_consumable", description = "d", schema = { type = "object" } },
    { name = "skip_pack", description = "d", schema = { type = "object" } },
  }
  b:register_actions(defs)
  local before = #b.sent
  b:withdraw_actions({ "use_consumable", "skip_pack", "never_registered" })
  local unreg = b.sent[#b.sent]
  check("unregister sent", unreg and unreg.command == "actions/unregister")
  check("only registered names included", unreg and #unreg.data.action_names == 2,
    unreg and table.concat(unreg.data.action_names, ","))
  check("unregistering nothing sends nothing",
    (function() b:withdraw_actions({ "ghost" }); return #b.sent end)() == before + 1)
  b:register_actions(defs)
  local rereg = b.sent[#b.sent]
  check("same defs re-register after unregister (dedupe key invalidated)",
    rereg and rereg.command == "actions/register")
end

do
  local D = require("core.dispatcher")
  G.NEURO.llm_paused = true
  G.NEURO.force_window = nil
  require("tests.helpers").open_force("MENU", { "exit_overlay_menu" })
  require("core.action_registry").note_registered({ "play_hand" })
  local results = {}
  local b = capture_bridge()
  b.send_action_result = require("tests.helpers").result_log(results, { "id", "success", "message" })
  b.replay_action_result = b.send_action_result
  D.route_message({ command = "action",
    data = { id = "pause-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("exactly one result", #results == 1, #results)
  check("paused result is acknowledged success with no mutation",
    results[1] and results[1].success == true, results[1] and tostring(results[1].success))
  check("paused action outside the force leaves that force pending",
    require("core.window").current() ~= nil)
  D.route_message({ command = "action",
    data = { id = "pause-1", name = "play_hand", data = '{"indices":[1,2]}' } }, b)
  check("same-session redelivery of paused id is suppressed",
    #results == 1,
    #results >= 2 and tostring(results[2].message) or ("#results=" .. #results))
  G.NEURO.llm_paused = nil
  G.NEURO.force_window = nil
end
do
  local D = require("core.dispatcher")
  local old_states, old_state = G.STATES, G.STATE
  G.STATES = require("tests.engine_cards").states()
  require("tests.helpers").stage_registered(nil, { "exit_overlay_menu" })
  local old_overlay = G.OVERLAY_MENU
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  local function sending_bridge()
    local b = capture_bridge()
    b.send = function(self, message) self.sent[#self.sent + 1] = message return true end
    b.is_transition_cooldown = function() return false end
    return b
  end

  local function arm_foreign_force(state)
    G.STATE = G.STATES[state]
    G.NEURO.state = state
    G.NEURO.force_window = nil
    require("tests.helpers").open_force(state, { "play_hand" })
  end

  arm_foreign_force("MENU")
  D.handle_message({
    command = "action",
    data = { id = "foreign-setup", name = "exit_overlay_menu", data = "{}" },
  }, sending_bridge())
  check("an accepted foreign setup action leaves the force pending",
    require("core.window").current() ~= nil and G.NEURO.force_window.ended_by == nil,
    tostring(G.NEURO.force_window and G.NEURO.force_window.ended_by))

  arm_foreign_force("SHOP")
  G.OVERLAY_MENU = require("tests.helpers").options_overlay()
  D.handle_message({
    command = "action",
    data = { id = "foreign-general", name = "exit_overlay_menu", data = "{}" },
  }, sending_bridge())
  check("an accepted foreign in-run action leaves the force pending",
    require("core.window").current() ~= nil and G.NEURO.force_window.ended_by == nil,
    tostring(G.NEURO.force_window and G.NEURO.force_window.ended_by))

  arm_foreign_force("SHOP")
  G.OVERLAY_MENU = nil
  local refused = sending_bridge()
  D.handle_message({
    command = "action",
    data = { id = "foreign-failure", name = "exit_overlay_menu", data = "{}" },
  }, refused)
  check("a refused foreign action (success=false) leaves the force open",
    refused.sent[1] and refused.sent[1].data.success == false and require("core.window").current() ~= nil)

  G.OVERLAY_MENU = old_overlay
  G.STATES, G.STATE = old_states, old_state
  G.NEURO.force_window = nil
end

do
  local D = require("core.dispatcher")
  local b = capture_bridge()
  local results = {}
  b.send_action_result = require("tests.helpers").result_log(results, { "id", "success", "message" })

  local ok_nil, err_nil = pcall(D.handle_message,
    { command = "action", data = { name = "exit_overlay_menu", data = nil } }, b)
  check("an action with a missing id never throws", ok_nil == true, tostring(err_nil))
  check("missing id never emits a wire frame", #results == 0, #results)

  local ok_empty, err_empty = pcall(D.handle_message,
    { command = "action", data = { id = "", name = "exit_overlay_menu", data = nil } }, b)
  check("an action with an empty-string id never throws", ok_empty == true, tostring(err_empty))
  check("an empty-string id is silently ignored", #results == 0, #results)
end
do
  local D = require("core.dispatcher")
  local b = capture_bridge()
  local results = {}
  b.send_action_result = require("tests.helpers").result_log(results, { "id", "success", "message", "reason_code" })
  local generation_before = G.NEURO.run_generation
  G.NEURO.run_generation = 5
  local ok_route = pcall(D.route_message, {
    command = "action",
    run_generation = 1,
    data = { name = "exit_overlay_menu" },
  }, b)
  check("stale-generation action without id never throws", ok_route == true)
  check("stale-generation action without id emits no invalid result", #results == 0, #results)
  G.NEURO.run_generation = generation_before
end

do
  local D = require("core.dispatcher")
  local results = {}
  local b = capture_bridge()
  b.send_action_result = require("tests.helpers").result_log(results, { "id", "success", "message", "reason_code" })
  local generation_before = G.NEURO.run_generation
  G.NEURO.run_generation = 5

  local ok_route = pcall(D.route_message, { command = "action", run_generation = 1 }, b)
  check("action with no data wrapper never throws", ok_route == true)
  check("action with no data wrapper emits no wire frame (would need id=nil)",
    #results == 0, #results)

  local ok_handle = pcall(D.handle_message, { command = "action" }, b)
  check("handle_message with no data wrapper never throws", ok_handle == true)
  check("handle_message with no data wrapper emits no wire frame",
    #results == 0, #results)

  G.NEURO.run_generation = generation_before
end

do
  local D = require("core.dispatcher")
  with_menu_overlay(function(reset_run_state)
    local results, contexts = {}, {}
    local executions = 0
    local saved_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function() executions = executions + 1 end
    local b = capture_bridge()
    b.is_transition_cooldown = function() return false end
    b.send_action_result = require("tests.helpers").result_log(results, { "id", "success", "message", "reason_code" })
    G.NEURO.send_context = function(_, message, silent)
      contexts[#contexts + 1] = { message = message, silent = silent }
    end

    reset_run_state()
    require("tests.helpers").stage_registered("MENU", { "exit_overlay_menu" })
    local generation_before = G.NEURO.run_generation
    local last_action_name_before = G.NEURO.last_action_name
    G.NEURO.run_generation = 1
    local msg = {
      command = "action",
      data = { id = "genmis-1", name = "exit_overlay_menu", data = "{}" },
    }
    local job = require("core.validate").validate(msg, b)
    check("validation admits a registered MENU action without answering or executing it",
      job ~= nil and #results == 0 and executions == 0 and #contexts == 0
        and G.NEURO.last_action_name == last_action_name_before)

    G.NEURO.run_generation = generation_before
    G.NEURO.send_context = nil
    G.FUNCS.exit_overlay_menu = saved_exit
  end)
end

do
  local D = require("core.dispatcher")
  with_menu_overlay(function(reset_run_state)
    local array_results = {}
    local array_bridge = capture_bridge()
    array_bridge.is_transition_cooldown = function() return false end
    array_bridge.send_action_result = require("tests.helpers").result_log(array_results, { "id", "success", "message", "reason_code" })
    reset_run_state()
    require("tests.helpers").stage_registered("MENU", { "exit_overlay_menu" })
    local array_accepted = require("core.validate").validate({
      command = "action",
      data = { id = "json-array-payload", name = "exit_overlay_menu", data = "[]" },
    }, array_bridge) ~= nil
    check("JSON type: dispatcher rejects string [] payload", array_accepted == false,
      tostring(array_accepted))
    check("JSON type: string [] rejection is SCHEMA_INVALID",
      array_results[1] and array_results[1].reason_code == "SCHEMA_INVALID",
      array_results[1] and tostring(array_results[1].reason_code))

    local object_results = {}
    local object_bridge = capture_bridge()
    object_bridge.is_transition_cooldown = function() return false end
    object_bridge.send_action_result = require("tests.helpers").result_log(object_results, { "id", "success", "message", "reason_code" })
    reset_run_state()
    local executions = 0
    local saved_exit = G.FUNCS.exit_overlay_menu
    G.FUNCS.exit_overlay_menu = function() executions = executions + 1 end
    local object_accepted = require("core.validate").validate({
      command = "action",
      data = { id = "json-object-payload", name = "exit_overlay_menu", data = "{}" },
    }, object_bridge) ~= nil
    check("JSON type: dispatcher accepts string {} for empty-object schema",
      object_accepted == true, tostring(object_accepted))
    check("validation alone neither answers nor executes",
      executions == 0 and #object_results == 0, executions .. "/" .. #object_results)
    G.FUNCS.exit_overlay_menu = saved_exit
  end)
end

do
  local D = require("core.dispatcher")
  local b = capture_bridge()
  local Metrics = require("util.metrics")
  local function invalid_acks() return Metrics._counters.dispatch_startup_ack_invalid or 0 end
  local invalid_before = invalid_acks()
  local persona_before = G.NEURO.persona
  local ok_call = pcall(D.route_message, {
    command = "startup",
    data = { session = { sessionId = "sess-77", characterId = "neuro", displayName = "Neuro" } },
  }, b)
  check("startup ack never throws", ok_call == true)
  check("a startup ack with a characterId is accepted", invalid_acks() == invalid_before)
  check("startup ack does not touch persona selection", G.NEURO.persona == persona_before,
    tostring(G.NEURO.persona))
  check("startup ack emits no wire frame", #b.sent == 0, #b.sent)

  local ok_malformed = pcall(D.route_message, { command = "startup", data = {} }, b)
  local ok_bad_type = pcall(D.route_message, {
    command = "startup",
    data = {
      session = { sessionId = "sess-77", characterId = "", displayName = "Neuro" },
    },
  }, b)
  check("startup ack malformed metadata never throws and is dropped as invalid",
    ok_malformed == true and ok_bad_type == true and invalid_acks() == invalid_before + 2
      and G.NEURO.persona == persona_before)

  local large_session_id = string.rep("s", 64 * 1024)
  local large_ack = {
    command = "startup",
    data = {
      session = {
        sessionId = large_session_id,
        characterId = "neuro",
        displayName = string.rep("N", 64 * 1024),
      },
    },
  }
  local encoded_large_ack = require("util.neuro_json").encode(large_ack)
  local ok_large = pcall(D.route_message, large_ack, b)
  check("startup ack accepts large frame-valid metadata",
    #encoded_large_ack + 1 <= Bridge.MAX_OUTBOUND_LINE_BYTES
      and ok_large == true
      and invalid_acks() == invalid_before + 2)
end

do
  local D = require("core.dispatcher")
  with_menu_overlay(function(reset_run_state)
    require("tests.helpers").stage_registered("MENU", { "exit_overlay_menu" })

    local function decode_message(id, payload)
      local out = {}
      local b = capture_bridge()
      b.is_transition_cooldown = function() return false end
      b.send_action_result = require("tests.helpers").result_log(out, { "id", "success", "message", "reason_code" })
      reset_run_state()
      D.handle_message({ command = "action", data = { id = id, name = "exit_overlay_menu", data = payload } }, b)
      return out[1]
    end

    local syn = decode_message("json-syntax", '{"a":')
    check("JSON prose: a real syntax error answers with the reference SDK failure (NeuroSdkStrings.cs:14)",
      syn and syn.success == false,
      syn and tostring(syn.message))

    local sem = decode_message("json-null-array", '{"a":[1,null,3]}')
    -- additionalProperties is not advertised, so unknown payload properties must remain accepted.
    check("JSON prose: an undeclared property does not refuse the action",
      sem and sem.success == true, sem and tostring(sem.reason_code))

  end)
end

do
  local CardUtil = require("facts.card_util")
  local CardArea = require("facts.card_area_util")
  local ForceShop = require("force.force_shop")
  local UseCard = require("handlers.use_card")
  local Dispatcher = require("core.dispatcher")
  local json = require("util.neuro_json")

  local function card(key, set, name, cost)
    return {
      cost = cost or 0,
      sell_cost = 1,
      ability = { set = set, name = name },
      config = { center = { key = key, set = set, name = name } },
    }
  end
  local EngineCards = require("tests.engine_cards")
  local death = EngineCards.consumable("c_death", { cost = 0, sell_cost = 1 })

  G.STATES = EngineCards.states()
  G.STATE = G.STATES.SHOP
  G.CONTROLLER = { locked = false }
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 20, chips = 0, used_vouchers = {}, modifiers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = {
      ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
      blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
    },
    blind_on_deck = "Small", blind = {},
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
  }
  G.NEURO = {
    enabled = true, persona = "neuro", reserved_dollars = 0,
    render_dirty_epoch = 0, run_generation = 1, state_enter_serial = 1,
    decision_serial = 1,
  }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.hand = { cards = {
    card("playing_a", "Default", "A", 0), card("playing_b", "Default", "B", 0),
  }, highlighted = {}, config = { card_limit = 8, highlighted_limit = 5 } }
  G.deck = { cards = {} }
  G.shop_vouchers = { cards = {} }
  G.shop_booster = { cards = {} }
  G.FUNCS = { get_poker_hand_info = require("tests.engine_hand_info").stub("Pair") }
  G.P_BLINDS = {
    bl_small = { name = "Small Blind" }, bl_big = { name = "Big Blind" },
    bl_boss = { name = "Boss Blind" },
  }

  local pack_cards = { cards = { EngineCards.consumable("c_hermit") } }
  G.pack_cards = pack_cards
  check("pack alias transition: pack_cards is the active pack area",
    CardUtil.pack_area() == pack_cards and CardArea.get_area("pack_cards") == pack_cards)
  G.pack_cards = nil

  G.shop_jokers = { cards = { death }, config = { card_limit = 2 } }
  local force = ForceShop.build()
  local offered_buy, offered_directional = false, false
  for _, action_name in ipairs((force and force.actions) or {}) do
    offered_buy = offered_buy or action_name == "buy_from_shop"
    offered_directional = offered_directional or action_name == "use_directional_consumable"
  end
  check("directional shop hint: force action names remain authoritative",
    offered_buy and not offered_directional,
    force and table.concat(force.actions or {}, ",") or "no force")
  local _, ordinary = UseCard.handle_use_card({ area = "shop_jokers", index = 1, name = "Death" })
  check("directional shop rejection: ordinary use is refused with a directional remedy",
    type(ordinary) == "table" and ordinary.reason_code == "INVALID_SELECTION"
      and tostring(ordinary.message):find("use_directional_consumable", 1, true) ~= nil,
    ordinary and ordinary.message)

  local ContextCompact = require("context.context_compact")
  local shop_item = card("j_cached", "Joker", "Cached Joker", 3)
  G.shop_jokers = { cards = { shop_item }, config = { card_limit = 2 } }
  local before = ContextCompact.build("SHOP", nil, {})
  shop_item.cost = 7
  local after = ContextCompact.build("SHOP", nil, {})
  check("visible shop mutation reaches the next context build",
    before:find("$3", 1, true) ~= nil and after:find("$7", 1, true) ~= nil
      and before ~= after, tostring(before) .. " / " .. tostring(after))

  G.STATE = G.STATES.SELECTING_HAND
  G.NEURO.state = "SELECTING_HAND"
  require("tests.helpers").stage_registered(nil, { "play_hand" })
  require("core.bridge").tx.reset()
  require("core.window").reset()
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  local results = {}
  local bridge = {
    send_action_result = require("tests.helpers").result_log(results, { "id", "success", "message", "reason_code" }, "written"),
  }
  Dispatcher.handle_message({
    command = "action",
    data = { id = "retry-gate-1", name = "play_hand", data = json.encode({ indices = { 99 } }) },
  }, bridge)
  check("dispatcher mock: forced failure is reported as success=false",
    results[1] and results[1].success == false, results[1] and results[1].message)
  check("dispatcher mock: failed forced action remains eligible for retry",
    require("core.window").current() ~= nil)
  require("core.window").reset()
end

do
  local Registry = require("core.action_registry")

  local saved_blind, saved_cards = G.GAME.blind, G.hand.cards
  G.GAME.blind = { key = "bl_psychic", debuff = { h_size_ge = 3 }, hands = {} }
  G.hand.cards = {}
  for i = 1, 8 do G.hand.cards[i] = { base = { value = "Ace", suit = "Spades" } } end
  local floor_lo, floor_hi = require("facts.boss.legality").play_size_bounds()
  check("the projection check runs in a state where a narrowing would be visible",
    floor_lo > 1 and floor_hi >= floor_lo, tostring(floor_lo) .. "-" .. tostring(floor_hi))

  local base = {}
  for _, def in ipairs(Registry.definitions()) do base[def.name] = def.schema end

  local function array_bounds(schema, out, path)
    if type(schema) ~= "table" then return end
    if schema.type == "array" then
      out[path] = { min = schema.minItems, max = schema.maxItems }
    end
    for key, child in pairs(schema.properties or {}) do
      array_bounds(child, out, path .. "." .. tostring(key))
    end
    if type(schema.items) == "table" then array_bounds(schema.items, out, path .. "[]") end
  end

  local tightened = {}
  for name, base_schema in pairs(base) do
    local live = Registry.get(name)
    local live_schema = live and live.schema
    if type(live_schema) == "table" then
      local base_required = {}
      for _, key in ipairs(base_schema.required or {}) do base_required[key] = true end
      for _, key in ipairs(live_schema.required or {}) do
        if not base_required[key] then
          tightened[#tightened + 1] = name .. " newly requires " .. tostring(key)
        end
      end
      local b, l = {}, {}
      array_bounds(base_schema, b, name)
      array_bounds(live_schema, l, name)
      for path, bounds in pairs(b) do
        local live_bounds = l[path]
        if live_bounds then
          if (live_bounds.min or 0) > (bounds.min or 0) then
            tightened[#tightened + 1] = string.format("%s raises minItems %s -> %s",
              path, tostring(bounds.min), tostring(live_bounds.min))
          end
          if bounds.max and (live_bounds.max or math.huge) < bounds.max then
            tightened[#tightened + 1] = string.format("%s lowers maxItems %s -> %s",
              path, tostring(bounds.max), tostring(live_bounds.max))
          end
        end
      end
    end
  end
  check("no runtime projection tightens the registered schema it was derived from",
    #tightened == 0, table.concat(tightened, "; "))

  local described = Registry.display("play_hand").schema.properties.indices
  local validating = Registry.get("play_hand").schema.properties.indices
  local registered = base["play_hand"].properties.indices
  check("the described projection does narrow here, so this state can tell the channels apart",
    described.minItems ~= registered.minItems or described.maxItems ~= registered.maxItems,
    string.format("described %s-%s vs registered %s-%s", tostring(described.minItems),
      tostring(described.maxItems), tostring(registered.minItems), tostring(registered.maxItems)))
  check("and the validating projection is the registered schema, untouched",
    validating.minItems == registered.minItems and validating.maxItems == registered.maxItems,
    string.format("validating %s-%s", tostring(validating.minItems), tostring(validating.maxItems)))

  local Scoring = require("util.scoring")
  local saved_gap = Scoring.joker_order_gap
  Scoring.joker_order_gap = function()
    return {
      signature = "test-gap",
      groups = { { add = "mult", factor = "xmult",
        behind = { { index = 2, card = { ability = { name = "Green Joker" } }, amount = 4, gain = 4 } },
        pivot = { index = 1, card = { ability = { name = "Blueprint" } }, factor = 2 } } },
    }
  end
  local saved_states, saved_state = G.STATES, G.STATE
  require("tests.helpers").in_engine_state("SHOP")
  local refusal = require("core.gate").check("plan", "leave_shop", {})
  G.STATES, G.STATE = saved_states, saved_state
  Scoring.joker_order_gap = saved_gap
  G.GAME.blind, G.hand.cards = saved_blind, saved_cards

  check("the joker-order gate is actually on for this assertion", refusal ~= nil)
  local prose = refusal and refusal.message
  check("an active joker-order gate refuses with prose that names the remedy, not with a schema",
    refusal ~= nil and refusal.reason_code == "CONFIRMATION_REQUIRED"
      and prose:find("joker_order_confirmed", 1, true) ~= nil,
    tostring(prose))
end

do
  local Dispatcher = require("core.dispatcher")
  local Registry = require("core.action_registry")
  local Enforce = { pre_action = function(_, name, data) return require("tests.helpers").pre_action(name, data) end, reset_run_state = require("core.validate").reset_run_state, reset_streaks = require("core.validate").reset_streaks, note_rejection = function() end }
  local Metrics = require("util.metrics")

  local serial = 0
  local function refuse(name)
    serial = serial + 1
    local seen = {}
    local bridge = require("tests.helpers").stub_bridge({
      send_action_result = function(_, _, success, message, code)
        seen[#seen + 1] = { success = success, message = tostring(message or ""), code = code }
        return true, { status = "written" }
      end,
      send_context = "noop", register_actions = "noop", is_transition_cooldown = "false",
    })
      Dispatcher.handle_message({ command = "action",
      data = { id = "legal-set-" .. serial .. "-" .. name, name = name, data = "{}" } }, bridge)
    return seen[1] or { message = "(no result)" }
  end

  Registry.reset()
  require("core.bridge").tx.reset()
  require("core.window").reset()
  require("tests.helpers").stage_registered(nil, { "play_hand", "discard_hand", "buy_from_shop" })
  local unknown = refuse("no_such_action_at_all")
  check("an unknown name is refused with the reference SDK text (NeuroSdkStrings.cs:16) plus this screen's registered offer",
    unknown.success == false
      and unknown.message:find("play_hand", 1, true) ~= nil
      and unknown.message:find("discard_hand", 1, true) ~= nil
      and unknown.message:find("buy_from_shop", 1, true) == nil, unknown.message)

  Registry.reset()
  require("core.bridge").tx.reset()
  require("core.window").reset()
  require("tests.helpers").stage_registered(nil, { "play_hand", "discard_hand" })
  Registry.note_unregistered({ "discard_hand" }, Registry.now())
  local gone = refuse("discard_hand")
  check("a recently withdrawn action fails like the reference SDKs (Action.cs:55-57, NeuroSdkStrings.cs:15)",
    gone.success == false
      and gone.message:find("play_hand", 1, true) ~= nil,
    tostring(gone.success) .. " " .. gone.message)
  Registry.note_unregistered({ "play_hand" }, Registry.now() - Registry.DYING_GRACE - 1)
  local stale = refuse("play_hand")
  check("past the dying grace a withdrawn game action is refused as not available, never as unknown (BEST_PRACTICES.md:23)",
    stale.success == false,
    tostring(stale.success) .. " " .. stale.message)
  Registry.note_registered({ "discard_hand" })
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  local outside = refuse("play_hand")
  require("core.window").reset()
  check("a game action outside the registered set names only the open force's registered actions",
    outside.success == false and outside.message:find("discard_hand", 1, true) ~= nil,
    outside.message)

  -- Rejection streaks key on the fault fingerprint; adding changing prose prevents the threshold.
  Registry.reset()
  require("core.bridge").tx.reset()
  require("core.window").reset()
  Enforce.reset_run_state()
  local function ack_count() return Metrics._counters.action_rejection_acknowledged or 0 end
  local before = ack_count()
  for i = 1, 4 do
    Registry.reset()
    require("tests.helpers").stage_registered(nil,
      i % 2 == 0 and { "play_hand" } or { "play_hand", "discard_hand" })
    refuse("play_hand")
  end
  local after = ack_count()
  check("a repeated fault accumulates its streak even as the accepted set changes around it",
    after > before, tostring(before) .. " -> " .. tostring(after))

  require("core.window").reset()
  Registry.reset()
end

do
  local function source(path)
    local fh = assert(io.open(path, "r"))
    local src = fh:read("*a"); fh:close(); return src
  end
  local SPOKEN_ALLOWED = { outcome = true, rare_joker = true }
  local offenders = {}
  for _, path in ipairs({ "core/orchestrator.lua", "core/window.lua", "core/validate.lua",
      "core/execute.lua", "force/force_router.lua", "core/dispatcher.lua", "core/rewards.lua" }) do
    for key in source(path):gmatch('ContextDelivery%.prompt_at%("([%w_]+)"') do
      if not SPOKEN_ALLOWED[key] then offenders[#offenders + 1] = path .. ":" .. key end
    end
  end
  check("only outcomes use the spoken context channel",
    #offenders == 0, table.concat(offenders, ", "))

  local Registry = require("core.action_registry")
  require("core.actions").get_static_actions()
  local props
  for _, def in ipairs(Registry.definitions()) do
    if def.name == "set_joker_order" then props = def.schema.properties end
  end
  check("set_joker_order advertises no index ceiling it cannot honour",
    props and props.from_index.maximum == nil and props.to_index.maximum == nil,
    tostring(props and props.from_index.maximum))
end

do
  local bad = {}
  for _, def in ipairs(Actions.get_static_actions()) do
    local name = tostring(def.name or "")
    if not name:match("^[a-z][a-z0-9_%-]*$") then bad[#bad + 1] = name end
  end
  check("every registered action name follows the SPECIFICATION.md:56 grammar",
    #bad == 0, table.concat(bad, ", "))
end

do
  local Catalogue = Actions.catalogue_signature
  check("the catalogue exposes its signature for this check", type(Catalogue) == "function")
  local before = Catalogue()
  local moved = {}
  local function mutate(label, fn)
    fn()
    if Catalogue() ~= before then moved[#moved + 1] = label end
  end
  local function card(name)
    return { ability = { name = name, set = "Joker" }, sort_id = 1,
      config = { center = { key = "j_" .. name, set = "Joker" } } }
  end
  mutate("a card in hand", function() G.hand = { cards = { card("ten"), card("jack") } } end)
  mutate("a joker bought", function() G.jokers = { cards = { card("blueprint") } } end)
  local EngineCards = require("tests.engine_cards")
  mutate("a consumable held", function() G.consumeables = { cards = { EngineCards.consumable("c_hermit") } } end)
  mutate("shop stock", function() G.shop_jokers = { cards = { card("mime") } } end)
  mutate("a pack opened", function() G.pack_cards = { cards = { EngineCards.consumable("c_fool") } } end)
  check("volatile board content does not churn the registered catalogue (BEST_PRACTICES.md:16)",
    #moved == 0, table.concat(moved, ", "))
end

do
  local LB = require("tests.fixtures.live_board")
  local FP = require("tests.force_payload")

  local boards = {}
  for _, list in ipairs({ LB.BOARDS, LB.BLOCKED, LB.OUT_OF_RUN }) do
    for _, board in ipairs(list) do boards[#boards + 1] = board end
  end

  local top_level, scanned = {}, 0
  for _, board in ipairs(boards) do
    LB.load(board.state, board.desc)
    local payload = FP.build(board.state)
    if payload and type(payload.state) == "string" then
      scanned = scanned + 1
      for line in (payload.state .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^#%s") then
          top_level[#top_level + 1] = board.state .. "/" .. tostring(board.desc)
          break
        end
      end
    end
  end

  check("the board sweep reached the live fixtures", scanned >= 15, tostring(scanned))
  check("no force state uses a top-level `# ` heading (BEST_PRACTICES.md:7)",
    #top_level == 0, table.concat(top_level, ", "))
end

local tmp = require("tests.tmp_workdir")
tmp.close()
done()
