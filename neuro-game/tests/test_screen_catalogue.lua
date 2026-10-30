require("tests.stubs").setup({ love = "timers", localize = true })
local ES = require("tests.engine_cards").states()

local check, done = require("tests.helpers").harness("screen-catalogue")
local TmpWork = require("tests.tmp_workdir")
local ipc_dir = TmpWork.open("screen_catalogue")
require("core.mod_paths").read_ipc_dir = function() return ipc_dir end
_G.G = { P_CENTERS = require("tests.engine_centers").centers(), TIMERS = { REAL = 100, TOTAL = 100 },
  GAME = { current_round = {} }, FUNCS = {}, STATES = ES, STATE = ES.MENU, SETTINGS = {} }

local Orchestrator = require("core.orchestrator")
local Registry = require("core.action_registry")
local Actions = require("core.actions")
local Window = require("core.window")
local json = require("util.neuro_json")
Orchestrator._step_bridge_init()
assert(G.NEURO and G.NEURO._bridge_init_complete, "bridge init")

local function frames()
  local count = { ["actions/register"] = 0, ["actions/unregister"] = 0 }
  local f = io.open(ipc_dir .. "/neuro_outbox.jsonl", "r")
  for line in (f and f:lines() or function() end) do
    local ok, msg = pcall(json.decode, line)
    if ok and type(msg) == "table" and count[msg.command] then count[msg.command] = count[msg.command] + 1 end
  end
  if f then f:close() end
  return count
end

local function enter(state)
  G.STATE = ES[state]
  Window.register_catalogue()
end

local function registered_exactly(state)
  local want = Actions.screen_action_set(state)
  for name in pairs(want) do
    if Actions.registrable(name) and not Registry.is_registered(name) then return false, "missing " .. name end
  end
  for name in pairs(G.NEURO._registered_sigs) do
    if not (want[name] and Actions.registrable(name)) then return false, "extra " .. name end
  end
  return true
end

check("the menu registers the menu's actions", registered_exactly("MENU"))

enter("BLIND_SELECT")
check("blind select registers exactly its own actions", registered_exactly("BLIND_SELECT"))
check("run-setup tools are gone once a run is under way",
  not Registry.is_registered("toggle_seeded_run") and not Registry.is_registered("paste_seed")
    and not Registry.is_registered("select_deck") and not Registry.is_registered("select_stake"))

for _, state in ipairs({ "SELECTING_HAND", "ROUND_EVAL", "SHOP", "SMODS_BOOSTER_OPENED", "SHOP", "BLIND_SELECT" }) do
  enter(state)
  check(state .. " registers exactly its own actions", registered_exactly(state))
end

enter("SELECTING_HAND")
local before = frames()
enter("HAND_PLAYED")
enter("DRAW_TO_HAND")
local after = frames()
check("a transitional state keeps the last screen's actions without registration frames",
  after["actions/register"] == before["actions/register"] and after["actions/unregister"] == before["actions/unregister"]
    and registered_exactly("SELECTING_HAND"),
  string.format("register +%d, unregister +%d", after["actions/register"] - before["actions/register"],
    after["actions/unregister"] - before["actions/unregister"]))

local offered = { "choose_persona" }
G.STATE = ES.SHOP
Window.register_catalogue(offered)
check("a force's offer is registered even outside its screen", Registry.is_registered("choose_persona"))

enter("GAME_OVER")
check("game over registers exactly its own actions; starting a run needs run setup open",
  registered_exactly("GAME_OVER") and not Registry.is_registered("start_run") and not Registry.is_registered("play_hand"))

G.STATE = ES.BLIND_SELECT
G.GAME.round_resets = { blind_states = { Small = "Defeated", Big = "Defeated", Boss = "Select" },
  blind_choices = { Boss = "bl_hook" }, blind_tags = {} }
G.GAME.blind_on_deck = "Boss"
Window.register_catalogue()
check("with the boss up and no reroll voucher, neither skipping nor rerolling it is registered",
  not Registry.is_registered("skip_blind") and not Registry.is_registered("reroll_boss"))
G.GAME.used_vouchers, G.GAME.dollars = { v_directors_cut = true }, 20
Window.register_catalogue()
check("the boss reroll is registered once the voucher allows it", Registry.is_registered("reroll_boss"))

G.NEURO.persona = "neuro"
G.PROFILES, G.SETTINGS.profile = { { all_unlocked = true } }, 1
G.P_CENTER_POOLS = { Back = { { key = "b_red", name = "Red Deck", set = "Back" } }, Stake = { { key = "stake_white" } } }
enter("MENU")
check("with one deck and one stake, neither picker is registered",
  not Registry.is_registered("select_deck") and not Registry.is_registered("select_stake"))
G.P_CENTER_POOLS.Back[2] = { key = "b_blue", name = "Blue Deck", set = "Back" }
G.P_CENTER_POOLS.Stake[2] = { key = "stake_red" }
Window.register_catalogue()
check("each picker is registered once it has a choice",
  Registry.is_registered("select_deck") and Registry.is_registered("select_stake"))
G.P_CENTER_POOLS = nil

G.NEURO.persona = "hiyori"
enter("MENU")
check("the persona tool is registered while no persona is set", Registry.is_registered("choose_persona"))
G.NEURO.persona = "neuro"
enter("GAME_OVER")
check("the persona tool is not registered once the persona is set", not Registry.is_registered("choose_persona"))

G.OVERLAY_MENU = { config = {}, get_UIE_by_ID = function(_, id) return id == "run_setup_seed" and {} or nil end }
enter("MENU")
local setup = frames()
G.OVERLAY_MENU, G.screenwipe = nil, {}
enter("MENU")
check("the screen wipe after starting a run registers nothing of the menu it passes through",
  not Registry.is_registered("open_run_setup") and frames()["actions/register"] == setup["actions/register"])
G.screenwipe = nil

done()
