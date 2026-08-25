_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("tag-facts")
local TagFacts = require("facts.tag_facts")

do
  local bad = {}
  for key, class in pairs(TagFacts.CLASS_OF) do
    if not TagFacts.CLASS_PROSE[class] then bad[#bad + 1] = key .. "=" .. tostring(class) end
  end
  check("every classified tag names a class that has prose", #bad == 0, table.concat(bad, ", "))
end

do
  check("T2a an unknown tag key yields no class", TagFacts.class_of("tag_from_some_mod") == nil)
  check("T2b and renders as an empty string, so callers can concatenate unconditionally",
    TagFacts.class_prose("tag_from_some_mod") == "" and TagFacts.class_prose(nil) == "")
end

do
  check("T3a a tag that hands over a card is an item tag",
    TagFacts.class_of("tag_uncommon") == "item" and TagFacts.class_of("tag_charm") == "item")
  check("T3b a tag that moves money is an economy tag",
    TagFacts.class_of("tag_investment") == "economy" and TagFacts.class_of("tag_d_six") == "economy")
  check("T3c a tag that upgrades a joker permanently is an edition tag",
    TagFacts.class_of("tag_negative") == "edition" and TagFacts.class_of("tag_polychrome") == "edition")
  check("T3d a tag that bends a rule and keeps nothing is a utility tag",
    TagFacts.class_of("tag_juggle") == "utility" and TagFacts.class_of("tag_boss") == "utility")
end

do
  local leaks = {}
  for class, prose in pairs(TagFacts.CLASS_PROSE) do
    if prose:find("%$") or prose:find("%d") then leaks[#leaks + 1] = class end
  end
  check("no class prose carries a figure -- amounts belong to the row, not the classification",
    #leaks == 0, table.concat(leaks, ", "))
end

do
  local CtxBlind = require("context.ctx_blind")
  _G.localize = function() return "" end
  _G.get_blind_amount = function(a) return 300 * a end
  _G.G = {
    STATE = 2, STATES = { BLIND_SELECT = 2 },
    P_BLINDS = { bl_small = { key = "bl_small", name = "Small Blind", mult = 1, dollars = 3 } },
    P_TAGS = { tag_uncommon = { key = "tag_uncommon", name = "Uncommon Tag" } },
    GAME = {
      win_ante = 8, dollars = 10, round = 1, blind_on_deck = "Small",
      starting_params = {}, modifiers = {}, current_round = { hands_left = 4, discards_left = 4 },
      round_resets = {
        ante = 1,
        blind_tags = { Small = "tag_uncommon" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
        blind_choices = { Small = "bl_small" },
      },
    },
    NEURO = { once_serials = {}, state_enter_serial = 1, decision_serial = 1 },
    jokers = { cards = {} }, consumeables = { cards = {} },
  }
  local ok, section = pcall(CtxBlind.blind_select_section)
  local text = (ok and type(section) == "string") and section or ""
  check("T5a the blind row still names the tag", text:find("Uncommon Tag", 1, true) ~= nil, text)
  check("T5b and now says what kind of thing that tag is",
    text:find("item tag", 1, true) ~= nil, text)
end

done()
