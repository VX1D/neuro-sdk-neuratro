
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local PRINTED = {}
local RECTS = {}
local DRAWS = {}
local SHADER_SETS = {}
local record_print = require("tests.helpers").print_recorder(function() return PRINTED end)
local SEQ = 0
local function record_rect(mode, x, y, w, h)
  SEQ = SEQ + 1
  RECTS[#RECTS + 1] = { mode = mode, x = x, y = y, w = w, h = h, seq = SEQ }
end
local function record_draw(_img, _q, x, y, r, sx, sy)
  SEQ = SEQ + 1
  DRAWS[#DRAWS + 1] = { x = x, y = y, r = r, sx = sx, sy = sy, seq = SEQ,
    shader = SHADER_SETS.current }
end
local IMG = { getWidth = function() return 640 end, getHeight = function() return 950 end,
  getDimensions = function() return 640, 950 end }
local gfxstub = setmetatable({
  getFont = function() return FONT end,
  newFont = function() return FONT end,
  getWidth = function() return 1920 end,
  getHeight = function() return 1080 end,
  getShader = function() return nil end,
  getBlendMode = function() return "alpha", "alphamultiply" end,
  newQuad = function() return {} end,
  newImage = function() return IMG end,
  newMesh = function() return {} end,
  print = record_print,
  rectangle = record_rect,
  draw = record_draw,
  setShader = function(sh)
    SHADER_SETS.current = sh and sh._name or nil
    if sh then SHADER_SETS[#SHADER_SETS + 1] = sh._name end
  end,
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

local area = require("tests.helpers").area
_G.G = {
  NEURO = { persona = "hiyori", state = "SHOP", enabled = true,
    ai_highlighted = setmetatable({}, { __mode = "k" }) },
  GAME = { dollars = 20, round = 1, round_resets = { ante = 1, blind_choices = {} },
    blind = {}, used_vouchers = {}, modifiers = {} },
  jokers = area({}), consumeables = area({}), hand = area({}),
  shop_jokers = area({}), shop_vouchers = area({}), shop_booster = area({}),
  FUNCS = {}, TIMERS = { REAL = 1 }, STATES = {},
  SETTINGS = { paused = false, GAMESPEED = 1, colourblind_option = false },
  C = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }),
  ARGS = {}, P_CENTERS = {}, P_CENTER_POOLS = {}, P_BLINDS = {}, localization = {},
  ASSET_ATLAS = {}, SHADERS = {}, TILESCALE = 3.65, TILESIZE = 20, CANV_SCALE = 1,
  I = { MOVEABLE = {}, UIBOX = {}, NODE = {} },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local check, done = require("tests.helpers").harness("edition shaders on minis")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local Cards = require("hud.cards")

local EDITION_TEXT = { NEG = true, POLY = true, HOLO = true, FOIL = true }

local function joker_card(edition, key)
  return {
    config = { center = { key = key or "j_blueprint", set = "Joker", name = "Blueprint",
      loc_txt = { name = "Blueprint" }, rarity = 1, pos = { x = 0, y = 0 } } },
    ability = {}, edition = edition, cost = 5, sell_cost = 2,
    VT = { w = 50, h = 70, scale = 1, x = 0, y = 0 },
  }
end

local function playing_card(edition)
  return {
    config = { center = { key = "c_base", set = "Default", pos = { x = 0, y = 0 },
        loc_txt = { name = "Base" } },
      card = { pos = { x = 3, y = 1 }, value = 10, suit = "Hearts" } },
    ability = {}, edition = edition,
    VT = { w = 50, h = 70, scale = 1, x = 0, y = 0 },
  }
end

local function fake_shader(name, send)
  return { _name = name, send = send or function() end }
end

local function register_atlases()
  G.ASSET_ATLAS.Joker = { image = IMG, px = 71, py = 95 }
  G.ASSET_ATLAS.centers = { image = IMG, px = 71, py = 95 }
  G.ASSET_ATLAS.cards_1 = { image = IMG, px = 71, py = 95 }
  G.ASSET_ATLAS.stickers = { image = IMG, px = 71, py = 95 }
end

local function enable_shaders(send)
  G.SHADERS = {}
  for _, n in ipairs({ "negative", "negative_shine", "holo", "foil", "polychrome" }) do
    G.SHADERS[n] = fake_shader(n, send)
  end
end

local function reset(with_shaders, with_atlas, send)
  PRINTED, RECTS, DRAWS = {}, {}, {}
  SEQ = 0
  SHADER_SETS = {}
  G.ASSET_ATLAS = {}
  G.SHADERS = {}
  if with_atlas ~= false then register_atlases() end
  if with_shaders then enable_shaders(send) end
  Cards.reset_mini_counters()
end

local function shader_names()
  local out = {}
  for _, n in ipairs(SHADER_SETS) do out[#out + 1] = n end
  return out
end

local function count_shader(name)
  local n = 0
  for _, s in ipairs(SHADER_SETS) do if s == name then n = n + 1 end end
  return n
end

local function edition_text_printed()
  for _, t in ipairs(PRINTED) do if EDITION_TEXT[t] then return t end end
  return nil
end

local function full_fill_rects(w, h)
  local n = 0
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.w and r.h
      and math.abs(r.w - w) < 0.5 and math.abs(r.h - h) < 0.5 then n = n + 1 end
  end
  return n
end

do
  reset(true)
  Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1)
  check("1a holo runs exactly one shader pass", count_shader("holo") == 1,
    table.concat(shader_names(), ","))
  reset(true)
  Cards.draw_card_mini(joker_card({ foil = true }), 0, 0, 95, 1)
  check("1b foil runs exactly one shader pass", count_shader("foil") == 1,
    table.concat(shader_names(), ","))
  reset(true)
  Cards.draw_card_mini(joker_card({ polychrome = true }), 0, 0, 95, 1)
  check("1c polychrome runs exactly one shader pass", count_shader("polychrome") == 1,
    table.concat(shader_names(), ","))
  reset(true)
  Cards.draw_card_mini(joker_card({ negative = true }), 0, 0, 95, 1)
  check("1d negative runs both passes in order",
    count_shader("negative") == 1 and count_shader("negative_shine") == 1
      and SHADER_SETS[1] == "negative" and SHADER_SETS[2] == "negative_shine",
    table.concat(shader_names(), ","))
end

do
  reset(true)
  local w, h = Cards.card_dimensions(joker_card({ holo = true }), 95)
  Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1)
  check("2a shaded mini draws no full-size edition overlay",
    full_fill_rects(w, h) == 0, full_fill_rects(w, h))
  check("2b shaded mini prints no edition text badge", edition_text_printed() == nil,
    edition_text_printed())
  check("2c shaded mini does not count as a fallback",
    (Cards._mini_edition_skip or 0) == 0 and Cards._mini_edition_fail == 0,
    tostring(Cards._mini_edition_skip) .. "/" .. tostring(Cards._mini_edition_fail))
end

do
  reset(false)
  local w, h = Cards.card_dimensions(joker_card({ holo = true }), 95)
  Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1)
  check("3a missing shader falls back to the overlay",
    full_fill_rects(w, h) >= 1, full_fill_rects(w, h))
  check("3b fallback keeps the edition text badge", edition_text_printed() == "HOLO",
    edition_text_printed())
  check("3c fallback increments the skip counter", Cards._mini_edition_skip == 1,
    Cards._mini_edition_skip)
  check("3d fallback does not touch the failure counter", Cards._mini_edition_fail == 0,
    Cards._mini_edition_fail)
end

do
  reset(true, false)
  Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1)
  check("4a missing atlas still uses the name placeholder", Cards._mini_fallback == 1,
    Cards._mini_fallback)
  check("4b missing atlas runs no shader pass", #SHADER_SETS == 0,
    table.concat(shader_names(), ","))
  check("4c missing atlas does not count an edition skip",
    (Cards._mini_edition_skip or 0) == 0, Cards._mini_edition_skip)
