_G.NEURO_TEST = true
_G.G = { GAME = {}, FUNCS = {} }

_G.Event = {}
function _G.Event.handle(self, results)
  results.completed = self.func()
  results.time_done = true
end
_G.Moveable = {}
function _G.Moveable.move(self, _dt) return self.FRAME.MOVE end
_G.Card = {}
function _G.Card.update_alert(self) return self.area.config.collection end
function _G.Card.remove(self) if self.area then self.area:remove_card(self) end end
_G.Game = {}
function _G.Game.update_blind_select(self) return G.hand.T.y - G.jokers.T.y end
_G.save_run = function() return G.GAME.blind:save() end
G.FUNCS.HUD_blind_debuff = function() return #G.GAME.blind.loc_debuff_lines end

local CrashGuards = require("core.crash_guards")
CrashGuards.install()

local check, done = require("tests.helpers").harness("crash-guards")

do
  local ev = { func = function() error("card.lua:1429: boom") end, complete = false }
  local res = {}
  local ok = pcall(_G.Event.handle, ev, res)
  check("throwing event: no propagation (frame survives)", ok, "handle re-threw")
  check("throwing event: force-completed (will be dropped)", res.completed == true and res.time_done == true, "completed=" .. tostring(res.completed))
end

do
  local ev = { func = function() return true end }
  local res = {}
  _G.Event.handle(ev, res)
  check("success event: completed=true preserved", res.completed == true)
  local ev2 = { func = function() return false end }
  local res2 = {}
  _G.Event.handle(ev2, res2)
  check("condition event returning false: stays incomplete", res2.completed == false)
end

do
  check("Moveable:move nil FRAME -> no throw", pcall(_G.Moveable.move, { FRAME = nil }, 0.1))
  check("Moveable:move live FRAME -> runs", (function()
    local ok, v = pcall(_G.Moveable.move, { FRAME = { MOVE = 7 } }, 0.1); return ok and v == 7 end)())
  check("Card:update_alert nil area.config -> no throw", pcall(_G.Card.update_alert, { area = {} }))
  check("Game:update_blind_select nil hand -> no throw", (function() G.hand = nil; return pcall(_G.Game.update_blind_select, {}) end)())
  check("save_run nil blind -> no throw", (function() G.GAME.blind = nil; return pcall(_G.save_run) end)())
  check("HUD_blind_debuff nil blind -> no throw", pcall(G.FUNCS.HUD_blind_debuff))
end

do
  local card = { area = {} }
  local ok = pcall(_G.Card.remove, card)
  check("Card:remove dead area -> no throw, area cleared", ok and card.area == nil, "area=" .. tostring(card.area))
end

do
  local ev = { func = function() error("throwaway/site.lua:1: x") end, complete = false }
  pcall(_G.Event.handle, ev, {})
  check("note() recorded a drop before reset", CrashGuards._test.drop_stats().total >= 1,
    CrashGuards._test.drop_stats().total)
  CrashGuards._test.reset()
  check("_test.reset() clears the ambient drop counters", CrashGuards._test.drop_stats().total == 0,
    CrashGuards._test.drop_stats().total)
end

do
  CrashGuards._test.reset()
  local captured = {}
  local orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    captured[#captured + 1] = table.concat(parts, "\t")
  end
  local marker = "boom-marker-9f1c2a"
  local ev = { func = function() error(marker) end, complete = false }
  pcall(_G.Event.handle, ev, {})
  print = orig_print
  local log = table.concat(captured, "\n")
  check("dropped event log includes the actual error text, not just a site key",
    log:find(marker, 1, true) ~= nil, log)
  check("dropped event log includes a stack traceback",
    log:find("stack traceback", 1, true) ~= nil, log)
end

done()
