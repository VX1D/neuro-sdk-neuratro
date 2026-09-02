local Guard = {}
local Utils = require("util.utils")
local gate_now = Utils.gate_now

local STOP_USE_GATED = {
  use_consumable = true, use_directional_consumable = true,
  choose_pack_card = true, choose_directional_pack_card = true, skip_pack = true,
}
-- select_blind reuses skip_blind's lock as a heuristic delay, giving a skipped tag's reward time
-- to resolve on G.E_MANAGER.
local LOCK = { leave_shop = "leave_shop", reroll_shop = "shop_reroll", skip_blind = "skip_blind",
  select_blind = "skip_blind" }
local LATCH = { cash_out = 1.0, select_blind = 0.8, reroll_boss = 0.5, skip_pack = 0.8 }

local last = {}
local BUSY_TAIL = "Wait a moment, then choose again."
Guard.BUSY_TAIL = BUSY_TAIL
local BUSY = "That just fired and is still resolving on screen. " .. BUSY_TAIL
Guard.BUSY = BUSY

local LOCK_LEAK_S = 5.0
local lock_seen = {}
local engine_blocked_at
local engine_failsafe_open = false

function Guard.stop_use_active()
  return not not (G and G.GAME and (tonumber(G.GAME.STOP_USE) or 0) > 0)
end

function Guard.engine_ready()
  local blocked = not Utils.engine_settled()
    or not not (G and G.CONTROLLER and G.CONTROLLER.locked)
    or Guard.stop_use_active()
  if not blocked then
    engine_blocked_at = nil
    engine_failsafe_open = false
    return true
  end
  local t = gate_now("engine_gate_failsafe")
  if not engine_blocked_at then engine_blocked_at = t end
  engine_failsafe_open = (t - engine_blocked_at)
    >= Utils.gate_seconds("engine_gate_failsafe", "NEURO_ENGINE_GATE_FAILSAFE")
  return engine_failsafe_open
end

function Guard.reject_reason(name)
  if STOP_USE_GATED[name] and Guard.stop_use_active() and not engine_failsafe_open then
    return BUSY
  end
  local lk = LOCK[name]
  if lk and G and G.CONTROLLER and G.CONTROLLER.locks then
    if G.CONTROLLER.locks[lk] then
      local t = gate_now("controller_lock_leak")
      local e = lock_seen[lk]
      if not e or (t - e.last) > LOCK_LEAK_S then e = { first = t } end
      e.last = t
      lock_seen[lk] = e
      if (t - e.first) < LOCK_LEAK_S then return BUSY end
    else
      lock_seen[lk] = nil
    end
  end
  local w = LATCH[name]
  if w then
    local t = last[name]
    if t and (gate_now("action_settle_latch") - t) < w then return BUSY end
  end
  return nil
end

function Guard.mark(name)
  if LATCH[name] then last[name] = gate_now("action_settle_latch") end
end

function Guard.reset()
  last = {}
  lock_seen = {}
  engine_blocked_at = nil
  engine_failsafe_open = false
end

return Guard
