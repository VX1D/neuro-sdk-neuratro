-- Not buying a booster does not trigger Red Card; only skip_pack on an opened pack does.
require("tests.stubs").setup({ love = "lazy", G = "board" })

local check, done = require("tests.helpers").harness("skip-trigger-fact")
local D = require("core.dispatcher")
local TD = require("tests.test_deadlock")

local SHOP_NOTE = "Red Card counts a Booster Pack as skipped only when you buy and open it, then close it early "
  .. "(even after taking a card); a pack left unbought in the shop is not skipped."

local function red_card(overrides)
  local card = { cost = 5, sell_cost = 2, sort_id = 900, ability = { set = "Joker", name = "Red Card", mult = 0, extra = 3 },
    config = { center = { key = "j_red_card", set = "Joker", name = "Red Card" } } }
  for k, v in pairs(overrides or {}) do card[k] = v end
  return card
end

local function scenario(state, desc)
  for _, sc in ipairs(TD.SCENARIOS) do
    if sc.state == state and sc.desc == desc then
      TD.apply_mock(sc.mock())
      G.NEURO.persona = "neuro"
      require("tests.helpers").in_scenario_state(sc)
      return
    end
  end
  error("no scenario " .. desc)
end

local function frame(state)
  local s, q = require("tests.helpers").force_frame(state)
  return s .. "\n" .. q
end

local function skip_rules(state, note)
  local s, q = require("tests.helpers").force_frame(state)
  local section = s:match("\n## Skip rules\n(.-)\n## ") or s:match("\n## Skip rules\n(.*)$") or ""
  local ok = section:find(note, 1, true) ~= nil and q:find(note, 1, true) == nil
  return ok, "state:\n" .. s .. "\nquery:\n" .. q
end

do
  scenario("SHOP", "Normal: affordable joker, affordable booster, $10")
  check("the shop frame says nothing about skipping without such a card", not frame("SHOP"):find("is not skipped", 1, true))
  G.jokers.cards[#G.jokers.cards + 1] = red_card()
  check("an owned Red Card puts the meaning of a skipped pack in the shop frame's state", skip_rules("SHOP", SHOP_NOTE))
end

do
  scenario("SHOP", "Normal: affordable joker, affordable booster, $10")
  G.shop_jokers.cards[#G.shop_jokers.cards + 1] = red_card()
  check("a Red Card for sale carries the same fact", skip_rules("SHOP", SHOP_NOTE))
end

do
  scenario("SMODS_BOOSTER_OPENED", "Buffoon pack with a joker")
  G.pack_cards.cards[#G.pack_cards.cards + 1] = red_card({ facing = "back" })
  G.booster_pack = G.pack_cards
  local s, q = require("tests.helpers").force_frame("SMODS_BOOSTER_OPENED")
  check("a face-down Red Card in a pack reveals nothing", (s .. q):find("Red Card", 1, true) == nil, s .. q)
end

done()
