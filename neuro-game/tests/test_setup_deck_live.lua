_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("setup-deck-live")

local Misc = require("context.ctx_misc")

local P_CENTERS = {
  b_red  = { loc_txt = { name = "Red Deck" } },
  b_blue = { loc_txt = { name = "Blue Deck" } },
}

local function set_game(sel, back)
  _G.G = {
    P_CENTERS = P_CENTERS,
    GAME = { selected_back = sel, back = back, stake = 1 },
  }
end

set_game({ key = "b_blue", name = "Blue Deck" }, { key = "b_red", name = "Red Deck" })
local row = Misc.run_section() or ""
check("selected_back wins over stale back", row:find("Run setup: Blue Deck", 1, true) ~= nil, row)
check("stale back name not shown", row:find("Red Deck", 1, true) == nil, row)

set_game(nil, { key = "b_red", name = "Red Deck" })
local row2 = Misc.run_section() or ""
check("falls back to back when no selected_back", row2:find("Run setup: Red Deck", 1, true) ~= nil, row2)

set_game({ key = "b_blue", name = "Blue Deck" }, nil)
local row3 = Misc.run_section() or ""
check("uses selected_back when back absent", row3:find("Run setup: Blue Deck", 1, true) ~= nil, row3)

do
  local pool, P = {}, {}
  for i = 1, 31 do
    local key = string.format("b_mod%02d", i)
    local deck = { key = key, loc_txt = { name = "Mod Deck " .. i, description = { "Effect " .. i } } }
    pool[i] = deck
    P[key] = deck
  end
  _G.G = {
    P_CENTERS = P,
    P_CENTER_POOLS = { Back = pool },
    GAME = { selected_back = { key = "b_mod01", name = "Mod Deck 1" }, stake = 1 },
  }
  local out = Misc.setup_decks_section() or ""
  check("the header counts every selectable deck", out:find("31 decks are selectable", 1, true) ~= nil, out)
  local rows = 0
  for _ in out:gmatch("\n%d+%. ") do rows = rows + 1 end
  check("every deck gets a row, not the first 24", rows == 31, rows)
  check("the 31st deck's key is listed so it can actually be chosen",
    out:find("key b_mod31", 1, true) ~= nil, out)
end

done()
