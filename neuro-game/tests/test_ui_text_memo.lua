rawset(_G, "NEURO_TEST", true)

love = { timer = { getTime = function() return 0 end } }

local check, done = require("tests.helpers").harness("ui text memo")
local Fixtures = require("hud.dev_fixtures")

_G.G = {
  TIMERS = { REAL = 0 },
  GAME = {},
  I = Fixtures._test.sparse_ui_registry(4000),
  P_CENTERS = {},
  localization = {},
}

local Utils = require("util.utils")
check("placeholder and UI text caches share the 0.75 second TTL", Utils.UI_TEXT_TTL == 0.75,
  Utils.UI_TEXT_TTL)
check("sparse fixture covers G.I keys 0/2000/4000",
  G.I.MOVEABLE[0] ~= nil and G.I.UIBOX[2000] ~= nil and G.I.NODE[4000] ~= nil)

local loc_calls, removed = 0, 0
local function live_loc_vars(_center, _info_queue, card)
  loc_calls = loc_calls + 1
  local key = 5000 + loc_calls
  local transient = {}
  transient.remove = function(self)
    self.removed = true
    removed = removed + 1
    G.I.UIBOX[key] = nil
  end
  G.I.UIBOX[key] = transient
  return { vars = { card.ability.mult } }
end

local swash = Fixtures.card({
  key = "j_swashbuckler",
  name = "Swashbuckler",
  set = "Joker",
  loc_text = { "Currently {C:mult}+#1#{} Mult" },
  loc_vars = live_loc_vars,
})
local other = { sell_cost = 5 }
G.jokers = { cards = { swash, other } }
swash.area, other.area = G.jokers, G.jokers

check("placeholder revision is empty before the first lookup", Utils.placeholder_revision(swash) == 0)
local first_text = Utils.safe_description(swash.config.center.loc_txt, swash)
local first_revision = Utils.placeholder_revision(swash)
check("placeholder miss builds loc_vars and reaps its transient UI",
  first_text == "Currently +5 Mult" and loc_calls == 1 and removed == 1 and first_revision > 0,
  first_text)

G.TIMERS.REAL = 0.20
other.sell_cost = 9
local hit_text = Utils.safe_description(swash.config.center.loc_txt, swash)
local hit_revision = Utils.placeholder_revision(swash)
check("placeholder hit returns the same value and revision without scanning G.I again",
  hit_text == first_text and hit_revision == first_revision and loc_calls == 1 and removed == 1,
  string.format("text=%s revision=%s calls=%d", tostring(hit_text), tostring(hit_revision), loc_calls))
check("dynamic joker refresh remains a live side effect on a placeholder hit",
  swash.ability.mult == 9, swash.ability.mult)

G.TIMERS.REAL = 0.75
local stale_revision = Utils.placeholder_revision(swash)
check("placeholder expiry changes the cheap token before rebuilding",
  stale_revision ~= first_revision, stale_revision)
local rebuilt_text = Utils.safe_description(swash.config.center.loc_txt, swash)
local rebuilt_revision = Utils.placeholder_revision(swash)
check("placeholder miss after TTL returns a new value and revision",
  rebuilt_text == "Currently +9 Mult" and loc_calls == 2 and removed == 2
    and rebuilt_revision > 0 and rebuilt_revision ~= first_revision,
  string.format("text=%s revision=%s calls=%d", tostring(rebuilt_text), tostring(rebuilt_revision), loc_calls))
Utils.safe_description(swash.config.center.loc_txt, swash)
check("rebuilt placeholder memo is immediately reusable", loc_calls == 2
  and Utils.placeholder_revision(swash) == rebuilt_revision)

local ui_value, ui_calls, ui_removed = "Alpha", 0, 0
local ui_card = {
  config = { center = { key = "j_ui_memo", set = "Joker", rarity = 1 } },
  ability = { set = "Joker" },
}
ui_card.generate_UIBox_ability_table = function()
  ui_calls = ui_calls + 1
  local key = 6000 + ui_calls
  local transient = {}
  transient.remove = function(self)
    self.removed = true
    ui_removed = ui_removed + 1
    G.I.NODE[key] = nil
  end
  G.I.NODE[key] = transient
  return {
    name = ui_value,
    main = { { config = { text = "Description " .. ui_value } } },
    info = {},
  }
end

G.TIMERS.REAL = 10
check("UI text revision is empty before generation", Utils.ui_text_revision(ui_card) == 0)
local first_name = Utils.safe_name(ui_card)
local first_ui_revision = Utils.ui_text_revision(ui_card)
check("UI text miss builds once and reaps generated UI",
  first_name == "Alpha" and ui_calls == 1 and ui_removed == 1 and first_ui_revision > 0,
  first_name)

ui_value = "Beta"
G.TIMERS.REAL = 10.74
local cached_name = Utils.safe_name(ui_card)
check("UI text hit keeps the result and revision until TTL",
  cached_name == "Alpha" and ui_calls == 1 and Utils.ui_text_revision(ui_card) == first_ui_revision,
  cached_name)

G.TIMERS.REAL = 10.75
local stale_ui_revision = Utils.ui_text_revision(ui_card)
check("UI text expiry is visible through the cheap public token without rebuilding",
  stale_ui_revision ~= first_ui_revision and ui_calls == 1, stale_ui_revision)
local rebuilt_name = Utils.safe_name(ui_card)
local final_ui_revision = Utils.ui_text_revision(ui_card)
local rebuilt_desc = Utils.card_description(ui_card)
check("expired UI text rebuilds to fresh content exactly once",
  rebuilt_name == "Beta" and rebuilt_desc == "Description Beta" and ui_calls == 2 and ui_removed == 2
    and final_ui_revision > 0 and final_ui_revision ~= first_ui_revision,
  string.format("name=%s desc=%s calls=%d", tostring(rebuilt_name), tostring(rebuilt_desc), ui_calls))

G.TIMERS.REAL = 10.76
Utils.safe_name(ui_card)
Utils.card_description(ui_card)
check("post-rebuild token prevents a second rebuild on the next frame",
  ui_calls == 2 and Utils.ui_text_revision(ui_card) == final_ui_revision, ui_calls)

done()
