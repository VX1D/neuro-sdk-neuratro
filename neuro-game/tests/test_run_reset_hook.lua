_G.NEURO_TEST = true
require("tests.stubs").setup({ love = "timers" })

local check, done = require("tests.helpers").harness("run-reset-hook")
local Lifecycle = require("core.neuro_lifecycle")
local BridgeInit = require("core.bridge_init")

local resets = 0
Lifecycle.withdraw_open_force = function() end
Lifecycle.bump_run_generation = function() resets = resets + 1 end
Lifecycle.reset_run_state = function() end

local started = 0
_G.Game = { start_run = function() started = started + 1 end }
_G.G = { NEURO = {}, FUNCS = {} }
local deferred
G.FUNCS.start_run = function() deferred = function() Game.start_run(G) end end
G.FUNCS.start_challenge_run = function() Game.start_run(G) end
BridgeInit.hook_run_reset()

Game.start_run(G)
check("a run started directly (Steamodded quick restart) resets the run", resets == 1 and started == 1, resets)

resets = 0
G.FUNCS.start_run()
check("the start button resets at once, before the run begins", resets == 1, resets)
deferred()
check("and the run it starts later does not reset again", resets == 1 and started == 2, resets)

resets = 0
G.FUNCS.start_challenge_run()
check("a button that starts the run in the same call resets once", resets == 1 and started == 3, resets)

resets = 0
Game.start_run(G)
check("a later direct start still resets", resets == 1, resets)

done()
