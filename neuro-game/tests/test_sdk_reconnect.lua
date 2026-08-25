_G.NEURO_TEST = true
love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
_G.G = { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("sdk-reconnect")

local Config = require("core.config")
local Bridge = require("core.bridge")
local Dispatcher = require("core.dispatcher")
local Actions = require("core.actions")
local FS = require("core.force_state")
local Lifecycle = require("core.neuro_lifecycle")
local Orchestrator = require("core.orchestrator")
local ContextCompact = require("context.context_compact")
local TokenLegends = require("facts.token_legends")
local Enforce = require("core.enforce")
local json = require("util.neuro_json")
local TmpWork = require("tests.tmp_workdir")

local play_card = require("tests.helpers").play_card

local function make_joker(key, name, desc)
  return {
    cost = 4, sell_cost = 2, debuff = false,
    ability = { set = "Joker", name = name, mult = 4 },
    config = { center = { key = key, name = name, set = "Joker",
      loc_txt = { name = name, description = desc or "+4 Mult" } } },
  }
end

local function selecting_hand_env(t)
  G.TIMERS.REAL = t
  G.STATES = { SELECTING_HAND = 4, HAND_PLAYED = 5, MENU = 11 }
  G.STATE = 4
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
  G.playbook_extra = nil
  G.shop_jokers = nil
  G.deck = { cards = {} }
  G.FUNCS = {
    get_poker_hand_info = function(cards) return "Pair", {}, { Pair = { cards } }, cards end,
  }
  require("core.transition_guard").reset()
  Enforce.reset_run_state()
  ContextCompact.invalidate_cache()
end

local function mod_neuro(over)
  require("core.context_delivery").reset_transport()
  local N = { enabled = true, persona = "neuro", emitted = {}, reg_log = {}, reg_defs = {},
    unreg_log = {}, forces = {}, llm_paused = false, reserved_dollars = 0 }
  function N:send_context(msg, _silent, receipt)
    if self.llm_paused then if receipt then receipt.status = "rejected" end return false end
    self.emitted[#self.emitted + 1] = tostring(msg)
    if receipt then receipt.status = "written" end
    return true
  end
  function N:register_actions(defs)
    self.reg_defs[#self.reg_defs + 1] = defs
    local names = {}
    for i, d in ipairs(defs or {}) do names[i] = d.name end
    self.reg_log[#self.reg_log + 1] = names
  end
  function N:unregister_actions(names)
    local copy = {}
    for i, v in ipairs(names or {}) do copy[i] = v end
    self.unreg_log[#self.unreg_log + 1] = copy
  end
  function N:force_actions(_ctx, _query, action_names)
    local copy = {}
    for i, v in ipairs(action_names or {}) do copy[i] = v end
    self.forces[#self.forces + 1] = copy
  end
  function N:send_action_result() end
  function N:update() end
  if over then for k, v in pairs(over) do N[k] = v end end
  return N
end

local transport_session = 0
local function reregister(bridge)
  transport_session = transport_session + 1
  Dispatcher.route_message(
    { command = "actions/reregister_all", transport_session = transport_session }, bridge)
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
  if Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off") == nil then
    check("bridge: outbox truncation disabled for the fixture", false)
  end
  local IPC_DIR = TmpWork.open("sdk_reconnect")
  os.execute("rm -rf " .. IPC_DIR)
  os.execute("mkdir -p " .. IPC_DIR)
  local b = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
  b:set_message_handler(function() end)
  b:send_startup()

  local function context_frames()
    local f = io.open(IPC_DIR .. "/" .. b.outbox_file, "rb")
    if not f then return 0 end
    local data = f:read("*a")
    f:close()
    local n = 0
    for line in data:gmatch("[^\n]+") do
      local ok, msg = pcall(json.decode, line)
      if ok and msg and msg.command == "context" then n = n + 1 end
    end
    return n
  end

  b:send_context("RULES. one-shot reference text", true)
  b:send_context("RULES. one-shot reference text", true)
  check("bridge: a repeated context is sent every time -- Context.send neither merges nor dedupes",
    context_frames() == 2, context_frames())

  local f = io.open(IPC_DIR .. "/" .. b.inbox_file, "ab")
  f:write('{"command":"actions/reregister_all"}\n')
  f:close()
  b:poll_inbox()

  check("bridge: reregister_all clears _last_register_key", b._last_register_key == nil)

  b:send_context("RULES. one-shot reference text", true)
  check("bridge: a context after reconnect is sent like any other",
    context_frames() == 3, context_frames())
  os.execute("rm -rf " .. IPC_DIR)
end

do
  if Config.set("NEURO_OUTBOX_TRUNCATE_ON_STARTUP", "off") == nil then
    check("startup carry-over: outbox truncation disabled for the fixture", false)
  end
  local IPC_DIR = TmpWork.open("startup_carry")

  local function run_fixture(inbox_lines)
    os.execute("rm -rf " .. IPC_DIR)
    os.execute("mkdir -p " .. IPC_DIR)
    local pre = io.open(IPC_DIR .. "/neuro_inbox.jsonl", "wb")
    pre:write(table.concat(inbox_lines, "\n") .. "\n")
    pre:close()

    local seen = {}
    local b = Bridge:new({ enabled = true, fs_dir = IPC_DIR })
    b:set_message_handler(function(msg)
      local outbox = io.open(IPC_DIR .. "/" .. b.outbox_file, "rb")
      local data = outbox and outbox:read("*a") or ""
      if outbox then outbox:close() end
      local first = data:match("^[^\n]*") or ""
      seen[#seen + 1] = { command = msg.command, transport_session = msg.transport_session,
        first_outbox_command = (json.decode(first ~= "" and first or "{}") or {}).command }
    end)
    b:send_startup()
    b:poll_inbox()
    return b, seen
  end

  local b, seen = run_fixture({ '{"command":"actions/reregister_all","transport_session":1}' })
  check("startup carry-over: a reregister_all written before the mod booted reaches the handler",
    #seen == 1 and seen[1].command == "actions/reregister_all", #seen)
  check("startup carry-over: the frame keeps its transport_session",
    seen[1] and seen[1].transport_session == 1, seen[1] and seen[1].transport_session)
  check("startup carry-over: the frame is delivered only after startup is on the outbox",
    seen[1] and seen[1].first_outbox_command == "startup",
    seen[1] and tostring(seen[1].first_outbox_command))
  check("startup carry-over: delivery resets the register memory",
    b._last_register_key == nil and b._force_full_register == true)

  local _, stale = run_fixture({
    '{"command":"actions/reregister_all","transport_session":1}',
    '{"command":"action","data":{"id":"dead-1","name":"play_hand"},"run_generation":1}',
    '{"command":"neuro-bridge/abandon","data":{"ids":["dead-1"]}}',
  })
  local carried_commands = {}
  for _, entry in ipairs(stale) do carried_commands[#carried_commands + 1] = entry.command end
  check("startup carry-over: actions left by the dead session are not replayed",
    #stale == 1 and stale[1].command == "actions/reregister_all",
    table.concat(carried_commands, ","))

  local _, folded = run_fixture({
    '{"command":"actions/reregister_all","transport_session":1}',
    '{"command":"actions/reregister_all","transport_session":2}',
  })
  check("startup carry-over: only the newest reregister_all is carried",
    #folded == 1 and folded[1].transport_session == 2,
    #folded .. "/" .. tostring(folded[1] and folded[1].transport_session))

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
  check("mod: reregister_all empties once_serials",
    type(G.NEURO.once_serials) == "table" and next(G.NEURO.once_serials) == nil)
  local fields = table.concat(require("core.lifecycle_registry").describe().run.fields, "|")
  check("mod: rules_ctx_sig is no longer a delivery ledger", not fields:find("rules_ctx_sig", 1, true))
  check("mod: stable_ctx_sig is no longer a delivery ledger", not fields:find("stable_ctx_sig", 1, true))
  check("mod: stable_sig_cheap is no longer a delivery ledger", not fields:find("stable_sig_cheap", 1, true))
  check("mod: reregister_all leaves no obsolete stable-refresh flag",
    G.NEURO.stable_refresh_due == false)
end

do
  selecting_hand_env(600)
  local N = mod_neuro({ once_serials = {} })
  G.NEURO = N
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  local first = #N.emitted
  check("glossary: first emission delivers the common legend",
    first > 0 and N.emitted[1] == TokenLegends.READABLE_COMMON)
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("glossary: a second call inside the session stays silent", #N.emitted == first)

  reregister(N)
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("glossary: reconnect re-delivers the common legend",
    #N.emitted > first and N.emitted[first + 1] == TokenLegends.READABLE_COMMON,
    tostring(N.emitted[first + 1]))
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
      { command = "actions/reregister_all", transport_session = session }, N)
  end

  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("the legend lands once on the first pass", glossary_count() == 1, glossary_count())

  reregister_raw(1)
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("a reconnect the counter DOES notice re-delivers the legend",
    glossary_count() == 2, glossary_count())

  reregister_raw(1)
  Orchestrator._emit_state_glossary("SELECTING_HAND")
  check("a repeated stamp still re-delivers the legend, so reference material never rides the gate",
    glossary_count() == 3, glossary_count())

  local before = glossary_count()
  for ante = 1, 8 do
    G.GAME.round_resets.ante = ante
    for _ = 1, 10 do Orchestrator._emit_state_glossary("SELECTING_HAND") end
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
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("rules: first stable emission carries the rules head", rules_heads() == 1, rules_heads())
  N.stable_refresh_due = true
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("rules: an unchanged board does not repeat the rules head", rules_heads() == 1, rules_heads())

  reregister(N)
  Orchestrator._maybe_emit_stable_context("SELECTING_HAND")
  check("rules: reconnect re-delivers the rules head", rules_heads() == 2, rules_heads())
end

do
  selecting_hand_env(800)
  G.NEURO = mod_neuro({
    force_sent_at = 800, force_dirty = false,
  })
  require("core.force_state").arm("SELECTING_HAND", { "cash_out" }, { cash_out = true }, 1)
  reregister(G.NEURO)
  check("reconnect closes the force left open on the dead socket",
    G.NEURO.force_inflight == false)
  check("reconnect closes the dead force's window",
    require("core.force_state").window_is_open() == false)
  check("reconnect requests a re-arm", G.NEURO.force_dirty == true)
  check("reconnect does not unregister the dead force's actions",
    #G.NEURO.unreg_log == 0, tostring(#G.NEURO.unreg_log))
  check("reconnect records the reason", G.NEURO.force_last_result == "reconnect")
end

do
  selecting_hand_env(850)
  G.STATE = 5
  G.NEURO = mod_neuro({})
  reregister(G.NEURO)
  check("reconnect in a transient state registers nothing",
    #G.NEURO.reg_log == 0, tostring(#G.NEURO.reg_log))
  check("reconnect in a transient state still resets the context ledger",
    type(G.NEURO.once_serials) == "table" and next(G.NEURO.once_serials) == nil)
  G.STATE = 4
end

do
  selecting_hand_env(900)
  local N = mod_neuro({
    dispatcher = Dispatcher, actions = Actions,
    force_sent_at = 900, force_dirty = false,
    state = "SELECTING_HAND", last_action_at = 0, once_serials = {},
  })
  G.NEURO = N
  require("core.force_state").arm("SELECTING_HAND", { "cash_out" }, { cash_out = true }, 1)
  require("core.tx_cache").reset()
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
  FS.arm("SELECTING_HAND", { "play_hand" }, { play_hand = true }, 1000)
  FS.mark_sent(1000)
  G.STATE = 5
  FS.invalidate("stall", 1000)
  check("invalidation explicitly withdraws and quarantines the force's actions",
    #N.unreg_log == 1 and FS.cancel_blocks("play_hand", 1000) == true, #N.unreg_log)
  check("a transient state re-registers nothing (the pass-2 gate holds)",
    #N.reg_log == 0, tostring(#N.reg_log))
  check("the re-arm request survives the transient state", N.force_dirty == true)

  G.STATE = 4
  G.TIMERS.REAL = 1000 + FS.CANCEL_SETTLE
  Orchestrator._step_state_transition("SELECTING_HAND", true, "HAND_PLAYED")
  local restored = false
  for _, names in ipairs(N.reg_log) do
    for _, n in ipairs(names) do
      if n == "play_hand" then restored = true end
    end
  end
  check("the state transition re-registers the action set",
    restored == true, tostring(#N.reg_log))
end

do
  selecting_hand_env(1100)
  G.GAME.blind = { name = "The Wall", debuff = { h_size_ge = 2, h_size_le = 2 } }
  local N = mod_neuro({})
  G.NEURO = N

  Orchestrator.register_valid_actions("SELECTING_HAND")
  local normal_defs = N.reg_defs[#N.reg_defs]
  local normal_schema = schema_for(normal_defs, "play_hand")
  local normal_indices = normal_schema and normal_schema.properties and normal_schema.properties.indices
  check("schema: normal registration applies legality narrowing",
    normal_indices and normal_indices.minItems == 2 and normal_indices.maxItems == 2)

  reregister(N)
  local reconnect_defs = N.reg_defs[#N.reg_defs]
  check("schema: reconnect registers the same narrowed definitions",
    #N.reg_defs == 2 and same_value(reconnect_defs, normal_defs), tostring(#N.reg_defs))
end

TmpWork.close()
done()
