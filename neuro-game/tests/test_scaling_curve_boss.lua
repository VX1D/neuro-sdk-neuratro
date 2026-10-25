require("tests.stubs").setup({ love = "lazy" })

local check, done = require("tests.helpers").harness("scaling-curve-boss")

local dump = os.getenv("BALATRO_DUMP")
if not dump or dump == "" then
  require("tests.skip_ledger").bail("scaling-curve-boss", 5, "game dump not found; set BALATRO_DUMP to run")
end
local fh = assert(io.open(dump .. "/game.lua", "r"))
local src = assert(fh:read("*a"):match("self%.P_BLINDS%s*=%s*(%b{})"))
fh:close()
local P_BLINDS = assert((loadstring or load)("local HEX = function(s) return s end "
  .. "local localize = function() return '' end return " .. src))()

_G.get_blind_amount = function(a)
  return ({ 300, 800, 2000, 5000, 11000, 20000, 35000, 50000, 110000 })[a]
end

local function state(ante, boss, boss_state, small_state)
  _G.G = { P_BLINDS = P_BLINDS, GAME = { win_ante = 8, starting_params = { ante_scaling = 1 },
    round_resets = { ante = ante, blind_choices = { Small = "bl_small", Big = "bl_big", Boss = boss },
      blind_states = { Small = small_state or "Select", Big = "Upcoming", Boss = boss_state or "Upcoming" } } } }
end

local EF = require("facts.economy_facts")
local UNDRAWN = "(boss not drawn yet: usually 2x that, 1x to 6x across all bosses)"

state(8, "bl_final_vessel")
local c = EF.scaling_curve()
check("L3 a drawn Violet Vessel is priced at its own 6x, the 300000 its blind row states",
  c == "Requirement climbs -- next small blinds: ante 8 ~50000 (its boss Violet Vessel is 6x: ~300000),"
    .. " ante 9 ~110000 " .. UNDRAWN .. ". ", c)

state(3, "bl_wall")
c = EF.scaling_curve()
check("L3 a drawn The Wall is priced at its own 4x",
  c == "Requirement climbs -- next small blinds: ante 3 ~2000 (its boss The Wall is 4x: ~8000),"
    .. " ante 4 ~5000 " .. UNDRAWN .. ". ", c)

state(3, "bl_wall", "Hide")
c = EF.scaling_curve()
check("L3 a hidden boss is never named or priced",
  c == "Requirement climbs -- next small blinds: ante 3 ~2000 " .. UNDRAWN .. ", ante 4 ~5000 " .. UNDRAWN .. ". ", c)

state(3, "bl_wall", "Upcoming", "Defeated")
c = EF.scaling_curve()
check("L3 the drawn boss belongs to its own ante, not the next one listed",
  c and c:find("Wall", 1, true) == nil and c:find("ante 4 ~5000 " .. UNDRAWN, 1, true) ~= nil, c)

check("L3 no listed boss is claimed at a flat 2x", c and c:find("about 2x", 1, true) == nil, c)

done()
