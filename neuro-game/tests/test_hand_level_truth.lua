_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local H = require("tests.helpers")
local check, done = H.harness("hand-level truth")

local function hands()
  return {
    Pair = { level = 3, chips = 30, mult = 6, l_chips = 10, l_mult = 2, s_chips = 10, s_mult = 2,
             played = 5, visible = true },
    ["High Card"] = { level = 1, chips = 5, mult = 1, l_chips = 10, l_mult = 1, s_chips = 5,
                      s_mult = 1, played = 2, visible = true },
  }
end

local function setup(opts)
  opts = opts or {}
  _G.G = {
    STATE = 1, STATES = { SELECTING_HAND = 1, SHOP = 2 },
    hand = { cards = {}, config = { card_limit = 8, highlighted_limit = 5 } },
    deck = { cards = {} }, jokers = nil, FUNCS = {},
    P_CENTERS = { b_plasma = { key = "b_plasma", name = "Plasma Deck" } },
    GAME = {
      hands = hands(),
      current_round = { discards_left = 3, hands_left = 4 },
      blind = opts.blind or {},
      selected_back = opts.back,
    },
  }
end

local HF = require("facts.hand_facts")

local function pair_row()
  for _, r in ipairs(HF.levels()) do if r.name == "Pair" then return r end end
  return nil
end

do
  setup()
  local r = pair_row()
  check("no boss: the Pair row is the table's own level 3 / 30 / 6",
    r and r.level == 3 and r.chips == 30 and r.mult == 6,
    r and (r.level .. "/" .. r.chips .. "/" .. r.mult) or "<no Pair row>")

  setup({ blind = { name = "The Arm", key = "bl_arm", in_blind = true, disabled = false, debuff = {} } })
  local a = pair_row()
  check("The Arm: the Pair row is reported at the level it will score at (2 / 20 / 4)",
    a and a.level == 2 and a.chips == 20 and a.mult == 4,
    a and (a.level .. "/" .. a.chips .. "/" .. a.mult) or "<no Pair row>")

  local hc
  for _, row in ipairs(HF.levels()) do if row.name == "High Card" then hc = row end end
  check("The Arm: a level-1 hand is untouched (blind.lua:594 gates on level > 1)",
    hc and hc.level == 1 and hc.chips == 5 and hc.mult == 1,
    hc and (hc.level .. "/" .. hc.chips .. "/" .. hc.mult) or "<no High Card row>")

  check("The Arm: the header note names the drop, as Flint's halving is named",
    table.concat(HF.level_notes(), "; "):find("Arm", 1, true) ~= nil,
    table.concat(HF.level_notes(), "; "))

  setup({ blind = { name = "The Arm", key = "bl_arm", in_blind = true, disabled = true, debuff = {} } })
  local d = pair_row()
  check("a disabled Arm changes nothing (blind.lua:560 self.disabled)",
    d and d.level == 3 and d.chips == 30 and d.mult == 6,
    d and (d.level .. "/" .. d.chips .. "/" .. d.mult) or "<no Pair row>")
  check("a disabled Arm emits no header note", #HF.level_notes() == 0,
    table.concat(HF.level_notes(), "; "))

  setup({ blind = { name = "The Arm", key = "bl_arm", disabled = false, debuff = {} } })
  local past = pair_row()
  check("a boss that is no longer in play shapes nothing",
    past and past.level == 3 and #HF.level_notes() == 0,
    past and (past.level .. "/" .. past.chips .. "/" .. past.mult) or "<no Pair row>")
end

do
  setup({ blind = { name = "The Arm", key = "bl_arm", in_blind = true, disabled = false, debuff = {} } })
  local RID, VALN = H.RID, H.VALN
  local function card(v, suit)
    local id = RID[v]
    return { base = { value = VALN[v] or v, suit = suit }, config = { center = { key = "c_base" } },
      get_id = function() return id end, is_suit = function(_, s) return s == suit end }
  end
  local kh, kd = card("K", "Hearts"), card("K", "Diamonds")
  G.hand.cards = { kh, kd, card("3", "Spades"), card("7", "Clubs"), card("9", "Hearts") }
  G.FUNCS.get_poker_hand_info = function() return nil, nil, { Pair = { { kh, kd } } } end
  local s = HF.summary()
  check("The Arm: the Ready row quotes the dropped level, not the table's",
    s:find("(lv2 20c x4)", 1, true) ~= nil and s:find("lv3", 1, true) == nil, s)
end

local CtxHand = require("context.ctx_hand")

do
  setup()
  local plain = CtxHand.levels_section()
  check("no deck effect: the Pair product is chips x mult",
    plain:find("30 chips x 6 mult = 180", 1, true) ~= nil, plain)

  setup({ back = { key = "b_plasma" } })
  local plasma = CtxHand.levels_section()
  check("Plasma: the header note is still there",
    plasma:find("Plasma deck", 1, true) ~= nil, plasma)
  check("Plasma: the printed product follows the balance the header describes",
    plasma:find("= 324", 1, true) ~= nil and plasma:find("= 180", 1, true) == nil, plasma)
  check("Plasma: the unbalanced factors are still printed, since cards and jokers land before the balance",
    plasma:find("30 chips x 6 mult", 1, true) ~= nil, plasma)
end

done()
