
local Staging = {}
local Utils = require("util.utils")
local CardArea = require("facts.card_area_util")
local GameActions = require("core.game_actions")
local CtxHelpers = require("context.ctx_helpers")
local ForceState = require("core.force_state")
local TxCache = require("core.tx_cache")
local json = require("util.neuro_json")

local Tuning = require("core.config")
local Metrics = require("util.metrics")

local _preflight_error_seen = {}
local function report_preflight_error(label, err)
  Metrics.incr("staging_preflight_error")
  local msg = Utils.safe_tostring(err)
  if _preflight_error_seen[label] ~= msg then
    print("[neuro-game] staging preflight error (" .. label .. "): " .. msg)
    _preflight_error_seen[label] = msg
  end
end

local _upd_err_cd, _upd_err_last = 0, nil

local function spd()
  return Tuning.get("NEURO_SPEED_MULT")
end

local function tuned(gate_id, key)
  return Utils.gate_seconds(gate_id, key) * spd()
end

local LIFT_FRAC = 0.65
local ENGINE_LIFT_S = 0.4
local GS_MIN, GS_MAX = 0.5, 4
local HOVER_FLOOR_S = 0.25
local PER_CARD_FLOOR_S = 0.20
local HOLD_FLOOR_S = 0.30

local function game_speed()
  local gs = tonumber(G and G.SETTINGS and G.SETTINGS.GAMESPEED) or 1
  if gs < GS_MIN then return GS_MIN end
  if gs > GS_MAX then return GS_MAX end
  return gs
end

-- The staging timeline runs on the game clock, so a duration whose own gate is on REAL -- the card's
-- spring motion (dump game.lua:2760-2765) and the commit events the handlers put on the REAL timer --
-- has to be converted onto it rather than copied.
local function on_timeline(gate_id, seconds)
  if Utils.gate_clock(gate_id) == "REAL" then return seconds * game_speed() end
  return seconds
end

local function off_timeline(gate_id, seconds)
  if Utils.gate_clock(gate_id) == "REAL" then return seconds / game_speed() end
  return seconds
end

local function paced(gate_id, key, floor_wall_s)
  local v = Utils.gate_seconds(gate_id, key) * spd()
  local floor_s = on_timeline("staging_engine_floor", floor_wall_s)
  if v < floor_s then return floor_s end
  return v
end

local function lift_safe_commit(commit_dur, hover_dur)
  local floor_s = on_timeline("staging_engine_floor", ENGINE_LIFT_S) - (1 - LIFT_FRAC) * hover_dur
  if commit_dur < floor_s then return floor_s end
  return commit_dur
end

