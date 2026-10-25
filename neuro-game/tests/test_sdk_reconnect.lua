require("tests.stubs").setup({ love = "timers", G = "timed" })

local check, done = require("tests.helpers").harness("sdk-reconnect")

local Config = require("core.config")
local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local Lifecycle = require("core.neuro_lifecycle")
local Orchestrator = require("core.orchestrator")
local ContextCompact = require("context.context_compact")
local TokenLegends = require("facts.token_legends")
local Enforce = require("tests.helpers").enforce()
local json = require("util.neuro_json")
local Registry = require("core.action_registry")
local TmpWork = require("tests.tmp_workdir")

local play_card = require("tests.helpers").play_card

local make_joker = require("tests.fake_cards").make_joker

local function selecting_hand_env(t)
  G.TIMERS.REAL = t
  require("tests.helpers").in_engine_state("SELECTING_HAND")
  G.STATE_COMPLETE = true
  G.SETTINGS = { GAMESPEED = 1 }
  G.OVERLAY_MENU = nil
  G.CONTROLLER = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 3, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small",
    hands = { Pair = { level = 1, chips = 20, mult = 2, visible = true } },
    modifiers = {},
  }
  G.hand = { cards = { play_card(1), play_card(2), play_card(3) },
    highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = { make_joker("j_joker", "Joker") }, config = { card_limit = 5 } }
  G.consumeables = { cards = {}, config = { card_limit = 2 } }
  G.shop_jokers = nil
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = require("tests.engine_hand_info").stub("Pair"),
  }
  require("core.validate").reset_run_state()
  Enforce.reset_run_state()
end

