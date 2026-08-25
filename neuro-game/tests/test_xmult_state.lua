_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("xmult-state")
local Scoring = require("util.scoring")

local function jk(key, xmult)
  local ab = { set = "Joker" }
  if xmult then ab.x_mult = xmult end
  return { ability = ab, config = { center = { key = key, set = "Joker", rarity = 1 } } }
end

_G.G = { jokers = { cards = {}, config = { card_limit = 5 } }, GAME = {}, consumeables = { cards = {} } }

G.jokers.cards = { jk("j_joker") }
check("none: flat joker (no xMult) -> none", Scoring.owned_xmult_state() == "none", Scoring.owned_xmult_state())

G.jokers.cards = { jk("j_blackboard") } -- X3 Mult if all held cards are Spades/Clubs (conditional)
check("conditional: Blackboard -> conditional (NOT none)", Scoring.owned_xmult_state() == "conditional", Scoring.owned_xmult_state())

G.jokers.cards = { jk("j_baron") } -- X1.5 Mult per King held (conditional)
check("conditional: Baron -> conditional", Scoring.owned_xmult_state() == "conditional", Scoring.owned_xmult_state())

G.jokers.cards = { jk("j_hologram", 2) } -- always-on x2
check("guaranteed: Hologram x2 -> guaranteed", Scoring.owned_xmult_state() == "guaranteed", Scoring.owned_xmult_state())

local bb = jk("j_blackboard"); bb.debuff = true
G.jokers.cards = { bb }
check("debuffed conditional xMult -> none", Scoring.owned_xmult_state() == "none", Scoring.owned_xmult_state())

done()
