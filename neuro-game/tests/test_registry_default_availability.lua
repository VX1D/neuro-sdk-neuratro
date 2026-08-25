_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("registry-default-availability")

_G.G = {
  STATE = 1, STATES = { SHOP = 1 }, GAME = { dollars = 0, current_round = {}, round_resets = {} },
  NEURO = { run_generation = 1, _decision_windows = {} }, FUNCS = {},
  jokers = { cards = {}, config = { card_limit = 5 } },
  consumeables = { cards = {}, config = { card_limit = 2 } },
}

require("core.actions")
require("core.dispatcher")
local ActionRegistry = require("core.action_registry")

check("validate accepts the loaded action set",
  ActionRegistry.validate({ require_preflights = true }) == true)

ActionRegistry.register({
  name = "default_availability_probe",
  description = "Probe the registry default.",
  schema = { type = "object", properties = {} },
})
local probe = ActionRegistry.get("default_availability_probe")
check("get installs a callable default availability predicate",
  type(probe.available) == "function" and probe.available() == true)
check("available uses the same permissive default for a registered action without a predicate",
  ActionRegistry.available("default_availability_probe") == true)

done()
