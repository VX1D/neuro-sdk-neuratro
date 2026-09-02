_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} } }

local check, done = require("tests.helpers").harness("query-section-reference")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local TD = require("tests.test_deadlock")
local CardUtil = require("facts.card_util")
local Actions = require("core.actions")

local REFERENCES = {
  { phrase = "An owned consumable", section = "Consumables (" },
  { phrase = "the consumables list shows", section = "Consumables (" },
  { phrase = "Boss rule is stated in full on the", section = "Boss blind " },
}

local scanned = 0
for _, board in ipairs(LB.BOARDS) do
  LB.load(board.state, board.desc)
  local first = FP.build(board.state)
  local state_text, query = (first and first.state) or "", (first and first.query) or ""
  for _, ref in ipairs(REFERENCES) do
    if query:find(ref.phrase, 1, true) then
      scanned = scanned + 1
      check("" .. board.state .. ": '" .. ref.phrase .. "' has its section in the payload",
        state_text:find(ref.section, 1, true) ~= nil, query:sub(1, 90))
    end
  end
end
check("the corpus produced at least one section reference to check", scanned > 0, tostring(scanned))

local boss_rows = 0
for _, board in ipairs(LB.BOARDS) do
  LB.load(board.state, board.desc)
  local p = FP.build(board.state)
  local state_text, query = (p and p.state) or "", (p and p.query) or ""
  for row in state_text:gmatch("Boss blind [^\n]*") do
    local effect = row:match("%. Effect: (.+)$")
    if effect then
      effect = effect:gsub("%.$", "")
      boss_rows = boss_rows + 1
      check("" .. board.state .. ": the boss Effect paragraph is not repeated in the query",
        query:find(effect, 1, true) == nil, query:sub(1, 200))
      check("" .. board.state .. ": and the query names the row that carries it",
        query:find("Boss rule is stated in full on the", 1, true) ~= nil, query:sub(1, 200))
    end
  end
end
check("the corpus produced at least one boss row to check", boss_rows > 0, tostring(boss_rows))

local function blocked_consumable_board()
  LB.load("SELECTING_HAND", "Normal: 5 cards, 4 hands, 3 discards")
  G.consumeables.cards = { LB.consumable("c_fool", 950) }
  G.consumeables.config = { card_limit = 1 }
  for _, c in ipairs(G.consumeables.cards) do c.area = G.consumeables end
  G.GAME.last_tarot_planet = nil
  G.FUNCS.get_poker_hand_info = TD.get_poker_hand_info
  require("context.context_compact").invalidate_cache()
  require("facts.fact_hints").reset_pending()
end

blocked_consumable_board()
check("the board really holds a consumable the engine refuses",
  CardUtil.has_blocked_consumable() == true, "has_blocked_consumable")
check("use_consumable really has no candidate on that board",
  Actions.is_action_valid("use_consumable") == false, "use_consumable is offered after all")

local built = FP.build("SELECTING_HAND")
check("the Consumables list is genuinely absent from that payload",
  built.state:find("Consumables (", 1, true) == nil, built.state:sub(-200))
check("the query does not explain the section it was not given",
  built.query:find("An owned consumable", 1, true) == nil,
  (built.query:match("An owned consumable[^%.]*%.") or ""))

done()
