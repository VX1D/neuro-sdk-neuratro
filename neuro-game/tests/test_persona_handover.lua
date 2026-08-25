require("tests.raster_capture")
local check, done = require("tests.helpers").harness("persona handover")

local Palette = require("render.palette")
local PP = require("render.persona_palette")
local NeuroAnim = require("render.neuro-anim")

local BOOT, LOADING = 0.35, 2.00
local HANDOVER = BOOT + LOADING

local function login(from, to, t0)
  G.NEURO.persona = to
  G.NEURO.login_anim = { start = t0, name = "X", palette_ready = false, from = from }
end

local function at(t0, dt)
  G.TIMERS.REAL = t0 + dt
  pcall(NeuroAnim.draw_login_anim)
  PP.apply_for_frame()
  return Palette.displayed_persona()
end

local t0 = G.TIMERS.REAL
login("hiyori", "evil", t0)
for _, dt in ipairs({ 0.00, 0.10, 1.00, HANDOVER - 0.05 }) do
  check("chrome still hiyori at t=" .. dt, at(t0, dt) == "hiyori", at(t0, dt))
end
check("chrome is evil once the animation hands over", at(t0, HANDOVER + 0.05) == "evil")

login("hiyori", "evil", G.TIMERS.REAL)
check("committed identity flips immediately", Palette.persona() == "evil")

G.NEURO.persona = "neuro"
G.NEURO.login_anim = { start = G.TIMERS.REAL, name = "X", palette_ready = false }
check("no `from` means no hold", Palette.displayed_persona() == "neuro")

G.NEURO.login_anim = nil
G.NEURO.persona = "evil"
check("no animation means chrome follows the committed identity",
  Palette.displayed_persona() == Palette.persona())

G.NEURO.login_anim = nil
G.NEURO.persona = "hiyori"
G.STATES = { MENU = 1 }
G.STATE = 1
local Dispatcher = require("core.dispatcher")
local exec = Dispatcher.preflight("choose_persona", { persona = "evil" })
check("choose_persona yields an executor", type(exec) == "function")
if type(exec) == "function" then
  exec()
  local anim = G.NEURO.login_anim
  check("dispatcher opened a login animation", type(anim) == "table", tostring(anim))
  check("dispatcher recorded the persona being handed over from",
    anim and anim.from == "hiyori", anim and tostring(anim.from))
  check("chrome holds the previous persona right after the pick",
    Palette.displayed_persona() == "hiyori", Palette.displayed_persona())
  check("committed identity is already the new one", Palette.persona() == "evil")
end

G.NEURO.login_anim = nil
G.NEURO.persona = "neuro"
done()
