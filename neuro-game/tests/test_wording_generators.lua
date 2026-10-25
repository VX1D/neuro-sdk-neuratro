require("tests.stubs").setup({ love = "lazy", localize = true, G = "board" })

local check, done = require("tests.helpers").harness("wording-generators")
local FP = require("tests.force_payload")
local LB = require("tests.fixtures.live_board")
local EngineCards = require("tests.engine_cards")

local function row(force, pattern)
  return (force and force.state or ""):match("[^\n]*" .. pattern .. "[^\n]*") or "(missing)"
end

do
  LB.load("SMODS_BOOSTER_OPENED", "Standard pack with playing cards")
  local bp = G.pack_cards or G.booster_pack
  EngineCards.enhance(bp.cards[2], "m_stone")
  bp.cards[3].seal = "Red"
  local force = FP.build("SMODS_BOOSTER_OPENED")
  local pack = force.state:match("## Cards in the pack.-\n##") or force.state
  check("no playing-card row names the engine's set",
    not pack:find("(Default)", 1, true) and not pack:find("(Enhanced)", 1, true), pack)
  check("fixture: the seal is still described", pack:find("Retriggers this card once", 1, true) ~= nil, pack)
  local stone_row = row(force, "Stone")
  check("the Stone row uses the name the action example uses",
    stone_row:find("Stone Card (", 1, true) ~= nil and force.query:find('name "Stone Card"', 1, true) ~= nil,
    stone_row .. "\n" .. force.query)
end

do
  LB.load("SMODS_BOOSTER_OPENED", "Has pack cards")
  local fool = LB.consumable("c_fool", 660)
  fool.generate_UIBox_ability_table = function()
    return { name = "The Fool", main = {
      { { n = 1, nodes = { { n = 2, config = { text = "Creates the last Tarot or Planet card used during this run" } } } } },
      { { n = 3, config = { align = "bm" }, nodes = { { n = 3, config = { align = "m" },
        nodes = { { n = 1, config = { text = " None " } } } } } } },
    } }
  end
  G.pack_cards.cards = { fool }
  fool.area = G.pack_cards
  local fool_row = row(FP.build("SMODS_BOOSTER_OPENED"), "The Fool")
  check("The Fool's empty slot is a word, not a missing value",
    fool_row:find("(currently: none)", 1, true) ~= nil and not fool_row:find("None", 1, true), fool_row)
end

do
  LB.load("SHOP", "Normal: affordable joker, affordable booster, $10")
  local blank = EngineCards.card({ sort_id = 650, cost = 10, ability = { set = "Voucher", name = "Blank" },
    config = { center = { key = "v_blank", set = "Voucher", name = "Blank", cost = 10,
      loc_txt = { name = "Blank", text = { "Does nothing?" } } } } })
  G.shop_vouchers.cards = { blank }
  blank.area = G.shop_vouchers
  local blank_row = row(FP.build("SHOP"), "Blank")
  check("a description that ends its own sentence gets no extra period",
    blank_row:find("Does nothing? ", 1, true) ~= nil and not blank_row:find("?.", 1, true), blank_row)
end

done()
