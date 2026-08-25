
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local function noop() end
local WRITTEN = {}
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
}, { __index = function() return noop end })
love = setmetatable({
  graphics = gfxstub,
  timer = { getTime = function() return 0 end, getFPS = function() return 144 end },
  filesystem = setmetatable({
    createDirectory = function() return true end,
    write = function(name, body) WRITTEN[#WRITTEN + 1] = { name = name, body = body }; return true end,
  }, { __index = function() return function() return nil end end }),
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

local check, done = require("tests.helpers").harness("card dex sweep tool")

local Config = require("core.config")
Config.init({ settings = {}, colours = {} }, function() return true end)

local CardDex = require("hud.card_dex")
local Cards = require("hud.cards")

local function center(key, set, atlas)
  return { key = key, set = set, name = key, loc_txt = { name = key }, rarity = 1,
    pos = { x = 0, y = 0 }, atlas = atlas }
end

local function seed_centers()
  G.P_CENTERS = {
    j_a = center("j_a", "Joker"),
    j_b = center("j_b", "Joker"),
    c_fool = center("c_fool", "Tarot"),
    c_pluto = center("c_pluto", "Planet"),
    v_grabber = center("v_grabber", "Voucher"),
    p_arcana = center("p_arcana", "Booster"),
    b_red = center("b_red", "Back"),
    no_pos = { key = "no_pos", set = "Joker", name = "no_pos", loc_txt = { name = "x" } },
  }
end

local function atlases_on()
  G.ASSET_ATLAS = {
    Joker = { image = IMG, px = 71, py = 95 },
    Tarot = { image = IMG, px = 71, py = 95 },
    Planet = { image = IMG, px = 71, py = 95 },
    Voucher = { image = IMG, px = 71, py = 95 },
    Booster = { image = IMG, px = 71, py = 95 },
    centers = { image = IMG, px = 71, py = 95 },
    stickers = { image = IMG, px = 71, py = 95 },
  }
end

local function shaders_on()
  G.SHADERS = {}
  for _, n in ipairs({ "negative", "negative_shine", "holo", "foil", "polychrome" }) do
    G.SHADERS[n] = { _name = n, send = function() end }
  end
end

local function reopen()
  CardDex.set(false)
  Cards.reset_mini_counters()
  CardDex.set(true)
end

seed_centers()
atlases_on()
shaders_on()
reopen()
do
  local tally = CardDex.sweep()
  local total = 0
  for _, n in pairs(tally) do total = total + n end
  check("1a collects only drawable sets with a pos", total == 6, total)
  local seen = {}
  for _, e in ipairs(CardDex.entries()) do seen[e.key] = true end
  check("1b skips a center without pos", seen.no_pos == nil)
  check("1c skips a set outside the dex (Back)", seen.b_red == nil)
  check("1d keeps jokers, consumables, vouchers and boosters",
    seen.j_a and seen.j_b and seen.c_fool and seen.c_pluto and seen.v_grabber and seen.p_arcana)
  local order = {}
  for _, e in ipairs(CardDex.entries()) do order[#order + 1] = e.set end
  check("1e entries are grouped by set", order[1] == "Joker" and order[#order] == "Booster",
    table.concat(order, ","))
end

do
  local t = CardDex.keypressed("e") and CardDex.sweep() or nil
  check("2a edition cycling works", t ~= nil)
  check("2b every card with an edition takes the shader path", (t.shader or 0) == 6,
    tostring(t.shader) .. " shader / " .. tostring(t.overlay) .. " overlay")
  check("2c no card silently falls back while shaders are available",
    (t.overlay or 0) == 0 and (t.fallback or 0) == 0,
    tostring(t.overlay) .. "/" .. tostring(t.fallback))
end

do
  G.SHADERS = {}
  Cards.reset_mini_counters()
  local t = CardDex.sweep()
  check("3 without shaders every card falls back to the overlay", (t.overlay or 0) == 6,
    tostring(t.overlay) .. "/" .. tostring(t.shader))
end

do
  shaders_on()
  G.ASSET_ATLAS = {}
  Cards.reset_mini_counters()
  local t = CardDex.sweep()
  check("4 without atlases every card lands on the name placeholder",
    (t.fallback or 0) == 6, tostring(t.fallback))
end

do
  atlases_on()
  shaders_on()
  Cards.reset_mini_counters()
  local plain_seen, guard = nil, 0
  repeat
    local t = CardDex.sweep()
    plain_seen = t.plain
    if not plain_seen then CardDex.keypressed("e") end
    guard = guard + 1
  until plain_seen or guard > 8
  check("5 cards without an edition report the plain path", plain_seen == 6,
    tostring(plain_seen) .. " po " .. guard .. " probach")
end

do
  WRITTEN = {}
  atlases_on()
  shaders_on()
  Cards.reset_mini_counters()
  local path = CardDex.report()
  check("6a report is written", path ~= nil and #WRITTEN == 1, tostring(path))
  local body = WRITTEN[1] and WRITTEN[1].body or ""
  local missing
  for _, sz in ipairs({ 26, 40, 110 }) do
    if not body:find("size: " .. sz .. " px", 1, true) then missing = missing or ("size " .. sz) end
  end
  for _, e in ipairs({ "none", "foil", "holo", "poly", "neg" }) do
    for _, v in ipairs({ "plain", "seal", "stickers", "debuff" }) do
      if not body:find("**" .. e .. " / " .. v .. "**", 1, true) then
        missing = missing or (e .. "/" .. v)
      end
    end
  end
  check("6b report covers every size x edition x variant cell", missing == nil, missing)
  check("6b2 report states the matrix it swept",
    body:find("3 sizes x 5 editions x 4 variants = 60 sweeps", 1, true) ~= nil)
  check("6b3 report carries an off-path total", body:find("Off-path total:", 1, true) ~= nil)
  check("6c report carries the path legend", body:find("Path legend", 1, true) ~= nil)
  check("6d report names the file with a carddex prefix",
    WRITTEN[1] and WRITTEN[1].name:find("^carddex/") ~= nil,
    WRITTEN[1] and WRITTEN[1].name)
end

do
  WRITTEN = {}
  G.ASSET_ATLAS = {}
  Cards.reset_mini_counters()
  CardDex.report()
  local body = WRITTEN[1] and WRITTEN[1].body or ""
  check("7a broken atlases are listed per card", body:find("`j_a (Joker)", 1, true) ~= nil)
  check("7b the listed path is the fallback", body:find("-> fallback", 1, true) ~= nil)
  check("7c the off-path total is non-zero when everything is broken",
    body:find("Off%-path total: [1-9]") ~= nil)
end

do
  atlases_on()
  shaders_on()
  Cards.reset_mini_counters()
  local ok, err = xpcall(function() CardDex.draw() end, debug.traceback)
  check("8a draw runs without error", ok, err)
  for _, k in ipairs({ "s", "f", "down", "up", "pagedown", "pageup", "home" }) do
    local ok2, err2 = xpcall(function() CardDex.keypressed(k) end, debug.traceback)
    check("8b key " .. k .. " handled", ok2, err2)
  end
  local ok3, err3 = xpcall(function() CardDex.wheelmoved(0, -3) end, debug.traceback)
  check("8c wheel handled", ok3, err3)
  local ok4, err4 = xpcall(function() CardDex.draw() end, debug.traceback)
  check("8d draw runs after the filter toggle", ok4, err4)
  CardDex.set(false)
  local ok5, err5 = xpcall(function() CardDex.draw() end, debug.traceback)
  check("8e closed dex draws nothing and does not error", ok5, err5)
  check("8f closed dex swallows keys", CardDex.keypressed("e") == false)
end

do
  local big = {}
  local sets = { "Joker", "Tarot", "Planet", "Spectral", "Voucher", "Booster" }
  for i = 1, 240 do
    local set = sets[(i % #sets) + 1]
    local key = "k_" .. set:lower() .. "_" .. i
    big[key] = center(key, set)
  end
  G.P_CENTERS = big
  atlases_on()
  G.ASSET_ATLAS.Spectral = { image = IMG, px = 71, py = 95 }
  shaders_on()
  CardDex.set(false)
  Cards.reset_mini_counters()
  CardDex.set(true)
  check("9a collects the whole catalogue", #CardDex.entries() == 240, #CardDex.entries())
  local t = CardDex.sweep()
  local total = 0
  for _, n in pairs(t) do total = total + n end
  check("9b every card is classified exactly once", total == 240, total)
  for _ = 1, #({ 26, 40, 110 }) do
    local ok, err = xpcall(function()
      CardDex.draw()
      CardDex.keypressed("s")
    end, debug.traceback)
    check("9c draws at catalogue scale", ok, err)
  end
  local ok_scroll = xpcall(function()
    for _ = 1, 40 do CardDex.wheelmoved(0, -3) end
    CardDex.draw()
    for _ = 1, 80 do CardDex.wheelmoved(0, 1) end
    CardDex.draw()
  end, debug.traceback)
  check("9d scrolling through the whole grid stays safe", ok_scroll)
  WRITTEN = {}
  local ok_rep, err_rep = xpcall(function() CardDex.report() end, debug.traceback)
  check("9e full-catalogue report over every edition", ok_rep, err_rep)
  local body = WRITTEN[1] and WRITTEN[1].body or ""
  check("9f report stays readable and not empty", #body > 500, #body)
  CardDex.set(false)
end

do
  WRITTEN = {}
  seed_centers()
  atlases_on()
  shaders_on()
  CardDex.set(false)
  Cards.reset_mini_counters()
  CardDex.set(true)
  local n = CardDex.start_full_sweep()
  check("10a full sweep queues the whole matrix", n == 60, n)
  local i0, total = CardDex.job_progress()
  check("10b progress starts at zero", i0 == 0 and total == 60, tostring(i0))
  local guard = 0
  while CardDex.job_progress() and guard < 200 do
    CardDex.step_job()
    guard = guard + 1
  end
  check("10c job finishes in exactly one step per combo", guard == 61, guard)
  check("10d job writes the report when it drains", #WRITTEN == 1, #WRITTEN)
  check("10e report notes it came from the button",
    (WRITTEN[1] and WRITTEN[1].body or ""):find("started from button", 1, true) ~= nil)
  check("10f job clears itself", CardDex.job_progress() == nil)
  local ok_btn = xpcall(function() CardDex.draw() end, debug.traceback)
  check("10g draw is safe right after the job drained", ok_btn)
  CardDex.set(false)
end

do
  seed_centers()
  atlases_on()
  shaders_on()
  check("11a ready when centers and atlases are loaded", CardDex.ready() == true)
  local keep = G.ASSET_ATLAS
  G.ASSET_ATLAS = {}
  check("11b not ready before atlases load", CardDex.ready() == false)
  G.ASSET_ATLAS = keep
  local keep_c = G.P_CENTERS
  G.P_CENTERS = {}
  CardDex.set(false)
  check("11c not ready with an empty catalogue", CardDex.ready() == false)
  G.P_CENTERS = keep_c
  CardDex.set(false)
end

do
  local Schema = require("core.config_schema")
  local found
  for _, d in ipairs(Schema.entries or Schema) do
    if type(d) == "table" and d.key == "NEURO_CARD_DEX_ON_BOOT" then found = d end
  end
  check("12a the on-boot flag is declared in the schema", found ~= nil)
  check("12b it defaults to off", found and found.default == "off", found and found.default)
  check("12c it is marked restart_required like the other boot flags",
    found and found.restart_required == true)
end

do
  WRITTEN = {}
  seed_centers()
  atlases_on()
  shaders_on()
  CardDex.set(false)
  Cards.reset_mini_counters()
  local ticks, guard = 0, 0
  while not CardDex.boot_done() and guard < 400 do
    CardDex.boot_tick()
    ticks = ticks + 1
    guard = guard + 1
  end
  check("13a boot sweep drains without anyone opening the dex", CardDex.boot_done(), ticks)
  check("13b boot sweep took one tick per combo plus start and latch",
    ticks == 62, ticks)
  check("13c boot sweep wrote exactly one report", #WRITTEN == 1, #WRITTEN)
  check("13d report records that it came from boot, not the button",
    (WRITTEN[1] and WRITTEN[1].body or ""):find("started from boot", 1, true) ~= nil)
  local before = #WRITTEN
  for _ = 1, 50 do CardDex.boot_tick() end
  check("13e boot sweep never runs twice", #WRITTEN == before, #WRITTEN)
end

do
  WRITTEN = {}
  G.ASSET_ATLAS = {}
  local dex = require("hud.card_dex")
  for _ = 1, 30 do dex.boot_tick() end
  check("14 boot sweep waits for atlases instead of sweeping an empty catalogue",
    #WRITTEN == 0, #WRITTEN)
  atlases_on()
end

done()
