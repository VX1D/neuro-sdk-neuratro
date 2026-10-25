local mode = arg[1] or "off"
require("tests.stubs").setup({ love = "timers", localize = true })
local ES = require("tests.engine_cards").states()
local H = require("tests.helpers")
local check, done = H.harness("joker-observers-crash-guards-" .. mode)
local ipc_dir = require("tests.tmp_workdir").open("joker_observers_cg_" .. mode)
require("core.mod_paths").read_ipc_dir = function() return ipc_dir end

local engine_calls = 0
local function engine_calculate_joker(self, context)
  engine_calls = engine_calls + 1
  if context.joker_main then return { mult_mod = 4, card = self }, true end
  return nil, nil
end
local function engine_remove(self)
  local cards = G.jokers and G.jokers.cards or {}
  for i = #cards, 1, -1 do if cards[i] == self then table.remove(cards, i) end end
end
_G.Card = { calculate_joker = engine_calculate_joker, calculate_dollar_bonus = function() return nil end,
  remove = engine_remove, use_consumeable = function() end }
_G.eval_card = function(card, context) return { jokers = card:calculate_joker(context) }, {} end
_G.SMODS.calculate_context = function() return {} end
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), TIMERS = { REAL = 100, TOTAL = 100 },
  GAME = { current_round = {}, round = 3 }, FUNCS = {}, STATES = ES, STATE = ES.MENU, SETTINGS = {} }

require("core.config").set("NEURO_CRASH_GUARDS", mode)
require("core.orchestrator")._step_bridge_init()
check("bridge init completes", G.NEURO and G.NEURO._bridge_init_complete == true)

local function wrapper_chain(fn)
  local chain = {}
  for _ = 1, 10 do
    chain[#chain + 1] = (debug.getinfo(fn, "S").source:match("([%w_]+)%.lua$") or "?")
    if fn == engine_calculate_joker then break end
    local inner
    for i = 1, 20 do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if type(value) == "function" and (name == "orig_calculate" or name == "original" or name == "calculate_joker") then
        inner = value
      end
    end
    if not inner then break end
    fn = inner
  end
  return table.concat(chain, " > ")
end
local EXPECTED = "joker_hits > joker_recorder > destruction_log > test_joker_observers_without_crash_guards"
check("Card.calculate_joker is wrapped by every observer, outermost first, whatever the crash-guard toggle",
  wrapper_chain(Card.calculate_joker) == EXPECTED, wrapper_chain(Card.calculate_joker))
check("eval_card is wrapped by the hit counter", _G.eval_card ~= nil
  and debug.getinfo(_G.eval_card, "S").source:find("joker_hits", 1, true) ~= nil)
check("crash guards follow the toggle", (Card.__neuro_remove_guard == true) == (mode == "on"))

local bridge = G.NEURO
H.orch_board({ clock = 100 })
G.TIMERS.TOTAL = 100
G.hand = H.card_area(G.hand)
for i = 1, 6 do G.hand.cards[i] = H.play_card(i) end
G.NEURO = bridge
local joker = setmetatable({ sort_id = 7, facing = "front", sell_cost = 2,
  ability = { set = "Joker", name = "Joker", mult = 4 },
  config = { center = G.P_CENTERS.j_joker } }, { __index = Card })
G.jokers.cards = { joker }
engine_calls = 0
for _ = 1, 4 do _G.eval_card(joker, { cardarea = G.jokers, joker_main = true }) end
check("the engine scores the joker once per evaluation", engine_calls == 4, tostring(engine_calls))
check("the trigger is observed", G.NEURO.joker_observations and G.NEURO.joker_observations[7]
  and G.NEURO.joker_observations[7].score_mult == true)

local function force_frames()
  local out = {}
  for _, f in ipairs(H.outbox_frames(ipc_dir .. "/" .. G.NEURO.outbox_file, { must = true })) do
    if f.command == "actions/force" then out[#out + 1] = f end
  end
  return out
end
local clock = 100
for _ = 1, 600 do
  if #force_frames() > 0 then break end
  clock = clock + 0.1
  G.TIMERS.REAL, G.TIMERS.TOTAL = clock, clock
  pcall(require("core.orchestrator").update, 0.1)
end
local frames = force_frames()
local state = frames[1] and frames[1].data and frames[1].data.state or ""
check("the next force reaches the wire", #frames > 0)
check("and Neuro reads the observation line in it",
  state:find("Observed this run, by roster number", 1, true) ~= nil
    and state:find("1. Mult", 1, true) ~= nil, state:sub(1, 400))

joker:remove()
check("a sold joker's observation is pruned", (G.NEURO.joker_observations or {})[7] == nil)

local calc_before, eval_before = Card.calculate_joker, _G.eval_card
require("core.bridge_init").run()
check("a second boot wraps nothing again", Card.calculate_joker == calc_before and _G.eval_card == eval_before)
done()
