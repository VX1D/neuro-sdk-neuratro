local M = {}

local SEED = tonumber(os.getenv("NEURO_FUZZ_SEED") or "") or 20260705

local function chance(p) return math.random() < p end
local function pick(t) return t[math.random(#t)] end
local function maybe(v) if chance(0.12) then return nil end return v end

local function make_card(o)
  local c = {
    cost = math.random(0, 12),
    sell_cost = math.random(0, 6),
    ability = { set = "Default", name = "Mock" },
    config = { center = {} },
    base = { value = tostring(math.random(2, 14)), suit = pick({ "Hearts", "Spades", "Clubs", "Diamonds" }) },
  }
  if o then for k, v in pairs(o) do c[k] = v end end
  return c
end

local VANILLA_CONSUMABLES = require("tests.fixtures.vanilla_consumables")
local function rand_consumable()
  return require("tests.engine_cards").consumable(pick(VANILLA_CONSUMABLES)[1],
    { cost = math.random(0, 12), sell_cost = math.random(0, 6) })
end

local function rand_area(maxn, factory)
  if chance(0.1) then return nil end
  local n = math.random(0, maxn)
  local cards = {}
  for i = 1, n do cards[i] = (factory or make_card)() end
  return { cards = cards, highlighted = {}, config = { card_limit = math.max(n, math.random(2, 5)) } }
end

local BLIND_STATES = { "Select", "Skipped", "Upcoming" }
local function rand_blind_states()
  return {
    Small = pick(BLIND_STATES),
    Big = pick(BLIND_STATES),
    Boss = pick(BLIND_STATES),
  }
end

local VOUCHER_SETS = {
  {}, { v_directors_cut = true }, { v_retcon = true },
  { v_directors_cut = true, v_retcon = true },
}

local function rand_game()
  if chance(0.06) then return nil end
  local g = {
    dollars = maybe(math.random(0, 40)) or 0,
    bankrupt_at = pick({ 0, 0, 0, math.random(1, 10) }),
    stake = math.random(1, 8),
    pack_choices = pick({ 0, 1, 1, 2 }),
    chips = math.random(0, 5000),
    blind = maybe({ chips = math.random(100, 3000), mult = math.random(1, 5) }),
    blind_on_deck = pick({ "Small", "Big", "Boss" }),
    used_vouchers = pick(VOUCHER_SETS),
  }
  if chance(0.9) then
    g.current_round = {
      hands_left = math.random(0, 5),
      discards_left = math.random(0, 5),
      reroll_cost = math.random(0, 12),
      free_rerolls = pick({ 0, 0, 1 }),
    }
  end
  if chance(0.9) then
    g.round_resets = {
      ante = math.random(1, 12),
      blind_choices = maybe({ Small = "bl_small", Big = "bl_big", Boss = "bl_hook" }),
      blind_states = rand_blind_states(),
      boss_rerolled = chance(0.4),
    }
  end
  return g
end

local function rand_overlay(state)
  if state ~= "RUN_SETUP" and chance(0.5) then return nil end
  if state == "RUN_SETUP" or chance(0.3) then
    return {
      get_UIE_by_ID = function(_, id)
        if id == "run_setup_seed" then return {} end
        if id == "tag_container" then
          return { config = { ref_table = { tag = { name = "Tag" } } } }
        end
        return nil
      end,
    }
  end
  return {}
end

local function rand_blind_select_opts()
  if chance(0.15) then return nil end
  local function opt()
    return { get_UIE_by_ID = function(_, id)
      if id == "tag_container" then return { config = { ref_table = { tag = { name = "Tag" } } } } end
      return nil
    end }
  end
  local o = {}
  if chance(0.8) then o.small = opt() end
  if chance(0.8) then o.big = opt() end
  if chance(0.8) then o.boss = opt() end
  return o
end

local PERSONAS = { "neuro", "evil", "hiyori", "neuro", "neuro" }
local STATES = {
  "SELECTING_HAND", "SHOP", "BLIND_SELECT",
  "SMODS_BOOSTER_OPENED",
  "ROUND_EVAL", "GAME_OVER", "MENU", "SPLASH", "RUN_SETUP",
}

local PAYLOADS = {
  nil, "", "{}", '{"index":1}', '{"index":-1}', '{"index":1e19}',
  "not json", "[1,2]", "42", '{"area":"consumables","index":1}',
  '{"seed":"AB12"}', '{"key":"b_red"}', { index = 1 }, { 1, 2, 3 },
}

local function make_bridge()
  local H = require("tests.helpers")
  return H.stub_bridge({ results = {}, send_action_result = H.result_log("results", { "id", "ok" }),
    send_context = "true", register_actions = "noop", force_actions = "noop", send = "noop" })
end

local set_state = require("tests.helpers").state_setter()

function M.run(iterations)
  iterations = iterations or 4000
  math.randomseed(SEED)

  local Dispatcher = G.NEURO and G.NEURO.dispatcher
  local Actions = G.NEURO and G.NEURO.actions
  local ForceHelpers = require("force.force_helpers")
  if not Dispatcher or not Actions then error("fuzz: wire dispatcher/actions") end

  print("====================================================")
  print(string.format("[fuzz] force fuzzer: %d iterations, seed=%d", iterations, SEED))
  print("====================================================")

  local fails = {}
  local function fail(fmt, ...) fails[#fails + 1] = string.format(fmt, ...) end
  local force_returns, probes = 0, 0
  local setup_failures, force_skips = 0, 0
  local attempted_by_state, returned_by_state, skipped_by_state = {}, {}, {}
  for it = 1, iterations do
    local state = pick(STATES)
    local board_state = { state = state, engine_state = state == "RUN_SETUP" and "MENU" or nil }
    attempted_by_state[state] = (attempted_by_state[state] or 0) + 1
    local ok_setup, setup_err = pcall(function()
      G.NEURO = { dispatcher = Dispatcher, actions = Actions }
      G.FUNCS = G.FUNCS or {}
      G.NEURO.persona = pick(PERSONAS)
      G.GAME = rand_game()
      G.hand = rand_area(8)
      G.jokers = rand_area(6)
      G.consumeables = rand_area(3, function() return rand_consumable() end)
      G.OVERLAY_MENU = rand_overlay(state)
      if state == "BLIND_SELECT" then
        G.blind_select_opts = rand_blind_select_opts()
        G.blind_select = true
      else
        G.blind_select_opts = nil
        G.blind_select = nil
      end
      if state == "SHOP" then
        G.shop_jokers = rand_area(4)
        G.shop_vouchers = rand_area(2, function() return make_card({ ability = { set = "Voucher" } }) end)
        G.shop_booster = rand_area(2, function() return make_card({ ability = { set = "Booster", name = "Arcana Pack" } }) end)
        G.NEURO.shop_reroll_count = math.random(0, 6)
        G.NEURO.reserved_dollars = pick({ 0, 0, math.random(0, 15) })
      else
        G.shop_jokers, G.shop_vouchers, G.shop_booster = nil, nil, nil
      end
      if state:find("PACK") or state == "SMODS_BOOSTER_OPENED" then
        G.pack_cards = rand_area(5)
        G.booster_pack = G.pack_cards and { cards = G.pack_cards.cards } or nil
      else
        G.pack_cards, G.booster_pack = nil, nil
      end
      if state == "ROUND_EVAL" then G.round_eval = {} else G.round_eval = nil end
      set_state(board_state)
    end)
    if not ok_setup then
      setup_failures = setup_failures + 1
      fail("iter=%d state=%s SETUP THREW: %s", it, state, tostring(setup_err))
    else
      local Router = require("force.force_router")
      local ok_force, force = pcall(Router.get_force_for_state, state)
      local ok_force2, force2 = pcall(Router.get_force_for_state, state)
      if not ok_force2 then
        fail("iter=%d state=%s I5 second get_force THREW: %s", it, state, tostring(force2))
      elseif ok_force and type(force) == "table" then
        local a1 = (type(force.actions) == "table" and table.concat(force.actions, ",")) or "<invalid>"
        local a2 = (type(force2) == "table" and type(force2.actions) == "table"
          and table.concat(force2.actions, ",")) or "<invalid>"
        if a1 ~= a2 then
          fail("iter=%d state=%s I5 force NONDETERMINISTIC: [%s] vs [%s]", it, state, a1, a2)
        end
      end
      if not ok_force then
        fail("iter=%d state=%s I1 get_force THREW: %s", it, state, tostring(force))
      elseif type(force) == "table" then
        returned_by_state[state] = (returned_by_state[state] or 0) + 1
        force_returns = force_returns + 1
        if type(force.actions) ~= "table" then
          fail("iter=%d state=%s I2 force actions is not a table: %s", it, state, type(force.actions))
        else
          local acts = force.actions
          if #acts == 0 then
            fail("iter=%d state=%s I2 force returned empty action list", it, state)
          end
          local ok_set, state_set = pcall(Actions.get_state_action_set, state)
          if not ok_set then
            fail("iter=%d state=%s I3 get_state_action_set THREW: %s", it, state, tostring(state_set))
          elseif type(state_set) ~= "table" then
            fail("iter=%d state=%s I3 get_state_action_set returned %s", it, state, type(state_set))
          else
            for _, nm in ipairs(acts) do
              if nm ~= "help" and not state_set[nm] then
                fail("iter=%d state=%s I3 forced action '%s' not in state set", it, state, tostring(nm))
              end
            end
          end
          local ok_arm, arm_err = pcall(require("tests.helpers").open_force, state, acts)
          if not ok_arm then
            fail("iter=%d state=%s I3 force arm THREW: %s", it, state, tostring(arm_err))
          end

          for _, nm in ipairs(acts) do
            local ok_state, state_err = pcall(set_state, board_state)
            if not ok_state then
              fail("iter=%d state=%s I4 state setup THREW for '%s': %s",
                it, state, tostring(nm), tostring(state_err))
            end
            local payload = pick(PAYLOADS)
            local id = string.format("fz-%d-%s", it, tostring(nm))
            local bridge = make_bridge()
            local ok_call, call_err = pcall(Dispatcher.handle_message,
              { command = "action", data = { id = id, name = nm, data = payload } }, bridge)
            probes = probes + 1
            if not ok_call then
              fail("iter=%d state=%s I4 handle_message THREW for '%s': %s",
                it, state, tostring(nm), tostring(call_err))
            elseif #bridge.results ~= 1 then
              fail("iter=%d state=%s I4 action '%s' -> %d results (want 1)", it, state, tostring(nm), #bridge.results)
            elseif bridge.results[1].id ~= id then
              fail("iter=%d state=%s I4 action '%s' id not echoed", it, state, tostring(nm))
            end
          end
        end
      else
        skipped_by_state[state] = (skipped_by_state[state] or 0) + 1
        force_skips = force_skips + 1
      end
    end
  end
  local setup_successes = iterations - setup_failures
  if setup_failures ~= 0 then
    fail("fuzzer setup must not fail: %d/%d iterations", setup_failures, iterations)
  end
  if force_returns + force_skips ~= setup_successes then
    fail("force outcomes do not partition successful setups: returned=%d skipped=%d setup=%d",
      force_returns, force_skips, setup_successes)
  end
  local min_returns = math.max(1, math.floor(iterations * 0.5))
  if force_returns < min_returns then
    fail("too few successful force partitions: returned=%d minimum=%d",
      force_returns, min_returns)
  end
  local min_probes = math.max(1, math.floor(force_returns * 0.5))
  if probes < min_probes then
    fail("too few meaningful action probes: probes=%d minimum=%d", probes, min_probes)
  end
  for _, state in ipairs(STATES) do
    if (returned_by_state[state] or 0) + (skipped_by_state[state] or 0)
        ~= (attempted_by_state[state] or 0) then
      fail("state outcome accounting incomplete: %s", state)
    end
  end
  if force_returns == 0 then
    fail("no successful force returned during fuzz setup")
  end
  if probes == 0 then
    fail("no action probes executed during fuzz setup")
  end

  print(string.format("[fuzz] iterations=%d, setup failures=%d, force returned=%d, explicit force skips=%d, action probes=%d",
    iterations, setup_failures, force_returns, force_skips, probes))
  print("====================================================")
  if #fails == 0 then
    print(string.format("==== force-fuzz: %d iters, 0 FAIL ====", iterations))
  else
    print(string.format("==== force-fuzz: %d FAIL ====", #fails))
    for i = 1, math.min(#fails, 40) do print("  FAIL " .. fails[i]) end
    if #fails > 40 then print("  ... and " .. (#fails - 40) .. " more") end
  end
  print("====================================================")
  return #fails
end

return M
