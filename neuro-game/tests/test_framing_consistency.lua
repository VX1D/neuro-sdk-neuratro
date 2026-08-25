
local M = {}

local TD = require("tests.test_deadlock")
local SCENARIOS = TD.SCENARIOS
local apply_mock = TD.apply_mock

local DEAD_ACTIONS = {
  "set_hand_highlight", "clear_hand_highlight",
  "play_cards_from_highlighted", "discard_cards_from_highlighted",
}

local ALL_STATES = {
  "SPLASH", "MENU", "RUN_SETUP", "GAME_OVER", "BLIND_SELECT", "SELECTING_HAND", "SHOP",
  "ROUND_EVAL", "TAROT_PACK", "PLANET_PACK", "SPECTRAL_PACK", "STANDARD_PACK",
  "BUFFOON_PACK", "SMODS_BOOSTER_OPENED",
}

local TAIL_STATES = {
  SELECTING_HAND = true, SHOP = true, BLIND_SELECT = true, ROUND_EVAL = true,
  TAROT_PACK = true, PLANET_PACK = true, SPECTRAL_PACK = true, STANDARD_PACK = true,
  BUFFOON_PACK = true, SMODS_BOOSTER_OPENED = true,
}

local _clock = 0
local function set_state(state)
  G.STATES = G.STATES or {}
  if G.STATES[state] == nil then
    local nx = 0
    for _, v in pairs(G.STATES) do if v > nx then nx = v end end
    G.STATES[state] = nx + 1
  end
  G.STATE = G.STATES[state]
  _clock = _clock + 5
  G.TIMERS = G.TIMERS or {}
  G.TIMERS.REAL = _clock
end

