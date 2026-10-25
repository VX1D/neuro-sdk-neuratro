local M = {}

local LOVE = {
  lazy = function()
    if not love then love = { timer = { getTime = function() return 0 end } } end
  end,
  timers = function()
    love = { timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end } }
  end,
  zero = function()
    love = { timer = { getTime = function() return 0 end } }
  end,
}

local function centers() return require("tests.engine_centers").centers() end
local GAME = {
  board = function() return { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, P_CENTERS = centers() } end,
  hand = function()
    return { GAME = { current_round = {}, hands = {} }, hand = { cards = {} }, FUNCS = {}, P_CENTERS = centers() }
  end,
  timed = function() return { NEURO = {}, FUNCS = {}, GAME = {}, TIMERS = { REAL = 100 }, P_CENTERS = centers() } end,
}

function M.setup(opts)
  opts = opts or {}
  _G.NEURO_TEST = true
  require("tests.engine_cards").install_smods(rawget(_G, "SMODS"))
  if opts.love then LOVE[opts.love]() end
  if opts.localize then _G.localize = function() return "" end end
  if opts.G then _G.G = GAME[opts.G]() end
end

return M
