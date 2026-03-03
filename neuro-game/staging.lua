
local Staging = {}
local Utils = require "utils"

local HOVER_PER_CARD    = 0.95
local HOLD_ALL_SELECTED = 1.1
local HOVER_SHOP        = 1.0
local HOVER_PACK        = 0.8
local HOVER_DEFAULT     = 0.5
local POST_PLAY         = 1.4
local POST_DISCARD      = 0.9
local POST_BUY          = 0.8
local POST_SELL         = 0.6
local POST_DEFAULT      = 0.5
local PRE_NO_HOVER      = 0.2
local STAGING_FAILSAFE_S = 12.0

local NEURO_SPEED_MULT = tonumber(os.getenv("NEURO_SPEED_MULT") or "") or 1.0
NEURO_SPEED_MULT = math.max(0.1, math.min(2.0, NEURO_SPEED_MULT))

HOVER_PER_CARD    = HOVER_PER_CARD * NEURO_SPEED_MULT
HOLD_ALL_SELECTED = HOLD_ALL_SELECTED * NEURO_SPEED_MULT
HOVER_SHOP        = HOVER_SHOP * NEURO_SPEED_MULT
HOVER_PACK        = HOVER_PACK * NEURO_SPEED_MULT
HOVER_DEFAULT     = HOVER_DEFAULT * NEURO_SPEED_MULT
POST_PLAY         = POST_PLAY * NEURO_SPEED_MULT
POST_DISCARD      = POST_DISCARD * NEURO_SPEED_MULT
POST_BUY          = POST_BUY * NEURO_SPEED_MULT
POST_SELL         = POST_SELL * NEURO_SPEED_MULT
POST_DEFAULT      = POST_DEFAULT * NEURO_SPEED_MULT
PRE_NO_HOVER      = PRE_NO_HOVER * NEURO_SPEED_MULT

local DEBUG_STAGING = false
do
  local env = os.getenv("NEURO_STAGING_DEBUG")
  if env ~= nil then
    env = tostring(env):lower()
    DEBUG_STAGING = not (env == "0" or env == "false" or env == "no")
  end
end

local INFO_ACTIONS = {
  choose_persona = true,
  scoring_explanation = true, joker_strategy = true, blind_info = true,
  hand_levels_info = true, shop_context = true, consumables_info = true,
  hand_details = true, deck_composition = true, owned_vouchers = true,
  round_history = true, neuratro_info = true, full_game_context = true,
  quick_status = true, help = true, joker_info = true,
  card_modifiers_information = true, deck_type = true,
  get_poker_hand_information = true, simulate_hand = true,
}

local staged = nil
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

local function cancel_staged(reason)
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
  end

  if G then
    G.NEURO.action_phase = "cancelled"
    G.NEURO.action_phase_at = now()
  end

  staged = nil
  overlay_text = nil
  debug_mark("cancelled", reason or "Action cancelled")
end

now = function()
  if G and G.TIMERS and G.TIMERS.REAL then return G.TIMERS.REAL end
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function card_effect(card)
  if not card then return nil end
  local ab = card.ability or {}
  if ab.x_mult and ab.x_mult > 1 then return "x" .. ab.x_mult .. " Mult" end
  if ab.h_mult then return "+" .. ab.h_mult .. " Mult" end
  if ab.h_mod then return "+" .. ab.h_mod .. " Chips" end
  if ab.t_mult then return "+" .. ab.t_mult .. " Mult/trigger" end
  if ab.d_mult then return "+" .. ab.d_mult .. " Mult/discard" end
  if ab.extra then
    if type(ab.extra) == "table" then
      if ab.extra.x_mult then return "x" .. ab.extra.x_mult .. " Mult" end
      if ab.extra.mult then return "+" .. ab.extra.mult .. " Mult" end
      if ab.extra.chips then return "+" .. ab.extra.chips .. " Chips" end
      if ab.extra.money then return "+$" .. ab.extra.money end
    end
  end
  if card.cost and card.cost > 0 then return "$" .. card.cost end
  return nil