function M.run()
  local Actions = G.NEURO and G.NEURO.actions
  local Dispatcher = G.NEURO and G.NEURO.dispatcher
  if not Actions or not Dispatcher then error("framing: wire actions/dispatcher") end
  local TokenLegends = require("facts.token_legends")
  local ContextCompact = require("context.context_compact")

  local fails = {}
  local function fail(fmt, ...) fails[#fails + 1] = string.format(fmt, ...) end
  local checks = 0
  local function claimed(cond) checks = checks + 1; return cond end

  print("====================================================")
  print("[framing] model-facing surface consistency lint")
  print("====================================================")

  local defs = Actions.get_static_actions()
  local registered = {}
  for _, d in ipairs(defs) do registered[d.name] = true end

  for _, n in ipairs({ "play_hand", "discard_hand" }) do
    if claimed(not registered[n]) then fail("expected action NOT registered: %s", n) end
  end
  for _, n in ipairs(DEAD_ACTIONS) do
    if claimed(registered[n]) then fail("dead action still registered: %s", n) end
  end

  for _, d in ipairs(defs) do
    local desc = tostring(d.description or "")
    for _, bad in ipairs(DEAD_ACTIONS) do
      if claimed(desc:find(bad, 1, true)) then fail("action '%s' description mentions dead action '%s'", d.name, bad) end
    end
  end

  local function read_file(path)
    local f = io.open(path, "r"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
  end
  local DEAD_SOURCE_TOKENS = { "set_hand_highlight", "clear_hand_highlight" }
  local FORBIDDEN_PHRASES = { "highlight cards first", "action='play'", 'action="play"', "highlighted, you provided" }
  local SOURCE_FILES = {
    "core/actions.lua",
    "handlers/hand_handlers.lua", "handlers/menu_handlers.lua",
    "handlers/seed_run_handlers.lua", "handlers/shop_handlers.lua", "handlers/use_card.lua",
    "force/force_blind_select.lua", "force/force_helpers.lua", "force/force_pack.lua",
    "force/force_router.lua", "force/force_selecting_hand.lua", "force/force_shop.lua",
  }
  for _, path in ipairs(SOURCE_FILES) do
    local src = read_file(path)
    if claimed(not src or src == "") then
      fail("source %s could not be read -- the dead-token scan over it is vacuous", path)
    else
      for _, bad in ipairs(DEAD_SOURCE_TOKENS) do
        if claimed(src:find(bad, 1, true)) then fail("source %s references dead action '%s'", path, bad) end
      end
      for _, ph in ipairs(FORBIDDEN_PHRASES) do
        if claimed(src:find(ph, 1, true)) then fail("source %s contains stale phrase '%s'", path, ph) end
      end
    end
  end

  do
    local common = TokenLegends.READABLE_COMMON or ""
    if claimed(common == "") then
      fail("READABLE_COMMON is empty -- the prescriptive-wording scan over it is vacuous")
    end
    if claimed(not common:find("How to decide:", 1, true)) then
      fail("READABLE_COMMON is missing the decision protocol")
    end
    local STRATEGY_WORDS = { "prefer", "should buy", "should play", "always play", "best hand" }
    local lc = common:lower()
    for _, w in ipairs(STRATEGY_WORDS) do
      if claimed(lc:find(w, 1, true)) then
        fail("READABLE_COMMON contains prescriptive strategy wording '%s' (context must state facts, not choices)", w)
      end
    end
  end

  do
    local SOURCES = {
      "force/force_blind_select.lua", "force/force_pack.lua", "force/force_router.lua",
      "force/force_selecting_hand.lua", "force/force_shop.lua", "force/force_helpers.lua",
      "core/actions.lua", "core/decision_window.lua",
    }
    local checked = 0
    local function lint_payloads(path, text)
      for name, payload in text:gmatch("([a-z_]+)|(%b{})") do
        local props
        for _, d in ipairs(defs) do if d.name == name then props = d.schema and d.schema.properties end end
        if props then
          local flat = payload:gsub("\\", "")
          local depth = 0
          local i = 1
          while i <= #flat do
            local ch = flat:sub(i, i)
            if ch == "{" or ch == "[" then
              depth = depth + 1
            elseif ch == "}" or ch == "]" then
              depth = depth - 1
            elseif depth == 1 and ch == '"' then
              local key = flat:match('^"([a-z_]+)"%s*:', i)
              if key then
                checked = checked + 1
                if claimed(not props[key]) then
                  fail("%s advertises payload key '%s' for %s, which its schema does not define",
                    path, key, name)
                end
              end
            end
            i = i + 1
          end
        end
      end
    end
    for _, path in ipairs(SOURCES) do
      local src = read_file(path)
      if claimed(not src or src == "") then
        fail("source %s could not be read -- the payload-key lint over it is vacuous", path)
      else
        lint_payloads(path, src)
      end
    end
    do
      local Registry = require("core.action_registry")
      for _, d in ipairs(defs) do
        lint_payloads("core/action_registry.lua prompt(" .. d.name .. ")", Registry.prompt(d.name) or "")
      end
    end
    if claimed(checked < 5) then
      fail("payload-key lint examined only %d keys -- the extraction is not matching", checked)
    end
  end

  do
    local PH = read_file("handlers/plan_handlers.lua") or ""
    local accepted = {}
    local decl = PH:match("local VALID_INTENT = %{(.-)%}")
    for tag in tostring(decl or ""):gmatch("(%u[%u_]+)%s*=%s*true") do accepted[tag] = true end
    local n_accepted = 0
    for _ in pairs(accepted) do n_accepted = n_accepted + 1 end
    if claimed(n_accepted < 1) then
      fail("could not parse VALID_INTENT from handlers/plan_handlers.lua (lint would be vacuous)")
    else
      local AC = read_file("core/actions.lua") or ""
      local body = AC:match("local function joker_intents_schema%(%)(.-)\nend")
      local enum_str = body and body:match('enum = %{(.-)%}')
      if claimed(not enum_str) then
        fail("could not parse the tag enum out of joker_intents_schema() in core/actions.lua")
      else
        local schema_tags, n_schema = {}, 0
        for tag in enum_str:gmatch('"(%u[%u_]*)"') do
          n_schema = n_schema + 1
          schema_tags[tag] = true
          if claimed(not accepted[tag]) then
            fail("core/actions.lua's joker_intents_schema advertises tag '%s', which the handler rejects", tag)
          end
        end
        if claimed(n_schema ~= n_accepted) then
          fail("joker_intents_schema offers %d tags but the handler accepts %d -- schema and handler have drifted",
            n_schema, n_accepted)
        end
      end
    end
  end

  do
    local src = read_file("force/force_pack.lua") or ""
    local i = src:find('ActionRegistry.render("skip_booster"', 1, true)
    if claimed(not i) then
      fail("force_pack no longer renders skip_booster where the parity lint expects it")
    elseif claimed(not src:sub(i, i + 300):find("(", 1, true)) then
      fail("skip_booster is offered without any parenthetical describing what it does")
    end
  end

  do
    local GameRules = require("context.game_rules")
    local frame = ""
    pcall(function() frame = GameRules.invariant_frame() or "" end)
    if claimed(frame == "") then
      fail("game_rules.invariant_frame() produced no text -- the RULES scan is vacuous")
    else
      if claimed(frame:find("clear all three", 1, true)) then
        fail("RULES claims all three blinds must be cleared, but skip_blind is an offered action")
      end
      if claimed(not frame:find("skipped", 1, true)) then
        fail("RULES describes the ante structure without mentioning that Small/Big can be skipped")
      end
    end
  end

  do
    local ForceHelpers = require("force.force_helpers")
    local Registry = require("core.action_registry")
    local tree = ""
    pcall(function() tree = ForceHelpers.menu_action_tree_query() or "" end)
    if claimed(tree == "") then
      fail("menu_action_tree_query() produced no text -- the scan over it is vacuous")
    end
    local named = 0
    for word in tree:gmatch("%f[%w_]([a-z][a-z0-9_]+)%f[^%w_]") do
      if Registry.get(word) then named = named + 1 end
    end
    if claimed(named == 0) then
      fail("the menu action tree names no registered action -- the scan is vacuous")
    end
    for _, d in ipairs(Registry.definitions()) do
      local offered = false
      for _, st in ipairs({ "MENU", "RUN_SETUP" }) do
        for _, n in ipairs(Actions.get_action_names_for_state(st) or {}) do
          if n == d.name then offered = true break end
        end
      end
      if claimed(not offered and tree:find("%f[%w_]" .. d.name .. "%f[^%w_]")) then
        fail("menu action tree advertises '%s', which no menu state registers", d.name)
      end
    end
  end

  do
    local by_name = {}
    for _, d in ipairs(defs) do by_name[d.name] = d end
    for _, nm in ipairs({ "buy_from_shop", "use_card", "sell_card" }) do
      local desc = (by_name[nm] or {}).description or ""
      if claimed(desc == "") then
        fail("action '%s' has no description -- the embedded-payload scan over it is vacuous", nm)
      end
      if claimed(desc:find('{"area"', 1, true) or desc:find('{\\"area\\"', 1, true)) then
        fail("action '%s' description re-embeds the payload JSON example (should live only in the force tail)", nm)
      end
    end
    local shl = tostring(TokenLegends.READABLE_STATE.SELECTING_HAND or ""):lower()
    if claimed(shl == "") then
      fail("READABLE_STATE.SELECTING_HAND is empty -- the prescriptive-wording scan is vacuous")
    end
    for _, w in ipairs({ "prefer", "should play", "should discard", "always play", "best hand" }) do
      if claimed(shl:find(w, 1, true)) then
        fail("SELECTING_HAND readable glossary contains prescriptive wording '%s' (state resources, not choices)", w)
      end
    end
  end

  local checked_states = {}
  local scanned = { scenarios = 0, forces = 0, queries = 0, contexts = 0, blobs = 0 }
  local live_states, queried_states = {}, {}
  for _, sc in ipairs(SCENARIOS) do
    if not sc.xfail then
      scanned.scenarios = scanned.scenarios + 1
      live_states[sc.state] = true
      G.NEURO = { dispatcher = Dispatcher, actions = Actions }
      G.FUNCS = G.FUNCS or {}
      apply_mock(sc.mock())
      set_state(sc.state)

      local ok_f, force = pcall(Dispatcher.get_force_for_state, sc.state)
      if ok_f and type(force) == "table" then
        scanned.forces = scanned.forces + 1
        for _, nm in ipairs(force.actions or {}) do
          if claimed(nm ~= "help" and not registered[nm]) then
            fail("force[%s] offers unregistered action '%s'", sc.state, tostring(nm))
          end
        end
        local q = tostring(force.query or "")
        if q ~= "" then
          scanned.queries = scanned.queries + 1
          queried_states[sc.state] = true
        end
        for _, bad in ipairs(DEAD_ACTIONS) do
          if claimed(q:find(bad, 1, true)) then fail("force[%s] query mentions dead action '%s'", sc.state, bad) end
        end
        if claimed(TAIL_STATES[sc.state] and #(force.actions or {}) > 0 and not q:find("Your move", 1, true)) then
          fail("force[%s] query lacks the 'Your move' action-contract tail", sc.state)
        end
      end

      if not checked_states[sc.state] then
        checked_states[sc.state] = true
        local ok_c, ctx = pcall(ContextCompact.build, sc.state)
        if ok_c then
          scanned.contexts = scanned.contexts + 1
          local blob = (type(ctx) == "table" and (ctx.query or table.concat(ctx, "\n"))) or tostring(ctx)
          if blob ~= "" then scanned.blobs = scanned.blobs + 1 end
          if claimed(blob:find("HG:", 1, true)) then fail("context[%s] still emits the removed HG token", sc.state) end
          for _, bad in ipairs(DEAD_ACTIONS) do
            if claimed(blob:find(bad, 1, true)) then fail("context[%s] mentions dead action '%s'", sc.state, bad) end
          end
        end
      end
    end
  end

  if claimed(scanned.scenarios == 0) then
    fail("no live scenario was scanned -- the force/context sweep is vacuous")
  end
  if claimed(scanned.forces == 0 or scanned.queries == 0) then
    fail("no scenario produced a force with a query -- the force sweep is vacuous (%d forces, %d queries)",
      scanned.forces, scanned.queries)
  end
  for state in pairs(TAIL_STATES) do
    if claimed(live_states[state] and not queried_states[state]) then
      fail("state %s was exercised but never produced a force query -- its prose went unscanned", state)
    end
  end
  if claimed(scanned.contexts == 0 or scanned.blobs < scanned.contexts) then
    fail("only %d of %d built contexts carried non-empty text -- the context sweep is partly vacuous",
      scanned.blobs, scanned.contexts)
  end

  local offered = {}
  for _, st in ipairs(ALL_STATES) do
    local ok_set, set = pcall(Actions.get_state_action_set, st)
    if ok_set and type(set) == "table" then
      for n in pairs(set) do offered[n] = true end
    end
  end
  local DYNAMIC_OFFERED = {
    help = true,
  }
  for name in pairs(registered) do
    if claimed(not offered[name] and not DYNAMIC_OFFERED[name]) then
      fail("orphan registered action never offered in any state: '%s'", name)
    end
  end

  print("====================================================")
  if #fails == 0 then
    print("==== framing-consistency: all checks PASS, 0 FAIL ====")
  else
    print(string.format("==== framing-consistency: %d FAIL ====", #fails))
    for _, f in ipairs(fails) do print("  FAIL " .. f) end
  end
  print("====================================================")
  return #fails, checks
end

return M
