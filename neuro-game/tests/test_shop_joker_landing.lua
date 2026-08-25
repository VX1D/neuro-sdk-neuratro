_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("shop-joker-landing")

local CtxShop = require("context.ctx_shop")
local GameRules = require("context.game_rules")

local function joker(name, key, cost, rarity)
  return {
    ability = { name = name, set = "Joker" }, cost = cost,
    config = { center = { key = key, set = "Joker", rarity = rarity or 1,
      loc_txt = { name = name } } },
  }
end

local function board(owned, limit, dollars)
  local mine = {}
  for i = 1, owned do mine[i] = joker("Owned " .. i, "j_joker", 2) end
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    NEURO = { reserved_dollars = 0, once_serials = {} },
    FUNCS = {},
    GAME = { dollars = dollars or 12, interest_cap = 25, round = 1,
      round_resets = { ante = 1, blind_choices = {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 },
      modifiers = {} },
    jokers = { cards = mine, config = { card_limit = limit or 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = { joker("Blueprint", "j_blueprint", 10, 3) } },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {} },
  }
end

local function row()
  local sec = CtxShop.shop_section() or ""
  for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, 20) == "shop jokers slot 1: " then return line end
  end
  return sec
end

board(0, 5)
local empty = row()
check("with no jokers owned the row names slot 1",
  empty:find("lands rightmost (joker slot 1)", 1, true) ~= nil, empty)

board(3, 5)
local three = row()
check("the landing slot follows the roster size, it is not a constant",
  three:find("lands rightmost (joker slot 4)", 1, true) ~= nil, three)

board(4, 5)
check("and again one slot further along",
  row():find("lands rightmost (joker slot 5)", 1, true) ~= nil, row())

board(5, 5)
local full = row()
check("with slots full the row still says rightmost (a sell frees the LAST slot too)",
  full:find("lands rightmost", 1, true) ~= nil, full)
check("and claims no slot number it cannot know",
  full:find("joker slot", 1, true) == nil, full)

board(2, 5)
G.shop_vouchers = { cards = { { ability = { name = "Overstock", set = "Voucher" }, cost = 10,
  config = { center = { key = "v_overstock", set = "Voucher" } } } } }
local sec = CtxShop.shop_section() or ""
local voucher_line
for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
  if line:sub(1, 22) == "shop vouchers slot 1: " then voucher_line = line end
end
check("non-joker rows carry no landing fact",
  voucher_line ~= nil and voucher_line:find("lands rightmost", 1, true) == nil,
  tostring(voucher_line))

board(2, 5)
G.shop_jokers = { cards = { { ability = { name = "The Tower", set = "Tarot" }, cost = 3,
  config = { center = { key = "c_tower", set = "Tarot", loc_txt = { name = "The Tower" } } } } } }
local tarot_row = row()
check("a consumable in the shop_jokers row carries no joker landing fact",
  tarot_row:find("lands rightmost", 1, true) == nil, tarot_row)

board(1, 5)
local frame = GameRules.invariant_frame()
check("the permanent frame resolves left/right instead of saying 'next to'",
  frame:find("rightmost joker slot, with no joker to its right", 1, true) ~= nil, frame)
check("the old unresolvable wording is gone",
  frame:find("next to your old ones", 1, true) == nil, frame)
check("the run frame does not restate the landing rule on every force",
  GameRules.run_frame_text():find("rightmost joker slot", 1, true) == nil,
  GameRules.run_frame_text())

done()