end

do
  reset(true, true, function(_, field)
    if field == "texture_details" then error("forced shader failure") end
  end)
  local w, h = Cards.card_dimensions(joker_card({ holo = true }), 95)
  local ok = pcall(function() Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1) end)
  check("5a throwing shader does not break the draw", ok)
  check("5b throwing shader increments the failure counter", Cards._mini_edition_fail == 1,
    Cards._mini_edition_fail)
  check("5c throwing shader repaints the overlay", full_fill_rects(w, h) >= 1,
    full_fill_rects(w, h))
  check("5d throwing shader brings the text badge back", edition_text_printed() == "HOLO",
    edition_text_printed())
end

do
  reset(true, true, function(_, field)
    if field == "texture_details" then error("forced shader failure") end
  end)
  local orig_print = print
  local logged = {}
  print = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end
  for _ = 1, 1000 do Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1) end
  print = orig_print
  check("6a 1000 failures increment the counter 1000 times", Cards._mini_edition_fail == 1000,
    Cards._mini_edition_fail)
  check("6b 1000 failures log at most once", #logged <= 1, #logged)
end

do
  for _, key in ipairs({ "j_half", "j_photograph", "j_square", "j_wee", "j_blueprint" }) do
    reset(true)
    local card = joker_card({ holo = true }, key)
    local _, _, scale_x, scale_y = Cards.card_dimensions(card, 95)
    Cards.draw_card_mini(card, 0, 0, 95, 1)
    local shaded_draw
    for _, d in ipairs(DRAWS) do if d.shader == "holo" then shaded_draw = d end end
    check("7 " .. key .. " shader pass uses the shared geometry scale",
      shaded_draw and math.abs(shaded_draw.sx - scale_x) < 1e-9
        and math.abs(shaded_draw.sy - scale_y) < 1e-9,
      shaded_draw and (tostring(shaded_draw.sx) .. "/" .. tostring(shaded_draw.sy))
        .. " vs " .. tostring(scale_x) .. "/" .. tostring(scale_y))
  end
end

do
  reset(true)
  G.SHADERS.negative_shine = nil
  local card = joker_card({ negative = true })
  local w, h = Cards.card_dimensions(card, 95)
  Cards.draw_card_mini(card, 0, 0, 95, 1)
  check("7b-1 primary pass still runs", count_shader("negative") == 1,
    table.concat(shader_names(), ","))
  check("7b-2 missing secondary pass does not repaint the overlay on top of the shader",
    full_fill_rects(w, h) == 0, full_fill_rects(w, h))
  check("7b-3 missing secondary pass does not bring the badge back",
    edition_text_printed() == nil, edition_text_printed())
  check("7b-4 missing secondary pass counts no fallback",
    (Cards._mini_edition_skip or 0) == 0, Cards._mini_edition_skip)
end

local function legendary(edition)
  return {
    config = { center = { key = "j_canio", set = "Joker", name = "Canio",
      loc_txt = { name = "Canio" }, rarity = 4,
      pos = { x = 0, y = 0 }, soul_pos = { x = 1, y = 1 } } },
    ability = {}, edition = edition,
    VT = { w = 50, h = 70, scale = 1, x = 0, y = 0 },
  }
end

do
  reset(true)
  Cards.draw_card_mini(legendary({ holo = true }), 0, 0, 95, 1)
  check("7c-1 shaded legendary draws base, edition and soul", #DRAWS == 3, #DRAWS)
  check("7c-2 edition pass runs on the base sprite, not on the soul",
    DRAWS[2] and DRAWS[2].shader == "holo", DRAWS[2] and tostring(DRAWS[2].shader))
  check("7c-3 soul is drawn last, so the edition pass cannot cover it",
    DRAWS[3] and DRAWS[3].shader == nil, DRAWS[3] and tostring(DRAWS[3].shader))
end

do
  reset(false)
  local w, h = Cards.card_dimensions(legendary({ holo = true }), 95)
  Cards.draw_card_mini(legendary({ holo = true }), 0, 0, 95, 1)
  local soul_seq = DRAWS[#DRAWS] and DRAWS[#DRAWS].seq
  local overlay_seq
  for _, r in ipairs(RECTS) do
    if r.mode == "fill" and r.w and r.h
      and math.abs(r.w - w) < 0.5 and math.abs(r.h - h) < 0.5 then
      overlay_seq = overlay_seq or r.seq
    end
  end
  check("7c-4 fallback overlay also runs before the soul",
    overlay_seq and soul_seq and overlay_seq < soul_seq,
    tostring(overlay_seq) .. " vs " .. tostring(soul_seq))
end

local function unshaded_draws()
  local n = 0
  for _, d in ipairs(DRAWS) do if d.shader == nil then n = n + 1 end end
  return n
end

do
  reset(true)
  Cards.draw_card_mini(joker_card({ negative = true }), 0, 0, 95, 1)
  check("7d-1 negative joker draws no plain base underneath the shader",
    unshaded_draws() == 0, unshaded_draws())
  check("7d-2 negative joker base goes through the negative shader",
    DRAWS[1] and DRAWS[1].shader == "negative", DRAWS[1] and tostring(DRAWS[1].shader))
  check("7d-3 negative_shine still runs on top",
    DRAWS[2] and DRAWS[2].shader == "negative_shine", DRAWS[2] and tostring(DRAWS[2].shader))
end

do
  reset(true)
  Cards.draw_card_mini(playing_card({ negative = true }), 0, 0, 95, 1)
  check("7d-4 negative playing card draws no plain base either",
    unshaded_draws() == 0, unshaded_draws())
  check("7d-5 negative playing card shades both center and front",
    count_shader("negative") == 2, count_shader("negative"))
  check("7d-6 negative_shine stays center-only", count_shader("negative_shine") == 1,
    count_shader("negative_shine"))
end

do
  reset(true)
  Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1)
  check("7d-7 holo stays additive: plain base first, shader pass on top",
    unshaded_draws() == 1 and DRAWS[1] and DRAWS[1].shader == nil
      and DRAWS[2] and DRAWS[2].shader == "holo",
    (DRAWS[1] and tostring(DRAWS[1].shader) or "?") .. "/"
      .. (DRAWS[2] and tostring(DRAWS[2].shader) or "?"))
end

do
  reset(true)
  G.SHADERS.negative = nil
  local w, h = Cards.card_dimensions(joker_card({ negative = true }), 95)
  Cards.draw_card_mini(joker_card({ negative = true }), 0, 0, 95, 1)
  check("7d-8 missing negative shader falls back to the plain base plus overlay",
    unshaded_draws() == 1 and full_fill_rects(w, h) >= 1,
    unshaded_draws() .. "/" .. full_fill_rects(w, h))
  check("7d-9 negative fallback keeps the text badge", edition_text_printed() == "NEG",
    edition_text_printed())
  check("7d-10 negative fallback counts a skip", Cards._mini_edition_skip == 1,
    Cards._mini_edition_skip)
end

do
  reset(false)
  Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1, true)
  check("8 skip_art_badge still suppresses the badge on the fallback path",
    edition_text_printed() == nil, edition_text_printed())
end

do
  reset(false)
  Cards.draw_card_mini(joker_card({ holo = true }), 0, 0, 95, 1)
  check("9a skip counter is non-zero before reset", Cards._mini_edition_skip > 0)
  Cards.reset_mini_counters()
  check("9b reset_mini_counters clears the skip counter", Cards._mini_edition_skip == 0,
    Cards._mini_edition_skip)
end

do
  reset(true)
  Cards.draw_card_mini(playing_card({ negative = true }), 0, 0, 95, 1)
  check("10a playing card still runs the negative pass on center and front",
    count_shader("negative") == 2, count_shader("negative"))
  check("10b negative_shine stays center-only", count_shader("negative_shine") == 1,
    count_shader("negative_shine"))
  reset(true)
  Cards.draw_card_mini(playing_card({ holo = true }), 0, 0, 95, 1)
  check("10c playing card holo covers center and front", count_shader("holo") == 2,
    count_shader("holo"))
end

-- Minis draw cards the game isn't refreshing ARGS for (card.lua:4709-4711), so the shader's
-- animation uniform must be sent manually or it goes stale; `dissolve` is excluded since it
-- owns a float uniform of the same name that a vec2 would clobber.
do
  local sends = {}
  local function record_send(_, name, value) sends[#sends + 1] = { name = name, value = value } end

  for _, ed in ipairs({ "foil", "holo", "polychrome", "negative" }) do
    for _, has_args in ipairs({ true, false }) do
      reset(true, true, record_send)
      for i = #sends, 1, -1 do sends[i] = nil end

      local card = joker_card({ [ed] = true }, "j_half")
      if has_args then card.ARGS = { send_to_shader = { 0.5, 7.25 } } end
      Cards.draw_card_mini(card, 0, 0, 95, 1)

      local named, value = false, nil
      for _, sd in ipairs(sends) do
        if sd.name == ed then named, value = true, sd.value end
      end
      local label = ed .. (has_args and " with card.ARGS" or " with NO card.ARGS")
      check(label .. " still sends its own uniform", named,
        "never sent " .. ed)
      check(label .. " sends a vec2", type(value) == "table" and #value == 2,
        type(value) == "table" and ("#" .. #value) or type(value))
      if has_args and type(value) == "table" then
        check(ed .. " prefers the card's own value when it has one", value[1] == 0.5 and value[2] == 7.25,
          tostring(value[1]) .. "/" .. tostring(value[2]))
      end
    end
  end
end

do
  local sends = {}
  reset(true, true, function(_, name, value) sends[#sends + 1] = { name = name, value = value } end)
  G.SHADERS.dissolve = fake_shader("dissolve",
    function(_, name, value) sends[#sends + 1] = { name = name, value = value } end)
  local _, _, scale_x, scale_y = Cards.card_dimensions(joker_card(), 95)
  Cards.draw_sprite_shaded("Joker", { x = 0, y = 0 }, 0, 0, scale_x, scale_y, 1, 0.5)

  local bad = 0
  for _, sd in ipairs(sends) do
    if sd.name == "dissolve" and type(sd.value) == "table" then bad = bad + 1 end
  end
  check("the dissolve shader is never handed a vec2 under its own name", bad == 0, bad)
end

done()
