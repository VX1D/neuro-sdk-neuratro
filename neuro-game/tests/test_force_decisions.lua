love = setmetatable({ timer = { getTime = function() return 100 end } },
  { __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
_G.G = { NEURO = {}, TIMERS = { REAL = 100 }, GAME = {}, STATES = {}, STATE = 0 }

local check, done = require("tests.helpers").harness("force-decisions")

local src = io.open("core/orchestrator.lua", "r"):read("*a")

local opts = src:match("{%s*priority%s*=%s*[^}]*}")
check("force defaults to ephemeral_context = true (SPECIFICATION.md:156, owner decision)",
  opts ~= nil and opts:find("ephemeral_context = p.ephemeral_context ~= false", 1, true) ~= nil, opts)

local FH = require("force.force_helpers")
check("an ordinary decision is low", FH.force_priority("SELECTING_HAND", false) == "low",
  FH.force_priority("SELECTING_HAND", false))
check("a round-blocking decision is medium",
  FH.force_priority("BLIND_SELECT", false) == "medium" and FH.force_priority("ROUND_EVAL", false) == "medium",
  FH.force_priority("BLIND_SELECT", false))
check("an overlay covering the board is high", FH.force_priority("SHOP", true) == "high",
  FH.force_priority("SHOP", true))
check("RUN_SETUP with overlay is low (deck selection does not escalate)", FH.force_priority("RUN_SETUP", true) == "low",
  FH.force_priority("RUN_SETUP", true))
check("GAME_OVER is high", FH.force_priority("GAME_OVER", false) == "high",
  FH.force_priority("GAME_OVER", false))
do
  local worst, states = "low", { "SELECTING_HAND", "SHOP", "BLIND_SELECT", "ROUND_EVAL",
    "GAME_OVER", "MENU", "TAROT_PACK", "BUFFOON_PACK", "STANDARD_PACK", "UNKNOWN", "" }
  local rank = { low = 1, medium = 2, high = 3, critical = 4 }
  for _, st in ipairs(states) do
    for _, ov in ipairs({ true, false }) do
      local pr = FH.force_priority(st, ov)
      if (rank[pr] or 0) > (rank[worst] or 0) then worst = pr end
    end
  end
  check("critical never reaches the wire", worst ~= "critical", worst)
end
check("priority is not hardcoded as a literal in the orchestrator",
  select(2, src:gsub('priority%s*=%s*"', "")) == 0)

local stable = src:match("local function maybe_emit_permanent_rules.-\nend")
check("the permanent rule frame goes through ContextDelivery.rule",
  stable ~= nil and stable:find("ContextDelivery.rule", 1, true) ~= nil)
local gloss = src:match("local function emit_state_glossary.-\nend")
check("the rule glossary goes through the retention channel",
  gloss ~= nil and gloss:find("send_glossary", 1, true) ~= nil
    and src:find("ContextDelivery.rule(key, text)", 1, true) ~= nil)

check("SPECIFICATION.md:93: orchestrator has no untyped direct context send",
  src:find("send_context", 1, true) == nil)
check("SPECIFICATION.md:93: retained rules and historical outcomes use distinct typed calls",
  src:find("ContextDelivery.rule", 1, true) ~= nil
    and src:find("ContextDelivery.event", 1, true) ~= nil
    and src:find("ContextDelivery.prompt", 1, true) ~= nil)
check("spoken outcomes opt in through the prompt type",
  src:find('ContextDelivery.prompt_at("outcome"', 1, true) ~= nil)

local Protocol = require("core.bridge_protocol")
check("bridge_protocol: a missing silent flag means SPOKEN -- hence `not spoken`, never `silent`",
  Protocol.context("m", nil).data.silent == false)
check("bridge_protocol: `not spoken` with spoken=nil is a silent context",
  Protocol.context("m", not nil).data.silent == true)

-- SPECIFICATION.md:184+188 -- code for an action from a stale generation must not retry a force
-- that no longer exists after a run reset.
local AR = require("core.action_result")
check("STALE_GENERATION carries the acknowledge flag (SPECIFICATION.md:188 Tip)",
  AR.acknowledges("STALE_GENERATION") == true)
check("transient transition codes also acknowledge",
  AR.acknowledges("TRANSITION_ACKNOWLEDGED") == true)
check("a purely schematic code does NOT acknowledge -- retry is productive there",
  AR.acknowledges("SCHEMA_INVALID") == false)

local fbs = io.open("force/force_blind_select.lua", "r"):read("*a")
local named_tag_verdict = fbs:find("Investment/Economy", 1, true) ~= nil
  or fbs:find("Boss/Double tag usually", 1, true) ~= nil
  or fbs:find("free pack, Investment", 1, true) ~= nil
check("skip_blind advice does not name specific tag types with a ranking verdict",
  not named_tag_verdict, fbs:match("Skip when that tag[^\"]*"))
check("the general skip-vs-payout tradeoff rule is still present (category, not build-specific)",
  fbs:find("Skip when that tag is worth more than the payout", 1, true) ~= nil)

done()
