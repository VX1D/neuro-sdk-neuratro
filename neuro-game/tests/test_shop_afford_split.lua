_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("shop-afford-split")

local REROLL_DEF_GOLD =
  "Replace the current shop jokers with a new random set, not the voucher or packs;"
  .. " each reroll costs money and the price rises each time this shop visit."
local REROLL_MOVE_GOLD =
  " (replaces the shop jokers with a new random set, not the voucher or packs)"

local Actions = require("core.actions")

local reroll_def = nil
for _, d in ipairs(Actions.get_static_actions()) do
  if d.name == "reroll_shop" then reroll_def = d end
end

check("reroll_shop action def exists", reroll_def ~= nil)
check("reroll_shop description opens with the corrected joker-only sentence",
  reroll_def ~= nil and reroll_def.description:sub(1, #REROLL_DEF_GOLD) == REROLL_DEF_GOLD,
  reroll_def and reroll_def.description or "-")
check("reroll_shop description never claims vouchers or packs are replaced",
  reroll_def ~= nil
    and reroll_def.description:find("all current shop items", 1, true) == nil
    and reroll_def.description:find("jokers, vouchers, packs", 1, true) == nil,
  reroll_def and reroll_def.description or "-")

local function shop_G(dollars, joker_count, joker_limit)
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    NEURO = { reserved_dollars = 0, once_serials = {} },
    FUNCS = {},
    GAME = {
      dollars = dollars, interest_cap = 25,
      round_resets = { ante = 2, blind_choices = {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 },
      modifiers = {},
    },
    jokers = { cards = {}, config = { card_limit = joker_limit } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {} },
  }
  for _ = 1, joker_count do
    G.jokers.cards[#G.jokers.cards + 1] =
      { ability = { name = "Filler", set = "Joker" }, config = { center = { key = "j_filler", set = "Joker" } } }
  end
end

do
  shop_G(20, 0, 5)
  Actions.is_action_valid = function(n) return n == "reroll_shop" end
  local FS = require("force.force_shop")
  local q = (FS.build() or {}).query or ""
  check("the shop `Your move` line carries the corrected reroll parenthetical",
    q:find(REROLL_MOVE_GOLD, 1, true) ~= nil, q)
  check("the shop `Your move` line never claims all shop items are replaced",
    q:find("replaces all shop items", 1, true) == nil, q)
end

local CtxShop = require("context.ctx_shop")

local function baron()
  return {
    ability = { name = "Baron", set = "Joker" },
    cost = 17,
    config = { center = { key = "j_baron", set = "Joker", rarity = 3, loc_txt = { name = "Baron" } } },
  }
end

local function joker_row(dollars, held_jokers)
  shop_G(dollars, held_jokers, 5)
  G.shop_jokers = { cards = { baron() } }
  local sec = CtxShop.shop_section() or ""
  for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, 20) == "shop jokers slot 1: " then return line end
  end
  return sec
end

local ROW_AFFORD_SLOT = "shop jokers slot 1: Baron (Joker, Rare) $17, affordable now: yes, free slot: yes"
local ROW_AFFORD_NOSLOT = "shop jokers slot 1: Baron (Joker, Rare) $17, affordable now: yes, free slot: no"
local ROW_BROKE = "shop jokers slot 1: Baron (Joker, Rare) $17, affordable now: no, free slot: yes"

local row_a = joker_row(20, 0)
check("cash and a free slot -> affordable yes, free slot yes",
  row_a:sub(1, #ROW_AFFORD_SLOT) == ROW_AFFORD_SLOT, row_a)

local row_b = joker_row(20, 5)
check("cash but slots full -> affordable STAYS yes, free slot no",
  row_b:sub(1, #ROW_AFFORD_NOSLOT) == ROW_AFFORD_NOSLOT, row_b)

local row_c = joker_row(3, 0)
check("no cash -> affordable no",
  row_c:sub(1, #ROW_BROKE) == ROW_BROKE, row_c)

check("a full-slot but cash-affordable row no longer reads 'affordable now: no'",
  row_b:find("affordable now: no", 1, true) == nil, row_b)

do
  shop_G(20, 5, 5)
  G.shop_booster = { cards = {
    { ability = { set = "Booster", name = "Buffoon Pack" }, cost = 4,
      config = { center = { kind = "Buffoon", set = "Booster", key = "p_buffoon_normal_1" } } },
  } }
  local sec = CtxShop.shop_section() or ""
  local bline = nil
  for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, 21) == "shop booster slot 1: " then bline = line end
  end
  check("booster rows carry no slot field (packs have no slot gate)",
    bline ~= nil and bline:find("free slot:", 1, true) == nil, bline or sec)
end

do
  local CtxEconomy = require("facts.economy_facts")
  local lying, rows = 0, 0
  for dollars = 0, 30, 3 do
    for held = 0, 5 do
      for cost = 0, 20, 4 do
        shop_G(dollars, held, 5)
        local c = baron(); c.cost = cost
        G.shop_jokers = { cards = { c } }
        local sec = CtxShop.shop_section() or ""
        for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
          if line:sub(1, 20) == "shop jokers slot 1: " then
            rows = rows + 1
            if line:find("affordable now: no", 1, true) and cost <= CtxEconomy.spendable() then
              lying = lying + 1
            end
          end
        end
      end
    end
  end
  check("sweep: no row says 'affordable now: no' while the cash covers the cost",
    rows > 0 and lying == 0, string.format("rows=%d lying=%d", rows, lying))
end

done()