end

local function card_name(card)
  if not card then return "Card" end
  if card.base and card.base.value and card.base.suit then
    return card.base.value .. " of " .. card.base.suit
  end
  return Utils.safe_name(card) or "Card"
end

local function resolve_payload_card(payload, cards)
  local area_name = payload.area
  local idx = payload.index
  if area_name and idx then
    local area = (area_name == "booster_pack") and G.booster_pack or (G and G[area_name])
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
    local ok, d = pcall(require("neuro_json").decode, payload)
    if ok and type(d) == "table" then payload = d else payload = {} end
  end
  if type(payload) ~= "table" then payload = {} end

  local cards = {}
  local hover_dur = HOVER_DEFAULT
  local post_dur = POST_DEFAULT
  local label = name or "action"
  local juice_scale = 0.5
  local juice_rot = 0.3

  if name == "set_hand_highlight" then
    if payload.indices and G and G.hand and G.hand.cards then
      for _, idx in ipairs(payload.indices) do
        if G.hand.cards[idx] then
          cards[#cards + 1] = G.hand.cards[idx]
        end
      end
    end
    hover_dur = HOVER_PER_CARD
    post_dur = POST_DEFAULT
    if payload.action == "play" then
      label = "Playing hand"
      post_dur = POST_PLAY
    elseif payload.action == "discard" then
      label = "Discarding"
      post_dur = POST_DISCARD
    else
      label = "Selecting cards"
    end

  elseif name == "play_cards_from_highlighted" then
    cards = {}
    hover_dur = 0.1
    post_dur = POST_PLAY
    label = "Playing hand"

  elseif name == "discard_cards_from_highlighted" then
    cards = {}
    hover_dur = 0.1
    post_dur = POST_DISCARD
    label = "Discarding"

  elseif name == "buy_from_shop" then
    resolve_payload_card(payload, cards)
    hover_dur = HOVER_SHOP
    post_dur = POST_BUY
    juice_scale = 0.8
    juice_rot = 0.5
    local cname = #cards > 0 and card_name(cards[1]) or "item"
    local cfx = #cards > 0 and card_effect(cards[1]) or nil
    local cost = #cards > 0 and cards[1].cost or 0
    label = "Buying " .. cname .. (cost > 0 and (" ($" .. cost .. ")") or "")
      .. (cfx and (" — " .. cfx) or "")

  elseif name == "use_card" then
    resolve_payload_card(payload, cards)
    hover_dur = HOVER_SHOP
    post_dur = POST_BUY
    juice_scale = 0.8
    juice_rot = 0.5
    local cname = #cards > 0 and card_name(cards[1]) or "card"
    local cfx = #cards > 0 and card_effect(cards[1]) or nil
    label = "Using " .. cname .. (cfx and (" — " .. cfx) or "")

  elseif name == "sell_card" then
    resolve_payload_card(payload, cards)
    hover_dur = HOVER_DEFAULT
    post_dur = POST_SELL
    juice_scale = 0.7
    juice_rot = 0.4
    local cname = #cards > 0 and card_name(cards[1]) or "card"
    local sell_val = #cards > 0 and (cards[1].sell_cost or 0) or 0
    label = "Selling " .. cname .. (sell_val > 0 and (" (+$" .. sell_val .. ")") or "")

  elseif name == "card_click" or name == "highlight_card" then
    resolve_payload_card(payload, cards)
    hover_dur = HOVER_PACK
    post_dur = POST_DEFAULT
    juice_scale = 0.8
    juice_rot = 0.5
    local cname = #cards > 0 and card_name(cards[1]) or "card"
    label = "Picking " .. cname

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

  elseif name == "cash_out" or name == "next_round" then
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
  card.highlighted = true
  if G and G.NEURO.ai_highlighted then G.NEURO.ai_highlighted[card] = true end
  card.hovering = false
  if card.juice_up and not card._neuro_juiced then
    card:juice_up(juice_scale or 0.25, juice_rot or 0.12)
    card._neuro_juiced = true
  end
end

local function unhover_card(card)
  if not card then return end
  card.highlighted = false
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
  if name == "play_cards_from_highlighted" or name == "discard_cards_from_highlighted" then
    return false
  end
  if INFO_ACTIONS[name] then return false end
  return true
end

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
    local id = msg_action_id(msg)
    if id and bridge and bridge.send_action_result then
      bridge:send_action_result(id, false, "Staging resolve failed: " .. tostring(cards))
    end
    if G then
      G.NEURO.action_phase = "failed"
      G.NEURO.action_phase_at = now()
    end
    debug_mark("resolve failed", cards)
    return false
  end
  local is_multi = (#cards > 1 and (msg.data.name == "set_hand_highlight"))

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
    state_at_queue = G and G.NEURO.state or nil,
  }
  if id then
    pending_ids[id] = true
  end
  if G then
    G.NEURO.action_phase = "queued"
    G.NEURO.action_phase_at = now()
  end
  debug_mark("queued " .. tostring(msg.data and msg.data.name or "?"), nil)
  overlay_text = label .. "..."

  if #cards == 0 and hover_dur <= 0 then
    staged.phase = "EXECUTE"
  end
  return true
end

function Staging.update(dt)
  local ok, err = pcall(function()
    local t = now()

    if not staged then return end

    if (t - (staged.start or t)) > STAGING_FAILSAFE_S then
      cancel_staged("Action cancelled: staging timeout")
      return
    end

    if staged.state_at_queue and G and G.NEURO.state ~= staged.state_at_queue then
      cancel_staged("Action cancelled: game state changed")
      return
    end

    if staged.phase == "HOVER" then
      local cards = staged.hover_cards
      local elapsed = t - staged.start

      if #cards == 0 then
        if elapsed >= (staged.hover_dur > 0 and staged.hover_dur or PRE_NO_HOVER) then
          staged.phase = "EXECUTE"
        end
      elseif staged.multi then
        local total_select_time = #cards * staged.hover_dur
        local total_time = total_select_time + HOLD_ALL_SELECTED

        if elapsed >= total_time then
          staged.phase = "EXECUTE"
        elseif elapsed >= total_select_time then
          for i = 1, #cards do
            pcall(hover_card, cards[i], staged.juice_scale, staged.juice_rot)
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
      if G then
        G.NEURO.action_phase = "executing"
        G.NEURO.action_phase_at = t
      end

      local NeuroDispatcher = require("dispatcher")
      local ok_exec, exec_err = pcall(NeuroDispatcher.handle_message, staged.msg, staged.bridge)
      if not ok_exec then
        local id = staged.msg and staged.msg.data and staged.msg.data.id
        if id ~= nil then
          pending_ids[tostring(id)] = nil
        end
        if id and staged.bridge and staged.bridge.send_action_result then
          pcall(staged.bridge.send_action_result, staged.bridge, id, false, "Staged action failed: " .. tostring(exec_err))
        end
        if G then
          G.NEURO.action_phase = "failed"
          G.NEURO.action_phase_at = t
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
    print("[neuro-staging] update error: " .. tostring(err))
    debug_mark("update panic", err)
    if staged then
      cancel_staged("Action cancelled: staging runtime error")
    end
  end
end

function Staging.is_busy()
  if staged then return true end
  if now() < post_until then return true end
  if overlay_text then overlay_text = nil end
  return false
end

function Staging.get_overlay_text()
  if not staged and now() >= post_until and overlay_text then
    overlay_text = nil
  end
  return overlay_text
end

function Staging.clear_overlay()
  overlay_text = nil
end

function Staging.on_state_change()
  if staged then
    cancel_staged("Action cancelled: state transition")
  end
end

function Staging.mark_settled(action_id, ok)
  if action_id == nil then return end
  pending_ids[tostring(action_id)] = nil
  if G then
    G.NEURO.action_phase = ok and "resolved" or "failed"
    G.NEURO.action_phase_at = now()
  end
  debug_mark(ok and "resolved" or "failed", ok and nil or "action result failed")
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
