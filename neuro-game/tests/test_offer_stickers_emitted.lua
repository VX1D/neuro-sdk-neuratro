require("tests.stubs").setup({ love = "lazy", G = "board" })

-- Joker stickers appear on offers as well as owned cards, including shop and Buffoon-pack offers.
local H = require("tests.helpers")
local check, done = H.harness("offer stickers: emitted text")

local A = require("core.actions")
local D = require("core.dispatcher")
G.NEURO.dispatcher = D
G.NEURO.actions = A
local TD = require("tests.test_deadlock")
local CR = require("context.context_readable")

local scenario = require("tests.helpers").scenario

local function joker(key, name, ability, area, facing)
  ability.name, ability.set = name, "Joker"
  return { sort_id = math.random(1e6), cost = 6, sell_cost = 3, facing = facing or "front",
    ability = ability, area = area,
    config = { center = { key = key, name = name, set = "Joker", rarity = 1, config = {} } } }
end

local function board(state, desc, setup)
  TD.apply_mock(scenario(desc).mock())
  require("tests.helpers").in_engine_state(state)
  G.NEURO.persona = "neuro"
  G.GAME.rental_rate = 3
  setup()
  return CR.build(state, A.get_valid_actions_for_state(state))
end

do
  local s = board("SHOP", "Normal: affordable joker, affordable booster, $10", function()
    local area = G.shop_jokers
    local rent = joker("j_green_joker", "Green Joker",
      { rental = true, perishable = true, perish_tally = 5, mult = 0 }, area)
    rent.cost = 1
    area.cards = { rent, joker("j_joker", "Joker", { eternal = true, mult = 4 }, area),
      joker("j_joker", "Joker", { eternal = true, mult = 4 }, area, "back") }
  end)
  check("a shop joker shows its Perishable and Rental stickers",
    (require("tests.helpers").area_row(s, "shop_jokers", 1) or ""):find(
      "1. Green Joker (Joker, Common) [perishable, 5 rounds left, rental, $3 per round] $1", 1, true) == 1, s)
  check("a shop joker shows its Eternal sticker",
    (require("tests.helpers").area_row(s, "shop_jokers", 2) or ""):find(
      "2. Joker (Joker, Common) [cannot be sold] $6", 1, true) == 1, s)
  check("a face-down shop joker names no sticker",
    s:find("3. face-down item #3 in shop_jokers -- identity and effect hidden.", 1, true) ~= nil
      and select(2, s:gsub("cannot be sold", "")) == 1, s)
end

do
  local s = board("SMODS_BOOSTER_OPENED", "Buffoon pack with a joker", function()
    local area = G.pack_cards
    area.cards = { joker("j_joker", "Joker", { perishable = true, perish_tally = 5, mult = 4 }, area),
      joker("j_joker", "Joker", { eternal = true, mult = 4 }, area, "back") }
    G.booster_pack = area
  end)
  check("a Buffoon-pack joker shows its Perishable sticker",
    s:find("1. Joker (Joker) [perishable, 5 rounds left]. Takeable now:", 1, true) ~= nil, s)
  check("a face-down pack joker names no sticker",
    s:find("identity and effect hidden", 1, true) ~= nil and s:find("cannot be sold", 1, true) == nil, s)
end

do
  local s = board("SHOP", "Normal: affordable joker, affordable booster, $10", function()
    G.jokers.cards = { joker("j_joker", "Joker", { eternal = true, mult = 4 }, G.jokers) }
  end)
  check("an owned joker's sticker reads the same words as the offer",
    s:find("1. Joker -- +4 Mult [cannot be sold]", 1, true) ~= nil, s)
end

done()