local function mod_neuro(over)
  require("core.context_delivery").reset_transport()
  local N = require("tests.helpers").started_bridge(require("tests.helpers").stub_bridge({ enabled = true, persona = "neuro",
    emitted = {}, reg_log = {}, reg_defs = {}, unreg_log = {}, forces = {}, llm_paused = false, reserved_dollars = 0,
    startup_calls = 0, _startup_complete = true, _bridge_init_complete = true, send_action_result = "noop", update = "noop" }))
  function N:send_context(msg, _silent, receipt)
    if self.llm_paused then if receipt then receipt.status = "rejected" end return false end
    self.emitted[#self.emitted + 1] = tostring(msg)
    if receipt then receipt.status = "written" end
    return true
  end
  function N:send_startup()
    self.startup_calls = self.startup_calls + 1
    return true
  end
  function N:register_actions(defs)
    self.reg_defs[#self.reg_defs + 1] = defs
    local names = {}
    for i, d in ipairs(defs or {}) do names[i] = d.name end
    self.reg_log[#self.reg_log + 1] = names
  end
  function N:withdraw_actions(names)
    local copy = {}
    for i, v in ipairs(names or {}) do copy[i] = v end
    self.unreg_log[#self.unreg_log + 1] = copy
    return true
  end
  function N:force_actions(_ctx, _query, action_names)
    local copy = {}
    for i, v in ipairs(action_names or {}) do copy[i] = v end
    self.forces[#self.forces + 1] = copy
    return true
  end
  if over then for k, v in pairs(over) do N[k] = v end end
  return N
end

local transport_session = 0
local function reregister(bridge)
  transport_session = transport_session + 1
  Dispatcher.route_message(
    { command = "neuro-bridge/reregister_all", transport_session = transport_session }, bridge)
end

local function same_value(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do
    if not same_value(value, right[key]) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

local function schema_for(defs, name)
  for _, def in ipairs(defs or {}) do
    if def.name == name then return def.schema end
  end
end

do
  local IPC_DIR = TmpWork.open("sdk_reconnect")
  os.execute("rm -rf " .. IPC_DIR)
  os.execute("mkdir -p " .. IPC_DIR)
  local b = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
  b:set_message_handler(function() end)
  b:send_startup()

  local function context_frames()
    return #require("tests.helpers").outbox_frames(IPC_DIR .. "/" .. b.outbox_file, { command = "context" })
  end

  b:send_context("RULES. one-shot reference text", true)
  b:send_context("RULES. one-shot reference text", true)
  check("bridge: a repeated context is sent every time -- Context.send neither merges nor dedupes",
    context_frames() == 2, context_frames())

  local f = io.open(IPC_DIR .. "/" .. b.inbox_file, "ab")
  f:write('{"command":"neuro-bridge/reregister_all"}\n')
  f:close()
  b:poll_inbox()

  check("bridge: reregister_all clears _last_register_key", b._last_register_key == nil)

  b:send_context("RULES. one-shot reference text", true)
  check("bridge: a context after reconnect is sent like any other",
    context_frames() == 3, context_frames())
  os.execute("rm -rf " .. IPC_DIR)
end

do
  local IPC_DIR = TmpWork.open("startup_carry")

  local function run_fixture(inbox_lines)
    os.execute("rm -rf " .. IPC_DIR)
    os.execute("mkdir -p " .. IPC_DIR)
    local pre = io.open(IPC_DIR .. "/neuro_inbox.jsonl", "wb")
    pre:write(table.concat(inbox_lines, "\n") .. "\n")
    pre:close()

    local seen = {}
    local b = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
    G.NEURO = b
    b:set_message_handler(function(msg)
      seen[#seen + 1] = { command = msg.command, transport_session = msg.transport_session }
    end)
    b:send_startup()
    b:poll_inbox()
    local outbox = io.open(IPC_DIR .. "/" .. b.outbox_file, "rb")
    local outbox_data = outbox and outbox:read("*a") or ""
    if outbox then outbox:close() end
    local records = {}
    for line in outbox_data:gmatch("[^\n]+") do records[#records + 1] = json.decode(line) end
    return b, seen, records
  end

  local b, seen, records =
    run_fixture({ '{"command":"neuro-bridge/reregister_all","transport_session":1}' })
  check("startup carry-over: a pre-startup reconnect control is not dispatched",
    #seen == 0, #seen)
  check("startup carry-over: the newest transport session is remembered",
    tostring(b.transport_session) == "1", tostring(b.transport_session))
  check("startup carry-over: startup is the first public frame, tagged with the carried session",
    #records >= 2 and records[1].command == "neuro-bridge/startup_answer"
      and records[1].transport_session == "1" and records[2].command == "startup",
    records[1] and tostring(records[1].command))
  check("startup carry-over: startup resets the register memory",
    b._last_register_key == nil and b._force_full_register == true)

  local stale_bridge, stale = run_fixture({
    '{"command":"neuro-bridge/reregister_all","transport_session":1}',
    '{"command":"action","data":{"id":"dead-1","name":"play_hand"},"run_generation":1}',
    '{"command":"neuro-bridge/abandon","data":{"ids":["dead-1"]}}',
  })
  check("startup carry-over: actions left by the dead session are not replayed",
    #stale == 0 and tostring(stale_bridge.transport_session) == "1",
    #stale .. "/" .. tostring(stale_bridge.transport_session))

  local folded_bridge, folded = run_fixture({
    '{"command":"neuro-bridge/reregister_all","transport_session":1}',
    '{"command":"neuro-bridge/reregister_all","transport_session":2}',
  })
  check("startup carry-over: only the newest reconnect stamp is remembered",
    #folded == 0 and tostring(folded_bridge.transport_session) == "2",
    #folded .. "/" .. tostring(folded_bridge.transport_session))

  local _, none = run_fixture({ '{"command":"action","data":{"id":"dead-2","name":"cash_out"}}' })
  check("startup carry-over: an inbox with nothing session-independent delivers nothing", #none == 0, #none)

  os.execute("rm -rf " .. IPC_DIR)
end


do
  selecting_hand_env(500)
  G.NEURO = mod_neuro({
    once_serials = { ["gloss:readable_common"] = "session" },
    rules_ctx_sig = "FRAME|old", stable_ctx_sig = "tail-old", stable_sig_cheap = "cheap-old",
    stable_refresh_due = false,
  })
  reregister(G.NEURO)
  check("mod: reregister_all keeps what was already delivered",
    type(G.NEURO.once_serials) == "table" and G.NEURO.once_serials["gloss:readable_common"] ~= nil)
end

do
  selecting_hand_env(600)
  local N = mod_neuro({ once_serials = {} })
  G.NEURO = N
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  local first = #N.emitted
  check("glossary: first emission delivers the common legend",
    first > 0 and N.emitted[1] == TokenLegends.READABLE_COMMON)
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("glossary: a second call inside the session stays silent", #N.emitted == first)

  reregister(N)
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("glossary: reconnect does not re-deliver the common legend she already has",
    #N.emitted == first, tostring(N.emitted[first + 1]))
end

do
  selecting_hand_env(650)
  local N = mod_neuro({ once_serials = {}, session_once_serials = {} })
  G.NEURO = N
  local function glossary_count()
    local n = 0
    for _, m in ipairs(N.emitted) do
      if m == TokenLegends.READABLE_COMMON then n = n + 1 end
    end
    return n
  end
  local function reregister_raw(session)
    Dispatcher.route_message(
      { command = "neuro-bridge/reregister_all", transport_session = session }, N)
  end

  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("the legend lands once on the first pass", glossary_count() == 1, glossary_count())

  reregister_raw(1)
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("a reconnect the counter DOES notice still keeps the legend delivered",
    glossary_count() == 1, glossary_count())

  reregister_raw(1)
  require("core.window")._test.emit_glossary("SELECTING_HAND")
  check("a repeated stamp does not re-deliver reference material",
    glossary_count() == 1, glossary_count())

  local before = glossary_count()
  for ante = 1, 8 do
    G.GAME.round_resets.ante = ante
    for _ = 1, 10 do require("core.window")._test.emit_glossary("SELECTING_HAND") end
  end
  check("without a reconnect the legend stays booked for the whole session (#184)",
    glossary_count() == before, glossary_count())

  N.run_generation = 4
  local gen_before = N.run_generation
  reregister_raw(1)
  check("an unchanged transport does not void the run generation",
    N.run_generation == gen_before, tostring(N.run_generation))
  reregister_raw(2)
  check("a stamp the mod has not seen voids the run generation",
    N.run_generation == gen_before + 1, tostring(N.run_generation))
end

do
  selecting_hand_env(700)
  local N = mod_neuro({ once_serials = {}, stable_refresh_due = true })
  G.NEURO = N
  local function rules_heads()
    local n = 0
    for _, m in ipairs(N.emitted) do
      if m:find("RULES.", 1, true) == 1 then n = n + 1 end
    end
    return n
  end
  require("core.window").emit_rules("SELECTING_HAND")
  check("rules: first stable emission carries the rules head", rules_heads() == 1, rules_heads())
  N.stable_refresh_due = true
  require("core.window").emit_rules("SELECTING_HAND")
  check("rules: an unchanged board does not repeat the rules head", rules_heads() == 1, rules_heads())

  reregister(N)
  require("core.window").emit_rules("SELECTING_HAND")
  check("rules: reconnect does not re-deliver the rules head", rules_heads() == 1, rules_heads())
end

do
  selecting_hand_env(800)
  G.NEURO = mod_neuro({})
  local dead = require("tests.helpers").open_force("SELECTING_HAND", { "cash_out" })
  reregister(G.NEURO)
  check("reconnect closes the dead force's window", require("core.window").current() == nil)
  check("reconnect does not unregister the dead force's actions",
    #G.NEURO.unreg_log == 0, tostring(#G.NEURO.unreg_log))
  check("reconnect records the reason", dead.phase == "ended" and dead.ended_by == "reset", tostring(dead.ended_by))
end

do
  selecting_hand_env(850)
  G.STATE = G.STATES.HAND_PLAYED
  G.NEURO = mod_neuro({ once_serials = { ["gloss:readable_common"] = "session" } })
  reregister(G.NEURO)
  check("reconnect re-registers the catalogue at once, whatever the state (BEST_PRACTICES.md:44)",
    #G.NEURO.reg_log == 1, tostring(#G.NEURO.reg_log))
  check("reconnect in a transient state keeps the context ledger too",
    type(G.NEURO.once_serials) == "table" and G.NEURO.once_serials["gloss:readable_common"] ~= nil)
  G.STATE = G.STATES.SELECTING_HAND
end

do
  selecting_hand_env(900)
  local N = mod_neuro({
    dispatcher = Dispatcher, actions = Actions,
    state = "SELECTING_HAND", last_action_at = 0, once_serials = {},
  })
  G.NEURO = N
  require("tests.helpers").open_force("SELECTING_HAND", { "cash_out" })
  require("core.bridge").tx.reset()
  reregister(N)

  local elapsed = 0
  local budget = 4.0
  while elapsed < budget and #N.forces == 0 do
    G.TIMERS.REAL = G.TIMERS.REAL + 0.1
    elapsed = elapsed + 0.1
    pcall(Orchestrator.update, 0.1)
  end
  check("a replacement force is armed on the debounce, with no clock to wait out",
    #N.forces == 1, "forces=" .. #N.forces .. " after " .. string.format("%.1f", elapsed) .. "s")

  local registered = {}
  for _, names in ipairs(N.reg_log) do
    for _, n in ipairs(names) do registered[n] = true end
  end
  local offered = N.forces[1]
  check("the rebuilt force actually names some actions to scan",
    type(offered) == "table" and #offered > 0, tostring(offered and #offered))
  offered = type(offered) == "table" and offered or {}
  local ghosts = {}
  for _, n in ipairs(offered) do
    if not registered[n] then ghosts[#ghosts + 1] = n end
  end
  check("the rebuilt force names only actions registered in this session",
    #N.forces == 1 and #ghosts == 0, table.concat(ghosts, ","))
  local replayed = false
  for _, n in ipairs(offered) do
    if n == "cash_out" then replayed = true end
  end
  check("the dead socket's action list is not replayed verbatim", replayed == false)
end

do
  selecting_hand_env(1000)
  local N = mod_neuro({ dispatcher = Dispatcher, actions = Actions, state = "SELECTING_HAND" })
  G.NEURO = N
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand" })
  G.STATE = G.STATES.HAND_PLAYED
  require("core.window").withdraw("stall", 1000)
  check("withdrawal unregisters a sent force's actions",
    #N.unreg_log == 1 and require("core.window").current() == nil, tostring(#N.unreg_log))
  check("a transient state re-registers nothing (the pass-2 gate holds)",
    #N.reg_log == 0, tostring(#N.reg_log))

  G.STATE = G.STATES.SELECTING_HAND
  Orchestrator._step_state_transition("SELECTING_HAND", true, "HAND_PLAYED")
  check("the state transition leaves the withdrawn force terminal", require("core.window").current() == nil)
end

do
  selecting_hand_env(1100)
  G.GAME.blind = { name = "The Wall", debuff = { h_size_ge = 2, h_size_le = 2 } }
  local N = mod_neuro({})
  G.NEURO = N

  require("core.window").register_catalogue()
  local normal_defs = N.reg_defs[#N.reg_defs]
  local normal_schema = schema_for(normal_defs, "play_hand")
  local normal_indices = normal_schema and normal_schema.properties and normal_schema.properties.indices
  local normal_detail = normal_indices
    and (tostring(normal_indices.minItems) .. "/"
      .. type(normal_indices.maxItems) .. "/" .. tostring(normal_indices.maxItems))
    or "missing"
  check("schema: normal registration advertises the run's selection bounds",
    normal_indices and normal_indices.minItems == 1 and normal_indices.maxItems ~= nil,
    normal_detail)
  local advertised = {}
  for _, def in ipairs(Registry.definitions()) do
    for i = 1, #(normal_defs or {}) do
      if normal_defs[i].name == def.name then advertised[#advertised + 1] = def end
    end
  end
  check("schema: Registry.definitions agrees with the stable registration catalogue",
    #advertised == #(normal_defs or {}) and same_value(advertised, normal_defs), tostring(#normal_defs))

  local live_def = Registry.display("play_hand")
  local live_schema = live_def and live_def.schema
  local live_indices = live_schema and live_schema.properties and live_schema.properties.indices
  local live_detail = live_indices
    and (tostring(live_indices.minItems) .. "/" .. type(live_indices.maxItems)
      .. "/" .. tostring(live_indices.maxItems))
    or "missing"
  check("schema: Registry.get exposes the current selecting-hand bounds",
    live_indices and live_indices.minItems == 2
      and type(live_indices.maxItems) == "number" and live_indices.maxItems == 2,
    live_detail)

  reregister(N)
  local reconnect_defs = N.reg_defs[#N.reg_defs]
  check("schema: reconnect registers the same stable definitions",
    #N.reg_defs == 2 and same_value(reconnect_defs, normal_defs), tostring(#N.reg_defs))
end

do
  local IPC_DIR = TmpWork.open("run_restart_withdrawal")
  os.execute("rm -rf " .. IPC_DIR)
  os.execute("mkdir -p " .. IPC_DIR)
  local b = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
  G.NEURO = b
  b.transport_session = 7
  b.run_generation = 1
  b.decision_serial = 1
  check("restart: startup succeeds", b:send_startup() == true)
  check("restart: the catalogue registers", b:register_actions({
    { name = "play_hand", description = "Play.", schema = { type = "object" } },
    { name = "discard_hand", description = "Discard.", schema = { type = "object" } },
  }) == true)
  require("tests.helpers").open_force("SELECTING_HAND", { "play_hand", "discard_hand" })
  check("restart: the open force reaches the wire",
    b:force_actions("SELECTING_HAND", "Choose.", { "play_hand", "discard_hand" }) == true)

  local function frames()
    local out = {}
    local f = assert(io.open(IPC_DIR .. "/" .. b.outbox_file, "rb"))
    for line in f:lines() do
      local ok, msg = pcall(json.decode, line)
      assert(ok and type(msg) == "table")
      out[#out + 1] = msg
    end
    f:close()
    return out
  end
  local before = #frames()
  Lifecycle.withdraw_open_force()
  Lifecycle.bump_run_generation("run restarted")
  Lifecycle.reset_run_state(true)
  local after = frames()
  local unregistered, marker = nil, false
  for i = before + 1, #after do
    if after[i].command == "actions/unregister" then unregistered = after[i].data.action_names end
    if tostring(after[i].command):find("run_restart", 1, true) then marker = true end
  end
  check("restart: the old run's forced actions are unregistered on the wire",
    unregistered ~= nil and table.concat(unregistered, ",") == "discard_hand,play_hand",
    unregistered and table.concat(unregistered, ",") or "none")
  check("restart: no private restart marker is written", marker == false)
  check("restart: the bridge carries no restart-marker machinery", b.mark_run_restart == nil)
  os.execute("rm -rf " .. IPC_DIR)
end

TmpWork.close()
done()
