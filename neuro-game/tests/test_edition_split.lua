_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("edition-split")

_G.G = { STATES = {}, GAME = {} }

local Utils = require("util.utils")
local SR = require("core.semantic_registry")
local CardUtil = require("facts.card_util")
local CtxHelpers = require("context.ctx_helpers")

local function node(text) return { { config = { text = text } } } end
local function with_ui(card, main_text, info_text)
  card.generate_UIBox_ability_table = function(_self)
    return { name = "X", main = node(main_text), info = info_text and node(info_text) or {} }
  end
  return card
end

do
  local card = with_ui({
    config = { center = { key = "j_joker", set = "Joker" } },
    ability = { set = "Joker" },
    edition = { foil = true },
  }, "X4 Mult", "+50 Chips")

  local own = Utils.card_description(card)
  check("card_description is own-effect only (no fused edition chips)",
    type(own) == "string" and own:find("X4") ~= nil and own:find("50") == nil, tostring(own))

  local info = Utils.card_info_text(card)
  check("card_info_text preserves the ui.info tooltip (edition text) separately",
    type(info) == "string" and info:find("50") ~= nil, tostring(info))
end

do
  local card = with_ui({
    config = { center = { key = "j_joker", set = "Joker" } },
    ability = { set = "Joker" },
    edition = { foil = true },
  }, "X4 Mult", "+50 Chips")

  local owned = SR.render("owned_joker_row", card, 80)
  check("owned_joker_row effect is own-only (no edition, it is in flags)",
    owned:find("X4") ~= nil and owned:find("Foil") == nil and owned:find("50") == nil, tostring(owned))

  local flags = CtxHelpers.joker_tags(card)
  check("the edition lives in the joker's flags column", flags:find("Foil(+50c)", 1, true) ~= nil, tostring(flags))

  local shop = SR.render("shop_card_row", card, 140)
  check("shop_card_row keeps the edition as a labeled token (no flags column there)",
    shop:find("X4") ~= nil and shop:find("Foil(+50c)", 1, true) ~= nil, tostring(shop))
end

do
  local card = {
    config = { center = { key = "j_x", set = "Joker" } },
    ability = { set = "Joker", mult = 4 },
    edition = { foil = true, chips = 50 },
  }
  local shop = SR.render("shop_card_row", card, 140)
  check("Branch-B shop labels the edition number ('Foil: +50 Chips'), not a bare '+50 Chips'",
    shop:find("Foil: +50 Chips", 1, true) ~= nil, tostring(shop))
  check("C1b Branch-B shop still shows the joker's own +4 Mult", shop:find("+4 Mult", 1, true) ~= nil, tostring(shop))

  local owned = SR.render("owned_joker_row", card, 80)
  check("Branch-B owned drops the edition number (it is in flags)",
    owned:find("+4 Mult", 1, true) ~= nil and owned:find("50") == nil, tostring(owned))
end

do
  local plain = with_ui({
    config = { center = { key = "j_joker", set = "Joker" } },
    ability = { set = "Joker" },
    edition = { foil = true },
  }, "X4 Mult", "+50 Chips")
  local fd = SR.render("card_description_full", plain, 320)
  check("full_description of a plain editioned joker is own-only (no fused edition, no Copying)",
    fd:find("X4") ~= nil and fd:find("50") == nil and fd:find("Copying") == nil, tostring(fd))

  local bp = with_ui({
    config = { center = { key = "j_blueprint", set = "Joker" } },
    ability = { set = "Joker", name = "Blueprint" },
  }, "Copies the Joker to the right", "+4 Mult")
  check("copy_joker_kind identifies Blueprint", CardUtil.copy_joker_kind(bp) == "blueprint",
    tostring(CardUtil.copy_joker_kind(bp)))
  local bpd = SR.render("card_description_full", bp, 320)
  check("Blueprint full_description keeps the copied ability under a 'Copying' label",
    bpd:find("Copies") ~= nil and bpd:find("Copying", 1, true) ~= nil and bpd:find("+4 Mult", 1, true) ~= nil, tostring(bpd))
end

