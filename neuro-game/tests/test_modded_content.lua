
_G.NEURO_TEST = true

local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local IMG = { getWidth = function() return 512 end, getHeight = function() return 512 end,
  getDimensions = function() return 512, 512 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local function area(cards, cfg)
  local config = { card_limit = 5 }
  for k, v in pairs(cfg or {}) do config[k] = v end
  return { cards = cards or {}, highlighted = {}, config = config }
end

local function base_game()
  return {
    NEURO = { persona = "hiyori", state = "SHOP", enabled = true },
    GAME = { dollars = 20, round = 1, blind = {}, used_vouchers = {}, modifiers = {},
      probabilities = { normal = 1 }, starting_params = {},
      current_round = { hands_left = 3, discards_left = 2 },
      round_resets = { ante = 1, blind_choices = {} } },
    jokers = area(), consumeables = area({}, { card_limit = 2 }), hand = area({}, { card_limit = 8, highlighted_limit = 5 }),
    shop_jokers = area(), shop_vouchers = area(), shop_booster = area(),
    FUNCS = {}, TIMERS = { REAL = 1 }, STATES = {},
    SETTINGS = { paused = false, GAMESPEED = 1, colourblind_option = false },
    C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
    ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, P_SEALS = {},
    localization = { misc = { labels = {}, dictionary = {} }, descriptions = {} },
    ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
    playing_cards = {},
    I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
  }
end

_G.G = base_game()
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

G.ASSET_ATLAS.centers = { image = IMG, px = 71, py = 95, name = "centers" }
G.ASSET_ATLAS.Joker = { image = IMG, px = 71, py = 95, name = "Joker" }

local check, done = require("tests.helpers").harness("modded content")

local Model = require("facts.boss.model")
local Limits = require("core.plan_limits")
local Legality = require("facts.boss.legality")
local CardUtil = require("facts.card_util")
local Cards = require("hud.cards")

local function reset_game()
  _G.G = base_game()
  _G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
  G.ASSET_ATLAS.centers = { image = IMG, px = 71, py = 95, name = "centers" }
  G.ASSET_ATLAS.Joker = { image = IMG, px = 71, py = 95, name = "Joker" }
end

local function vanilla_blinds()
  return {
    bl_small = { name = "Small Blind", defeated = false, order = 1, dollars = 3, mult = 1,
      vars = {}, debuff_text = "", debuff = {}, pos = { x = 0, y = 0 }, set = "Blind" },
    bl_big = { name = "Big Blind", defeated = false, order = 2, dollars = 4, mult = 1.5,
      vars = {}, debuff_text = "", debuff = {}, pos = { x = 0, y = 1 }, set = "Blind" },
    bl_ox = { name = "The Ox", defeated = false, order = 4, dollars = 5, mult = 2, vars = { "" },
      debuff = {}, pos = { x = 0, y = 2 }, boss = { min = 6 }, set = "Blind" },
    bl_club = { name = "The Club", defeated = false, order = 9, dollars = 5, mult = 2, vars = {},
      debuff = { suit = "Clubs" }, pos = { x = 0, y = 4 }, boss = { min = 1 }, set = "Blind" },
  }
end

local MODDED_BOSS = { name = "Gilded Gate", defeated = false, order = 40, dollars = 5, mult = 2,
  vars = {}, debuff = { suit = "Clubs" }, pos = { x = 0, y = 0 }, boss = { min = 2 }, set = "Blind" }

do
  reset_game()
  G.P_BLINDS = vanilla_blinds()
  G.P_BLINDS.bl_mymod_gate = MODDED_BOSS

  check("a modded boss key resolves from the blind itself",
    Model.resolve_key({ key = "bl_mymod_gate", name = "Gilded Gate" }) == "bl_mymod_gate",
    tostring(Model.resolve_key({ key = "bl_mymod_gate", name = "Gilded Gate" })))
  check("a modded boss key resolves from the blind center",
    Model.resolve_key({ config = { blind = { key = "bl_mymod_gate" } } }) == "bl_mymod_gate",
    tostring(Model.resolve_key({ config = { blind = { key = "bl_mymod_gate" } } })))
  check("a modded boss resolves by name alone",
    Model.resolve_key({ name = "Gilded Gate" }) == "bl_mymod_gate",
    tostring(Model.resolve_key({ name = "Gilded Gate" })))
  check("a modded boss reports its live name",
    Model.boss_name("bl_mymod_gate") == "Gilded Gate", tostring(Model.boss_name("bl_mymod_gate")))
  check("a shipping boss still resolves against the live table",
    Model.resolve_key({ key = "bl_ox" }) == "bl_ox", tostring(Model.resolve_key({ key = "bl_ox" })))
  check("a non-boss blind is still not a boss key",
    Model.resolve_key({ key = "bl_small", name = "Small Blind" }) == nil,
    tostring(Model.resolve_key({ key = "bl_small", name = "Small Blind" })))
  check("a blind the game does not know is still rejected",
    Model.resolve_key({ key = "bl_not_installed", name = "Nothing" }) == nil,
    tostring(Model.resolve_key({ key = "bl_not_installed", name = "Nothing" })))
end

do
  reset_game()
  local renamed = vanilla_blinds()
  renamed.bl_ox.name = "The Rebranded Ox"
  G.P_BLINDS = renamed
  check("the live name wins over the literal",
    Model.boss_name("bl_ox") == "The Rebranded Ox", tostring(Model.boss_name("bl_ox")))
  check("the live name resolves back to its key",
    Model.resolve_key({ name = "The Rebranded Ox" }) == "bl_ox",
    tostring(Model.resolve_key({ name = "The Rebranded Ox" })))
end

do
  reset_game()
  G.P_BLINDS = {}
  check("headless, the literal still resolves a shipping key",
    Model.resolve_key({ key = "bl_ox" }) == "bl_ox", tostring(Model.resolve_key({ key = "bl_ox" })))
  check("headless, the literal still resolves a shipping name",
    Model.resolve_key({ name = "Crimson Heart" }) == "bl_final_heart",
    tostring(Model.resolve_key({ name = "Crimson Heart" })))
end

local function hand_of(n)
  local cards = {}
  for i = 1, n do
    cards[i] = { base = { value = "Ace", suit = "Spades" }, sort_id = i,
      config = { center = { key = "c_base", set = "Default" } },
      is_suit = function(_, s) return s == "Spades" end }
  end
  return cards
end

do
  reset_game()
  G.hand = nil
  G.GAME.starting_params = nil
  check("headless, the selection cap falls back to the shipping 5",
    Limits.HAND_SELECT_MAX == 5, tostring(Limits.HAND_SELECT_MAX))
end

do
  reset_game()
  G.hand = area(hand_of(8), { card_limit = 8, highlighted_limit = 5 })
  G.GAME.starting_params = { play_limit = 5, discard_limit = 5 }
  check("vanilla, the selection cap is 5",
    Limits.HAND_SELECT_MAX == 5, tostring(Limits.HAND_SELECT_MAX))
  check("vanilla, the play cap is 5", Limits.play_select_max() == 5, tostring(Limits.play_select_max()))
end

do
  reset_game()
  G.hand = area(hand_of(8), { card_limit = 8, highlighted_limit = 8 })
  G.GAME.starting_params = { play_limit = 8, discard_limit = 5 }
  check("a raised play_limit raises the selection cap",
    Limits.HAND_SELECT_MAX == 8, tostring(Limits.HAND_SELECT_MAX))
  check("a raised play_limit raises the play cap",
    Limits.play_select_max() == 8, tostring(Limits.play_select_max()))
  check("a raised play_limit does not raise the discard cap",
    Limits.discard_select_max() == 5, tostring(Limits.discard_select_max()))
  local lo, hi = Legality.play_size_bounds()
  check("legality advertises the raised play range", lo == 1 and hi == 8,
    tostring(lo) .. "-" .. tostring(hi))
end

do
  reset_game()
  G.hand = area(hand_of(8), { card_limit = 8, highlighted_limit = 5 })
  G.GAME.starting_params = { play_limit = 8, discard_limit = 5 }
  check("the CardArea highlight ceiling still caps a raised play_limit",
    Limits.play_select_max() == 5, tostring(Limits.play_select_max()))
end

do
  reset_game()
  G.hand = area(hand_of(8), { card_limit = 8, highlighted_limit = 5 })
  G.GAME.starting_params = { play_limit = 3, discard_limit = 5 }
  check("a challenge that lowers play_limit still lowers the play cap",
    Limits.play_select_max() == 3, tostring(Limits.play_select_max()))
  local lo, hi = Legality.play_size_bounds()
  check("legality still narrows to a lowered play_limit", lo == 1 and hi == 3,
    tostring(lo) .. "-" .. tostring(hi))
end

local function modded_consumable(set)
  return {
    config = { center = { key = "c_mymod_rune_one", set = set } },
    ability = { set = set, name = "Rune One" },
    cost = 4,
  }
end

do
  reset_game()
  SMODS.ConsumableType = { obj_buffer = { "Tarot", "Planet", "Spectral", "Rune" } }
  SMODS.ConsumableTypes = { Tarot = {}, Planet = {}, Spectral = {}, Rune = { key = "Rune" } }
  check("a modded consumable type is a consumable set",
    CardUtil.is_consumable_set("Rune") == true)
  check("a shipping consumable type stays a consumable set",
    CardUtil.is_consumable_set("Tarot") == true)
  check("a joker is still not a consumable set",
    CardUtil.is_consumable_set("Joker") == false)
  check("a modded consumable card is a consumable card",
    CardUtil.is_consumable_card(modded_consumable("Rune")) == true)

  G.consumeables = area({ {}, {} }, { card_limit = 2 })
  G.jokers = area({}, { card_limit = 5 })
  check("a modded consumable in the shop is judged against consumable slots, not joker slots",
    CardUtil.can_buy_card_space(modded_consumable("Rune"), "shop_jokers") == false,
    tostring(CardUtil.can_buy_card_space(modded_consumable("Rune"), "shop_jokers")))
  G.consumeables = area({}, { card_limit = 2 })
  check("with a free consumable slot the same card is buyable",
    CardUtil.can_buy_card_space(modded_consumable("Rune"), "shop_jokers") == true)
end

do
  reset_game()
  check("without SMODS the shipping sets still answer",
    CardUtil.is_consumable_set("Spectral") == true and CardUtil.is_consumable_set("Rune") == false)
end

do
  reset_game()
  SMODS.Rarities = {
    Common = { key = "Common" }, Uncommon = { key = "Uncommon" },
    Rare = { key = "Rare" }, Legendary = { key = "Legendary" },
    mymod_mythic = { key = "mymod_mythic", original_key = "mythic", mod = { prefix = "mymod" } },
  }
  SMODS.Rarity = {
    get_rarity_badge = function(_, rarity)
      local vanilla = { "Common", "Uncommon", "Rare", "Legendary" }
      if vanilla[rarity] then return vanilla[rarity] end
      local misc = G.localization.misc.labels
      return misc["k_" .. tostring(rarity):lower()]
    end,
  }
  G.localization.misc.labels["k_mymod_mythic"] = "Mythic"
  check("a modded rarity is named by the game, not echoed as a key",
    CardUtil.rarity_name("mymod_mythic") == "Mythic", tostring(CardUtil.rarity_name("mymod_mythic")))
  check("shipping numeric rarities are unchanged",
    CardUtil.rarity_name(1) == "Common" and CardUtil.rarity_name(4) == "Legendary")
  check("a string-form shipping rarity is named too",
    CardUtil.rarity_name("Legendary") == "Legendary", tostring(CardUtil.rarity_name("Legendary")))
end

do
  reset_game()
  SMODS.Rarities = {
    mymod_mythic = { key = "mymod_mythic", original_key = "mythic", mod = { prefix = "mymod" } },
  }
  check("with no localization the modded rarity is still readable, not a raw key",
    CardUtil.rarity_name("mymod_mythic") == "Mythic", tostring(CardUtil.rarity_name("mymod_mythic")))
end

local Rewards = require("core.rewards")

local function joker_card(rarity)
  return {
    config = { center = { key = "j_mymod_legend", name = "Modded Legend", set = "Joker",
      rarity = rarity, loc_txt = { name = "Modded Legend" } } },
    ability = { set = "Joker", name = "Modded Legend" },
  }
end

do
  reset_game()
  G.NEURO = { run_generation = 1, enabled = true }
  local msg = Rewards.rare_joker_message(joker_card("Legendary"))
  check("a modded joker with string rarity \"Legendary\" is announced",
    type(msg) == "string" and msg:find("Legendary", 1, true) ~= nil, tostring(msg))
end

do
  reset_game()
  G.NEURO = { run_generation = 2, enabled = true }
  local msg = Rewards.rare_joker_message(joker_card(4))
  check("a shipping numeric Legendary rarity is still announced",
    type(msg) == "string" and msg:find("Legendary", 1, true) ~= nil, tostring(msg))
end

do
  reset_game()
  G.NEURO = { run_generation = 3, enabled = true }
  local msg = Rewards.rare_joker_message(joker_card("mymod_mythic"))
  check("a wholly custom, non-vanilla-equivalent rarity tier is not swept into the gate",
    msg == nil, tostring(msg))
end

do
  reset_game()
  local rc_legendary = Cards.rarity_color(joker_card("Legendary"))
  local rc_rare = Cards.rarity_color(joker_card("Rare"))
  local rc_numeric = Cards.rarity_color(joker_card(4))
  check("hud: a modded joker with string rarity \"Legendary\" gets the Legendary color",
    rc_legendary ~= nil and rc_numeric ~= nil and rc_legendary[1] == rc_numeric[1]
      and rc_legendary[2] == rc_numeric[2] and rc_legendary[3] == rc_numeric[3],
    tostring(rc_legendary))
  check("hud: a modded joker with string rarity \"Rare\" gets a color at all",
    rc_rare ~= nil, tostring(rc_rare))
end

local function vanilla_seals()
  return {
    Red = { order = 1, discovered = false, set = "Seal" },
    Blue = { order = 2, discovered = false, set = "Seal" },
    Gold = { order = 3, discovered = false, set = "Seal" },
    Purple = { order = 4, discovered = false, set = "Seal" },
  }
end

do
  reset_game()
  G.P_SEALS = vanilla_seals()
  G.P_SEALS.mymod_flame = { key = "mymod_flame", set = "Seal", discovered = false,
    get_p_dollars = function() return 5 end }
  G.localization.misc.labels["mymod_flame_seal"] = "Flame Seal"

  check("a modded seal is named by the game", CardUtil.seal_name("mymod_flame") == "Flame Seal",
    tostring(CardUtil.seal_name("mymod_flame")))
  check("a modded seal reports the money the game pays",
    CardUtil.seal_fx_short("mymod_flame") == "+$5", tostring(CardUtil.seal_fx_short("mymod_flame")))
  check("a modded seal gets a compact token, not a bare key",
    CardUtil.seal_short("mymod_flame") == "Flame Seal(+$5_when_scored)",
    tostring(CardUtil.seal_short("mymod_flame")))
  check("shipping seals are unchanged",
    CardUtil.seal_short("Gold") == "Gold(+$3_when_scored)" and CardUtil.seal_name("Red") == "Red",
    tostring(CardUtil.seal_short("Gold")))
end

do
  reset_game()
  G.P_SEALS = vanilla_seals()
  G.P_SEALS.Gold.get_p_dollars = function() return 7 end
  check("a mod that takes over the Gold seal changes the quoted payout",
    CardUtil.seal_fx_short("Gold") == "+$7", tostring(CardUtil.seal_fx_short("Gold")))
  check("and the compact token follows it",
    CardUtil.seal_short("Gold") == "Gold(+$7_when_scored)", tostring(CardUtil.seal_short("Gold")))
end

do
  reset_game()
  G.P_SEALS = nil
  check("headless, the Gold seal keeps the shipping payout",
    CardUtil.seal_fx_short("Gold") == "+$3", tostring(CardUtil.seal_fx_short("Gold")))
  check("headless, an unknown seal still degrades to its key",
    CardUtil.seal_name("mymod_flame") == "mymod_flame", tostring(CardUtil.seal_name("mymod_flame")))
end

local function sized_card(key, box, field)
  local center = { key = key, set = "Joker", atlas = "Joker", pos = { x = 0, y = 0 }, name = key }
  if box then center[field or "display_size"] = box end
  return { config = { center = center }, ability = {}, cost = 5 }
end

do
  reset_game()
  local plain_w, plain_h = Cards.card_dimensions(sized_card("j_mymod_tall"), 95)
  check("an ordinary modded joker is unchanged", plain_w == 71 and plain_h == 95,
    plain_w .. "x" .. plain_h)

  local w, h = Cards.card_dimensions(sized_card("j_mymod_tall", { w = 71, h = 190 }), 95)
  check("display_size.h stretches the card the way the game does", h == 190 and w == 71,
    w .. "x" .. h)

  local w2, h2 = Cards.card_dimensions(sized_card("j_mymod_wide", { w = 142, h = 95 }), 95)
  check("display_size.w widens the card the way the game does", w2 == 142 and h2 == 95,
    w2 .. "x" .. h2)

  local w3, h3 = Cards.card_dimensions(sized_card("j_mymod_pix", { w = 71, h = 47.5 }, "pixel_size"), 95)
  check("pixel_size is the documented fallback for display_size", h3 == 48 and w3 == 71,
    w3 .. "x" .. h3)

  local w4, h4 = Cards.card_dimensions(sized_card("j_wee", { w = 71, h = 190 }), 95)
  check("the generic rule composes with a named exception instead of replacing it",
    math.abs(h4 - 133) <= 2 and math.abs(w4 - 50) <= 2, w4 .. "x" .. h4)
end

do
  reset_game()
  local card = sized_card("j_mymod_tall", { w = 71, h = 190 })
  local w, h = Cards.card_dimensions(card, 95)
  local dw, dh = Cards.draw_card_mini(card, 0, 0, 95, 1)
  check("a display_size joker draws at the size it reports",
    dw and dh and math.abs(dw - w) <= 1 and math.abs(dh - h) <= 1,
    string.format("drew %sx%s, reports %dx%d", tostring(dw), tostring(dh), w, h))
end

done()
