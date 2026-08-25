local M = {}

local Metrics = require("util.metrics")

local _drops_total = 0
local _drops_by_site = {}
local _log_next = {}

local _save_skip_total = 0
local _save_skip_log_next = 1

local function note_save_skip()
  _save_skip_total = _save_skip_total + 1
  Metrics.incr("crash_guard_save_skip")
  if _save_skip_total < _save_skip_log_next then return end
  _save_skip_log_next = _save_skip_total * 10
  print(string.format("[neuro-game] crash_guard: skipped save_run, game state incomplete (x%d)", _save_skip_total))
end

local function note(msg)
  local text = tostring(msg)
  local key = text:match("[%w_./]+%.lua:%d+") or text
  local n = (_drops_by_site[key] or 0) + 1
  _drops_by_site[key] = n
  _drops_total = _drops_total + 1
  Metrics.incr("crash_guard_event_drop")
  local next_at = _log_next[key]
  if next_at and n < next_at then return end
  _log_next[key] = n * 10
  print(string.format("[neuro-game] crash_guard: dropped throwing event/callback @ %s (x%d, %d total)\n%s",
    key, n, _drops_total, text))
end

local function drop_stats()
  local by_site = {}
  for k, v in pairs(_drops_by_site) do by_site[k] = v end
  return { total = _drops_total, by_site = by_site }
end

local function save_skip_total()
  return _save_skip_total
end

local function reset()
  _drops_total = 0
  _drops_by_site = {}
  _log_next = {}
  _save_skip_total = 0
  _save_skip_log_next = 1
end

local function guard_method(holder, name, flag_key, should_skip)
  if type(holder) ~= "table" or type(holder[name]) ~= "function" or holder[flag_key] then return false end
  holder[flag_key] = true
  local orig = holder[name]
  holder[name] = function(self, ...)
    if should_skip(self, ...) then return end
    return orig(self, ...)
  end
  return true
end

local function wrap_event_handle()
  local Event = rawget(_G, "Event")
  if type(Event) ~= "table" or type(Event.handle) ~= "function" or Event.__neuro_event_guarded then return false end
  Event.__neuro_event_guarded = true
  local orig = Event.handle
  Event.handle = function(self, _results)
    local ok, err = xpcall(orig, debug.traceback, self, _results)
    if not ok then
      if type(_results) == "table" then _results.completed = true; _results.time_done = true end
      self.complete = true
      note(err)
    end
  end
  return true
end

function M.install_pack_area_guard()
  local CardArea = rawget(_G, "CardArea")
  if type(CardArea) ~= "table" or type(CardArea.remove) ~= "function" or CardArea.__neuro_cardarea_guard then return end
  CardArea.__neuro_cardarea_guard = true
  local orig_remove = CardArea.remove
  CardArea.remove = function(self, ...)
    if G then
      if self == G.pack_cards then G.pack_cards = nil end
      if self == G.booster_pack then G.booster_pack = nil end
    end
    return orig_remove(self, ...)
  end
  guard_method(CardArea, "align_cards", "__neuro_cardarea_align_guard",
    function(self) return not (self and self.cards) end)
  guard_method(CardArea, "emplace", "__neuro_cardarea_emplace_guard",
    function(self) return not (self and self.cards) end)
end

function M.install()
  wrap_event_handle()
  pcall(function() require("core.joker_recorder").install() end)
  pcall(function() require("core.joker_hits").install() end)

  guard_method(rawget(_G, "Moveable"), "move", "__neuro_move_guard",
    function(self) return not (self and self.FRAME) end)

  guard_method(rawget(_G, "Card"), "update_alert", "__neuro_alert_guard",
    function(self) return self and self.area and not self.area.config end)

  guard_method(rawget(_G, "Game"), "update_blind_select", "__neuro_bs_guard",
    function() return not (G and G.hand and G.hand.T and G.jokers and G.jokers.T) end)

  do
    local Card = rawget(_G, "Card")
    if type(Card) == "table" and type(Card.remove) == "function" and not Card.__neuro_remove_guard then
      Card.__neuro_remove_guard = true
      local orig = Card.remove
      Card.remove = function(self, ...)
        if self and self.area and type(self.area.remove_card) ~= "function" then self.area = nil end
        local result = orig(self, ...)
        pcall(function() require("core.joker_recorder").prune_owned() end)
        return result
      end
    end
  end

  if type(_G.save_run) == "function" and not _G.__neuro_save_guard then
    _G.__neuro_save_guard = true
    local orig = _G.save_run
    _G.save_run = function(...)
      local gm = G and G.GAME
      if not (gm and gm.blind and gm.current_scoring_calculation and gm.selected_back) then
        note_save_skip()
        return
      end
      return orig(...)
    end
  end

  if G and G.FUNCS then
    guard_method(G.FUNCS, "HUD_blind_debuff", "__neuro_hud_blind_guard",
      function() return not (G and G.GAME and G.GAME.blind) end)
    guard_method(G.FUNCS, "SMODS_scoring_calculation_function", "__neuro_score_guard",
      function() return not (G and G.GAME and G.GAME.current_scoring_calculation) end)
  end
end

M.reset_run_state = reset

if rawget(_G, "NEURO_TEST") then
  M._test = {
    drop_stats = drop_stats,
    save_skip_total = save_skip_total,
    reset = reset,
  }
end

return M