local function multi_node(texts)
  local n = {}
  for _, t in ipairs(texts) do n[#n + 1] = { config = { text = t } } end
  return n
end

do
  local greenish = {
    config = { center = { key = "j_x", set = "Joker" } },
    ability = { set = "Joker" },
  }
  greenish.generate_UIBox_ability_table = function(_self)
    return { name = "Green-ish", main = multi_node({
      "+1", " Mult per hand played", "-1", " Mult per discard", "(Currently ", "+1", " Mult)",
    }), info = {} }
  end
  local desc = Utils.card_description(greenish)
  local first = desc:find("+1", 1, true)
  local second = first and desc:find("+1", first + 1, true)
  check("non-adjacent identical fragments both survive (Green Joker's static and live +1)",
    first ~= nil and second ~= nil, tostring(desc))
  check("E1b the live value is not simply missing from the parenthetical",
    desc:find("Currently Mult)", 1, true) == nil, tostring(desc))
end

do
  local temperish = {
    config = { center = { key = "j_y", set = "Joker" } },
    ability = { set = "Joker" },
  }
  temperish.generate_UIBox_ability_table = function(_self)
    return { name = "Temper-ish", main = multi_node({
      "Gives the total sell value of all current Jokers", "(Max of $50", ")", "(Currently $4", ")",
    }), info = {} }
  end
  local desc = Utils.card_description(temperish)
  check("the text is not left with a dangling unclosed paren",
    desc:find("$4 )", 1, true) ~= nil, tostring(desc))
end

do
  local adjacent = {
    config = { center = { key = "j_z", set = "Joker" } },
    ability = { set = "Joker" },
  }
  adjacent.generate_UIBox_ability_table = function(_self)
    return { name = "Adjacent", main = multi_node({ ")", ")" }), info = {} }
  end
  local desc = Utils.card_description(adjacent)
  local _, count = desc:gsub("%)", "%%)")
  check("an immediately-adjacent repeat still collapses to one",
    count == 1, tostring(desc))
end

do
  local triple = {
    config = { center = { key = "j_z3", set = "Joker" } },
    ability = { set = "Joker" },
  }
  triple.generate_UIBox_ability_table = function(_self)
    return { name = "Triple", main = multi_node({ ")", ")", ")" }), info = {} }
  end
  local desc = Utils.card_description(triple)
  local _, count = desc:gsub("%)", "%%)")
  check("E3b three immediately-adjacent repeats still collapse to one", count == 1, tostring(desc))
end

do
  local gapped = {
    config = { center = { key = "j_z4", set = "Joker" } },
    ability = { set = "Joker" },
  }
  gapped.generate_UIBox_ability_table = function(_self)
    return { name = "Gapped", main = multi_node({ "a", "a", "mid", "a" }), info = {} }
  end
  local desc = Utils.card_description(gapped)
  local _, count = desc:gsub("a", "a")
  check("E3c an adjacent pair collapses, but a later occurrence past a gap survives (2 a's, not 1 or 3)",
    count == 2, tostring(desc))
end

do
  local alt = {
    config = { center = { key = "j_z5", set = "Joker" } },
    ability = { set = "Joker" },
  }
  alt.generate_UIBox_ability_table = function(_self)
    return { name = "Alternating", main = multi_node({ "a", "b", "a", "b", "a" }), info = {} }
  end
  local desc = Utils.card_description(alt)
  check("E3d full alternation loses nothing", desc == "a b a b a", tostring(desc))
end

do
  local both = {
    config = { center = { key = "j_w", set = "Joker" } },
    ability = { set = "Joker" },
  }
  both.generate_UIBox_ability_table = function(_self)
    return { name = "Both", main = node("+50 Chips"), info = node("+50 Chips") }
  end
  local main_desc = tostring(Utils.card_description(both) or "")
  local info_desc = tostring(Utils.card_info_text(both) or "")
  check("ui.main and ui.info no longer share dedup state (both keep +50 Chips)",
    main_desc:find("+50 Chips", 1, true) ~= nil and info_desc:find("+50 Chips", 1, true) ~= nil,
    main_desc .. " | " .. info_desc)
end

done()
