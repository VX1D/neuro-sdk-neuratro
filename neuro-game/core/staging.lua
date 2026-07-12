
local Staging = {}
local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local CtxHelpers = require("context.ctx_helpers")
local ForceHelpers = require("force.force_helpers")
local TxCache = require("core.tx_cache")

local Tuning = require("core.tuning")

local HOLD_ALL_SELECTED_BASE = 1.1
local HOVER_DEFAULT_BASE     = 0.5
local POST_SELL_BASE         = 0.6
local POST_DEFAULT_BASE      = 0.5

-- Staging.update runs every frame; dedup+cooldown this print or a persistent throw spams stdout ~60x/s
local _upd_err_cd, _upd_err_last = 0, nil

local function spd()
  return Tuning.get("NEURO_SPEED_MULT")
end

local function tuned(key)
  return Tuning.get(key) * spd()
end

local function failsafe_s()
  local f = Tuning.get("NEURO_STAGING_FAILSAFE")
  return math.max(f, f * spd())
end

local DEBUG_STAGING = Tuning.bool("NEURO_STAGING_DEBUG")

-- derived from Actions.INFO_ACTIONS so a new read-only action can't silently get hover-staged
local Actions = require("core.actions")
local INFO_ACTIONS = { choose_persona = true }
for k in pairs(Actions.INFO_ACTIONS or {}) do INFO_ACTIONS[k] = true end

local staged = nil
local _executor = nil
local post_until = 0
local overlay_text = nil
local clear_hovers
local now
local pending_ids = {}
local debug_state = {
  last_fault = nil,
  last_fault_at = 0,
  last_event = nil,
  last_event_at = 0,
}

local function pending_count()
  local n = 0
  for _ in pairs(pending_ids) do n = n + 1 end
  return n
end

local function debug_mark(event, fault)
  if not DEBUG_STAGING then return end
  local t = now and now() or os.clock()
  if event then
    debug_state.last_event = tostring(event)
    debug_state.last_event_at = t
  end
  if fault then
    local s = tostring(fault):gsub("\n", " ")
    if #s > 220 then s = s:sub(1, 217) .. "..." end
    debug_state.last_fault = s
    debug_state.last_fault_at = t
  end
end

local function msg_action_id(msg)
  if not msg or not msg.data then return nil end
  local id = msg.data.id
  if id == nil then return nil end
  return tostring(id)
end

local function cancel_staged(reason, transient)
  if not staged then return end
  pcall(clear_hovers, staged.hover_cards)

  local msg = staged.msg
  local bridge = staged.bridge
  local id = msg and msg.data and msg.data.id
  if id ~= nil then
    pending_ids[tostring(id)] = nil
  end
  if id and bridge and bridge.send_action_result then
    pcall(bridge.send_action_result, bridge, id, false, reason or "Action cancelled")
    -- transient cancels are retryable; do not settle the id or a retry replays the cancellation
    if not transient then
      TxCache.store(id, false, reason or "Action cancelled")
    end
  end

  if G and G.NEURO then
    ForceHelpers.set_action_phase("cancelled")
  end

  staged = nil
  overlay_text = nil
  debug_mark("cancelled", reason or "Action cancelled")
end

now = Utils.now

local function card_effect(card)
  if not card then return nil end
  local ab = card.ability or {}
  local parts = CtxHelpers.effect_parts(ab)
  if parts[1] then return parts[1] end
  if ab.extra then
    if type(ab.extra) == "table" then
      if ab.extra.x_mult then return "x" .. ab.extra.x_mult .. " Mult" end
      if ab.extra.mult then return "+" .. ab.extra.mult .. " Mult" end
      if ab.extra.chips then return "+" .. ab.extra.chips .. " Chips" end
      if ab.extra.money then return "+$" .. ab.extra.money end
    end
  end
  if card.cost and card.cost > 0 then return Utils.money(card.cost) end
  return nil
end

local function card_name(card)
  if not card then return "Card" end
  if card.base and card.base.value and card.base.suit then
    return Utils.playing_card_label(card)
  end
  return Utils.safe_name(card) or "Card"
end

