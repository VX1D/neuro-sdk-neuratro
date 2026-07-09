-- Framing-consistency lint: model-facing surface (descriptions, force queries, context tokens, glossary) free of stale/dead refs.
-- Guards the "phantom two-step" bug (a fresh model misled by contradictory framing). luajit tests/run_framing.lua

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

-- progress states must end with the uniform "Your move:" action-contract tail (A1); menu/setup states use a prose query.
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

  print("====================================================")
  print("[framing] model-facing surface consistency lint")
  print("====================================================")

  local defs = Actions.get_static_actions()
  local registered = {}
  for _, d in ipairs(defs) do registered[d.name] = true end

  for _, n in ipairs({ "play_hand", "discard_hand" }) do
    if not registered[n] then fail("expected action NOT registered: %s", n) end
  end
  for _, n in ipairs(DEAD_ACTIONS) do
    if registered[n] then fail("dead action still registered: %s", n) end
  end

  for _, d in ipairs(defs) do
    local desc = tostring(d.description or "")
    for _, bad in ipairs(DEAD_ACTIONS) do
      if desc:find(bad, 1, true) then fail("action '%s' description mentions dead action '%s'", d.name, bad) end
    end
  end

  for _, st in ipairs(ALL_STATES) do
    local _, legend = TokenLegends.for_state(st)
    legend = tostring(legend or "")
    for _, bad in ipairs(DEAD_ACTIONS) do
      if legend:find(bad, 1, true) then fail("glossary[%s] mentions dead action '%s'", st, bad) end
    end
    if legend:find("HG=", 1, true) then fail("glossary[%s] still documents the removed HG token", st) end
  end

  -- 2c. scan source for dead ACTION names only: G.FUNCS play_cards_from_highlighted/discard_cards_from_highlighted are legit engine calls in hand_handlers
  local function read_file(path)
    local f = io.open(path, "r"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
  end
  local DEAD_SOURCE_TOKENS = { "set_hand_highlight", "clear_hand_highlight" }
  local FORBIDDEN_PHRASES = { "highlight cards first", "action='play'", 'action="play"', "highlighted, you provided" }
  local SOURCE_FILES = {
    "core/actions.lua",
    "handlers/hand_handlers.lua", "handlers/info_handlers.lua", "handlers/menu_handlers.lua",
    "handlers/seed_run_handlers.lua", "handlers/shop_handlers.lua", "handlers/use_card.lua",
    "force/force_blind_select.lua", "force/force_helpers.lua", "force/force_pack.lua",
    "force/force_router.lua", "force/force_selecting_hand.lua", "force/force_shop.lua",
  }
  for _, path in ipairs(SOURCE_FILES) do
    local src = read_file(path)
    if src then
      for _, bad in ipairs(DEAD_SOURCE_TOKENS) do
        if src:find(bad, 1, true) then fail("source %s references dead action '%s'", path, bad) end
      end
      for _, ph in ipairs(FORBIDDEN_PHRASES) do
        if src:find(ph, 1, true) then fail("source %s contains stale phrase '%s'", path, ph) end
      end
    end
  end

  do
    local common = TokenLegends.COMMON or ""
    if not common:find("DECIDE=", 1, true) then
      fail("COMMON glossary is missing the DECIDE= decision protocol")
    end
    local STRATEGY_WORDS = { "prefer", "should buy", "should play", "always play", "best hand" }
    local lc = common:lower()
    for _, w in ipairs(STRATEGY_WORDS) do
      if lc:find(w, 1, true) then
        fail("COMMON contains prescriptive strategy wording '%s' (context must state facts, not choices)", w)
      end
    end
  end

  -- 2e. tail-canonical: the payload JSON example lives only in the force tail, not the action description or PACK glossary (A2)
  do
    local by_name = {}
    for _, d in ipairs(defs) do by_name[d.name] = d end
    for _, nm in ipairs({ "buy_from_shop", "use_card", "sell_card" }) do
      local desc = (by_name[nm] or {}).description or ""
      if desc:find('{"area"', 1, true) or desc:find('{\\"area\\"', 1, true) then
        fail("action '%s' description re-embeds the payload JSON example (should live only in the force tail)", nm)
      end
    end
    local _, pack_legend = TokenLegends.for_state("TAROT_PACK")
    if tostring(pack_legend or ""):find("use_card payload", 1, true) then
      fail("PACK glossary still carries the use_card payload (force tail now owns it)")
    end
    -- 2f. RUN_SETUP legend must not re-collide SD (was: seeded flag vs deck-selection header)
    local _, rs_legend = TokenLegends.for_state("RUN_SETUP")
    if tostring(rs_legend or ""):find("SD=seeded", 1, true) then
      fail("RUN_SETUP legend still defines SD as 'seeded' (collides with the SD deck-selection header)")
    end
    local _, sh_legend = TokenLegends.for_state("SELECTING_HAND")
    local shl = tostring(sh_legend or ""):lower()
    for _, w in ipairs({ "prefer", "should play", "should discard", "always play", "best hand" }) do
      if shl:find(w, 1, true) then
        fail("SELECTING_HAND legend contains prescriptive wording '%s' (state resources, not choices)", w)
      end
    end
  end

  local checked_states = {}
  for _, sc in ipairs(SCENARIOS) do
    if not sc.xfail then
      G.NEURO = { dispatcher = Dispatcher, actions = Actions, rules_sent = true }
      G.FUNCS = G.FUNCS or {}
      apply_mock(sc.mock())
      set_state(sc.state)

      local ok_f, force = pcall(Dispatcher.get_force_for_state, sc.state)
      if ok_f and type(force) == "table" then
        for _, nm in ipairs(force.actions or {}) do
          if nm ~= "help" and not registered[nm] then
            fail("force[%s] offers unregistered action '%s'", sc.state, tostring(nm))
          end
        end
        local q = tostring(force.query or "")
        for _, bad in ipairs(DEAD_ACTIONS) do
          if q:find(bad, 1, true) then fail("force[%s] query mentions dead action '%s'", sc.state, bad) end
        end
        -- A1: progress force ends with the "Your move" contract (SELECTING_HAND: "Your move (up to N cards...)", others "Your move: ...")
        if TAIL_STATES[sc.state] and #(force.actions or {}) > 0 and not q:find("Your move", 1, true) then
          fail("force[%s] query lacks the 'Your move' action-contract tail", sc.state)
        end
      end

      if not checked_states[sc.state] then
        checked_states[sc.state] = true
        local ok_c, ctx = pcall(ContextCompact.build, sc.state)
        if ok_c then
          local blob = (type(ctx) == "table" and (ctx.query or table.concat(ctx, "\n"))) or tostring(ctx)
          if blob:find("HG:", 1, true) then fail("context[%s] still emits the removed HG token", sc.state) end
          for _, bad in ipairs(DEAD_ACTIONS) do
            if blob:find(bad, 1, true) then fail("context[%s] mentions dead action '%s'", sc.state, bad) end
          end
          -- token<->glossary closure: every multi-letter line header must be in COMMON or the state legend; D<col>|Tn: dict lines and single-letter headers are exempt
          local _, legend = TokenLegends.for_state(sc.state)
          local doc = TokenLegends.COMMON .. " " .. tostring(legend or "")
          for line in (blob .. "\n"):gmatch("([^\n]*)\n") do
            if not line:match("^D%u*|%u+%d+:") then
              local header = line:match("^([A-Z][A-Z_0-9]*)")
              if header and #header >= 2 and not doc:find(header, 1, true) then
                fail("context[%s] emits undocumented token '%s' (add it to token_legends)", sc.state, header)
              end
            end
          end
        end
      end
    end
  end

  local offered = {}
  for _, st in ipairs(ALL_STATES) do
    local ok_set, set = pcall(Actions.get_state_action_set, st)
    if ok_set and type(set) == "table" then
      for n in pairs(set) do offered[n] = true end
    end
  end
  -- help is appended universally by the forcer (not via STATE_ACTIONS), so it's not an orphan
  local DYNAMIC_OFFERED = {
    help = true,
  }
  for name in pairs(registered) do
    if not offered[name] and not DYNAMIC_OFFERED[name] then
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
  return #fails
end

return M
