_G.NEURO_TEST = true

local check, done = require("tests.helpers").harness("gfx drain + input hooks")

local function noop() end
local FONT = {
  getWidth = function(_, s) return #tostring(s or "") * 8 end,
  getHeight = function() return 12 end,
}
local gfx = { depth = 0, scissor_cleared = 0, shader_cleared = 0, origin_calls = 0 }
gfx.push = function()
  gfx.depth = gfx.depth + 1
end
gfx.pop = function()
  if gfx.depth <= 0 then error("unbalanced pop") end
  gfx.depth = gfx.depth - 1
end
gfx.origin = function() gfx.origin_calls = gfx.origin_calls + 1 end
gfx.setScissor = function() gfx.scissor_cleared = gfx.scissor_cleared + 1 end
gfx.setShader = function(s) if s == nil then gfx.shader_cleared = gfx.shader_cleared + 1 end end
gfx.getShader = function() return nil end
gfx.getBlendMode = function() return "alpha", "alphamultiply" end
gfx.getFont = function() return FONT end
gfx.newFont = function() return FONT end
gfx.getWidth = function() return 1920 end
gfx.getHeight = function() return 1080 end
gfx.newQuad = function() return {} end
gfx.newImage = function() return { getWidth = function() return 64 end,
  getHeight = function() return 64 end, getDimensions = function() return 64, 64 end } end
gfx.newMesh = function() return {} end
setmetatable(gfx, { __index = function() return noop end })

love = setmetatable({
  graphics = gfx,
  timer = { getTime = function() return (G and G.TIMERS and G.TIMERS.REAL) or 0 end },
  filesystem = setmetatable({}, { __index = function() return function() return nil end end }),
}, { __index = function() return setmetatable({}, { __index = function() return noop end }) end })

_G.G = {
  NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, TIMERS = { REAL = 0 },
  STATES = { SHOP = 1 }, STATE = 1, SETTINGS = { paused = false },
}
_G.SMODS = { current_mod = { path = "./" }, Mods = {}, findModByID = function() return nil end }
_G.NFS = setmetatable({}, { __index = function() return noop end })

local function read(path)
  local fh = assert(io.open(path, "r"))
  local src = fh:read("a")
  fh:close()
  return src
end

local entry_src = read("neuro-game.lua")
local drain = require("render.gfx_guard").drain
check("the graphics-state drain is callable", type(drain) == "function")

do
  gfx.depth = 0
  gfx.push(); gfx.push(); gfx.push()
  drain()
  check("the real drain pops a leaked transform stack back to zero (" .. gfx.depth .. ")",
    gfx.depth == 0)
end

local drain_calls = 0
G.NEURO.drain_gfx_leak = function()
  drain_calls = drain_calls + 1
  return drain()
end

local throwing_draw = function()
  love.graphics.push()
  error("atlas exploded")
end
_G.Card = { draw = throwing_draw }

local Cards = require("hud.cards")
Cards.hook_card_draw()
check("the Card.draw wrapper was installed", Card.draw ~= throwing_draw)

do
  gfx.depth = 0
  drain_calls = 0
  local card = { VT = { x = 0, y = 0, w = 1, h = 1, scale = 1 } }
  local ok, err = pcall(Card.draw, card, "card")
  check("the wrapper still swallows a throwing base draw", ok == true, tostring(err))
  check("the wrapper drained the leak (" .. drain_calls .. " call(s))", drain_calls == 1)
  check("the graphics stack is balanced after a failed base draw (" .. gfx.depth .. ")",
    gfx.depth == 0)
end

do
  gfx.depth = 0
  drain_calls = 0
  local card = { VT = { x = 0, y = 0, w = 1, h = 1, scale = 1 } }
  for _ = 1, 5 do pcall(Card.draw, card, "card") end
  check("a card failing every frame does not grow the stack (" .. gfx.depth .. ")", gfx.depth == 0)
  check("every failing frame drains, not just the first logged one (" .. drain_calls .. ")",
    drain_calls == 5)
end

do
  gfx.depth = 0
  drain_calls = 0
  local seen = 0
  _G.Card.draw = nil
  local S = require("hud.state")
  S.neuro_card_draw_hooked = false
  _G.Card.draw = function()
    seen = seen + 1
    love.graphics.push()
    love.graphics.pop()
  end
  Cards.hook_card_draw()
  local card = { VT = { x = 0, y = 0, w = 1, h = 1, scale = 1 } }
  local ok = pcall(Card.draw, card, "card")
  check("a healthy base draw still runs", ok == true and seen == 1)
  check("a healthy base draw does not drain (" .. drain_calls .. ")", drain_calls == 0)
  check("a healthy base draw leaves the stack balanced (" .. gfx.depth .. ")", gfx.depth == 0)
end

local function hook_block(name)
  local s = entry_src:find("love%." .. name .. " = function")
  if not s then return nil end
  local e = entry_src:find("\nlocal original_love", s)
  return entry_src:sub(s, e and (e - 1) or #entry_src)
end

local SWALLOWERS = { "mousepressed", "mousereleased", "wheelmoved", "keypressed" }
for _, name in ipairs(SWALLOWERS) do
  local body = hook_block(name)
  check("love." .. name .. " hook found", body ~= nil)
  check("love." .. name .. " is still swallowed during the login animation",
    body ~= nil and body:find("login_anim", 1, true) ~= nil)
end

do
  local body = hook_block("mousemoved")
  check("love.mousemoved hook found", body ~= nil)
  check("love.mousemoved is no longer gated on the login animation",
    body ~= nil and body:find("login_anim", 1, true) == nil)
  check("love.mousemoved still delegates to the base handler",
    body ~= nil and body:find("original_love_mousemoved(x, y, dx, dy, istouch)", 1, true) ~= nil)
  check("love.mousemoved is still pcall-wrapped",
    body ~= nil and body:find("finish_input_hook(\"MOUSE MOVE\", pcall(", 1, true) ~= nil)
end

done()
