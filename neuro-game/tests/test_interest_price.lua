_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
_G.localize = function() return "" end

local check, done = require("tests.helpers").harness("interest-price")

local CtxShop = require("context.ctx_shop")

local function shop_G(dollars, opts)
  opts = opts or {}
  _G.G = {
    STATE = 5, STATES = { SHOP = 5 },
    NEURO = { reserved_dollars = 0, once_serials = {} },
    FUNCS = {},
    GAME = {
      dollars = dollars,
      interest_cap = opts.cap or 25,
      interest_amount = opts.amount,
      round = 1,
      round_resets = { ante = 2, blind_choices = {} },
      current_round = { free_rerolls = 0, reroll_cost = 5, discards_left = 0, hands_left = 0 },
      modifiers = opts.no_interest and { no_interest = true } or {},
    },
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
    shop_jokers = { cards = {} },
    shop_vouchers = { cards = {} },
    shop_booster = { cards = {} },
  }
end

local function baron(cost)
  return {
    ability = { name = "Baron", set = "Joker" },
    cost = cost,
    config = { center = { key = "j_baron", set = "Joker", rarity = 3, loc_txt = { name = "Baron" } } },
  }
end

local function joker_row(dollars, cost, opts)
  shop_G(dollars, opts)
  G.shop_jokers = { cards = { baron(cost) } }
  local sec = CtxShop.shop_section() or ""
  for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, 20) == "shop jokers slot 1: " then return line end
  end
  return sec
end

local GOLD_FREE = "shop jokers slot 1: Baron (Joker, Rare) $3, affordable now: yes, free slot: yes, lands rightmost (joker slot 1)"
local GOLD_ONE = "shop jokers slot 1: Baron (Joker, Rare) $2, affordable now: yes, free slot: yes, lands rightmost (joker slot 1), interest cost: $1"
local GOLD_MANY = "shop jokers slot 1: Baron (Joker, Rare) $17, affordable now: yes, free slot: yes, lands rightmost (joker slot 1), interest cost: $4"

local row_free = joker_row(9, 3)
check("a buy that crosses no interest step carries no interest field",
  row_free == GOLD_FREE, row_free)

local row_one = joker_row(10, 2)
check("a buy that drops one step reads the exact step value",
  row_one == GOLD_ONE, row_one)

local row_many = joker_row(20, 17)
check("a buy that drops four steps reads the summed value, not one step",
  row_many == GOLD_MANY, row_many)

check("the interest field closes the price fields, after the slot field",
  row_many:find("lands rightmost (joker slot 1), interest cost: $4", 1, true) ~= nil, row_many)

local row_cap = joker_row(30, 3)
check("spending above the cap costs no interest -- field stays away",
  row_cap:find("interest cost", 1, true) == nil, row_cap)

local row_over_cap = joker_row(30, 10)
check("a buy that pushes the bank back under the cap is priced from the capped bank",
  row_over_cap:find("interest cost: $1", 1, true) ~= nil, row_over_cap)

local row_off = joker_row(20, 17, { no_interest = true })
check("no field while the run pays no interest",
  row_off:find("interest cost", 1, true) == nil, row_off)

local row_debt = joker_row(-5, 3)
check("no field while the bank is under water",
  row_debt:find("interest cost", 1, true) == nil, row_debt)

local row_rate = joker_row(10, 6, { amount = 2 })
check("the field follows the run's interest rate, not a hardcoded $1 per step",
  row_rate:find("interest cost: $4", 1, true) ~= nil, row_rate)

do
  shop_G(20)
  G.shop_booster = { cards = {
    { ability = { set = "Booster", name = "Buffoon Pack" }, cost = 4,
      config = { center = { kind = "Buffoon", set = "Booster", key = "p_buffoon_normal_1" } } },
  } }
  local sec = CtxShop.shop_section() or ""
  local bline
  for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
    if line:sub(1, 21) == "shop booster slot 1: " then bline = line end
  end
  check("pack rows are priced in interest too (they spend the same bank)",
    bline ~= nil and bline:find("interest cost: $1", 1, true) ~= nil, bline or sec)
end

do
  local CtxEconomy = require("facts.economy_facts")
  local wrong, rows = 0, 0
  for dollars = 0, 40, 1 do
    for cost = 0, 20, 1 do
      shop_G(dollars)
      G.shop_jokers = { cards = { baron(cost) } }
      local sec = CtxShop.shop_section() or ""
      for line in (sec .. "\n"):gmatch("([^\n]*)\n") do
        if line:sub(1, 20) == "shop jokers slot 1: " then
          rows = rows + 1
          local truth = CtxEconomy.calc_interest(dollars) - CtxEconomy.calc_interest(dollars - cost)
          local shown = tonumber(line:match("interest cost: %$(%d+)")) or 0
          if shown ~= truth then wrong = wrong + 1 end
        end
      end
    end
  end
  check("sweep: every row's interest field equals the engine's own step difference",
    rows > 0 and wrong == 0, string.format("rows=%d wrong=%d", rows, wrong))
end

done()
