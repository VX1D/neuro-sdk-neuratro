
_G.NEURO_TEST = true
local _clock = 0
if not love then love = { timer = { getTime = function() _clock = _clock + 5; return _clock end } } end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }
local STATE_ID = {}

local A = require("core.actions")
local D = require("core.dispatcher")
local Config = require("core.config")
local Enforce = require("core.enforce")

local TD = require("tests.test_deadlock")

local SEED  = tonumber(arg and arg[1]) or 20260722
local ITERS = tonumber(arg and arg[2]) or 4000
math.randomseed(SEED)
local function ri(a, b) return math.random(a, b) end
local function pick(t) return t[ri(1, #t)] end

local FORBIDDEN = {
  "decision_window", "soft_reject", "hard_reject", "not_in_state", "unknown_action",
  "resolving name", "unavailable name", "throttle", "transitioning",
  "state=", "name=",
}

local function folded(s) return (tostring(s):lower():gsub("[_%s]+", " ")) end
local FORBIDDEN_FOLDED = {}
for i = 1, #FORBIDDEN do FORBIDDEN_FOLDED[i] = folded(FORBIDDEN[i]) end

local function make_bridge()
  local b = { emitted = {}, last_context_full = nil, last_context_spoken = false, llm_paused = false,
    _recent_silent = {}, _recent_silent_q = {},
    dispatcher = D, actions = A, persona = "neuro", reserved_dollars = 0,
  shop_reroll_count = 0, state_enter_serial = 1 }
  function b:send_context(message, silent) self.emitted[#self.emitted + 1] = message or "" end
  b.register_actions = function() end
  b.send = function() end
  b.is_transition_cooldown = function() return false end
  return b
end

local REAL = { "play_hand", "discard_hand", "select_blind", "skip_blind", "leave_shop",
  "buy_from_shop", "sell_card", "use_consumable", "record_plan", "set_joker_order", "reroll_shop",
  "cash_out", "start_run", "choose_persona", "skip_pack" }

local WIPE = { "hand","jokers","consumeables","shop_jokers","shop_vouchers","shop_booster","shop","pack_cards","booster_pack","blind_select_opts","blind_select","OVERLAY_MENU" }
local function fresh_g()
  for _, k in ipairs(WIPE) do G[k] = nil end
  G.NEURO = { dispatcher = D, actions = A, persona = "neuro", reserved_dollars = 0, shop_reroll_count = 0,
  state_enter_serial = (tonumber(G.NEURO and G.NEURO.state_enter_serial) or 0) + 5 }
end

local leaks, corrections, crashes = {}, 0, 0
local function run_iteration(it)
  fresh_g()
  local sc = pick(TD.SCENARIOS)
  local built = pcall(function()
    TD.apply_mock(sc.mock())
    if G.NEURO.persona == nil then G.NEURO.persona = "neuro" end

  end)
  if not built then crashes = crashes + 1; return end
  STATE_ID[sc.state] = STATE_ID[sc.state] or (#REAL + it)
  G.STATES = G.STATES or {}; G.STATES[sc.state] = STATE_ID[sc.state]; G.STATE = STATE_ID[sc.state]
  local b = make_bridge(); G.NEURO = b

  local wrong = (sc.state == "SELECTING_HAND") and { "buy_from_shop", "reroll_shop" }
    or (sc.state == "SHOP") and { "play_hand", "discard_hand" }
    or { "play_hand", "buy_from_shop", "leave_shop" }
  local names = { "bogus_action_" .. it }
  for _, w in ipairs(wrong) do names[#names + 1] = w end
  for _, r in ipairs(REAL) do names[#names + 1] = r end     -- some will gate / be unavailable in this state
  local rep = pick(REAL)
  for _ = 1, 12 do names[#names + 1] = rep end              -- trip throttle_repeat
  for _, name in ipairs(names) do
    pcall(Enforce.pre_action, b, name)
    local staged = Enforce.take_correction()
    if staged then b.emitted[#b.emitted + 1] = staged end
  end

  for _, msg in ipairs(b.emitted) do
    corrections = corrections + 1
    local low = folded(msg)
    for i, tok in ipairs(FORBIDDEN) do
      if low:find(FORBIDDEN_FOLDED[i], 1, true) then
        leaks[#leaks + 1] = { it = it, state = sc.state, token = tok, msg = msg }
        break
      end
    end
  end
end
for it = 1, ITERS do run_iteration(it) end

local function banner(s) print(("="):rep(90)); print(s); print(("="):rep(90)) end
banner(string.format("CORRECTION-SCAN FUZZ  seed=%d iters=%d corrections=%d leaks=%d crashes=%d",
  SEED, ITERS, corrections, #leaks, crashes))
print("leak = a rejection correction shown to the model contains a raw internal token (jargon)\n")

if #leaks > 0 then
  banner("TOKEN LEAKS (raw internal reason reached the model's readable context)")
  local seen = {}
  for _, lk in ipairs(leaks) do seen[lk.token] = (seen[lk.token] or 0) + 1 end
  for tok, n in pairs(seen) do print(string.format("  '%s' x%d", tok, n)) end
  print("\n  sample: " .. tostring(leaks[1].msg):sub(1, 140))
end

print()
print(string.format("==== correction-scan: %d leak(s) over %d corrections, %d crash(es) ====",
  #leaks, corrections, crashes))
if crashes > 0 then os.exit(2) end        -- a scenario that blew up was never scanned at all
if corrections == 0 then os.exit(2) end   -- couldn't drive anything = harness broken
if #leaks > 0 and os.getenv("FAIL_ON_FINDINGS") == "1" then os.exit(1) end
