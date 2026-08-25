
local check, done = require("tests.helpers").harness("blind juice isolation")

_G.G = {
  TIMERS = { REAL = 0, TOTAL = 0 },
  SETTINGS = { GAMESPEED = 1 },
  SPEEDFACTOR = 1,
  NEURO = {},
}
_G.SMODS = {
  current_mod = { config = { settings = {}, colours = {} } },
  save_mod_config = function() return true end,
  Mods = {},
}
love = {
  timer = { getTime = function() return G.TIMERS.REAL end },
  graphics = setmetatable({}, { __index = function() return function() end end }),
}

local queue = {}
_G.Event = function(config) return config end
G.E_MANAGER = {
  add_event = function(_, event)
    queue[#queue + 1] = event
  end,
}

local fired = 0
local function blind_option()
  return {
    STATIONARY = true,
    juice_up = function() fired = fired + 1 end,
  }
end

G.blind_select_opts = {
  small = blind_option(),
  big = blind_option(),
  boss = blind_option(),
}

local NeuroAnim = require("render.neuro-anim")
check("blind-select animation entry point is absent", NeuroAnim.on_blind_select == nil)

NeuroAnim.on_state_enter("BLIND_SELECT")
for i = 1, #queue do
  if queue[i].func then queue[i].func() end
end

check("entering blind select schedules no animation events", #queue == 0, tostring(#queue))
check("blind option UIBoxes are never juiced", fired == 0, tostring(fired))

local source = assert(io.open("render/neuro-anim.lua", "r")):read("*all")
check("NeuroAnim never reads blind_select_opts", source:find("blind_select_opts", 1, true) == nil)

done()
