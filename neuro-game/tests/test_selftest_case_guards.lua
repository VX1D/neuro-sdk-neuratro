_G.NEURO_TEST = true
if not love then
  love = setmetatable({ timer = { getTime = function() return 0 end } },
    { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("selftest-case-guards")

local function pool(key) return { { key = key, name = key, config = {} } } end

_G.SMODS = { Mods = {} }
_G.G = {
  GAME = {}, NEURO = {}, FUNCS = {}, STATES = {},
  P_CENTERS = {
    m_gold = { key = "m_gold", set = "Enhanced" },
    e_foil = { key = "e_foil", set = "Edition" },
    c_mercury = { key = "c_mercury", set = "Planet" },
  },
  P_SEALS = { Gold = {}, Red = {} },
  P_BLINDS = {}, P_TAGS = {},
  P_CENTER_POOLS = {
    Planet = { { key = "c_mercury", name = "Mercury", config = { hand_type = "Pair" } } },
    Tarot = pool("c_fool"), Spectral = pool("c_familiar"),
    Booster = pool("p_arcana_1"), Voucher = pool("v_hone"),
  },
}
local BASE_POOLS = G.P_CENTER_POOLS
local BASE_CENTERS = G.P_CENTERS
local BASE_SEALS = G.P_SEALS

local Cases = require("core.selftest_cases")
local Actions = require("core.actions")
local Dispatcher = require("core.dispatcher")
local Router = require("force.force_router")
local TokenLegends = require("facts.token_legends")

local built = Cases.build()
local by_name = {}
for _, c in ipairs(built) do by_name[c.name] = c end

local GUARDED = {
  "meta/all_mods_have_context",
  "ctx/token_legends_ascii",
  "policy/dead_actions_are_known_set",
  "force/selecting_hand_completeness",
  "force/shop_completeness",
  "force/blind_select_completeness",
  "meta/pools_fully_enumerated",
}
do
  local absent = {}
  for _, n in ipairs(GUARDED) do if not (by_name[n] and by_name[n].assert) then absent[#absent + 1] = n end end
  check("every guarded case was built and carries an assert body to run",
    #built > 0 and #absent == 0, table.concat(absent, ",") .. " of " .. #built .. " cases")
end

local function run(name)
  local c = by_name[name]
  if not (c and c.assert) then return nil, "case not built: " .. name end
  local ok, res, msg = pcall(c.assert, {})
  if not ok then return nil, "assert threw: " .. tostring(res) end
  return res, msg
end

local function trio(name, label, clean, violate, starve)
  local function verdict(setup, want, tag)
    setup()
    local res, msg = run(name)
    check(string.format("%s %s: %s", label, tag, name),
      res == want, tostring(res) .. " -- " .. tostring(msg))
  end
  verdict(clean, true, "passes on a clean world")
  verdict(function() clean(); violate() end, false, "fails on a violated world")
  verdict(function() clean(); starve() end, false, "fails when its sole source is EMPTY")
  clean()
end

trio("meta/all_mods_have_context", "G1",
  function() G.P_CENTERS = BASE_CENTERS; G.P_SEALS = BASE_SEALS end,
  function() G.P_CENTERS = { m_nosuch = { key = "m_nosuch", set = "Enhanced" } } end,
  function() G.P_CENTERS = {} end)

trio("meta/all_mods_have_context", "G2",
  function() G.P_CENTERS = BASE_CENTERS; G.P_SEALS = BASE_SEALS end,
  function() G.P_SEALS = { Chartreuse = {} } end,
  function() G.P_SEALS = {} end)

do
  local base_state = TokenLegends.READABLE_STATE
  trio("ctx/token_legends_ascii", "G3",
    function() TokenLegends.READABLE_STATE = base_state end,
    function() TokenLegends.READABLE_STATE = { SHOP = "caf\xc3\xa9" } end,
    function() TokenLegends.READABLE_STATE = {} end)
  TokenLegends.READABLE_STATE = base_state
end

do
  local base_avail = Actions.get_available_actions_for_state
  local base_names = Actions.get_action_names_for_state
  local base_static = Actions.get_static_actions
  local base_np = Dispatcher.NON_PROGRESS_FORCE_ACTIONS
  local base_force = Router.get_force_for_state

  local function restore()
    Actions.get_available_actions_for_state = base_avail
    Actions.get_action_names_for_state = base_names
    Actions.get_static_actions = base_static
    Dispatcher.NON_PROGRESS_FORCE_ACTIONS = base_np
    Router.get_force_for_state = base_force
  end

  trio("policy/dead_actions_are_known_set", "G5",
    function()
      restore()
      Actions.get_static_actions = function() return { { name = "play_hand" } } end
      Actions.get_action_names_for_state = function() return { "play_hand" } end
    end,
    function() Actions.get_static_actions = function() return { { name = "play_hand" }, { name = "ghost_action" } } end end,
    function() Actions.get_static_actions = function() return {} end end)

  local FORCE_CASES = {
    { case = "force/selecting_hand_completeness", state = "SELECTING_HAND",
      offered = { "play_hand", "discard_hand", "sell_card" }, legal = { "play_hand", "sell_card" } },
    { case = "force/shop_completeness", state = "SHOP",
      offered = { "toggle_shop", "sell_card", "buy_from_shop" }, legal = { "buy_from_shop" } },
    { case = "force/blind_select_completeness", state = "BLIND_SELECT",
      offered = { "select_blind", "skip_blind" }, legal = { "select_blind" } },
  }
  for i, fc in ipairs(FORCE_CASES) do
    trio(fc.case, "G" .. (5 + i),
      function()
        restore()
        Dispatcher.NON_PROGRESS_FORCE_ACTIONS = {}
        Router.get_force_for_state = function() return { actions = fc.offered } end
        Actions.get_available_actions_for_state = function() return fc.legal end
        Actions.is_action_valid = function(n)
          for _, a in ipairs(fc.offered) do if a == n then return true end end
          return false
        end
      end,
      function() Actions.get_available_actions_for_state = function() return { "no_such_action" } end end,
      function() Actions.get_available_actions_for_state = function() return {} end end)
  end
  restore()
end

trio("meta/pools_fully_enumerated", "G9",
  function() G.P_CENTER_POOLS = BASE_POOLS end,
  function()
    G.P_CENTER_POOLS = { Planet = BASE_POOLS.Planet, Tarot = BASE_POOLS.Tarot,
      Spectral = BASE_POOLS.Spectral, Booster = BASE_POOLS.Booster,
      Voucher = { { key = "v_never_generated", name = "x", config = {} } } }
  end,
  function()
    G.P_CENTER_POOLS = { Planet = BASE_POOLS.Planet, Tarot = {},
      Spectral = BASE_POOLS.Spectral, Booster = BASE_POOLS.Booster, Voucher = BASE_POOLS.Voucher }
  end)

done()
