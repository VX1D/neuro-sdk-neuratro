require("tests.stubs").setup({ love = "lazy" })

local LABEL = "description-line-joins"
local LOST_IF_SKIPPED = 8
local skip = require("tests.skip_ledger")
local check, done = require("tests.helpers").harness(LABEL)
local read = require("tests.helpers").read_file

local DUMP = os.getenv("BALATRO_DUMP")
if not DUMP or DUMP == "" then skip.bail(LABEL, LOST_IF_SKIPPED, "BALATRO_DUMP is unset") end
local misc_src = read(DUMP .. "/functions/misc_functions.lua")
local smods_src = read(DUMP .. "/../../smods/src/utils.lua")
if not (misc_src and smods_src) then skip.bail(LABEL, LOST_IF_SKIPPED, "game dump or smods source unreadable") end

local exe = os.getenv("BALATRO_EXE")
if not exe or exe == "" then
  local steamapps = DUMP:match("^(.*/steamapps)/compatdata/")
  exe = steamapps and (steamapps .. "/common/Balatro/Balatro.exe") or nil
end
local loc_src
if exe and read(exe) ~= nil and not exe:find("'", 1, true) then
  local pipe = io.popen("unzip -p '" .. exe .. "' localization/en-us.lua 2>/dev/null")
  loc_src = pipe and pipe:read("*a")
  if pipe then pipe:close() end
end
if not loc_src or loc_src == "" then
  skip.bail(LABEL, LOST_IF_SKIPPED, "game localization unreadable; set BALATRO_EXE to Balatro.exe")
end
local LOC = assert((loadstring or load)(loc_src))()

local function engine_fn(src, header, name)
  local body = src:match("\n" .. header:gsub("[%(%)%.]", "%%%0") .. ".-\nend\n")
  assert(body, name .. " not found in the engine source")
  return body
end
local shade = 0
local function colour() shade = shade + 1; return { shade / 100, 0, 0, 1 } end
_G.G = {
  ARGS = {}, LANG = { font = { DESCSCALE = 1 } }, FONTS = {},
  C = setmetatable({ UI = { TEXT_INACTIVE = colour(), TEXT_DARK = colour() },
    SUITS = {}, SECONDARY_SET = {}, RARITY = {}, DYN_UI = {} }, { __index = function(t, k)
      local c = colour(); rawset(t, k, c); return c end }),
  UIT = { T = 1, C = 3, O = 4 },
  P_CENTERS = {}, P_TAGS = {},
}
SMODS.Fonts, SMODS.DynaTextEffects = {}, {}
for _, k in ipairs({ "Rarity", "Gradient", "ConsumableType", "Suit" }) do SMODS[k] = { obj_buffer = {} } end
_G.number_format = function(v) return tostring(v) end
assert((loadstring or load)(engine_fn(misc_src, "function loc_colour(_c, _default)", "loc_colour")
  .. engine_fn(misc_src, "function loc_parse_string(line)", "loc_parse_string")
  .. engine_fn(smods_src, "function format_ui_value(value)", "format_ui_value")
  .. engine_fn(smods_src, "function SMODS.localize_box(lines, args)", "SMODS.localize_box")))()

local Utils = require("util.utils")

local function described(set, key, vars)
  local rows = {}
  for _, line in ipairs(LOC.descriptions[set][key].text) do
    rows[#rows + 1] = SMODS.localize_box(loc_parse_string(line), { vars = vars or {} })
  end
  local card = { sort_id = key, ability = { set = set, name = key },
    config = { center = { key = key, set = set } },
    generate_UIBox_ability_table = function() return { main = rows } end }
  return Utils.card_description_with_fallback(card)
end

local CASES = {
  { "Tag", "tag_double", nil, "Gives a copy of the next selected Tag (Double Tag excluded)" },
  { "Joker", "j_loyalty_card", { 4, 6, "5 remaining" }, "X4 Mult every 6 hands played (5 remaining)" },
  { "Joker", "j_gros_michel", { 15, 1, 6 }, "+15 Mult; 1 in 6 chance this card is destroyed at end of round" },
  { "Joker", "j_green_joker", { 1, 1, 0 }, "+1 Mult per hand played; -1 Mult per discard (Currently +0 Mult)" },
  { "Tarot", "c_fool", nil, "Creates the last Tarot or Planet card used during this run (The Fool excluded)" },
  { "Spectral", "c_ouija", nil, "Converts all cards in hand to a single random rank; -1 hand size" },
  { "Joker", "j_fibonacci", { 8 }, "Each played Ace, 2, 3, 5, or 8 gives +8 Mult when scored" },
  { "Joker", "j_walkie_talkie", { 10, 4 }, "Each played 10 or 4 gives +10 Chips and +4 Mult when scored" },
}
for _, c in ipairs(CASES) do
  local got = described(c[1], c[2], c[3])
  check(c[2] .. " reads as separate clauses where the game breaks them", got == c[4], tostring(got))
end

done()
