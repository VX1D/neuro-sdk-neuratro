
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

local CONSUMABLE_SETS = { "Tarot", "Planet", "Spectral" }
local function rand_consumable()
  return make_card({
    ability = {
      set = pick(CONSUMABLE_SETS),
      name = "Rnd",
      consumeable = chance(0.7) and {
        max_highlighted = math.random(1, 3),
        min_highlighted = math.random(0, 1),
        hand_type = pick({ "Pair", "Flush", "Straight", "High Card" }),
      } or nil,
    },
  })
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
  if chance(0.5) then return nil end
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
  "TAROT_PACK", "PLANET_PACK", "SPECTRAL_PACK", "STANDARD_PACK", "BUFFOON_PACK", "SMODS_BOOSTER_OPENED",
  "ROUND_EVAL", "GAME_OVER", "MENU", "SPLASH", "RUN_SETUP",
}

local PAYLOADS = {
  nil, "", "{}", '{"index":1}', '{"index":-1}', '{"index":1e19}',
  "not json", "[1,2]", "42", '{"area":"consumables","index":1}',
  '{"seed":"AB12"}', '{"key":"b_red"}', { index = 1 }, { 1, 2, 3 },
}

local function make_bridge()
  local b = { session_id = nil, results = {} }
  function b:send_action_result(id, ok, message) self.results[#self.results + 1] = { id = id, ok = ok } end
  function b:send_context(_, _) return true end
  function b:register_actions(_) end
  function b:force_actions(_, _, _, _) end
  function b:send(_) end
  return b
end

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

function M.run(iterations)
  iterations = iterations or 4000
  math.randomseed(SEED)

  local Dispatcher = G.NEURO and G.NEURO.dispatcher
  local Actions = G.NEURO and G.NEURO.actions
  local ForceHelpers = require("force.force_helpers")
  local ActionPolicy = require("core.action_policy")
  local NON_PROGRESS = ActionPolicy.NON_PROGRESS or {}
  if not Dispatcher or not Actions then error("fuzz: wire dispatcher/actions") end

  print("====================================================")
  print(string.format("[fuzz] force fuzzer: %d iterations, seed=%d", iterations, SEED))
  print("====================================================")

  local fails = {}
  local function fail(fmt, ...) fails[#fails + 1] = string.format(fmt, ...) end
  local force_returns, probes = 0, 0

  local function has_progress(actions)
    for _, n in ipairs(actions or {}) do
      if type(n) == "string" and not NON_PROGRESS[n] then return true end
    end
    return false
  end

  for it = 1, iterations do
    local state = pick(STATES)
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
    set_state(state)

    local ok_force, force = pcall(Dispatcher.get_force_for_state, state)
    local ok_force2, force2 = pcall(Dispatcher.get_force_for_state, state)
    if ok_force and ok_force2 then
      local a1 = (type(force) == "table" and table.concat(force.actions or {}, ",")) or "<nil>"
      local a2 = (type(force2) == "table" and table.concat(force2.actions or {}, ",")) or "<nil>"
      if a1 ~= a2 then
        fail("iter=%d state=%s I5 force NONDETERMINISTIC: [%s] vs [%s]", it, state, a1, a2)
      end
    end
    if not ok_force then
      fail("iter=%d state=%s I1 get_force THREW: %s", it, state, tostring(force))
    elseif type(force) == "table" then
      force_returns = force_returns + 1
      local acts = force.actions or {}
      if #acts == 0 then
        fail("iter=%d state=%s I2 force returned empty action list", it, state)
      elseif not has_progress(acts) then
        fail("iter=%d state=%s I2 forced set has NO progress action (soft-loop): %s",
          it, state, table.concat(acts, ","))
      end
      local ok_set, state_set = pcall(Actions.get_state_action_set, state)
      if ok_set and type(state_set) == "table" then
        for _, nm in ipairs(acts) do
          if nm ~= "help" and not state_set[nm] then
            fail("iter=%d state=%s I3 forced action '%s' not in state set", it, state, tostring(nm))
          end
        end
      end
      local fset = {}
      for _, nm in ipairs(acts) do fset[nm] = true end
      G.NEURO.force_inflight = false
      G.NEURO.force_window = nil
      require("core.force_state").arm(state, acts, fset, 1)

      for _, nm in ipairs(acts) do
        set_state(state)  -- advance clock so cooldowns clear
        local payload = pick(PAYLOADS)
        local id = string.format("fz-%d-%s", it, tostring(nm))
        local bridge = make_bridge()
        local ok_call = pcall(Dispatcher.handle_message,
          { command = "action", data = { id = id, name = nm, data = payload } }, bridge)
        probes = probes + 1
        if not ok_call then
          fail("iter=%d state=%s I4 handle_message THREW for '%s'", it, state, tostring(nm))
        elseif #bridge.results ~= 1 then
          fail("iter=%d state=%s I4 action '%s' -> %d results (want 1)", it, state, tostring(nm), #bridge.results)
        elseif bridge.results[1].id ~= id then
          fail("iter=%d state=%s I4 action '%s' id not echoed", it, state, tostring(nm))
        end
      end
    end
  end

  print(string.format("[fuzz] iterations=%d, force returned=%d, action probes=%d", iterations, force_returns, probes))
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
