_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("confirm-turn-payload")
local H = require("tests.helpers")
local LB = require("tests.fixtures.live_board")
local Evidence = require("core.confirmation_evidence")
local FactHints = require("facts.fact_hints")

local BOARD = "Normal: 5 cards, 4 hands, 3 discards"

local function board()
  LB.load("SELECTING_HAND", BOARD)
  G.NEURO.run_generation = 1
  G.NEURO.decision_serial = 5
  G.NEURO.once_serials = {}
  G.NEURO.session_once_serials = {}
  Evidence.clear()
end

local function force()
  FactHints.reset_pending()
  local built = require("force.force_selecting_hand").build()
  local q = (type(built) == "table" and built.query) or ""
  return q, H.drain_hints()
end

local function arm()
  local sig = {}
  for i = 1, 2 do sig[#sig + 1] = tostring(G.hand.cards[i].sort_id) end
  local signature = table.concat(sig, ",")
  G.NEURO.play_confirm = {
    signature = signature, content = "sealed", indices = { 1, 2 },
    decision_serial = G.NEURO.decision_serial, run_generation = G.NEURO.run_generation,
  }
  local candidate = Evidence.candidate(signature, "sealed", { 1, 2 }, "Pair")
  local receipt = { status = "written" }
  assert(Evidence.stage(candidate, "Committing Pair -- 300 to clear. Send the same indices again to commit this play.", receipt))
  assert(Evidence.step_delivery())
end

board()
local plain = force()
check("the plain force is the full decision prompt", #plain > 0 and plain:find("Rules: 1)", 1, true) ~= nil, plain:sub(1, 120))

board()
arm()
local confirming = force()

check("the confirm turn carries the engine verdict it is asking about",
  confirming:find("Committing Pair", 1, true) ~= nil, confirming)
check("the confirm turn offers confirm_play", confirming:find("confirm_play", 1, true) ~= nil, confirming)

local TEACHING = {
  ["the numbered rules block"] = "Rules: 1)",
  ["the copy-order chain"] = "Joker copy order:",
  ["the consumable route"] = "To use a targeting consumable",
  ["the first-play gate note"] = "spends nothing and comes back",
}
for label, mark in pairs(TEACHING) do
  check("the confirm turn drops " .. label,
    confirming:find(mark, 1, true) == nil, confirming)
end

local FACTS = {
  ["the shape summary"] = "Shape:",
  ["the hand-index range"] = "Hand card indices:",
  ["the move line"] = "Your move:",
  ["the chips/hands/discards move cue"] = "You still need",
}
for label, mark in pairs(FACTS) do
  check("the confirm turn keeps " .. label,
    confirming:find(mark, 1, true) ~= nil, confirming)
end

check("the confirm turn is smaller than the decision it repeats",
  #confirming < #plain, tostring(#confirming) .. " vs " .. tostring(#plain))

board()
arm()
force()
Evidence.clear()
G.NEURO.play_confirm = nil
local after = force()
check("a confirm turn does not spend the round's rules gate",
  after:find("Rules: 1)", 1, true) ~= nil, after)

do
  local RULE = "Discards are a separate pool that costs no hand%-slot"
  local owners = {}
  for _, path in ipairs({ "facts/fact_hints.lua", "force/force_selecting_hand.lua",
      "handlers/hand_handlers.lua" }) do
    local fh = io.open(path, "r")
    local src = fh and fh:read("*a") or ""
    if fh then fh:close() end
    if src:find(RULE) then owners[#owners + 1] = path end
  end
  check("the discard-pool rule has exactly one owner",
    #owners == 1 and owners[1] == "handlers/hand_handlers.lua", table.concat(owners, ", "))
  check("and that owner publishes it",
    require("handlers.hand_handlers").DISCARD_POOL_RULE
      == "Discards are a separate pool that costs no hand-slot")
end

done()