local function resolve_payload_card(payload, cards)
  local area_name = payload.area
  if area_name then area_name = CardArea.AREA_ALIASES[area_name] or area_name end
  local idx = payload.index
  if area_name and idx then
    local area = (area_name == "booster_pack") and CardArea.get_area("booster_pack") or (G and G[area_name])
    if area and area.cards and area.cards[idx] then
      cards[#cards+1] = area.cards[idx]
    end
  end
end

local function resolve_hover(msg)
  local data = msg.data or {}
  local name = data.name
  local payload = data.data
  if type(payload) == "string" and payload ~= "" then
    local ok, d = pcall(require("util.neuro_json").decode, payload)
    if ok and type(d) == "table" then payload = d else payload = {} end
  end
  if type(payload) ~= "table" then payload = {} end

  local cards = {}
  local hover_dur = HOVER_DEFAULT_BASE * spd()
  local post_dur = POST_DEFAULT_BASE * spd()
  local label = name or "action"
  local juice_scale = 0.5
  local juice_rot = 0.3

  if name == "play_hand" or name == "discard_hand" then
    if payload.indices and G and G.hand and G.hand.cards then
      for _, idx in ipairs(payload.indices) do
        if G.hand.cards[idx] then
          cards[#cards + 1] = G.hand.cards[idx]
        end
      end
    end
    hover_dur = tuned("NEURO_HOVER_PER_CARD")
    if name == "play_hand" then
      label = "Playing hand"
      post_dur = tuned("NEURO_POST_PLAY")
    else
      label = "Discarding"
      post_dur = tuned("NEURO_POST_DISCARD")
    end

  elseif name == "buy_from_shop" then
    resolve_payload_card(payload, cards)
    hover_dur = tuned("NEURO_HOVER_SHOP")
    post_dur = tuned("NEURO_POST_BUY")
    juice_scale = 0.8
    juice_rot = 0.5
    local cname = #cards > 0 and card_name(cards[1]) or "item"
    local cfx = #cards > 0 and card_effect(cards[1]) or nil
    local cost = #cards > 0 and cards[1].cost or 0
    label = "Buying " .. cname .. (cost > 0 and (" ($" .. cost .. ")") or "")
      .. (cfx and (" — " .. cfx) or "")

  elseif name == "use_card" then
    resolve_payload_card(payload, cards)
    hover_dur = tuned("NEURO_HOVER_SHOP")
    post_dur = tuned("NEURO_POST_BUY")
    juice_scale = 0.8
    juice_rot = 0.5
    local cname = #cards > 0 and card_name(cards[1]) or "card"
    local cfx = #cards > 0 and card_effect(cards[1]) or nil
    label = "Using " .. cname .. (cfx and (" — " .. cfx) or "")

  elseif name == "sell_card" then
    resolve_payload_card(payload, cards)
    hover_dur = HOVER_DEFAULT_BASE * spd()
    post_dur = POST_SELL_BASE * spd()
    juice_scale = 0.7
    juice_rot = 0.4
    local cname = #cards > 0 and card_name(cards[1]) or "card"
    local sell_val = #cards > 0 and (cards[1].sell_cost or 0) or 0
    label = "Selling " .. cname .. (sell_val > 0 and (" (+$" .. sell_val .. ")") or "")

  elseif name == "select_blind" then
    hover_dur = 0
    post_dur = 0.4
    local b = payload.blind or "?"
    label = "Fighting " .. b .. " blind"

  elseif name == "skip_blind" then
    hover_dur = 0
    post_dur = 0.3
    label = "Skipping blind"

  elseif name == "reroll_shop" then
    hover_dur = 0
    post_dur = 0.6
    local money = G and G.GAME and G.GAME.dollars or 0
    label = "Rerolling shop ($" .. money .. " left)"

  elseif name == "cash_out" then
    hover_dur = 0
    post_dur = 0.3
    label = "Cashing out"

  elseif name == "start_run" or name == "start_setup_run" or name == "start_challenge_run" then
    hover_dur = 0
    post_dur = 0.3
    label = "Starting run"
  end

  return cards, hover_dur, post_dur, label, juice_scale, juice_rot
end

local function hover_card(card, juice_scale, juice_rot)
  if not card then return end
  CardArea.set_highlight(card, true)
  card.hovering = false
  if card.juice_up and not card._neuro_juiced then
    card:juice_up(juice_scale or 0.25, juice_rot or 0.12)
    card._neuro_juiced = true
  end
end

local function unhover_card(card)
  if not card then return end
  CardArea.set_highlight(card, false)
  card.hovering = false
  card._neuro_juiced = nil
end

clear_hovers = function(cards)
  if not cards then return end
  for _, c in ipairs(cards) do
    pcall(unhover_card, c)
  end
end

function Staging.should_stage(msg)
  if not msg or not msg.data or msg.command ~= "action" then return false end
  local name = msg.data.name
  if not name then return false end
  if INFO_ACTIONS[name] then return false end
  -- skip hover for a play the boss size-rule will reject anyway (e.g. Psychic's "must play 5") so rejection is instant
  if name == "play_hand" and G and G.GAME and G.GAME.blind then
    local ok, err = pcall(function()
      local d = msg.data or {}
      local count = (type(d.indices) == "table") and #d.indices or 0
      local blind = G.GAME.blind
      local debuff = (not blind.disabled) and blind.debuff or nil
      return CardArea.blind_size_rule_error(debuff, count)
    end)
    if ok and err then return false end
  end
  return true
end

function Staging.set_executor(fn) _executor = fn end

function Staging.queue(msg, bridge)
  local id = msg_action_id(msg)
  if id and pending_ids[id] then
    debug_mark("duplicate id ignored", nil)
    return false
  end

  if staged then
    cancel_staged("Action cancelled: replaced by newer action")
  end

  local ok_resolve, cards, hover_dur, post_dur, label, j_scale, j_rot = pcall(resolve_hover, msg)
  if not ok_resolve then
    local raw_id = msg.data and msg.data.id
    if raw_id ~= nil and bridge and bridge.send_action_result then
      bridge:send_action_result(raw_id, false, "Staging resolve failed: " .. tostring(cards))
      TxCache.store(raw_id, false, "Staging resolve failed")
    end
    if G and G.NEURO then
      ForceHelpers.record_failure(msg.data and msg.data.name or "action", "the action could not be staged")
      ForceHelpers.set_action_phase("failed")
    end
    debug_mark("resolve failed", cards)
    return false
  end
  local is_multi = (#cards > 1 and (msg.data.name == "play_hand" or msg.data.name == "discard_hand"))

  staged = {
    msg = msg,
    bridge = bridge,
    hover_cards = cards,
    hover_idx = 0,
    hover_dur = hover_dur,
    post_dur = post_dur,
    label = label,
    multi = is_multi,
    juice_scale = j_scale or 0.5,
    juice_rot = j_rot or 0.3,
    phase = "HOVER",
    start = now(),
    state_at_queue = (function()
      local State = Utils.lazy_require("core.state")
      return (State and State.get_state_name and State.get_state_name())
        or (G and G.NEURO and G.NEURO.state) or nil
    end)(),
  }
  if id then
    pending_ids[id] = true
  end
  if G and G.NEURO then
    ForceHelpers.set_action_phase("queued")
  end
  debug_mark("queued " .. tostring(msg.data and msg.data.name or "?"), nil)
  overlay_text = label .. "..."

  if #cards == 0 then
    staged.phase = "EXECUTE"
  end
  return true
end

function Staging.update()
  local ok, err = pcall(function()
    local t = now()

    if not staged then return end

    if (t - (staged.start or t)) > failsafe_s() then
      cancel_staged("Action cancelled: staging timeout", true)
      return
    end

    -- compare LIVE state: the G.NEURO.state mirror lags Staging.update by a frame, so a staged action could execute in the new state
    local State = Utils.lazy_require("core.state")
    local live_state = State and State.get_state_name and State.get_state_name()
    -- an unresolvable live_state (nil) must also cancel, not just a state mismatch
    if staged.state_at_queue and (not live_state or live_state ~= staged.state_at_queue) then
      cancel_staged("Action cancelled: game state changed", true)
      return
    end

    if staged.phase == "HOVER" then
      local cards = staged.hover_cards
      local elapsed = t - staged.start

      if #cards == 0 then
        staged.phase = "EXECUTE"
      elseif staged.multi then
        local total_select_time = #cards * staged.hover_dur
        local total_time = total_select_time + HOLD_ALL_SELECTED_BASE * spd()

        if elapsed >= total_time then
          staged.phase = "EXECUTE"
        elseif elapsed >= total_select_time then
          if not staged.locked_in then
            staged.locked_in = true
            for i = 1, #cards do
              local c = cards[i]
              if c and c.juice_up then
                pcall(c.juice_up, c, (staged.juice_scale or 0.5) * 1.5, (staged.juice_rot or 0.3) * 1.3)
              end
            end
          else
            for i = 1, #cards do
              pcall(hover_card, cards[i], staged.juice_scale, staged.juice_rot)
            end
          end
          overlay_text = staged.label .. " (" .. #cards .. " cards)"
        else
          local card_idx = math.floor(elapsed / staged.hover_dur) + 1
          if card_idx > #cards then card_idx = #cards end

          if card_idx ~= staged.hover_idx then
            staged.hover_idx = card_idx
            pcall(hover_card, cards[card_idx], staged.juice_scale, staged.juice_rot)
            overlay_text = "Selecting: " .. card_name(cards[card_idx]) .. " (" .. card_idx .. "/" .. #cards .. ")"
          end

          for i = 1, card_idx do
            pcall(hover_card, cards[i], staged.juice_scale, staged.juice_rot)
          end
        end
      else
        if elapsed >= staged.hover_dur then
          pcall(clear_hovers, cards)
          staged.phase = "EXECUTE"
        else
          pcall(hover_card, cards[1], staged.juice_scale, staged.juice_rot)
          local cfx = card_effect(cards[1])
          overlay_text = card_name(cards[1]) .. (cfx and (" — " .. cfx) or "")
        end
      end

    elseif staged.phase == "EXECUTE" then
      overlay_text = staged.label
      pcall(clear_hovers, staged.hover_cards)
      if G and G.NEURO then
        ForceHelpers.set_action_phase("executing", t)
      end

      local exec = _executor or require("core.dispatcher").handle_message
      local ok_exec, exec_err = pcall(exec, staged.msg, staged.bridge)
      if not ok_exec then
        local id = staged.msg and staged.msg.data and staged.msg.data.id
        if id ~= nil then
          pending_ids[tostring(id)] = nil
        end
        if id and staged.bridge and staged.bridge.send_action_result then
          pcall(staged.bridge.send_action_result, staged.bridge, id, false, "Staged action failed: " .. tostring(exec_err))
          TxCache.store(id, false, "Staged action failed")
        end
        if G and G.NEURO then
          ForceHelpers.set_action_phase("failed", t)
        end
        debug_mark("execute failed", exec_err)
      else
        local id = staged.msg and staged.msg.data and staged.msg.data.id
        if id ~= nil then
          pending_ids[tostring(id)] = nil
        end
        debug_mark("executed", nil)
      end

      post_until = t + staged.post_dur
      overlay_text = staged.label
      staged = nil
    end
  end)

  if not ok then
    local msg = tostring(err)
    local clk = Utils.now()
    if clk > _upd_err_cd or msg ~= _upd_err_last then
      print("[neuro-game] staging update error: " .. msg)
      _upd_err_last = msg
      _upd_err_cd = clk + 5
    end
    debug_mark("update panic", err)
    if staged then
      cancel_staged("Action cancelled: staging runtime error")
    end
  end
end

function Staging.is_busy()
  if staged then return true end
  if now() < post_until then return true end
  return false
end

function Staging.get_overlay_text()
  if not staged and now() >= post_until and overlay_text then
    overlay_text = nil
  end
  return overlay_text
end

function Staging.on_state_change()
  if staged then
    cancel_staged("Action cancelled: state transition", true)
  end
end

function Staging.mark_settled(action_id, ok)
  if action_id == nil then return end
  pending_ids[tostring(action_id)] = nil
  if G and G.NEURO then
    ForceHelpers.set_action_phase(ok and "resolved" or "failed")
  end
  if ok then debug_mark("resolved") else debug_mark("failed", "action result failed") end
end

function Staging.get_debug_lines()
  if not DEBUG_STAGING then return {} end

  local out = {}
  local t = now()
  local sid = staged and msg_action_id(staged.msg) or "-"
  local sname = staged and staged.msg and staged.msg.data and staged.msg.data.name or "-"
  local sphase = staged and staged.phase or "idle"
  local selapsed = staged and (t - (staged.start or t)) or 0
  local post_left = math.max(0, post_until - t)
  out[#out + 1] = string.format("stg id:%s action:%s phase:%s", tostring(sid), tostring(sname), tostring(sphase))
  out[#out + 1] = string.format("elapsed:%.2fs post:%.2fs pending:%d", selapsed, post_left, pending_count())

  if debug_state.last_event then
    local age = t - (debug_state.last_event_at or t)
    out[#out + 1] = string.format("event(%.1fs): %s", age, tostring(debug_state.last_event))
  end

  if debug_state.last_fault then
    local age = t - (debug_state.last_fault_at or t)
    out[#out + 1] = string.format("FAULT(%.1fs): %s", age, tostring(debug_state.last_fault))
  end

  return out
end

return Staging