function Staging.lift_safe_delay(seconds)
  local entry = Staging._executing_entry()
  local cards = entry and entry.hover_cards
  if not (cards and #cards > 0) then return seconds end
  return lift_safe_commit(seconds, entry.hover_dur or 0)
end

local SHOP_ATTACK_ACTIONS = { buy_from_shop = true }

local function failsafe_s()
  local f = Utils.gate_seconds("staging_failsafe", "NEURO_STAGING_FAILSAFE")
  return math.max(f, f * spd())
end

local function DEBUG_STAGING() return Tuning.bool("NEURO_STAGING_DEBUG") end

local INFO_ACTIONS = { choose_persona = true }

local ACTION_LABELS = {
  change_selected_back = "Changing deck",
  change_stake = "Changing stake",
  change_challenge_description = "Browsing challenge",
  set_joker_order = "Reordering jokers",
  set_joker_intents = "Tagging jokers",
  toggle_seeded_run = "Toggling seeded run",
  paste_seed = "Pasting seed",
  copy_seed = "Copying seed",
  toggle_shop = "Leaving shop",
  exit_overlay_menu = "Closing popup",
  setup_run = "Opening run setup",
}

local staged = nil
local executing = nil
function Staging._executing_entry() return executing end
local _executor = nil
local _validator = nil
local post_until = 0
local glow_release = nil
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
  if not DEBUG_STAGING() then return end
  local t = now and now() or os.clock()
  if event then
    debug_state.last_event = tostring(event)
    debug_state.last_event_at = t
  end
  if fault then
    local s = Utils.safe_tostring(fault):gsub("\n", " ")
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
  local entry = staged
  if not entry then return end
  pcall(clear_hovers, entry.hover_cards)

  if entry == executing or entry.settled then
    if staged == entry then staged = nil end
    debug_mark("cancel skipped (executing)", reason)
    return
  end

  local msg = entry.msg
  local id = msg and msg.data and msg.data.id
  if id ~= nil then
    pending_ids[tostring(id)] = nil
  end
  if id ~= nil then
    pcall(function()
      require("core.dispatcher").abort_prepared(id, reason or "Action cancelled")
    end)
  end

  if G and G.NEURO then
    ForceState.set_action_phase("cancelled")
  end

  if staged == entry then staged = nil end
  debug_mark("cancelled", reason or "Action cancelled")
end

now = function() return Utils.gate_now("staging_failsafe") end

local function card_effect(card)
  if not card then return nil end
  local ab = card.ability or {}
  local parts = CtxHelpers.effect_parts(ab)
  if parts[1] then return parts[1] end
  if ab.extra then
    if type(ab.extra) == "table" then
      local xm = ab.extra.Xmult or ab.extra.x_mult or ab.extra.xmult
      if xm then return "x" .. xm .. " Mult" end
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

local function is_pack_area(area_name)
  if type(area_name) ~= "string" then return false end
  local n = CardArea.AREA_ALIASES[area_name] or area_name
  return n == "booster_pack" or n == "pack_cards"
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
  local hover_dur = paced("staging_hover", "NEURO_HOVER_DEFAULT", HOVER_FLOOR_S)
  local hold_dur = paced("staging_hold", "NEURO_HOLD_ALL_SELECTED", HOLD_FLOOR_S)
  local post_dur = tuned("staging_post", "NEURO_POST_DEFAULT")
  local commit_dur = 0
  local label = ACTION_LABELS[name] or Utils.humanize_identifier(name or "action")
  local juice_scale = 0.5
  local juice_rot = 0.3

  local is_confirmed_play = name == "confirm_play" and payload.answer == "yes"
  if name == "play_hand" or name == "discard_hand" or is_confirmed_play then
    local play_indices = payload.indices
    if is_confirmed_play then
      local HH = Utils.lazy_require("handlers.hand_handlers")
      local pend = HH and HH.pending and HH.pending()
      play_indices = pend and pend.indices or nil
    end
    if play_indices and G and G.hand and G.hand.cards then
      for _, idx in ipairs(play_indices) do
        if G.hand.cards[idx] then
          cards[#cards + 1] = G.hand.cards[idx]
        end
      end
    end
    hover_dur = paced("staging_hover", "NEURO_HOVER_PER_CARD", PER_CARD_FLOOR_S)
    if name == "discard_hand" then
      label = "Discarding"
      post_dur = tuned("staging_post", "NEURO_POST_DISCARD")
    else
      label = "Playing hand"
      post_dur = tuned("staging_post", "NEURO_POST_PLAY")
    end

  elseif name == "buy_from_shop" then
    resolve_payload_card(payload, cards)
    hover_dur = paced("staging_hover", "NEURO_HOVER_SHOP", HOVER_FLOOR_S)
    post_dur = tuned("staging_post", "NEURO_POST_BUY")
    commit_dur = on_timeline("staging_commit", Utils.gate_seconds("staging_commit", "NEURO_SHOP_BUY_DELAY") or 0)
    juice_scale = 0.8
    juice_rot = 0.5
    local cname = #cards > 0 and card_name(cards[1]) or "item"
    local cfx = #cards > 0 and card_effect(cards[1]) or nil
    local cost = #cards > 0 and cards[1].cost or 0
    label = "Buying " .. cname .. (cost > 0 and (" ($" .. cost .. ")") or "")
      .. (cfx and (" — " .. cfx) or "")

  elseif name == "use_card" or name == "use_directional_card" then
    resolve_payload_card(payload, cards)
    hover_dur = paced("staging_hover", "NEURO_HOVER_USE", HOVER_FLOOR_S)
    post_dur = tuned("staging_post", "NEURO_POST_BUY")
    if is_pack_area(payload.area) then
      commit_dur = on_timeline("staging_commit", Utils.gate_seconds("staging_commit", "NEURO_PACK_PICK_DELAY") or 0)
    end
    juice_scale = 0.8
    juice_rot = 0.5
    local cname = #cards > 0 and card_name(cards[1]) or "card"
    local cfx = #cards > 0 and card_effect(cards[1]) or nil
    label = "Using " .. cname .. (cfx and (" — " .. cfx) or "")

  elseif name == "sell_card" then
    resolve_payload_card(payload, cards)
    hover_dur = paced("staging_hover", "NEURO_HOVER_DEFAULT", HOVER_FLOOR_S)
    post_dur = tuned("staging_post", "NEURO_POST_SELL")
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

  if #cards > 0 then
    commit_dur = lift_safe_commit(commit_dur, hover_dur)
  end

  local play_like = name == "play_hand" or name == "discard_hand" or is_confirmed_play
  return cards, hover_dur, post_dur, label, juice_scale, juice_rot, commit_dur, hold_dur, play_like
end

local function glow_map()
  if not (G and G.NEURO) then return nil end
  G.NEURO.ai_glow = G.NEURO.ai_glow or setmetatable({}, { __mode = "k" })
  return G.NEURO.ai_glow
end

function Staging.glow_now()
  return Utils.gate_now("glow_window")
end

local function set_glow_windows(entry)
  local map = glow_map()
  if not map then return end
  local cards = entry.hover_cards
  if #cards == 0 then return end
  local t0 = Staging.glow_now()
  local hover = off_timeline("glow_window", entry.hover_dur)
  if entry.multi then
    local t1 = t0 + #cards * hover + off_timeline("glow_window", entry.hold_dur)
    for i, c in ipairs(cards) do
      map[c] = { t0 = t0 + (i - 1) * hover, t1 = t1 }
    end
  else
    local t1 = t0 + hover + off_timeline("glow_window", entry.commit_dur or 0)
    local name = entry.msg and entry.msg.data and entry.msg.data.name
    local attack = SHOP_ATTACK_ACTIONS[name] or nil
    local span = t1 - t0
    local lift01 = (span > 0) and (LIFT_FRAC * hover / span) or nil
    for _, c in ipairs(cards) do
      map[c] = { t0 = t0, t1 = t1, attack = attack, lift01 = lift01 }
    end
  end
end

local function juice_target_settled(card)
  if card.STATIONARY ~= true then return false end
  return Utils.engine_settled()
end

local function hover_card(card, juice_scale, juice_rot)
  if not card then return end
  if not card.highlighted then
    if not (card.area and GameActions.add_area_highlight(card.area, card)) then
      GameActions.set_highlight(card, true)
    end
  elseif G and G.NEURO and G.NEURO.ai_highlighted then
    G.NEURO.ai_highlighted[card] = true
  end
  if card.juice_up and not card._neuro_juiced and juice_target_settled(card) then
    card:juice_up(juice_scale or 0.25, juice_rot or 0.12)
    card._neuro_juiced = true
  end
end

local function unhover_card(card, keep_glow)
  if not card then return end
  if card.highlighted and card.area and type(card.area.remove_from_highlighted) == "function" then
    pcall(function() card.area:remove_from_highlighted(card) end)
  end
  GameActions.set_highlight(card, false)
  card._neuro_juiced = nil
  if not keep_glow and G and G.NEURO and G.NEURO.ai_glow then
    G.NEURO.ai_glow[card] = nil
  end
end

clear_hovers = function(cards, keep_glow)
  if not cards then return end
  for _, c in ipairs(cards) do
    pcall(unhover_card, c, keep_glow)
  end
end

local function anticipate(entry)
  if not entry or entry.anticipated or not entry.play_like then return end
  local name = entry.msg and entry.msg.data and entry.msg.data.name
  entry.anticipated = true
  local NeuroAnim = Utils.lazy_require("render.neuro-anim")
  if not NeuroAnim then return end
  if name == "discard_hand" then
    if NeuroAnim.pre_discard then pcall(NeuroAnim.pre_discard, entry.hover_cards) end
  elseif NeuroAnim.pre_play then
    pcall(NeuroAnim.pre_play, entry.hover_cards)
  end
end

local function payload_of(msg)
  local d = (msg and msg.data) or {}
  local p = d.data
  if type(p) == "string" and p ~= "" then
    local ok, dec = pcall(json.decode, p)
    if ok and type(dec) == "table" then return dec end
  end
  if type(p) == "table" then return p end
  return d
end

function Staging.should_stage(msg)
  if not msg or not msg.data or msg.command ~= "action" then return false end
  local name = msg.data.name
  if not name then return false end
  if INFO_ACTIONS[name] then return false end
  if name == "play_hand" and G and G.GAME and G.GAME.blind then
    local ok, err = pcall(function()
      local d = payload_of(msg)
      local count = (type(d.indices) == "table") and #d.indices or 0
      local blind = G.GAME.blind
      local debuff = (not blind.disabled) and blind.debuff or nil
      return CardArea.blind_size_rule_error(debuff, count,
        (require("facts.boss.legality").play_size_bounds()))
    end)
    if not ok then report_preflight_error("blind size", err) end
    if ok and err then return false end
  end
  if name == "play_hand" then
    local skip = false
    local ok_preflight, preflight_err = pcall(function()
      if not (G and G.hand and G.hand.cards) then return end
      local d = payload_of(msg)
      if type(d.indices) ~= "table" then return end
      local sel = {}
      for _, ix in ipairs(d.indices) do
        local c = G.hand.cards[ix]
        if c then sel[#sel + 1] = c end
      end
      if #sel == 0 then return end
      local HH = Utils.lazy_require("handlers.hand_handlers")
      if not (HH and HH.play_confirm_reject) then return end
      if HH.play_confirm_reject(sel) then skip = true end
    end)
    if not ok_preflight then report_preflight_error("play confirmation", preflight_err) end
    if skip then return false end
  end
  if name == "confirm_play" then
    local skip = false
    local ok_preflight, preflight_err = pcall(function()
      local d = payload_of(msg)
      if d.answer ~= "yes" then skip = true return end
      local HH = Utils.lazy_require("handlers.hand_handlers")
      local pend = HH and HH.pending and HH.pending()
      if not pend then skip = true end
    end)
    if not ok_preflight then report_preflight_error("confirm play", preflight_err) end
    if skip then return false end
  end
  if name == "use_card" or name == "use_directional_card" then
    local skip = false
    local ok_preflight, preflight_err = pcall(function()
      if require("core.decision_window").would_reject(name) then skip = true end
    end)
    if not ok_preflight then report_preflight_error("decision window", preflight_err) end
    if skip then return false end
  end
  if name == "buy_from_shop" or name == "sell_card" or name == "use_card" or name == "use_directional_card" or name == "reroll_shop" then
    local skip = false
    local ok_preflight, preflight_err = pcall(function()
      if name ~= "reroll_shop" then
        local d = payload_of(msg)
        local nm, idx = d.name, tonumber(d.index)
        if type(nm) == "string" and nm ~= "" and d.area and idx then
          local aname = CardArea.AREA_ALIASES[d.area] or d.area
          local area = (aname == "booster_pack") and CardArea.get_area("booster_pack") or (G and G[aname])
          local card = area and area.cards and area.cards[idx]
          if not card or CardArea.check_target_name(card, nm, idx, aname) then skip = true end
        end
      end
    end)
    if not ok_preflight then report_preflight_error("shop action", preflight_err) end
    if skip then return false end
  end
  return true
end

function Staging.set_executor(fn) _executor = fn end

local function set_validator(fn) _validator = fn end

function Staging.queue(msg, bridge)
  local id = msg_action_id(msg)
  if id and pending_ids[id] then
    debug_mark("duplicate id ignored", nil)
    return false
  end

  -- Hover targets resolve before validation: preflight runs the handler body, which clears
  -- G.NEURO.play_confirm -- where confirm_play's indices come from.
  local ok_resolve, cards, hover_dur, post_dur, label, j_scale, j_rot, commit_dur, hold_dur, play_like =
    pcall(resolve_hover, msg)

  local validate = _validator or require("core.dispatcher").validate_message
  local ok_validate, accepted = pcall(validate, msg, bridge)
  if not ok_validate then
    local raw_id = msg.data and msg.data.id
    if raw_id ~= nil and bridge and bridge.send_action_result
        and TxCache.get(raw_id) == nil then
      require("core.dispatcher").report_validation_crash(
        bridge, raw_id, msg.data and msg.data.name, accepted)
    end
    if G and G.NEURO then
      ForceState.record_failure(msg.data and msg.data.name or "action", "the action could not be staged")
      ForceState.set_action_phase("failed")
    end
    debug_mark("validate failed", accepted)
    return false
  end
  if not accepted then
    debug_mark("rejected at validation", nil)
    return false
  end

  if staged and staged ~= executing then
    cancel_staged("Action cancelled: replaced by newer action")
  end

  if not ok_resolve then
    debug_mark("resolve failed", cards)
    cards, hover_dur, post_dur = {}, 0, 0
    label = Utils.humanize_identifier((msg.data and msg.data.name) or "action")
    j_scale, j_rot, commit_dur, hold_dur, play_like = nil, nil, 0, 0, false
  end
  local is_multi = (#cards > 1 and play_like)

  local state_at_queue = G and G.NEURO and G.NEURO.state or nil
  do
    local State = Utils.lazy_require("core.state")
    if State and State.get_state_name then
      local ok_state, live_state = pcall(State.get_state_name)
      if ok_state and live_state then state_at_queue = live_state end
    end
  end

  staged = {
    msg = msg,
    bridge = bridge,
    hover_cards = cards,
    hover_idx = 0,
    hover_dur = hover_dur,
    post_dur = post_dur,
    commit_dur = commit_dur or 0,
    hold_dur = hold_dur or 0,
    label = label,
    multi = is_multi,
    play_like = play_like,
    juice_scale = j_scale or 0.5,
    juice_rot = j_rot or 0.3,
    phase = "HOVER",
    start = now(),
    state_at_queue = state_at_queue,
  }
  set_glow_windows(staged)
  if id then
    pending_ids[id] = true
  end
  if G and G.NEURO then
    ForceState.set_action_phase("queued")
  end
  debug_mark("queued " .. tostring(msg.data and msg.data.name or "?"), nil)

  if #cards == 0 then
    staged.phase = "EXECUTE"
  end
  return true
end

function Staging.update()
  local ok, err = pcall(function()
    local t = now()

    if glow_release and t >= glow_release.at then
      local map = G and G.NEURO and G.NEURO.ai_glow
      if map then
        for _, c in ipairs(glow_release.cards) do map[c] = nil end
      end
      glow_release = nil
    end

    if executing then return end
    if not staged then return end

    if (t - (staged.start or t)) > failsafe_s() then
      cancel_staged("Action cancelled: staging timeout")
      return
    end

    local State = Utils.lazy_require("core.state")
    local live_state = State and State.get_state_name and State.get_state_name()
    if staged.state_at_queue and (not live_state or live_state ~= staged.state_at_queue) then
      cancel_staged("Action cancelled: game state changed")
      return
    end

    if staged.phase == "HOVER" then
      local cards = staged.hover_cards
      local elapsed = t - staged.start

      if #cards == 0 then
        staged.phase = "EXECUTE"
      elseif staged.multi then
        local total_select_time = #cards * staged.hover_dur
        local total_time = total_select_time + staged.hold_dur

        if elapsed >= total_time then
          staged.phase = "EXECUTE"
        elseif elapsed >= total_select_time then
          if not staged.locked_in then
            staged.locked_in = true
            anticipate(staged)
          else
            for i = 1, #cards do
              pcall(hover_card, cards[i], staged.juice_scale, staged.juice_rot)
            end
          end
        else
          local card_idx = math.floor(elapsed / staged.hover_dur) + 1
          if card_idx > #cards then card_idx = #cards end

          if card_idx ~= staged.hover_idx then
            staged.hover_idx = card_idx
            pcall(hover_card, cards[card_idx], staged.juice_scale, staged.juice_rot)
          end

          for i = 1, card_idx do
            pcall(hover_card, cards[i], staged.juice_scale, staged.juice_rot)
          end
        end
      else
        if elapsed >= staged.hover_dur then
          anticipate(staged)
          staged.phase = "EXECUTE"
        elseif elapsed >= staged.hover_dur * LIFT_FRAC then
          pcall(hover_card, cards[1], staged.juice_scale, staged.juice_rot)
        end
      end

    elseif staged.phase == "EXECUTE" then
      local entry = staged
      local exec_name = entry.msg and entry.msg.data and entry.msg.data.name
      if not entry.play_like then
        pcall(clear_hovers, entry.hover_cards, (entry.commit_dur or 0) > 0)
      end
      if G and G.NEURO then
        ForceState.set_action_phase("executing", t)
      end

      local exec = _executor or require("core.dispatcher").handle_message
      entry.settled = true
      executing = entry
      local ok_exec, exec_err = pcall(exec, entry.msg, entry.bridge)
      executing = nil
      local id = entry.msg and entry.msg.data and entry.msg.data.id
      if id ~= nil then
        pending_ids[tostring(id)] = nil
      end
      if not ok_exec then
        if G and G.NEURO then
          pcall(ForceState.correct_optimistic, exec_name or "action",
            "the staged action failed to execute", id,
            "Your last action '" .. tostring(exec_name)
              .. "' failed to apply (internal error); the game state is unchanged -- choose again.")
          ForceState.set_action_phase("failed", t)
        end
        debug_mark("execute failed", exec_err)
      else
        debug_mark("executed", nil)
      end
      if entry.play_like then
        local result = id ~= nil and TxCache.get(id) or nil
        if id ~= nil and (not result or not result.ok) then
          pcall(clear_hovers, entry.hover_cards)
        end
      end

      if staged == entry then
        if (entry.commit_dur or 0) > 0 then
          glow_release = {
            cards = entry.hover_cards,
            at = entry.start + entry.hover_dur + entry.commit_dur,
          }
        end
        post_until = t + entry.post_dur
        staged = nil
      end
    end
  end)

  if not ok then
    local msg = Utils.safe_tostring(err)
    local clk = Utils.gate_now("staging_error_log_cooldown")
    if clk > _upd_err_cd or msg ~= _upd_err_last then
      print("[neuro-game] staging update error: " .. msg)
      _upd_err_last = msg
      _upd_err_cd = clk + 5
    end
    debug_mark("update panic", err)
    local victim = staged
    if victim then
      local ok_cancel = pcall(cancel_staged, "Action cancelled: staging runtime error")
      if not ok_cancel and staged == victim then
        staged = nil
        local vid = msg_action_id(victim.msg)
        if vid then pending_ids[vid] = nil end
      end
    end
    executing = nil
  end
end

function Staging.is_busy()
  if staged then return true end
  if now() < post_until then return true end
  return false
end

function Staging.on_state_change()
  if staged then
    cancel_staged("Action cancelled: state transition")
  end
end

function Staging.on_reconnect()
  if staged then
    cancel_staged("Action cancelled: reconnected")
  end
end

function Staging.mark_settled(action_id, ok)
  if action_id == nil then return end
  pending_ids[tostring(action_id)] = nil
  if G and G.NEURO then
    ForceState.set_action_phase(ok and "resolved" or "failed")
  end
  if ok then debug_mark("resolved") else debug_mark("failed", "action result failed") end
end

function Staging.get_debug_lines()
  if not DEBUG_STAGING() then return {} end

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

function Staging.reset_run_state()
  if staged then
    pcall(cancel_staged, "Action cancelled: run state reset")
    if staged then
      pcall(clear_hovers, staged.hover_cards)
      staged = nil
    end
  end
  post_until = 0
  _upd_err_cd, _upd_err_last = 0, nil
  glow_release = nil
  pending_ids = {}
  _preflight_error_seen = {}
  debug_state = {
    last_fault = nil, last_fault_at = 0,
    last_event = nil, last_event_at = 0,
  }
end

local function staged_hover_count() return staged and staged.hover_cards and #staged.hover_cards or 0 end

if rawget(_G, "NEURO_TEST") then
  Staging._test = { set_validator = set_validator, staged_hover_count = staged_hover_count }
  Staging._hover_card = hover_card
  Staging._unhover_card = unhover_card
  Staging._juice_target_settled = juice_target_settled
end

return Staging
